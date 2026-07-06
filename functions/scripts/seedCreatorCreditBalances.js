#!/usr/bin/env node

const admin = require("firebase-admin");

const uidArgs = process.argv.slice(2).filter(Boolean);
const envUids = (process.env.TEST_USER_UIDS || "")
  .split(",")
  .map((uid) => uid.trim())
  .filter(Boolean);
const uids = Array.from(new Set([...uidArgs, ...envUids]));
const credits = Number.parseInt(process.env.CREATOR_TEST_CREDITS || "500", 10);
const planTier = process.env.CREATOR_TEST_PLAN_TIER || "creator_test";

if (uids.length === 0) {
  console.error("Usage: npm run seed:creator-credits -- <uid> [uid...]");
  console.error("Or set TEST_USER_UIDS=uid1,uid2. Optional: CREATOR_TEST_CREDITS=500 CREATOR_TEST_PLAN_TIER=creator_test");
  process.exit(1);
}

if (!Number.isFinite(credits) || credits < 0) {
  console.error("CREATOR_TEST_CREDITS must be a non-negative number.");
  process.exit(1);
}

admin.initializeApp();

async function main() {
  const db = admin.firestore();
  const batch = db.batch();
  const now = admin.firestore.FieldValue.serverTimestamp();

  for (const uid of uids) {
    const balanceRef = db.collection("creatorCreditBalances").doc(uid);
    batch.set(
      balanceRef,
      {
        availableCredits: credits,
        reservedCredits: 0,
        lifetimeEarned: admin.firestore.FieldValue.increment(credits),
        lifetimeSpent: 0,
        planTier,
        seededForTesting: true,
        updatedAt: now,
      },
      { merge: true }
    );

    const transactionRef = db.collection("creatorCreditTransactions").doc();
    batch.create(transactionRef, {
      userId: uid,
      amount: credits,
      type: "test_seed_grant",
      metadata: {
        source: "seedCreatorCreditBalances",
        planTier,
      },
      createdAt: now,
    });
  }

  await batch.commit();
  console.log(`Seeded creator credit balances for ${uids.length} user(s): ${uids.join(", ")}`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
