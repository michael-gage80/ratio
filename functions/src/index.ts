import "./setup.js";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { isAcceptable, SafeSearch } from "./avatar.js";
import { Brief, buildBrief, londonDate } from "./brief.js";
import { duelLessons, HISTORY_LIMIT, lessonInfo, lessons, MODULES, testItems, TopicScores } from "./content.js";
import { Answer, DuelQuestion, matchQuestions, playMatch, questionPool, SPARRING_LEVELS, SPARRING_RD, sparringPlan } from "./duel.js";
import { dueDate, review } from "./fsrs.js";
import { INITIAL } from "./glicko.js";
import { countDuel } from "./account.js";
import { studyModules } from "./entitlement.js";
import { readSide, Side, StoredRating, writeSide } from "./settle.js";
import { BankItem, Estimate, Headline, isCorrect, ItemResponse, priorHeadline, scoreResponses, SKILLS, TopicEstimates } from "./scoring.js";


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

// MARK: - Lesson tests and practice

/** Reviews at least this far apart count towards delayed retention (PRD north star). */
const DELAYED_DAYS = 7;
const DAY_MS = 24 * 60 * 60 * 1000;

interface AttemptResult {
  results: { itemId: string; correct: boolean }[];
  topicsBefore: Record<string, TopicScores>;
  topicsAfter: Record<string, TopicScores>;
  headline: Headline;
  /** When each item comes back for review (ISO 8601). */
  reviews: { itemId: string; dueAt: string }[];
}

interface Delayed {
  total: number;
  correct: number;
}

/**
 * Re-grades answers to test items, updates each topic's θ/σ (with a history snapshot)
 * and the headline, schedules every item with FSRS, and records the attempt at
 * users/{uid}/testAttempts/{attemptId} with `record` merged in. Idempotent per attempt:
 * a retried call returns what the first one stored.
 */
async function scoreAttempt(
  uid: string,
  attemptId: string,
  responses: ItemResponse[],
  record: Record<string, unknown>,
  toStored: (result: AttemptResult) => unknown,
): Promise<unknown> {
  const db = getFirestore();
  const userRef = db.doc(`users/${uid}`);
  const attemptRef = userRef.collection("testAttempts").doc(attemptId);
  const entries = responses.map((r) => testItems.get(r.itemId)!);
  const topicIds = [...new Set(entries.map((e) => e.item.topicId))];
  const skillsRefs = topicIds.map((id) => userRef.collection("skills").doc(id));
  const itemRefs = responses.map((r) => userRef.collection("items").doc(r.itemId));
  const pool = new Map(entries.map((e) => [e.item.itemId, e.item]));

  return db.runTransaction(async (tx) => {
    const existing = await tx.get(attemptRef);
    if (existing.exists) return existing.get("result");

    const [user, ...rest] = await tx.getAll(userRef, ...skillsRefs, ...itemRefs);
    const skillDocs = rest.slice(0, skillsRefs.length);
    const itemStates = rest.slice(skillsRefs.length);
    const headlineBefore = (user.get("headline") as Headline | undefined) ?? priorHeadline();
    const topicsBefore: Record<string, TopicScores> = {};
    topicIds.forEach((topicId, i) => {
      topicsBefore[topicId] = {};
      for (const skill of SKILLS) {
        const estimate = skillDocs[i].get(skill) as Estimate | undefined;
        if (estimate) topicsBefore[topicId][skill] = estimate;
      }
    });

    const { topics: topicsAfter, headline } = scoreResponses(responses, pool, { topics: topicsBefore, headline: headlineBefore });

    const now = new Date();
    const results: AttemptResult["results"] = [];
    const reviews: AttemptResult["reviews"] = [];
    const delayed: Delayed = { total: 0, correct: 0 };
    responses.forEach((response, i) => {
      const { item, lessonId } = entries[i];
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
        lessonId,
        topicId: item.topicId,
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

    topicIds.forEach((topicId, i) => {
      const history = ((skillDocs[i].get("history") as unknown[] | undefined) ?? [])
        .concat({ at: Timestamp.fromDate(now), ...topicsAfter[topicId] })
        .slice(-HISTORY_LIMIT);
      tx.set(skillsRefs[i], { ...topicsAfter[topicId], history, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    });
    tx.update(userRef, { headline, headlineUpdatedAt: FieldValue.serverTimestamp() });
    const result = toStored({ results, topicsBefore, topicsAfter, headline, reviews });
    tx.set(attemptRef, {
      ...record,
      itemIds: responses.map((r) => r.itemId),
      result,
      delayed,
      createdAt: FieldValue.serverTimestamp(),
    });
    return result;
  });
}

const ATTEMPT_ID = /^[A-Za-z0-9-]{8,64}$/;

/** Checks the answers are unique and each is for one of `allowed`. */
function validateResponses(responses: unknown, allowed: Set<string>, max: number): ItemResponse[] {
  if (!Array.isArray(responses) || responses.length === 0 || responses.length > max) {
    throw new HttpsError("invalid-argument", "Unexpected number of answers.");
  }
  const itemIds = responses.map((r) => (r as ItemResponse)?.itemId);
  if (new Set(itemIds).size !== itemIds.length || itemIds.some((id) => typeof id !== "string" || !allowed.has(id) || !testItems.has(id))) {
    throw new HttpsError("invalid-argument", "An answer doesn't match the items served.");
  }
  return responses as ItemResponse[];
}

interface SubmitTestRequest {
  /** Chosen by the app per attempt, so a retried call returns the same result. */
  attemptId?: string;
  lessonId?: string;
  responses?: ItemResponse[];
}

interface SubmitTestResult {
  results: { itemId: string; correct: boolean }[];
  topicBefore: TopicScores;
  topicAfter: TopicScores;
  headline: Headline;
  reviews: { itemId: string; dueAt: string }[];
}

/**
 * Scores a lesson's tests (PRD: lesson stage 3) and schedules every item for spaced
 * review (PRD: "Every tested item enters the student's review queue after the
 * lesson, scheduled by FSRS"). Recorded with the lesson ID so retakes draw new items.
 */
export const submitTest = onCall<SubmitTestRequest>(async (request): Promise<SubmitTestResult> => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const { attemptId, lessonId, responses } = request.data ?? {};
  if (typeof attemptId !== "string" || !ATTEMPT_ID.test(attemptId)) throw new HttpsError("invalid-argument", "Missing attempt ID.");
  const lesson = typeof lessonId === "string" ? lessons.get(lessonId) : undefined;
  if (!lesson) throw new HttpsError("invalid-argument", "Unknown lesson.");
  const valid = validateResponses(responses, new Set(lesson.testPool.map((i) => i.itemId)), lesson.itemCounts.testServedPerAttempt);

  return scoreAttempt(uid, attemptId, valid, { kind: "test", lessonId: lesson.lessonId }, (r): SubmitTestResult => ({
    results: r.results,
    topicBefore: r.topicsBefore[lesson.topicId] ?? {},
    topicAfter: r.topicsAfter[lesson.topicId] ?? {},
    headline: r.headline,
    reviews: r.reviews,
  })) as Promise<SubmitTestResult>;
});

interface SubmitPracticeRequest {
  attemptId?: string;
  /** The brief and step the items were served for. */
  briefDate?: string;
  stepIndex?: number;
  responses?: ItemResponse[];
}

/**
 * Scores a daily-brief step — Drill, Build or Review. Only the items the brief chose
 * for that step are accepted. Answers count exactly like test answers: they move the
 * profile and reschedule each item.
 */
export const submitPractice = onCall<SubmitPracticeRequest>(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const { attemptId, briefDate, stepIndex, responses } = request.data ?? {};
  if (typeof attemptId !== "string" || !ATTEMPT_ID.test(attemptId)) throw new HttpsError("invalid-argument", "Missing attempt ID.");
  if (typeof briefDate !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(briefDate) || typeof stepIndex !== "number") {
    throw new HttpsError("invalid-argument", "Missing brief step.");
  }
  const brief = (await getFirestore().doc(`users/${uid}/briefs/${briefDate}`).get()).data() as Brief | undefined;
  const step = brief?.steps[stepIndex];
  if (!step || step.kind === "read") throw new HttpsError("invalid-argument", "Unknown brief step.");
  const valid = validateResponses(responses, new Set(step.itemIds), step.itemIds.length);

  return scoreAttempt(uid, attemptId, valid, { kind: step.kind, briefDate, stepIndex }, (r) => ({
    results: r.results,
    headline: r.headline,
    reviews: r.reviews,
  }));
});

// MARK: - Daily brief

/**
 * Builds and stores users/{uid}/briefs/{date} unless it already exists (a brief is
 * fixed for the day). Returns null for a student who hasn't finished onboarding, or
 * whose modules have no lessons yet.
 */
async function ensureBrief(uid: string, now: Date): Promise<Brief | null> {
  const db = getFirestore();
  const userRef = db.doc(`users/${uid}`);
  const date = londonDate(now);
  const briefRef = userRef.collection("briefs").doc(date);
  const existing = await briefRef.get();
  if (existing.exists) return existing.data() as Brief;

  const [user, skills, items, progress, earlier] = await Promise.all([
    userRef.get(),
    userRef.collection("skills").get(),
    userRef.collection("items").get(),
    userRef.collection("lessons").get(),
    userRef.collection("briefs").limit(1).get(),
  ]);
  const headline = user.get("headline") as Headline | undefined;
  const modules = user.get("modules") as string[] | undefined;
  if (!headline || !modules?.length) return null;

  const brief = buildBrief({
    date,
    now,
    // Free students' briefs stay within their free module (PRD: "Daily brief and spaced review: within the free module").
    modules: studyModules({ ...user.data(), modules: modules.map((m) => LEGACY_MODULE_IDS[m] ?? m) }),
    headline,
    topics: Object.fromEntries(skills.docs.map((d) => [d.id, d.data() as TopicScores])),
    lessons: lessonInfo,
    partsCompleted: Object.fromEntries(progress.docs.map((d) => [d.id, (d.get("partsCompleted") as number) ?? 0])),
    items: items.docs.map((d) => ({
      itemId: d.id,
      lessonId: d.get("lessonId"),
      topicId: d.get("topicId"),
      due: (d.get("due") as Timestamp).toDate(),
      lastReview: (d.get("lastReview") as Timestamp).toDate(),
      lastCorrect: d.get("lastCorrect") === true,
    })),
    firstBrief: earlier.empty,
  });
  if (!brief) return null;
  // create() fails if the nightly job and the app raced; either copy is fine.
  await briefRef.create({ ...brief, createdAt: FieldValue.serverTimestamp() }).catch(() => undefined);
  return ((await briefRef.get()).data() as Brief) ?? brief;
}

/** Today's brief, built on demand — day 1 straight after the diagnostic, or if the nightly job missed it. */
export const getBrief = onCall(async (request): Promise<{ brief: Brief | null }> => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  return { brief: await ensureBrief(uid, new Date()) };
});

/** Rebuilds every onboarded student's brief overnight (PRD: "rebuilt overnight at 03:00 UK time"). */
export const buildBriefs = onSchedule({ schedule: "0 3 * * *", timeZone: "Europe/London", timeoutSeconds: 540 }, async () => {
  const users = await getFirestore().collection("users").where("headline", "!=", null).select().get();
  const now = new Date();
  let failed = 0;
  for (const user of users.docs) {
    await ensureBrief(user.id, now).catch((error) => {
      failed += 1;
      logger.error("Couldn't build a brief", { uid: user.id, error: String(error) });
    });
  }
  logger.info("Built briefs", { students: users.size, failed });
});

// MARK: - Duels: sparring

interface StartSparringRequest {
  moduleId?: string;
  /** 1–5. */
  level?: number;
  /** 15 or 20 for extended time. */
  seconds?: number;
  /** The 3-question first-time practice duel: not stored, not rated. */
  tutorial?: boolean;
}


/**
 * Starts a match against a labelled sparring partner (PRD: "Sparring: bots in 5
 * difficulty bands ... always labelled"). The partner's answers are fixed now, on the
 * server; the student's are marked against the stored questions on submission.
 */
export const startSparring = onCall<StartSparringRequest>(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const { moduleId, level, seconds, tutorial } = request.data ?? {};
  if (typeof moduleId !== "string" || !MODULES.includes(moduleId)) throw new HttpsError("invalid-argument", "Unknown module.");
  if (!Number.isInteger(level) || level! < 1 || level! > 5) throw new HttpsError("invalid-argument", "Level must be 1–5.");
  const limitMs = (seconds === 15 || seconds === 20 ? seconds : 10) * 1000;

  const pool = questionPool(duelLessons.filter((l) => l.moduleId === moduleId), Math.random);
  if (tutorial !== true) await countDuel(uid);
  const questions = matchQuestions(pool, Math.random, tutorial === true);
  if (!questions) throw new HttpsError("failed-precondition", "This module doesn't have enough questions for a duel yet.");
  const plan = sparringPlan(questions, level!, limitMs, Math.random);
  const partner = { name: "Sparring partner", level, rating: SPARRING_LEVELS[level! - 1].rating };

  const db = getFirestore();
  const ratingDoc = await db.doc(`ratings/${uid}_${moduleId}`).get();
  const rating = ratingDoc.exists ? (ratingDoc.data() as StoredRating) : { ...INITIAL, duels: 0, wins: 0 };
  if (tutorial === true) return { matchId: null, questions, plan, partner, limitMs, rating };

  const matchRef = db.collection("matches").doc();
  await matchRef.set({
    players: [uid],
    mode: "sparring",
    isBot: true,
    moduleId,
    partner,
    limitMs,
    questions,
    plan,
    status: "active",
    createdAt: FieldValue.serverTimestamp(),
  });
  return { matchId: matchRef.id, questions, plan, partner, limitMs, rating };
});

interface SubmitSparringRequest {
  matchId?: string;
  /** The student's answer for each round played, in order. */
  answers?: Answer[];
}

/**
 * Referees a finished sparring match from the stored questions and plan: decides every
 * round, updates the Glicko-2 rating for the module, and moves the profile (PRD: duel
 * answers feed the profile, never the review queue). Idempotent.
 */
export const submitSparring = onCall<SubmitSparringRequest>(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const { matchId, answers } = request.data ?? {};
  if (typeof matchId !== "string" || !/^[A-Za-z0-9]{10,40}$/.test(matchId)) throw new HttpsError("invalid-argument", "Unknown match.");
  if (!Array.isArray(answers) || answers.length > 12) throw new HttpsError("invalid-argument", "Unexpected answers.");
  const clean: Answer[] = answers.map((a) => ({
    answerIndex: Number.isInteger(a?.answerIndex) ? a.answerIndex : null,
    timeMs: typeof a?.timeMs === "number" && Number.isFinite(a.timeMs) ? Math.round(a.timeMs) : Number.MAX_SAFE_INTEGER,
  }));

  const db = getFirestore();
  const matchRef = db.doc(`matches/${matchId}`);
  return db.runTransaction(async (tx) => {
    const match = await tx.get(matchRef);
    if (!match.exists || !(match.get("players") as string[]).includes(uid)) throw new HttpsError("not-found", "Unknown match.");
    if (match.get("status") === "complete") return match.get("result");

    const questions = match.get("questions") as DuelQuestion[];
    const moduleId = match.get("moduleId") as string;
    const partner = match.get("partner") as { rating: number };
    const outcome = playMatch(questions, clean, match.get("plan") as Answer[], match.get("limitMs") as number);

    const side: Side = {
      uid,
      moduleId,
      answers: outcome.rounds.map((round) => ({ question: questions[round.questionIndex], answer: round.answers[0] })),
    };
    const state = await readSide(tx, db, side);
    const score = outcome.winner === 0 ? 1 : outcome.winner === 1 ? 0 : 0.5;
    const settlement = writeSide(tx, state, { rating: partner.rating, rd: SPARRING_RD }, score);
    const result = { rounds: outcome.rounds, score: outcome.score, winner: outcome.winner, ...settlement };
    tx.update(matchRef, { status: "complete", result, completedAt: FieldValue.serverTimestamp() });
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

export * from "./multiplayer.js";
export * from "./newsIngest.js";
export * from "./account.js";
export * from "./purchases.js";
