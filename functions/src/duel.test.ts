import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { Answer, DuelLesson, DuelQuestion, matchQuestions, playMatch, questionPool, resolveRound, segments, sparringPlan } from "./duel.js";

const LIMIT = 10_000;
const q = (correctIndex = 0, final = false): DuelQuestion => ({
  id: `q${Math.random()}`, kind: "fastestFinger", skill: "knowledge", prompt: "?", options: ["a", "b", "c", "d"],
  correctIndex, why: "", lessonId: "crime-01", topicId: "crime.x.y", difficulty: 0.5, final,
});
const right = (timeMs: number): Answer => ({ answerIndex: 0, timeMs });
const wrong = (timeMs: number): Answer => ({ answerIndex: 1, timeMs });
const none: Answer = { answerIndex: null, timeMs: LIMIT };

test("the first right answer takes the point", () => {
  assert.equal(resolveRound(q(), [right(2000), right(3000)], LIMIT), 0);
  assert.equal(resolveRound(q(), [right(4000), right(3000)], LIMIT), 1);
});

test("a wrong answer first gives the point away", () => {
  assert.equal(resolveRound(q(), [wrong(1500), right(6000)], LIMIT), 1);
  assert.equal(resolveRound(q(), [wrong(1500), none], LIMIT), 1);
  assert.equal(resolveRound(q(), [none, wrong(1500)], LIMIT), 0);
});

test("nobody scores when nobody answers in time, and impossible taps don't count", () => {
  assert.equal(resolveRound(q(), [none, none], LIMIT), null);
  assert.equal(resolveRound(q(), [right(12_000), none], LIMIT), null);
  assert.equal(resolveRound(q(), [right(50), right(4000)], LIMIT), 1);
});

test("first to three wins", () => {
  const questions = [q(), q(), q(), q(), q(), q(), q(), q(), q(0, true)];
  const outcome = playMatch(questions, [right(1000), right(1000), right(1000)], questions.map(() => right(3000)), LIMIT);
  assert.deepEqual(outcome.score, [3, 0]);
  assert.equal(outcome.winner, 0);
  assert.equal(outcome.rounds.length, 3);
});

test("the final round decides it at 2–2", () => {
  const questions = [q(), q(), q(), q(), q(), q(), q(), q(), q(0, true)];
  const plan = questions.map((_, i) => (i === 8 ? right(5000) : right(3000)));
  const mine = [right(1000), right(1000), right(5000), right(5000), right(1000)];
  const outcome = playMatch(questions, mine, plan, LIMIT);
  assert.deepEqual(outcome.score, [3, 2]);
  assert.equal(outcome.rounds.at(-1)!.questionIndex, 8);
});

test("a match nobody finishes ends after the regular rounds", () => {
  const questions = [q(), q(), q(), q(), q(), q(), q(), q(), q(0, true)];
  const outcome = playMatch(questions, [], questions.map(() => none), LIMIT);
  assert.equal(outcome.rounds.length, 8);
  assert.equal(outcome.winner, null);
});

test("a scenario is cut at its tappable phrases", () => {
  const cut = segments("Owen, wanting to frighten a rival, drives at speed, not slowing down.", ["at speed", "wanting to frighten a rival", "not slowing down"]);
  assert.deepEqual(cut, [
    { text: "Owen" },
    { text: "wanting to frighten a rival", option: 0 },
    { text: "drives" },
    { text: "at speed", option: 1 },
    { text: "not slowing down", option: 2 },
  ]);
  assert.equal(segments("abc", ["zzz"]), null);
});

test("a sparring partner's accuracy follows its level", () => {
  const questions = Array.from({ length: 2000 }, () => q());
  let seed = 1;
  const random = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  const accuracy = (level: number) => sparringPlan(questions, level, LIMIT, random).filter((a) => a.answerIndex === 0).length / 2000;
  assert.ok(accuracy(1) < accuracy(3) && accuracy(3) < accuracy(5));
  assert.ok(sparringPlan(questions, 5, LIMIT, random).every((a) => a.timeMs <= LIMIT));
});

test("the Crime lessons give a full match of every round type", () => {
  const dir = join(__dirname, "lessons");
  const crime = readdirSync(dir).filter((f) => f.startsWith("crime-")).map((f) => JSON.parse(readFileSync(join(dir, f), "utf8")) as DuelLesson);
  const pool = questionPool(crime, Math.random);
  assert.ok(pool.fastestFinger.length >= 4, `fastest finger: ${pool.fastestFinger.length}`);
  assert.ok(pool.nameTheCase.length >= 4, `name the case: ${pool.nameTheCase.length}`);
  assert.ok(pool.spotTheIssue.length >= 4, `spot the issue: ${pool.spotTheIssue.length}`);
  const questions = matchQuestions(pool, Math.random)!;
  assert.equal(questions.length, 9);
  assert.equal(new Set(questions.map((x) => x.id)).size, 9);
  for (const question of questions) assert.ok(question.options[question.correctIndex] !== undefined);
  assert.equal(matchQuestions(pool, Math.random, true)!.length, 3);
});
