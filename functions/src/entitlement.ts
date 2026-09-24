// Ratio Plus (PRD: "Monetisation and B2B"). A student has Plus while an App Store
// subscription is active or a university licence is valid. Both are written only by
// Functions, on users/{uid}.subscription and users/{uid}.licence.

import { getFirestore, Timestamp } from "firebase-admin/firestore";

/**
 * During the beta everyone has Plus, so testers can use every module. config/app
 * .plusForEveryone overrides this (set it to false in the Firebase console at launch);
 * the app reads the same document.
 */
export const BETA_PLUS_FOR_EVERYONE = true;
let cached: { value: boolean; at: number } | undefined;

export async function everyoneHasPlus(): Promise<boolean> {
  if (cached && Date.now() - cached.at < 60_000) return cached.value;
  const doc = await getFirestore().doc("config/app").get();
  const value = (doc.get("plusForEveryone") as boolean | undefined) ?? BETA_PLUS_FOR_EVERYONE;
  cached = { value, at: Date.now() };
  return value;
}

/** Free students get 3 duels a day (PRD); tutorials don't count. */
export const FREE_DUELS_PER_DAY = 3;

interface Dated {
  expiresAt?: Timestamp | null;
  revoked?: boolean;
}

export function isPlus(user: { subscription?: Dated; licence?: Dated } | undefined, now = Date.now()): boolean {
  const active = (e?: Dated) => !!e && !e.revoked && !!e.expiresAt && e.expiresAt.toMillis() > now;
  return active(user?.subscription) || active(user?.licence);
}

/** The modules a student can study in full: all of theirs with Plus, otherwise their free module. */
export function studyModules(user: { modules?: string[]; freeModule?: string; subscription?: Dated; licence?: Dated } | undefined, everyone = false): string[] {
  const modules = user?.modules ?? [];
  if (everyone || isPlus(user)) return modules;
  const free = user?.freeModule && modules.includes(user.freeModule) ? user.freeModule : modules[0];
  return free ? [free] : [];
}
