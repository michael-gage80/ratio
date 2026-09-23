// Security rules for users/{uid}. Run against the emulator:
//   firebase emulators:exec --only firestore "npm --prefix firestore-tests test"
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { deleteDoc, deleteField, doc, getDoc, serverTimestamp, setDoc, updateDoc } from 'firebase/firestore';

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
const amara = () => doc(db('amara'), 'users/amara');
const thisYear = new Date().getFullYear();

/** Seeds users/amara directly, bypassing the rules. */
const seed = (data) =>
  env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'users/amara'), { createdAt: new Date(), ...data }));

const passAgeGate = { birthYear: thisYear - 20, ageConfirmedAt: serverTimestamp() };

describe('creating the user document', () => {
  test('a student can create their own with a server timestamp', async () => {
    await assertSucceeds(setDoc(amara(), { createdAt: serverTimestamp() }));
  });

  test("a student can't create someone else's", async () => {
    await assertFails(setDoc(doc(db('amara'), 'users/zara'), { createdAt: serverTimestamp() }));
  });

  test("the create can't smuggle in other fields or a client-chosen time", async () => {
    await assertFails(setDoc(amara(), { createdAt: serverTimestamp(), plan: 'plus' }));
    await assertFails(setDoc(amara(), { createdAt: new Date(0) }));
  });

  test('signed-out clients can do nothing', async () => {
    await assertFails(setDoc(doc(db(null), 'users/amara'), { createdAt: serverTimestamp() }));
    await assertFails(getDoc(doc(db(null), 'users/amara')));
  });
});

describe('reading', () => {
  test('a student reads only their own document', async () => {
    await seed({});
    await assertSucceeds(getDoc(amara()));
    await assertFails(getDoc(doc(db('zara'), 'users/amara')));
  });
});

describe('the age gate', () => {
  test('an adult birth year with a server timestamp passes', async () => {
    await seed({});
    await assertSucceeds(updateDoc(amara(), passAgeGate));
  });

  test('an under-18 birth year is rejected', async () => {
    await seed({});
    await assertFails(updateDoc(amara(), { birthYear: thisYear - 16, ageConfirmedAt: serverTimestamp() }));
  });

  test('nothing else can be saved before the gate is passed', async () => {
    await seed({});
    await assertFails(updateDoc(amara(), { displayName: 'Amara' }));
    await assertFails(updateDoc(amara(), { ...passAgeGate, displayName: 'Amara' }));
  });

  test('the gate needs the server time and a whole-number year', async () => {
    await seed({});
    await assertFails(updateDoc(amara(), { birthYear: thisYear - 20, ageConfirmedAt: new Date() }));
    await assertFails(updateDoc(amara(), { birthYear: String(thisYear - 20), ageConfirmedAt: serverTimestamp() }));
  });

  test("the birth year can't be changed once set", async () => {
    await seed({ birthYear: thisYear - 20 });
    await assertFails(updateDoc(amara(), { birthYear: thisYear - 30 }));
  });
});

describe('profile fields after the gate', () => {
  test('name, initial, programme and waitlist can be saved', async () => {
    await seed({ birthYear: thisYear - 20 });
    await assertSucceeds(updateDoc(amara(), { displayName: 'Amara', initial: 'O' }));
    await assertSucceeds(updateDoc(amara(), { programme: 'llb', waitlist: ['sqe'] }));
  });

  test('the initial can be removed, but must be one capital letter if present', async () => {
    await seed({ birthYear: thisYear - 20, displayName: 'Amara', initial: 'O' });
    await assertSucceeds(updateDoc(amara(), { initial: deleteField() }));
    await assertFails(updateDoc(amara(), { initial: 'ok' }));
    await assertFails(updateDoc(amara(), { initial: 'o' }));
  });

  test('names must be 1–40 characters', async () => {
    await seed({ birthYear: thisYear - 20 });
    await assertFails(updateDoc(amara(), { displayName: '' }));
    await assertFails(updateDoc(amara(), { displayName: 'A'.repeat(41) }));
  });

  test('only LLB and known waitlist programmes are accepted', async () => {
    await seed({ birthYear: thisYear - 20 });
    await assertFails(updateDoc(amara(), { programme: 'sqe' }));
    await assertFails(updateDoc(amara(), { waitlist: ['mba'] }));
  });

  test('unknown fields are rejected', async () => {
    await seed({ birthYear: thisYear - 20 });
    await assertFails(updateDoc(amara(), { plan: 'plus' }));
  });
});

describe('university, year and modules', () => {
  test('a listed university, or free text for an unlisted one, can be saved', async () => {
    await seed({ birthYear: thisYear - 20 });
    await assertSucceeds(updateDoc(amara(), { universityId: 'university-college-london' }));
    await assertSucceeds(updateDoc(amara(), { universityOther: 'Ruskin College', universityId: deleteField() }));
  });

  test("a listed and an unlisted university can't both be set", async () => {
    await seed({ birthYear: thisYear - 20, universityId: 'university-of-leeds' });
    await assertFails(updateDoc(amara(), { universityOther: 'Somewhere else' }));
  });

  test('university IDs and free text are validated', async () => {
    await seed({ birthYear: thisYear - 20 });
    await assertFails(updateDoc(amara(), { universityId: 'Not An ID!' }));
    await assertFails(updateDoc(amara(), { universityOther: 'X' }));
    await assertFails(updateDoc(amara(), { universityOther: 'X'.repeat(81) }));
  });

  test('year is 1, 2 or 3 and modules are known and non-empty', async () => {
    await seed({ birthYear: thisYear - 20 });
    await assertSucceeds(updateDoc(amara(), { year: 2, modules: ['crime', 'tort', 'public'] }));
    await assertFails(updateDoc(amara(), { year: 4 }));
    await assertFails(updateDoc(amara(), { year: '2' }));
    await assertFails(updateDoc(amara(), { modules: [] }));
    await assertFails(updateDoc(amara(), { modules: ['crime', 'family'] }));
  });

  test("can't be saved before the age gate", async () => {
    await seed({});
    await assertFails(updateDoc(amara(), { universityId: 'university-of-leeds' }));
    await assertFails(updateDoc(amara(), { year: 1, modules: ['crime'] }));
  });
});

describe('deleting', () => {
  test('an account that never passed the age gate can be removed by its owner', async () => {
    await seed({});
    await assertSucceeds(deleteDoc(amara()));
  });

  test('once the gate is passed, the document can only be deleted server-side', async () => {
    await seed({ birthYear: thisYear - 20 });
    await assertFails(deleteDoc(amara()));
  });
});

describe('scores', () => {
  test('a student can read their own skill estimates but never write them', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'users/amara/skills/crime.homicide.murder'), { knowledge: { theta: 0, sigma: 1 } }));
    await assertSucceeds(getDoc(doc(db('amara'), 'users/amara/skills/crime.homicide.murder')));
    await assertFails(getDoc(doc(db('zara'), 'users/amara/skills/crime.homicide.murder')));
    await assertFails(setDoc(doc(db('amara'), 'users/amara/skills/crime.homicide.murder'), { knowledge: { theta: 9, sigma: 0.1 } }));
  });

  test("the headline profile on the user document can't be written by the client", async () => {
    await seed({ birthYear: thisYear - 20 });
    await assertFails(updateDoc(amara(), { headline: { knowledge: { theta: 9, sigma: 0.1 } } }));
    await assertFails(updateDoc(amara(), { diagnosticCompletedAt: serverTimestamp() }));
  });
});

describe('lesson progress', () => {
  const progress = (uid, lessonId = 'crime-03') => doc(db(uid), `users/${uid}/lessons/${lessonId}`);

  test('a student can save and read their own lecture progress', async () => {
    await assertSucceeds(setDoc(progress('amara'), { partsCompleted: 2, updatedAt: serverTimestamp() }));
    await assertSucceeds(getDoc(progress('amara')));
    await assertFails(getDoc(doc(db('zara'), 'users/amara/lessons/crime-03')));
  });

  test("progress can't be written for someone else, a malformed lesson ID, or with extra fields", async () => {
    await assertFails(setDoc(doc(db('zara'), 'users/amara/lessons/crime-03'), { partsCompleted: 1, updatedAt: serverTimestamp() }));
    await assertFails(setDoc(progress('amara', 'not a lesson'), { partsCompleted: 1, updatedAt: serverTimestamp() }));
    await assertFails(setDoc(progress('amara'), { partsCompleted: 1, updatedAt: serverTimestamp(), score: 100 }));
  });

  test('progress must be a small whole number with the server time', async () => {
    await assertFails(setDoc(progress('amara'), { partsCompleted: 99, updatedAt: serverTimestamp() }));
    await assertFails(setDoc(progress('amara'), { partsCompleted: '2', updatedAt: serverTimestamp() }));
    await assertFails(setDoc(progress('amara'), { partsCompleted: 2, updatedAt: new Date(0) }));
  });
});

describe('everything else', () => {
  test('is denied', async () => {
    await assertFails(setDoc(doc(db('amara'), 'boards/weekly_everyone'), { rank: 1 }));
  });
});
