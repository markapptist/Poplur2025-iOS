/**
 * The aggregate, maintained by the real transactions, against a real Firestore.
 *
 * `users/{uid}.claimRadiusMeters` is what firestore.rules reads instead of a
 * sum it cannot compute, so the only property that matters is that it never
 * drifts from the posts it stands for. These tests run recordPostEngagement
 * and radiusDecay themselves — no stand-in for the transaction — and after
 * every step re-sum the owner's posts and demand the two agree.
 *
 *   firebase emulators:exec --only firestore \
 *     "node scripts/testEngagementAggregate.mjs"
 */
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);

assert.ok(process.env.FIRESTORE_EMULATOR_HOST,
  "run me through `firebase emulators:exec --only firestore`");
process.env.GCLOUD_PROJECT ??= "poplur-claim-radius-aggregate";

const admin = require("firebase-admin");
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const { recordPostEngagement } = require("../lib/postEngagement.js");
const { radiusDecay } = require("../lib/radiusDecay.js");
const { accountRadiusOnPostDeleted } = require("../lib/accountRadiusOnPostDeleted.js");
const {
  ACCOUNT_CLAIM_RADIUS_FIELD,
  accountClaimRadiusSum,
} = require("../lib/accountRadius.js");

const OWNER = "owner-uid";
const ACTOR = "actor-uid";
const SEED = 30_000;

async function wipe() {
  for (const collection of ["posts", "users"]) {
    const snapshot = await db.collection(collection).get();
    await Promise.all(snapshot.docs.map(doc => db.recursiveDelete(doc.ref)));
  }
}

async function givenPost(id, extra = {}) {
  await db.collection("posts").doc(id).set({
    userID: OWNER,
    audience: "public",
    status: "published",
    radius: SEED,
    radiusMeters: SEED,
    seedRadiusMeters: SEED,
    organicRadiusMeters: 0,
    viewCount: 0,
    ...extra,
  });
}

const engage = (kind, eventId, postId = "p1", uid = ACTOR) =>
  recordPostEngagement.run({ data: { postId, eventId, kind }, auth: { uid } });

async function aggregate() {
  const user = await db.collection("users").doc(OWNER).get();
  const value = user.data()?.[ACCOUNT_CLAIM_RADIUS_FIELD];
  return value === undefined ? undefined : Number(value);
}

/** The whole point: the number the rule reads equals the number a sum over the
 *  posts would produce. Checked after every step, never only at the end. */
async function assertNoDrift(why) {
  const posts = await db.collection("posts").where("userID", "==", OWNER).get();
  const summed = accountClaimRadiusSum(posts.docs.map(doc => doc.data()));
  assert.equal(await aggregate() ?? 0, summed, `aggregate drifted from the posts: ${why}`);
  return summed;
}

// ── A view, a like and a comment ─────────────────────────────────────────
await wipe();
await db.collection("users").doc(OWNER).set({ username: "owner" });
await db.collection("users").doc(ACTOR).set({ username: "actor" });
await givenPost("p1");

assert.equal(await aggregate(), undefined, "an account starts with no aggregate at all");

const viewed = await engage("view", "evt_view_0000000001");
assert.equal(viewed.applied, true);
assert.equal(viewed.radiusDeltaMeters, 1_000);
assert.equal(await aggregate(), 1_000,
  "the first view creates the aggregate on an account document that had no such field");
await assertNoDrift("after the first view");

await engage("like", "evt_like_0000000001");
assert.equal(await aggregate(), 2_000, "a like moves the aggregate by what it moved the post by");
await assertNoDrift("after a like");

await engage("comment", "evt_comment_000000001");
const afterComment = await assertNoDrift("after a comment");
assert.ok(afterComment > 2_000, "the comment earned something");

// Replaying the same event id returns the stored result and moves nothing.
const replay = await engage("like", "evt_like_0000000001");
assert.equal(replay.duplicate, true);
assert.equal(await aggregate(), afterComment, "a retried event does not pay twice");

// A second comment pays nothing, so it must not write a zero step either.
await engage("comment", "evt_comment_000000002");
assert.equal(await aggregate(), afterComment, "an unpaid engagement leaves the aggregate alone");

// ── You cannot grow your own entitlement ─────────────────────────────────
await engage("view", "evt_self_00000000001", "p1", OWNER);
await engage("like", "evt_self_00000000002", "p1", OWNER);
assert.equal(await aggregate(), afterComment,
  "an owner engaging with their own post earns no radius and therefore no entitlement");

// ── A second post adds to the same account ───────────────────────────────
await givenPost("p2");
await engage("view", "evt_second_000000001", "p2");
const twoPosts = await assertNoDrift("with two posts on one account");
assert.equal(twoPosts, afterComment + 1_000, "entitlement is the sum across posts");

// ── Decay takes it back ──────────────────────────────────────────────────
const thirtyDaysAgo = admin.firestore.Timestamp.fromMillis(Date.now() - 30 * 86_400_000);
await db.collection("posts").doc("p1").update({ decayedAt: thirtyDaysAgo });
await db.collection("posts").doc("p2").update({ decayedAt: thirtyDaysAgo });
await radiusDecay.run({});
const afterDecay = await assertNoDrift("after decay");
assert.ok(afterDecay < twoPosts, "decay really took entitlement back");

// Decay all the way to the floor leaves exactly zero, not a residue.
await db.collection("posts").doc("p1")
  .update({ decayedAt: admin.firestore.Timestamp.fromMillis(Date.now() - 3_650 * 86_400_000) });
await db.collection("posts").doc("p2")
  .update({ decayedAt: admin.firestore.Timestamp.fromMillis(Date.now() - 3_650 * 86_400_000) });
await radiusDecay.run({});
assert.equal(await assertNoDrift("after decaying to the floor"), 0,
  "an account whose posts decayed to nothing is entitled to nothing");
assert.equal(await aggregate(), 0, "and lands on exactly zero, never below it");

// ── An owner with no account document yet ────────────────────────────────
// The aggregate is a merge write precisely so a missing users/{uid} row cannot
// fail somebody else's like.
await wipe();
await db.collection("users").doc(ACTOR).set({ username: "actor" });
await givenPost("p1");
await engage("view", "evt_nouser_000000001");
assert.equal(await aggregate(), 1_000, "the account document is created rather than the write failing");
await assertNoDrift("with an owner who had no account document");

// ── A deleted post takes its entitlement with it ─────────────────────────
// Otherwise "earn a kilometre, delete the post, keep the kilometre" is the
// cheapest way to hold entitlement that radiusDecay can never reach.
await wipe();
await db.collection("users").doc(ACTOR).set({ username: "actor" });
await givenPost("p1");
await givenPost("p2");
await engage("view", "evt_del_0000000000001", "p1");
await engage("view", "evt_del_0000000000002", "p2");
assert.equal(await aggregate(), 2_000);

const doomed = await db.collection("posts").doc("p1").get();
await db.collection("posts").doc("p1").delete();
const deletion = { data: doomed, params: { postId: "p1" } };
await accountRadiusOnPostDeleted.run(deletion);
assert.equal(await aggregate(), 1_000, "the deleted post's earned radius goes with it");
await assertNoDrift("after a post was deleted");

// Cloud Functions deliver at least once; the aggregate must move at most once.
await accountRadiusOnPostDeleted.run(deletion);
await accountRadiusOnPostDeleted.run(deletion);
assert.equal(await aggregate(), 1_000, "a redelivered delete takes nothing a second time");
await assertNoDrift("after the delete was redelivered");

// A post that never earned anything moves nothing, and writes no receipt.
await givenPost("p3");
const unearned = await db.collection("posts").doc("p3").get();
await db.collection("posts").doc("p3").delete();
await accountRadiusOnPostDeleted.run({ data: unearned, params: { postId: "p3" } });
assert.equal(await aggregate(), 1_000, "deleting a post that earned nothing changes nothing");

// ── The backfill agrees with the maintenance ─────────────────────────────
// Recomputing from the posts must land on exactly what the transactions built,
// or re-running the backfill after an incident would move honest accounts.
await engage("like", "evt_backfill_00000001", "p2");
const built = await aggregate();
const posts = await db.collection("posts").where("userID", "==", OWNER).get();
assert.equal(accountClaimRadiusSum(posts.docs.map(doc => doc.data())), built,
  "a fresh sum reproduces the maintained aggregate exactly");

await wipe();
console.log("engagement aggregate: PASS");
process.exit(0);
