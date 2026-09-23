// Publishes one content bundle per module to Cloud Storage (PRD: "Content bundles:
// one bundle per module, versioned by semantic version… A 'law moved' fix ships
// without an App Store release"). Runs in CI on merge to main.
//
//   content/manifest.json                       { modules: { crime: { version, path, sha256, lessons } } }
//   content/modules/<moduleId>/<version>.json   { moduleId, version, lessons: [...] }
//
// Only reviewed lessons are published (PRD: "only lessons marked approved go into a
// bundle"). Until the review workflow exists, INCLUDE_UNREVIEWED=1 publishes drafts too;
// the app labels them as unreviewed.
//
// Needs GOOGLE_APPLICATION_CREDENTIALS for a service account that can write the bucket.
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { initializeApp } from 'firebase-admin/app';
import { getStorage } from 'firebase-admin/storage';

const BUCKET = 'ratio-91a04.firebasestorage.app';
const LESSONS = new URL('../ratio/Resources/Content/lessons/', import.meta.url).pathname;
const includeUnreviewed = process.env.INCLUDE_UNREVIEWED === '1';

initializeApp({ storageBucket: BUCKET });
const bucket = getStorage().bucket();

const lessons = readdirSync(LESSONS)
  .filter((f) => f.endsWith('.json'))
  .map((f) => JSON.parse(readFileSync(join(LESSONS, f), 'utf8')))
  .filter((l) => includeUnreviewed || l.reviewedBy)
  .sort((a, b) => a.lessonNumber - b.lessonNumber);

const byModule = Object.groupBy(lessons, (l) => l.moduleId);

const manifestFile = bucket.file('content/manifest.json');
const [manifestExists] = await manifestFile.exists();
const manifest = manifestExists
  ? JSON.parse((await manifestFile.download())[0].toString('utf8'))
  : { modules: {} };

const bumpPatch = (version) => {
  const [major, minor, patch] = version.split('.').map(Number);
  return `${major}.${minor}.${patch + 1}`;
};

let changed = false;
for (const [moduleId, moduleLessons] of Object.entries(byModule)) {
  const contentHash = createHash('sha256').update(JSON.stringify(moduleLessons)).digest('hex');
  const current = manifest.modules[moduleId];
  if (current?.contentHash === contentHash) {
    console.log(`${moduleId}: unchanged at ${current.version}`);
    continue;
  }
  const version = current ? bumpPatch(current.version) : '1.0.0';
  const body = JSON.stringify({ moduleId, version, lessons: moduleLessons });
  const path = `content/modules/${moduleId}/${version}.json`;
  await bucket.file(path).save(body, {
    contentType: 'application/json',
    metadata: { cacheControl: 'public, max-age=31536000, immutable' },
  });
  manifest.modules[moduleId] = {
    version,
    path,
    sha256: createHash('sha256').update(body).digest('hex'),
    contentHash,
    lessons: moduleLessons.length,
  };
  changed = true;
  console.log(`${moduleId}: published ${version} (${moduleLessons.length} lessons)`);
}

if (changed) {
  manifest.publishedAt = new Date().toISOString();
  await manifestFile.save(JSON.stringify(manifest, null, 2), {
    contentType: 'application/json',
    metadata: { cacheControl: 'no-cache' },
  });
  console.log('manifest updated');
}
