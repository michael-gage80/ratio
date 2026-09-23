// Settling a finished duel for one player (PRD: "Rating: Glicko-2 for each student and
// module"; duel answers move the profile, never the review queue). Split into a read
// and a write so a Firestore transaction can read both players before writing either.

import { DocumentReference, DocumentSnapshot, FieldValue, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { HISTORY_LIMIT, TopicScores } from "./content.js";
import { Answer, DuelQuestion } from "./duel.js";
import { INITIAL, rate, Rating } from "./glicko.js";
import { Estimate, Headline, priorHeadline, SIGMA_PRIOR, Skill, SKILLS, update } from "./scoring.js";

export interface StoredRating extends Rating {
  uid: string;
  moduleId: string;
  duels: number;
  wins: number;
}

/** One player's side of a finished match: each round's question and their answer. */
export interface Side {
  uid: string;
  moduleId: string;
  answers: { question: DuelQuestion; answer: Answer & { correct: boolean } }[];
}

export interface SideState {
  side: Side;
  ratingRef: DocumentReference;
  userRef: DocumentReference;
  skillRefs: DocumentReference[];
  topicIds: string[];
  rating: StoredRating;
  user: DocumentSnapshot;
  skillDocs: DocumentSnapshot[];
}

export interface Settlement {
  ratingBefore: number;
  ratingAfter: number;
  skillMoved: { topicId: string; skill: Skill; before: Estimate; after: Estimate } | null;
}

export async function readSide(tx: Transaction, db: Firestore, side: Side): Promise<SideState> {
  const userRef = db.doc(`users/${side.uid}`);
  const ratingRef = db.doc(`ratings/${side.uid}_${side.moduleId}`);
  const topicIds = [...new Set(side.answers.map((a) => a.question.topicId))];
  const skillRefs = topicIds.map((id) => userRef.collection("skills").doc(id));
  const [ratingDoc, user, ...skillDocs] = await tx.getAll(ratingRef, userRef, ...skillRefs);
  const rating: StoredRating = ratingDoc.exists
    ? (ratingDoc.data() as StoredRating)
    : { ...INITIAL, uid: side.uid, moduleId: side.moduleId, duels: 0, wins: 0 };
  return { side, ratingRef, userRef, skillRefs, topicIds, rating, user, skillDocs };
}

/**
 * Writes the new rating (against `opponent`, with `score` 1/0.5/0 for a win/draw/loss)
 * and moves the profile with every answer the player gave.
 */
export function writeSide(tx: Transaction, state: SideState, opponent: Pick<Rating, "rating" | "rd">, score: 0 | 0.5 | 1): Settlement {
  const { side, rating: before } = state;
  const after = rate(before, opponent, score);

  const headlineBefore = (state.user.get("headline") as Headline | undefined) ?? priorHeadline();
  const headline: Headline = structuredClone(headlineBefore);
  const topics: Record<string, TopicScores> = {};
  state.topicIds.forEach((id, i) => {
    topics[id] = {};
    for (const skill of SKILLS) {
      const estimate = state.skillDocs[i].get(skill) as Estimate | undefined;
      if (estimate) topics[id][skill] = estimate;
    }
  });
  const topicsBefore = structuredClone(topics);
  for (const { question, answer } of side.answers) {
    if (answer.answerIndex === null) continue;
    const topic = topics[question.topicId];
    topic[question.skill] = update(topic[question.skill] ?? { theta: headline[question.skill].theta, sigma: SIGMA_PRIOR }, question.difficulty, answer.correct);
    headline[question.skill] = update(headline[question.skill], question.difficulty, answer.correct);
  }

  // The skill that moved most, for the result screen.
  let skillMoved: Settlement["skillMoved"] = null;
  let biggest = -1;
  for (const id of state.topicIds) {
    for (const skill of SKILLS) {
      const a = topics[id][skill];
      if (!a) continue;
      const b = topicsBefore[id][skill] ?? { theta: headlineBefore[skill].theta, sigma: SIGMA_PRIOR };
      const change = Math.abs(a.theta - b.theta);
      if (change > biggest) {
        biggest = change;
        skillMoved = { topicId: id, skill, before: b, after: a };
      }
    }
  }

  const now = Timestamp.now();
  state.topicIds.forEach((id, i) => {
    if (Object.keys(topics[id]).length === 0) return;
    const history = ((state.skillDocs[i].get("history") as unknown[] | undefined) ?? []).concat({ at: now, ...topics[id] }).slice(-HISTORY_LIMIT);
    tx.set(state.skillRefs[i], { ...topics[id], history, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  });
  if (side.answers.some((a) => a.answer.answerIndex !== null)) {
    tx.update(state.userRef, { headline, headlineUpdatedAt: FieldValue.serverTimestamp() });
  }
  tx.set(state.ratingRef, {
    uid: side.uid,
    moduleId: side.moduleId,
    rating: after.rating,
    rd: after.rd,
    vol: after.vol,
    duels: before.duels + 1,
    wins: before.wins + (score === 1 ? 1 : 0),
    updatedAt: FieldValue.serverTimestamp(),
  });
  return { ratingBefore: Math.round(before.rating), ratingAfter: Math.round(after.rating), skillMoved };
}
