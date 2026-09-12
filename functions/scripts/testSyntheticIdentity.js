// One predicate, one module: the tester table and the algorithm digest must
// agree on who is a person and which pops are theirs, or the desk's REAL
// figures count the simulation. These pin the module's rules and its purity
// (the digest byte-copies the source, so an import here breaks that copy).
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const identity = require(process.argv[2] || "../lib/syntheticIdentity.js");
const { SYNTHETIC_BETA_PROFILES } = require("../lib/syntheticBetaCohort.js");
const testActivity = require("../lib/testActivity.js");

const {
  DESK_OWNER_UIDS, DESK_REVIEW_UIDS,
  isSyntheticAccount, isSyntheticPost, postClass, actorClass,
} = identity;

// ── Pure module ─────────────────────────────────────────────────────────────
const source = fs.readFileSync(path.join(__dirname, "..", "src", "syntheticIdentity.ts"), "utf8");
assert.ok(!/^\s*import\b/m.test(source) && !/\brequire\(/.test(source),
  "syntheticIdentity.ts must import nothing: the digest byte-copies it");

// Dropping syntheticProfile() lost nothing: every cohort id is `sim-`.
assert.ok(SYNTHETIC_BETA_PROFILES.length > 0);
for (const profile of SYNTHETIC_BETA_PROFILES) {
  assert.match(profile.id, /^sim-/, `cohort id ${profile.id} must carry the sim- prefix`);
  assert.equal(isSyntheticAccount(profile.id, undefined, null), true);
}

// testActivity re-exports the very same functions, so the tester table
// cannot drift from the digest.
assert.equal(testActivity.isSyntheticAccount, isSyntheticAccount);
assert.equal(testActivity.isSyntheticPost, isSyntheticPost);

// ── The pinned sets ─────────────────────────────────────────────────────────
assert.deepEqual([...DESK_OWNER_UIDS], ["LiEG6SNtKEZN6eEGeybf0afZnHm1", "eoP2Z0ElxIa0Eua7xpFxNlr6tur1"]);
assert.deepEqual([...DESK_REVIEW_UIDS], ["92eygyJsD3VEXzHXdBLch44AMRl1"]);
assert.ok(Object.isFrozen(DESK_OWNER_UIDS) && Object.isFrozen(DESK_REVIEW_UIDS));

// ── isSyntheticAccount: every spelling (the tester-table assertions, re-run) ─
assert.equal(isSyntheticAccount("sim-food-001", undefined, null), true, "cohort actor id");
assert.equal(isSyntheticAccount("x", { syntheticBeta: true }, null), true);
assert.equal(isSyntheticAccount("synthetic-conquer-orange", undefined, null), true, "colour-lab poster uid");
assert.equal(isSyntheticAccount("sim-daily-2026-09-11-1", undefined, null), true, "sim-daily uid");
assert.equal(isSyntheticAccount("x", { accountType: "synthetic" }, null), true);
assert.equal(isSyntheticAccount("x", { accountType: "Synthetic-Business" }, null), true);
assert.equal(isSyntheticAccount("x", { syntheticCohort: true }, null), true);
assert.equal(isSyntheticAccount("x", { syntheticSource: "daily" }, null), true);
assert.equal(isSyntheticAccount("x", { syntheticSource: "" }, null), false, "an empty source is no source");
assert.equal(isSyntheticAccount("x", undefined, "bot@poplur.test"), true);
assert.equal(isSyntheticAccount("x", undefined, "BOT@POPLUR.TEST"), true, "mailboxes compare case-insensitively");
assert.equal(isSyntheticAccount("x", { accountType: "business" }, "shop@example.com"), false);
assert.equal(isSyntheticAccount("x", null, undefined), false);

// The widened mailbox rule: the permanent QA cohorts live at a poplur.test
// SUBDOMAIN, in Auth only, with no users document to carry a flag.
assert.equal(isSyntheticAccount("n1BkpZPv4HcBKLAG7FXQTzYp7sF2", undefined, "shared.first.user.mtive6bz-abc@synthetic.poplur.test"), true,
  "the lab pin's owner is the shared-onboarding QA account");
assert.equal(isSyntheticAccount("RaNd0mUid", undefined, "radius.actor.1-abc@synthetic.poplur.test"), true,
  "radius cohort actor from the Auth page, no users doc");
assert.equal(isSyntheticAccount("x", undefined, "someone@notpoplur.test"), false,
  "a look-alike domain is neither @poplur.test nor .poplur.test");
assert.equal(isSyntheticAccount("x", undefined, "poplur.test@example.com"), false);
assert.equal(isSyntheticAccount("x", undefined, "mark@poplur.com"), false, "the production mailbox is a person");

// ── isSyntheticPost ─────────────────────────────────────────────────────────
assert.equal(isSyntheticPost({}, true), true, "a synthetic owner makes the post synthetic");
assert.equal(isSyntheticPost({ syntheticBeta: true }, false), true);
assert.equal(isSyntheticPost({ syntheticCohort: true }, false), true);
assert.equal(isSyntheticPost({ syntheticActorId: "sim-food-001" }, false), true);
assert.equal(isSyntheticPost({ syntheticActorId: "" }, false), false);
assert.equal(isSyntheticPost({ userID: "u-real" }, false), false);

// ── postClass: official → lab → synthetic → real, in that order ─────────────
// The 29 App Review posts are owned by a @poplur.com mailbox: only the
// officialContent flag keeps them out of "real".
assert.equal(postClass("post-official-cartoon-drive-ad", { officialContent: true, userID: "PoplurTest" }, false), "official");
// officialContent wins over every other signal, even a synthetic stamp.
assert.equal(postClass("post-radius-lab-1", { officialContent: true, syntheticBeta: true }, true), "official");
// The lab pins also carry syntheticBeta; the id decides before the cohort rule.
assert.equal(postClass("post-radius-lab-abc", { syntheticBeta: true }, false), "lab");
assert.equal(postClass("post-x", { syntheticSource: "radius-lab-cohort" }, false), "lab", "lab by syntheticSource prefix");
assert.equal(postClass("post-x", { syntheticSource: "radius-lab" }, true), "lab", "lab before a synthetic owner");
// Every synthetic spelling.
assert.equal(postClass("post-x", { syntheticBeta: true }, false), "synthetic");
assert.equal(postClass("post-x", {}, true), "synthetic", "synthetic owner");
assert.equal(postClass("post-x", { syntheticSource: "daily" }, false), "synthetic");
assert.equal(postClass("post-x", { source: "synthetic-browser" }, false), "synthetic");
assert.equal(postClass("post-sim-daily-1", {}, false), "synthetic", "post-sim- id prefix");
assert.equal(postClass("synthetic-conquer-orange-1", {}, false), "synthetic", "synthetic- id prefix");
// Anything else is a person's pop, whoever owns it.
assert.equal(postClass("post-455e2ec0abcdef", { userID: "eoP2Z0ElxIa0Eua7xpFxNlr6tur1" }, false), "real", "the owner's own drop is real-class");
assert.equal(postClass("post-x", { userID: "u-tester", channelId: "food" }, false), "real");

// ── actorClass: five values, in the signature and in the answers ────────────
const seen = new Set();
const classify = (...args) => { const value = actorClass(...args); seen.add(value); return value; };
assert.equal(classify("LiEG6SNtKEZN6eEGeybf0afZnHm1", undefined, "testcall@poplur.com", true), "owner");
assert.equal(classify("eoP2Z0ElxIa0Eua7xpFxNlr6tur1", { username: "mark" }, "mark@apptist.ca", true), "owner");
assert.equal(classify("92eygyJsD3VEXzHXdBLch44AMRl1", { username: "appreview" }, null, true), "review");
// The owner and review sets win before every other rule, known or not.
assert.equal(classify("eoP2Z0ElxIa0Eua7xpFxNlr6tur1", { syntheticBeta: true }, "x@poplur.test", false), "owner");
assert.equal(classify("92eygyJsD3VEXzHXdBLch44AMRl1", undefined, null, false), "review");
// Synthetic by uid, profile or Auth mailbox — with or without a users doc.
assert.equal(classify("sim-daily-2026-09-11-1", undefined, null, true), "synthetic");
assert.equal(classify("RaNd0mUid", undefined, "radius.actor.1-abc@synthetic.poplur.test", true), "synthetic");
assert.equal(classify("n1BkpZPv4HcBKLAG7FXQTzYp7sF2", undefined, "shared.first.user.mtive6bz-abc@synthetic.poplur.test", true), "synthetic");
assert.equal(classify("x", { syntheticBeta: true }, null, true), "synthetic");
assert.equal(classify("sim-food-001", undefined, null, false), "synthetic", "a synthetic uid is synthetic even when unknown");
// A random uid with an unknown mailbox is a person; absent from Auth and
// users it is unknown, never assumed real.
assert.equal(classify("RaNd0mUid", undefined, "someone@example.com", true), "real");
assert.equal(classify("RaNd0mUid", { username: "ada" }, null, true), "real");
assert.equal(classify("RaNd0mUid", undefined, null, false), "unknown");
assert.deepEqual([...seen].sort(), ["owner", "real", "review", "synthetic", "unknown"]);

console.log("synthetic identity: PASS");
