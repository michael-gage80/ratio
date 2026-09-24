// Account and plan actions from Settings (PRD: "Me tab and settings", "UK GDPR"):
// export, reset, delete; the free module; university licence codes; the free tier's
// daily duel allowance; and push notifications for challenges.

import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { londonDate } from "./brief.js";
import { MODULES } from "./content.js";
import { FREE_DUELS_PER_DAY, isPlus } from "./entitlement.js";

/** What reset clears and delete removes, under users/{uid}. */
const PROGRESS = ["skills", "items", "lessons", "testAttempts", "briefs", "activity"];
const EVERYTHING = [...PROGRESS, "friends", "blocked", "devices", "usage"];

function requireAuth(uid: string | undefined): string {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  return uid;
}

/** UK GDPR data export: everything held about the student, as JSON. */
export const exportData = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const db = getFirestore();
  const user = await db.doc(`users/${uid}`).get();
  const collections: Record<string, unknown[]> = {};
  for (const name of EVERYTHING) {
    const snapshot = await db.collection(`users/${uid}/${name}`).get();
    collections[name] = snapshot.docs.map((d) => ({ id: d.id, ...d.data() }));
  }
  const [ratings, matches] = await Promise.all([
    db.collection("ratings").where("uid", "==", uid).get(),
    db.collection("matches").where("players", "array-contains", uid).get(),
  ]);
  const json = JSON.stringify({
    exportedAt: new Date().toISOString(),
    account: { uid, email: request.auth?.token.email ?? null },
    profile: user.data() ?? null,
    ...collections,
    ratings: ratings.docs.map((d) => ({ id: d.id, ...d.data() })),
    matches: matches.docs.map((d) => ({ id: d.id, ...d.data() })),
  }, (_, value) => (value instanceof Timestamp ? value.toDate().toISOString() : value), 2);
  return { json };
});

/** Clears scores, reviews, briefs and history; keeps the account, profile and plan. */
export const resetProgress = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const db = getFirestore();
  for (const name of PROGRESS) await db.recursiveDelete(db.collection(`users/${uid}/${name}`));
  await db.doc(`users/${uid}`).update({ headline: FieldValue.delete(), headlineUpdatedAt: FieldValue.delete() });
  return { ok: true };
});

/**
 * Deletes the account (PRD: "delete account in the app"). Removes the student's data,
 * ratings, board entries and photo, anonymises their name in opponents' match history,
 * and deletes the sign-in. Runs at once, well inside the 30 days the PRD allows.
 */
export const deleteAccount = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const db = getFirestore();
  await db.recursiveDelete(db.doc(`users/${uid}`));
  const [ratings, entries, matches] = await Promise.all([
    db.collection("ratings").where("uid", "==", uid).get(),
    db.collectionGroup("entries").where("uid", "==", uid).get(),
    db.collection("matches").where("players", "array-contains", uid).get(),
  ]);
  const writer = db.bulkWriter();
  ratings.docs.forEach((d) => writer.delete(d.ref));
  entries.docs.forEach((d) => writer.delete(d.ref));
  matches.docs.forEach((d) => writer.update(d.ref, { [`names.${uid}`]: "Deleted student" }));
  await writer.close();
  await getStorage().bucket().deleteFiles({ prefix: `avatars/${uid}/` }).catch(() => undefined);
  await getAuth().deleteUser(uid);
  logger.info("Account deleted", { uid });
  return { ok: true };
});

/**
 * Chooses the one module a free student studies in full (PRD: "1 full module of the
 * student's choice"). It can be changed once, so the free tier can't rotate through all.
 */
export const chooseFreeModule = onCall<{ moduleId?: string }>(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const moduleId = request.data?.moduleId;
  if (typeof moduleId !== "string" || !MODULES.includes(moduleId)) throw new HttpsError("invalid-argument", "Unknown module.");
  const ref = getFirestore().doc(`users/${uid}`);
  await getFirestore().runTransaction(async (tx) => {
    const user = await tx.get(ref);
    if (!(user.get("modules") as string[] | undefined)?.includes(moduleId)) throw new HttpsError("failed-precondition", "Choose one of your modules.");
    const current = user.get("freeModule") as string | undefined;
    if (current === moduleId) return;
    const changes = (user.get("freeModuleChanges") as number | undefined) ?? 0;
    if (current && changes >= 1) throw new HttpsError("failed-precondition", "You've already changed your free module once.");
    tx.update(ref, { freeModule: moduleId, ...(current ? { freeModuleChanges: changes + 1 } : {}) });
  });
  return { ok: true };
});

/**
 * University licence codes (PRD: "licences are activated with a university code plus a
 * university email check"). licences/{code}: universityName, emailDomains, seats, used,
 * expiresAt — created with content-tools/admin.mjs.
 */
export const redeemLicence = onCall<{ code?: string }>(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const code = String(request.data?.code ?? "").trim().toUpperCase().replace(/[^A-Z0-9-]/g, "");
  if (code.length < 4 || code.length > 40) throw new HttpsError("invalid-argument", "Check the code and try again.");
  const email = (request.auth?.token.email as string | undefined)?.toLowerCase();
  const verified = request.auth?.token.email_verified === true;
  const db = getFirestore();
  const licenceRef = db.doc(`licences/${code}`);
  return db.runTransaction(async (tx) => {
    const [licence, seat] = await tx.getAll(licenceRef, licenceRef.collection("students").doc(uid));
    if (!licence.exists) throw new HttpsError("not-found", "That code isn't recognised.");
    const expiresAt = licence.get("expiresAt") as Timestamp;
    if (expiresAt.toMillis() < Date.now()) throw new HttpsError("failed-precondition", "That licence has expired.");
    const domains = (licence.get("emailDomains") as string[]).map((d) => d.toLowerCase());
    const domain = email?.split("@")[1];
    if (!verified || !domain || !domains.some((d) => domain === d || domain.endsWith(`.${d}`))) {
      throw new HttpsError("permission-denied", `Sign in with your verified university email (${domains.map((d) => `@${d}`).join(" or ")}) to use this code.`);
    }
    if (!seat.exists) {
      if ((licence.get("used") as number) >= (licence.get("seats") as number)) throw new HttpsError("resource-exhausted", "All the licences for this code are in use.");
      tx.update(licenceRef, { used: FieldValue.increment(1) });
      tx.set(seat.ref, { email, at: FieldValue.serverTimestamp() });
    }
    tx.set(db.doc(`users/${uid}`), {
      licence: { code, universityName: licence.get("universityName"), expiresAt, revoked: false },
    }, { merge: true });
    return { universityName: licence.get("universityName") as string, expiresAt: expiresAt.toDate().toISOString() };
  });
});

/** Whether the student can start another duel today (without counting one). */
export async function checkDuel(uid: string): Promise<void> {
  const db = getFirestore();
  const [user, usage] = await db.getAll(db.doc(`users/${uid}`), db.doc(`users/${uid}/usage/${londonDate(new Date())}`));
  if (!isPlus(user.data()) && ((usage.get("duels") as number | undefined) ?? 0) >= FREE_DUELS_PER_DAY) {
    throw new HttpsError("resource-exhausted", `Free plans include ${FREE_DUELS_PER_DAY} duels a day. Ratio Plus makes them unlimited.`, { reason: "free-limit" });
  }
}

/**
 * Counts a duel against today's free allowance, or refuses it (PRD: "Duels: 3 a day"
 * free, unlimited with Plus). Tutorials never call this.
 */
export async function countDuel(uid: string): Promise<void> {
  const db = getFirestore();
  const userRef = db.doc(`users/${uid}`);
  const usageRef = userRef.collection("usage").doc(londonDate(new Date()));
  await db.runTransaction(async (tx) => {
    const [user, usage] = await tx.getAll(userRef, usageRef);
    const duels = (usage.get("duels") as number | undefined) ?? 0;
    if (!isPlus(user.data()) && duels >= FREE_DUELS_PER_DAY) {
      throw new HttpsError("resource-exhausted", `Free plans include ${FREE_DUELS_PER_DAY} duels a day. Ratio Plus makes them unlimited.`, { reason: "free-limit" });
    }
    tx.set(usageRef, { duels: duels + 1 }, { merge: true });
  });
}

/** At most 3 challenge pushes a day (PRD: "Duel challenge ... At most 3 a day"). */
const PUSHES_PER_DAY = 3;

/** Sends a push to all the student's devices, within the daily cap. Never throws. */
export async function notify(uid: string, title: string, body: string, data: Record<string, string>): Promise<void> {
  try {
    const db = getFirestore();
    const usageRef = db.doc(`users/${uid}/usage/${londonDate(new Date())}`);
    const allowed = await db.runTransaction(async (tx) => {
      const pushes = ((await tx.get(usageRef)).get("pushes") as number | undefined) ?? 0;
      if (pushes >= PUSHES_PER_DAY) return false;
      tx.set(usageRef, { pushes: pushes + 1 }, { merge: true });
      return true;
    });
    if (!allowed) return;
    const devices = await db.collection(`users/${uid}/devices`).get();
    const tokens = devices.docs.map((d) => d.id);
    if (tokens.length === 0) return;
    const result = await getMessaging().sendEachForMulticast({ tokens, notification: { title, body }, data, apns: { payload: { aps: { sound: "default" } } } });
    // Forget tokens the phone has thrown away.
    await Promise.all(result.responses.map((r, i) =>
      !r.success && /registration-token-not-registered|invalid-argument/.test(r.error?.code ?? "") ? devices.docs[i].ref.delete() : undefined));
  } catch (error) {
    logger.warn("Push failed", { uid, error: String(error) });
  }
}
