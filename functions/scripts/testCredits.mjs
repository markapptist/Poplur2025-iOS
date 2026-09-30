/**
 * Credits on the server (lib/credits.js), against the Firestore emulator:
 * the welcome grant, the Map's daily die, the casino's daily spin, referral
 * codes and their limits, the Wallet's history, and two claims racing.
 *
 *   npm run build
 *   firebase emulators:exec --only firestore --project demo-poplur-credits "node scripts/testCredits.mjs"
 *
 * Refuses to run anywhere but an emulator with a demo- project, so it can
 * never write to production.
 */
import { createRequire } from "node:module";
import assert from "node:assert/strict";

const require = createRequire(import.meta.url);
const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || "";
if (!process.env.FIRESTORE_EMULATOR_HOST || !projectId.startsWith("demo-")) {
  console.error("Run under `firebase emulators:exec --only firestore --project demo-...`; refusing to touch a real project.");
  process.exit(2);
}

const admin = require("firebase-admin");
const { Timestamp } = require("firebase-admin/firestore");
const credits = require("../lib/credits.js");

admin.initializeApp({ projectId });
const db = admin.firestore();
const DAY = 24 * 60 * 60 * 1000;
const T0 = Date.UTC(2026, 9, 1, 15, 0, 0); // Thu 1 Oct 2026, 11:00 in Toronto

let clock = T0;
let randoms = [];
const created = new Map();
const ctx = {
  db,
  now: () => clock,
  // Queued values steer a roll; everything else (referral codes, retries) is random.
  random: () => (randoms.length ? randoms.shift() : Math.random()),
  accountCreatedAtMs: async uid => created.get(uid) ?? null,
};
const balance = async uid => (await db.collection("creatorCreditBalances").doc(uid).get()).data() ?? {};
const row = async id => (await db.collection("creatorCreditTransactions").doc(id).get());
const wallet = async uid => (await credits.creditsAction(ctx, uid, { action: "wallet" })).wallet;
const refusal = async (promise, code) => {
  await assert.rejects(promise, error => error.code === code, `expected ${code}`);
};

let passed = 0;
const check = async (name, fn) => { await fn(); passed += 1; console.log(`PASS ${name}`); };

await check("the first wallet read grants 30 welcome credits once and assigns a code", async () => {
  created.set("alice", T0 - 40 * DAY);
  const first = await wallet("alice");
  assert.equal(first.balance, 30);
  assert.match(first.referral.code, /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/);
  assert.equal(first.referral.canRedeem, false, "a 40-day-old account cannot use a friend's code");
  const again = await wallet("alice");
  assert.equal(again.balance, 30);
  assert.equal(again.referral.code, first.referral.code);
  assert.equal(again.history.filter(entry => entry.type === "welcome_grant").length, 1);
});

await check("the Map die pays once per UTC day and repeats the same face", async () => {
  randoms = [0.99]; // face 6, 25 credits
  const roll = (await credits.creditsAction(ctx, "alice", { action: "mapRoll" })).roll;
  assert.deepEqual({ face: roll.face, credits: roll.credits, alreadyClaimed: roll.alreadyClaimed }, { face: 6, credits: 25, alreadyClaimed: false });
  randoms = [0.0];
  const repeat = await credits.creditsAction(ctx, "alice", { action: "mapRoll" });
  assert.equal(repeat.roll.alreadyClaimed, true);
  assert.equal(repeat.roll.face, 6);
  assert.equal(repeat.wallet.balance, 55);
  assert.equal(repeat.wallet.mapRoll.day, "2026-10-01");
  clock = T0 + DAY;
  randoms = [0.0]; // face 1, 5 credits
  const tomorrow = await credits.creditsAction(ctx, "alice", { action: "mapRoll" });
  assert.equal(tomorrow.roll.alreadyClaimed, false);
  assert.equal(tomorrow.wallet.balance, 60);
  assert.ok((await row(`maproll_alice_2026-10-02`)).exists);
  clock = T0;
});

await check("a casino miss spends the day's spin without a ledger row", async () => {
  randoms = [0.1, 0.5];
  const spin = (await credits.creditsAction(ctx, "alice", { action: "casinoSpin" })).spin;
  assert.equal(spin.count, 0);
  assert.equal(spin.amount, 0);
  assert.equal(spin.alreadySpun, false);
  assert.equal((await row("casino_alice_2026-10-01")).exists, false);
  randoms = [0.99, 0.0];
  const again = await credits.creditsAction(ctx, "alice", { action: "casinoSpin" });
  assert.equal(again.spin.alreadySpun, true);
  assert.equal(again.spin.count, 0);
  assert.equal(again.wallet.balance, 60);
});

await check("the casino day turns over at Toronto midnight, not UTC", async () => {
  assert.equal(credits.casinoDay(Date.UTC(2026, 9, 2, 3, 30)), "2026-10-01"); // 23:30 in Toronto
  assert.equal(credits.casinoDay(Date.UTC(2026, 9, 2, 4, 30)), "2026-10-02"); // 00:30 in Toronto
  assert.equal(credits.isCasinoDoubleDay(Date.UTC(2026, 9, 2, 3, 30)), false);
  assert.equal(credits.isCasinoDoubleDay(Date.UTC(2026, 9, 2, 4, 30)), true);
  clock = Date.UTC(2026, 9, 2, 3, 30);
  const sameDay = await credits.creditsAction(ctx, "alice", { action: "casinoSpin" });
  assert.equal(sameDay.spin.alreadySpun, true, "still Thursday in Toronto");
  clock = T0;
});

await check("a Friday win pays double and lands in the ledger", async () => {
  clock = Date.UTC(2026, 9, 2, 16, 0); // Fri 2 Oct, noon in Toronto
  randoms = [0.5, 0.0]; // 3 of a kind, POPLUR: 3 credits, doubled
  const result = await credits.creditsAction(ctx, "alice", { action: "casinoSpin" });
  assert.deepEqual(
    { count: result.spin.count, symbolId: result.spin.symbolId, amount: result.spin.amount, doubled: result.spin.doubled },
    { count: 3, symbolId: "p", amount: 6, doubled: true },
  );
  assert.equal(result.wallet.balance, 66);
  const paid = await row("casino_alice_2026-10-02");
  assert.equal(paid.data().amount, 6);
  assert.equal(paid.data().note, "Slots 3× POPLUR · Friday 2× credits");
  clock = T0;
});

await check("the pay table and odds match what the reels draw", async () => {
  assert.equal(credits.casinoOutcome(0.2499, 0.5, false).count, 0);
  assert.equal(credits.casinoOutcome(0.25, 0.0, false).count, 3);
  assert.equal(credits.casinoOutcome(0.7499, 0.0, false).count, 3);
  assert.equal(credits.casinoOutcome(0.75, 0.0, false).count, 4);
  assert.equal(credits.casinoOutcome(0.9399, 0.0, false).count, 4);
  assert.equal(credits.casinoOutcome(0.94, 0.0, false).amount, 100);
  assert.equal(credits.casinoOutcome(0.999, 0.999, true).amount, 12, "5 globes, doubled");
  assert.deepEqual(credits.MAP_ROLL_OUTCOMES.map(outcome => outcome.credits), [5, 8, 10, 12, 15, 25]);
});

const aliceCode = (await wallet("alice")).referral.code;

await check("a new account's friend code pays both sides once", async () => {
  created.set("bob", T0 - DAY);
  const before = await wallet("bob");
  assert.equal(before.referral.canRedeem, true);
  const result = await credits.creditsAction(ctx, "bob", { action: "redeemReferral", code: ` ${aliceCode.toLowerCase()} ` });
  assert.deepEqual(result.referral, { creditsAdded: 10, referrerPaid: true });
  assert.equal(result.wallet.balance, 40);
  assert.equal(result.wallet.referral.canRedeem, false);
  assert.equal(result.wallet.referral.redeemedCode, aliceCode);
  assert.equal(result.wallet.worldRadiusUntil, T0 + DAY);
  const alice = await balance("alice");
  assert.equal(alice.availableCredits, 76);
  assert.equal(alice.referralRewardCount, 1);
  assert.equal(alice.worldRadiusUntil.toMillis(), T0 + DAY);
  const rows = (await db.collection("creatorCreditTransactions").where("type", "==", "referral_reward").get()).docs;
  assert.equal(rows.length, 2);
  for (const entry of rows) {
    assert.ok(!entry.id.includes("bob") && !entry.id.includes("alice"), "row ids carry no uid");
    assert.ok(!JSON.stringify(entry.data()).includes(entry.data().userId === "bob" ? "alice" : "bob"), "rows never name the other account");
  }
  await refusal(credits.creditsAction(ctx, "bob", { action: "redeemReferral", code: aliceCode }), "already-exists");
  assert.equal((await balance("alice")).availableCredits, 76);
});

await check("codes are refused when they are your own, unknown, malformed or too late", async () => {
  created.set("carol", T0 - 2 * DAY);
  const carol = await wallet("carol");
  await refusal(credits.creditsAction(ctx, "carol", { action: "redeemReferral", code: carol.referral.code }), "invalid-argument");
  await refusal(credits.creditsAction(ctx, "carol", { action: "redeemReferral", code: "ZZZZZZ" }), "not-found");
  await refusal(credits.creditsAction(ctx, "carol", { action: "redeemReferral", code: "AB1" }), "invalid-argument");
  created.set("dave", T0 - 15 * DAY);
  await refusal(credits.creditsAction(ctx, "dave", { action: "redeemReferral", code: aliceCode }), "failed-precondition");
  assert.equal((await wallet("carol")).balance, 30);
});

await check("a referrer at the cap stops earning, the new account is still paid", async () => {
  await db.collection("creatorCreditBalances").doc("alice").set({ referralRewardCount: 20 }, { merge: true });
  created.set("erin", T0 - DAY);
  const result = await credits.creditsAction(ctx, "erin", { action: "redeemReferral", code: aliceCode });
  assert.deepEqual(result.referral, { creditsAdded: 10, referrerPaid: false });
  assert.equal(result.wallet.balance, 40);
  assert.equal((await balance("alice")).availableCredits, 76);
  assert.equal((await wallet("alice")).referral.rewardsLeft, 0);
});

await check("the Wallet lists every kind of row newest first, with store cards", async () => {
  await db.collection("creatorCreditTransactions").doc("meshy_job1").set({
    uid: "alice", jobId: "job1", kind: "meshy_generation", credits: -25, createdAt: Timestamp.fromMillis(Date.now() + 1000),
  });
  await db.collection("creatorCreditTransactions").doc("store_abc").set({
    userId: "alice", amount: 1200, type: "store_card_purchase", cardId: "swoosh", createdAt: Timestamp.fromMillis(Date.now() + 2000),
  });
  await db.collection("verifiedStorePurchases").doc("abc").set({ userId: "alice", cardId: "swoosh" });
  const snapshot = await wallet("alice");
  assert.equal(snapshot.historyComplete, true);
  assert.deepEqual(snapshot.cards, ["swoosh"]);
  assert.equal(snapshot.history[0].type, "store_card_purchase");
  assert.equal(snapshot.history[0].cardId, "swoosh");
  assert.equal(snapshot.history[1].type, "meshy_generation");
  assert.equal(snapshot.history[1].amount, -25);
  const types = snapshot.history.map(entry => entry.type);
  for (const type of ["welcome_grant", "map_daily_roll", "casino_daily_spin", "referral_reward"]) assert.ok(types.includes(type), type);
  const times = snapshot.history.map(entry => entry.at);
  assert.deepEqual(times, [...times].sort((a, b) => b - a));
});

await check("two rolls racing on a new day pay exactly once", async () => {
  created.set("frank", T0 - 3 * DAY);
  await wallet("frank");
  randoms = [0.4, 0.4, 0.4, 0.4];
  const [a, b] = await Promise.all([credits.claimMapRoll(ctx, "frank"), credits.claimMapRoll(ctx, "frank")]);
  assert.equal([a.alreadyClaimed, b.alreadyClaimed].filter(Boolean).length, 1);
  assert.equal((await balance("frank")).availableCredits, 30 + a.credits);
});

await check("two first wallet reads racing grant the welcome once", async () => {
  created.set("gina", T0 - DAY);
  await Promise.all([wallet("gina"), wallet("gina"), wallet("gina")]);
  assert.equal((await balance("gina")).availableCredits, 30);
});

await check("unknown actions are refused and an empty call reads the wallet", async () => {
  await refusal(credits.creditsAction(ctx, "alice", { action: "mint" }), "invalid-argument");
  const plain = await credits.creditsAction(ctx, "alice", undefined);
  assert.equal(typeof plain.wallet.balance, "number");
});

console.log(`${passed} credits checks passed`);
