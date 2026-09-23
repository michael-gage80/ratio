// The student model (PRD: "Student profile and scoring model"): an Elo-style
// Bayesian estimate — a rating θ and an uncertainty σ — for each student, skill and
// topic. After every answer:
//
//   p  = 1 / (1 + e^-(θ - b))       b: the item's difficulty, on the same logit scale
//   θ' = θ + K(σ)·(y − p)           y: 1 if correct, 0 if not; K grows with σ
//   σ' = max(σmin, σ·d)             d: shrink factor below 1
//
// Every answer updates two estimates: the topic's, and a headline estimate for the
// skill overall. A topic seen for the first time starts from the headline θ (a simple
// hierarchical prior) rather than from zero — otherwise a diagnostic, which touches
// each topic about once, could never show a strong student as strong. Scores are
// shown on a 0–100 scale with the band as a shaded range (app side).

export type Skill = "knowledge" | "understanding" | "application";
export const SKILLS: Skill[] = ["knowledge", "understanding", "application"];

export interface Estimate {
  theta: number;
  sigma: number;
}

export type Headline = Record<Skill, Estimate>;
/** topicId → the skills estimated for that topic. */
export type TopicEstimates = Record<string, Partial<Record<Skill, Estimate>>>;

/** Starting uncertainty: the widest band a skill can show (about ±23 on 0–100). */
export const SIGMA_PRIOR = 1.0;
/** The floor: bands never narrow beyond about ±6. */
export const SIGMA_MIN = 0.25;
/** Each answer shrinks σ by this factor. */
export const SHRINK = 0.8;

export const prior = (): Estimate => ({ theta: 0, sigma: SIGMA_PRIOR });

/** Content difficulty runs 0–1; map it onto the logit scale θ lives on (0.5 → 0). */
export const difficultyToLogit = (difficulty: number): number => (difficulty - 0.5) * 2;

/** Larger σ, larger steps: early answers move the estimate further. */
const gain = (sigma: number): number => sigma * sigma;

export function update(estimate: Estimate, difficulty: number, correct: boolean): Estimate {
  const p = 1 / (1 + Math.exp(-(estimate.theta - difficultyToLogit(difficulty))));
  return {
    theta: estimate.theta + gain(estimate.sigma) * ((correct ? 1 : 0) - p),
    sigma: Math.max(SIGMA_MIN, estimate.sigma * SHRINK),
  };
}

export const priorHeadline = (): Headline => ({ knowledge: prior(), understanding: prior(), application: prior() });

// MARK: Items and grading

export interface BankItem {
  itemId: string;
  topicId: string;
  skillTag: Skill;
  difficultyStart: number;
  type: string;
  correctIndex?: number;
  correctScenario?: "A" | "B";
  correctSpan?: string;
  sliderLabels?: [string, string];
  correctPosition?: string;
  correctOrder?: number[];
  passage?: string;
  ratioSentence?: string;
  factsToOrder?: string[];
}

/** What the app sends for one answered item. Only the field for its type is set. */
export interface ItemResponse {
  itemId: string;
  /** Choice items, and distinguishTheCase (0 = scenario A, 1 = B). */
  choiceIndex?: number;
  /** tapTheFact. */
  span?: string;
  /** thresholdSlider, 0 (left label) to 1 (right label). */
  sliderValue?: number;
  /** sequence: original item indices in the order the student left them. */
  order?: number[];
  /** recallFirst: the student's own mark against the model answer. */
  selfMarkedCorrect?: boolean;
}

export function isCorrect(item: BankItem, response: ItemResponse): boolean {
  switch (item.type) {
    case "quickCheck":
    case "mcqWithTrap":
    case "applyTheRule":
    case "statuteParser":
      return response.choiceIndex === item.correctIndex;
    case "distinguishTheCase":
      return response.choiceIndex === (item.correctScenario === "A" ? 0 : 1);
    case "tapTheFact":
      return response.span === item.correctSpan;
    case "thresholdSlider": {
      if (response.sliderValue === undefined || response.sliderValue === 0.5) return false;
      const rightIsCorrect = sliderCorrectSide(item) === 1;
      return rightIsCorrect ? response.sliderValue > 0.5 : response.sliderValue < 0.5;
    }
    case "sequence":
      return (
        !!response.order &&
        !!item.correctOrder &&
        response.order.length === item.correctOrder.length &&
        response.order.every((v, i) => v === item.correctOrder![i])
      );
    case "recallFirst":
      return response.selfMarkedCorrect === true;
    case "highlightTheRatio":
      return !!response.span && !!item.ratioSentence && sentenceStatesRatio(response.span, item.ratioSentence);
    case "irac": {
      // Mirrors the app: facts placed must be exactly the real ones (decoys arrive as
      // -1), any rule chosen must be the right one (0), and the written part must have
      // been marked as covering the model answer.
      if (response.order) {
        const facts = item.factsToOrder?.length ?? 0;
        const placed = new Set(response.order);
        if (placed.size !== facts || [...placed].some((i) => i < 0 || i >= facts)) return false;
      }
      if (response.choiceIndex !== undefined && response.choiceIndex !== 0) return false;
      return response.selfMarkedCorrect === true;
    }
    default:
      return false;
  }
}

/** Same rule as the app and the content lint: either contains the other, ignoring case, spacing and the final full stop. */
export function sentenceStatesRatio(sentence: string, ratio: string): boolean {
  const normalise = (s: string) => s.toLowerCase().replace(/\s+/g, " ").replace(/[.\s]+$/, "").trim();
  const [a, b] = [normalise(sentence), normalise(ratio)];
  return a.includes(b) || b.includes(a);
}

/** The end of the slider whose label contains the correct position (default: right). */
export function sliderCorrectSide(item: BankItem): 0 | 1 {
  const target = (item.correctPosition ?? "").toLowerCase();
  const left = (item.sliderLabels?.[0] ?? "").toLowerCase();
  return target && left.includes(target) ? 0 : 1;
}

/**
 * Scores answers in order, returning the updated per-topic estimates and headline.
 * Starts from the prior (the diagnostic) or from the student's current estimates.
 */
export function scoreResponses(
  responses: ItemResponse[],
  itemsById: Map<string, BankItem>,
  start: { topics?: TopicEstimates; headline?: Headline } = {},
): { topics: TopicEstimates; headline: Headline } {
  const topics: TopicEstimates = structuredClone(start.topics ?? {});
  const headline: Headline = structuredClone(start.headline ?? priorHeadline());
  for (const response of responses) {
    const item = itemsById.get(response.itemId);
    if (!item) continue;
    const skill = item.skillTag;
    const correct = isCorrect(item, response);
    const topic = (topics[item.topicId] ??= {});
    topic[skill] = update(topic[skill] ?? { theta: headline[skill].theta, sigma: SIGMA_PRIOR }, item.difficultyStart, correct);
    headline[skill] = update(headline[skill], item.difficultyStart, correct);
  }
  return { topics, headline };
}
