"use strict";

/**
 * The account entitlement aggregate: users/{uid}.claimRadiusMeters.
 *
 * firestore.rules cannot sum a collection, so the create rule reads this
 * field instead of the posts it stands for. That only holds while the two
 * agree, so the tests here are mostly one shape: run a realistic sequence of
 * radius moves through the same policy the transactions use, maintain the
 * aggregate the same way the transactions maintain it, and assert the result
 * still equals a fresh sum over the posts.
 *
 *   node scripts/testAccountClaimRadius.js
 */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const account = require(process.argv[2] || "../lib/accountRadius.js");
const policy = require("../lib/postEngagementPolicy.js");

// ── What one post contributes ────────────────────────────────────────────
// Deliberately identical to the web picker's reading in
// poplur-clay-map/src/accountRadiusPosts.ts. If these drift, a legitimate
// claim is refused on upload with nothing on screen to explain it.
assert.equal(
  account.postEarnedRadiusMeters({ radius: 5_000, seedRadiusMeters: 5_000, organicRadiusMeters: 0 }),
  0,
  "a fresh seeded post has earned nothing",
);
assert.equal(
  account.postEarnedRadiusMeters({ radius: 6_000, seedRadiusMeters: 5_000, organicRadiusMeters: 1_000 }),
  1_000,
  "a seeded post contributes only what it earned",
);
assert.equal(
  account.postEarnedRadiusMeters({ radius: 7_000, seedRadiusMeters: 5_000 }),
  2_000,
  "with no declared pool, total minus seed is what was earned",
);
assert.equal(
  account.postEarnedRadiusMeters({ radius: 3_000, seedRadiusMeters: 5_000 }),
  0,
  "a post below its own seed has earned nothing, never a negative",
);
assert.equal(
  account.postEarnedRadiusMeters({ radius: 40_075_000, organicRadiusMeters: 40_075_000 }),
  6_371_000,
  "an official world-radius post is clamped like every other radius reader",
);

// ── The sum ──────────────────────────────────────────────────────────────
assert.equal(account.accountClaimRadiusSum([]), 0, "no posts is no entitlement");
assert.equal(
  account.accountClaimRadiusSum([
    { radius: 5_000, seedRadiusMeters: 5_000, organicRadiusMeters: 0 },
    { radius: 6_000, seedRadiusMeters: 5_000, organicRadiusMeters: 1_000 },
    { radius: 30_000, seedRadiusMeters: 25_000, organicRadiusMeters: 5_000 },
  ]),
  6_000,
  "entitlement is earned radius only — seeds never count, however many posts carry them",
);

// A thousand seeded posts still buy nothing. This is the property the whole
// seed/earned split exists for.
assert.equal(
  account.accountClaimRadiusSum(Array.from({ length: 1_000 }, () => (
    { radius: 25_000, seedRadiusMeters: 25_000, organicRadiusMeters: 0 }
  ))),
  0,
  "post count is not claim power",
);

assert.equal(account.postOwnerUid({ userID: "a" }), "a");
assert.equal(account.postOwnerUid({ userId: "b" }), "b", "the older spelling is an owner too");
assert.equal(account.postOwnerUid({ ownerId: "c" }), "c");
assert.equal(account.postOwnerUid({}), "", "a post with no owner names nobody");

// ── The step each writer stages ──────────────────────────────────────────
assert.equal(account.claimRadiusDeltaMeters(1_000, 2_000), 1_000, "growth adds");
assert.equal(account.claimRadiusDeltaMeters(2_000, 1_500), -500, "decay takes back");
assert.equal(account.claimRadiusDeltaMeters(undefined, 1_000), 1_000, "an absent pool starts at zero");
assert.equal(account.claimRadiusDeltaMeters(1_000, 1_000), 0, "no move, no write");
assert.equal(account.claimRadiusDeltaMeters("nonsense", 700), 700, "junk reads as zero, never NaN");

/** A Transaction/WriteBatch stand-in that records what was staged, and a
 *  reader that resolves the recorded FieldValue.increment sentinels. */
function recordingWriter() {
  const writes = [];
  return {
    writes,
    set(ref, data, options) { writes.push({ ref, data, options }); },
    /** The aggregate as Firestore would leave it after these writes. */
    total(ref, from = 0) {
      return writes
        .filter(write => write.ref === ref)
        .reduce((sum, write) => {
          const value = write.data[account.ACCOUNT_CLAIM_RADIUS_FIELD];
          // firebase-admin's increment sentinel keeps its operand privately;
          // read it back the way the emulator would apply it.
          const operand = value && typeof value === "object"
            ? Number(Object.values(value).find(entry => typeof entry === "number"))
            : Number(value);
          assert.ok(Number.isFinite(operand), "every staged aggregate write carries a number");
          return sum + operand;
        }, from);
    },
  };
}

const noop = recordingWriter();
assert.equal(account.addAccountClaimRadius(noop, "users/a", 0), false, "a zero step stages nothing");
assert.equal(account.addAccountClaimRadius(noop, "users/a", Number.NaN), false, "junk stages nothing");
assert.equal(noop.writes.length, 0, "and really stages nothing — a merge write of nothing still costs a write");

const staged = recordingWriter();
assert.equal(account.addAccountClaimRadius(staged, "users/a", 1_000), true);
assert.equal(staged.writes[0].options.merge, true,
  "a merge write, so an account with no document yet is created rather than failing the whole engagement");
assert.equal(staged.total("users/a"), 1_000);

// ── The maintenance invariant ────────────────────────────────────────────
//
// recordPostEngagement stages claimRadiusDeltaMeters(previous.organic,
// counters.organic) against the owner, in the transaction that writes the
// post. radiusDecay stages the same delta for the shrink. Drive both through
// the real policy and assert the aggregate lands exactly on a fresh sum.
const owner = "users/owner";
const writer = recordingWriter();
let post = { radiusMeters: 30_000, radius: 30_000, seedRadiusMeters: 30_000, organicRadiusMeters: 0 };
let now = 1_000_000;

function engage(kind, actorState = null) {
  const mutation = policy.calculatePostEngagementMutation(post, kind, now, actorState);
  if (!mutation.applied) return mutation;
  account.addAccountClaimRadius(writer, owner, account.claimRadiusDeltaMeters(
    mutation.previous.organicRadiusMeters,
    mutation.counters.organicRadiusMeters,
  ));
  post = { ...post, ...mutation.postUpdate };
  return mutation;
}

engage("view");
engage("like", { lastViewAtMillis: now, liked: false });
engage("comment", { lastViewAtMillis: now, commentGranted: false });
assert.ok(post.organicRadiusMeters > 0, "the post earned something to aggregate");
assert.equal(
  writer.total(owner),
  account.accountClaimRadiusSum([post]),
  "after three engagements the aggregate equals the posts it summarises",
);

// Decay, on the same principle: the same delta, taken back.
const stamp = millis => ({ toMillis: () => millis });
post = { ...post, decayedAt: stamp(now) };
now += 30 * 86_400_000;
const before = policy.postRadiusParts(post, now);
const decayed = policy.calculateRadiusDecay(post, now);
assert.ok(decayed, "thirty days is long enough to decay");
account.addAccountClaimRadius(writer, owner, account.claimRadiusDeltaMeters(
  before.organic,
  decayed.organicRadiusMeters,
));
post = { ...post, ...decayed, radius: decayed.radiusMeters };
assert.ok(writer.total(owner) < account.accountClaimRadiusSum([{ ...post, organicRadiusMeters: before.organic }]),
  "decay really took entitlement back");
assert.equal(
  writer.total(owner),
  account.accountClaimRadiusSum([post]),
  "after decay the aggregate still equals the posts it summarises",
);

// Decay to nothing leaves the aggregate at exactly zero, not at a residue.
post = { ...post, decayedAt: stamp(now) };
now += 3_650 * 86_400_000;
const floored = policy.calculateRadiusDecay(post, now);
assert.ok(floored, "ten years decays");
assert.equal(floored.organicRadiusMeters, 0, "and decays to the floor");
account.addAccountClaimRadius(writer, owner, account.claimRadiusDeltaMeters(
  policy.postRadiusParts(post, now).organic,
  floored.organicRadiusMeters,
));
assert.equal(writer.total(owner), 0, "an account whose posts earned nothing back is entitled to nothing");

// ── The ceiling the create rule enforces ─────────────────────────────────
// Earned once, spent once: the discovery seed plus (earned − committed).
const SEED = account.POST_DISCOVERY_SEED_METERS;
assert.equal(account.maxSeedRadiusMeters(0, 0), SEED,
  "an account that has earned nothing may still publish into the discovery seed");
assert.equal(account.maxSeedRadiusMeters(72_800, 0), 72_800 + SEED,
  "an account holding 72.8 km may claim 72.8 km, which is the point of the 6 Sep change");
assert.equal(account.maxSeedRadiusMeters(72_800, 72_800), SEED,
  "a claim already sitting on a live pop cannot be claimed again");
assert.equal(account.maxSeedRadiusMeters(72_800, 20_000), 52_800 + SEED,
  "what is out on other pops comes off the allowance");
assert.equal(account.maxSeedRadiusMeters(10_000, 50_000), SEED,
  "more committed than earned (decayed earnings) is the seed, never negative");
assert.equal(account.maxSeedRadiusMeters(-5_000, 0), SEED,
  "a drifted negative aggregate reads as zero, never as a negative ceiling");
assert.equal(account.maxSeedRadiusMeters(null, null), SEED,
  "absent means zero — there is no migration fallback any more");
assert.equal(account.maxSeedRadiusMeters(9_000_000, 0), 6_371_000,
  "the planet is still the outer bound");

// ── The rule and this module say the same thing ──────────────────────────
// The numbers above are duplicated into firestore.rules by hand, because rules
// cannot import. Read them back so a change to one that misses the other fails
// here rather than in production.
const totals = require("../lib/accountTotalRadius");
const rules = fs.readFileSync(path.join(__dirname, "..", "..", "firestore.rules"), "utf8");
const ceilingStart = rules.indexOf("function maxSeedRadiusMeters(");
assert.ok(ceilingStart > 0, "firestore.rules still defines the ceiling this module mirrors");
const ceiling = rules.slice(ceilingStart, rules.indexOf("}", ceilingStart));
assert.ok(ceiling.includes(`'${totals.ACCOUNT_EARNED_CLAIM_FIELD}'`),
  "the rule reads the earned sum the trigger maintains");
assert.ok(ceiling.includes(`'${totals.ACCOUNT_COMMITTED_CLAIM_FIELD}'`),
  "and subtracts the committed sum the trigger maintains");
assert.ok(!ceiling.includes(totals.ACCOUNT_TOTAL_RADIUS_FIELD),
  "the profile's full-radius sum grants nothing — that was the ladder");
assert.ok(ceiling.includes(`+ ${account.POST_DISCOVERY_SEED_METERS}`),
  "the rule adds the same discovery seed");
for (const field of [totals.ACCOUNT_EARNED_CLAIM_FIELD, totals.ACCOUNT_COMMITTED_CLAIM_FIELD,
  ...Object.values(totals.POST_RATE_FIELDS)]) {
  assert.ok(rules.includes(`'${field}'`), `the fence names ${field}`);
}
assert.ok(
  rules.includes("serverOwnedAccountRadiusFields"),
  "the aggregate is fenced from the account that owns the document it lives on",
);
assert.ok(
  rules.includes(`'${account.ACCOUNT_CLAIM_RADIUS_FIELD}', 'claimRadiusUpdatedAt'`),
  "and the fence names the field by the same name the server writes",
);

console.log("account claim radius: PASS");
