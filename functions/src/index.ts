import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { isAcceptable, SafeSearch } from "./avatar.js";
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
  const now = Timestamp.now();
  for (const [topicId, skills] of Object.entries(topics)) {
    batch.set(userRef.collection("skills").doc(topicId), {
      ...skills,
      history: FieldValue.arrayUnion({ at: now, ...skills }),
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }
  batch.update(userRef, {
    headline,
    headlineUpdatedAt: FieldValue.serverTimestamp(),
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

/** Snapshots of a topic's scores kept for the Me tab's trend charts. */
const HISTORY_LIMIT = 100;
/** Reviews at least this far apart count towards delayed retention (PRD north star). */
const DELAYED_DAYS = 7;
const DAY_MS = 24 * 60 * 60 * 1000;

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

interface Delayed {
  total: number;
  correct: number;
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
    const delayed: Delayed = { total: 0, correct: 0 };
    responses.forEach((response, i) => {
      const item = pool.get(response.itemId)!;
      const correct = isCorrect(item, response);
      const state = itemStates[i];
      const previous = state.exists
        ? { stability: state.get("stability"), difficulty: state.get("difficulty"), lastReview: (state.get("lastReview") as Timestamp).toDate() }
        : undefined;
      if (previous && now.getTime() - previous.lastReview.getTime() >= DELAYED_DAYS * DAY_MS) {
        delayed.total += 1;
        delayed.correct += correct ? 1 : 0;
      }
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
    const history = ((skills.get("history") as unknown[] | undefined) ?? [])
      .concat({ at: Timestamp.fromDate(now), ...topicAfter })
      .slice(-HISTORY_LIMIT);
    tx.set(skillsRef, { ...topicAfter, history, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    tx.update(userRef, { headline, headlineUpdatedAt: FieldValue.serverTimestamp() });
    tx.set(attemptRef, { lessonId: lesson.lessonId, itemIds, result, delayed, createdAt: FieldValue.serverTimestamp() });
    return result;
  });
});

// MARK: - Avatars

// Loaded on first use so the other functions' cold starts don't pay for it.
let vision: import("@google-cloud/vision").ImageAnnotatorClient | undefined;
/** The app resizes photos to 512 px JPEGs, well under this. */
const MAX_AVATAR_BYTES = 1024 * 1024;

/**
 * Moderates the photo the app has just uploaded to avatars/{uid}/upload.jpg with
 * Cloud Vision SafeSearch. An accepted photo replaces avatars/{uid}/avatar.jpg, which
 * other students can see; a refused one is deleted. Either way the upload is removed,
 * and users/{uid}.avatarVersion changes only when a new photo goes live.
 */
export const moderateAvatar = onCall(async (request): Promise<{ approved: boolean }> => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");

  const bucket = getStorage().bucket();
  const upload = bucket.file(`avatars/${uid}/upload.jpg`);
  const [exists] = await upload.exists();
  if (!exists) throw new HttpsError("not-found", "Upload the photo first.");
  const [metadata] = await upload.getMetadata();
  if (metadata.contentType !== "image/jpeg" || Number(metadata.size) > MAX_AVATAR_BYTES) {
    await upload.delete();
    throw new HttpsError("invalid-argument", "Expected a JPEG under 1 MB.");
  }

  const [content] = await upload.download();
  vision ??= new (await import("@google-cloud/vision")).ImageAnnotatorClient();
  const [annotation] = await vision.safeSearchDetection({ image: { content } });
  const approved = isAcceptable(annotation.safeSearchAnnotation as SafeSearch | null | undefined);

  if (approved) {
    await upload.move(`avatars/${uid}/avatar.jpg`);
    await getFirestore().doc(`users/${uid}`).update({ avatarVersion: Date.now() });
  } else {
    await upload.delete();
  }
  return { approved };
});
