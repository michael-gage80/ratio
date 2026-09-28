// Case of the week on Today: one case a week from the student's own study modules,
// recalled from its facts before the ratio is revealed. "Didn't know it" turns the case
// into a review item (a case recall) that comes back in the brief's Review step on the
// same schedule as any other item. Stored at users/{uid}/caseWeeks/{monday}.

import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { londonDate } from "./brief.js";
import { CaseEntry, cases } from "./content.js";
import { everyoneHasPlus, studyModules } from "./entitlement.js";
import { dueDate, review } from "./fsrs.js";

// Early test profiles stored these before module IDs were aligned with the content.
const LEGACY_MODULE_IDS: Record<string, string> = { "public-law": "public", "land-law": "land", "equity-trusts": "equity" };

/** The UK date (yyyy-mm-dd) of the Monday starting `now`'s week: the case changes at 00:00 UK time on Monday. */
export function weekKey(now: Date): string {
  const today = new Date(`${londonDate(now)}T00:00:00Z`);
  const sinceMonday = (today.getUTCDay() + 6) % 7;
  return new Date(today.getTime() - sinceMonday * 86_400_000).toISOString().slice(0, 10);
}

function hash(seed: string): number {
  let h = 2166136261;
  for (let i = 0; i < seed.length; i++) h = Math.imul(h ^ seed.charCodeAt(i), 16777619);
  return h >>> 0;
}

/**
 * The week's case: never one already featured until the student has had them all, and
 * from a lesson they've started when there is one. Stable for a student and week.
 */
export function pickCase(pool: CaseEntry[], started: Set<string>, seen: Set<string>, seed: string): CaseEntry | null {
  if (pool.length === 0) return null;
  const fresh = pool.filter((c) => !seen.has(c.itemId));
  const candidates = fresh.length > 0 ? fresh : pool;
  const met = candidates.filter((c) => c.lessonIds.some((id) => started.has(id)));
  const from = (met.length > 0 ? met : candidates).sort((a, b) => a.itemId.localeCompare(b.itemId));
  return from[hash(seed) % from.length];
}

export interface CaseWeek {
  week: string;
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

/** This week's case, chosen on first ask. Null when the student's modules have no cases. */
export const getCaseOfWeek = onCall(async (request): Promise<{ caseWeek: CaseWeek | null }> => {
  const uid = requireAuth(request.auth?.uid);
  const db = getFirestore();
  const userRef = db.doc(`users/${uid}`);
  const week = weekKey(new Date());
  const ref = userRef.collection("caseWeeks").doc(week);
  const existing = await ref.get();
  if (existing.exists) return { caseWeek: existing.data() as CaseWeek };

  const [user, progress, items, earlier] = await Promise.all([
    userRef.get(),
    userRef.collection("lessons").get(),
    userRef.collection("items").select("lessonId").get(),
    userRef.collection("caseWeeks").select("caseId").get(),
  ]);
  const modules = ((user.get("modules") as string[] | undefined) ?? []).map((m) => LEGACY_MODULE_IDS[m] ?? m);
  const allowed = new Set(studyModules({ ...user.data(), modules }, await everyoneHasPlus()));
  const started = new Set([
    ...progress.docs.filter((d) => ((d.get("partsCompleted") as number | undefined) ?? 0) > 0).map((d) => d.id),
    ...items.docs.filter((d) => !d.id.startsWith("case-")).map((d) => d.get("lessonId") as string),
  ]);
  const seen = new Set(earlier.docs.map((d) => d.get("caseId") as string));
  const pool = [...cases.values()].filter((c) => allowed.has(c.moduleId));
  const chosen = pickCase(pool, started, seen, `${uid}:${week}`);
  if (!chosen) return { caseWeek: null };

  const caseWeek: CaseWeek = {
    week,
    caseId: chosen.itemId,
    lessonId: chosen.lessonIds.find((id) => started.has(id)) ?? chosen.lessonId,
    moduleId: chosen.moduleId,
    result: null,
  };
  // create() fails if two devices raced; either copy is fine.
  await ref.create({ ...caseWeek, createdAt: FieldValue.serverTimestamp() }).catch(() => undefined);
  return { caseWeek: ((await ref.get()).data() as CaseWeek) ?? caseWeek };
});

interface RateRequest {
  week?: string;
  knew?: boolean;
}

/**
 * "Knew it" or "Didn't know it" on the card, once per week. A miss schedules the case
 * as a review item (FSRS, rated Again), so it comes back in a brief tomorrow.
 */
export const rateCaseOfWeek = onCall<RateRequest>(async (request): Promise<{ caseWeek: CaseWeek }> => {
  const uid = requireAuth(request.auth?.uid);
  const { week, knew } = request.data ?? {};
  if (typeof week !== "string" || typeof knew !== "boolean") throw new HttpsError("invalid-argument", "Missing rating.");
  const db = getFirestore();
  const userRef = db.doc(`users/${uid}`);
  const ref = userRef.collection("caseWeeks").doc(week);
  return db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists) throw new HttpsError("not-found", "That week's case has gone.");
    const caseWeek = doc.data() as CaseWeek;
    if (caseWeek.result) return { caseWeek };
    const entry = cases.get(caseWeek.caseId);
    const itemRef = userRef.collection("items").doc(caseWeek.caseId);
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
    return { caseWeek: { ...caseWeek, result } };
  });
});
