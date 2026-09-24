// Hand-authoring for the news centre (PRD: "Up to 5 items a day get a short 'Why it
// matters' note ... linking the story to a syllabus topic and a Ratio lesson"; "Every
// Sunday: 7 questions based on the week's stories").
//
// Needs GOOGLE_APPLICATION_CREDENTIALS pointing at a service-account key for ratio-91a04
// (Project settings → Service accounts → Generate new private key). Keep the key outside
// the repo — it's public.
//
//   node content-tools/news-admin.mjs list [days]
//       Recent headlines with their IDs, newest first (default: 7 days).
//   node content-tools/news-admin.mjs why <newsId> <lessonId> "Note text"
//       Adds or replaces the story's "Why it matters" note, linked to a lesson.
//   node content-tools/news-admin.mjs why <newsId> --remove
//   node content-tools/news-admin.mjs quiz <file.json>
//       Publishes a Sunday quiz. See content-tools/quiz-template.json for the shape.

import { readFileSync, readdirSync } from 'node:fs';
import { initializeApp } from 'firebase-admin/app';
import { FieldValue, getFirestore, Timestamp } from 'firebase-admin/firestore';

initializeApp({ projectId: process.env.GCLOUD_PROJECT ?? 'ratio-91a04' });
const db = getFirestore();
const LESSONS = new URL('../ratio/Resources/Content/lessons/', import.meta.url).pathname;
const lessons = new Map(
  readdirSync(LESSONS).filter((f) => f.endsWith('.json')).map((f) => {
    const lesson = JSON.parse(readFileSync(LESSONS + f, 'utf8'));
    return [lesson.lessonId, lesson];
  }),
);

const fail = (message) => {
  console.error(message);
  process.exit(1);
};

async function list(days = 7) {
  const since = Timestamp.fromMillis(Date.now() - days * 24 * 60 * 60 * 1000);
  const snapshot = await db.collection('news').where('publishedAt', '>', since).orderBy('publishedAt', 'desc').get();
  for (const doc of snapshot.docs) {
    const d = doc.data();
    const date = d.publishedAt.toDate().toISOString().slice(0, 10);
    const note = d.whyItMatters ? `  ✎ ${d.whyItMatters.lessonId}` : '';
    console.log(`${doc.id}  ${date}  ${d.source.padEnd(20)}  ${(d.modules ?? []).join(',').padEnd(12)}  ${d.title}${note}`);
  }
}

async function why(newsId, lessonId, text) {
  const ref = db.doc(`news/${newsId}`);
  const story = await ref.get();
  if (!story.exists) fail(`No story ${newsId}. Run "list" for IDs.`);
  if (lessonId === '--remove') {
    await ref.update({ whyItMatters: FieldValue.delete() });
    return console.log('Removed.');
  }
  const lesson = lessons.get(lessonId);
  if (!lesson) fail(`No lesson ${lessonId}.`);
  if (!text || text.length > 280) fail('The note should be 1–280 characters.');

  const day = story.get('publishedAt').toDate().toISOString().slice(0, 10);
  const sameDay = await db.collection('news')
    .where('publishedAt', '>=', Timestamp.fromDate(new Date(`${day}T00:00:00Z`)))
    .where('publishedAt', '<', Timestamp.fromDate(new Date(`${day}T23:59:59Z`))).get();
  const notes = sameDay.docs.filter((d) => d.get('whyItMatters') && d.id !== newsId).length;
  if (notes >= 5) console.warn(`Note: ${day} already has ${notes} notes; the PRD suggests up to 5 a day.`);

  await ref.update({
    whyItMatters: {
      text,
      lessonId,
      lessonTitle: lesson.title,
      moduleId: lesson.moduleId,
      topicId: lesson.topicId,
      updatedAt: FieldValue.serverTimestamp(),
    },
  });
  console.log(`Saved: "${story.get('title')}" → ${lesson.moduleTitle}: ${lesson.title}`);
}

async function quiz(file) {
  const quiz = JSON.parse(readFileSync(file, 'utf8'));
  if (!/^\d{4}-\d{2}-\d{2}$/.test(quiz.sunday) || new Date(`${quiz.sunday}T12:00:00Z`).getUTCDay() !== 0) {
    fail('"sunday" must be a Sunday, as yyyy-mm-dd.');
  }
  if (!Array.isArray(quiz.questions) || quiz.questions.length !== 7) fail('A Sunday quiz has 7 questions.');
  const questions = [];
  for (const [i, q] of quiz.questions.entries()) {
    const where = `Question ${i + 1}`;
    if (!q.prompt) fail(`${where}: missing prompt.`);
    if (!Array.isArray(q.options) || q.options.length < 2 || q.options.length > 4) fail(`${where}: 2–4 options.`);
    if (!Number.isInteger(q.correctIndex) || q.correctIndex < 0 || q.correctIndex >= q.options.length) fail(`${where}: correctIndex out of range.`);
    if (!q.explanation) fail(`${where}: missing explanation.`);
    const story = await db.doc(`news/${q.newsId}`).get();
    if (!story.exists) fail(`${where}: no story ${q.newsId}.`);
    questions.push({
      prompt: q.prompt,
      options: q.options,
      correctIndex: q.correctIndex,
      explanation: q.explanation,
      story: {
        id: story.id,
        title: story.get('title'),
        source: story.get('source'),
        url: story.get('url'),
        ...(story.get('whyItMatters') ? { whyItMatters: story.get('whyItMatters') } : {}),
      },
    });
  }
  await db.doc(`quizzes/${quiz.sunday}`).set({ sunday: quiz.sunday, questions, publishedAt: FieldValue.serverTimestamp() });
  console.log(`Published the Sunday quiz for ${quiz.sunday}.`);
}

const [command, ...args] = process.argv.slice(2);
switch (command) {
  case 'list': await list(Number(args[0]) || 7); break;
  case 'why': await why(args[0], args[1], args[2]); break;
  case 'quiz': await quiz(args[0]); break;
  default: fail('Commands: list [days] | why <newsId> <lessonId> "text" | why <newsId> --remove | quiz <file.json>');
}
