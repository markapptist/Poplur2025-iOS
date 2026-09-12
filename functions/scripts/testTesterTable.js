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

// Post counts and the most recent post lead each row (the ledger path: a
// caller that still holds the documents).
assert.equal(online.postCount, 2);
assert.equal(online.postCountSource, "ledger");
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
assert.equal(signupOnly.postCountSource, "ledger");

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

// --- the count() path: the dashboard's source since the read fix ------------
// One count() and one newest-post read per tester replaced the newest-2,000
// posts per call. A row built from them carries exact figures, says where
// they came from, and no summaries: those load on expand (testerPosts).
const { summarizeTesterPost } = require("../lib/testActivity.js");
const counted = buildTesterTable({
  now: NOW,
  accounts: [
    { uid: "u-online", displayName: "Ada", email: null, createdAtMs: NOW - 86_400_000, lastSignInAtMs: NOW - 1000 },
    { uid: "u-signup-only", displayName: null, email: null, createdAtMs: NOW - 60_000, lastSignInAtMs: 0 },
    { uid: "u-ledger-only", displayName: null, email: null, createdAtMs: NOW - 60_000, lastSignInAtMs: 0 },
  ],
  users: [],
  heartbeats: [],
  postStats: [
    // More pops than any ledger slice would carry: the count is exact.
    { uid: "u-online", postCount: 2_345, lastPostedAtMs: NOW - 5000 },
    { uid: "u-signup-only", postCount: 0, lastPostedAtMs: 0 },
    // A uid no other source knows still gets a row from its stats.
    { uid: "u-stats-only", postCount: 1, lastPostedAtMs: NOW - 7000 },
  ],
  // A uid without a stats entry falls back to whatever ledger the caller holds.
  ledger: [
    { id: "post-aaaaaaaaaaaaaaaaaaaa9", userID: "u-ledger-only", createdAtMillis: NOW - 8000, radius: 5000 },
    // Ignored for u-online: its stats entry wins and it carries no summaries.
    { id: "post-aaaaaaaaaaaaaaaaaaaa8", userID: "u-online", createdAtMillis: NOW - 1, radius: 5000 },
  ],
});
const byUid = new Map(counted.map(row => [row.uid, row]));
assert.deepEqual([...byUid.keys()].sort(), ["u-ledger-only", "u-online", "u-signup-only", "u-stats-only"]);
assert.equal(byUid.get("u-online").postCount, 2_345);
assert.equal(byUid.get("u-online").lastPostedAtMs, NOW - 5000);
assert.equal(byUid.get("u-online").postCountSource, "count");
assert.deepEqual(byUid.get("u-online").posts, [], "the count path carries no summaries");
assert.equal(byUid.get("u-signup-only").postCount, 0);
assert.equal(byUid.get("u-signup-only").postCountSource, "count");
assert.equal(byUid.get("u-stats-only").postCount, 1);
assert.equal(byUid.get("u-ledger-only").postCount, 1);
assert.equal(byUid.get("u-ledger-only").postCountSource, "ledger");
assert.equal(byUid.get("u-ledger-only").posts[0].id, "post-aaaaaaaaaaaaaaaaaaaa9");
// Junk from a stats source never becomes a negative or fractional count.
const junk = buildTesterTable({ now: NOW, accounts: [], users: [], heartbeats: [], postStats: [{ uid: "u-junk", postCount: -3, lastPostedAtMs: NaN }] });
assert.equal(junk[0].postCount, 0);
assert.equal(junk[0].lastPostedAtMs, 0);

// testerPosts describes a pop exactly the way the ledger path did.
assert.deepEqual(
  summarizeTesterPost("post-aaaaaaaaaaaaaaaaaaaa1", { createdAtMillis: NOW - 5000, radius: 5000, mediaType: "photo", latitude: 43.6, longitude: -79.4, caption: "  hi   there ", channelId: "food" }),
  { id: "post-aaaaaaaaaaaaaaaaaaaa1", createdAtMs: NOW - 5000, radiusMeters: 5000, mediaType: "photo", mediaCount: 1, caption: "hi there", channelId: "food", coarse: { latitude: 43.6, longitude: -79.4 } },
);
assert.deepEqual(
  summarizeTesterPost("post-aaaaaaaaaaaaaaaaaaaa3", { createdAt: ts(NOW - 100_000), radius: 99_000_000, mediaType: "video", mediaCount: 4 }),
  { id: "post-aaaaaaaaaaaaaaaaaaaa3", createdAtMs: NOW - 100_000, radiusMeters: 40_075_000, mediaType: "video", mediaCount: 4, caption: "", channelId: "", coarse: null },
);
console.log("tester table count path: ok");

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

// --- daily series, count() path: exact per-day totals, no ledger ------------
// The dashboard now counts each strip day twice (every post, and the posts
// stamped syntheticBeta) instead of bucketing a capped ledger slice. The
// counts are exact, so the window is complete whatever any slice cap says;
// a synthetic cell reads null while its composite index is still building.
const { dailySeriesDayKeys, dailySeriesDayBounds } = require("../lib/testActivity.js");
const keys = dailySeriesDayKeys(NOW, "UTC", 3);
assert.deepEqual(keys, series.days.map(day => day.day), "the same keys the series buckets on");
const countedSeries = buildDailySeries({
  now: NOW,
  timeZone: "UTC",
  days: 3,
  accounts: [
    { uid: "u-real", displayName: "Ada", email: "ada@example.com", createdAtMs: NOW - 1000, lastSignInAtMs: NOW },
    { uid: "u-sim", displayName: null, email: "u-sim@poplur.test", createdAtMs: NOW - DAY, lastSignInAtMs: 0 },
  ],
  users: [],
  postCounts: {
    [keys[2]]: { posts: 70, syntheticPosts: 64 },
    [keys[1]]: { posts: 2, syntheticPosts: null },
    // keys[0] absent: nothing counted, synthetic split unknown.
  },
  // A ledger supplied alongside counts is never consulted.
  ledger: [{ id: "p1", userID: "u-real", createdAtMillis: NOW - 2000 }],
  ledgerLimit: 1,
});
const [cDayBefore, cYesterday, cToday] = countedSeries.days;
assert.deepEqual(cToday, { day: keys[2], signups: 1, syntheticSignups: 0, posts: 70, syntheticPosts: 64 });
assert.deepEqual(cYesterday, { day: keys[1], signups: 1, syntheticSignups: 1, posts: 2, syntheticPosts: null });
assert.deepEqual(cDayBefore, { day: keys[0], signups: 0, syntheticSignups: 0, posts: 0, syntheticPosts: null });
assert.equal(countedSeries.postsComplete, true, "count() totals are exact, whatever the ledger cap");

// The bounds a count() query is given cover each calendar day exactly once,
// end to end, in the strip's own time zone — including the 25-hour day when
// Toronto leaves DST (1 Nov 2026) and the 23-hour day when it enters it.
const utcBounds = dailySeriesDayBounds(NOW, "UTC", 3);
assert.deepEqual(utcBounds.map(bound => bound.day), keys);
assert.equal(utcBounds[2].startMs, Date.UTC(2027, 0, 15), "NOW is 2027-01-15T08:00Z");
assert.equal(utcBounds[2].endMs, Date.UTC(2027, 0, 16));
for (let i = 1; i < utcBounds.length; i++) assert.equal(utcBounds[i].startMs, utcBounds[i - 1].endMs, "contiguous days");
const dstEnd = dailySeriesDayBounds(Date.UTC(2026, 10, 2, 12), "America/Toronto", 3);
assert.deepEqual(dstEnd.map(bound => bound.day), ["2026-10-31", "2026-11-01", "2026-11-02"]);
assert.equal(dstEnd[0].startMs, Date.UTC(2026, 9, 31, 4), "EDT midnight");
assert.equal(dstEnd[1].startMs, Date.UTC(2026, 10, 1, 4), "EDT midnight");
assert.equal(dstEnd[2].startMs, Date.UTC(2026, 10, 2, 5), "EST midnight");
assert.equal(dstEnd[2].endMs, Date.UTC(2026, 10, 3, 5));
assert.equal(dstEnd[1].endMs - dstEnd[1].startMs, 25 * 3_600_000, "the fall-back day has 25 hours");
for (let i = 1; i < dstEnd.length; i++) assert.equal(dstEnd[i].startMs, dstEnd[i - 1].endMs);
const dstStart = dailySeriesDayBounds(Date.UTC(2026, 2, 9, 12), "America/Toronto", 2);
assert.deepEqual(dstStart.map(bound => bound.day), ["2026-03-08", "2026-03-09"]);
assert.equal(dstStart[0].endMs - dstStart[0].startMs, 23 * 3_600_000, "the spring-forward day has 23 hours");
// Month and year roll over in the zone, not in UTC: 31 Dec 21:00 Toronto is
// already 1 Jan in UTC, and the strip must still end on 31 Dec.
const yearEnd = dailySeriesDayBounds(Date.UTC(2027, 0, 1, 2), "America/Toronto", 2);
assert.deepEqual(yearEnd.map(bound => bound.day), ["2026-12-30", "2026-12-31"]);
assert.equal(yearEnd[1].endMs, Date.UTC(2027, 0, 1, 5));
console.log("daily series count path: ok");
