import assert from "node:assert/strict";
import { test } from "node:test";
import {
  BankItem,
  difficultyToLogit,
  isCorrect,
  prior,
  priorHeadline,
  scoreResponses,
  SIGMA_MIN,
  SIGMA_PRIOR,
  update,
} from "./scoring.js";

const item = (overrides: Partial<BankItem>): BankItem => ({
  itemId: "i",
  topicId: "crime.homicide.murder",
  skillTag: "knowledge",
  difficultyStart: 0.3,
  type: "quickCheck",
  ...overrides,
});

test("difficulty maps onto the logit scale around 0", () => {
  assert.equal(difficultyToLogit(0.5), 0);
  assert.ok(difficultyToLogit(0.2) < 0 && difficultyToLogit(0.8) > 0);
});

test("a correct answer raises θ, a wrong one lowers it, and σ shrinks either way", () => {
  const up = update(prior(), 0.3, true);
  const down = update(prior(), 0.3, false);
  assert.ok(up.theta > 0 && down.theta < 0);
  assert.equal(up.sigma, SIGMA_PRIOR * 0.8);
  assert.equal(down.sigma, SIGMA_PRIOR * 0.8);
});

test("missing an easy item costs more than getting it right gains", () => {
  const up = update(prior(), 0.2, true).theta;
  const down = update(prior(), 0.2, false).theta;
  assert.ok(Math.abs(down) > Math.abs(up));
});

test("σ never drops below its floor", () => {
  let e = prior();
  for (let i = 0; i < 50; i++) e = update(e, 0.5, true);
  assert.equal(e.sigma, SIGMA_MIN);
});

test("evidence accumulates in the headline across topics", () => {
  const items = new Map<string, BankItem>(
    ["a", "b", "c", "d"].map((id, i) => [id, item({ itemId: id, topicId: `crime.t${i}`, skillTag: "application", correctIndex: 0 })]),
  );
  const allRight = scoreResponses(["a", "b", "c", "d"].map((itemId) => ({ itemId, choiceIndex: 0 })), items).headline;
  const oneRight = scoreResponses([{ itemId: "a", choiceIndex: 0 }], items).headline;
  assert.ok(allRight.application.theta > oneRight.application.theta);
  assert.ok(allRight.application.sigma < oneRight.application.sigma);
});

test("a new topic starts from the skill's headline, not from zero", () => {
  const items = new Map<string, BankItem>([
    ["a", item({ itemId: "a", topicId: "crime.x", correctIndex: 0 })],
    ["b", item({ itemId: "b", topicId: "crime.y", correctIndex: 0 })],
  ]);
  const { topics } = scoreResponses([{ itemId: "a", choiceIndex: 0 }, { itemId: "b", choiceIndex: 0 }], items);
  assert.ok(topics["crime.y"].knowledge!.theta > topics["crime.x"].knowledge!.theta);
});

test("skills with no evidence stay at the prior", () => {
  const items = new Map<string, BankItem>([["a", item({ itemId: "a", correctIndex: 0 })]]);
  const { headline } = scoreResponses([{ itemId: "a", choiceIndex: 0 }], items);
  assert.deepEqual(headline.understanding, prior());
  assert.deepEqual(priorHeadline().application, prior());
});

test("grading covers every diagnostic item type", () => {
  assert.ok(isCorrect(item({ type: "mcqWithTrap", correctIndex: 1 }), { itemId: "i", choiceIndex: 1 }));
  assert.ok(!isCorrect(item({ type: "applyTheRule", correctIndex: 0 }), { itemId: "i", choiceIndex: 1 }));
  assert.ok(isCorrect(item({ type: "distinguishTheCase", correctScenario: "B" }), { itemId: "i", choiceIndex: 1 }));
  assert.ok(isCorrect(item({ type: "tapTheFact", correctSpan: "shoves them" }), { itemId: "i", span: "shoves them" }));
  assert.ok(isCorrect(item({ type: "sequence", correctOrder: [0, 1, 2] }), { itemId: "i", order: [0, 1, 2] }));
  assert.ok(!isCorrect(item({ type: "sequence", correctOrder: [0, 1, 2] }), { itemId: "i", order: [1, 0, 2] }));
  assert.ok(isCorrect(item({ type: "recallFirst" }), { itemId: "i", selfMarkedCorrect: true }));
  assert.ok(!isCorrect(item({ type: "recallFirst" }), { itemId: "i" }));
});

test("the slider is correct on the side whose label contains the answer, never the middle", () => {
  const slider = item({ type: "thresholdSlider", sliderLabels: ["Definitely a valid defence", "Definitely not a defence"], correctPosition: "not a defence" });
  assert.ok(isCorrect(slider, { itemId: "i", sliderValue: 1 }));
  assert.ok(isCorrect(slider, { itemId: "i", sliderValue: 0.75 }));
  assert.ok(!isCorrect(slider, { itemId: "i", sliderValue: 0.5 }));
  assert.ok(!isCorrect(slider, { itemId: "i", sliderValue: 0 }));
  const leftAnswer = item({ type: "thresholdSlider", sliderLabels: ["Settled law", "Contested"], correctPosition: "settled" });
  assert.ok(isCorrect(leftAnswer, { itemId: "i", sliderValue: 0.25 }));
});

test("scoring ignores unknown items and builds per-topic estimates in answer order", () => {
  const items = new Map<string, BankItem>([
    ["a", item({ itemId: "a", topicId: "crime.x", skillTag: "application", correctIndex: 0 })],
    ["b", item({ itemId: "b", topicId: "crime.x", skillTag: "application", correctIndex: 0 })],
  ]);
  const { topics, headline } = scoreResponses(
    [{ itemId: "a", choiceIndex: 0 }, { itemId: "b", choiceIndex: 0 }, { itemId: "zzz", choiceIndex: 0 }],
    items,
  );
  assert.deepEqual(Object.keys(topics), ["crime.x"]);
  assert.ok(topics["crime.x"].application!.theta > 0);
  assert.equal(topics["crime.x"].application!.sigma, 0.8 * 0.8);
  assert.deepEqual(headline.knowledge, prior());
});
