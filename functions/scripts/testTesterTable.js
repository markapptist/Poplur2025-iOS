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

// --- daily series: who joined and what was dropped, per calendar day ---------
// The desk's "new testers per day" must mean people, so simulation accounts and
// their pops are counted apart. Pinned in UTC so the assertions do not move
// with the owner's clock; production buckets in America/Toronto.
const { buildDailySeries, isSyntheticAccount } = require("../lib/testActivity.js");
const DAY = 86_400_000;
const series = buildDailySeries({
  now: NOW,
  timeZone: "UTC",
  days: 3,
  accounts: [
    { uid: "u-real", displayName: "Ada", email: "ada@example.com", createdAtMs: NOW - 1000, lastSignInAtMs: NOW },
    { uid: "u-sim", displayName: null, email: "u-sim@poplur.test", createdAtMs: NOW - DAY, lastSignInAtMs: 0 },
    { uid: "u-old", displayName: null, email: null, createdAtMs: NOW - 30 * DAY, lastSignInAtMs: 0 },
  ],
  users: [
    { uid: "u-real", profile: { username: "ada" } },
    { uid: "u-sim", profile: { username: "u-sim", syntheticBeta: true, syntheticSource: "daily" } },
  ],
  ledger: [
    { id: "p1", userID: "u-real", createdAtMillis: NOW - 2000 },
    // A real owner, but the writer stamped the post as cohort output.
    { id: "p2", userID: "u-real", createdAtMillis: NOW - 3000, syntheticCohort: true },
    { id: "p3", userID: "u-sim", createdAt: ts(NOW - DAY) },
    // Outside the window: neither counted nor an error.
    { id: "p4", userID: "u-real", createdAtMillis: NOW - 10 * DAY },
  ],
});
assert.equal(series.timeZone, "UTC");
assert.equal(series.days.length, 3, "one bucket per requested day");
const [dayBefore, yesterday, today] = series.days;
assert.ok(today.day > yesterday.day && yesterday.day > dayBefore.day, "oldest first");
assert.deepEqual(today, { day: today.day, signups: 1, syntheticSignups: 0, posts: 2, syntheticPosts: 1 });
assert.deepEqual(yesterday, { day: yesterday.day, signups: 1, syntheticSignups: 1, posts: 1, syntheticPosts: 1 });
assert.deepEqual(dayBefore, { day: dayBefore.day, signups: 0, syntheticSignups: 0, posts: 0, syntheticPosts: 0 });
assert.equal(series.postsComplete, true, "a ledger below its cap covers the window");

// A capped ledger whose oldest post is still inside the window cannot vouch
// for the early columns.
const capped = buildDailySeries({
  now: NOW, timeZone: "UTC", days: 3, ledgerLimit: 2, accounts: [], users: [],
  ledger: [
    { id: "p1", userID: "u-real", createdAtMillis: NOW - 1000 },
    { id: "p2", userID: "u-real", createdAtMillis: NOW - 2000 },
  ],
});
assert.equal(capped.postsComplete, false);

// Every spelling of "this is a simulation account".
assert.equal(isSyntheticAccount("sim-food-001", undefined, null), true, "cohort actor id");
assert.equal(isSyntheticAccount("x", { syntheticBeta: true }, null), true);
assert.equal(isSyntheticAccount("synthetic-conquer-orange", undefined, null), true, "colour-lab poster uid");
assert.equal(isSyntheticAccount("sim-daily-2026-09-11-1", undefined, null), true, "sim-daily uid");
assert.equal(isSyntheticAccount("x", { accountType: "synthetic" }, null), true);
assert.equal(isSyntheticAccount("x", undefined, "bot@poplur.test"), true);
assert.equal(isSyntheticAccount("x", { accountType: "business" }, "shop@example.com"), false);
// And the tester rows carry the flag.
const flagged = buildTesterTable({ now: NOW, accounts: [{ uid: "u-sim", displayName: null, email: "u-sim@poplur.test", createdAtMs: NOW, lastSignInAtMs: 0 }], users: [], heartbeats: [], ledger: [] });
assert.equal(flagged[0].synthetic, true);
console.log("daily series: ok");
