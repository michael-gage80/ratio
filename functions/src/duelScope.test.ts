import assert from "node:assert/strict";
import { test } from "node:test";
import { limitFor, ratingWindow, requireDuelModule, sharedModules } from "./duelScope.js";

test("15 s a question, or 30 s with extra time", () => {
  assert.equal(limitFor(undefined), 15_000);
  assert.equal(limitFor(20), 15_000);
  assert.equal(limitFor(30), 30_000);
});

test("the rating window widens from ±100 to ±500 at 60 s, then holds", () => {
  assert.equal(ratingWindow(0), 100);
  assert.equal(ratingWindow(9_999), 100);
  assert.equal(ratingWindow(30_000), 300);
  assert.equal(ratingWindow(60_000), 500);
  assert.equal(ratingWindow(600_000), 500);
});

test("mixed duels use shared modules, or both students' when they share none", () => {
  assert.deepEqual(sharedModules(["crime", "tort", "land"], ["tort", "land", "equity"]), ["tort", "land"]);
  assert.deepEqual(sharedModules(["crime"], ["tort"]), ["crime", "tort"]);
});

test("a duel is on a known module or mixed", () => {
  assert.equal(requireDuelModule("mixed"), "mixed");
  assert.equal(requireDuelModule("crime"), "crime");
  assert.throws(() => requireDuelModule("astrology"));
});
