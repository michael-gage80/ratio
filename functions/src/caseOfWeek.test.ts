import assert from "node:assert/strict";
import { test } from "node:test";
import { pickCase, weekKey } from "./caseOfWeek.js";
import { CaseEntry, caseItemId, cases, isReportedCase, testItems } from "./content.js";
import { update } from "./scoring.js";

const entry = (name: string, lessonId: string): CaseEntry => ({
  itemId: caseItemId(name), caseName: name, citation: "[2000] 1 AC 1", court: "House of Lords", factsShort: "", ratioShort: "",
  lessonId, moduleId: "crime", topicId: "crime.t", lessonIds: [lessonId],
});

test("the week starts at 00:00 UK time on Monday", () => {
  assert.equal(weekKey(new Date("2026-09-28T09:00:00Z")), "2026-09-28"); // Monday
  assert.equal(weekKey(new Date("2026-10-04T22:30:00Z")), "2026-09-28"); // Sunday 23:30 BST
  assert.equal(weekKey(new Date("2026-10-04T23:30:00Z")), "2026-10-05"); // Monday 00:30 BST
  assert.equal(weekKey(new Date("2026-12-31T12:00:00Z")), "2026-12-28");
});

test("case IDs are slugs of the name", () => {
  assert.equal(caseItemId("R v Woollin"), "case-r-v-woollin");
  assert.equal(caseItemId("M'Naghten's Case"), "case-m-naghten-s-case");
  assert.equal(caseItemId("CILFIT v Ministero della Sanità"), "case-cilfit-v-ministero-della-sanit");
});

test("only reported cases count", () => {
  assert.ok(isReportedCase("[1999] 1 AC 82", "House of Lords"));
  assert.ok(isReportedCase("(1843) 10 Cl & F 200", "House of Lords"));
  assert.ok(!isReportedCase("Illustrative, not a reported case", "N/A"));
  assert.ok(!isReportedCase("CA 2006, ss 630, 633", "Statute (not a case)"));
});

test("every bundled case is a case-recall item", () => {
  assert.ok(cases.size > 250);
  for (const c of cases.values()) {
    const item = testItems.get(c.itemId);
    assert.ok(item, c.caseName);
    assert.equal(item.item.type, "recallFirst");
    assert.equal(item.item.skillTag, "knowledge");
    assert.ok(c.ratioShort.length > 0);
  }
});

test("picks a case from a started lesson, never a repeat until all are seen, stable per seed", () => {
  const pool = [entry("A v B", "crime-01"), entry("C v D", "crime-02"), entry("E v F", "crime-03")];
  assert.equal(pickCase(pool, new Set(["crime-02"]), new Set(), "s")?.caseName, "C v D");
  const fresh = pickCase(pool, new Set(["crime-02"]), new Set([caseItemId("C v D")]), "s");
  assert.notEqual(fresh?.caseName, "C v D");
  assert.ok(pickCase(pool, new Set(), new Set(pool.map((c) => c.itemId)), "s"), "starts again once all are seen");
  assert.equal(pickCase(pool, new Set(), new Set(), "u:w")?.itemId, pickCase([...pool].reverse(), new Set(), new Set(), "u:w")?.itemId);
  assert.equal(pickCase([], new Set(), new Set(), "s"), null);
});

test("a case recall is a lighter answer", () => {
  const start = { theta: 0, sigma: 1 };
  const full = update(start, 0.5, true);
  const light = update(start, 0.5, true, 0.5);
  assert.ok(light.theta > 0 && light.theta < full.theta);
  assert.ok(light.sigma > full.sigma);
});
