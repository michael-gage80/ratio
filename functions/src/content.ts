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

export const MODULES = ["crime", "contract", "tort", "public", "land", "equity", "companylaw", "eulaw", "humanrights", "jurisprudence"];

export const lessons = new Map<string, Lesson>(
  readdirSync(join(__dirname, "lessons"))
    .filter((f) => f.endsWith(".json"))
    .map((f) => JSON.parse(readFileSync(join(__dirname, "lessons", f), "utf8")) as Lesson)
    .sort((a, b) => a.lessonId.localeCompare(b.lessonId))
    .map((lesson) => [lesson.lessonId, lesson]),
);

/** Every test item, tagged with its lesson's topic. */
export const testItems = new Map<string, { item: BankItem; lessonId: string }>(
  [...lessons.values()].flatMap((lesson) =>
    lesson.testPool.map((item) => [item.itemId, { item: { ...item, topicId: lesson.topicId }, lessonId: lesson.lessonId }] as const),
  ),
);

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
