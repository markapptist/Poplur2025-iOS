"use strict";

const { createHash } = require("node:crypto");

const PROJECT_ID = "poplur2025";
const COHORT_ID = "beta-browser-v1";
const SOURCE = "synthetic-browser";
const EXPECTED_AUTH_COUNT = 8;

const ACTORS = Object.freeze([
  Object.freeze({ actorId: "sim-food-001", email: "beta-sim-food-001@poplur.test", kind: "person" }),
  Object.freeze({ actorId: "sim-sports-002", email: "beta-sim-sports-002@poplur.test", kind: "person" }),
  Object.freeze({ actorId: "sim-music-003", email: "beta-sim-music-003@poplur.test", kind: "person" }),
  Object.freeze({ actorId: "sim-tech-004", email: "beta-sim-tech-004@poplur.test", kind: "person" }),
  Object.freeze({ actorId: "sim-news-005", email: "beta-sim-news-005@poplur.test", kind: "person" }),
  // Business testers own a users/{uid} profile and a public businesses/{uid}
  // listing, both provisioned; the reset removes exactly those two documents.
  Object.freeze({ actorId: "sim-biz-food-006", email: "beta-sim-biz-food-006@poplur.test", kind: "business" }),
  Object.freeze({ actorId: "sim-biz-shop-007", email: "beta-sim-biz-shop-007@poplur.test", kind: "business" }),
  Object.freeze({ actorId: "sim-biz-fashion-008", email: "beta-sim-biz-fashion-008@poplur.test", kind: "business" }),
]);

const ACTOR_BY_ID = new Map(ACTORS.map(actor => [actor.actorId, actor]));
const ACTOR_IDS = Object.freeze(ACTORS.map(actor => actor.actorId));

const COLLECTIONS = Object.freeze({
  actors: "testSyntheticRunnerActors",
  events: "testSyntheticBrowserEvents",
  sessions: "testSyntheticBrowserSessions",
  betaPosts: "testBetaPosts",
  posts: "posts",
  users: "users",
  profiles: "profiles",
  businesses: "businesses",
});

const CONTROL_PATHS = Object.freeze({
  runner: "testControl/syntheticBrowserRunner",
  runtime: "testControl/syntheticBrowserRuntime",
  simulation: "testControl/simulation",
});

function fail(message) {
  throw new Error(message);
}

function parseArguments(argv) {
  const supported = new Set([
    "--execute",
    `--confirm-project=${PROJECT_ID}`,
    `--confirm-synthetic-auth-count=${EXPECTED_AUTH_COUNT}`,
  ]);
  const unknown = argv.filter(argument => !supported.has(argument));
  if (unknown.length) fail(`Unsupported reset argument: ${unknown[0]}`);

  const execute = argv.includes("--execute");
  if (execute && !argv.includes(`--confirm-project=${PROJECT_ID}`)) {
    fail(`Execution requires --confirm-project=${PROJECT_ID}.`);
  }
  if (execute && !argv.includes(`--confirm-synthetic-auth-count=${EXPECTED_AUTH_COUNT}`)) {
    fail(`Execution requires --confirm-synthetic-auth-count=${EXPECTED_AUTH_COUNT}.`);
  }
  return { execute };
}

function normalizeEmail(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function syntheticIdentitySignal(user) {
  const claims = user.customClaims || {};
  return claims.syntheticBeta !== undefined
    || claims.syntheticActorId !== undefined
    || normalizeEmail(user.email).endsWith("@poplur.test")
    || ACTOR_BY_ID.has(user.uid);
}

function validateAuthUsers(users) {
  if (!Array.isArray(users)) fail("Auth inventory is unavailable.");
  const byUid = new Map();
  for (const user of users) {
    if (!user || typeof user.uid !== "string" || !user.uid) fail("Auth inventory contains an invalid UID.");
    if (byUid.has(user.uid)) fail(`Auth inventory contains duplicate UID ${user.uid}.`);
    byUid.set(user.uid, user);
  }

  const targets = ACTORS.map(actor => {
    const user = byUid.get(actor.actorId);
    if (!user) fail(`Required synthetic Auth account ${actor.actorId} is missing.`);
    const claims = user.customClaims || {};
    if (normalizeEmail(user.email) !== actor.email
      || !normalizeEmail(user.email).endsWith("@poplur.test")
      || claims.syntheticBeta !== true
      || claims.syntheticActorId !== actor.actorId) {
      fail(`Synthetic Auth identity ${actor.actorId} does not match its locked UID/email/claim contract.`);
    }
    return user;
  });

  const nonTargets = users.filter(user => !ACTOR_BY_ID.has(user.uid));
  const ambiguous = nonTargets.find(syntheticIdentitySignal);
  if (ambiguous) {
    fail("An Auth account outside the fixed eight-actor allowlist carries a synthetic identity marker.");
  }
  if (targets.length !== EXPECTED_AUTH_COUNT) fail(`Synthetic Auth target count is not exactly ${EXPECTED_AUTH_COUNT}.`);
  return { targets, nonTargets };
}

function exactRunnerActors(value) {
  if (!Array.isArray(value) || value.length !== EXPECTED_AUTH_COUNT) return false;
  const seen = new Set();
  for (const entry of value) {
    if (!entry || typeof entry !== "object"
      || !ACTOR_BY_ID.has(entry.actorId)
      || entry.active !== true
      || seen.has(entry.actorId)) return false;
    seen.add(entry.actorId);
  }
  return ACTOR_IDS.every(actorId => seen.has(actorId));
}

function validateControls(controls) {
  const runner = controls?.runner;
  if (!runner?.exists || runner.data?.cohortId !== COHORT_ID
    || runner.data?.enabled !== false
    || !Number.isSafeInteger(runner.data?.generation)
    || runner.data.generation < 0
    || !exactRunnerActors(runner.data?.actors)) {
    fail("Synthetic browser runner control is missing, enabled, or outside the locked paused cohort contract.");
  }

  const simulation = controls?.simulation;
  if (simulation?.exists && simulation.data?.enabled !== false) {
    fail("Synthetic simulation must be explicitly disabled before reset.");
  }

  const runtime = controls?.runtime;
  if (runtime?.exists) {
    if (runtime.data?.source !== SOURCE
      || runtime.data?.cohortId !== COHORT_ID
      || runtime.data?.generation !== runner.data.generation
      || !Array.isArray(runtime.data?.sessions)) {
      fail("Synthetic browser runtime is not an exact tagged match for the paused runner generation.");
    }
    if (runtime.data.sessions.some(session => session?.status === "live")) {
      fail("Synthetic browser runtime still contains a live session.");
    }
  }
}

function markerCandidate(document, identityFields = []) {
  const data = document.data || {};
  return data.source === SOURCE
    || data.cohortId === COHORT_ID
    || data.syntheticBeta !== undefined
    || data.testOnly !== undefined
    || identityFields.some(field => ACTOR_BY_ID.has(data[field]))
    || ACTOR_BY_ID.has(document.id)
    || document.id.startsWith("synthetic-sim-");
}

function exactCommonTags(data) {
  return data.source === SOURCE && data.cohortId === COHORT_ID;
}

function classifyActorDocuments(documents) {
  const targets = [];
  for (const document of documents) {
    if (!markerCandidate(document, ["actorId", "uid"])) continue;
    const data = document.data || {};
    if (!ACTOR_BY_ID.has(document.id)
      || data.actorId !== document.id
      || data.uid !== document.id
      || data.active !== true
      || !exactCommonTags(data)) {
      fail(`Runner allowlist document ${document.path} is not an exact fixed-cohort actor record.`);
    }
    targets.push(document);
  }
  if (targets.length !== EXPECTED_AUTH_COUNT
    || !ACTOR_IDS.every(actorId => targets.some(document => document.id === actorId))) {
    fail(`Runner allowlist does not contain exactly the ${EXPECTED_AUTH_COUNT} locked actor documents.`);
  }
  return targets;
}

function classifyEventDocuments(documents) {
  return documents.filter(document => {
    if (!markerCandidate(document, ["actorId"])) return false;
    const data = document.data || {};
    if (!exactCommonTags(data)
      || !ACTOR_BY_ID.has(data.actorId)
      || data.eventId !== document.id) {
      fail(`Runner event ${document.path} is partially tagged or outside the fixed actor cohort.`);
    }
    return true;
  });
}

function classifySessionDocuments(documents) {
  return documents.filter(document => {
    if (!markerCandidate(document, ["actorId"])) return false;
    const data = document.data || {};
    if (!exactCommonTags(data)
      || !ACTOR_BY_ID.has(data.actorId)
      || data.actorId !== document.id
      || data.status === "live") {
      fail(`Runner session ${document.path} is active, partially tagged, or outside the fixed actor cohort.`);
    }
    return true;
  });
}

function expectedSyntheticPostId(data) {
  const actorId = data.userID || data.uid;
  if (!ACTOR_BY_ID.has(actorId)
    || !Number.isSafeInteger(data.syntheticGeneration)
    || data.syntheticGeneration <= 0) return "";
  return `synthetic-${actorId}-${data.syntheticGeneration}`;
}

function exactPostTags(data) {
  return exactCommonTags(data) && data.syntheticBeta === true && data.testOnly === true;
}

function classifyMapPostDocuments(documents) {
  return documents.filter(document => {
    if (!markerCandidate(document, ["userID", "userId"])) return false;
    const data = document.data || {};
    const expectedId = expectedSyntheticPostId(data);
    if (!exactPostTags(data)
      || !expectedId
      || document.id !== expectedId
      || data.userID !== data.userId
      || typeof data.syntheticSessionId !== "string"
      || !data.syntheticSessionId.startsWith(`${data.userID}_${data.syntheticGeneration}_`)) {
      fail(`Map post ${document.path} has an incomplete or inconsistent synthetic cohort identity.`);
    }
    return true;
  });
}

function classifyBetaPostDocuments(documents) {
  return documents.filter(document => {
    if (!markerCandidate(document, ["uid"])) return false;
    const data = document.data || {};
    const expectedId = expectedSyntheticPostId(data);
    if (!exactPostTags(data)
      || !expectedId
      || document.id !== expectedId
      || data.postKey !== expectedId
      || typeof data.syntheticSessionId !== "string"
      || !data.syntheticSessionId.startsWith(`${data.uid}_${data.syntheticGeneration}_`)) {
      fail(`Beta post ${document.path} has an incomplete or inconsistent synthetic cohort identity.`);
    }
    return true;
  });
}

/**
 * A provisioned BUSINESS tester's own profile: users/{actorId} and
 * businesses/{actorId}, each carrying the exact cohort tags provisioning
 * stamps. Those two documents are in scope and are deleted with the account.
 * Any other synthetic-looking user/profile record still aborts the reset —
 * a person tester owns no profile document, and nothing else may.
 */
function exactCohortProfile(document) {
  const data = document.data || {};
  const actor = ACTOR_BY_ID.get(document.id);
  return Boolean(actor)
    && actor.kind === "business"
    && data.syntheticActorId === document.id
    && data.syntheticBeta === true
    && exactCommonTags(data)
    && data.accountType === "business";
}

function classifyProfileDocuments(collectionName, documents) {
  const targets = [];
  for (const document of documents) {
    if (exactCohortProfile(document)) { targets.push(document); continue; }
    if (markerCandidate(document, ["uid", "userID", "userId", "ownerUserId", "ownerUserID"])) {
      fail(`${collectionName}/${document.id} appears synthetic but user/profile records are outside this reset's authorized scope.`);
    }
  }
  return targets;
}

function assertNoOutOfScopeSyntheticProfiles(collectionName, documents) {
  const conflicting = documents.find(document => markerCandidate(document, ["uid", "userID", "userId"]));
  if (conflicting) {
    fail(`${collectionName}/${conflicting.id} appears synthetic but user/profile records are outside this reset's authorized scope.`);
  }
}

function buildDeletionPlan(snapshot) {
  const auth = validateAuthUsers(snapshot.authUsers);
  validateControls(snapshot.controls);
  const documents = snapshot.documents || {};
  assertNoOutOfScopeSyntheticProfiles(COLLECTIONS.profiles, documents[COLLECTIONS.profiles] || []);

  const firestoreTargets = [
    snapshot.controls.runner,
    ...(snapshot.controls.runtime?.exists ? [snapshot.controls.runtime] : []),
    ...classifyActorDocuments(documents[COLLECTIONS.actors] || []),
    ...classifyProfileDocuments(COLLECTIONS.users, documents[COLLECTIONS.users] || []),
    ...classifyProfileDocuments(COLLECTIONS.businesses, documents[COLLECTIONS.businesses] || []),
    ...classifyEventDocuments(documents[COLLECTIONS.events] || []),
    ...classifySessionDocuments(documents[COLLECTIONS.sessions] || []),
    ...classifyMapPostDocuments(documents[COLLECTIONS.posts] || []),
    ...classifyBetaPostDocuments(documents[COLLECTIONS.betaPosts] || []),
  ];
  const duplicatePath = firestoreTargets.find((document, index) =>
    firestoreTargets.findIndex(candidate => candidate.path === document.path) !== index);
  if (duplicatePath) fail(`Reset plan contains duplicate path ${duplicatePath.path}.`);
  const withSubcollections = firestoreTargets.find(document => (document.subcollectionCount || 0) !== 0);
  if (withSubcollections) fail(`Target ${withSubcollections.path} has a nested collection and cannot be reset safely.`);

  const firestoreByCollection = {};
  for (const document of firestoreTargets) {
    const collection = document.path.split("/")[0];
    firestoreByCollection[collection] = (firestoreByCollection[collection] || 0) + 1;
  }
  return {
    authTargets: auth.targets,
    nonTargetAuthUsers: auth.nonTargets,
    firestoreTargets,
    firestoreByCollection,
  };
}

function digestStrings(values) {
  return createHash("sha256").update([...values].sort().join("\n")).digest("hex");
}

function preservationFingerprint(snapshot, plan) {
  const targetPaths = new Set(plan.firestoreTargets.map(document => document.path));
  const preservedPaths = [];
  for (const documents of Object.values(snapshot.documents || {})) {
    for (const document of documents) {
      if (!targetPaths.has(document.path)) preservedPaths.push(document.path);
    }
  }
  for (const control of Object.values(snapshot.controls || {})) {
    if (control?.exists && !targetPaths.has(control.path)) preservedPaths.push(control.path);
  }
  return {
    nonTargetAuthCount: plan.nonTargetAuthUsers.length,
    nonTargetAuthDigest: digestStrings(plan.nonTargetAuthUsers.map(user => user.uid)),
    preservedScannedPathCount: preservedPaths.length,
    preservedScannedPathDigest: digestStrings(preservedPaths),
    storageObjectCount: snapshot.storageObjects.length,
    storageObjectDigest: digestStrings(snapshot.storageObjects),
  };
}

function assertAfterInvariants(before, after, plan) {
  const afterAuth = validateAuthAfterReset(after.authUsers);
  if (afterAuth.nonTargets.length !== plan.nonTargetAuthUsers.length
    || digestStrings(afterAuth.nonTargets.map(user => user.uid))
      !== digestStrings(plan.nonTargetAuthUsers.map(user => user.uid))) {
    fail("Non-synthetic Auth inventory changed during reset.");
  }

  const allCollections = new Set([
    ...Object.keys(before.collectionCounts || {}),
    ...Object.keys(after.collectionCounts || {}),
    ...Object.keys(plan.firestoreByCollection),
  ]);
  for (const collection of allCollections) {
    const expected = (before.collectionCounts?.[collection] || 0)
      - (plan.firestoreByCollection[collection] || 0);
    if ((after.collectionCounts?.[collection] || 0) !== expected) {
      fail(`After-reset count invariant failed for ${collection}: expected ${expected}.`);
    }
  }

  const remainingTarget = plan.firestoreTargets.find(target => after.existingPaths.has(target.path));
  if (remainingTarget) fail(`After-reset target still exists: ${remainingTarget.path}.`);
  if (before.storageObjects.length !== after.storageObjects.length
    || digestStrings(before.storageObjects) !== digestStrings(after.storageObjects)) {
    fail("Storage inventory changed during synthetic reset.");
  }
}

function validateAuthAfterReset(users) {
  const targets = users.filter(user => ACTOR_BY_ID.has(user.uid));
  if (targets.length) fail("One or more fixed synthetic Auth accounts remain after reset.");
  const ambiguous = users.find(syntheticIdentitySignal);
  if (ambiguous) fail("A synthetic identity marker remains outside the deleted cohort.");
  return { nonTargets: users };
}

module.exports = {
  ACTORS,
  ACTOR_IDS,
  COLLECTIONS,
  COHORT_ID,
  CONTROL_PATHS,
  EXPECTED_AUTH_COUNT,
  PROJECT_ID,
  SOURCE,
  assertAfterInvariants,
  buildDeletionPlan,
  digestStrings,
  parseArguments,
  preservationFingerprint,
  validateAuthAfterReset,
  validateAuthUsers,
  validateControls,
};
