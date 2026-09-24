// Security rules for users/{uid}. Run against the emulator:
//   firebase emulators:exec --only firestore "npm --prefix firestore-tests test"
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { addDoc, collection, deleteDoc, deleteField, doc, getDoc, serverTimestamp, setDoc, updateDoc } from 'firebase/firestore';

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
    await assertSucceeds(updateDoc(amara(), { modules: ['companylaw', 'eulaw', 'humanrights', 'jurisprudence'] }));
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

describe('review schedules and test attempts', () => {
  test('are readable by their owner and writable by no client', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/amara/items/crime-03-test-01'), { due: new Date(), stability: 3 });
      await setDoc(doc(ctx.firestore(), 'users/amara/testAttempts/a1'), { lessonId: 'crime-03' });
    });
    for (const path of ['users/amara/items/crime-03-test-01', 'users/amara/testAttempts/a1']) {
      await assertSucceeds(getDoc(doc(db('amara'), path)));
      await assertFails(getDoc(doc(db('zara'), path)));
      await assertFails(setDoc(doc(db('amara'), path), { due: new Date(), stability: 999 }));
    }
  });
});

describe('daily briefs', () => {
  test('are readable by their owner and writable by no client', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users/amara/briefs/2026-09-23'), { steps: [] });
    });
    await assertSucceeds(getDoc(doc(db('amara'), 'users/amara/briefs/2026-09-23')));
    await assertFails(getDoc(doc(db('zara'), 'users/amara/briefs/2026-09-23')));
    await assertFails(setDoc(doc(db('amara'), 'users/amara/briefs/2026-09-24'), { steps: [] }));
  });
});

describe('activity', () => {
  const today = new Date().toISOString().slice(0, 10);
  const day = (uid, date = today) => doc(db(uid), `users/${uid}/activity/${date}`);

  test('a student can mark and read their own active days', async () => {
    await assertSucceeds(setDoc(day('amara'), { at: serverTimestamp() }));
    await assertSucceeds(setDoc(day('amara'), { at: serverTimestamp() }));
    await assertSucceeds(getDoc(day('amara')));
    await assertFails(getDoc(doc(db('zara'), `users/amara/activity/${today}`)));
  });

  test("days can't be backdated, forged for others, or carry anything else", async () => {
    await assertFails(setDoc(day('amara'), { at: new Date(0) }));
    await assertFails(setDoc(doc(db('zara'), `users/amara/activity/${today}`), { at: serverTimestamp() }));
    await assertFails(setDoc(day('amara', 'yesterday'), { at: serverTimestamp() }));
    await assertFails(setDoc(day('amara', '2025-01-06'), { at: serverTimestamp() }));
    await assertFails(setDoc(day('amara'), { at: serverTimestamp(), minutes: 90 }));
  });
});

describe('duels', () => {
  test('a match is readable only by its players and written by no client', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'matches/m1'), { players: ['amara'], status: 'active' });
    });
    await assertSucceeds(getDoc(doc(db('amara'), 'matches/m1')));
    await assertFails(getDoc(doc(db('zara'), 'matches/m1')));
    await assertFails(setDoc(doc(db('amara'), 'matches/m2'), { players: ['amara'], status: 'complete' }));
    await assertFails(updateDoc(doc(db('amara'), 'matches/m1'), { status: 'complete' }));
  });

  test('ratings are readable when signed in and written by no client', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'ratings/amara_crime'), { rating: 1200 });
    });
    await assertSucceeds(getDoc(doc(db('zara'), 'ratings/amara_crime')));
    await assertFails(getDoc(doc(db(null), 'ratings/amara_crime')));
    await assertFails(setDoc(doc(db('amara'), 'ratings/amara_crime'), { rating: 2800 }));
  });
});

describe('lobbies, chat and challenges', () => {
  test('lobbies and their chat are readable by members only and written by no client', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'lobbies/ABC234'), { host: 'amara', members: ['amara', 'zara'], status: 'open' });
      await setDoc(doc(ctx.firestore(), 'lobbies/ABC234/messages/m1'), { uid: 'zara', text: 'good luck' });
    });
    await assertSucceeds(getDoc(doc(db('zara'), 'lobbies/ABC234')));
    await assertSucceeds(getDoc(doc(db('amara'), 'lobbies/ABC234/messages/m1')));
    await assertFails(getDoc(doc(db('omar'), 'lobbies/ABC234')));
    await assertFails(getDoc(doc(db('omar'), 'lobbies/ABC234/messages/m1')));
    await assertFails(setDoc(doc(db('amara'), 'lobbies/ABC234/messages/m2'), { uid: 'amara', text: 'unfiltered' }));
    await assertFails(updateDoc(doc(db('amara'), 'lobbies/ABC234'), { status: 'started' }));
  });

  test('challenges are readable by their players; their answers by no one', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'challenges/c1'), { players: ['amara', 'zara'], status: 'open' });
      await setDoc(doc(ctx.firestore(), 'challengeSecrets/c1'), { questions: [] });
    });
    await assertSucceeds(getDoc(doc(db('zara'), 'challenges/c1')));
    await assertFails(getDoc(doc(db('omar'), 'challenges/c1')));
    await assertFails(getDoc(doc(db('amara'), 'challengeSecrets/c1')));
    await assertFails(setDoc(doc(db('amara'), 'challenges/c2'), { players: ['amara', 'zara'], status: 'complete' }));
  });

  test('a block list is the owner\'s to read and no client\'s to write', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'users/amara/blocked/omar'), { at: new Date() }));
    await assertSucceeds(getDoc(doc(db('amara'), 'users/amara/blocked/omar')));
    await assertFails(getDoc(doc(db('omar'), 'users/amara/blocked/omar')));
    await assertFails(setDoc(doc(db('amara'), 'users/amara/blocked/zara'), { at: new Date() }));
  });

  test('the matchmaking queue is closed to clients', async () => {
    await assertFails(getDoc(doc(db('amara'), 'matchQueue/amara')));
    await assertFails(setDoc(doc(db('amara'), 'matchQueue/amara'), { rating: 3000 }));
  });
});

describe('boards', () => {
  test('entries are readable when signed in and written by no client', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'boards/week-2026-09-21/entries/zara'), { wins: 3 }));
    await assertSucceeds(getDoc(doc(db('amara'), 'boards/week-2026-09-21/entries/zara')));
    await assertFails(getDoc(doc(db(null), 'boards/week-2026-09-21/entries/zara')));
    await assertFails(setDoc(doc(db('amara'), 'boards/week-2026-09-21/entries/amara'), { wins: 99 }));
  });

  test('a friends list is the owner\'s to read and no client\'s to write', async () => {
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'users/amara/friends/zara'), { name: 'Zara K.' }));
    await assertSucceeds(getDoc(doc(db('amara'), 'users/amara/friends/zara')));
    await assertFails(getDoc(doc(db('zara'), 'users/amara/friends/zara')));
    await assertFails(setDoc(doc(db('amara'), 'users/amara/friends/omar'), { name: 'Omar S.' }));
  });
});

describe('news and the Sunday quiz', () => {
  test('are readable when signed in and written by no client', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'news/s1'), { title: 'Headline' });
      await setDoc(doc(ctx.firestore(), 'quizzes/2026-09-27'), { sunday: '2026-09-27' });
    });
    await assertSucceeds(getDoc(doc(db('amara'), 'news/s1')));
    await assertSucceeds(getDoc(doc(db('amara'), 'quizzes/2026-09-27')));
    await assertFails(getDoc(doc(db(null), 'news/s1')));
    await assertFails(setDoc(doc(db('amara'), 'news/s2'), { title: 'Fake news' }));
    await assertFails(setDoc(doc(db('amara'), 'quizzes/2026-10-04'), { sunday: '2026-10-04' }));
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

describe('error reports', () => {
  const report = (overrides = {}) => ({
    uid: 'amara', itemId: 'crime-03-check-02', lessonId: 'crime-03', reason: 'wrong-answer',
    note: 'Option B is also right', status: 'open', createdAt: serverTimestamp(), appVersion: '1.0', ...overrides,
  });

  test('a student can file a report for any item', async () => {
    await assertSucceeds(addDoc(collection(db('amara'), 'reports'), report()));
    const { lessonId, note, ...minimal } = report();
    await assertSucceeds(addDoc(collection(db('amara'), 'reports'), minimal));
  });

  test("reports can't be forged, read back, edited or pre-triaged", async () => {
    await assertFails(addDoc(collection(db('amara'), 'reports'), report({ uid: 'zara' })));
    await assertFails(addDoc(collection(db(null), 'reports'), report()));
    await assertFails(addDoc(collection(db('amara'), 'reports'), report({ status: 'resolved' })));
    await assertFails(addDoc(collection(db('amara'), 'reports'), report({ reason: 'spam' })));
    await assertFails(addDoc(collection(db('amara'), 'reports'), report({ note: 'x'.repeat(501) })));
    await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'reports/r1'), report({ createdAt: new Date() })));
    await assertFails(getDoc(doc(db('amara'), 'reports/r1')));
    await assertFails(updateDoc(doc(db('amara'), 'reports/r1'), { status: 'resolved' }));
  });
});

describe('everything else', () => {
  test('is denied', async () => {
    await assertFails(setDoc(doc(db('amara'), 'boards/weekly_everyone'), { rank: 1 }));
  });
});
