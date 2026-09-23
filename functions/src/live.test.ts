import assert from "node:assert/strict";
import { test } from "node:test";
import { DuelQuestion } from "./duel.js";
import { answer, checkedTime, COUNTDOWN_MS, forfeit, LiveState, newMatch, normalise, publicView, REVEAL_MS, timeout } from "./live.js";

const LIMIT = 10_000;
const q = (i: number, final = false): DuelQuestion => ({
  id: `q${i}`, kind: "fastestFinger", skill: "knowledge", prompt: `Q${i}`, options: ["a", "b", "c", "d"],
  correctIndex: 0, why: `because ${i}`, lessonId: "crime-01", topicId: "crime.x.y", difficulty: 0.5, final,
});
const questions = [...Array.from({ length: 8 }, (_, i) => q(i)), q(8, true)];
const T0 = 1_000_000;
const start = () => newMatch({
  mode: "lobby", moduleId: "crime", limitMs: LIMIT, order: ["amara", "zara"],
  players: { amara: { name: "Amara O.", initial: "A", rating: 1200 }, zara: { name: "Zara K.", initial: "Z", rating: 1250 } },
  questions,
}, T0);

/** Both players answer the current round: `a` then `b`, each at the given second, right (0) or wrong (1). */
function play(state: LiveState, a: [number, number], b: [number, number]): LiveState {
  const at = state.startsAt;
  let s = answer(state, 0, state.round, a[1], a[0] * 1000, at + a[0] * 1000 + 100).state;
  s = answer(s, 1, s.round, b[1], b[0] * 1000, at + b[0] * 1000 + 100).state;
  return s;
}

test("the first round starts after the countdown", () => {
  const s = start();
  assert.equal(s.round, 1);
  assert.equal(s.startsAt, T0 + COUNTDOWN_MS);
  assert.equal(answer(s, 0, 1, 0, 1000, T0 + 1000).outcome, "ignored"); // before it appears
});

test("a round resolves when both have answered, and the reveal comes before the next round", () => {
  const s = play(start(), [2, 0], [3, 0]);
  assert.deepEqual(s.score, [1, 0]);
  assert.equal(s.round, 2);
  const view = publicView(s);
  assert.equal(view.lastReveal?.winner, 0);
  assert.equal(view.lastReveal?.correctIndex, 0);
  assert.ok(s.startsAt >= T0 + COUNTDOWN_MS + 3000 + REVEAL_MS);
});

test("a lone answer waits; a timeout claim resolves only once time is really up", () => {
  let s = start();
  s = answer(s, 1, 1, 1, 2000, s.startsAt + 2100).state; // Zara, wrong
  assert.equal(s.round, 1);
  assert.equal(timeout(s, 1, s.startsAt + 5000), null);
  const after = timeout(s, 1, s.startsAt + LIMIT + 1000)!;
  assert.deepEqual(after.score, [1, 0]); // a wrong answer gives the point away
});

test("answers can't be changed or sent for another round", () => {
  let s = start();
  s = answer(s, 0, 1, 1, 2000, s.startsAt + 2100).state;
  assert.equal(answer(s, 0, 1, 0, 2500, s.startsAt + 2600).outcome, "ignored");
  assert.equal(answer(s, 1, 2, 0, 2500, s.startsAt + 2600).outcome, "ignored");
});

test("the players never see an answer before it's revealed", () => {
  const view = publicView(start());
  assert.equal(view.round?.question.correctIndex, -1);
  assert.equal(view.round?.question.why, "");
  assert.equal(JSON.stringify(view).includes("because"), false);
});

test("first to three wins; the final decides 2–2", () => {
  let s = start();
  for (let i = 0; i < 3; i++) s = play(s, [1, 0], [2, 0]);
  assert.equal(s.status, "complete");
  assert.equal(s.winner, 0);

  s = start();
  s = play(s, [1, 0], [2, 0]);
  s = play(s, [1, 0], [2, 0]);
  s = play(s, [2, 0], [1, 0]);
  s = play(s, [2, 0], [1, 0]);
  assert.equal(s.questions[s.questionIndex].final, true);
  s = play(s, [3, 0], [1, 1]); // Zara first and wrong
  assert.equal(s.status, "complete");
  assert.deepEqual(s.score, [3, 2]);
});

test("forfeiting ends the match for the other player", () => {
  const s = forfeit(start(), 1)!;
  assert.equal(s.status, "complete");
  assert.equal(s.winner, 0);
  assert.equal(s.forfeitedBy, 1);
  assert.equal(forfeit(s, 0), null);
});

test("claimed times are trusted only within what the server saw", () => {
  assert.equal(checkedTime(2300, 2600), 2300); // network delay
  assert.equal(checkedTime(9000, 2600), 2600); // longer than possible
  assert.equal(checkedTime(300, 7000), 7000); // claims a fast tap it sent much later
  assert.equal(checkedTime(100, 150), 150); // superhuman
});

test("state survives the database dropping empty values", () => {
  const stored = JSON.parse(JSON.stringify({ ...start(), pending: undefined, rounds: undefined, winner: undefined, forfeitedBy: undefined }));
  const s = normalise(stored);
  assert.deepEqual(s.rounds, []);
  assert.equal(play(s, [1, 0], [2, 0]).score[0], 1);
});

test("an unanswered round survives the database dropping nulls", () => {
  let s = start();
  s = timeout(s, 1, s.startsAt + LIMIT + 1000)!; // nobody answered
  s = answer(s, 0, 2, 1, 2000, s.startsAt + 2100).state; // Amara, wrong, pending
  const stored = JSON.parse(JSON.stringify(s, (_, v) => (v === null ? undefined : v)));
  const back = normalise(stored);
  assert.equal(back.rounds[0].answers[0].answerIndex, null);
  const resolved = timeout(back, 2, back.startsAt + LIMIT + 1000)!;
  assert.deepEqual(resolved.score, [0, 1]);
});
