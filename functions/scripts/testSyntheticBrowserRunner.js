const assert = require("node:assert/strict");
const {
  SYNTHETIC_BETA_COHORT_ID,
  SYNTHETIC_BETA_PROFILES,
  SYNTHETIC_RUNNER_RECENT_EVENT_LIMIT,
  advanceSyntheticBrowserRuntime,
} = require("../lib/syntheticBetaCohort.js");
const {
  parseSyntheticRunnerRequest,
  syntheticBetaPostData,
  syntheticMapPostData,
  syntheticMapPostId,
  syntheticRunnerEventId,
  syntheticRunnerSessionId,
  validateSyntheticRunnerAccess,
} = require("../lib/syntheticBrowserRunner.js");

const now = 1_800_000_000_000;
const actorId = SYNTHETIC_BETA_PROFILES[0].id;
const generation = 7;
const sessionId = syntheticRunnerSessionId(actorId, generation, now);
assert.equal(sessionId, syntheticRunnerSessionId(actorId, generation, now));
assert.notEqual(sessionId, syntheticRunnerSessionId(actorId, generation + 1, now));

const identity = { uid: "runnerUid123", actorId };
const config = { enabled: true, generation, cohortId: SYNTHETIC_BETA_COHORT_ID };
const allowlist = {
  active: true,
  actorId,
  uid: identity.uid,
  cohortId: SYNTHETIC_BETA_COHORT_ID,
  source: "synthetic-browser",
};
assert.deepEqual(validateSyntheticRunnerAccess(identity, actorId, config, allowlist, generation), {
  enabled: true,
  generation,
});
assert.throws(() => validateSyntheticRunnerAccess(identity, actorId, config, allowlist, generation + 1));
assert.throws(() => validateSyntheticRunnerAccess(identity, actorId, config, { ...allowlist, active: false }, generation));
assert.throws(() => validateSyntheticRunnerAccess(identity, actorId, config, { ...allowlist, uid: "differentUid" }, generation));
assert.throws(() => validateSyntheticRunnerAccess({ ...identity, actorId: SYNTHETIC_BETA_PROFILES[1].id }, actorId, config, allowlist, generation));
assert.throws(() => validateSyntheticRunnerAccess(identity, actorId, { ...config, cohortId: "wrong" }, allowlist, generation));
assert.deepEqual(validateSyntheticRunnerAccess(identity, actorId, { ...config, enabled: false }, allowlist), {
  enabled: false,
  generation,
});
assert.deepEqual(validateSyntheticRunnerAccess(identity, actorId, { ...config, generation: 0 }, allowlist), {
  enabled: false,
  generation: 0,
});

assert.deepEqual(parseSyntheticRunnerRequest({ type: "status", actorId }, now), { type: "status", actorId });
assert.deepEqual(parseSyntheticRunnerRequest({
  type: "start",
  actorId,
  occurredAtMs: now,
}, now), {
  type: "start",
  actorId,
  occurredAtMs: now,
});

const acceptedEvent = parseSyntheticRunnerRequest({
  type: "event",
  actorId,
  sessionId,
  sequence: 1,
  occurredAtMs: now + 1_000,
  screen: "map",
  action: "open-map",
  status: "foreground",
  localFrameSequence: 12,
  frameSuppressed: false,
  dwellMs: 1_000,
  stepIndex: 1,
  journeyLength: 4,
  eventType: "navigation",
  metrics: { loadMs: 420, frameRate: 30, longTaskCount: 0 },
}, now);
assert.equal(acceptedEvent.type, "event");
assert.equal(acceptedEvent.frameSuppressed, false, "local-only frame availability metadata was lost");

const rejectedBodies = [
  { ...acceptedEvent, coordinates: [43.6, -79.3] },
  { ...acceptedEvent, url: "https://example.com/private" },
  { ...acceptedEvent, dom: "<main>private</main>" },
  { ...acceptedEvent, text: "private post" },
  { ...acceptedEvent, media: "data:image/png;base64,abc" },
  { ...acceptedEvent, frameSuppressed: "false" },
  { ...acceptedEvent, screen: "camera" },
  { ...acceptedEvent, action: "publish" },
  { ...acceptedEvent, eventType: "engagement" },
  { ...acceptedEvent, action: "typed arbitrary private text" },
  { ...acceptedEvent, metrics: { loadMs: 1, pixelCount: 10 } },
  { ...acceptedEvent, metrics: { loadMs: "fast" } },
  { ...acceptedEvent, occurredAtMs: now - (11 * 60 * 1_000) },
  { ...acceptedEvent, generation },
];
rejectedBodies.forEach(body => assert.throws(() => parseSyntheticRunnerRequest(body, now)));

assert.deepEqual(parseSyntheticRunnerRequest({
  type: "end",
  actorId,
  sessionId,
  sequence: 2,
  occurredAtMs: now + 2_000,
  status: "paused",
  reason: "owner-paused",
}, now), {
  type: "end",
  actorId,
  sessionId,
  sequence: 2,
  occurredAtMs: now + 2_000,
  status: "paused",
  reason: "owner-paused",
});

const eventId = syntheticRunnerEventId("event", actorId, generation, sessionId, 1);
assert.equal(eventId, syntheticRunnerEventId("event", actorId, generation, sessionId, 1));
assert.notEqual(eventId, syntheticRunnerEventId("event", actorId, generation + 1, sessionId, 1));

const mapPost = syntheticMapPostData(actorId, generation, sessionId, 1);
assert.equal(syntheticMapPostId(actorId, generation), `synthetic-${actorId}-${generation}`);
assert.deepEqual([mapPost.longitude, mapPost.latitude], [-79.383, 43.653]);
assert.equal(mapPost.locationVisibility, "approximate");
assert.equal(mapPost.syntheticBeta, true);
assert.equal(mapPost.testOnly, true);
assert.equal(mapPost.userID, actorId);
assert.equal(mapPost.radiusMeters, 2400);
assert.equal(syntheticMapPostData(actorId, generation, sessionId, 2).radiusMeters, 3000);
assert.throws(() => syntheticMapPostData("not-an-actor", generation, sessionId, 1));
const betaMapPost = syntheticBetaPostData(actorId, generation, sessionId, 2);
assert.equal(betaMapPost.radiusKm, 3);
assert.equal(betaMapPost.initialRadiusKm, 2.4);
assert.equal(betaMapPost.radiusDeltaKm, 0.6000000000000001);
assert.equal(betaMapPost.place, "Toronto");

function runtimeEvent(sequence, eventGeneration = generation) {
  return {
    eventId: syntheticRunnerEventId("event", actorId, eventGeneration, sessionId, sequence),
    actorId,
    actor: SYNTHETIC_BETA_PROFILES[0].label,
    sessionId,
    generation: eventGeneration,
    sequence,
    priorScreen: sequence === 1 ? "home" : "map",
    screen: "map",
    currentScreen: "map",
    action: "screen-view",
    eventType: "navigation",
    stepIndex: sequence,
    journeyLength: 200,
    dwellMs: 500,
    status: "foreground",
    localFrameSequence: sequence,
    frameSuppressed: true,
    metrics: { frameRate: 30 },
    eventAtMs: now + sequence,
    place: SYNTHETIC_BETA_PROFILES[0].place,
    source: "synthetic-browser",
    cohortId: SYNTHETIC_BETA_COHORT_ID,
  };
}

let runtime;
for (let sequence = 1; sequence <= 100; sequence += 1) {
  const event = runtimeEvent(sequence);
  const advanced = advanceSyntheticBrowserRuntime(runtime, event);
  const repeated = advanceSyntheticBrowserRuntime(advanced, event);
  assert.equal(repeated.analytics.eventCount, advanced.analytics.eventCount, "duplicate counted twice");
  runtime = advanced;
}
assert.equal(runtime.analytics.eventCount, 100);
assert.equal(runtime.sessions.length, 1);
assert.equal(runtime.recentEvents.length, SYNTHETIC_RUNNER_RECENT_EVENT_LIMIT);
assert.equal(runtime.analytics.averageDwellMs, 500);
assert.equal(Object.values(runtime.analytics.actionCounts).reduce((sum, value) => sum + value, 0), 100);

const nextGeneration = advanceSyntheticBrowserRuntime(runtime, runtimeEvent(1, generation + 1));
assert.equal(nextGeneration.generation, generation + 1);
assert.equal(nextGeneration.analytics.eventCount, 1, "stale generation leaked into new runtime");
assert.equal(nextGeneration.recentEvents.length, 1);

const prohibitedEventKeys = new Set([
  "coordinates", "latitude", "longitude", "pixels", "dom", "text", "message",
  "media", "frame", "url", "microphone", "recording", "email", "uid",
]);
Object.keys(runtime.recentEvents[0]).forEach(key => {
  assert.ok(!prohibitedEventKeys.has(key), `prohibited stored event key ${key}`);
});

console.log("synthetic browser runner privacy/idempotency/generation tests PASS");
