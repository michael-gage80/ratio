import assert from "node:assert/strict";
import { test } from "node:test";
import { tally } from "./online.js";

test("counts fresh entries and flags stale or malformed ones", () => {
  const now = 1_000_000_000;
  const result = tally({ a: now - 60_000, b: now - 16 * 60_000, c: "x", d: now }, now);
  assert.equal(result.online, 2);
  assert.deepEqual(result.stale.sort(), ["b", "c"]);
});
