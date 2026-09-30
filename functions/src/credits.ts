import { createHash, randomInt } from "crypto";
import * as admin from "firebase-admin";
import {
  DocumentData,
  DocumentReference,
  FieldValue,
  Firestore,
  QueryDocumentSnapshot,
  Timestamp,
  Transaction,
} from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";

/**
 * Poplur credits, kept on the server.
 *
 * The web layer used to keep its own ledger in localStorage: the welcome
 * grant, the Map's daily die, the casino's daily spin and the referral reward
 * were all decided and written on the phone. Clearing storage or moving the
 * clock minted credits, none of it reached the account, and the number the
 * Wallet showed was not the one the server charged against: card purchases
 * are verified and granted here (cardPurchases.ts), and Meshy and AI jobs
 * already debit here.
 *
 * This is the one door for everything else. The server rolls every outcome,
 * owns every daily gate, and writes the balance and its ledger row in one
 * transaction, so the Wallet shows exactly what the account holds:
 *
 *   wallet          the balance, the latest ledger rows, the cards bought on
 *                   the account, today's claims and the referral state. The
 *                   first call grants the welcome credits and assigns the
 *                   account's referral code.
 *   mapRoll         the Map's free daily die, once per UTC day.
 *   casinoSpin      the casino's free daily spin, once per Toronto day.
 *   redeemReferral  a new account enters a friend's code; both get credits.
 *
 * Every answer carries the fresh wallet, so the phone never computes a
 * balance of its own.
 *
 * State stays on the records account deletion already removes: the daily
 * claims and the referral code live on creatorCreditBalances/{uid}, every row
 * is a creatorCreditTransactions document owned by `userId`, and a referral
 * row never stores the other account's uid.
 */

const REGION = "us-central1";
const BALANCES = "creatorCreditBalances";
const LEDGER = "creatorCreditTransactions";
const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
const HISTORY_LIMIT = 25;

/** Every account starts with enough for one Meshy cube (meshyModels.ts). */
export const WELCOME_CREDITS = 30;
/** What an accepted referral pays each side. */
export const REFERRAL_CREDITS = 10;
/** A friend's code only counts for an account this new. */
export const REFERRAL_REDEEM_WINDOW_MS = 14 * DAY_MS;
/** Rewarded referrals per referrer, lifetime. The new account is always paid. */
export const MAX_REFERRAL_REWARDS = 20;
/** Each accepted referral banks a day of worldwide radius for both accounts. */
export const WORLD_RADIUS_GRANT_MS = DAY_MS;
export const MAX_BANKED_WORLD_RADIUS_MS = 30 * DAY_MS;
/** The casino's day turns over at midnight here; Friday pays double. */
export const CASINO_TIME_ZONE = "America/Toronto";
/** Easy to read aloud: no O/0 or I/1. */
const REFERRAL_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const REFERRAL_CODE = /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/;

/** The die's six faces. Mirrors RADIUS_REWARD_OUTCOMES in
 *  poplur-clay-map/src/radiusRewardRoll.ts, which draws them. */
export const MAP_ROLL_OUTCOMES = [
  { face: 1, title: "Pocket change", credits: 5 },
  { face: 2, title: "Street bonus", credits: 8 },
  { face: 3, title: "Local reward", credits: 10 },
  { face: 4, title: "Hot Area scout", credits: 12 },
  { face: 5, title: "Territory dividend", credits: 15 },
  { face: 6, title: "Community chest", credits: 25 },
] as const;

/** The reels' symbols and what 3, 4 and 5 of a kind pay on the middle line.
 *  Mirrors SYMBOLS in poplur-clay-map/src/CasinoScreen.tsx, which draws them
 *  and prints the pay table. */
export const CASINO_SYMBOLS = [
  { id: "p", name: "POPLUR", pays: [3, 10, 100] },
  { id: "star", name: "STAR", pays: [2, 8, 25] },
  { id: "headphones", name: "BEATS", pays: [2, 6, 20] },
  { id: "phone", name: "PHONE", pays: [2, 5, 16] },
  { id: "sneaker", name: "KICKS", pays: [1, 5, 15] },
  { id: "coins", name: "COINS", pays: [1, 4, 12] },
  { id: "shades", name: "SHADES", pays: [1, 4, 10] },
  { id: "backpack", name: "PACK", pays: [1, 3, 10] },
  { id: "camera", name: "CAMERA", pays: [1, 3, 8] },
  { id: "globe", name: "GLOBE", pays: [1, 2, 6] },
] as const;

export interface CreditsContext {
  db: Firestore;
  now: () => number;
  /** Uniform in [0, 1). */
  random: () => number;
  /** When the Firebase Auth account was created, in epoch ms. */
  accountCreatedAtMs: (uid: string) => Promise<number | null>;
}

export interface MapRollClaim {
  day: string;
  face: number;
  credits: number;
  title: string;
}

export interface CasinoClaim {
  day: string;
  /** 0 is a miss; 3, 4 or 5 of `symbolId` from the left otherwise. */
  count: number;
  symbolId: string | null;
  amount: number;
  doubled: boolean;
  line: string;
}

export interface HistoryEntry {
  id: string;
  type: string;
  amount: number;
  note: string | null;
  cardId: string | null;
  at: number;
}

export interface WalletSnapshot {
  balance: number;
  reserved: number;
  history: HistoryEntry[];
  /** False when the ledger could not be read; the balance is still exact. */
  historyComplete: boolean;
  cards: string[];
  referral: {
    code: string | null;
    redeemedCode: string | null;
    canRedeem: boolean;
    rewardsLeft: number;
    credits: number;
  };
  worldRadiusUntil: number;
  today: { mapRoll: string; casino: string };
  mapRoll: MapRollClaim | null;
  casino: CasinoClaim | null;
  serverTime: number;
}

export function utcDay(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10);
}

const casinoCalendar = new Intl.DateTimeFormat("en-US", {
  timeZone: CASINO_TIME_ZONE,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  weekday: "short",
});

function casinoCalendarParts(ms: number): Record<string, string> {
  return Object.fromEntries(casinoCalendar.formatToParts(new Date(ms)).map(part => [part.type, part.value]));
}

export function casinoDay(ms: number): string {
  const parts = casinoCalendarParts(ms);
  return `${parts.year}-${parts.month}-${parts.day}`;
}

export function isCasinoDoubleDay(ms: number): boolean {
  return casinoCalendarParts(ms).weekday === "Fri";
}

function pickIndex(unit: number, length: number): number {
  const safe = Number.isFinite(unit) ? unit : 0;
  return Math.min(length - 1, Math.max(0, Math.floor(safe * length)));
}

export function mapRollOutcome(unit: number): (typeof MAP_ROLL_OUTCOMES)[number] {
  return MAP_ROLL_OUTCOMES[pickIndex(unit, MAP_ROLL_OUTCOMES.length)];
}

/** Mostly small wins and rare big ones, the odds the on-device roll used. */
export function casinoOutcome(
  tierUnit: number,
  symbolUnit: number,
  doubled: boolean
): Omit<CasinoClaim, "day"> {
  const tier = Number.isFinite(tierUnit) ? tierUnit : 0;
  const count = tier < 0.25 ? 0 : tier < 0.75 ? 3 : tier < 0.94 ? 4 : 5;
  if (count === 0) return { count: 0, symbolId: null, amount: 0, doubled, line: "" };
  const symbol = CASINO_SYMBOLS[pickIndex(symbolUnit, CASINO_SYMBOLS.length)];
  return {
    count,
    symbolId: symbol.id,
    amount: symbol.pays[count - 3] * (doubled ? 2 : 1),
    doubled,
    line: `Slots ${count}× ${symbol.name}${doubled ? " · Friday 2× credits" : ""}`,
  };
}

export function normalizeReferralCode(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const code = value.toUpperCase().replace(/[\s-]/g, "");
  return REFERRAL_CODE.test(code) ? code : null;
}

function newReferralCode(random: () => number): string {
  let code = "";
  for (let i = 0; i < 6; i += 1) code += REFERRAL_ALPHABET[pickIndex(random(), REFERRAL_ALPHABET.length)];
  return code;
}

function wholeCredits(value: unknown): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= 0 ? value : 0;
}

function millis(value: unknown): number {
  return value instanceof Timestamp ? value.toMillis() : 0;
}

/** Keys a referral row without storing the other account's uid in it. */
function referralTag(uid: string): string {
  return createHash("sha256").update(uid, "utf8").digest("hex").slice(0, 24);
}

function validMapRoll(value: unknown): MapRollClaim | null {
  const claim = value as Partial<MapRollClaim> | null;
  const outcome = MAP_ROLL_OUTCOMES.find(entry => entry.face === claim?.face);
  if (!outcome || typeof claim?.day !== "string") return null;
  return { day: claim.day, face: outcome.face, credits: outcome.credits, title: outcome.title };
}

function validCasino(value: unknown): CasinoClaim | null {
  const claim = value as Partial<CasinoClaim> | null;
  if (!claim || typeof claim.day !== "string" || ![0, 3, 4, 5].includes(Number(claim.count))) return null;
  return {
    day: claim.day,
    count: Number(claim.count),
    symbolId: typeof claim.symbolId === "string" ? claim.symbolId : null,
    amount: wholeCredits(claim.amount),
    doubled: claim.doubled === true,
    line: typeof claim.line === "string" ? claim.line : "",
  };
}

/** Adds `amount` to the balance inside `transaction`; returns the new balance. */
function credit(
  transaction: Transaction,
  balanceRef: DocumentReference,
  current: DocumentData,
  amount: number,
  extra: Record<string, unknown> = {}
): number {
  const available = wholeCredits(current.availableCredits) + amount;
  transaction.set(balanceRef, {
    availableCredits: available,
    lifetimeEarned: wholeCredits(current.lifetimeEarned) + amount,
    updatedAt: FieldValue.serverTimestamp(),
    ...extra,
  }, { merge: true });
  return available;
}

function extendWorldRadius(current: unknown, now: number): Timestamp {
  const from = Math.max(now, millis(current));
  return Timestamp.fromMillis(Math.min(from + WORLD_RADIUS_GRANT_MS, now + MAX_BANKED_WORLD_RADIUS_MS));
}

/**
 * The welcome credits, the account's referral code and its creation time.
 * Idempotent: the welcome row's id is the account's, so it is written once.
 */
export async function ensureAccount(ctx: CreditsContext, uid: string): Promise<void> {
  const balanceRef = ctx.db.collection(BALANCES).doc(uid);
  const welcomeRef = ctx.db.collection(LEDGER).doc(`welcome_${uid}`);
  const known = (await balanceRef.get()).data() ?? {};
  const needsCode = !normalizeReferralCode(known.referralCode);
  const needsCreatedAt = !(known.accountCreatedAt instanceof Timestamp);
  if (known.welcomeGrantedAt && !needsCode && !needsCreatedAt) return;

  const createdAtMs = needsCreatedAt ? await ctx.accountCreatedAtMs(uid).catch(() => null) : null;
  const candidates = needsCode ? Array.from({ length: 4 }, () => newReferralCode(ctx.random)) : [];

  await ctx.db.runTransaction(async transaction => {
    const [balance, welcome, ...taken] = await Promise.all([
      transaction.get(balanceRef),
      transaction.get(welcomeRef),
      ...candidates.map(code =>
        transaction.get(ctx.db.collection(BALANCES).where("referralCode", "==", code).limit(1))
      ),
    ]);
    const current = balance.data() ?? {};
    const extra: Record<string, unknown> = {};
    if (!normalizeReferralCode(current.referralCode)) {
      const free = candidates.find((_, index) => taken[index].empty);
      if (free) extra.referralCode = free;
    }
    if (!(current.accountCreatedAt instanceof Timestamp) && createdAtMs) {
      extra.accountCreatedAt = Timestamp.fromMillis(createdAtMs);
    }
    if (!current.welcomeGrantedAt && !welcome.exists) {
      credit(transaction, balanceRef, current, WELCOME_CREDITS, {
        ...extra,
        welcomeGrantedAt: FieldValue.serverTimestamp(),
      });
      transaction.create(welcomeRef, {
        userId: uid,
        amount: WELCOME_CREDITS,
        type: "welcome_grant",
        note: "Welcome to Poplur",
        createdAt: FieldValue.serverTimestamp(),
      });
      return;
    }
    if (!current.welcomeGrantedAt) extra.welcomeGrantedAt = FieldValue.serverTimestamp();
    if (Object.keys(extra).length > 0) {
      transaction.set(balanceRef, { ...extra, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    }
  });
}

function historyEntry(row: QueryDocumentSnapshot): HistoryEntry | null {
  const data = row.data();
  // Meshy rows predate the shared shape: `credits` and `kind` rather than
  // `amount` and `type` (meshyModels.ts).
  const amount = typeof data.amount === "number" ? data.amount : data.credits;
  if (typeof amount !== "number" || !Number.isFinite(amount)) return null;
  const type = typeof data.type === "string" ? data.type : typeof data.kind === "string" ? data.kind : "credits";
  return {
    id: row.id,
    type,
    amount: Math.trunc(amount),
    note: typeof data.note === "string" ? data.note.slice(0, 120) : null,
    cardId: typeof data.cardId === "string" ? data.cardId : null,
    at: millis(data.createdAt),
  };
}

async function readHistory(ctx: CreditsContext, uid: string): Promise<{ entries: HistoryEntry[]; complete: boolean }> {
  try {
    const ledger = ctx.db.collection(LEDGER);
    const [rows, meshyRows] = await Promise.all([
      ledger.where("userId", "==", uid).orderBy("createdAt", "desc").limit(HISTORY_LIMIT).get(),
      ledger.where("uid", "==", uid).limit(HISTORY_LIMIT).get(),
    ]);
    const entries = [...rows.docs, ...meshyRows.docs]
      .map(historyEntry)
      .filter((entry): entry is HistoryEntry => entry !== null)
      .sort((a, b) => b.at - a.at)
      .slice(0, HISTORY_LIMIT);
    return { entries, complete: true };
  } catch (error) {
    logger.warn("credits_history_unavailable", {
      uidSuffix: uid.slice(-6),
      error: error instanceof Error ? error.message.slice(0, 240) : "unknown",
    });
    return { entries: [], complete: false };
  }
}

export async function walletSnapshot(ctx: CreditsContext, uid: string): Promise<WalletSnapshot> {
  const now = ctx.now();
  const [balance, receipts, history] = await Promise.all([
    ctx.db.collection(BALANCES).doc(uid).get(),
    ctx.db.collection("verifiedStorePurchases").where("userId", "==", uid).get(),
    readHistory(ctx, uid),
  ]);
  const data = balance.data() ?? {};
  const cards = [...new Set(receipts.docs
    .map(receipt => receipt.data().cardId)
    .filter((cardId): cardId is string => typeof cardId === "string" && cardId.length > 0))];
  const redeemedCode = normalizeReferralCode(data.referralRedeemedCode);
  const createdAt = millis(data.accountCreatedAt);
  return {
    balance: wholeCredits(data.availableCredits),
    reserved: wholeCredits(data.reservedCredits),
    history: history.entries,
    historyComplete: history.complete,
    cards,
    referral: {
      code: normalizeReferralCode(data.referralCode),
      redeemedCode,
      canRedeem: !redeemedCode && createdAt > 0 && now - createdAt <= REFERRAL_REDEEM_WINDOW_MS,
      rewardsLeft: Math.max(0, MAX_REFERRAL_REWARDS - wholeCredits(data.referralRewardCount)),
      credits: REFERRAL_CREDITS,
    },
    worldRadiusUntil: millis(data.worldRadiusUntil),
    today: { mapRoll: utcDay(now), casino: casinoDay(now) },
    mapRoll: validMapRoll(data.mapRoll),
    casino: validCasino(data.casino),
    serverTime: now,
  };
}

export async function claimMapRoll(
  ctx: CreditsContext,
  uid: string
): Promise<MapRollClaim & { alreadyClaimed: boolean }> {
  const day = utcDay(ctx.now());
  const balanceRef = ctx.db.collection(BALANCES).doc(uid);
  const rowRef = ctx.db.collection(LEDGER).doc(`maproll_${uid}_${day}`);
  return ctx.db.runTransaction(async transaction => {
    const [balance, row] = await Promise.all([transaction.get(balanceRef), transaction.get(rowRef)]);
    const current = balance.data() ?? {};
    const claimed = validMapRoll(current.mapRoll);
    if (claimed?.day === day) return { ...claimed, alreadyClaimed: true };
    if (row.exists) {
      // The row is the payment; restore the day's marker from it.
      const restored = validMapRoll({ day, face: row.data()?.face });
      if (!restored) throw new HttpsError("internal", "Today's roll could not be read.");
      transaction.set(balanceRef, { mapRoll: restored, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      return { ...restored, alreadyClaimed: true };
    }
    const outcome = mapRollOutcome(ctx.random());
    const claim: MapRollClaim = { day, face: outcome.face, credits: outcome.credits, title: outcome.title };
    credit(transaction, balanceRef, current, outcome.credits, { mapRoll: claim });
    transaction.create(rowRef, {
      userId: uid,
      amount: outcome.credits,
      type: "map_daily_roll",
      note: `${outcome.title} — daily Map roll`,
      face: outcome.face,
      day,
      createdAt: FieldValue.serverTimestamp(),
    });
    return { ...claim, alreadyClaimed: false };
  });
}

export async function spinCasino(
  ctx: CreditsContext,
  uid: string
): Promise<CasinoClaim & { alreadySpun: boolean }> {
  const now = ctx.now();
  const day = casinoDay(now);
  const balanceRef = ctx.db.collection(BALANCES).doc(uid);
  const rowRef = ctx.db.collection(LEDGER).doc(`casino_${uid}_${day}`);
  return ctx.db.runTransaction(async transaction => {
    const [balance, row] = await Promise.all([transaction.get(balanceRef), transaction.get(rowRef)]);
    const current = balance.data() ?? {};
    const spun = validCasino(current.casino);
    if (spun?.day === day) return { ...spun, alreadySpun: true };
    if (row.exists) {
      const restored = validCasino({ ...row.data(), day });
      if (!restored) throw new HttpsError("internal", "Today's spin could not be read.");
      transaction.set(balanceRef, { casino: restored, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      return { ...restored, alreadySpun: true };
    }
    const claim: CasinoClaim = { day, ...casinoOutcome(ctx.random(), ctx.random(), isCasinoDoubleDay(now)) };
    if (claim.amount > 0) {
      credit(transaction, balanceRef, current, claim.amount, { casino: claim });
      transaction.create(rowRef, {
        userId: uid,
        amount: claim.amount,
        type: "casino_daily_spin",
        note: claim.line,
        count: claim.count,
        symbolId: claim.symbolId,
        doubled: claim.doubled,
        line: claim.line,
        day,
        createdAt: FieldValue.serverTimestamp(),
      });
    } else {
      // A miss still spends the day's spin; there is simply no money to record.
      transaction.set(balanceRef, { casino: claim, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    }
    return { ...claim, alreadySpun: false };
  });
}

export async function redeemReferral(
  ctx: CreditsContext,
  uid: string,
  rawCode: unknown
): Promise<{ creditsAdded: number; referrerPaid: boolean }> {
  const code = normalizeReferralCode(rawCode);
  if (!code) throw new HttpsError("invalid-argument", "Enter the 6-character code your friend shared.");
  const now = ctx.now();
  const balances = ctx.db.collection(BALANCES);
  const redeemerRef = balances.doc(uid);
  const tag = referralTag(uid);
  return ctx.db.runTransaction(async transaction => {
    const [redeemer, owners] = await Promise.all([
      transaction.get(redeemerRef),
      transaction.get(balances.where("referralCode", "==", code).limit(2)),
    ]);
    const me = redeemer.data() ?? {};
    if (normalizeReferralCode(me.referralRedeemedCode)) {
      throw new HttpsError("already-exists", "You've already used a friend's code.");
    }
    if (normalizeReferralCode(me.referralCode) === code || owners.docs.some(owner => owner.id === uid)) {
      throw new HttpsError("invalid-argument", "That's your own code. Share it with a friend instead.");
    }
    const createdAt = millis(me.accountCreatedAt);
    if (!createdAt || now - createdAt > REFERRAL_REDEEM_WINDOW_MS) {
      throw new HttpsError("failed-precondition", "Friend codes work during your first 14 days on Poplur.");
    }
    if (owners.size !== 1) {
      throw new HttpsError("not-found", "That code isn't on Poplur. Check it with your friend.");
    }
    const referrer = owners.docs[0];
    const referrerData = referrer.data();
    const referrerCount = wholeCredits(referrerData.referralRewardCount);
    const referrerPaid = referrerCount < MAX_REFERRAL_REWARDS;

    credit(transaction, redeemerRef, me, REFERRAL_CREDITS, {
      referralRedeemedCode: code,
      referralRedeemedAt: FieldValue.serverTimestamp(),
      worldRadiusUntil: extendWorldRadius(me.worldRadiusUntil, now),
    });
    transaction.create(ctx.db.collection(LEDGER).doc(`referral_in_${tag}`), {
      userId: uid,
      amount: REFERRAL_CREDITS,
      type: "referral_reward",
      note: "You joined with a friend's code",
      createdAt: FieldValue.serverTimestamp(),
    });
    if (referrerPaid) {
      credit(transaction, referrer.ref, referrerData, REFERRAL_CREDITS, {
        referralRewardCount: referrerCount + 1,
        worldRadiusUntil: extendWorldRadius(referrerData.worldRadiusUntil, now),
      });
      transaction.create(ctx.db.collection(LEDGER).doc(`referral_out_${tag}`), {
        userId: referrer.id,
        amount: REFERRAL_CREDITS,
        type: "referral_reward",
        note: "A friend joined with your code",
        createdAt: FieldValue.serverTimestamp(),
      });
    }
    return { creditsAdded: REFERRAL_CREDITS, referrerPaid };
  });
}

export async function creditsAction(
  ctx: CreditsContext,
  uid: string,
  data: unknown
): Promise<Record<string, unknown>> {
  const body = (data && typeof data === "object" && !Array.isArray(data) ? data : {}) as Record<string, unknown>;
  const action = body.action ?? "wallet";
  await ensureAccount(ctx, uid);
  switch (action) {
    case "wallet":
      return { wallet: await walletSnapshot(ctx, uid) };
    case "mapRoll": {
      const roll = await claimMapRoll(ctx, uid);
      return { roll, wallet: await walletSnapshot(ctx, uid) };
    }
    case "casinoSpin": {
      const spin = await spinCasino(ctx, uid);
      return { spin, wallet: await walletSnapshot(ctx, uid) };
    }
    case "redeemReferral": {
      const referral = await redeemReferral(ctx, uid, body.code);
      return { referral, wallet: await walletSnapshot(ctx, uid) };
    }
    default:
      throw new HttpsError("invalid-argument", "Unknown credits action.");
  }
}

function liveContext(): CreditsContext {
  if (admin.apps.length === 0) admin.initializeApp();
  return {
    db: admin.firestore(),
    now: () => Date.now(),
    random: () => randomInt(0, 2 ** 32) / 2 ** 32,
    accountCreatedAtMs: async uid => {
      const created = Date.parse((await admin.auth().getUser(uid)).metadata.creationTime);
      return Number.isFinite(created) ? created : null;
    },
  };
}

/**
 * Called by the web layer with the shell's ID token (the callable protocol
 * over fetch, like notificationPreferences), so it cannot carry App Check.
 * One function for every action keeps a single Cloud Run service against the
 * region's CPU quota.
 */
export const poplurCredits = onCall(
  { region: REGION, timeoutSeconds: 30, memory: "512MiB", maxInstances: 3 },
  async request => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in to use Poplur credits.");
    try {
      return await creditsAction(liveContext(), uid, request.data);
    } catch (error) {
      if (error instanceof HttpsError) throw error;
      logger.error("credits_action_failed", {
        uidSuffix: uid.slice(-6),
        action: typeof request.data?.action === "string" ? request.data.action.slice(0, 32) : "wallet",
        error: error instanceof Error ? error.message.slice(0, 240) : "unknown",
      });
      throw new HttpsError("unavailable", "Credits are unavailable right now. Try again in a moment.");
    }
  }
);
