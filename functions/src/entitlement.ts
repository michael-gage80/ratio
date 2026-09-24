// Ratio Plus (PRD: "Monetisation and B2B"). A student has Plus while an App Store
// subscription is active or a university licence is valid. Both are written only by
// Functions, on users/{uid}.subscription and users/{uid}.licence.

import { Timestamp } from "firebase-admin/firestore";

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
export function studyModules(user: { modules?: string[]; freeModule?: string; subscription?: Dated; licence?: Dated } | undefined): string[] {
  const modules = user?.modules ?? [];
  if (isPlus(user)) return modules;
  const free = user?.freeModule && modules.includes(user.freeModule) ? user.freeModule : modules[0];
  return free ? [free] : [];
}
