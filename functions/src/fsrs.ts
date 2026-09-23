// Spaced review scheduling with FSRS-5 (PRD: "an FSRS-style scheduler for each item
// and student"; https://github.com/open-spaced-repetition). Each item carries a
// memory stability S (days until recall probability falls to 90%) and a difficulty D
// (1–10). Ratio grades binary — right or wrong — so reviews are rated Good (3) or
// Again (1): "items the student got wrong come back sooner; secure items drift out".

export type Rating = 1 | 2 | 3 | 4; // Again, Hard, Good, Easy

export interface MemoryState {
  stability: number;
  difficulty: number;
  /** When it was last reviewed. */
  lastReview: Date;
}

/** FSRS-5 default parameters. */
const W = [
  0.40255, 1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575, 0.1192, 1.01925, 1.9395, 0.11, 0.29605,
  2.2698, 0.2315, 2.9898, 0.51655, 0.6621,
];
const DECAY = -0.5;
const FACTOR = 19 / 81; // Makes retrievability 0.9 when elapsed time equals stability.
/** Schedule for 90% recall; at this retention the interval equals the stability. */
export const DESIRED_RETENTION = 0.9;
export const MAX_INTERVAL_DAYS = 365;

const DAY = 24 * 60 * 60 * 1000;
const clamp = (value: number, min: number, max: number) => Math.min(max, Math.max(min, value));

/** Probability of recall after `elapsedDays` with stability `stability`. */
export const retrievability = (elapsedDays: number, stability: number): number =>
  Math.pow(1 + (FACTOR * elapsedDays) / stability, DECAY);

const initialDifficulty = (rating: Rating): number => clamp(W[4] - Math.exp(W[5] * (rating - 1)) + 1, 1, 10);

function nextDifficulty(difficulty: number, rating: Rating): number {
  const delta = -W[6] * (rating - 3);
  const damped = difficulty + (delta * (10 - difficulty)) / 9; // Linear damping (FSRS-5).
  return clamp(W[7] * initialDifficulty(4) + (1 - W[7]) * damped, 1, 10); // Mean reversion.
}

function stabilityAfterRecall(s: number, d: number, r: number, rating: Rating): number {
  const hardPenalty = rating === 2 ? W[15] : 1;
  const easyBonus = rating === 4 ? W[16] : 1;
  return s * (Math.exp(W[8]) * (11 - d) * Math.pow(s, -W[9]) * (Math.exp(W[10] * (1 - r)) - 1) * hardPenalty * easyBonus + 1);
}

function stabilityAfterLapse(s: number, d: number, r: number): number {
  const next = W[11] * Math.pow(d, -W[12]) * (Math.pow(s + 1, W[13]) - 1) * Math.exp(W[14] * (1 - r));
  return Math.min(next, s); // A lapse never makes a memory more stable (FSRS-5).
}

/** The memory state after reviewing an item at `now`; `previous` is undefined for a first review. */
export function review(previous: MemoryState | undefined, rating: Rating, now: Date): MemoryState {
  if (!previous) {
    return { stability: W[rating - 1], difficulty: initialDifficulty(rating), lastReview: now };
  }
  const elapsedDays = Math.max(0, (now.getTime() - previous.lastReview.getTime()) / DAY);
  const { stability: s, difficulty: d } = previous;
  let stability: number;
  if (elapsedDays < 1) {
    stability = s * Math.exp(W[17] * (rating - 3 + W[18])); // Same-day review (FSRS-5).
  } else {
    const r = retrievability(elapsedDays, s);
    stability = rating === 1 ? stabilityAfterLapse(s, d, r) : stabilityAfterRecall(s, d, r, rating);
  }
  return { stability: Math.max(stability, 0.1), difficulty: nextDifficulty(d, rating), lastReview: now };
}

/** Whole days until the next review: at least tomorrow, at most a year. */
export function intervalDays(stability: number): number {
  const days = (stability / FACTOR) * (Math.pow(DESIRED_RETENTION, 1 / DECAY) - 1);
  return clamp(Math.round(days), 1, MAX_INTERVAL_DAYS);
}

export const dueDate = (state: MemoryState): Date => new Date(state.lastReview.getTime() + intervalDays(state.stability) * DAY);
