#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const {
  ACTORS,
  COLLECTIONS,
  COHORT_ID,
  CONTROL_PATHS,
  PROJECT_ID,
  SOURCE,
  assertAfterInvariants,
  buildDeletionPlan,
  parseArguments,
} = require("./syntheticBetaResetPolicy");

function document(path, data, extra = {}) {
  return { id: path.split("/").at(-1), path, data, exists: true, subcollectionCount: 0, ...extra };
}

function actorDocument(actor) {
  return document(`${COLLECTIONS.actors}/${actor.actorId}`, {
    actorId: actor.actorId,
    uid: actor.actorId,
    active: true,
    source: SOURCE,
    cohortId: COHORT_ID,
  });
}

function authUser(actor) {
  return {
    uid: actor.actorId,
    email: actor.email,
    customClaims: { syntheticBeta: true, syntheticActorId: actor.actorId },
  };
}

function baseSnapshot() {
  const runner = document(CONTROL_PATHS.runner, {
    enabled: false,
    generation: 2,
    cohortId: COHORT_ID,
    actors: ACTORS.map(actor => ({ actorId: actor.actorId, active: true })),
  });
  const simulation = document(CONTROL_PATHS.simulation, { enabled: false });
  const humanAuth = { uid: "human-1", email: "human@example.com", customClaims: {} };
  const humanPost = document(`${COLLECTIONS.posts}/human-post`, { userID: humanAuth.uid });
  const humanUser = document(`${COLLECTIONS.users}/${humanAuth.uid}`, { username: "human" });
  return {
    authUsers: [...ACTORS.map(authUser), humanAuth],
    controls: {
      runner,
      runtime: { id: "syntheticBrowserRuntime", path: CONTROL_PATHS.runtime, exists: false, subcollectionCount: 0 },
      simulation,
    },
    documents: {
      [COLLECTIONS.actors]: ACTORS.map(actorDocument),
      [COLLECTIONS.events]: [],
      [COLLECTIONS.sessions]: [],
      [COLLECTIONS.betaPosts]: [],
      [COLLECTIONS.posts]: [humanPost],
      [COLLECTIONS.users]: [humanUser],
      [COLLECTIONS.profiles]: [],
    },
    collectionCounts: {
      testControl: 2,
      [COLLECTIONS.actors]: 5,
      [COLLECTIONS.posts]: 1,
      [COLLECTIONS.users]: 1,
    },
    storageObjects: ["profiles/human.jpg\u00001"],
    existingPaths: new Set([runner.path, simulation.path, humanPost.path, humanUser.path,
      ...ACTORS.map(actor => `${COLLECTIONS.actors}/${actor.actorId}`)]),
  };
}

function expectFailure(callback, pattern) {
  assert.throws(callback, pattern);
}

assert.deepEqual(parseArguments([]), { execute: false });
expectFailure(() => parseArguments(["--execute"]), /confirm-project/);
expectFailure(() => parseArguments(["--execute", `--confirm-project=${PROJECT_ID}`]), /confirm-synthetic-auth-count/);
assert.deepEqual(parseArguments([
  "--execute",
  `--confirm-project=${PROJECT_ID}`,
  "--confirm-synthetic-auth-count=5",
]), { execute: true });
expectFailure(() => parseArguments(["--force"]), /Unsupported/);

const safe = baseSnapshot();
const safePlan = buildDeletionPlan(safe);
assert.equal(safePlan.authTargets.length, 5);
assert.equal(safePlan.nonTargetAuthUsers.length, 1);
assert.equal(safePlan.firestoreTargets.length, 6);
assert.deepEqual(safePlan.firestoreByCollection, { testControl: 1, testSyntheticRunnerActors: 5 });
assert.ok(!safePlan.firestoreTargets.some(target => target.path.includes("human")));

const ordinarySourcePost = baseSnapshot();
ordinarySourcePost.documents[COLLECTIONS.posts][0].data.source = "camera-upload";
const ordinarySourcePlan = buildDeletionPlan(ordinarySourcePost);
assert.ok(!ordinarySourcePlan.firestoreTargets.some(target => target.path.endsWith("/human-post")));

const wrongClaim = baseSnapshot();
wrongClaim.authUsers[0].customClaims.syntheticActorId = "sim-news-005";
expectFailure(() => buildDeletionPlan(wrongClaim), /locked UID\/email\/claim/);

const unknownSynthetic = baseSnapshot();
unknownSynthetic.authUsers.push({ uid: "sim-other-999", email: "other@poplur.test", customClaims: { syntheticBeta: true } });
expectFailure(() => buildDeletionPlan(unknownSynthetic), /outside the fixed five-person allowlist/);

const enabledRunner = baseSnapshot();
enabledRunner.controls.runner.data.enabled = true;
expectFailure(() => buildDeletionPlan(enabledRunner), /runner control/);

const activeRuntime = baseSnapshot();
activeRuntime.controls.runtime = document(CONTROL_PATHS.runtime, {
  source: SOURCE,
  cohortId: COHORT_ID,
  generation: 2,
  sessions: [{ actorId: ACTORS[0].actorId, status: "live" }],
});
expectFailure(() => buildDeletionPlan(activeRuntime), /live session/);

const taggedRuntime = baseSnapshot();
taggedRuntime.controls.runtime = document(CONTROL_PATHS.runtime, {
  source: SOURCE,
  cohortId: COHORT_ID,
  generation: 2,
  sessions: [],
});
const eventId = "event-1";
taggedRuntime.documents[COLLECTIONS.events].push(document(`${COLLECTIONS.events}/${eventId}`, {
  eventId,
  actorId: ACTORS[0].actorId,
  source: SOURCE,
  cohortId: COHORT_ID,
}));
taggedRuntime.documents[COLLECTIONS.sessions].push(document(`${COLLECTIONS.sessions}/${ACTORS[0].actorId}`, {
  actorId: ACTORS[0].actorId,
  status: "paused",
  source: SOURCE,
  cohortId: COHORT_ID,
}));
const taggedRuntimePlan = buildDeletionPlan(taggedRuntime);
assert.ok(taggedRuntimePlan.firestoreTargets.some(target => target.path === CONTROL_PATHS.runtime));
assert.ok(taggedRuntimePlan.firestoreTargets.some(target => target.path === `${COLLECTIONS.events}/${eventId}`));
assert.ok(taggedRuntimePlan.firestoreTargets.some(target => target.path === `${COLLECTIONS.sessions}/${ACTORS[0].actorId}`));

const partialPost = baseSnapshot();
partialPost.documents[COLLECTIONS.posts].push(document(`${COLLECTIONS.posts}/partial`, {
  source: SOURCE,
  userID: ACTORS[0].actorId,
}));
expectFailure(() => buildDeletionPlan(partialPost), /incomplete or inconsistent/);

const taggedPost = baseSnapshot();
const actorId = ACTORS[0].actorId;
const generation = 2;
const postId = `synthetic-${actorId}-${generation}`;
taggedPost.documents[COLLECTIONS.posts].push(document(`${COLLECTIONS.posts}/${postId}`, {
  source: SOURCE,
  cohortId: COHORT_ID,
  syntheticBeta: true,
  testOnly: true,
  userID: actorId,
  userId: actorId,
  syntheticGeneration: generation,
  syntheticSessionId: `${actorId}_${generation}_session`,
}));
taggedPost.documents[COLLECTIONS.betaPosts].push(document(`${COLLECTIONS.betaPosts}/${postId}`, {
  source: SOURCE,
  cohortId: COHORT_ID,
  syntheticBeta: true,
  testOnly: true,
  uid: actorId,
  postKey: postId,
  syntheticGeneration: generation,
  syntheticSessionId: `${actorId}_${generation}_session`,
}));
const taggedPlan = buildDeletionPlan(taggedPost);
assert.ok(taggedPlan.firestoreTargets.some(target => target.path === `${COLLECTIONS.posts}/${postId}`));
assert.ok(taggedPlan.firestoreTargets.some(target => target.path === `${COLLECTIONS.betaPosts}/${postId}`));

const syntheticUser = baseSnapshot();
syntheticUser.documents[COLLECTIONS.users].push(document(`${COLLECTIONS.users}/${ACTORS[0].actorId}`, {
  source: SOURCE,
  cohortId: COHORT_ID,
}));
expectFailure(() => buildDeletionPlan(syntheticUser), /outside this reset's authorized scope/);

const nestedTarget = baseSnapshot();
nestedTarget.documents[COLLECTIONS.actors][0].subcollectionCount = 1;
expectFailure(() => buildDeletionPlan(nestedTarget), /nested collection/);

const after = {
  authUsers: safe.authUsers.filter(user => !user.uid.startsWith("sim-")),
  collectionCounts: {
    testControl: 1,
    [COLLECTIONS.posts]: 1,
    [COLLECTIONS.users]: 1,
  },
  storageObjects: [...safe.storageObjects],
  existingPaths: new Set([CONTROL_PATHS.simulation, `${COLLECTIONS.posts}/human-post`, `${COLLECTIONS.users}/human-1`]),
};
assert.doesNotThrow(() => assertAfterInvariants(safe, after, safePlan));

const storageChanged = { ...after, storageObjects: [] };
expectFailure(() => assertAfterInvariants(safe, storageChanged, safePlan), /Storage inventory changed/);

const humanDeleted = {
  ...after,
  collectionCounts: { ...after.collectionCounts, [COLLECTIONS.users]: 0 },
};
expectFailure(() => assertAfterInvariants(safe, humanDeleted, safePlan), /count invariant failed/);

console.log("Synthetic beta reset policy safety suite passed.");
