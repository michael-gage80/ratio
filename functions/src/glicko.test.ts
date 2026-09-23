import assert from "node:assert/strict";
import { test } from "node:test";
import { INITIAL, rate } from "./glicko.js";

test("matches Glickman's worked example for the first opponent", () => {
  // Glickman (2013): 1500/200/0.06 beats 1400/30. With one game the rating rises and RD falls.
  const after = rate({ rating: 1500, rd: 200, vol: 0.06 }, { rating: 1400, rd: 30 }, 1);
  assert.ok(after.rating > 1500 && after.rating < 1600, `rating ${after.rating}`);
  assert.ok(after.rd < 200);
  assert.ok(Math.abs(after.vol - 0.06) < 0.001);
});

test("a new player moves a lot; a settled one moves a little", () => {
  const fresh = rate(INITIAL, { rating: 1200, rd: 60 }, 1);
  const settled = rate({ rating: 1200, rd: 60, vol: 0.06 }, { rating: 1200, rd: 60 }, 1);
  assert.ok(fresh.rating - 1200 > 100);
  assert.ok(settled.rating - 1200 < 30);
});

test("a loss lowers the rating and a draw against an equal leaves it about the same", () => {
  const player = { rating: 1300, rd: 80, vol: 0.06 };
  assert.ok(rate(player, { rating: 1300, rd: 60 }, 0).rating < 1300);
  assert.ok(Math.abs(rate(player, { rating: 1300, rd: 60 }, 0.5).rating - 1300) < 1);
});

test("beating a much weaker opponent gains little", () => {
  const player = { rating: 1500, rd: 80, vol: 0.06 };
  const easy = rate(player, { rating: 1000, rd: 60 }, 1).rating - 1500;
  const even = rate(player, { rating: 1500, rd: 60 }, 1).rating - 1500;
  assert.ok(easy < even / 3);
});
