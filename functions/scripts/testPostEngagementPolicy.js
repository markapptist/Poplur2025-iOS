"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const policy = require(process.argv[2] || "../lib/postEngagementPolicy.js");

const parsed = policy.parsePostEngagementInput({
  postId: "post-1",
  eventId: "evt_1234567890123456",
  kind: "comment",
});
assert.deepEqual(parsed, {
  postId: "post-1",
  eventId: "evt_1234567890123456",
  kind: "comment",
});
assert.throws(() => policy.parsePostEngagementInput({
  ...parsed,
  body: "must never cross this boundary",
}), /only postId, eventId and kind/i);
assert.throws(() => policy.parsePostEngagementInput({
  ...parsed,
  kind: "set-radius",
}), /unsupported engagement kind/i);

const firstView = policy.calculatePostEngagementMutation(
  { radiusMeters: 5_000, viewCount: 4 },
  "view",
  100_000,
  null,
);
assert.equal(firstView.applied, true);
assert.equal(firstView.radiusDeltaMeters, 1_000);
assert.equal(firstView.counters.radiusMeters, 6_000);
assert.equal(firstView.counters.viewCount, 5);

const remount = policy.calculatePostEngagementMutation(
  { radiusMeters: 6_000, viewCount: 5 },
  "view",
  110_000,
  100_000,
);
assert.equal(remount.applied, false);
assert.equal(remount.radiusDeltaMeters, 0);
assert.deepEqual(remount.postUpdate, {});

const replay = policy.calculatePostEngagementMutation(
  { radiusMeters: 6_000, organicRadiusMeters: 4_000, boostedRadiusMeters: 2_000, viewCount: 5 },
  "view",
  130_000,
  100_000,
);
assert.equal(replay.radiusDeltaMeters, 500);
assert.equal(replay.counters.organicRadiusMeters, 4_500);
assert.equal(replay.counters.radiusMeters, 6_500);

const like = policy.calculatePostEngagementMutation(
  { radiusMeters: 9_000, likeCount: 7 },
  "like",
  200_000,
  null,
);
assert.equal(like.radiusDeltaMeters, 1_000);
assert.equal(like.counters.likeCount, 8);

const dislike = policy.calculatePostEngagementMutation(
  { radiusMeters: 500, downvoteCount: 2 },
  "dislike",
  200_000,
  null,
);
assert.equal(dislike.radiusDeltaMeters, -500);
assert.equal(dislike.counters.radiusMeters, 0);
assert.equal(dislike.counters.downvoteCount, 3);

const comment = policy.calculatePostEngagementMutation(
  { radiusMeters: 1_000, commentCount: 1 },
  "comment",
  200_000,
  null,
);
assert.equal(comment.radiusDeltaMeters, 2_000);
assert.equal(comment.counters.commentCount, 2);

assert.equal(
  policy.postEngagementDocumentId("user", "evt_1234567890123456"),
  policy.postEngagementDocumentId("user", "evt_1234567890123456"),
);
assert.notEqual(
  policy.postEngagementDocumentId("user", "evt_1234567890123456"),
  policy.postEngagementDocumentId("other", "evt_1234567890123456"),
);

const rulesPath = process.argv[3];
// ── Reach is earned from OTHER people, and once per person ────────────────
// Both rules below were live defects proven against production on 1 Sep 2026:
// one account added 8 km by tapping like eight times, and a post's own owner
// moved their own radius 18 km -> 23 km alone.

const post = { radiusMeters: 5_000, viewCount: 3, likeCount: 2, commentCount: 1, downvoteCount: 0 };
const fresh = { lastViewAtMillis: null };

// A like pays once per account, however many times it is sent.
const firstLike = policy.calculatePostEngagementMutation(post, "like", 100_000, fresh);
assert.equal(firstLike.applied, true);
assert.equal(firstLike.radiusDeltaMeters, 1_000);
assert.equal(firstLike.actorStateUpdate.liked, true);

const repeatLike = policy.calculatePostEngagementMutation(
  post, "like", 200_000, { lastViewAtMillis: null, liked: true },
);
assert.equal(repeatLike.applied, false, "a second like from one account must not pay");
assert.equal(repeatLike.radiusDeltaMeters, 0);
assert.equal(repeatLike.counters.likeCount, 2, "and must not inflate the like count");

// Same for a dislike.
const repeatDislike = policy.calculatePostEngagementMutation(
  post, "dislike", 200_000, { lastViewAtMillis: null, disliked: true },
);
assert.equal(repeatDislike.applied, false);
assert.equal(repeatDislike.radiusDeltaMeters, 0);

// Commenting again still counts as a comment; it just stops paying radius.
const firstComment = policy.calculatePostEngagementMutation(post, "comment", 100_000, fresh);
assert.equal(firstComment.radiusDeltaMeters, 2_000);
assert.equal(firstComment.actorStateUpdate.commentGranted, true);
const secondComment = policy.calculatePostEngagementMutation(
  post, "comment", 200_000, { lastViewAtMillis: null, commentGranted: true },
);
assert.equal(secondComment.applied, true, "the comment itself still lands");
assert.equal(secondComment.radiusDeltaMeters, 0, "but it pays no more radius");
assert.equal(secondComment.counters.commentCount, 2);

// The owner earns nothing from themselves — no radius and no counter.
for (const kind of ["view", "like", "comment", "dislike"]) {
  const own = policy.calculatePostEngagementMutation(post, kind, 100_000, fresh, true);
  assert.equal(own.applied, false, `owner ${kind} must not apply`);
  assert.equal(own.radiusDeltaMeters, 0, `owner ${kind} must not move radius`);
  assert.equal(own.counters.radiusMeters, 5_000);
  assert.equal(own.counters.viewCount, 3, `owner ${kind} must not move the view count`);
  assert.equal(own.counters.likeCount, 2);
}

// A stranger is unaffected by all of the above.
const stranger = policy.calculatePostEngagementMutation(post, "like", 100_000, fresh, false);
assert.equal(stranger.applied, true);
assert.equal(stranger.radiusDeltaMeters, 1_000);

if (rulesPath) {
  const rules = fs.readFileSync(rulesPath, "utf8");
  const requiredProtectedFields = [
    "radius", "radiusMeters", "organicRadiusMeters", "boostedRadiusMeters",
    "viewCount", "likeCount", "downvoteCount", "commentCount",
    "lastEngagementAt", "likeNotifyAt", "likesPendingNotify",
  ];
  requiredProtectedFields.forEach(field => assert.match(
    rules,
    new RegExp(`['\"]${field}['\"]`),
    `missing protected post field ${field}`,
  ));
  assert.match(rules, /keepsPostEngagementFieldsUnchanged\(\)/);
  assert.match(
    rules,
    /match \/engagements\/\{engagementId\}[\s\S]*?allow create: if false;/,
  );
}

console.log("post engagement policy: PASS");
