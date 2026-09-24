// Content lint (PRD: "Content operations" → "CI checks the schema, required
// citations, item counts per skill, and reading time"). Validates every lesson and the
// diagnostic bank. Errors fail the run; warnings are printed for the content team.
//
//   node content-tools/validate.mjs
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';

const CONTENT = new URL('../ratio/Resources/Content/', import.meta.url).pathname;
const LESSONS = join(CONTENT, 'lessons');
const WORDS_PER_MINUTE = 200;

const ajv = new Ajv2020({ allErrors: true, strict: false });
addFormats(ajv);
const schema = JSON.parse(readFileSync(new URL('./lesson.schema.json', import.meta.url), 'utf8'));
const validateLesson = ajv.compile(schema);
const validateItem = ajv.getSchema(`${schema.$id}#/$defs/item`);

const errors = [];
const warnings = [];
const seenItemIds = new Map();

/** Same rule as the app (Item.highlightTheRatio): a sentence that contains the ratio, or vice versa. */
const normalise = (s) => s.toLowerCase().replace(/\s+/g, ' ').replace(/[.\s]+$/, '').trim();
const sentences = (passage) => passage.split(/(?<=[.!?])\s+/).filter(Boolean);

function checkItem(where, item) {
  const prior = seenItemIds.get(item.itemId);
  if (prior) errors.push(`${where}: item ID ${item.itemId} is also used in ${prior}`);
  seenItemIds.set(item.itemId, where);

  switch (item.type) {
    case 'quickCheck': case 'mcqWithTrap': case 'applyTheRule': case 'statuteParser':
      if (item.correctIndex >= item.options.length) errors.push(`${where}: correctIndex ${item.correctIndex} is past the last option`);
      break;
    case 'sortIntoBuckets':
      for (const statement of item.itemsToSort) {
        if (!item.buckets.includes(statement.correctBucket)) {
          errors.push(`${where}: "${statement.text}" belongs to "${statement.correctBucket}", which isn't one of the buckets`);
        }
      }
      break;
    case 'tapTheFact':
      if (!item.tappableSpans.includes(item.correctSpan)) errors.push(`${where}: correctSpan isn't one of tappableSpans`);
      for (const span of item.tappableSpans) {
        // Same rule as the app: spans match case-insensitively.
        if (!item.scenarioText.toLowerCase().includes(span.toLowerCase())) {
          errors.push(`${where}: span "${span}" doesn't appear in scenarioText`);
        } else if (!item.scenarioText.includes(span)) {
          warnings.push(`${where}: span "${span}" only matches scenarioText ignoring case`);
        }
      }
      break;
    case 'sequence': {
      const sorted = [...item.correctOrder].sort((a, b) => a - b);
      if (sorted.length !== item.items.length || sorted.some((v, i) => v !== i)) {
        errors.push(`${where}: correctOrder isn't a permutation of the ${item.items.length} items`);
      }
      break;
    }
    case 'thresholdSlider': {
      // Same rule as the app and the server: a label equal to correctPosition, otherwise
      // the one label containing it. Anything else would mark the wrong end.
      const target = item.correctPosition.trim().toLowerCase();
      const labels = item.sliderLabels.map((l) => l.trim().toLowerCase());
      const containing = labels.filter((l) => l.includes(target)).length;
      if (!labels.includes(target) && containing !== 1) {
        errors.push(`${where}: correctPosition "${item.correctPosition}" must equal one slider label or appear in exactly one (it's in ${containing})`);
      }
      break;
    }
    case 'highlightTheRatio': {
      const ratio = normalise(item.ratioSentence);
      const hits = sentences(item.passage).filter((s) => normalise(s).includes(ratio) || ratio.includes(normalise(s)));
      if (hits.length !== 1) errors.push(`${where}: ratioSentence matches ${hits.length} sentences of the passage (needs exactly 1)`);
      break;
    }
  }
}

function lintLesson(file) {
  const where = file;
  const lesson = JSON.parse(readFileSync(join(LESSONS, file), 'utf8'));
  if (!validateLesson(lesson)) {
    for (const e of validateLesson.errors) errors.push(`${where}${e.instancePath}: ${e.message}`);
    return;
  }
  const { lessonId, moduleId, lessonNumber, topicId, itemCounts, lecture, testPool } = lesson;

  if (!lessonId.startsWith(`${moduleId}-`)) errors.push(`${where}: lessonId ${lessonId} doesn't start with ${moduleId}-`);
  if (Number(lessonId.split('-')[1]) !== lessonNumber) errors.push(`${where}: lessonNumber ${lessonNumber} doesn't match ${lessonId}`);
  if (!topicId.startsWith(`${moduleId}.`)) errors.push(`${where}: topicId ${topicId} isn't in module ${moduleId}`);
  if (itemCounts.lecture !== lecture.parts.length) errors.push(`${where}: itemCounts.lecture is ${itemCounts.lecture} but there are ${lecture.parts.length} parts`);
  if (itemCounts.testPool !== testPool.length) errors.push(`${where}: itemCounts.testPool is ${itemCounts.testPool} but the pool has ${testPool.length}`);
  if (itemCounts.testServedPerAttempt > testPool.length) errors.push(`${where}: serves more test items than the pool holds`);

  lecture.parts.forEach((p, i) => {
    if (p.partNumber !== i + 1) errors.push(`${where}: part ${i + 1} is numbered ${p.partNumber}`);
    checkItem(`${where} part ${p.partNumber}`, p.interaction);
  });
  testPool.forEach((item) => checkItem(`${where} testPool`, item));

  for (const skill of ['knowledge', 'understanding', 'application']) {
    if (!testPool.some((i) => i.skillTag === skill)) errors.push(`${where}: test pool has no ${skill} items`);
  }

  const words = lecture.parts.flatMap((p) => p.body).join(' ').split(/\s+/).length;
  const readingMinutes = Math.ceil(words / WORDS_PER_MINUTE);
  if (readingMinutes > lesson.estimatedMinutes) {
    warnings.push(`${where}: lecture alone is ~${readingMinutes} min of reading, more than estimatedMinutes ${lesson.estimatedMinutes}`);
  }
  if (/where the profile shows/i.test(lesson.whyThisMattersTemplate.default)) {
    warnings.push(`${where}: whyThisMattersTemplate.default contains an authoring note ("Where the profile shows…") — move it to profileHooks`);
  }
  if (lesson.reviewedBy === null) warnings.push(`${where}: not yet reviewed (reviewedBy is null)`);
}

function lintDiagnosticBank() {
  const where = 'diagnostic-bank.json';
  const bank = JSON.parse(readFileSync(join(CONTENT, where), 'utf8'));
  for (const [moduleId, { items }] of Object.entries(bank.modules)) {
    for (const item of items) {
      if (!validateItem(item)) {
        for (const e of validateItem.errors) errors.push(`${where} ${item.itemId}${e.instancePath}: ${e.message}`);
        continue;
      }
      if (!item.topicId?.startsWith(`${moduleId}.`)) errors.push(`${where} ${item.itemId}: topicId isn't in module ${moduleId}`);
      checkItem(`${where} ${moduleId}`, item);
    }
  }
}

const files = readdirSync(LESSONS).filter((f) => /^[a-z]+-\d{2}-[a-z0-9-]+\.json$/.test(f)).sort();
files.forEach(lintLesson);
lintDiagnosticBank();

const unreviewed = warnings.filter((w) => w.includes('not yet reviewed')).length;
for (const w of warnings.filter((w) => !w.includes('not yet reviewed'))) console.log(`warning  ${w}`);
if (unreviewed) console.log(`warning  ${unreviewed} of ${files.length} lessons not yet reviewed`);
for (const e of errors) console.log(`ERROR    ${e}`);
console.log(`\n${files.length} lessons + diagnostic bank: ${errors.length} errors, ${warnings.length} warnings`);
process.exit(errors.length ? 1 : 0);
