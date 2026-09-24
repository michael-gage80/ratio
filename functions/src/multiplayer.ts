// Duels against other students (PRD: "Duel: multiplayer"): friend lobbies, ranked
// matchmaking and async challenges. Live matches are refereed by the callables below
// over /live/{matchId} in the Realtime Database (see live.ts); results are settled in
// Firestore — ratings, the profile, and matches/{id} for both players.

import { getDatabaseWithUrl } from "firebase-admin/database";
import { FieldValue, getFirestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { checkDuel, countDuel, notify } from "./account.js";
import { periodKeys } from "./boards.js";
import { blockReason, MAX_MESSAGE_LENGTH } from "./chat.js";
import { duelLessons, MODULES } from "./content.js";
import { Answer, DuelQuestion, marked, matchQuestions, MIN_ANSWER_MS, playMatchWith, questionPool } from "./duel.js";
import { INITIAL } from "./glicko.js";
import * as live from "./live.js";
import { readSide, Settlement, Side, SideState, writeSide } from "./settle.js";

/** Live duels' Realtime Database (europe-west1), named so nothing depends on project defaults. */
const DATABASE_URL = "https://ratio-91a04-default-rtdb.europe-west1.firebasedatabase.app";
const getDatabase = () => getDatabaseWithUrl(DATABASE_URL);

const LOBBY_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // No 0/O or 1/I (PRD).
const LOBBY_MINUTES = 15;
const CHALLENGE_HOURS = 24;
const MATCH_ID = /^[A-Za-z0-9_-]{10,40}$/;

function requireAuth(uid: string | undefined): string {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  return uid;
}

function limitFor(seconds: unknown): number {
  return (seconds === 15 || seconds === 20 ? seconds : 10) * 1000;
}

function requireModule(moduleId: unknown): string {
  if (typeof moduleId !== "string" || !MODULES.includes(moduleId)) throw new HttpsError("invalid-argument", "Unknown module.");
  return moduleId;
}

/** "Amara O.", the initial, avatar and module rating, as other players see them. */
async function player(uid: string, moduleId: string): Promise<live.Player & { rd: number }> {
  const db = getFirestore();
  const [user, rating] = await Promise.all([db.doc(`users/${uid}`).get(), db.doc(`ratings/${uid}_${moduleId}`).get()]);
  const displayName = (user.get("displayName") as string | undefined) ?? "Student";
  const initial = user.get("initial") as string | undefined;
  const avatarVersion = user.get("avatarVersion") as number | undefined;
  return {
    name: initial ? `${displayName} ${initial}.` : displayName,
    initial: displayName.slice(0, 1).toUpperCase(),
    rating: Math.round((rating.get("rating") as number | undefined) ?? INITIAL.rating),
    rd: (rating.get("rd") as number | undefined) ?? INITIAL.rd,
    ...(avatarVersion ? { avatarVersion } : {}),
  };
}

async function isBlocked(a: string, b: string): Promise<boolean> {
  const db = getFirestore();
  const [ab, ba] = await Promise.all([db.doc(`users/${a}/blocked/${b}`).get(), db.doc(`users/${b}/blocked/${a}`).get()]);
  return ab.exists || ba.exists;
}

function questionsFor(moduleId: string): DuelQuestion[] {
  const questions = matchQuestions(questionPool(duelLessons.filter((l) => l.moduleId === moduleId), Math.random), Math.random);
  if (!questions) throw new HttpsError("failed-precondition", "This module doesn't have enough questions for a duel yet.");
  return questions;
}

// MARK: - Live matches

/** Starts a live match between two students; returns its ID. */
async function createLiveMatch(mode: live.Mode, moduleId: string, limitMs: number, uids: [string, string]): Promise<string> {
  const [a, b] = await Promise.all(uids.map((uid) => player(uid, moduleId)));
  const players = { [uids[0]]: strip(a), [uids[1]]: strip(b) };
  const state = live.newMatch({ mode, moduleId, limitMs, order: uids, players, questions: questionsFor(moduleId) }, Date.now());
  const ref = getDatabase().ref("live").push();
  await ref.set({ state, public: live.publicView(state), createdAt: Date.now() });
  return ref.key!;
}

/**
 * Applies `change` to a live match in a transaction and mirrors the public view. The
 * change sees the normalised state and the caller's player index; returning null
 * leaves the match untouched.
 */
async function updateLive(matchId: string, uid: string, change: (state: live.LiveState, player: 0 | 1, now: number) => live.LiveState | null): Promise<live.LiveState> {
  if (!MATCH_ID.test(matchId)) throw new HttpsError("invalid-argument", "Unknown match.");
  const ref = getDatabase().ref(`live/${matchId}`);
  let notPlayer = false;
  const result = await ref.transaction((current: { state?: live.LiveState } | null) => {
    if (!current?.state) return current; // Not loaded yet: the transaction retries with the real value.
    const state = live.normalise(current.state);
    const player = state.order.indexOf(uid);
    if (player < 0) {
      notPlayer = true;
      return; // Abort.
    }
    const next = change(state, player as 0 | 1, Date.now());
    if (!next) return; // Abort: nothing to change.
    return { ...current, state: next, public: live.publicView(next) };
  });
  if (notPlayer) throw new HttpsError("permission-denied", "You're not in this match.");
  const stored = result.snapshot.child("state").val() as live.LiveState | null;
  if (!stored) throw new HttpsError("not-found", "Unknown match.");
  const state = live.normalise(stored);
  // Settle once it's over — or again, if an earlier attempt didn't get as far as the results.
  if (state.status === "complete" && !result.snapshot.child("public/results").exists()) await settleLive(matchId, state);
  return state;
}

/** An answer to the current round. */
export const liveAnswer = onCall<{ matchId?: string; round?: number; answerIndex?: number; timeMs?: number }>(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const { matchId, round, answerIndex, timeMs } = request.data ?? {};
  if (typeof matchId !== "string" || !Number.isInteger(round) || !Number.isInteger(answerIndex) || typeof timeMs !== "number") {
    throw new HttpsError("invalid-argument", "Malformed answer.");
  }
  await updateLive(matchId, uid, (state, player, now) => {
    const { state: next, outcome } = live.answer(state, player, round!, answerIndex!, timeMs, now);
    return outcome === "ignored" ? null : next;
  });
  return { ok: true };
});

/** Either player's clock has run out for this round. */
export const liveTimeout = onCall<{ matchId?: string; round?: number }>(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const { matchId, round } = request.data ?? {};
  if (typeof matchId !== "string" || !Number.isInteger(round)) throw new HttpsError("invalid-argument", "Malformed request.");
  await updateLive(matchId, uid, (state, _, now) => live.timeout(state, round!, now));
  return { ok: true };
});

/** Leaving mid-match forfeits it. */
export const liveLeave = onCall<{ matchId?: string }>(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const { matchId } = request.data ?? {};
  if (typeof matchId !== "string") throw new HttpsError("invalid-argument", "Unknown match.");
  await updateLive(matchId, uid, (state, player) => live.forfeit(state, player));
  return { ok: true };
});

/** Claims the match when the opponent has been gone for 45 s (PRD: "after 45 s the whole match is forfeited"). */
export const liveClaim = onCall<{ matchId?: string }>(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const { matchId } = request.data ?? {};
  if (typeof matchId !== "string" || !MATCH_ID.test(matchId)) throw new HttpsError("invalid-argument", "Unknown match.");
  const order = (await getDatabase().ref(`live/${matchId}/public/order`).get()).val() as [string, string] | null;
  const opponent = order?.find((p) => p !== uid);
  if (!order || !opponent) throw new HttpsError("not-found", "Unknown match.");
  const presence = (await getDatabase().ref(`presence/${matchId}/${opponent}`).get()).val() as { online?: boolean; lastSeen?: number } | null;
  const state = await updateLive(matchId, uid, (state, player, now) => {
    const goneSince = presence?.online ? null : presence?.lastSeen ?? state.startsAt - live.COUNTDOWN_MS;
    if (goneSince === null || now - goneSince < live.FORFEIT_AFTER_MS) return null;
    return live.forfeit(state, player === 0 ? 1 : 0);
  });
  return { claimed: state.status === "complete" && state.forfeitedBy !== null };
});

// MARK: - Settling

interface PlayerRecord {
  questions: DuelQuestion[];
  limitMs: number;
  mode: live.Mode;
  moduleId: string;
  opponent: { uid: string; name: string; initial: string; avatarVersion?: number };
  /** Each round from this player's side: answers are [mine, theirs]; winner 0 is me. */
  rounds: { questionIndex: number; answers: (Answer & { correct: boolean })[]; winner: number | null }[];
  score: [number, number];
  winner: number | null;
  forfeited: boolean;
  ratingBefore: number;
  ratingAfter: number;
  skillMoved: Settlement["skillMoved"];
}

/**
 * Settles a finished two-player match once: both ratings (Glicko-2 against each other's
 * rating before the match), both profiles, and matches/{id}. Returns each player's view.
 */
async function settle(
  tx: Transaction,
  matchId: string,
  params: {
    mode: live.Mode;
    moduleId: string;
    limitMs: number;
    order: [string, string];
    players: Record<string, Pick<live.Player, "name" | "initial" | "avatarVersion">>;
    questions: DuelQuestion[];
    rounds: live.LiveState["rounds"];
    score: [number, number];
    winner: number | null;
    forfeitedBy: number | null;
  },
): Promise<Record<string, PlayerRecord> | null> {
  const db = getFirestore();
  const matchRef = db.doc(`matches/${matchId}`);
  const existing = await tx.get(matchRef);
  if (existing.exists) return null;

  const sides: SideState[] = [];
  for (const p of [0, 1] as const) {
    const side: Side = {
      uid: params.order[p],
      moduleId: params.moduleId,
      answers: params.rounds.map((r) => ({ question: params.questions[r.questionIndex], answer: r.answers[p] })),
    };
    sides.push(await readSide(tx, db, side));
  }
  const settlements = ([0, 1] as const).map((p) => {
    const opponent = sides[1 - p].rating;
    const score = params.winner === null ? 0.5 : params.winner === p ? 1 : 0;
    return writeSide(tx, sides[p], opponent, score);
  });

  const records: Record<string, PlayerRecord> = {};
  for (const p of [0, 1] as const) {
    const me = params.order[p];
    const them = params.order[1 - p];
    const flip = (w: number | null) => (w === null ? null : w === p ? 0 : 1);
    records[me] = {
      questions: params.questions,
      limitMs: params.limitMs,
      mode: params.mode,
      moduleId: params.moduleId,
      opponent: {
        uid: them,
        name: params.players[them].name,
        initial: params.players[them].initial,
        ...(params.players[them].avatarVersion ? { avatarVersion: params.players[them].avatarVersion } : {}),
      },
      rounds: params.rounds.map((r) => ({ questionIndex: r.questionIndex, answers: [r.answers[p], r.answers[1 - p]], winner: flip(r.winner) })),
      score: [params.score[p], params.score[1 - p]],
      winner: flip(params.winner),
      forfeited: params.forfeitedBy !== null,
      ...settlements[p],
    };
  }

  // Boards: every human match puts both players on this period's boards; only a win
  // scores. A forfeit before any round was played scores nothing.
  const played = params.rounds.length > 0;
  const keys = Object.values(periodKeys(new Date()));
  for (const p of [0, 1] as const) {
    const uid = params.order[p];
    const user = sides[p].user;
    const won = played && params.winner === p;
    for (const key of keys) {
      tx.set(db.doc(`boards/${key}/entries/${uid}`), {
        uid,
        name: params.players[uid].name,
        initial: params.players[uid].initial,
        ...(params.players[uid].avatarVersion ? { avatarVersion: params.players[uid].avatarVersion } : {}),
        universityId: (user.get("universityId") as string | undefined) ?? null,
        universityName: (user.get("universityOther") as string | undefined) ?? null,
        rating: settlements[p].ratingAfter,
        wins: FieldValue.increment(won ? 1 : 0),
        played: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    // Students you've duelled are your friends for the Friends board.
    const other = params.order[1 - p];
    tx.set(db.doc(`users/${uid}/friends/${other}`), { name: params.players[other].name, lastPlayed: FieldValue.serverTimestamp() }, { merge: true });
  }

  tx.create(matchRef, {
    players: params.order,
    mode: params.mode,
    isBot: false,
    moduleId: params.moduleId,
    names: Object.fromEntries(params.order.map((uid) => [uid, params.players[uid].name])),
    limitMs: params.limitMs,
    status: "complete",
    results: Object.fromEntries(Object.entries(records).map(([uid, r]) => [uid, {
      score: r.score, winner: r.winner, ratingBefore: r.ratingBefore, ratingAfter: r.ratingAfter, forfeited: r.forfeited,
    }])),
    createdAt: FieldValue.serverTimestamp(),
  });
  return records;
}

async function settleLive(matchId: string, state: live.LiveState): Promise<void> {
  const records = await getFirestore().runTransaction((tx) => settle(tx, matchId, state));
  if (records) await getDatabase().ref(`live/${matchId}/public/results`).set(records);
}

// MARK: - Friend lobbies

function lobbyRef(code: unknown) {
  const clean = String(code ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (clean.length !== 6) throw new HttpsError("invalid-argument", "Lobby codes have six characters.");
  return getFirestore().doc(`lobbies/${clean}`);
}

function lobbyCode(): string {
  return Array.from({ length: 6 }, () => LOBBY_CODE_ALPHABET[Math.floor(Math.random() * LOBBY_CODE_ALPHABET.length)]).join("");
}

/** A friend lobby (PRD): a 6-character code, 15 minutes to fill it, the host starts. */
export const createLobby = onCall<{ moduleId?: string; seconds?: number }>(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const moduleId = requireModule(request.data?.moduleId);
  const host = await player(uid, moduleId);
  const db = getFirestore();
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = lobbyCode();
    try {
      await db.doc(`lobbies/${code}`).create({
        host: uid,
        guest: null,
        members: [uid],
        names: { [uid]: host.name },
        moduleId,
        limitMs: limitFor(request.data?.seconds),
        status: "open",
        matchId: null,
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: Timestamp.fromMillis(Date.now() + LOBBY_MINUTES * 60_000),
      });
      return { code };
    } catch {
      // Taken: try another code.
    }
  }
  throw new HttpsError("resource-exhausted", "Couldn't make a lobby code. Try again.");
});

export const joinLobby = onCall<{ code?: string }>(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const db = getFirestore();
  const ref = lobbyRef(request.data?.code);
  const code = ref.id;
  const snapshot = await ref.get();
  if (!snapshot.exists) throw new HttpsError("not-found", "No lobby has that code.");
  const host = snapshot.get("host") as string;
  if (host !== uid && (await isBlocked(host, uid))) throw new HttpsError("permission-denied", "You can't join this lobby.");
  const name = (await player(uid, snapshot.get("moduleId"))).name;
  await db.runTransaction(async (tx) => {
    const lobby = await tx.get(ref);
    const guest = lobby.get("guest") as string | null;
    if (host === uid || guest === uid) return;
    if (lobby.get("status") !== "open" || (lobby.get("expiresAt") as Timestamp).toMillis() < Date.now()) {
      throw new HttpsError("failed-precondition", "That lobby has closed.");
    }
    if (guest) throw new HttpsError("failed-precondition", "That lobby is full.");
    tx.update(ref, { guest: uid, members: [host, uid], [`names.${uid}`]: name });
  });
  return { code };
});

export const leaveLobby = onCall<{ code?: string }>(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const ref = lobbyRef(request.data?.code);
  await getFirestore().runTransaction(async (tx) => {
    const lobby = await tx.get(ref);
    if (!lobby.exists || lobby.get("status") !== "open") return;
    if (lobby.get("host") === uid) tx.update(ref, { status: "closed" });
    else if (lobby.get("guest") === uid) tx.update(ref, { guest: null, members: [lobby.get("host")] });
  });
  return { ok: true };
});

/** The host starts: the live match begins with a 5-second countdown. */
export const startLobby = onCall<{ code?: string }>(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const ref = lobbyRef(request.data?.code);
  const lobby = await ref.get();
  if (!lobby.exists || lobby.get("host") !== uid) throw new HttpsError("permission-denied", "Only the host can start.");
  if (lobby.get("matchId")) return { matchId: lobby.get("matchId") };
  const guest = lobby.get("guest") as string | null;
  if (lobby.get("status") !== "open" || !guest) throw new HttpsError("failed-precondition", "Wait for your opponent to join.");
  if ((lobby.get("expiresAt") as Timestamp).toMillis() < Date.now()) throw new HttpsError("failed-precondition", "That lobby has expired. Make a new one.");
  await checkDuel(guest).catch(() => {
    throw new HttpsError("resource-exhausted", "Your opponent has used today's free duels.", { reason: "opponent-limit" });
  });
  await countDuel(uid);
  await countDuel(guest);
  const matchId = await createLiveMatch("lobby", lobby.get("moduleId"), lobby.get("limitMs"), [uid, guest]);
  await ref.update({ status: "started", matchId });
  return { matchId };
});

/** Lobby chat, filtered before delivery; kept 30 days (PRD). */
export const sendLobbyMessage = onCall<{ code?: string; text?: string }>(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const text = String(request.data?.text ?? "").trim();
  if (!text || text.length > MAX_MESSAGE_LENGTH) throw new HttpsError("invalid-argument", `Messages are 1–${MAX_MESSAGE_LENGTH} characters.`);
  const ref = lobbyRef(request.data?.code);
  const lobby = await ref.get();
  if (!lobby.exists || !(lobby.get("members") as string[]).includes(uid)) throw new HttpsError("permission-denied", "You're not in this lobby.");
  const reason = blockReason(text);
  if (reason) return { sent: false, reason };
  await ref.collection("messages").add({
    uid,
    name: (lobby.get("names") as Record<string, string>)[uid] ?? "Student",
    text,
    at: FieldValue.serverTimestamp(),
    expireAt: Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000),
  });
  return { sent: true };
});

export const reportMessage = onCall<{ code?: string; messageId?: string }>(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const ref = lobbyRef(request.data?.code);
  const messageId = String(request.data?.messageId ?? "");
  if (!/^[A-Za-z0-9]{10,40}$/.test(messageId)) throw new HttpsError("invalid-argument", "Unknown message.");
  const [lobby, message] = await Promise.all([ref.get(), ref.collection("messages").doc(messageId).get()]);
  if (!lobby.exists || !(lobby.get("members") as string[]).includes(uid) || !message.exists) throw new HttpsError("not-found", "Message not found.");
  await getFirestore().collection("reports").add({
    kind: "chat",
    reporter: uid,
    reported: message.get("uid"),
    lobby: lobby.id,
    messageId: message.id,
    text: message.get("text"),
    status: "open",
    createdAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});

/** Blocked students can't join your lobbies, chat with you, or be matched with you. */
export const blockUser = onCall<{ uid?: string }>(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const other = String(request.data?.uid ?? "");
  if (!other || other === uid) throw new HttpsError("invalid-argument", "Unknown student.");
  await getFirestore().doc(`users/${uid}/blocked/${other}`).set({ at: FieldValue.serverTimestamp() });
  return { ok: true };
});

// MARK: - Ranked matchmaking

/** The rating gap accepted after waiting `ms` (PRD: "within ±100 ... widening every 10 s"). */
export function ratingWindow(ms: number): number {
  return 100 + 50 * Math.floor(ms / 10_000);
}

const QUEUE_STALE_MS = 10_000;

/**
 * Polled every few seconds while the student waits. Pairs them with the closest fresh
 * entry in the same module and time pool within both players' windows; returns the
 * match when there is one.
 */
export const findMatch = onCall<{ moduleId?: string; seconds?: number }>(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const moduleId = requireModule(request.data?.moduleId);
  const limitMs = limitFor(request.data?.seconds);
  const pool = limitMs === 10_000 ? "standard" : `extended-${limitMs / 1000}`;
  const db = getFirestore();
  const mine = db.doc(`matchQueue/${uid}`);
  await checkDuel(uid);
  const me = await player(uid, moduleId);
  const now = Date.now();

  const paired = await db.runTransaction(async (tx) => {
    const entry = await tx.get(mine);
    if (entry.exists && entry.get("matchId")) {
      tx.delete(mine);
      return { matchId: entry.get("matchId") as string, opponent: null };
    }
    const joinedAt = entry.exists && entry.get("moduleId") === moduleId && entry.get("pool") === pool ? (entry.get("joinedAt") as number) : now;
    const candidates = await tx.get(db.collection("matchQueue").where("moduleId", "==", moduleId).where("pool", "==", pool).where("matchId", "==", null));
    const fits = candidates.docs
      .filter((d) => d.id !== uid && now - (d.get("lastPoll") as number) < QUEUE_STALE_MS)
      .filter((d) => Math.abs((d.get("rating") as number) - me.rating) <= Math.max(ratingWindow(now - joinedAt), ratingWindow(now - (d.get("joinedAt") as number))))
      .sort((a, b) => Math.abs(a.get("rating") - me.rating) - Math.abs(b.get("rating") - me.rating));
    const opponent = fits[0];
    if (!opponent) {
      tx.set(mine, { moduleId, pool, rating: me.rating, joinedAt, lastPoll: now, matchId: null });
      return { matchId: null, opponent: null, joinedAt };
    }
    // Reserve the pair now; the match is created straight after the transaction.
    const matchId = getDatabase().ref("live").push().key!;
    tx.update(opponent.ref, { matchId });
    tx.delete(mine);
    return { matchId, opponent: opponent.id };
  });

  if (paired.matchId && paired.opponent) {
    if (await isBlocked(uid, paired.opponent)) {
      await db.doc(`matchQueue/${paired.opponent}`).update({ matchId: null }).catch(() => undefined);
      return { matchId: null, window: ratingWindow(0) };
    }
    await countDuel(uid);
    await countDuel(paired.opponent).catch(() => undefined); // They were within their allowance when they queued.
    const them = await player(paired.opponent, moduleId);
    const order: [string, string] = [uid, paired.opponent];
    const players = { [uid]: strip(me), [paired.opponent]: strip(them) };
    const state = live.newMatch({ mode: "ranked", moduleId, limitMs, order, players, questions: questionsFor(moduleId) }, Date.now());
    await getDatabase().ref(`live/${paired.matchId}`).set({ state, public: live.publicView(state), createdAt: Date.now() });
    return { matchId: paired.matchId };
  }
  if (paired.matchId) return { matchId: paired.matchId };
  return { matchId: null, window: ratingWindow(now - (paired.joinedAt ?? now)) };
});

function strip(p: live.Player & { rd?: number }): live.Player {
  const { rd: _, ...rest } = p;
  return rest;
}

export const cancelMatchmaking = onCall(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const ref = getFirestore().doc(`matchQueue/${uid}`);
  await getFirestore().runTransaction(async (tx) => {
    const entry = await tx.get(ref);
    if (entry.exists && !entry.get("matchId")) tx.delete(ref);
  });
  return { ok: true };
});

// MARK: - Async challenges

/**
 * Challenge a past opponent (PRD: "Async challenge: Challenge a friend or a past
 * opponent. They have 24 h to play their half. Rating applies"). Each player answers
 * every question in their own time; the rounds are decided once both halves are in.
 */
export const createChallenge = onCall<{ opponent?: string; moduleId?: string; seconds?: number }>(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const opponent = String(request.data?.opponent ?? "");
  const moduleId = requireModule(request.data?.moduleId);
  if (!opponent || opponent === uid) throw new HttpsError("invalid-argument", "Choose an opponent.");
  const db = getFirestore();
  const past = await db.collection("matches").where("players", "array-contains", uid).orderBy("createdAt", "desc").limit(100).get();
  if (!past.docs.some((m) => (m.get("players") as string[]).includes(opponent) && m.get("isBot") === false)) {
    throw new HttpsError("permission-denied", "You can challenge students you've played.");
  }
  if (await isBlocked(uid, opponent)) throw new HttpsError("permission-denied", "You can't challenge this student.");
  const open = await db.collection("challenges").where("players", "array-contains", uid).where("status", "==", "open").get();
  if (open.docs.some((c) => (c.get("players") as string[]).includes(opponent))) {
    throw new HttpsError("already-exists", "You already have a challenge open with this student.");
  }

  const [me, them] = await Promise.all([player(uid, moduleId), player(opponent, moduleId)]);
  const ref = db.collection("challenges").doc();
  const batch = db.batch();
  batch.set(ref, {
    players: [uid, opponent],
    names: { [uid]: me.name, [opponent]: them.name },
    initials: { [uid]: me.initial, [opponent]: them.initial },
    moduleId,
    limitMs: limitFor(request.data?.seconds),
    status: "open",
    done: { [uid]: false, [opponent]: false },
    createdAt: FieldValue.serverTimestamp(),
    expiresAt: Timestamp.fromMillis(Date.now() + CHALLENGE_HOURS * 60 * 60 * 1000),
  });
  batch.set(db.doc(`challengeSecrets/${ref.id}`), { questions: questionsFor(moduleId), answers: {}, servedAt: {} });
  await countDuel(uid);
  await batch.commit();
  await notify(opponent, "You've been challenged", `${me.name} has challenged you to a duel. You have 24 hours to play your half.`, { challengeId: ref.id });
  return { challengeId: ref.id };
});

type Stored = Record<string, Answer[]>;

/**
 * One step of a player's half: answers question `index` (if an answer is given) and
 * serves the next. The question the student sees is timed from when it was served.
 */
export const playChallenge = onCall<{ challengeId?: string; index?: number; answerIndex?: number | null; timeMs?: number }>(async (request) => {
  const uid = requireAuth(request.auth?.uid);
  const { challengeId, index, answerIndex, timeMs } = request.data ?? {};
  if (typeof challengeId !== "string" || !MATCH_ID.test(challengeId)) throw new HttpsError("invalid-argument", "Unknown challenge.");
  const db = getFirestore();
  const ref = db.doc(`challenges/${challengeId}`);
  const secretRef = db.doc(`challengeSecrets/${challengeId}`);
  // The challenged student's half counts as a duel when they start it.
  if (index === undefined) {
    const [challenge, secret] = await db.getAll(ref, secretRef);
    const started = ((secret.get("servedAt") as Record<string, unknown[]> | undefined)?.[uid] ?? []).length > 0;
    if (challenge.exists && (challenge.get("players") as string[])[1] === uid && !started) await countDuel(uid);
  }

  return db.runTransaction(async (tx) => {
    const [challenge, secret] = await tx.getAll(ref, secretRef);
    const players = challenge.get("players") as [string, string] | undefined;
    if (!challenge.exists || !players?.includes(uid)) throw new HttpsError("not-found", "Unknown challenge.");
    if (challenge.get("status") !== "open") throw new HttpsError("failed-precondition", "This challenge has finished.");
    if ((challenge.get("expiresAt") as Timestamp).toMillis() < Date.now()) {
      tx.update(ref, { status: "expired" });
      throw new HttpsError("deadline-exceeded", "This challenge has expired.");
    }
    const questions = secret.get("questions") as DuelQuestion[];
    const limitMs = challenge.get("limitMs") as number;
    const answers = (secret.get("answers") as Stored)[uid] ?? [];
    const servedAt = (secret.get("servedAt") as Record<string, (number | null)[]>)[uid] ?? [];
    const now = Date.now();

    // A question served but never answered (the app was closed) counts as unanswered.
    const next = () => answers.length;
    let revealed: { correct: boolean; correctIndex: number; why: string } | null = null;
    if (Number.isInteger(index) && index === next() && servedAt[index!] != null) {
      const question = questions[index!];
      const elapsed = now - servedAt[index!]!;
      const given: Answer = elapsed > limitMs + live.GRACE_MS || !Number.isInteger(answerIndex)
        ? { answerIndex: null, timeMs: limitMs }
        : { answerIndex: answerIndex!, timeMs: Math.max(MIN_ANSWER_MS, live.checkedTime(typeof timeMs === "number" ? timeMs : elapsed, elapsed)) };
      answers.push(given);
      revealed = { correct: marked(question, given, limitMs).correct, correctIndex: question.correctIndex, why: question.why };
    }
    while (answers.length < questions.length && servedAt[answers.length] != null && now - servedAt[answers.length]! > limitMs + live.GRACE_MS) {
      answers.push({ answerIndex: null, timeMs: limitMs });
    }

    const finished = answers.length >= questions.length;
    let question: DuelQuestion | null = null;
    if (!finished) {
      const i = answers.length;
      if (servedAt[i] == null) servedAt[i] = now;
      question = { ...questions[i], correctIndex: -1, why: "" };
    }
    const done = { ...(challenge.get("done") as Record<string, boolean>), [uid]: finished };
    const allAnswers = { ...(secret.get("answers") as Stored), [uid]: answers };

    let records: Record<string, PlayerRecord> | null = null;
    if (done[players[0]] && done[players[1]]) {
      const outcome = playMatchWith(questions, (p, qi) => allAnswers[players[p]]?.[qi] ?? undefined, limitMs);
      const names = challenge.get("names") as Record<string, string>;
      const initials = challenge.get("initials") as Record<string, string>;
      records = await settle(tx, challengeId, {
        mode: "challenge",
        moduleId: challenge.get("moduleId"),
        limitMs,
        order: players,
        players: Object.fromEntries(players.map((p) => [p, { name: names[p], initial: initials[p] }])),
        questions,
        rounds: outcome.rounds,
        score: outcome.score,
        winner: outcome.winner,
        forfeitedBy: null,
      });
    }

    tx.update(secretRef, { [`answers.${uid}`]: answers, [`servedAt.${uid}`]: servedAt });
    tx.update(ref, { done, ...(records ? { status: "complete", results: records } : {}) });
    return {
      revealed,
      question,
      index: finished ? null : answers.length,
      total: questions.length,
      limitMs,
      result: records?.[uid] ?? null,
    };
  });
});
