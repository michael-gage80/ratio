import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { dueDate, review } from "./fsrs.js";
import { BankItem, Estimate, Headline, isCorrect, ItemResponse, priorHeadline, scoreResponses, Skill, SKILLS, TopicEstimates } from "./scoring.js";

initializeApp();
setGlobalOptions({ region: "europe-west2", maxInstances: 10 });

// The same bank the app bundles, copied into lib/ at build time, so answers are
// re-graded here rather than trusted from the client.
const bank = JSON.parse(readFileSync(join(__dirname, "diagnostic-bank.json"), "utf8")) as {
  totalItemsServedPerAttempt: number;
  modules: Record<string, { items: BankItem[] }>;
};
const moduleOfItem = new Map<string, string>();
const itemsById = new Map<string, BankItem>();
for (const [moduleId, { items }] of Object.entries(bank.modules)) {
  for (const item of items) {
    itemsById.set(item.itemId, item);
    moduleOfItem.set(item.itemId, moduleId);
  }
}

// Early test profiles stored these before module IDs were aligned with the content.
const LEGACY_MODULE_IDS: Record<string, string> = { "public-law": "public", "land-law": "land", "equity-trusts": "equity" };

interface SubmitDiagnosticRequest {
  skipped?: boolean;
  responses?: ItemResponse[];
}

/**
 * Scores the onboarding diagnostic and writes the student's first profile:
 * users/{uid}/skills/{topicId} for each topic answered, and the headline estimate on
 * users/{uid}. Skipping gives every skill the widest band (diagnostic bank:
 * skippedProfileNote). Idempotent — a completed diagnostic can't be retaken.
 */
export const submitDiagnostic = onCall<SubmitDiagnosticRequest>(async (request): Promise<{ headline: Headline }> => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");

  const db = getFirestore();
  const userRef = db.doc(`users/${uid}`);
  const user = (await userRef.get()).data();
  if (!user?.birthYear || !Array.isArray(user.modules) || user.modules.length === 0) {
    throw new HttpsError("failed-precondition", "Finish the earlier onboarding steps first.");
  }
  if (user.headline) return { headline: user.headline as Headline };

  const skipped = request.data?.skipped === true;
  let topics: TopicEstimates = {};
  let headline = priorHeadline();

  if (!skipped) {
    const responses = validate(request.data?.responses, user.modules as string[]);
    ({ topics, headline } = scoreResponses(responses, itemsById));
  }

  const batch = db.batch();
  for (const [topicId, skills] of Object.entries(topics)) {
    batch.set(userRef.collection("skills").doc(topicId), { ...skills, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  }
  batch.update(userRef, {
    headline,
    diagnosticSkipped: skipped,
    diagnosticCompletedAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return { headline };
});

function validate(raw: unknown, modules: string[]): ItemResponse[] {
  const allowed = new Set(modules.map((m) => LEGACY_MODULE_IDS[m] ?? m));
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > bank.totalItemsServedPerAttempt) {
    throw new HttpsError("invalid-argument", "Expected between 1 and 10 responses.");
  }
  const seen = new Set<string>();
  return raw.map((r) => {
    const response = r as ItemResponse;
    const moduleId = typeof response?.itemId === "string" ? moduleOfItem.get(response.itemId) : undefined;
    if (!moduleId || !allowed.has(moduleId) || seen.has(response.itemId)) {
      throw new HttpsError("invalid-argument", "A response doesn't match an item for your modules.");
    }
    seen.add(response.itemId);
    return response;
  });
}

// MARK: - Lesson tests

interface Lesson {
  lessonId: string;
  topicId: string;
  itemCounts: { testServedPerAttempt: number };
  testPool: BankItem[];
}

// The same lessons the app bundles, copied into lib/lessons at build time.
const lessons = new Map<string, Lesson>(
  readdirSync(join(__dirname, "lessons"))
    .filter((f) => f.endsWith(".json"))
    .map((f) => JSON.parse(readFileSync(join(__dirname, "lessons", f), "utf8")) as Lesson)
    .map((lesson) => [lesson.lessonId, lesson]),
);

interface SubmitTestRequest {
  /** Chosen by the app per attempt, so a retried call returns the same result. */
  attemptId?: string;
  lessonId?: string;
  responses?: ItemResponse[];
}

interface SubmitTestResult {
  results: { itemId: string; correct: boolean }[];
  topicBefore: Partial<Record<Skill, Estimate>>;
  topicAfter: Partial<Record<Skill, Estimate>>;
  headline: Headline;
  /** When each item comes back for review (ISO 8601). */
  reviews: { itemId: string; dueAt: string }[];
}

/**
 * Scores a lesson's tests (PRD: lesson stage 3) and schedules every item for spaced
 * review (PRD: "Every tested item enters the student's review queue after the
 * lesson, scheduled by FSRS"). Re-grades against the lesson content, updates the
 * topic's θ/σ and the headline, writes users/{uid}/items/{itemId} with its memory
 * state, and records the attempt (so retakes draw new items). Idempotent per attempt.
 */
export const submitTest = onCall<SubmitTestRequest>(async (request): Promise<SubmitTestResult> => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const { attemptId, lessonId, responses } = request.data ?? {};
  if (typeof attemptId !== "string" || !/^[A-Za-z0-9-]{8,64}$/.test(attemptId)) {
    throw new HttpsError("invalid-argument", "Missing attempt ID.");
  }
  const lesson = typeof lessonId === "string" ? lessons.get(lessonId) : undefined;
  if (!lesson) throw new HttpsError("invalid-argument", "Unknown lesson.");

  const pool = new Map(lesson.testPool.map((item) => [item.itemId, { ...item, topicId: lesson.topicId }]));
  if (!Array.isArray(responses) || responses.length === 0 || responses.length > lesson.itemCounts.testServedPerAttempt) {
    throw new HttpsError("invalid-argument", "Unexpected number of answers.");
  }
  const itemIds = responses.map((r) => r?.itemId);
  if (new Set(itemIds).size !== itemIds.length || itemIds.some((id) => typeof id !== "string" || !pool.has(id))) {
    throw new HttpsError("invalid-argument", "An answer doesn't match this lesson's test items.");
  }

  const db = getFirestore();
  const userRef = db.doc(`users/${uid}`);
  const attemptRef = userRef.collection("testAttempts").doc(attemptId);
  const skillsRef = userRef.collection("skills").doc(lesson.topicId);
  const itemRefs = itemIds.map((id) => userRef.collection("items").doc(id));

  return db.runTransaction(async (tx) => {
    const existing = await tx.get(attemptRef);
    if (existing.exists) return existing.get("result") as SubmitTestResult;

    const [user, skills, ...itemStates] = await tx.getAll(userRef, skillsRef, ...itemRefs);
    const headlineBefore = (user.get("headline") as Headline | undefined) ?? priorHeadline();
    const topicBefore: Partial<Record<Skill, Estimate>> = {};
    for (const skill of SKILLS) {
      const estimate = skills.get(skill) as Estimate | undefined;
      if (estimate) topicBefore[skill] = estimate;
    }

    const { topics, headline } = scoreResponses(responses, pool, {
      topics: { [lesson.topicId]: topicBefore },
      headline: headlineBefore,
    });
    const topicAfter = topics[lesson.topicId] ?? {};

    const now = new Date();
    const results: SubmitTestResult["results"] = [];
    const reviews: SubmitTestResult["reviews"] = [];
    responses.forEach((response, i) => {
      const item = pool.get(response.itemId)!;
      const correct = isCorrect(item, response);
      const state = itemStates[i];
      const previous = state.exists
        ? { stability: state.get("stability"), difficulty: state.get("difficulty"), lastReview: (state.get("lastReview") as Timestamp).toDate() }
        : undefined;
      const next = review(previous, correct ? 3 : 1, now);
      const due = dueDate(next);
      tx.set(itemRefs[i], {
        lessonId: lesson.lessonId,
        topicId: lesson.topicId,
        skill: item.skillTag,
        stability: next.stability,
        difficulty: next.difficulty,
        lastReview: Timestamp.fromDate(now),
        due: Timestamp.fromDate(due),
        lastCorrect: correct,
        reps: FieldValue.increment(1),
        lapses: FieldValue.increment(correct ? 0 : 1),
      }, { merge: true });
      results.push({ itemId: item.itemId, correct });
      reviews.push({ itemId: item.itemId, dueAt: due.toISOString() });
    });

    const result: SubmitTestResult = { results, topicBefore, topicAfter, headline, reviews };
    tx.set(skillsRef, { ...topicAfter, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    tx.update(userRef, { headline });
    tx.set(attemptRef, { lessonId: lesson.lessonId, itemIds, result, createdAt: FieldValue.serverTimestamp() });
    return result;
  });
});
