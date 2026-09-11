// The tester table joins three sources that each know one thing: Auth knows
// when an account signed up, testActivity knows whether it is here right now,
// and the posts ledger knows what it has made. These pin the joins and the
// presence rule, because a table that quietly drops the signup-with-zero-posts
// row hides exactly the tester the owner most wants to see.
const assert = require("node:assert/strict");
const { buildTesterTable } = require("../lib/testActivity.js");

const NOW = 1_800_000_000_000;
const ts = ms => ({ toMillis: () => ms });

const rows = buildTesterTable({
  now: NOW,
  accounts: [
    { uid: "u-online", displayName: "Ada", email: null, createdAtMs: NOW - 86_400_000, lastSignInAtMs: NOW - 1000 },
    { uid: "u-away", displayName: null, email: "b@x", createdAtMs: NOW - 172_800_000, lastSignInAtMs: 0 },
    { uid: "u-signup-only", displayName: null, email: null, createdAtMs: NOW - 60_000, lastSignInAtMs: 0 },
  ],
  users: [
    { uid: "u-online", profile: { username: "ada", accountType: "user" } },
    { uid: "u-away", profile: { username: "bea", accountType: "business" } },
  ],
  heartbeats: [
    { uid: "u-online", lastActivityAt: ts(NOW - 30_000), screen: "map", platform: "native" },
    { uid: "u-away", lastActivityAt: ts(NOW - 600_000), screen: "feed", platform: "browser" },
  ],
  leases: [
    // u-away has NO fresh heartbeat but holds a live foreground lease: online.
    { uid: "u-away", synthetic: false, activeUntilMs: NOW + 60_000 },
    // A synthetic actor's lease never reads as a human being online.
    { uid: "u-signup-only", synthetic: true, activeUntilMs: NOW + 60_000 },
  ],
  ledger: [
    { id: "post-aaaaaaaaaaaaaaaaaaaa1", userID: "u-online", createdAtMillis: NOW - 5000, radius: 5000, mediaType: "photo", latitude: 43.6, longitude: -79.4 },
    { id: "post-aaaaaaaaaaaaaaaaaaaa2", userID: "u-online", createdAtMillis: NOW - 9000, radius: 7000, mediaType: "video", mediaCount: 1 },
    { id: "post-aaaaaaaaaaaaaaaaaaaa3", userID: "u-away", createdAt: ts(NOW - 100_000), radius: 12_000, mediaCount: 4 },
    { id: "post-orphan", userID: "", createdAtMillis: NOW },
  ],
});

// One row per account, even the one that has never done anything.
assert.deepEqual(rows.map(r => r.uid).sort(), ["u-away", "u-online", "u-signup-only"]);

// u-online is online by heartbeat alone; u-away is online by LEASE despite a
// ten-minute-old heartbeat; the signup-only account's only lease is synthetic.
const online = rows.find(r => r.uid === "u-online");
const away = rows.find(r => r.uid === "u-away");
const signupOnly = rows.find(r => r.uid === "u-signup-only");
assert.equal(online.presence, "online");
assert.equal(online.presenceSource, "heartbeat");
assert.equal(away.presence, "online");
assert.equal(away.presenceSource, "lease");
assert.equal(signupOnly.presence, "unknown");
assert.equal(signupOnly.presenceSource, "none");

// Post counts and the most recent post lead each row.
assert.equal(online.postCount, 2);
assert.equal(online.lastPostedAtMs, NOW - 5000);
assert.equal(online.posts[0].id, "post-aaaaaaaaaaaaaaaaaaaa1");
assert.equal(online.posts[0].coarse.latitude, 43.6);
assert.equal(online.posts[1].mediaType, "video");
assert.equal(away.postCount, 1);
assert.equal(away.posts[0].mediaCount, 4);
// createdAt Timestamp is an acceptable fallback when createdAtMillis is absent.
assert.equal(away.lastPostedAtMs, NOW - 100_000);
assert.equal(signupOnly.postCount, 0);
assert.equal(signupOnly.lastPostedAtMs, 0);

// Auth is the signup source; the profile supplies the username.
assert.equal(online.signedUpAtMs, NOW - 86_400_000);
assert.equal(online.username, "ada");
assert.equal(away.accountType, "business");
assert.equal(signupOnly.username, "");

// The orphan ledger row never becomes a tester.
assert.ok(!rows.some(r => r.uid === ""));

// Ordering: online first, unknown last.
assert.deepEqual(rows.map(r => r.presence), ["online", "online", "unknown"]);

console.log("tester table: ok");
