// How many students have the app open, for the Duel card's "N online". The app keeps
// /online/{uid} set while it's in the foreground (removed on disconnect); every five
// minutes this counts them into /stats/online and clears any left behind.

import { getDatabaseWithUrl } from "firebase-admin/database";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";

const DATABASE_URL = "https://ratio-91a04-default-rtdb.europe-west1.firebasedatabase.app";
/** An entry older than this belongs to a phone that went away without disconnecting. */
const STALE_MS = 15 * 60 * 1000;

/** Counts the fresh entries and returns the stale ones to remove. */
export function tally(entries: Record<string, unknown>, now: number): { online: number; stale: string[] } {
  const stale = Object.entries(entries)
    .filter(([, at]) => typeof at !== "number" || now - at > STALE_MS)
    .map(([uid]) => uid);
  return { online: Object.keys(entries).length - stale.length, stale };
}

export const countOnline = onSchedule({ schedule: "every 5 minutes", timeZone: "Europe/London" }, async () => {
  const db = getDatabaseWithUrl(DATABASE_URL);
  const now = Date.now();
  const { online, stale } = tally(((await db.ref("online").get()).val() ?? {}) as Record<string, unknown>, now);
  await db.ref().update({ "stats/online": { count: online, at: now }, ...Object.fromEntries(stale.map((uid) => [`online/${uid}`, null])) });
  logger.info("Counted online students", { online, stale: stale.length });
});
