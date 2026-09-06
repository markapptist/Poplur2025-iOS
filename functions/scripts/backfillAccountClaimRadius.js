#!/usr/bin/env node
/**
 * Give every account the earned total that firestore.rules needs to check a
 * claim.
 *
 * `users/{uid}.claimRadiusMeters` is the sum of `organicRadiusMeters` over
 * everything that account has published. From now on the server maintains it
 * inside the same transaction that moves any post's earned radius (see
 * functions/src/accountRadius.ts); this script establishes it for the accounts
 * that already exist, and re-establishes it whenever the aggregate is
 * suspected of having drifted.
 *
 * Idempotent by construction: it never increments, it recomputes the whole sum
 * from the posts and writes that. Re-running it is how drift is corrected, so
 * running it twice is a no-op and running it after an incident is the fix.
 *
 * The last thing it writes is config/claimRadius.backfilled = true, which is
 * what tells the create rule to stop falling back to the pre-6-Sep-2026 flat
 * 25 km per-drop ceiling and start trusting the sums. That ordering matters:
 * until every account has a total, an account with no total must not be told
 * it has earned nothing.
 *
 *   node scripts/backfillAccountClaimRadius.js --dry-run
 *   node scripts/backfillAccountClaimRadius.js
 *   node scripts/backfillAccountClaimRadius.js --no-mark   # sums only
 *
 * Needs application default credentials for the Poplur project, like the other
 * admin scripts here.
 */
const admin = require("firebase-admin");
const {
  ACCOUNT_CLAIM_RADIUS_FIELD,
  accountClaimRadiusSum,
  postEarnedRadiusMeters,
  postOwnerUid,
} = require("../lib/accountRadius");

if (admin.apps.length === 0) admin.initializeApp();
const db = admin.firestore();

/** Every owner's posts, grouped. ~70 posts today, so one pass over the
 *  collection is cheaper and far easier to reason about than a query per
 *  account — and it is the only reading that cannot miss a post whose owner
 *  has no users/ document. */
async function earnedByOwner() {
  const owners = new Map();
  let posts = 0;
  let orphaned = 0;
  const snapshot = await db.collection("posts").get();
  for (const doc of snapshot.docs) {
    const post = doc.data() ?? {};
    posts += 1;
    const uid = postOwnerUid(post);
    if (!uid) {
      orphaned += 1;
      continue;
    }
    const earned = postEarnedRadiusMeters(post);
    owners.set(uid, (owners.get(uid) ?? 0) + earned);
  }
  return { owners, posts, orphaned };
}

async function backfillAccountClaimRadius({ dryRun = false, skipMark = false } = {}) {
  const { owners, posts, orphaned } = await earnedByOwner();
  // Accounts with no posts still need an explicit zero: once the marker is
  // set, "absent" and "zero" mean the same thing to the rule, but writing it
  // makes the aggregate auditable and makes a later drift check meaningful.
  const users = await db.collection("users").get();
  const targets = new Map();
  for (const doc of users.docs) targets.set(doc.id, owners.get(doc.id) ?? 0);
  for (const [uid, total] of owners) if (!targets.has(uid)) targets.set(uid, total);

  let written = 0;
  let unchanged = 0;
  let batch = db.batch();
  let staged = 0;
  const existing = new Map(users.docs.map(doc => [doc.id, doc.data() ?? {}]));

  for (const [uid, total] of targets) {
    const before = Number(existing.get(uid)?.[ACCOUNT_CLAIM_RADIUS_FIELD]);
    if (Number.isFinite(before) && Math.round(before) === total) {
      unchanged += 1;
      continue;
    }
    console.log(`  ${uid}: ${Number.isFinite(before) ? Math.round(before) : "—"} → ${total} m`);
    written += 1;
    if (dryRun) continue;
    batch.set(db.collection("users").doc(uid), {
      [ACCOUNT_CLAIM_RADIUS_FIELD]: total,
      claimRadiusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    staged += 1;
    if (staged === 400) {
      await batch.commit();
      batch = db.batch();
      staged = 0;
    }
  }
  if (!dryRun && staged > 0) await batch.commit();

  // Only after every account has a total: the marker retires the migration
  // fallback, so setting it early is what would lock somebody out.
  if (!dryRun && !skipMark) {
    await db.collection("config").doc("claimRadius").set({
      backfilled: true,
      backfilledAt: admin.firestore.FieldValue.serverTimestamp(),
      accounts: targets.size,
      posts,
    }, { merge: true });
  }

  console.log([
    `[backfillAccountClaimRadius]${dryRun ? " DRY RUN" : ""}`,
    `${posts} posts (${orphaned} with no owner, skipped),`,
    `${targets.size} accounts,`,
    `${written} written, ${unchanged} already correct.`,
    skipMark || dryRun ? "config/claimRadius NOT marked." : "config/claimRadius marked backfilled.",
  ].join(" "));
  return { posts, orphaned, accounts: targets.size, written, unchanged };
}

module.exports = { backfillAccountClaimRadius, accountClaimRadiusSum };

if (require.main === module) {
  backfillAccountClaimRadius({
    dryRun: process.argv.includes("--dry-run"),
    skipMark: process.argv.includes("--no-mark"),
  }).then(() => process.exit(0)).catch(error => {
    console.error(error);
    process.exit(1);
  });
}
