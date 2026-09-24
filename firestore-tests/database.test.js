// Realtime Database rules for live duels. Run against the emulator:
//   firebase emulators:exec --only firestore,database "npm --prefix firestore-tests test"
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { get, ref, serverTimestamp, set, update } from 'firebase/database';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-ratio',
    database: { rules: readFileSync(new URL('../database.rules.json', import.meta.url), 'utf8'), host: '127.0.0.1', port: 9000 },
  });
});

beforeEach(async () => {
  await env.clearDatabase();
  await env.withSecurityRulesDisabled((ctx) => set(ref(ctx.database(), 'live/m1'), {
    state: { questions: [{ correctIndex: 2 }] },
    public: { players: { amara: { name: 'Amara O.' }, zara: { name: 'Zara K.' } }, status: 'playing' },
  }));
});
after(() => env.cleanup());

const db = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).database();

describe('live matches', () => {
  test('players read the public view; nobody reads the referee state', async () => {
    await assertSucceeds(get(ref(db('amara'), 'live/m1/public')));
    await assertFails(get(ref(db('omar'), 'live/m1/public')));
    await assertFails(get(ref(db('amara'), 'live/m1/state')));
    await assertFails(get(ref(db('amara'), 'live/m1')));
  });

  test('no client can write the match', async () => {
    await assertFails(update(ref(db('amara'), 'live/m1/public'), { status: 'complete' }));
    await assertFails(set(ref(db('amara'), 'live/m1/state/score'), [3, 0]));
  });
});

describe('presence', () => {
  test('a player marks only their own presence, in the expected shape', async () => {
    await assertSucceeds(set(ref(db('amara'), 'presence/m1/amara'), { online: true, lastSeen: serverTimestamp() }));
    await assertFails(set(ref(db('amara'), 'presence/m1/zara'), { online: false, lastSeen: serverTimestamp() }));
    await assertFails(set(ref(db('omar'), 'presence/m1/omar'), { online: true, lastSeen: serverTimestamp() }));
    await assertFails(set(ref(db('amara'), 'presence/m1/amara'), { online: true, lastSeen: serverTimestamp(), score: 3 }));
    await assertFails(set(ref(db('amara'), 'presence/m1/amara'), { online: 'yes', lastSeen: serverTimestamp() }));
  });

  test('both players can read the match presence', async () => {
    await assertSucceeds(get(ref(db('zara'), 'presence/m1')));
    await assertFails(get(ref(db('omar'), 'presence/m1')));
  });
});

describe('who is online', () => {
  test('a student marks only themselves online, and nobody reads the list', async () => {
    await assertSucceeds(set(ref(db('amara'), 'online/amara'), serverTimestamp()));
    await assertFails(set(ref(db('amara'), 'online/zara'), serverTimestamp()));
    await assertFails(set(ref(db('amara'), 'online/amara'), 'here'));
    await assertFails(get(ref(db('amara'), 'online')));
  });

  test('the count is readable when signed in and written by no client', async () => {
    await assertSucceeds(get(ref(db('amara'), 'stats/online')));
    await assertFails(get(ref(db(), 'stats/online')));
    await assertFails(set(ref(db('amara'), 'stats/online'), { count: 999, at: 0 }));
  });
});
