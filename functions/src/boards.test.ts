import assert from "node:assert/strict";
import { test } from "node:test";
import { periodKeys } from "./boards.js";

test("keys follow the UK calendar, with weeks starting Monday", () => {
  assert.deepEqual(periodKeys(new Date("2026-09-23T12:00:00Z")), { daily: "day-2026-09-23", weekly: "week-2026-09-21", monthly: "month-2026-09" });
});

test("just after midnight UK in summer time is already the next day", () => {
  assert.equal(periodKeys(new Date("2026-09-20T23:30:00Z")).daily, "day-2026-09-21");
  assert.equal(periodKeys(new Date("2026-09-20T23:30:00Z")).weekly, "week-2026-09-21"); // Monday 00:30 BST
  assert.equal(periodKeys(new Date("2026-09-20T22:30:00Z")).weekly, "week-2026-09-14"); // still Sunday
});

test("a week that spans two months keeps its Monday", () => {
  assert.deepEqual(periodKeys(new Date("2026-10-02T09:00:00Z")), { daily: "day-2026-10-02", weekly: "week-2026-09-28", monthly: "month-2026-10" });
  assert.equal(periodKeys(new Date("2027-01-01T09:00:00Z")).weekly, "week-2026-12-28");
});
