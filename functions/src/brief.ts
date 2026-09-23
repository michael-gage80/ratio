// The daily brief (PRD: "Today screen and daily brief"): 2–4 steps from Read, Drill,
// Build and Review, weighted towards the weakest skill, folding in spaced-review items
// that have come due, interleaved across topics. Spar joins when duels do.

import { Estimate, Headline, Skill, SKILLS } from "./scoring.js";

export type StepKind = "read" | "drill" | "build" | "review";

export interface BriefStep {
  kind: StepKind;
  /** The lesson to read, for a Read step. */
  lessonId?: string;
  /** Items to answer, for the other steps. */
  itemIds: string[];
  minutes: number;
}

export interface Brief {
  /** The UK date it's for, yyyy-mm-dd. */
  date: string;
  lessonId: string;
  moduleId: string;
  topicId: string;
  title: string;
  minutes: number;
  reason: string;
  tutorNote: string | null;
  steps: BriefStep[];
}

export interface LessonInfo {
  lessonId: string;
  moduleId: string;
  moduleTitle: string;
  topicId: string;
  title: string;
  estimatedMinutes: number;
  lectureParts: number;
  testPool: { itemId: string; type: string; skillTag: Skill }[];
}

export interface ItemState {
  itemId: string;
  lessonId: string;
  topicId: string;
  due: Date;
  lastReview: Date;
  lastCorrect: boolean;
}

export interface BriefInput {
  date: string;
  now: Date;
  /** The student's modules, in their order. */
  modules: string[];
  headline: Headline;
  topics: Record<string, Partial<Record<Skill, Estimate>>>;
  /** Every lesson, in teaching order within each module. */
  lessons: LessonInfo[];
  partsCompleted: Record<string, number>;
  items: ItemState[];
  /** No brief has been built for this student before. */
  firstBrief: boolean;
}

const DRILL_ITEMS = 5;
const DRILL_ITEMS_AFTER_READ = 3;
const DRILL_REVIEWS = 2;
const REVIEW_CAP = 8;
/** "A student with many overdue items gets a longer Review." */
const LONG_REVIEW_CAP = 15;
const MANY_DUE = 15;
const TARGET_MINUTES = 20;
const HOUR = 60 * 60 * 1000;

const logistic = (x: number) => 1 / (1 + Math.exp(-x));
const phrase: Record<Skill, string> = { knowledge: "recall", understanding: "understanding", application: "application" };

/** The UK calendar date for `now`, yyyy-mm-dd. */
export const londonDate = (now: Date): string =>
  new Intl.DateTimeFormat("en-CA", { timeZone: "Europe/London", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);

/** A small deterministic PRNG so a brief is reproducible for a given student and day. */
function seeded(seed: string): () => number {
  let h = 1779033703 ^ seed.length;
  for (let i = 0; i < seed.length; i++) h = Math.imul(h ^ seed.charCodeAt(i), 3432918353);
  return () => {
    h = Math.imul(h ^ (h >>> 16), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    return ((h ^= h >>> 16) >>> 0) / 4294967296;
  };
}

function shuffled<T>(values: T[], random: () => number): T[] {
  const copy = [...values];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

/** Round-robin across topics so neighbouring reviews test different rules. */
export function interleave(items: ItemState[]): ItemState[] {
  const byTopic = new Map<string, ItemState[]>();
  for (const item of [...items].sort((a, b) => a.due.getTime() - b.due.getTime())) {
    byTopic.set(item.topicId, [...(byTopic.get(item.topicId) ?? []), item]);
  }
  const queues = [...byTopic.values()];
  const out: ItemState[] = [];
  while (queues.some((q) => q.length > 0)) {
    for (const queue of queues) {
      const next = queue.shift();
      if (next) out.push(next);
    }
  }
  return out;
}

type LessonState = "notStarted" | "inProgress" | "secure" | "needsReview";

function lessonState(lesson: LessonInfo, input: BriefInput): LessonState {
  const tested = input.items.filter((i) => i.lessonId === lesson.lessonId);
  if (tested.length > 0) return tested.some((i) => !i.lastCorrect || i.due <= input.now) ? "needsReview" : "secure";
  return (input.partsCompleted[lesson.lessonId] ?? 0) > 0 ? "inProgress" : "notStarted";
}

/** Returns null when none of the student's modules has lessons yet. */
export function buildBrief(input: BriefInput): Brief | null {
  const random = seeded(input.date);
  const lessons = input.modules.flatMap((m) => input.lessons.filter((l) => l.moduleId === m));
  if (lessons.length === 0) return null;

  // Carry on where the student is: a lecture under way, then a lesson with misses, then
  // the next new lesson; if everything is secure, the weakest topic.
  const byState = (state: LessonState) => lessons.find((l) => lessonState(l, input) === state);
  const meanScore = (l: LessonInfo) => {
    const scores = SKILLS.map((s) => input.topics[l.topicId]?.[s]).filter((e): e is Estimate => !!e);
    return scores.length ? scores.reduce((sum, e) => sum + logistic(e.theta), 0) / scores.length : 1;
  };
  const focus = byState("inProgress") ?? byState("needsReview") ?? byState("notStarted")
    ?? [...lessons].sort((a, b) => meanScore(a) - meanScore(b))[0];

  const estimate = (skill: Skill) => input.topics[focus.topicId]?.[skill] ?? input.headline[skill];
  const weakest = [...SKILLS].sort((a, b) => estimate(a).theta - estimate(b).theta)[0];
  const strongest = [...SKILLS].sort((a, b) => estimate(b).theta - estimate(a).theta)[0];
  const clearGap = logistic(estimate(strongest).theta) - logistic(estimate(weakest).theta) >= 0.05;

  const endOfDay = new Date(input.now.getTime() + 24 * HOUR);
  let due = interleave(input.items.filter((i) => i.due <= endOfDay));
  const steps: BriefStep[] = [];

  // Read: the lecture, if it isn't finished.
  const needsRead = (input.partsCompleted[focus.lessonId] ?? 0) < focus.lectureParts;
  if (needsRead) steps.push({ kind: "read", lessonId: focus.lessonId, itemIds: [], minutes: focus.estimatedMinutes });

  // Drill: quick items on the focus lesson, weakest skill first, yesterday's misses
  // before anything else, with a couple of due reviews from other topics mixed in.
  const recentMisses = new Set(
    input.items.filter((i) => !i.lastCorrect && input.now.getTime() - i.lastReview.getTime() <= 36 * HOUR).map((i) => i.itemId),
  );
  const pool = shuffled(focus.testPool.filter((i) => i.type !== "irac"), random)
    .sort((a, b) => Number(recentMisses.has(b.itemId)) - Number(recentMisses.has(a.itemId))
      || Number(b.skillTag === weakest) - Number(a.skillTag === weakest));
  const drillOwn = pool.slice(0, needsRead ? DRILL_ITEMS_AFTER_READ : DRILL_ITEMS).map((i) => i.itemId);
  const drillReviews = due.filter((i) => i.topicId !== focus.topicId && !drillOwn.includes(i.itemId)).slice(0, DRILL_REVIEWS);
  due = due.filter((i) => !drillReviews.includes(i) && !drillOwn.includes(i.itemId));
  const drillIds = shuffled([...drillOwn, ...drillReviews.map((i) => i.itemId)], random);
  steps.push({ kind: "drill", itemIds: drillIds, minutes: drillIds.length });

  // Build: apply the rule to fresh facts — for a student weak on application, or to
  // round out a short brief.
  const minutesSoFar = () => steps.reduce((sum, s) => sum + s.minutes, 0);
  const buildItems = [
    shuffled(focus.testPool.filter((i) => i.type === "irac"), random)[0],
    shuffled(focus.testPool.filter((i) => i.type === "applyTheRule" && !drillIds.includes(i.itemId)), random)[0],
  ].filter((i): i is LessonInfo["testPool"][number] => !!i);
  const wantsBuild = weakest === "application" || (!needsRead && due.length === 0);
  if (wantsBuild && buildItems.length > 0 && minutesSoFar() + 4 <= TARGET_MINUTES + 2) {
    steps.push({ kind: "build", itemIds: buildItems.map((i) => i.itemId), minutes: 4 });
  }

  // Review: whatever else has come due, interleaved, within the day's time.
  const manyDue = due.length > MANY_DUE;
  const budget = Math.max(manyDue ? 6 : 3, TARGET_MINUTES - minutesSoFar());
  const reviewIds = due.slice(0, Math.min(manyDue ? LONG_REVIEW_CAP : REVIEW_CAP, budget * 2)).map((i) => i.itemId);
  if (reviewIds.length > 0) steps.push({ kind: "review", itemIds: reviewIds, minutes: Math.ceil(reviewIds.length / 2) });

  // Always at least two steps.
  if (steps.length < 2 && buildItems.length > 0) steps.push({ kind: "build", itemIds: buildItems.map((i) => i.itemId), minutes: 4 });

  const reviewsIncluded = drillReviews.length + reviewIds.length;
  const reasons = [
    input.firstBrief ? "Built from your diagnostic." : null,
    clearGap ? `Chosen because ${phrase[weakest]} is your growth edge in ${focus.moduleTitle}.` : `Next on your ${focus.moduleTitle} pathway.`,
    reviewsIncluded > 0 ? `Folds in ${reviewsIncluded} ${reviewsIncluded === 1 ? "review" : "reviews"} that ${reviewsIncluded === 1 ? "has" : "have"} come due.` : null,
  ];

  return {
    date: input.date,
    lessonId: focus.lessonId,
    moduleId: focus.moduleId,
    topicId: focus.topicId,
    title: focus.title,
    minutes: steps.reduce((sum, s) => sum + s.minutes, 0),
    reason: reasons.filter(Boolean).join(" "),
    tutorNote: tutorNote(input, focus, weakest, steps, recentMisses, due.length + reviewsIncluded),
    steps,
  };
}

/** "From your tutor": rules over pre-approved sentences, never live AI (PRD). */
function tutorNote(input: BriefInput, focus: LessonInfo, weakest: Skill, steps: BriefStep[], recentMisses: Set<string>, dueCount: number): string | null {
  const focusMisses = input.items.filter((i) => recentMisses.has(i.itemId) && i.topicId === focus.topicId).length;
  if (focusMisses >= 2) return `Your last misses were on ${focus.title}. Today's drill starts with them.`;
  if (dueCount > MANY_DUE) return `${dueCount} reviews have come due. A longer review today keeps them from piling up.`;
  if (input.firstBrief) return "Your first brief comes from the diagnostic. It sharpens with every answer.";
  if (weakest === "application" && steps.some((s) => s.kind === "build")) {
    return "Application is where exam marks are won. The build step has you apply the rule to fresh facts.";
  }
  return null;
}
