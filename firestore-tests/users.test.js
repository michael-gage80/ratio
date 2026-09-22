// Security rules for users/{uid}. Run against the emulator:
//   firebase emulators:exec --only firestore "npm --prefix firestore-tests test"
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, serverTimestamp, setDoc, updateDoc } from 'firebase/firestore';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-ratio',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});

beforeEach(() => env.clearFirestore());
after(() => env.cleanup());

const db = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

test('a student can create their own user document with a server timestamp', async () => {
  await assertSucceeds(setDoc(doc(db('amara'), 'users/amara'), { createdAt: serverTimestamp() }));
});

test("a student can't create someone else's user document", async () => {
  await assertFails(setDoc(doc(db('amara'), 'users/zara'), { createdAt: serverTimestamp() }));
});

test("the create can't smuggle in other fields or a client-chosen time", async () => {
  await assertFails(setDoc(doc(db('amara'), 'users/amara'), { createdAt: serverTimestamp(), plan: 'plus' }));
  await assertFails(setDoc(doc(db('amara'), 'users/amara'), { createdAt: new Date(0) }));
});

test('signed-out clients can do nothing', async () => {
  await assertFails(setDoc(doc(db(null), 'users/amara'), { createdAt: serverTimestamp() }));
  await assertFails(getDoc(doc(db(null), 'users/amara')));
});

test("a student reads only their own document, and can't update or delete it yet", async () => {
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'users/amara'), { createdAt: new Date() }));
  await assertSucceeds(getDoc(doc(db('amara'), 'users/amara')));
  await assertFails(getDoc(doc(db('zara'), 'users/amara')));
  await assertFails(updateDoc(doc(db('amara'), 'users/amara'), { plan: 'plus' }));
  await assertFails(deleteDoc(doc(db('amara'), 'users/amara')));
});

test('everything outside users/{uid} is denied', async () => {
  await assertFails(setDoc(doc(db('amara'), 'boards/weekly_everyone'), { rank: 1 }));
  await assertFails(setDoc(doc(db('amara'), 'users/amara/skills/crime'), { theta: 99 }));
});
