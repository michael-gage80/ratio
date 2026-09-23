import assert from "node:assert/strict";
import { test } from "node:test";
import { dueDate, intervalDays, retrievability, review } from "./fsrs.js";

const DAY = 24 * 60 * 60 * 1000;
const start = new Date("2026-09-22T09:00:00Z");
const days = (n: number) => new Date(start.getTime() + n * DAY);

test("recall probability is 90% when elapsed time equals stability", () => {
  assert.ok(Math.abs(retrievability(10, 10) - 0.9) < 1e-9);
});

test("at 90% desired retention the interval equals the stability", () => {
  assert.equal(intervalDays(12), 12);
  assert.equal(intervalDays(0.3), 1); // Never sooner than tomorrow.
  assert.equal(intervalDays(10_000), 365); // Never further than a year.
});

test("a first review schedules a miss for tomorrow and a correct answer a few days out", () => {
  const miss = review(undefined, 1, start);
  const right = review(undefined, 3, start);
  assert.equal(intervalDays(miss.stability), 1);
  assert.equal(intervalDays(right.stability), 3);
  assert.ok(miss.difficulty > right.difficulty);
});

test("secure items drift further out with each correct review", () => {
  let state = review(undefined, 3, start);
  const intervals: number[] = [intervalDays(state.stability)];
  let when = start;
  for (let i = 0; i < 4; i++) {
    when = dueDate(state);
    state = review(state, 3, when);
    intervals.push(intervalDays(state.stability));
  }
  for (let i = 1; i < intervals.length; i++) assert.ok(intervals[i] > intervals[i - 1], `intervals grow: ${intervals}`);
});

test("a miss brings a well-known item back sooner and makes it harder", () => {
  let state = review(undefined, 3, start);
  state = review(state, 3, days(3));
  const lapsed = review(state, 1, dueDate(state));
  assert.ok(lapsed.stability < state.stability);
  assert.ok(lapsed.difficulty > state.difficulty);
  assert.ok(intervalDays(lapsed.stability) < intervalDays(state.stability));
});

test("difficulty stays within 1–10", () => {
  let state = review(undefined, 1, start);
  for (let i = 1; i <= 30; i++) state = review(state, 1, days(i));
  assert.ok(state.difficulty <= 10 && state.difficulty >= 1);
});
