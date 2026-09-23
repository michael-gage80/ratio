// Hourly news ingestion (PRD: "Pulled from RSS every hour by a Cloud Function") into
// news/{id}: headline, source, date, link and module tags. "Why it matters" notes and
// the Sunday quiz are added by hand (content-tools/news-admin.mjs).

import { createHash } from "node:crypto";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { dedupe, modulesFor, NewsItem, parseFeed, SOURCES } from "./news.js";

const DAY_MS = 24 * 60 * 60 * 1000;
/** The news centre shows the last 7 days (PRD); older items are kept a while for quizzes. */
const WINDOW_DAYS = 7;
const KEEP_DAYS = 45;

async function fetchSource(source: (typeof SOURCES)[number]): Promise<NewsItem[]> {
  try {
    const response = await fetch(source.url, {
      headers: { "User-Agent": "Ratio legal news (educational app; headlines and links only)" },
      signal: AbortSignal.timeout(10_000),
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    return parseFeed(await response.text(), source);
  } catch (error) {
    logger.warn("Feed failed", { source: source.id, error: String(error) });
    return [];
  }
}

export const ingestNews = onSchedule({ schedule: "every 60 minutes", timeZone: "Europe/London", timeoutSeconds: 120 }, async () => {
  const db = getFirestore();
  const now = Date.now();
  const fetched = (await Promise.all(SOURCES.map(fetchSource)))
    .flat()
    .filter((i) => i.publishedAt.getTime() > now - WINDOW_DAYS * DAY_MS && i.publishedAt.getTime() < now + DAY_MS);

  // Compare against what's already stored, so a story first seen from one source isn't
  // added again when another source carries it.
  const recent = await db.collection("news").where("publishedAt", ">", Timestamp.fromMillis(now - (WINDOW_DAYS + 1) * DAY_MS)).select("url", "title").get();
  const existing = recent.docs.map((d) => ({ url: d.get("url") as string, title: d.get("title") as string }));
  // Sources are listed in order of preference (the court itself first), newest first within each.
  const order = new Map(SOURCES.map((s, i) => [s.id, i]));
  const fresh = dedupe(
    fetched.sort((a, b) => order.get(a.sourceId)! - order.get(b.sourceId)! || b.publishedAt.getTime() - a.publishedAt.getTime()),
    existing,
  );

  const batch = db.batch();
  for (const item of fresh) {
    const id = createHash("sha1").update(item.url).digest("hex").slice(0, 20);
    batch.set(db.doc(`news/${id}`), {
      sourceId: item.sourceId,
      source: item.source,
      title: item.title,
      url: item.url,
      publishedAt: Timestamp.fromDate(item.publishedAt),
      modules: modulesFor(item.title),
      ingestedAt: FieldValue.serverTimestamp(),
    }, { merge: true }); // Never touches a hand-written whyItMatters.
  }
  const stale = await db.collection("news").where("publishedAt", "<", Timestamp.fromMillis(now - KEEP_DAYS * DAY_MS)).limit(200).get();
  stale.docs.forEach((d) => batch.delete(d.ref));
  if (fresh.length || stale.size) await batch.commit();
  logger.info("News ingested", { fetched: fetched.length, added: fresh.length, removed: stale.size });
});
