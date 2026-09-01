#!/usr/bin/env node
"use strict";

/**
 * Narrow reset for the five fixed beta-browser-v1 Firebase identities.
 *
 * Dry run (default):
 *   node scripts/resetSyntheticBetaCohort.js
 *
 * Destructive execution requires all three flags in the same invocation:
 *   node scripts/resetSyntheticBetaCohort.js --execute \
 *     --confirm-project=poplur2025 --confirm-synthetic-auth-count=5
 *
 * This tool never deletes Storage, feedback, human telemetry, ordinary users,
 * ordinary posts, configuration, credits, or purchases. It aborts rather than
 * broadening scope when any synthetic identity or document is ambiguous.
 */

const admin = require("firebase-admin");
const {
  ACTOR_IDS,
  COLLECTIONS,
  CONTROL_PATHS,
  PROJECT_ID,
  assertAfterInvariants,
  buildDeletionPlan,
  parseArguments,
  preservationFingerprint,
} = require("./syntheticBetaResetPolicy");

const STORAGE_BUCKET = "poplur2025.firebasestorage.app";
const RELEVANT_COLLECTIONS = Object.freeze(Object.values(COLLECTIONS));
const PRESERVED_COLLECTIONS = Object.freeze([
  "users",
  "profiles",
  "posts",
  "testActivity",
  "testActivityPosts",
  "testBetaPosts",
  "testFeedback",
  "testSimulationEvents",
  "poplurConfig",
  "creatorCreditBalances",
  "creatorCreditTransactions",
  "verifiedStorePurchases",
]);

function initialize() {
  if (!admin.apps.length) {
    admin.initializeApp({ projectId: PROJECT_ID, storageBucket: STORAGE_BUCKET });
  }
  return {
    auth: admin.auth(),
    firestore: admin.firestore(),
    storage: admin.storage().bucket(),
  };
}

async function listAllAuthUsers(auth) {
  const users = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1_000, pageToken);
    users.push(...page.users.map(user => ({
      uid: user.uid,
      email: user.email || "",
      customClaims: { ...(user.customClaims || {}) },
    })));
    pageToken = page.pageToken;
  } while (pageToken);
  return users;
}

function serializableDocument(snapshot, subcollectionCount = 0) {
  return {
    id: snapshot.id,
    path: snapshot.ref.path,
    exists: snapshot.exists,
    data: snapshot.data(),
    updateTime: snapshot.updateTime,
    ref: snapshot.ref,
    subcollectionCount,
  };
}

async function readDocumentWithSubcollections(reference) {
  const snapshot = await reference.get();
  if (!snapshot.exists) {
    return { id: reference.id, path: reference.path, exists: false, data: undefined, ref: reference, subcollectionCount: 0 };
  }
  const nested = await reference.listCollections();
  return serializableDocument(snapshot, nested.length);
}

async function readCollection(firestore, collectionName) {
  const snapshot = await firestore.collection(collectionName).get();
  return Promise.all(snapshot.docs.map(async document => {
    const nested = await document.ref.listCollections();
    return serializableDocument(document, nested.length);
  }));
}

async function collectionCounts(firestore) {
  const collections = await firestore.listCollections();
  const entries = await Promise.all(collections.map(async collection => {
    const aggregate = await collection.count().get();
    return [collection.id, aggregate.data().count];
  }));
  return Object.fromEntries(entries);
}

async function storageInventory(bucket) {
  const [files] = await bucket.getFiles({ autoPaginate: true });
  return files.map(file => `${file.name}\u0000${file.metadata.generation || ""}`).sort();
}

async function readSnapshot(services) {
  const { auth, firestore, storage } = services;
  const [authUsers, counts, storageObjects, runner, runtime, simulation, ...collections] = await Promise.all([
    listAllAuthUsers(auth),
    collectionCounts(firestore),
    storageInventory(storage),
    readDocumentWithSubcollections(firestore.doc(CONTROL_PATHS.runner)),
    readDocumentWithSubcollections(firestore.doc(CONTROL_PATHS.runtime)),
    readDocumentWithSubcollections(firestore.doc(CONTROL_PATHS.simulation)),
    ...RELEVANT_COLLECTIONS.map(collection => readCollection(firestore, collection)),
  ]);
  return {
    authUsers,
    collectionCounts: counts,
    storageObjects,
    controls: { runner, runtime, simulation },
    documents: Object.fromEntries(RELEVANT_COLLECTIONS.map((collection, index) => [collection, collections[index]])),
    existingPaths: new Set([
      ...(runner.exists ? [runner.path] : []),
      ...(runtime.exists ? [runtime.path] : []),
      ...(simulation.exists ? [simulation.path] : []),
      ...collections.flat().map(document => document.path),
    ]),
  };
}

function publicReport(snapshot, plan, mode) {
  const preservation = preservationFingerprint(snapshot, plan);
  const preservedFirestoreCounts = Object.fromEntries(PRESERVED_COLLECTIONS.map(collection => [
    collection,
    Math.max(0, (snapshot.collectionCounts[collection] || 0) - (plan.firestoreByCollection[collection] || 0)),
  ]));
  return {
    mode,
    project: PROJECT_ID,
    runnerVerifiedPaused: true,
    before: {
      authUsers: snapshot.authUsers.length,
      syntheticAuthUsers: plan.authTargets.length,
      nonSyntheticAuthUsers: plan.nonTargetAuthUsers.length,
      storageObjects: snapshot.storageObjects.length,
    },
    proposedDeletion: {
      authUsers: plan.authTargets.length,
      firestoreDocuments: plan.firestoreTargets.length,
      byCollection: plan.firestoreByCollection,
    },
    preserved: {
      nonSyntheticAuthUsers: preservation.nonTargetAuthCount,
      nonSyntheticAuthDigest: preservation.nonTargetAuthDigest,
      scannedFirestoreDocuments: preservation.preservedScannedPathCount,
      scannedFirestoreDigest: preservation.preservedScannedPathDigest,
      firestoreDocumentsByCollection: preservedFirestoreCounts,
      storageObjects: preservation.storageObjectCount,
      storageDigest: preservation.storageObjectDigest,
      storageWrites: 0,
    },
  };
}

async function deleteFirestoreTargets(firestore, targets) {
  // A second complete snapshot is taken immediately before this function. Each
  // delete also carries its original update-time precondition, so a concurrent
  // mutation fails instead of expanding or silently changing the reset scope.
  for (let offset = 0; offset < targets.length; offset += 400) {
    const batch = firestore.batch();
    for (const target of targets.slice(offset, offset + 400)) {
      if (!target.updateTime) throw new Error(`Target ${target.path} has no update-time precondition.`);
      batch.delete(target.ref, { lastUpdateTime: target.updateTime });
    }
    await batch.commit();
  }
}

async function executeReset(services, initialSnapshot, initialPlan) {
  const freshSnapshot = await readSnapshot(services);
  const freshPlan = buildDeletionPlan(freshSnapshot);
  const initialPaths = initialPlan.firestoreTargets.map(target => target.path).sort();
  const freshPaths = freshPlan.firestoreTargets.map(target => target.path).sort();
  if (JSON.stringify(initialPaths) !== JSON.stringify(freshPaths)
    || freshPlan.authTargets.length !== initialPlan.authTargets.length) {
    throw new Error("Synthetic reset inventory changed between preflight reads; nothing was deleted.");
  }

  await deleteFirestoreTargets(services.firestore, freshPlan.firestoreTargets);

  const authUsers = await listAllAuthUsers(services.auth);
  buildDeletionPlan({ ...freshSnapshot, authUsers });
  const result = await services.auth.deleteUsers(ACTOR_IDS);
  if (result.failureCount !== 0 || result.successCount !== ACTOR_IDS.length) {
    throw new Error(`Firebase Auth deleted ${result.successCount}/${ACTOR_IDS.length} fixed synthetic accounts.`);
  }

  const after = await readSnapshot(services);
  assertAfterInvariants(freshSnapshot, after, freshPlan);
  return publicReport(after, {
    ...freshPlan,
    authTargets: [],
    nonTargetAuthUsers: after.authUsers,
    firestoreTargets: [],
    firestoreByCollection: {},
  }, "executed");
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const services = initialize();
  const snapshot = await readSnapshot(services);
  const plan = buildDeletionPlan(snapshot);
  console.log(JSON.stringify(publicReport(snapshot, plan, options.execute ? "execute-preflight" : "dry-run"), null, 2));
  if (!options.execute) {
    console.log("Dry run only. No Firebase Auth, Firestore, or Storage data was changed.");
    return;
  }
  const report = await executeReset(services, snapshot, plan);
  console.log(JSON.stringify(report, null, 2));
}

if (require.main === module) {
  main().catch(error => {
    console.error(error instanceof Error ? error.message : "Synthetic reset failed safely.");
    process.exitCode = 1;
  });
}

module.exports = { executeReset, listAllAuthUsers, publicReport, readSnapshot };
