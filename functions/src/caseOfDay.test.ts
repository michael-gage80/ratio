import assert from "node:assert/strict";
import { test } from "node:test";
import { addDays, pickCase, PickInput } from "./caseOfDay.js";
import { CaseEntry, caseItemId, cases, isReportedCase, testItems } from "./content.js";
import { update } from "./scoring.js";

const entry = (name: string, lessonId: string): CaseEntry => ({
  itemId: caseItemId(name), caseName: name, citation: "[2000] 1 AC 1", court: "House of Lords", factsShort: "", ratioShort: "",
  lessonId, moduleId: "crime", topicId: "crime.t", lessonIds: [lessonId],
});

const pool = [entry("A v B", "crime-01"), entry("C v D", "crime-01"), entry("E v F", "crime-02"), entry("G v H", "crime-03")];
const input = (over: Partial<PickInput>): PickInput => ({
  pool, started: new Set(["crime-01"]), rated: new Map(), upcoming: new Set(), date: "2026-09-28", seed: "amara", ...over,
});

test("days count on across month and year ends", () => {
  assert.equal(addDays("2026-09-28", 6), "2026-10-04");
  assert.equal(addDays("2026-12-31", 1), "2027-01-01");
  assert.equal(addDays("2026-10-01", -1), "2026-09-30");
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

test("unrated cases from started lessons come first, never twice in the week", () => {
  const first = pickCase(input({}));
  assert.ok(first && first.lessonId === "crime-01");
  const second = pickCase(input({ upcoming: new Set([first.itemId]) }));
  assert.ok(second && second.lessonId === "crime-01" && second.itemId !== first.itemId);
  assert.equal(pickCase(input({ date: "2026-10-01" }))?.itemId, pickCase(input({ date: "2026-10-01" }))?.itemId, "stable");
});

test("skipped cases stay in the pool; only rated ones are used", () => {
  const rated = new Map([[caseItemId("A v B"), 1]]);
  assert.equal(pickCase(input({ rated }))?.caseName, "C v D");
});

test("once every met case is rated, days alternate between a repeat and a preview", () => {
  const rated = new Map([[caseItemId("A v B"), 200], [caseItemId("C v D"), 100]]);
  const even = pickCase(input({ rated, date: "2026-09-28" })); // day number even
  const odd = pickCase(input({ rated, date: "2026-09-29" }));
  const kinds = [even, odd].map((c) => (c?.lessonId === "crime-01" ? "repeat" : "preview")).sort();
  assert.deepEqual(kinds, ["preview", "repeat"]);
  const repeat = [even, odd].find((c) => c?.lessonId === "crime-01");
  assert.equal(repeat?.caseName, "C v D", "the one rated longest ago");
});

test("nothing to pick when the pool is empty", () => {
  assert.equal(pickCase(input({ pool: [] })), null);
});

test("a case recall is a lighter answer", () => {
  const start = { theta: 0, sigma: 1 };
  const full = update(start, 0.5, true);
  const light = update(start, 0.5, true, 0.5);
  assert.ok(light.theta > 0 && light.theta < full.theta);
  assert.ok(light.sigma > full.sigma);
});
