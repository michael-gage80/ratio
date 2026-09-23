import assert from "node:assert/strict";
import { test } from "node:test";
import { BriefInput, buildBrief, interleave, ItemState, LessonInfo, londonDate } from "./brief.js";
import { priorHeadline, Skill } from "./scoring.js";

const HOUR = 60 * 60 * 1000;
const now = new Date("2026-09-23T07:00:00Z");

function lesson(n: number, topicId = `crime.group.topic-${n}`): LessonInfo {
  const pool: LessonInfo["testPool"] = [];
  const types: [string, Skill][] = [
    ["quickCheck", "knowledge"], ["mcqWithTrap", "knowledge"], ["recallFirst", "knowledge"],
    ["sequence", "understanding"], ["statuteParser", "understanding"], ["highlightTheRatio", "understanding"],
    ["applyTheRule", "application"], ["applyTheRule", "application"], ["tapTheFact", "application"], ["irac", "application"],
  ];
  types.forEach(([type, skillTag], i) => pool.push({ itemId: `crime-${n}-t${i}`, type, skillTag }));
  return { lessonId: `crime-0${n}`, moduleId: "crime", moduleTitle: "Crime", topicId, title: `Lesson ${n}`, estimatedMinutes: 14, lectureParts: 5, testPool: pool };
}

const lessons = [lesson(1), lesson(2), lesson(3)];

function input(overrides: Partial<BriefInput> = {}): BriefInput {
  return { date: londonDate(now), now, modules: ["crime"], headline: priorHeadline(), topics: {}, lessons, partsCompleted: {}, items: [], firstBrief: false, ...overrides };
}

function item(itemId: string, topicId: string, dueInHours: number, lastCorrect = true, lessonId = "crime-09"): ItemState {
  return { itemId, lessonId, topicId, due: new Date(now.getTime() + dueInHours * HOUR), lastReview: new Date(now.getTime() - 72 * HOUR), lastCorrect };
}

test("the UK date follows British Summer Time", () => {
  assert.equal(londonDate(new Date("2026-09-22T23:30:00Z")), "2026-09-23");
  assert.equal(londonDate(new Date("2026-12-22T23:30:00Z")), "2026-12-22");
});

test("a new student reads the first lesson, then drills it", () => {
  const brief = buildBrief(input({ firstBrief: true }))!;
  assert.equal(brief.lessonId, "crime-01");
  assert.deepEqual(brief.steps.map((s) => s.kind).slice(0, 2), ["read", "drill"]);
  assert.equal(brief.steps[1].itemIds.length, 3);
  assert.ok(brief.reason.startsWith("Built from your diagnostic."));
  assert.ok(brief.steps.length >= 2 && brief.steps.length <= 4);
});

test("a lecture under way is carried on before a new lesson", () => {
  const brief = buildBrief(input({ partsCompleted: { "crime-02": 2 } }))!;
  assert.equal(brief.lessonId, "crime-02");
});

test("a student weak on application gets a build step", () => {
  const headline = { ...priorHeadline(), application: { theta: -1, sigma: 0.5 } };
  const brief = buildBrief(input({ headline, partsCompleted: { "crime-01": 5 } }))!;
  const build = brief.steps.find((s) => s.kind === "build");
  assert.ok(build);
  assert.ok(brief.reason.includes("application is your growth edge"));
});

test("due reviews are folded in and interleaved across topics", () => {
  const items = [
    item("a1", "crime.a", -48), item("a2", "crime.a", -47), item("a3", "crime.a", -46),
    item("b1", "crime.b", -45), item("b2", "crime.b", -44),
    item("later", "crime.c", 72),
  ];
  const brief = buildBrief(input({ partsCompleted: { "crime-01": 5 }, items }))!;
  const scheduled = brief.steps.flatMap((s) => s.itemIds);
  for (const id of ["a1", "a2", "a3", "b1", "b2"]) assert.ok(scheduled.includes(id), `${id} is in the brief`);
  assert.ok(!scheduled.includes("later"));
  assert.deepEqual(interleave(items.slice(0, 5)).map((i) => i.itemId), ["a1", "b1", "a2", "b2", "a3"]);
});

test("many overdue items give a longer review", () => {
  const items = Array.from({ length: 30 }, (_, i) => item(`r${i}`, `crime.t${i % 4}`, -24 - i));
  const brief = buildBrief(input({ partsCompleted: { "crime-01": 5 }, items }))!;
  const review = brief.steps.find((s) => s.kind === "review")!;
  assert.ok(review.itemIds.length > 8);
  assert.ok(brief.tutorNote?.includes("reviews have come due"));
});

test("no brief when none of the student's modules has lessons", () => {
  assert.equal(buildBrief(input({ modules: ["tort"] })), null);
});

test("the same day gives the same brief", () => {
  assert.deepEqual(buildBrief(input()), buildBrief(input()));
});
