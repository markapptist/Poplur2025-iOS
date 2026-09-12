"use strict";

/**
 * The digest's knobs are pinned to the main codebase: the two synced modules
 * must be byte-identical to functions/src, the grants the synced policy pays
 * must be the ones the digest's KNOBS declare, and the three knobs lifted from
 * source text by pattern must still be found and match the stamp. A miss here
 * blocks the deploy (deploy-nearby-pops-digest.sh), never the desk's numbers.
 *
 *   npm run test:shared-sync
 */
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const sync = require("./syncShared.js");

const libDir = process.argv[2] || path.resolve(__dirname, "..", "lib");
const policy = require(path.join(libDir, "shared", "postEngagementPolicy.js"));
const digest = require(path.join(libDir, "algorithmDigestPolicy.js"));

// ── Byte equality ────────────────────────────────────────────────────────
for (const file of sync.COPIES) {
  const source = fs.readFileSync(path.join(sync.FUNCTIONS_SRC, file));
  const copy = fs.readFileSync(path.join(sync.SHARED_DIR, file));
  assert.ok(source.equals(copy), `src/shared/${file} is not byte-identical to functions/src/${file} — run node scripts/syncShared.js`);
}
const stamp = JSON.parse(fs.readFileSync(sync.STAMP_PATH, "utf8"));
assert.equal(stamp.policySha256, sync.sha256(fs.readFileSync(path.join(sync.SHARED_DIR, "postEngagementPolicy.ts"), "utf8")), "stamp policySha256 is stale");
assert.equal(stamp.identitySha256, sync.sha256(fs.readFileSync(path.join(sync.SHARED_DIR, "syntheticIdentity.ts"), "utf8")), "stamp identitySha256 is stale");
assert.ok(Number.isFinite(stamp.syncedAtMillis) && stamp.syncedAtMillis > 0);

// ── The live grants, driven through the synced mutation with a fresh actor ──
const NOW = 1_700_000_000_000;
const post = { radiusMeters: 100_000, organicRadiusMeters: 100_000, seedRadiusMeters: 0, boostedRadiusMeters: 0 };
const fresh = { lastViewAtMillis: null };
const grant = (kind, actor = fresh) => policy.calculatePostEngagementMutation(post, kind, NOW, actor).radiusDeltaMeters;
assert.equal(grant("view"), 1_000, "first view pays 1,000 m");
assert.equal(grant("like"), 1_000, "like pays 1,000 m");
assert.equal(grant("comment"), 2_000, "comment pays 2,000 m");
assert.equal(grant("dislike"), -1_000, "dislike takes 1,000 m");
assert.equal(grant("view", { lastViewAtMillis: NOW - policy.REPEAT_VIEW_MIN_MS, paidRepeatViews: 0 }), 500, "first paid repeat pays 500 m");
assert.equal(grant("view", { lastViewAtMillis: NOW - policy.REPEAT_VIEW_MIN_MS, paidRepeatViews: 1 }), 250, "…then halves");
assert.equal(grant("view", { lastViewAtMillis: NOW - policy.REPEAT_VIEW_MIN_MS + 1, paidRepeatViews: 0 }), 0, "inside 30 s nothing is paid");
const exhausted = policy.calculatePostEngagementMutation(post, "view", NOW, { lastViewAtMillis: NOW - policy.REPEAT_VIEW_MIN_MS, paidRepeatViews: 64 });
assert.equal(exhausted.applied, true, "an exhausted repeat view is still applied");
assert.equal(exhausted.radiusDeltaMeters, 0, "…and pays 0 m");
assert.equal(exhausted.counters.viewCount, 1, "…so viewCount moves while the ledger does not");
assert.equal(exhausted.counters.radiusMeters, exhausted.previous.radiusMeters, "…and the stored total is unchanged (no entry is written)");

// ── KNOBS parity with the synced module ──────────────────────────────────
const knobs = digest.KNOBS;
assert.equal(knobs.firstViewMeters, 1_000);
assert.equal(knobs.likeMeters, 1_000);
assert.equal(knobs.commentMeters, 2_000);
assert.equal(knobs.dislikeMeters, -1_000);
assert.equal(knobs.repeatViewBaseMeters, policy.REPEAT_VIEW_BASE_METERS);
assert.equal(knobs.repeatViewBaseMeters, 500);
assert.equal(knobs.repeatViewMinMs, policy.REPEAT_VIEW_MIN_MS);
assert.equal(knobs.repeatViewMinMs, 30_000);
assert.equal(knobs.repeatViewLifetimeMeters, 994, "500 + 250 + 125 + 62 + 31 + 15 + 7 + 3 + 1");
assert.equal(knobs.decayPerDay, policy.RADIUS_DECAY_PER_DAY);
assert.equal(knobs.decayPerDay, 0.05);
assert.equal(knobs.decayFloorMeters, policy.RADIUS_DECAY_FLOOR_METERS);
assert.equal(knobs.decayFloorMeters, 10);
assert.equal(knobs.maxRadiusMeters, policy.MAX_POST_RADIUS_METERS);
assert.equal(knobs.maxRadiusMeters, 6_371_000);
assert.equal(knobs.decayHalfLifeDays, 13.51);

// ── Extraction: re-run the anchored patterns and compare with the stamp ───
const extracted = sync.extractKnobs();
assert.equal(extracted.seedMeters, 5_000, "POST_DISCOVERY_SEED_METERS in functions/src/accountRadius.ts");
assert.equal(extracted.boostDefaultMeters, 1_000, "positiveInt(body.radiusMetersAdded, …) in functions/src/index.ts");
assert.equal(extracted.boostDefaultHours, 24, "positiveInt(body.durationHours, …) in functions/src/index.ts");
assert.equal(extracted.stressHalfLifeHours, 4, "SYNTHETIC_RADIUS_HALF_LIFE_HOURS in functions/src/syntheticRetentionPolicy.ts");
for (const key of ["seedMeters", "boostDefaultMeters", "boostDefaultHours", "stressHalfLifeHours"]) {
  assert.equal(stamp.extracted[key], extracted[key], `sync-stamp.json.extracted.${key} is stale`);
  assert.equal(stamp.extracted.sourceLines[key], extracted.sourceLines[key], `sync-stamp.json source line for ${key} moved`);
  assert.equal(knobs[key === "stressHalfLifeHours" ? "syntheticStressHalfLifeHours" : key], extracted[key], `KNOBS.${key} does not read the stamp`);
}
assert.throws(() => sync.extractKnobs((file) => file === "accountRadius.ts" ? "export const POST_DISCOVERY_SEED_METERS = SEED;" : sync.readSource(file)),
  /pattern for seedMeters missed/, "a moved knob fails the extraction, not the desk");

console.log("shared sync: all assertions passed");
