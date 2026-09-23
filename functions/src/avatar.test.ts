import assert from "node:assert/strict";
import { test } from "node:test";
import { isAcceptable } from "./avatar.js";

test("an ordinary photo is accepted", () => {
  assert.equal(isAcceptable({ adult: "VERY_UNLIKELY", violence: "UNLIKELY", racy: "POSSIBLE" }), true);
});

test("likely adult or violent content is refused", () => {
  assert.equal(isAcceptable({ adult: "LIKELY", violence: "VERY_UNLIKELY", racy: "UNLIKELY" }), false);
  assert.equal(isAcceptable({ adult: "VERY_UNLIKELY", violence: "VERY_LIKELY", racy: "UNLIKELY" }), false);
});

test("racy content is refused only when very likely", () => {
  assert.equal(isAcceptable({ adult: "UNLIKELY", violence: "UNLIKELY", racy: "LIKELY" }), true);
  assert.equal(isAcceptable({ adult: "UNLIKELY", violence: "UNLIKELY", racy: "VERY_LIKELY" }), false);
});

test("an unreadable image is refused", () => {
  assert.equal(isAcceptable(undefined), false);
});
