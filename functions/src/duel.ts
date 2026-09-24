// Duels (PRD: "Duel: multiplayer"): first to 3, a timed question per round, four round
// types. The first answer decides the round — right takes the point, wrong gives it to
// the opponent — and if nobody answers in time, nobody scores. Pure functions, shared by
// sparring now and the live referee later.
//
// Questions come from the lessons until the dedicated duel bank arrives: Fastest finger
// from knowledge MCQs, Name the case from case cards, Spot the issue from tap-the-fact.

import { Skill } from "./scoring.js";

export type RoundKind = "fastestFinger" | "nameTheCase" | "spotTheIssue";

export interface Segment {
  text: string;
  /** Set when this phrase is tappable: its index in `options`. */
  option?: number;
}

export interface DuelQuestion {
  id: string;
  kind: RoundKind;
  skill: Skill;
  prompt: string;
  options: string[];
  correctIndex: number;
  /** Spot the issue: the scenario, phrase by phrase. */
  segments?: Segment[];
  /** One line of reasoning for the debrief. */
  why: string;
  lessonId: string;
  topicId: string;
  difficulty: number;
  /** The 2–2 decider. */
  final?: boolean;
}

export interface Answer {
  /** Null when the player didn't answer in time. */
  answerIndex: number | null;
  /** From the question appearing to the tap, measured on the device. */
  timeMs: number;
}

export interface Round {
  questionIndex: number;
  answers: [Answer & { correct: boolean }, Answer & { correct: boolean }];
  /** 0 or 1 for the player who took the point, or null. */
  winner: 0 | 1 | null;
}

export interface MatchOutcome {
  rounds: Round[];
  score: [number, number];
  /** 0 or 1, or null for a draw. */
  winner: 0 | 1 | null;
}

export const POINTS_TO_WIN = 3;
export const REGULAR_ROUNDS = 8;
/** Faster than this can't be a considered tap (PRD: "rejects impossible values"). */
export const MIN_ANSWER_MS = 250;
const ORDER: RoundKind[] = ["nameTheCase", "spotTheIssue", "fastestFinger"];
export const TUTORIAL_ORDER: RoundKind[] = ["fastestFinger", "nameTheCase", "spotTheIssue"];
/** What to play instead when a module has no questions of the scheduled type. */
const FALLBACK: RoundKind[] = ["fastestFinger", "spotTheIssue", "nameTheCase"];

// MARK: - Rounds

/** An answer that counts: given, in time, and humanly possible. */
function counts(answer: Answer, limitMs: number): boolean {
  return answer.answerIndex !== null && answer.timeMs >= MIN_ANSWER_MS && answer.timeMs <= limitMs;
}

/** The first answer decides: right takes the point, wrong gives it away. */
export function resolveRound(question: DuelQuestion, answers: [Answer, Answer], limitMs: number): Round["winner"] {
  const valid = ([0, 1] as const).filter((p) => counts(answers[p], limitMs));
  if (valid.length === 0) return null;
  const correct = (p: 0 | 1) => answers[p].answerIndex === question.correctIndex;
  const [first, second] = [...valid].sort((a, b) => answers[a].timeMs - answers[b].timeMs);
  if (second !== undefined && answers[first].timeMs === answers[second].timeMs) {
    // A dead heat: only a lone right answer scores.
    return correct(first) === correct(second) ? null : correct(first) ? first : second;
  }
  return correct(first) ? first : first === 0 ? 1 : 0;
}

/**
 * The question for the next round, or null when the match is over: regular rounds in
 * order, then the final — played only at 2–2, and always the last round.
 */
export function nextQuestionIndex(questions: DuelQuestion[], score: [number, number], regularPlayed: number, finalPlayed: boolean): number | null {
  if (Math.max(...score) >= POINTS_TO_WIN || finalPlayed) return null;
  const finalIndex = questions.findIndex((q) => q.final);
  if (score[0] === POINTS_TO_WIN - 1 && score[1] === POINTS_TO_WIN - 1 && finalIndex >= 0) return finalIndex;
  const regular = questions.map((_, i) => i).filter((i) => i !== finalIndex);
  return regular[regularPlayed] ?? null;
}

/** Whether an answer counts and is right. */
export function marked(question: DuelQuestion, answer: Answer, limitMs: number): Answer & { correct: boolean } {
  return { ...answer, correct: counts(answer, limitMs) && answer.answerIndex === question.correctIndex };
}

/**
 * Plays a match through, asking `answerFor` for each player's answer to each round.
 * Used for sparring (the partner's plan is per question) and async challenges (both
 * players answered every question in advance).
 */
export function playMatchWith(
  questions: DuelQuestion[],
  answerFor: (player: 0 | 1, questionIndex: number, round: number) => Answer | undefined,
  limitMs: number,
): MatchOutcome {
  const score: [number, number] = [0, 0];
  const rounds: Round[] = [];
  let regularPlayed = 0;
  let finalPlayed = false;
  const none: Answer = { answerIndex: null, timeMs: limitMs };
  for (;;) {
    const questionIndex = nextQuestionIndex(questions, score, regularPlayed, finalPlayed);
    if (questionIndex === null) break;
    const question = questions[questionIndex];
    if (question.final) finalPlayed = true;
    else regularPlayed += 1;
    const answers: [Answer, Answer] = [answerFor(0, questionIndex, rounds.length) ?? none, answerFor(1, questionIndex, rounds.length) ?? none];
    const winner = resolveRound(question, answers, limitMs);
    if (winner !== null) score[winner] += 1;
    rounds.push({ questionIndex, answers: [marked(question, answers[0], limitMs), marked(question, answers[1], limitMs)], winner });
  }
  const winner = score[0] === score[1] ? null : score[0] > score[1] ? 0 : 1;
  return { rounds, score, winner };
}

/** A sparring match: the student's answers by round, the partner's by question. */
export function playMatch(questions: DuelQuestion[], playerAnswers: Answer[], opponentPlan: Answer[], limitMs: number): MatchOutcome {
  return playMatchWith(questions, (player, questionIndex, round) => (player === 0 ? playerAnswers[round] : opponentPlan[questionIndex]), limitMs);
}

// MARK: - Sparring partners

/** Five bands (PRD: "Bots in 5 difficulty bands"), until real play calibrates them. */
export const SPARRING_LEVELS = [
  { accuracy: 0.45, meanSeconds: 6.5, rating: 1000 },
  { accuracy: 0.55, meanSeconds: 5.5, rating: 1150 },
  { accuracy: 0.65, meanSeconds: 4.6, rating: 1300 },
  { accuracy: 0.75, meanSeconds: 3.8, rating: 1450 },
  { accuracy: 0.85, meanSeconds: 3.0, rating: 1600 },
] as const;
export const SPARRING_RD = 60;

/** How a sparring partner of `level` (1–5) will answer each question. */
export function sparringPlan(questions: DuelQuestion[], level: number, limitMs: number, random: () => number): Answer[] {
  const band = SPARRING_LEVELS[Math.min(Math.max(level, 1), 5) - 1];
  const scale = limitMs / 10_000; // Extended time slows the partner equally.
  return questions.map((question) => {
    if (random() < 0.05) return { answerIndex: null, timeMs: limitMs };
    const gaussian = Math.sqrt(-2 * Math.log(1 - random())) * Math.cos(2 * Math.PI * random());
    const seconds = Math.min(Math.max(band.meanSeconds + gaussian * 1.3, 1.2), 9.7) * scale;
    const right = random() < band.accuracy;
    const wrong = question.options.map((_, i) => i).filter((i) => i !== question.correctIndex);
    return {
      answerIndex: right ? question.correctIndex : wrong[Math.floor(random() * wrong.length)],
      timeMs: Math.round(seconds * 1000),
    };
  });
}

// MARK: - Questions

interface CaseCard {
  type: "caseCard";
  caseName: string;
  factsShort: string;
  ratioShort: string;
}

export interface DuelLesson {
  lessonId: string;
  moduleId: string;
  topicId: string;
  lecture: { parts: { components: { type: string }[] }[] };
  testPool: {
    itemId: string;
    type: string;
    skillTag: Skill;
    difficultyStart: number;
    prompt: string;
    options?: string[];
    correctIndex?: number;
    trapExplanation?: string;
    explanation?: string;
    scenarioText?: string;
    tappableSpans?: string[];
    correctSpan?: string;
  }[];
}

export function shuffled<T>(values: readonly T[], random: () => number): T[] {
  const copy = [...values];
  for (let i = copy.length - 1; i > 0; i--) {
    const j = Math.floor(random() * (i + 1));
    [copy[i], copy[j]] = [copy[j], copy[i]];
  }
  return copy;
}

/** The scenario cut at each tappable phrase; runs of bare punctuation are dropped. */
export function segments(text: string, spans: string[]): Segment[] | null {
  const lower = text.toLowerCase();
  const found = spans.map((span) => ({ span, at: lower.indexOf(span.toLowerCase()) }));
  if (found.some((f) => f.at < 0)) return null;
  found.sort((a, b) => a.at - b.at);
  const out: Segment[] = [];
  let cursor = 0;
  const plain = (from: number, to: number) => {
    const piece = text.slice(from, to).replace(/^[\s,;:.]+|[\s,;:]+$/gu, "");
    if (/[\p{L}\p{N}]/u.test(piece)) out.push({ text: piece });
  };
  found.forEach(({ span, at }, option) => {
    if (at < cursor) return; // Overlapping spans: keep the first.
    plain(cursor, at);
    out.push({ text: text.slice(at, at + span.length), option });
    cursor = at + span.length;
  });
  plain(cursor, text.length);
  return out;
}

/** Every question a module's lessons can give, by round type. */
export function questionPool(lessons: DuelLesson[], random: () => number): Record<RoundKind, DuelQuestion[]> {
  const pool: Record<RoundKind, DuelQuestion[]> = { fastestFinger: [], nameTheCase: [], spotTheIssue: [] };
  const cases = new Map<string, { card: CaseCard; lesson: DuelLesson }>();

  for (const lesson of lessons) {
    for (const part of lesson.lecture.parts) {
      for (const component of part.components) {
        if (component.type === "caseCard") {
          const card = component as CaseCard;
          if (card.caseName && card.factsShort && !cases.has(card.caseName)) cases.set(card.caseName, { card, lesson });
        }
      }
    }
    for (const item of lesson.testPool) {
      const base = { lessonId: lesson.lessonId, topicId: lesson.topicId, difficulty: item.difficultyStart, prompt: item.prompt };
      if ((item.type === "mcqWithTrap" || item.type === "quickCheck") && item.skillTag === "knowledge"
        && (item.options?.length ?? 0) >= 3 && item.correctIndex !== undefined) {
        pool.fastestFinger.push({
          ...base,
          id: item.itemId,
          kind: "fastestFinger",
          skill: "knowledge",
          options: item.options!,
          correctIndex: item.correctIndex,
          why: item.trapExplanation ?? item.explanation ?? `The answer is ${item.options![item.correctIndex]}.`,
        });
      }
      if (item.type === "tapTheFact" && item.scenarioText && item.tappableSpans && item.correctSpan) {
        const cut = segments(item.scenarioText, item.tappableSpans);
        const options = cut?.filter((s) => s.option !== undefined).map((s) => s.text) ?? [];
        const correctIndex = options.findIndex((o) => o.toLowerCase() === item.correctSpan!.toLowerCase());
        if (cut && correctIndex >= 0) {
          pool.spotTheIssue.push({
            ...base,
            id: item.itemId,
            kind: "spotTheIssue",
            skill: "application",
            options,
            correctIndex,
            segments: cut,
            why: item.explanation ?? `The deciding fact: “${item.correctSpan}”.`,
          });
        }
      }
    }
  }

  const names = [...cases.keys()];
  if (names.length >= 4) {
    for (const [name, { card, lesson }] of cases) {
      const options = shuffled([name, ...shuffled(names.filter((n) => n !== name), random).slice(0, 3)], random);
      pool.nameTheCase.push({
        id: `case:${name}`,
        kind: "nameTheCase",
        skill: "understanding",
        prompt: card.factsShort,
        options,
        correctIndex: options.indexOf(name),
        why: `${name}: ${card.ratioShort}`,
        lessonId: lesson.lessonId,
        topicId: lesson.topicId,
        difficulty: 0.5,
      });
    }
  }
  return pool;
}

/** A match's questions: regular rounds cycling through the types, then the final. */
export function matchQuestions(pool: Record<RoundKind, DuelQuestion[]>, random: () => number, tutorial = false): DuelQuestion[] | null {
  const decks = Object.fromEntries(
    (Object.keys(pool) as RoundKind[]).map((kind) => [kind, shuffled(pool[kind], random)]),
  ) as Record<RoundKind, DuelQuestion[]>;
  const order = tutorial ? TUTORIAL_ORDER : Array.from({ length: REGULAR_ROUNDS }, (_, i) => ORDER[i % ORDER.length]);
  const questions: DuelQuestion[] = [];
  for (const kind of order) {
    // A module short of one round type (Jurisprudence has no case cards) plays another.
    const question = decks[kind].shift() ?? FALLBACK.map((k) => decks[k].shift()).find(Boolean);
    if (!question) return null;
    questions.push(question);
  }
  if (!tutorial) {
    const kinds = shuffled(ORDER, random);
    const final = kinds.map((k) => decks[k].shift()).find(Boolean);
    if (!final) return null;
    questions.push({ ...final, final: true });
  }
  return questions;
}
