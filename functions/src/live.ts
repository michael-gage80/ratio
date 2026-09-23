// Live duels (PRD: "Matches are ... server-authoritative, meaning the server decides
// every point"). The whole match lives at /live/{matchId} in the Realtime Database:
// `state` is the referee's (questions with answers, answers not yet revealed) and only
// Functions can read it; `public` is what the players see. Every change goes through
// these pure functions inside a transaction, so two answers landing at once can't both
// decide a round.

import { Answer, DuelQuestion, marked, MIN_ANSWER_MS, nextQuestionIndex, resolveRound } from "./duel.js";

/** Before the first round: the versus screen and a 5-second countdown (PRD). */
export const COUNTDOWN_MS = 5000;
/** Between rounds, while the reveal is shown. */
export const REVEAL_MS = 3000;
/** Late answers and timeout claims get this much grace for the network. */
export const GRACE_MS = 1500;
/** A player gone this long forfeits the match (PRD: "after 45 s the whole match"). */
export const FORFEIT_AFTER_MS = 45_000;

export type Mode = "lobby" | "ranked" | "challenge";

export interface Player {
  name: string;
  initial: string;
  rating: number;
  avatarVersion?: number;
}

export interface LiveState {
  mode: Mode;
  moduleId: string;
  limitMs: number;
  /** Player 0 and player 1. */
  order: [string, string];
  players: Record<string, Player>;
  questions: DuelQuestion[];
  status: "playing" | "complete";
  /** 1-based; 0 before the first round is set. */
  round: number;
  questionIndex: number;
  /** Server time the current round's question appears. */
  startsAt: number;
  regularPlayed: number;
  finalPlayed: boolean;
  score: [number, number];
  /** The current round's answers, by player index (stored as an array or a map; both index alike). */
  pending: Pending;
  rounds: { questionIndex: number; answers: (Answer & { correct: boolean })[]; winner: number | null }[];
  winner: number | null;
  forfeitedBy: number | null;
  version: number;
}

export type Pending = Partial<Record<0 | 1, Answer & { at: number }>>;

/** The Realtime Database drops empty arrays and turns sparse ones into maps. */
export function normalise(raw: LiveState): LiveState {
  // Null answer indices come back missing, which would otherwise read as an answer given.
  const fix = <T extends Answer>(a: T | undefined): T | undefined => (a ? { ...a, answerIndex: a.answerIndex ?? null } : undefined);
  const pending: Pending = {};
  for (const p of [0, 1] as const) {
    const entry = fix(raw.pending?.[p]);
    if (entry) pending[p] = entry;
  }
  return {
    ...raw,
    pending,
    rounds: (raw.rounds ?? []).map((r) => ({ ...r, answers: r.answers.map((a) => fix(a)!), winner: r.winner ?? null })),
    winner: raw.winner ?? null,
    forfeitedBy: raw.forfeitedBy ?? null,
    score: [raw.score?.[0] ?? 0, raw.score?.[1] ?? 0],
    finalPlayed: raw.finalPlayed ?? false,
  };
}

export function newMatch(
  params: { mode: Mode; moduleId: string; limitMs: number; order: [string, string]; players: Record<string, Player>; questions: DuelQuestion[] },
  now: number,
): LiveState {
  const state: LiveState = {
    ...params,
    status: "playing",
    round: 0,
    questionIndex: -1,
    startsAt: 0,
    regularPlayed: 0,
    finalPlayed: false,
    score: [0, 0],
    pending: {},
    rounds: [],
    winner: null,
    forfeitedBy: null,
    version: 0,
  };
  return startNextRound(state, now + COUNTDOWN_MS);
}

function startNextRound(state: LiveState, startsAt: number): LiveState {
  const next = nextQuestionIndex(state.questions, state.score, state.regularPlayed, state.finalPlayed);
  if (next === null) return finish(state, state.score[0] === state.score[1] ? null : state.score[0] > state.score[1] ? 0 : 1, null);
  const final = state.questions[next].final === true;
  return {
    ...state,
    round: state.round + 1,
    questionIndex: next,
    startsAt,
    regularPlayed: state.regularPlayed + (final ? 0 : 1),
    finalPlayed: state.finalPlayed || final,
    pending: {},
    version: state.version + 1,
  };
}

function finish(state: LiveState, winner: number | null, forfeitedBy: number | null): LiveState {
  return { ...state, status: "complete", winner, forfeitedBy, pending: {}, version: state.version + 1 };
}

/**
 * The device's measured time is trusted within what the server saw: never longer than
 * the time since the question went out (plus a little clock slack), and never so much
 * shorter that the answer must have been sent late. Otherwise the server's own
 * elapsed time is used.
 */
export function checkedTime(claimedMs: number, serverElapsedMs: number): number {
  const plausible = claimedMs >= MIN_ANSWER_MS && claimedMs <= serverElapsedMs + 500 && claimedMs >= serverElapsedMs - 4000;
  return Math.round(plausible ? claimedMs : serverElapsedMs);
}

export type AnswerOutcome = "recorded" | "resolved" | "ignored";

/** A player's answer to the current round. The round resolves once both have answered. */
export function answer(state: LiveState, player: 0 | 1, round: number, answerIndex: number, claimedMs: number, now: number): { state: LiveState; outcome: AnswerOutcome } {
  if (state.status !== "playing" || round !== state.round || now < state.startsAt) return { state, outcome: "ignored" };
  const pending = state.pending;
  if (pending[player]) return { state, outcome: "ignored" };
  const elapsed = now - state.startsAt;
  const recorded: Answer & { at: number } = elapsed > state.limitMs + GRACE_MS
    ? { answerIndex: null, timeMs: state.limitMs, at: now }
    : { answerIndex, timeMs: checkedTime(claimedMs, elapsed), at: now };
  const next: LiveState = { ...state, pending: { ...pending, [player]: recorded }, version: state.version + 1 };
  const both = next.pending[0] && next.pending[1];
  return both ? { state: resolve(next, now), outcome: "resolved" } : { state: next, outcome: "recorded" };
}

/** Called by either player when the clock runs out; honoured once the server agrees. */
export function timeout(state: LiveState, round: number, now: number): LiveState | null {
  if (state.status !== "playing" || round !== state.round) return null;
  if (now < state.startsAt + state.limitMs + GRACE_MS / 2) return null;
  return resolve(state, now);
}

function resolve(state: LiveState, now: number): LiveState {
  const question = state.questions[state.questionIndex];
  const pending = state.pending;
  const none: Answer = { answerIndex: null, timeMs: state.limitMs };
  const answers: [Answer, Answer] = [strip(pending[0]) ?? none, strip(pending[1]) ?? none];
  const winner = resolveRound(question, answers, state.limitMs);
  const score: [number, number] = [...state.score];
  if (winner !== null) score[winner] += 1;
  const played: LiveState = {
    ...state,
    score,
    rounds: [...state.rounds, { questionIndex: state.questionIndex, answers: answers.map((a) => marked(question, a, state.limitMs)), winner }],
    version: state.version + 1,
  };
  return startNextRound(played, now + REVEAL_MS);
}

function strip(answer: (Answer & { at: number }) | undefined): Answer | undefined {
  return answer ? { answerIndex: answer.answerIndex, timeMs: answer.timeMs } : undefined;
}

/** A player leaves, or is gone long enough for the other to claim the match. */
export function forfeit(state: LiveState, loser: 0 | 1): LiveState | null {
  if (state.status !== "playing") return null;
  return finish(state, loser === 0 ? 1 : 0, loser);
}

/** What the players may see: never an unrevealed answer. */
export function publicView(state: LiveState) {
  const question = state.questions[state.questionIndex];
  const last = state.rounds.at(-1);
  const lastQuestion = last ? state.questions[last.questionIndex] : undefined;
  const pending = state.pending;
  return {
    version: state.version,
    mode: state.mode,
    moduleId: state.moduleId,
    limitMs: state.limitMs,
    order: state.order,
    players: state.players,
    status: state.status,
    score: state.score,
    round: state.status === "playing" && question
      ? { number: state.round, startsAt: state.startsAt, question: { ...question, correctIndex: -1, why: "" } }
      : null,
    locked: [Boolean(pending[0]), Boolean(pending[1])],
    lastReveal: last && lastQuestion
      ? { number: state.rounds.length, questionIndex: last.questionIndex, winner: last.winner, correctIndex: lastQuestion.correctIndex, why: lastQuestion.why, answers: last.answers }
      : null,
    winner: state.winner,
    forfeitedBy: state.forfeitedBy,
  };
}
