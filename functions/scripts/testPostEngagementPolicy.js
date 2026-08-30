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
