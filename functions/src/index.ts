import { readFileSync } from "node:fs";
import { join } from "node:path";
import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { BankItem, Headline, ItemResponse, priorHeadline, scoreResponses, TopicEstimates } from "./scoring.js";

initializeApp();
setGlobalOptions({ region: "europe-west2", maxInstances: 10 });

// The same bank the app bundles, copied into lib/ at build time, so answers are
// re-graded here rather than trusted from the client.
const bank = JSON.parse(readFileSync(join(__dirname, "diagnostic-bank.json"), "utf8")) as {
  totalItemsServedPerAttempt: number;
  modules: Record<string, { items: BankItem[] }>;
};
const moduleOfItem = new Map<string, string>();
const itemsById = new Map<string, BankItem>();
for (const [moduleId, { items }] of Object.entries(bank.modules)) {
  for (const item of items) {
    itemsById.set(item.itemId, item);
    moduleOfItem.set(item.itemId, moduleId);
  }
}

// Early test profiles stored these before module IDs were aligned with the content.
const LEGACY_MODULE_IDS: Record<string, string> = { "public-law": "public", "land-law": "land", "equity-trusts": "equity" };

interface SubmitDiagnosticRequest {
  skipped?: boolean;
  responses?: ItemResponse[];
}

/**
 * Scores the onboarding diagnostic and writes the student's first profile:
 * users/{uid}/skills/{topicId} for each topic answered, and the headline estimate on
 * users/{uid}. Skipping gives every skill the widest band (diagnostic bank:
 * skippedProfileNote). Idempotent — a completed diagnostic can't be retaken.
 */
export const submitDiagnostic = onCall<SubmitDiagnosticRequest>(async (request): Promise<{ headline: Headline }> => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");

  const db = getFirestore();
  const userRef = db.doc(`users/${uid}`);
  const user = (await userRef.get()).data();
  if (!user?.birthYear || !Array.isArray(user.modules) || user.modules.length === 0) {
    throw new HttpsError("failed-precondition", "Finish the earlier onboarding steps first.");
  }
  if (user.headline) return { headline: user.headline as Headline };

  const skipped = request.data?.skipped === true;
  let topics: TopicEstimates = {};
  let headline = priorHeadline();

  if (!skipped) {
    const responses = validate(request.data?.responses, user.modules as string[]);
    ({ topics, headline } = scoreResponses(responses, itemsById));
  }

  const batch = db.batch();
  for (const [topicId, skills] of Object.entries(topics)) {
    batch.set(userRef.collection("skills").doc(topicId), { ...skills, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
  }
  batch.update(userRef, {
    headline,
    diagnosticSkipped: skipped,
    diagnosticCompletedAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return { headline };
});

function validate(raw: unknown, modules: string[]): ItemResponse[] {
  const allowed = new Set(modules.map((m) => LEGACY_MODULE_IDS[m] ?? m));
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > bank.totalItemsServedPerAttempt) {
    throw new HttpsError("invalid-argument", "Expected between 1 and 10 responses.");
  }
  const seen = new Set<string>();
  return raw.map((r) => {
    const response = r as ItemResponse;
    const moduleId = typeof response?.itemId === "string" ? moduleOfItem.get(response.itemId) : undefined;
    if (!moduleId || !allowed.has(moduleId) || seen.has(response.itemId)) {
      throw new HttpsError("invalid-argument", "A response doesn't match an item for your modules.");
    }
    seen.add(response.itemId);
    return response;
  });
}
