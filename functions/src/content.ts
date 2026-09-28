// The lessons the app bundles, copied into lib/lessons at build time, so the server
// marks, schedules and builds duels from its own copy rather than trusting the client.

import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { LessonInfo } from "./brief.js";
import { DuelLesson } from "./duel.js";
import { BankItem, Estimate, Skill } from "./scoring.js";

export interface Lesson {
  lessonId: string;
  moduleId: string;
  moduleTitle: string;
  topicId: string;
  title: string;
  estimatedMinutes: number;
  lecture: { parts: unknown[] };
  itemCounts: { testServedPerAttempt: number };
  testPool: BankItem[];
}

export type TopicScores = Partial<Record<Skill, Estimate>>;

/** Snapshots of a topic's scores kept for the Me tab's trend charts. */
export const HISTORY_LIMIT = 100;

export const MODULES = ["crime", "contract", "tort", "public", "land", "equity", "companylaw", "eulaw", "humanrights", "jurisprudence", "employmentlaw", "familylaw",
  // SQE1 (Functioning Legal Knowledge), Ratio-Lesson-Spine.md part two.
  "sqe1-dispute-resolution", "sqe1-legal-system-legal-services", "sqe1-business-law-practice", "sqe1-property-practice", "sqe1-wills-administration-estates", "sqe1-solicitors-accounts", "sqe1-criminal-law-practice"];

/**
 * Items without a `difficultyStart` are treated as middling (0.5), as the app does; the
 * scoring and duel code need a number (undefined would make every score NaN).
 */
function withDefaults(lesson: Lesson): Lesson {
  for (const item of lesson.testPool) item.difficultyStart ??= 0.5;
  return lesson;
}

export const lessons = new Map<string, Lesson>(
  readdirSync(join(__dirname, "lessons"))
    // Only real lesson files: iCloud leaves "name 2.json" copies behind in synced folders.
    .filter((f) => /^[a-z0-9]+(-[a-z]+)?-\d{2}-[a-z0-9-]+\.json$/.test(f))
    .map((f) => withDefaults(JSON.parse(readFileSync(join(__dirname, "lessons", f), "utf8")) as Lesson))
    .sort((a, b) => a.lessonId.localeCompare(b.lessonId))
    .map((lesson) => [lesson.lessonId, lesson]),
);

/** A case card from the lectures (Case of the week, and its case-recall reviews). */
export interface CaseEntry {
  /** "case-" plus the case name as a slug; the app derives the same ID. */
  itemId: string;
  caseName: string;
  citation: string;
  court: string;
  factsShort: string;
  ratioShort: string;
  /** The first lesson, by ID, whose lecture has the case: its module and topic. */
  lessonId: string;
  moduleId: string;
  topicId: string;
  /** Every lesson whose lecture has the case. */
  lessonIds: string[];
}

export const CASE_ITEM_PREFIX = "case-";

/** Same rule as the app's `CaseOfWeek.itemId(for:)`. */
export function caseItemId(caseName: string): string {
  return CASE_ITEM_PREFIX + caseName.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 80);
}

/**
 * A reported case, not a worked example or summary on a case card: a year in brackets
 * in the citation ("[1993]", "(1843)") and a real court. Same rule as the app.
 */
export function isReportedCase(citation: string, court: string): boolean {
  return /[[(]\d{4}[\])]/.test(citation) && !/^N\/A|not a case/i.test(court);
}

/** Every case in the lectures, once each (lessons in ID order, so the first lesson is stable). */
export const cases = new Map<string, CaseEntry>();
for (const lesson of lessons.values()) {
  for (const part of lesson.lecture.parts as { components?: Record<string, unknown>[] }[]) {
    for (const component of part.components ?? []) {
      if (component.type !== "caseCard") continue;
      const caseName = String(component.caseName ?? "");
      if (!caseName || !component.ratioShort || !isReportedCase(String(component.citation ?? ""), String(component.court ?? ""))) continue;
      const itemId = caseItemId(caseName);
      const existing = cases.get(itemId);
      if (existing) {
        if (!existing.lessonIds.includes(lesson.lessonId)) existing.lessonIds.push(lesson.lessonId);
        continue;
      }
      cases.set(itemId, {
        itemId,
        caseName,
        citation: String(component.citation ?? ""),
        court: String(component.court ?? ""),
        factsShort: String(component.factsShort ?? ""),
        ratioShort: String(component.ratioShort),
        lessonId: lesson.lessonId,
        moduleId: lesson.moduleId,
        topicId: lesson.topicId,
        lessonIds: [lesson.lessonId],
      });
    }
  }
}

/**
 * A case recalled from its facts: marked by the student against the ratio, like a
 * recallFirst item, and counted as a light Knowledge answer.
 */
export const CASE_RECALL_WEIGHT = 0.5;
function caseRecallItem(entry: CaseEntry): BankItem {
  return { itemId: entry.itemId, topicId: entry.topicId, skillTag: "knowledge", difficultyStart: 0.5, type: "recallFirst", weight: CASE_RECALL_WEIGHT };
}

/** Every test item, tagged with its lesson's topic — plus a case-recall item for every case. */
export const testItems = new Map<string, { item: BankItem; lessonId: string }>([
  ...[...lessons.values()].flatMap((lesson) =>
    lesson.testPool.map((item) => [item.itemId, { item: { ...item, topicId: lesson.topicId }, lessonId: lesson.lessonId }] as const),
  ),
  ...[...cases.values()].map((entry) => [entry.itemId, { item: caseRecallItem(entry), lessonId: entry.lessonId }] as const),
]);

export const lessonInfo: LessonInfo[] = [...lessons.values()].map((l) => ({
  lessonId: l.lessonId,
  moduleId: l.moduleId,
  moduleTitle: l.moduleTitle,
  topicId: l.topicId,
  title: l.title,
  estimatedMinutes: l.estimatedMinutes,
  lectureParts: l.lecture.parts.length,
  testPool: l.testPool.map((i) => ({ itemId: i.itemId, type: i.type, skillTag: i.skillTag })),
}));

export const duelLessons = [...lessons.values()] as unknown as DuelLesson[];
