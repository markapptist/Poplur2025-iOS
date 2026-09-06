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

// ── Repeat views halve: time alone buys ~1 km, not the world ──────────────
// Measured 2 Sep 2026: the uncapped +500/30s let one account earn +29 km in
// 30 minutes. Each PAID repeat now halves the next (500, 250, 125 … 0) and
// the halving index rides the same actor-state doc as the like grant.
{
  let paid = 0;
  let total = 0;
  const expected = [500, 250, 125, 62, 31, 15, 7, 3, 1];
  for (const meters of expected) {
    const repeat = policy.calculatePostEngagementMutation(
      post, "view", 200_000 + paid,
      { lastViewAtMillis: 100_000, paidRepeatViews: paid },
    );
    assert.equal(repeat.applied, true);
    assert.equal(repeat.radiusDeltaMeters, meters, `repeat #${paid + 1} must pay ${meters}`);
    assert.equal(repeat.actorStateUpdate.paidRepeatViews, paid + 1);
    total += meters;
    paid += 1;
  }
  assert.equal(total, 994, "lifetime repeat payout stays under 1 km");
  // Exhausted: the view still counts and still advances the 30s clock, but
  // pays nothing and stops touching the actor state.
  const exhausted = policy.calculatePostEngagementMutation(
    { ...post, viewCount: 9 }, "view", 900_000,
    { lastViewAtMillis: 100_000, paidRepeatViews: 9 },
  );
  assert.equal(exhausted.applied, true, "an exhausted repeat view still counts");
  assert.equal(exhausted.radiusDeltaMeters, 0);
  assert.equal(exhausted.counters.viewCount, 10);
  assert.equal(exhausted.nextViewAtMillis, 900_000);
  assert.deepEqual(exhausted.actorStateUpdate, {});
  // The legacy bare-number actor state means "no repeats paid yet".
  const legacy = policy.calculatePostEngagementMutation(post, "view", 200_000, 100_000);
  assert.equal(legacy.radiusDeltaMeters, 500);
}

// ── Decay: a score you defend ─────────────────────────────────────────────
// 5%/day on organic only, elapsed-time based, floored to zero near dust.
{
  const DAY = 86_400_000;
  const decayed = policy.calculateRadiusDecay(
    { organicRadiusMeters: 10_000, radiusMeters: 10_000, decayedAt: 0 }, DAY,
  );
  assert.deepEqual(decayed, { organicRadiusMeters: 9_500, radiusMeters: 9_500 });
  // Boost never decays and is re-added on top of the shrunken organic.
  const boosted = policy.calculateRadiusDecay(
    { organicRadiusMeters: 4_000, radiusMeters: 6_000, boostedRadiusMeters: 2_000, decayedAt: 0 },
    DAY,
  );
  assert.deepEqual(boosted, { organicRadiusMeters: 3_800, radiusMeters: 5_800 });
  // The discovery seed never decays either and never drops out of the total:
  // a seeded post keeps its 5 km window while only the earned part shrinks.
  // (It used to vanish on the first tick — 6,750 m → 1,726 m in production.)
  const seeded = policy.calculateRadiusDecay(
    { organicRadiusMeters: 1_750, radiusMeters: 6_750, seedRadiusMeters: 5_000, decayedAt: 0 },
    DAY,
  );
  assert.deepEqual(seeded, { organicRadiusMeters: 1_662, radiusMeters: 6_662 });
  // Dust snaps to zero instead of shrinking forever.
  const dust = policy.calculateRadiusDecay(
    { organicRadiusMeters: 9, radiusMeters: 9, decayedAt: 0 }, DAY,
  );
  assert.deepEqual(dust, { organicRadiusMeters: 0, radiusMeters: 0 });
  // Nothing to write: no baseline stamp yet, nothing organic, or no time.
  assert.equal(policy.calculateRadiusDecay({ organicRadiusMeters: 10_000 }, DAY), null);
  assert.equal(policy.calculateRadiusDecay(
    { organicRadiusMeters: 0, decayedAt: 0 }, DAY), null);
  assert.equal(policy.calculateRadiusDecay(
    { organicRadiusMeters: 10_000, decayedAt: 0 }, 30_000), null);
  // A future-dated clock must freeze nothing INTO GROWTH: never pays upward.
  assert.equal(policy.calculateRadiusDecay(
    { organicRadiusMeters: 10_000, decayedAt: 10 * DAY }, DAY), null);
}

// ── Radius history: a pop's curve, one entry per change ──────────────────
{
  const first = policy.calculatePostEngagementMutation(
    { radiusMeters: 5_000, seedRadiusMeters: 5_000, organicRadiusMeters: 0 },
    "like", 100_000, null,
  );
  // The mutation carries where it stepped FROM, and the parts under the sum.
  assert.deepEqual(first.previous, { radiusMeters: 5_000, organicRadiusMeters: 0 });
  assert.deepEqual(first.radius, { seed: 5_000, boost: 0 });
  assert.equal(first.counters.radiusMeters, 6_000);
  const entry = policy.buildRadiusHistoryEntry({
    atMillis: 100_000,
    cause: "engagement",
    writer: "recordPostEngagement",
    previous: first.previous,
    next: first.counters,
    seedRadiusMeters: first.radius.seed,
    boostedRadiusMeters: first.radius.boost,
    kind: "like",
    engagementId: "abc",
  });
  assert.deepEqual(entry, {
    atMillis: 100_000,
    cause: "engagement",
    radiusMeters: 6_000,
    organicRadiusMeters: 1_000,
    seedRadiusMeters: 5_000,
    boostedRadiusMeters: 0,
    delta: 1_000,
    organicDelta: 1_000,
    writer: "recordPostEngagement",
    kind: "like",
    engagementId: "abc",
  });
  // The first point of a curve steps from nothing.
  const born = policy.buildRadiusHistoryEntry({
    atMillis: 1, cause: "create", writer: "t", previous: null,
    next: { radiusMeters: 5_000, organicRadiusMeters: 0 }, seedRadiusMeters: 5_000, boostedRadiusMeters: 0,
  });
  assert.equal(born.delta, 0);
  assert.equal(born.organicDelta, 0);
  assert.equal("kind" in born, false);
  // A repeat that pays nothing reports the unchanged total INCLUDING the seed
  // (it used to drop the seed from what it told the client).
  const nothing = policy.calculatePostEngagementMutation(
    { radiusMeters: 6_000, seedRadiusMeters: 5_000, organicRadiusMeters: 1_000 },
    "like", 100_000, { lastViewAtMillis: null, liked: true },
  );
  assert.equal(nothing.applied, false);
  assert.equal(nothing.counters.radiusMeters, 6_000);
  assert.equal(nothing.previous.radiusMeters, 6_000);
  // An entry steps from what the document DECLARED, not from the policy's
  // sum: a post the old decay left at 994 m with its 5,000 m seed still on the
  // doc shows 994 on the pin, so a like that lands it at 5,994+1,000 is a
  // +6,000 m change to the person watching, not +1,000.
  const damaged = policy.calculatePostEngagementMutation(
    { radiusMeters: 994, radius: 994, organicRadiusMeters: 994, seedRadiusMeters: 5_000 },
    "like", 100_000, null,
  );
  assert.equal(damaged.previous.radiusMeters, 994);
  assert.equal(damaged.counters.radiusMeters, 6_994);
  assert.equal(policy.buildRadiusHistoryEntry({
    atMillis: 1, cause: "engagement", writer: "t", previous: damaged.previous, next: damaged.counters,
    seedRadiusMeters: 5_000, boostedRadiusMeters: 0,
  }).delta, 6_000);
  assert.deepEqual(
    policy.postRadiusParts({ radiusMeters: 994, organicRadiusMeters: 994, seedRadiusMeters: 5_000 }, 0),
    { organic: 994, boost: 0, seed: 5_000, total: 5_994, stored: 994 },
  );
  assert.equal(policy.postRadiusParts({ organicRadiusMeters: 10 }, 0).stored, null);
  // Deterministic ids, so a retried write lands on the same point.
  assert.equal(policy.radiusHistoryEntryId.engagement("e1"), "eng_e1");
  assert.equal(policy.radiusHistoryEntryId.decay(5), "decay_5");
  assert.equal(policy.radiusHistoryEntryId.create(), "create");
  // The stored post's parts, read the way the policy reads them.
  assert.deepEqual(
    policy.postRadiusParts({ radiusMeters: 6_750, organicRadiusMeters: 1_750, seedRadiusMeters: 5_000 }, 0),
    { organic: 1_750, boost: 0, seed: 5_000, total: 6_750, stored: 6_750 },
  );
}

if (rulesPath) {
  const rules = fs.readFileSync(rulesPath, "utf8");
  const requiredProtectedFields = [
    "radius", "radiusMeters", "organicRadiusMeters", "boostedRadiusMeters",
    "viewCount", "likeCount", "downvoteCount", "commentCount",
    "lastEngagementAt", "likeNotifyAt", "likesPendingNotify",
    "decayedAt",
  ];
  assert.match(rules, /match \/radiusHistory\/\{entryId\} \{\s*allow read: if true;\s*allow write: if false;/,
    "posts/{postId}/radiusHistory must be public-read and never client-written");
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
  // Creation must be seed-guarded too: without validNewPostEngagementSeed a
  // modified client mints a post already at world radius and skips the
  // engagement economy entirely.
  assert.match(rules, /function validNewPostEngagementSeed\(\)/);
  assert.match(
    rules,
    /match \/posts\/\{postId\}[\s\S]*?allow create:[\s\S]*?validNewPostEngagementSeed\(\)/,
    "the posts create rule must apply the engagement seed guard",
  );
}

// A discovery seed is reach, never entitlement. It must stay out of
// organicRadiusMeters, because the account total that grants a claim is summed
// from that field alone — otherwise post count mints claim power.
const seeded = policy.calculatePostEngagementMutation(
  { radiusMeters: 5_000, seedRadiusMeters: 5_000, viewCount: 0 },
  'view',
  100_000,
  null,
);
assert.equal(seeded.applied, true);
assert.equal(seeded.counters.organicRadiusMeters, 1_000, 'the seed must not be counted as earned');
assert.equal(seeded.counters.radiusMeters, 6_000, 'reach is seed plus earned');

// An unseeded post from before this rule keeps its old meaning: its whole
// radius is treated as earned, so no account loses entitlement it had.
const legacy = policy.calculatePostEngagementMutation(
  { radiusMeters: 5_000, viewCount: 0 },
  'view',
  100_000,
  null,
);
assert.equal(legacy.counters.organicRadiusMeters, 6_000, 'legacy posts keep counting as earned');

// A big seed is honoured as a seed, and buys nothing.
const claimed = policy.calculatePostEngagementMutation(
  { radiusMeters: 50_000, seedRadiusMeters: 50_000, viewCount: 0 },
  'view',
  100_000,
  null,
);
// MAX_POST_SEED_METERS stopped being 5 km on 6 Sep 2026 (2c780362): a drop may
// claim every metre the account earned, so clipping the seed here would have
// re-counted the claimed part as EARNED on the post's first view — the account
// would then have been paid entitlement for ground it had merely spent. What
// stops an inflated claim is the create rule reading the account's own total
// (firestore.rules maxSeedRadiusMeters), not a clamp after the fact.
assert.equal(claimed.counters.organicRadiusMeters, 1_000,
  'a claimed seed stays spent reach; only the view is earned');
assert.equal(claimed.counters.radiusMeters, 51_000, 'and reach is seed plus what it earned');

console.log('post engagement policy: PASS');
