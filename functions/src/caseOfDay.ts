// Case of the day on Today: one case a day from the student's own study modules,
// recalled from its facts before the ratio is revealed. "Didn't know it" turns the case
// into a review item (a case recall) that comes back in the brief on the same schedule
// as any other item. Stored at users/{uid}/caseDays/{yyyy-mm-dd}; the next week's cases
// are chosen in advance so the opt-in reminder can name each day's case.

import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { londonDate } from "./brief.js";
import { CaseEntry, cases } from "./content.js";
import { everyoneHasPlus, studyModules } from "./entitlement.js";
import { dueDate, review } from "./fsrs.js";

// Early test profiles stored these before module IDs were aligned with the content.
const LEGACY_MODULE_IDS: Record<string, string> = { "public-law": "public", "land-law": "land", "equity-trusts": "equity" };

/** Today and the six days after it are always chosen. */
const DAYS_AHEAD = 7;

/** The UK date `days` after `date` (both yyyy-mm-dd). */
export function addDays(date: string, days: number): string {
  return new Date(Date.parse(`${date}T00:00:00Z`) + days * 86_400_000).toISOString().slice(0, 10);
}

function hash(seed: string): number {
  let h = 2166136261;
  for (let i = 0; i < seed.length; i++) h = Math.imul(h ^ seed.charCodeAt(i), 16777619);
  return h >>> 0;
}

export interface PickInput {
  /** Every case in the student's study modules. */
  pool: CaseEntry[];
  /** Lessons the student has started. */
  started: Set<string>;
  /** Cases rated, with when they were last rated (ms). Only rated cases count as used. */
  rated: Map<string, number>;
  /** Cases already chosen for other upcoming days, so a week has no repeats. */
  upcoming: Set<string>;
  date: string;
  seed: string;
}

/**
 * The day's case. First every unrated case from a lesson the student has started. Once
 * those are all rated, alternate by day: a case they've met again (the one rated
 * longest ago), then a preview from a lesson they haven't started.
 */
export function pickCase({ pool, started, rated, upcoming, date, seed }: PickInput): CaseEntry | null {
  const open = pool.filter((c) => !upcoming.has(c.itemId));
  if (open.length === 0) return null;
  const sorted = (list: CaseEntry[]) => [...list].sort((a, b) => a.itemId.localeCompare(b.itemId));
  const choose = (list: CaseEntry[]) => sorted(list)[hash(`${seed}:${date}`) % list.length];
  const isMet = (c: CaseEntry) => c.lessonIds.some((id) => started.has(id));
  const met = open.filter(isMet);
  const previews = open.filter((c) => !isMet(c));

  const unratedMet = met.filter((c) => !rated.has(c.itemId));
  if (unratedMet.length > 0) return choose(unratedMet);

  const unratedPreviews = previews.filter((c) => !rated.has(c.itemId));
  const repeat = [...met].sort((a, b) => (rated.get(a.itemId) ?? 0) - (rated.get(b.itemId) ?? 0) || a.itemId.localeCompare(b.itemId))[0];
  const preview = unratedPreviews.length > 0 ? choose(unratedPreviews) : undefined;
  const repeatDay = Math.floor(Date.parse(`${date}T00:00:00Z`) / 86_400_000) % 2 === 0;
  if (repeatDay) return repeat ?? preview ?? choose(open);
  return preview ?? repeat ?? choose(open);
}

export interface CaseDay {
  date: string;
  caseId: string;
  /** The lesson the card links to: one the student has started, if any. */
  lessonId: string;
  moduleId: string;
  result: "knew" | "missed" | null;
}

function requireAuth(uid: string | undefined): string {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  return uid;
}

/** Today's case and the next six days', choosing any not yet chosen. Empty when the student's modules have no cases. */
export const getCaseOfDay = onCall(async (request): Promise<{ days: CaseDay[] }> => {
  const uid = requireAuth(request.auth?.uid);
  const db = getFirestore();
  const userRef = db.doc(`users/${uid}`);
  const today = londonDate(new Date());
  const dates = Array.from({ length: DAYS_AHEAD }, (_, i) => addDays(today, i));
  const refs = dates.map((d) => userRef.collection("caseDays").doc(d));
  const existing = await db.getAll(...refs);
  if (existing.every((d) => d.exists)) return { days: existing.map((d) => d.data() as CaseDay) };

  const [user, progress, items, earlier] = await Promise.all([
    userRef.get(),
    userRef.collection("lessons").get(),
    userRef.collection("items").select("lessonId").get(),
    userRef.collection("caseDays").where("result", "!=", null).select("caseId", "ratedAt").get(),
  ]);
  const modules = ((user.get("modules") as string[] | undefined) ?? []).map((m) => LEGACY_MODULE_IDS[m] ?? m);
  const allowed = new Set(studyModules({ ...user.data(), modules }, await everyoneHasPlus()));
  const started = new Set([
    ...progress.docs.filter((d) => ((d.get("partsCompleted") as number | undefined) ?? 0) > 0).map((d) => d.id),
    ...items.docs.filter((d) => !d.id.startsWith("case-")).map((d) => d.get("lessonId") as string),
  ]);
  const rated = new Map<string, number>();
  for (const d of earlier.docs) {
    const at = (d.get("ratedAt") as Timestamp | undefined)?.toMillis() ?? 0;
    rated.set(d.get("caseId") as string, Math.max(at, rated.get(d.get("caseId") as string) ?? 0));
  }
  const pool = [...cases.values()].filter((c) => allowed.has(c.moduleId));
  const upcoming = new Set(existing.filter((d) => d.exists).map((d) => d.get("caseId") as string));

  const days: CaseDay[] = [];
  for (const [i, snapshot] of existing.entries()) {
    if (snapshot.exists) {
      days.push(snapshot.data() as CaseDay);
      continue;
    }
    const chosen = pickCase({ pool, started, rated, upcoming, date: dates[i], seed: uid });
    if (!chosen) break;
    upcoming.add(chosen.itemId);
    const day: CaseDay = {
      date: dates[i],
      caseId: chosen.itemId,
      lessonId: chosen.lessonIds.find((id) => started.has(id)) ?? chosen.lessonId,
      moduleId: chosen.moduleId,
      result: null,
    };
    // create() fails if two devices raced; either copy is fine.
    await refs[i].create({ ...day, createdAt: FieldValue.serverTimestamp() }).catch(() => undefined);
    days.push(((await refs[i].get()).data() as CaseDay) ?? day);
  }
  return { days };
});

interface RateRequest {
  date?: string;
  knew?: boolean;
}

/**
 * "Knew it" or "Didn't know it" on today's card, once. A miss schedules the case as a
 * review item (FSRS, rated Again), so it comes back in a brief tomorrow.
 */
export const rateCaseOfDay = onCall<RateRequest>(async (request): Promise<{ day: CaseDay }> => {
  const uid = requireAuth(request.auth?.uid);
  const { date, knew } = request.data ?? {};
  if (typeof date !== "string" || typeof knew !== "boolean") throw new HttpsError("invalid-argument", "Missing rating.");
  // Just after midnight the app may still show yesterday's case; a day's grace.
  const today = londonDate(new Date());
  if (date !== today && date !== addDays(today, -1)) throw new HttpsError("failed-precondition", "Only today's case can be rated.");
  const db = getFirestore();
  const userRef = db.doc(`users/${uid}`);
  const ref = userRef.collection("caseDays").doc(date);
  return db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists) throw new HttpsError("not-found", "That day's case has gone.");
    const day = doc.data() as CaseDay;
    if (day.result) return { day };
    const entry = cases.get(day.caseId);
    const itemRef = userRef.collection("items").doc(day.caseId);
    const item = knew || !entry ? undefined : await tx.get(itemRef);
    const result = knew ? "knew" : "missed";
    tx.update(ref, { result, ratedAt: FieldValue.serverTimestamp() });
    if (entry && item) {
      const now = new Date();
      const previous = item.exists
        ? { stability: item.get("stability"), difficulty: item.get("difficulty"), lastReview: (item.get("lastReview") as Timestamp).toDate() }
        : undefined;
      const next = review(previous, 1, now);
      tx.set(itemRef, {
        lessonId: entry.lessonId,
        topicId: entry.topicId,
        skill: "knowledge",
        kind: "case",
        stability: next.stability,
        difficulty: next.difficulty,
        lastReview: Timestamp.fromDate(now),
        due: Timestamp.fromDate(dueDate(next)),
        lastCorrect: false,
        reps: FieldValue.increment(1),
        lapses: FieldValue.increment(1),
      }, { merge: true });
    }
    return { day: { ...day, result } };
  });
});
