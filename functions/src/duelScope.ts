// What a duel is played on and for how long. A duel is on one module, or "mixed": the
// student's own modules — its own rating (ratings/{uid}_mixed) and matchmaking pool.
// Between two students, a mixed duel uses the modules they share.

import { getFirestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { duelLessons, MODULES } from "./content.js";
import { DuelQuestion, matchQuestions, questionPool } from "./duel.js";

export const MIXED = "mixed";

/** 15 s a question; 30 s for students who've turned on extra time (Settings → Accessibility). */
export function limitFor(seconds: unknown): number {
  return (seconds === 30 ? 30 : 15) * 1000;
}

/** "mixed" or a module ID. */
export function requireDuelModule(moduleId: unknown): string {
  if (typeof moduleId !== "string" || (moduleId !== MIXED && !MODULES.includes(moduleId))) {
    throw new HttpsError("invalid-argument", "Unknown module.");
  }
  return moduleId;
}

/**
 * The rating gap accepted after waiting `ms`: ±100 at first, widening every 10 s to
 * ±500 at 60 s, then held there.
 */
export function ratingWindow(ms: number): number {
  const steps = Math.min(6, Math.floor(Math.max(0, ms) / 10_000));
  return Math.round(100 + (steps * 400) / 6);
}

const withLessons = new Set(duelLessons.map((l) => l.moduleId));

/** Modules both students take; if they share none, both students' modules together. */
export function sharedModules(a: string[], b: string[]): string[] {
  const shared = a.filter((m) => b.includes(m));
  return shared.length > 0 ? shared : [...new Set([...a, ...b])];
}

export async function studentModules(uid: string): Promise<string[]> {
  const user = await getFirestore().doc(`users/${uid}`).get();
  return ((user.get("modules") as string[] | undefined) ?? []).filter((m) => withLessons.has(m));
}

/** The modules a duel draws on, for one student (sparring) or two. */
export async function duelModules(moduleId: string, uids: string[]): Promise<string[]> {
  if (moduleId !== MIXED) return [moduleId];
  const lists = await Promise.all(uids.map(studentModules));
  const modules = lists.length === 1 ? lists[0] : sharedModules(lists[0], lists[1]);
  if (modules.length === 0) throw new HttpsError("failed-precondition", "Add a module with lessons to play mixed duels.");
  return modules;
}

/** A match's questions from the given modules' lessons, mixed together. */
export function questionsFor(modules: string[]): DuelQuestion[] {
  const lessons = duelLessons.filter((l) => modules.includes(l.moduleId));
  const questions = matchQuestions(questionPool(lessons, Math.random), Math.random);
  if (!questions) throw new HttpsError("failed-precondition", "These modules don't have enough questions for a duel yet.");
  return questions;
}
