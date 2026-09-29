const assert = require("node:assert/strict");
const { foldScorecard, dayKey, dayKeyOffset, THRESHOLDS } = require("../lib/betaScorecard");

const T0 = Date.UTC(2026, 8, 22, 16, 0, 0); // Tue 22 Sep 2026, noon Toronto — invite day
const H = 3_600_000, D = 24 * H;
const human = (uid, at) => ({ uid, createdAtMillis: at });
const pop = (id, uid, at, extra = {}) => ({ id, uid, createdAtMillis: at, human: true, seedMeters: 5_000, organicMeters: 0, radiusMeters: 5_000, live: true, ...extra });
const eng = (postId, postOwnerUid, actorUid, at, surface = "feed", actorHuman = true) => ({ postId, postOwnerUid, actorUid, actorHuman, kind: "like", surface, createdAtMillis: at });

assert.equal(dayKey(T0), "2026-09-22");
assert.equal(dayKeyOffset("2026-09-22", 14), "2026-10-06");

// Four students. A posts within the hour and again after B likes it; B posts on day 2 only;
// C installs and never posts; D is outside the window and never counts.
const now = T0 + 16 * D;
const input = {
  nowMillis: now, startMillis: T0 - D, endMillis: null, promptDays: ["2026-09-22", "2026-09-23"], referralInstalls: 2,
  humans: [human("a", T0), human("b", T0 + H), human("c", T0 + 2 * H), human("d", T0 - 40 * D)],
  posts: [
    pop("a1", "a", T0 + H),
    pop("b1", "b", T0 + 2 * D, { organicMeters: 400, radiusMeters: 5_400 }), // grew after a's like
    pop("a2", "a", T0 + 2 * D + 30 * H, { organicMeters: 1_200, radiusMeters: 6_200 }),
    pop("d1", "d", T0 - 39 * D),
    pop("a3", "a", T0 + 7 * D + H),               // day 7 activity for a
    pop("b2", "b", T0 + 14 * D + H, { organicMeters: 800, radiusMeters: 5_800 }), // day 14 activity for b
  ],
  engagements: [
    eng("a1", "a", "b", T0 + 2 * D + 2 * H, "map"),        // b finds a1 by radius → a1 grew (organic below)
    eng("a2", "a", "b", T0 + 3 * D, "profile"),
    eng("b1", "b", "a", T0 + 2 * D + 5 * H, "feed"),
    eng("b1", "b", "sim-food-001", T0 + 2 * D, "feed", false), // synthetic like never counts
  ],
  earnedByUid: new Map([["a", 1_200], ["b", 800]]),
  replacedPops: 1,
};
input.posts[0].organicMeters = 900; input.posts[0].radiusMeters = 5_900; // a1 grew after b's like

const card = foldScorecard(input);
assert.equal(card.installs, 3, "d is outside the window");
const by = Object.fromEntries(card.signals.map(s => [s.key, s]));
assert.deepEqual([by.activation.count, by.activation.of], [1, 3], "only a posted within 24 h");
assert.equal(by.activation.verdict, "mid", "1 of 3 sits between weak (30 %) and good (60 %)");
assert.deepEqual([by.d7.count, by.d7.of], [1, 3], "a was active on day 7");
assert.deepEqual([by.d14.count, by.d14.of], [1, 3], "b was active on day 14");
assert.equal(by.d7.verdict, "good", "1 of 3 clears the 30 % line");
assert.deepEqual([by.loop.count, by.loop.of], [3, 3], "every engaged pop grew");
assert.deepEqual([by.discovery.count, by.discovery.of], [2, 3], "map + feed vs one profile visit");
assert.deepEqual([by.offPrompt.count, by.offPrompt.of], [4, 5], "a1 landed on a prompt day; the rest did not");
assert.equal(card.loop.repostRateGrew, 0.5, "a reposted within 72 h of b's like; b did not");
assert.equal(card.loop.repostRateNotGrew, null, "nobody with an un-grown pop to compare against");
assert.equal(card.organic.referralInstalls, 2);
assert.equal(card.activity.humanEngagements, 3, "the synthetic like is not a human engagement");
assert.deepEqual(card.integrity, { overClaimedPops: 0, ladderPops: 0, replacedPops: 1 });

// Nothing yet: everything is pending, nothing is zero-shamed.
const empty = foldScorecard({ ...input, humans: [], posts: [], engagements: [] });
assert.equal(empty.installs, 0);
assert.ok(empty.signals.every(s => s.verdict === "pending"), "no denominators → pending");

// Retention is only judged once the day has passed.
const fresh = foldScorecard({ ...input, nowMillis: T0 + 3 * D });
const f = Object.fromEntries(fresh.signals.map(s => [s.key, s]));
assert.equal(f.d7.verdict, "pending");
assert.equal(f.d7.of, 0);

// Integrity catches a seed above the allowance and a ladder pop.
const dirty = foldScorecard({ ...input, posts: [...input.posts, pop("x", "c", T0 + D, { seedMeters: 40_000, radiusMeters: 40_000 })] });
assert.deepEqual(dirty.integrity, { overClaimedPops: 1, ladderPops: 1, replacedPops: 1 });
assert.ok(THRESHOLDS.activation.good > THRESHOLDS.activation.weak);
console.log("beta scorecard: PASS");
