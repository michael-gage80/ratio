// Storage rules: Pencil notes. Run against the emulator:
//   firebase emulators:exec --only firestore,database,storage "npm --prefix firestore-tests test"
import { readFileSync } from 'node:fs';
import { after, before, describe, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { getBytes, ref, uploadBytes } from 'firebase/storage';

let env;

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-ratio',
    storage: { rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8'), host: '127.0.0.1', port: 9199 },
  });
});
after(() => env.cleanup());

const storage = (uid) => env.authenticatedContext(uid).storage();
const drawing = new Uint8Array([1, 2, 3]);
const meta = { contentType: 'application/octet-stream' };

describe('Pencil notes', () => {
  test('only their owner can write and read them', async () => {
    await assertSucceeds(uploadBytes(ref(storage('amara'), 'notes/amara/crime-03/2.drawing'), drawing, meta));
    await assertSucceeds(getBytes(ref(storage('amara'), 'notes/amara/crime-03/2.drawing')));
    await assertFails(getBytes(ref(storage('zara'), 'notes/amara/crime-03/2.drawing')));
    await assertFails(uploadBytes(ref(storage('zara'), 'notes/amara/crime-03/3.drawing'), drawing, meta));
  });

  test('only drawing files of the right type', async () => {
    await assertFails(uploadBytes(ref(storage('amara'), 'notes/amara/crime-03/notes.txt'), drawing, meta));
    await assertFails(uploadBytes(ref(storage('amara'), 'notes/amara/crime-03/2.drawing'), drawing, { contentType: 'image/png' }));
  });
});
