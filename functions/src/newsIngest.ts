// Hourly news ingestion (PRD: "Pulled from RSS every hour by a Cloud Function") into
// news/{id}: headline, source, date, link and module tags; whether it's subscriber-only;
// and, for sources whose full-text switch is on, the in-app reader's text (reader.ts).
// "Why it matters" notes and the Sunday quiz are added by hand (content-tools/admin.mjs).

import { createHash } from "node:crypto";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { londonDate } from "./brief.js";
import { dedupe, modulesFor, NewsItem, parseFeed, Source, SOURCES } from "./news.js";
import { buildReader, checkPaywall } from "./reader.js";

const DAY_MS = 24 * 60 * 60 * 1000;
/** The news centre shows the last 7 days (PRD); older items are kept a while for quizzes. */
const WINDOW_DAYS = 7;
const KEEP_DAYS = 45;
/** Stories whose text isn't ready yet (an Act's notes) are tried again at most this often. */
const RETRY_MS = 6 * 60 * 60 * 1000;

async function fetchSource(source: Source): Promise<NewsItem[]> {
  try {
    const response = await fetch(source.url, {
      headers: { "User-Agent": "Ratio legal news (educational app for UK law students)" },
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return parseFeed(await response.text(), source);
  } catch (error) {
    logger.warn("Feed failed", { source: source.id, error: String(error) });
    return [];
  }
}

export const storyId = (url: string) => createHash("sha1").update(url).digest("hex").slice(0, 20);

/**
 * config/news: { fullText: { sourceId: bool }, images: { sourceId: bool } } — overrides
 * each source's default, so a publisher's switch can go on once they've agreed, with no
 * deploy. Images are off unless switched on: a text licence doesn't always cover photos.
 */
export interface NewsConfig {
  fullText: (source: Source) => boolean;
  images: (source: Source) => boolean;
}

async function newsConfig(): Promise<NewsConfig> {
  const doc = await getFirestore().doc("config/news").get();
  const fullText = (doc.get("fullText") ?? {}) as Record<string, boolean>;
  const images = (doc.get("images") ?? {}) as Record<string, boolean>;
  return {
    fullText: (source) => fullText[source.id] ?? source.fullText,
    images: (source) => images[source.id] ?? false,
  };
}

/** High-volume feeds keep their best few a day: most module matches, then newest. */
export function capped(items: NewsItem[], usedToday: Record<string, number>): NewsItem[] {
  const bySource = new Map(SOURCES.map((s) => [s.id, s]));
  const counts = { ...usedToday };
  const ranked = [...items].sort((a, b) =>
    modulesFor(b.title).length - modulesFor(a.title).length || b.publishedAt.getTime() - a.publishedAt.getTime());
  const kept = new Set<NewsItem>();
  for (const item of ranked) {
    const limit = bySource.get(item.sourceId)?.perDay;
    if (limit !== undefined) {
      if ((counts[item.sourceId] ?? 0) >= limit) continue;
      counts[item.sourceId] = (counts[item.sourceId] ?? 0) + 1;
    }
    kept.add(item);
  }
  return items.filter((i) => kept.has(i));
}

/** Runs `work` over `items`, a few at a time. */
async function inBatches<T>(items: T[], size: number, work: (item: T) => Promise<void>): Promise<void> {
  for (let i = 0; i < items.length; i += size) await Promise.all(items.slice(i, i + size).map(work));
}

export const ingestNews = onSchedule({ schedule: "every 60 minutes", timeZone: "Europe/London", timeoutSeconds: 300, memory: "512MiB" }, async () => {
  const db = getFirestore();
  const now = Date.now();
  const config = await newsConfig();
  const fetched = (await Promise.all(SOURCES.map(fetchSource)))
    .flat()
    .filter((i) => i.publishedAt.getTime() > now - WINDOW_DAYS * DAY_MS && i.publishedAt.getTime() < now + DAY_MS);

  // Compare against what's already stored, so a story first seen from one source isn't
  // added again when another source carries it.
  const recent = await db.collection("news").where("publishedAt", ">", Timestamp.fromMillis(now - (WINDOW_DAYS + 1) * DAY_MS)).select("url", "title").get();
  const existing = recent.docs.map((d) => ({ url: d.get("url") as string, title: d.get("title") as string }));
  // Sources are listed in order of preference (the court itself first), newest first within each.
  const order = new Map(SOURCES.map((s, i) => [s.id, i]));
  const unique = dedupe(
    fetched.sort((a, b) => order.get(a.sourceId)! - order.get(b.sourceId)! || b.publishedAt.getTime() - a.publishedAt.getTime()),
    existing,
  );
  const dailyRef = db.doc(`newsDaily/${londonDate(new Date(now))}`);
  const usedToday = ((await dailyRef.get()).data() ?? {}) as Record<string, number>;
  const fresh = capped(unique, usedToday);

  const bySource = new Map(SOURCES.map((s) => [s.id, s]));
  const batch = db.batch();
  const added: Record<string, number> = {};
  for (const item of fresh) {
    const source = bySource.get(item.sourceId)!;
    added[item.sourceId] = (added[item.sourceId] ?? 0) + 1;
    batch.set(db.doc(`news/${storyId(item.url)}`), {
      sourceId: item.sourceId,
      source: item.source,
      title: item.title,
      url: item.url,
      publishedAt: Timestamp.fromDate(item.publishedAt),
      modules: modulesFor(item.title),
      paywalled: source.paywall === "always",
      readerStatus: config.fullText(source) ? "pending" : "off",
      ingestedAt: FieldValue.serverTimestamp(),
    }, { merge: true }); // Never touches a hand-written whyItMatters.
  }
  if (Object.keys(added).length) {
    batch.set(dailyRef, Object.fromEntries(Object.entries(added).map(([id, n]) => [id, FieldValue.increment(n)])), { merge: true });
  }

  const stale = await db.collection("news").where("publishedAt", "<", Timestamp.fromMillis(now - KEEP_DAYS * DAY_MS)).limit(200).get();
  stale.docs.forEach((d) => batch.delete(d.ref));
  if (fresh.length || stale.size) await batch.commit();
  await inBatches(stale.docs, 10, (d) => getStorage().bucket().deleteFiles({ prefix: `news/${d.id}/` }).catch(() => undefined));

  // Subscriber-only checks for publishers that paywall some articles.
  await inBatches(fresh.filter((i) => bySource.get(i.sourceId)!.paywall === "check"), 4, async (item) => {
    if (await checkPaywall(item.url, bySource.get(item.sourceId)!)) await db.doc(`news/${storyId(item.url)}`).update({ paywalled: true });
  });

  // The reader's text: new stories, stories still waiting (an Act's notes), and recent
  // stories from a source whose switch has just been turned on.
  const waiting = await db.collection("news")
    .where("readerStatus", "in", ["pending", "off"])
    .where("publishedAt", ">", Timestamp.fromMillis(now - WINDOW_DAYS * DAY_MS))
    .limit(300).get();
  const isNew = new Set(fresh.map((i) => storyId(i.url)));
  // A "feed" story's text is its feed item, so it's read from this run's feeds.
  const html = new Map(fetched.filter((i) => i.html).map((i) => [storyId(i.url), i.html]));
  const due = waiting.docs.filter((d) => {
    const source = bySource.get(d.get("sourceId") as string);
    if (!source || !config.fullText(source) || d.get("paywalled") === true) return false;
    const checked = (d.get("readerCheckedAt") as Timestamp | undefined)?.toMillis() ?? 0;
    return isNew.has(d.id) || now - checked >= RETRY_MS;
  }).slice(0, 80);
  let built = 0;
  await inBatches(due, 4, async (d) => {
    const source = bySource.get(d.get("sourceId") as string)!;
    const result = await buildReader({ id: d.id, title: d.get("title"), url: d.get("url"), html: html.get(d.id) }, source, config.images(source));
    if (result.status === "done") built += 1;
    await d.ref.update({
      readerStatus: result.status,
      readerCheckedAt: FieldValue.serverTimestamp(),
      ...(result.status === "done" ? { reader: result.reader } : {}),
    });
  });
  logger.info("News ingested", { fetched: fetched.length, added: fresh.length, removed: stale.size, readers: built, readerTried: due.length });
});
