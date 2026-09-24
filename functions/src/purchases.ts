// Ratio Plus through the App Store (PRD: "Purchases go through StoreKit 2 and are
// verified by the server"). The app sends each signed transaction; the server checks
// Apple's signature against Apple's root certificates (no API keys), then records the
// subscription. App Store Server Notifications keep it current after renewals,
// cancellations and refunds.

import { readFileSync } from "node:fs";
import { join } from "node:path";
import { Environment, JWSTransactionDecodedPayload, SignedDataVerifier } from "@apple/app-store-server-library";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError, onCall, onRequest } from "firebase-functions/v2/https";

const BUNDLE_ID = "com.mg.ratio";
/**
 * App Store Connect → App Information → Apple ID. Needed to verify Production
 * (App Store) purchases; TestFlight and sandbox purchases verify without it.
 */
const APP_APPLE_ID: number | undefined = undefined;

export const PRODUCTS: Record<string, "monthly" | "annual"> = {
  "com.mg.ratio.plus.monthly": "monthly",
  "com.mg.ratio.plus.annual": "annual",
};

let verifiers: SignedDataVerifier[] | undefined;

/** Sandbox (TestFlight) always; Production once the app's Apple ID is set. */
function allVerifiers(): SignedDataVerifier[] {
  if (verifiers) return verifiers;
  const roots = ["AppleRootCA-G3.cer", "AppleRootCA-G2.cer"].map((f) => readFileSync(join(__dirname, "certs", f)));
  verifiers = [new SignedDataVerifier(roots, true, Environment.SANDBOX, BUNDLE_ID)];
  if (APP_APPLE_ID) verifiers.unshift(new SignedDataVerifier(roots, true, Environment.PRODUCTION, BUNDLE_ID, APP_APPLE_ID));
  return verifiers;
}

async function firstVerified<T>(decode: (v: SignedDataVerifier) => Promise<T>): Promise<T> {
  let lastError: unknown;
  for (const verifier of allVerifiers()) {
    try {
      return await decode(verifier);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError;
}

/**
 * Records a verified transaction on its owner. A subscription belongs to the first Ratio
 * account that presents it, so one purchase can't unlock several accounts.
 */
async function apply(transaction: JWSTransactionDecodedPayload, uid: string | null): Promise<{ active: boolean; expiresAt: string | null }> {
  const productId = transaction.productId ?? "";
  const original = transaction.originalTransactionId;
  if (!PRODUCTS[productId] || !original) throw new HttpsError("invalid-argument", "Not a Ratio Plus purchase.");
  const db = getFirestore();
  const ownerRef = db.doc(`subscriptions/${original}`);

  return db.runTransaction(async (tx) => {
    const owner = await tx.get(ownerRef);
    const ownerUid = (owner.get("uid") as string | undefined) ?? uid;
    if (!ownerUid) return { active: false, expiresAt: null }; // A notification for a purchase never linked to an account.
    if (uid && owner.exists && owner.get("uid") !== uid) {
      throw new HttpsError("already-exists", "This subscription belongs to another Ratio account. Sign in with that account to use it.");
    }
    const expires = transaction.expiresDate ?? 0;
    const revoked = !!transaction.revocationDate;
    const active = !revoked && expires > Date.now();
    if (!owner.exists) tx.set(ownerRef, { uid: ownerUid, createdAt: FieldValue.serverTimestamp() });
    tx.set(db.doc(`users/${ownerUid}`), {
      subscription: {
        productId,
        plan: PRODUCTS[productId],
        originalTransactionId: original,
        expiresAt: Timestamp.fromMillis(expires),
        revoked,
        environment: transaction.environment ?? null,
        updatedAt: FieldValue.serverTimestamp(),
      },
    }, { merge: true });
    return { active, expiresAt: expires ? new Date(expires).toISOString() : null };
  });
}

/** The app sends each transaction it sees (purchase, restore, renewal) as Apple signed it. */
export const verifyPurchase = onCall<{ signedTransaction?: string }>(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  const jws = request.data?.signedTransaction;
  if (typeof jws !== "string" || jws.length > 20_000) throw new HttpsError("invalid-argument", "Missing transaction.");
  let transaction: JWSTransactionDecodedPayload;
  try {
    transaction = await firstVerified((v) => v.verifyAndDecodeTransaction(jws));
  } catch (error) {
    logger.warn("Transaction didn't verify", { uid, error: String(error) });
    throw new HttpsError("permission-denied", "That purchase couldn't be verified.");
  }
  return apply(transaction, uid);
});

/**
 * App Store Server Notifications V2 — paste this function's URL into App Store Connect
 * (App Information → App Store Server Notifications, both Production and Sandbox).
 */
export const appStoreNotifications = onRequest(async (req, res) => {
  const signedPayload = (req.body as { signedPayload?: string } | undefined)?.signedPayload;
  if (req.method !== "POST" || typeof signedPayload !== "string") {
    res.status(400).send("Expected a signed App Store notification.");
    return;
  }
  try {
    const notification = await firstVerified((v) => v.verifyAndDecodeNotification(signedPayload));
    const signed = notification.data?.signedTransactionInfo;
    if (signed) {
      const transaction = await firstVerified((v) => v.verifyAndDecodeTransaction(signed));
      await apply(transaction, null);
    }
    logger.info("App Store notification", { type: notification.notificationType, subtype: notification.subtype ?? null });
    res.status(200).send("OK");
  } catch (error) {
    logger.warn("App Store notification rejected", { error: String(error) });
    res.status(400).send("Not verified.");
  }
});
