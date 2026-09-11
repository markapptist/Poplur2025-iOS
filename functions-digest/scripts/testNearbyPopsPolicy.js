"use strict";

/**
 * The nearby pops digest policy: who counts as "near you", when a digest may
 * go out, and what it says. Pure functions only; Firestore and FCM live in
 * nearbyPopsDigest.ts and are exercised by a real run.
 *
 *   npm run test:nearby-pops
 */
const assert = require("node:assert/strict");
const policy = require(process.argv[2] || "../lib/nearbyPopsPolicy.js");

const HOUR = 3_600_000;
const TORONTO = { latitude: 43.6487, longitude: -79.3811 };
const T0 = Date.UTC(2026, 8, 11, 17, 0, 0); // 13:00 Toronto solar-ish

function post(overrides = {}) {
  return {
    userID: "someone-else", username: "ari", mediaURL: "https://x/y.jpg",
    latitude: 43.66, longitude: -79.39, radiusMeters: 5_000,
    audience: "public", status: "published", locationVisibility: "approximate",
    createdAt: { toMillis: () => T0 - HOUR },
    ...overrides,
  };
}
const viewer = { viewerUid: "me", includeTestCohort: false };

// ── Distance ─────────────────────────────────────────────────────────────
assert.equal(policy.haversineMeters(TORONTO, TORONTO), 0);
const ottawa = { latitude: 45.4215, longitude: -75.6972 };
const km = policy.haversineMeters(TORONTO, ottawa) / 1000;
assert.ok(km > 350 && km < 360, `Toronto→Ottawa should be ~353 km, got ${km}`);
assert.equal(policy.coordinatePair(43.6, null), null, "half a pair is no pair");
assert.equal(policy.coordinatePair(91, 0), null, "out-of-range latitude is rejected");

// ── Eligibility ──────────────────────────────────────────────────────────
assert.equal(policy.eligibleNearbyPost(post(), viewer), true);
assert.equal(policy.eligibleNearbyPost(post({ userID: "me" }), viewer), false, "never your own post");
assert.equal(policy.eligibleNearbyPost(post({ officialContent: true }), viewer), false, "official world content is not 'near'");
assert.equal(policy.eligibleNearbyPost(post({ audience: "private" }), viewer), false);
assert.equal(policy.eligibleNearbyPost(post({ status: "deleted" }), viewer), false);
assert.equal(policy.eligibleNearbyPost(post({ locationVisibility: "hidden", latitude: undefined, longitude: undefined }), viewer), false, "hidden origin cannot be located");
assert.equal(policy.eligibleNearbyPost(post({ moderationStatus: "removed" }), viewer), false);
assert.equal(policy.eligibleNearbyPost(post({ radiusMeters: 0, radius: 0 }), viewer), false, "an expired pop is not new");
assert.equal(policy.eligibleNearbyPost(post({ syntheticCohort: true }), viewer), false, "test cohort hidden by default");
assert.equal(policy.eligibleNearbyPost(post({ syntheticCohort: true }), { ...viewer, includeTestCohort: true }), true, "…unless the config opts in");
assert.equal(policy.eligibleNearbyPost(post({ mediaURL: undefined, playbackURL: undefined, caption: undefined }), viewer), false, "nothing to open");

// ── Reach: union of "it reaches me" and "I reach it" ─────────────────────
const nearby = post(); // ~1.4 km from TORONTO
assert.equal(policy.postInViewerRadius(nearby, TORONTO, 0), true, "a 5 km pop reaches a viewer 1.4 km away");
const far = post({ latitude: 43.9, longitude: -79.0, radiusMeters: 5_000 }); // ~40 km
assert.equal(policy.postInViewerRadius(far, TORONTO, 0), false, "a 5 km pop 40 km away does not intercept");
assert.equal(policy.postInViewerRadius(far, TORONTO, 84_164), true, "…but an 84 km claim radius reaches it");
assert.equal(policy.postInViewerRadius(post({ latitude: undefined }), TORONTO, 1e7), false);

// ── Timing ───────────────────────────────────────────────────────────────
assert.equal(policy.solarLocalHour(Date.UTC(2026, 8, 11, 12, 0), 0), 12, "Greenwich noon");
assert.equal(policy.solarLocalHour(Date.UTC(2026, 8, 11, 17, 0), -79.38), 11, "Toronto solar hour ≈ UTC−5.3");
assert.equal(policy.solarLocalHour(Date.UTC(2026, 8, 11, 2, 0), 139.7), 11, "Tokyo solar hour ≈ UTC+9.3");
assert.equal(policy.digestWindowOpen(8), false);
assert.equal(policy.digestWindowOpen(9), true);
assert.equal(policy.digestWindowOpen(20), true);
assert.equal(policy.digestWindowOpen(21), false);
assert.equal(policy.digestDue(undefined, T0), true, "never sent → due");
assert.equal(policy.digestDue(T0 - 19 * HOUR, T0), false, "19 h ago → not yet");
assert.equal(policy.digestDue(T0 - 20 * HOUR, T0), true, "20 h ago → due");
assert.equal(policy.digestSinceMillis(undefined, T0), T0 - 24 * HOUR, "first digest looks back one day");
assert.equal(policy.digestSinceMillis(T0 - 20 * HOUR, T0), T0 - 20 * HOUR, "later digests start at the last one");
assert.equal(policy.digestSinceMillis(T0 - 30 * HOUR, T0), T0 - 24 * HOUR, "…but never further back than the lookback");
assert.equal(policy.nearbyDigestId(T0), "nearby:2026-09-11T17");
assert.equal(policy.postCreatedAtMillis({ createdAt: { toMillis: () => 5 } }), 5);
assert.equal(policy.postCreatedAtMillis({ createdAtMillis: 7 }), 7);
assert.equal(policy.postCreatedAtMillis({}), 0);

// ── Copy ─────────────────────────────────────────────────────────────────
assert.equal(policy.nearbyPopsNotification([]), null);
const one = policy.nearbyPopsNotification([{ postId: "p1", handle: "@ari", createdAtMillis: 1 }]);
assert.equal(one.title, "1 new pop in your radius");
assert.equal(one.body, "@ari just landed near you. Tap to see it on the map.");
const three = policy.nearbyPopsNotification([
  { postId: "p1", handle: "@ari", createdAtMillis: 3 },
  { postId: "p2", handle: "@bo", createdAtMillis: 2 },
  { postId: "p3", handle: "@ari", createdAtMillis: 1 },
]);
assert.equal(three.title, "3 new pops in your radius");
assert.equal(three.body, "@ari and @bo and 1 more just landed near you. Tap to see them on the map.");
assert.equal(three.detail, "3 new pops in your radius · @ari and @bo and 1 more");
const anonymous = policy.nearbyPopsNotification([{ postId: "p1", handle: "", createdAtMillis: 1 }, { postId: "p2", handle: "", createdAtMillis: 2 }]);
assert.equal(anonymous.body, "Pops just landed near you. Tap to see them on the map.");
const ordered = policy.orderNewestFirst([{ createdAtMillis: 1 }, { createdAtMillis: 3 }, { createdAtMillis: 2 }]);
assert.deepEqual(ordered.map((c) => c.createdAtMillis), [3, 2, 1], "the row's postId is the freshest pop");

console.log("nearby pops policy: all assertions passed");
