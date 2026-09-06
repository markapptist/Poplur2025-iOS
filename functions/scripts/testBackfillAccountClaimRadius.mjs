/**
 * The one-shot that gives existing accounts the total the create rule reads.
 *
 * Two properties matter and nothing else does: it reproduces the sum over each
 * owner's posts, and running it twice changes nothing. The second is what lets
 * it be the fix for a suspected drift rather than a thing to be afraid of.
 *
 *   firebase emulators:exec --only firestore \
 *     "node scripts/testBackfillAccountClaimRadius.mjs"
 */
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);

assert.ok(process.env.FIRESTORE_EMULATOR_HOST,
  "run me through `firebase emulators:exec --only firestore`");
process.env.GCLOUD_PROJECT ??= "poplur-claim-radius-backfill";

const admin = require("firebase-admin");
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const db = admin.firestore();

const { backfillAccountClaimRadius } = require("./backfillAccountClaimRadius.js");
const { ACCOUNT_CLAIM_RADIUS_FIELD } = require("../lib/accountRadius.js");

const total = async uid => (await db.collection("users").doc(uid).get())
  .data()?.[ACCOUNT_CLAIM_RADIUS_FIELD];

async function wipe() {
  for (const path of ["posts", "users", "config"]) {
    const snapshot = await db.collection(path).get();
    await Promise.all(snapshot.docs.map(doc => db.recursiveDelete(doc.ref)));
  }
}

await wipe();

// An owner with three posts: a fresh seeded drop that earned nothing, one that
// earned 1 km, and a pre-seed-era post whose whole radius is earned.
await db.collection("posts").doc("a1").set({
  userID: "alice", radius: 30_000, radiusMeters: 30_000,
  seedRadiusMeters: 30_000, organicRadiusMeters: 0,
});
await db.collection("posts").doc("a2").set({
  userID: "alice", radius: 6_000, radiusMeters: 6_000,
  seedRadiusMeters: 5_000, organicRadiusMeters: 1_000,
});
await db.collection("posts").doc("a3").set({
  userID: "alice", radius: 4_200, radiusMeters: 4_200,
});
// The older owner spelling still names an owner.
await db.collection("posts").doc("b1").set({
  userId: "bob", radius: 9_000, radiusMeters: 9_000,
  seedRadiusMeters: 5_000, organicRadiusMeters: 4_000,
});
// A post nobody owns must not stop the run.
await db.collection("posts").doc("orphan").set({ radius: 5_000, radiusMeters: 5_000 });

await db.collection("users").doc("alice").set({ username: "alice" });
await db.collection("users").doc("bob").set({ username: "bob" });
// An account that never published: it needs an explicit zero, not silence.
await db.collection("users").doc("carol").set({ username: "carol" });
// An account carrying a stale total from an interrupted run.
await db.collection("users").doc("dave")
  .set({ username: "dave", [ACCOUNT_CLAIM_RADIUS_FIELD]: 500_000 });

const dry = await backfillAccountClaimRadius({ dryRun: true });
assert.equal(dry.posts, 5);
assert.equal(dry.orphaned, 1, "a post with no owner is counted and skipped");
assert.equal(await total("alice"), undefined, "a dry run writes nothing");
assert.equal(
  (await db.collection("config").doc("claimRadius").get()).exists, false,
  "and above all does not retire the migration fallback",
);

const first = await backfillAccountClaimRadius();
assert.equal(await total("alice"), 5_200, "1 km earned plus a pre-seed post's whole 4.2 km");
assert.equal(await total("bob"), 4_000, "the older owner spelling is summed too");
assert.equal(await total("carol"), 0, "an account with no posts is entitled to nothing, said out loud");
assert.equal(await total("dave"), 0, "a stale total is corrected, not left alone");
assert.equal(first.written, 4);

const marker = await db.collection("config").doc("claimRadius").get();
assert.equal(marker.data().backfilled, true, "the fallback is retired only after every account is summed");
assert.equal(marker.data().posts, 5);

// Idempotent: a second run recomputes the same sums and writes nothing.
const second = await backfillAccountClaimRadius();
assert.equal(second.written, 0, "re-running the backfill is a no-op");
assert.equal(second.unchanged, 4);
assert.equal(await total("alice"), 5_200);

// Which is what makes it the fix for drift: corrupt a total and re-run.
await db.collection("users").doc("alice").set({ [ACCOUNT_CLAIM_RADIUS_FIELD]: 999_999 }, { merge: true });
const repair = await backfillAccountClaimRadius();
assert.equal(repair.written, 1, "only the drifted account is rewritten");
assert.equal(await total("alice"), 5_200, "and it lands back on the posts it summarises");

await wipe();
console.log("backfill account claim radius: PASS");
process.exit(0);
