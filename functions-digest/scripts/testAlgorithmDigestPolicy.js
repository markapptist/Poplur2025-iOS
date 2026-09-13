"use strict";

/**
 * The algorithm desk digest, folded against an in-memory reader: classes,
 * attribution, decay-mode inference, pool pro-rating, gating, cursors, the
 * create guard, the sweep, the refresh, the curve, bounds and versioning.
 * Firestore and Auth live in algorithmDigest.ts and are exercised by a run.
 *
 *   npm run test:algorithm-digest
 */
const assert = require("node:assert/strict");
const path = require("node:path");

const digestModulePath = process.argv[2] || "../lib/algorithmDigestPolicy.js";
const digest = require(digestModulePath);
const libDir = path.dirname(require.resolve(digestModulePath));
const policy = require(path.join(libDir, "shared", "postEngagementPolicy.js"));

const MIN = 60_000, H = 3_600_000, D = 86_400_000;
const MAX = policy.MAX_POST_RADIUS_METERS;
const T0 = Date.UTC(2026, 8, 11, 17, 0, 0); // 2026-09-11T17:00Z = 13:00 Toronto
const TZ = "America/Toronto";
const RATE = policy.RADIUS_DECAY_PER_DAY;
const trialAt = (from, multiplier = 5, boosted = false) => ({ multiplier, effectiveAtMillis: from, ...(boosted ? { boostedEffectiveAtMillis: from } : {}) });
const day = (ms) => digest.dayKey(ms, TZ);
const approx = (actual, expected, tolerance, message) => assert.ok(Math.abs(actual - expected) <= tolerance, `${message}: ${actual} ≠ ${expected} ± ${tolerance}`);

// ── Actors ───────────────────────────────────────────────────────────────
const MARK = "eoP2Z0ElxIa0Eua7xpFxNlr6tur1";
const TESTCALL = "LiEG6SNtKEZN6eEGeybf0afZnHm1";
const REVIEW = "92eygyJsD3VEXzHXdBLch44AMRl1";
const TESTER_A = "TesterAaaaaaaaaaaaaaaaaaaaaA";
const TESTER_B = "TesterBbbbbbbbbbbbbbbbbbbbbB";
const TESTER_C = "TesterCccccccccccccccccccccC";
const QA = "QaRadiusActor1xxxxxxxxxxxxxx";
const LAB_OWNER = "n1BkpZPv4HcBKLAG7FXQTzYp7sF2";
const SIM = "sim-food-001";
const POPLURTEST = "PoplurTestUid000000000000000";
const STRANGER = "StrangerWithUsersDocOnly0000";
const PROFILE_SYN = "ProfileFlaggedSyntheticUid00";
const GHOST = "GhostNowhere0000000000000000";
const AUTH = {
  [MARK]: "mark@apptist.ca", [TESTCALL]: "testcall@poplur.com", [REVIEW]: "appreview@poplur.com",
  [TESTER_A]: "a@gmail.com", [TESTER_B]: "b@gmail.com", [TESTER_C]: "c@gmail.com",
  [QA]: "radius.actor.1-abc@synthetic.poplur.test", [LAB_OWNER]: "shared.first.user.mtive6bz-abc@synthetic.poplur.test",
  [SIM]: "sim-food-001@poplur.test", [POPLURTEST]: "poplurtest@poplur.com",
};
const USERS = new Map([[STRANGER, { username: "stranger" }], [PROFILE_SYN, { syntheticBeta: true }]]);

// ── Classes (§1.1) ───────────────────────────────────────────────────────
assert.equal(digest.postClass("post-x", { officialContent: true, syntheticBeta: true }, true), "official", "official wins whatever else the post carries");
assert.equal(digest.postClass("post-radius-lab-1", { syntheticBeta: true }, false), "lab", "lab before synthetic");
assert.equal(digest.postClass("post-x", { syntheticSource: "radius-lab-server" }, false), "lab");
assert.equal(digest.postClass("post-x", { syntheticBeta: true }, false), "synthetic");
assert.equal(digest.postClass("post-x", { syntheticSource: "scheduled-test-simulation" }, false), "synthetic");
assert.equal(digest.postClass("post-x", { source: "synthetic-browser" }, false), "synthetic");
assert.equal(digest.postClass("post-sim-2026-09-11T10-sim-food-001-0", {}, false), "synthetic");
assert.equal(digest.postClass("post-x", {}, true), "synthetic", "a synthetic owner makes the post synthetic");
assert.equal(digest.postClass("post-x", {}, false), "real");
assert.equal(digest.actorClass(MARK, undefined, AUTH[MARK], true), "owner");
assert.equal(digest.actorClass(TESTCALL, undefined, AUTH[TESTCALL], true), "owner");
assert.equal(digest.actorClass(REVIEW, undefined, AUTH[REVIEW], true), "review", "the App Review demo account is review, never real");
assert.equal(digest.actorClass("RandomUid00000000000000000000", undefined, "someone@example.com", true), "real");
assert.equal(digest.actorClass(GHOST, undefined, null, false), "unknown", "absent from Auth and users → unknown");
assert.equal(digest.actorClass(SIM, undefined, AUTH[SIM], true), "synthetic");
assert.equal(digest.actorClass("synthetic-conquer-3", undefined, null, false), "synthetic");
assert.equal(digest.actorClass("u", { syntheticBeta: true }, null, true), "synthetic");
assert.equal(digest.actorClass("u", { syntheticCohort: true }, null, true), "synthetic");
assert.equal(digest.actorClass("u", { syntheticSource: "x" }, null, true), "synthetic");
assert.equal(digest.actorClass("u", { accountType: "Synthetic Business" }, null, true), "synthetic");
assert.equal(digest.actorClass("u", undefined, "sim-x@poplur.test", true), "synthetic");
assert.equal(digest.actorClass(QA, undefined, AUTH[QA], true), "synthetic", "radius.actor.1-abc@synthetic.poplur.test from the Auth page, no users doc");
assert.equal(digest.actorClass(LAB_OWNER, undefined, AUTH[LAB_OWNER], true), "synthetic", "the lab pin's owner classifies by its Auth mailbox");
assert.equal(digest.actorClass(LAB_OWNER, undefined, null, true), "real", "…and would read as real without it — why a failed Auth page aborts");

// ── Knobs and the curve (M7) ─────────────────────────────────────────────
assert.deepEqual(Object.keys(digest.KNOBS).sort(), ["boostDefaultHours", "boostDefaultMeters", "commentMeters", "decayFloorMeters", "decayHalfLifeDays",
  "decayPerDay", "dislikeMeters", "firstViewMeters", "likeMeters", "maxRadiusMeters", "repeatViewBaseMeters", "repeatViewLifetimeMeters", "repeatViewMinMs",
  "seedMeters", "syntheticStressHalfLifeHours"]);
assert.equal(digest.KNOBS.seedMeters, 5_000);
assert.equal(digest.RATE_INFORMATIVE_MIN_ORGANIC, 468);
const curve1k = digest.decayCurve(1_000);
const curve10k = digest.decayCurve(10_000);
const curve100k = digest.decayCurve(100_000);
// The shipped Math.floor rounds every pass's loss up, so the stepped curve
// runs ahead of the closed form: ≈ 30 / 71 / 116 d at 60-minute passes.
approx(curve1k.days, 30, 4, "1 km of earned reach is gone in ≈ a month");
approx(curve10k.days, 72, 8, "10 km in ≈ 2.5 months");
approx(curve100k.days, 116, 10, "100 km in ≈ 4 months");
assert.ok(curve1k.days < curve10k.days && curve10k.days < curve100k.days);
approx(digest.decayCurve(468).days, 19, 0.5, "linear tail: 468 → 10 m at 1 m/pass ≈ 19 d");
assert.equal(digest.decayCurve(468).passes, 459);
assert.ok(digest.decayCurve(1_000, { passMinutes: 65 }).days > curve1k.days, "65-minute passes take longer");
const trialCurve = digest.decayCurve(1_000, { trial: { multiplier: 5 } });
approx(trialCurve.days, 12, 2, "×5: 1 km in ≈ 12 d");
const seedCurve = digest.decayCurve(0, { seedMeters: 5_000, trial: { multiplier: 5 } });
approx(seedCurve.seedDays, 18, 2, "×5 steps the seed too: 5 km → 0 in ≈ 18 d");
assert.equal(digest.decayCurve(0, { seedMeters: 5_000 }).seedDays, null, "outside a trial the seed never moves");
assert.equal(digest.KNOBS.decayHalfLifeDays, 13.51, "half-life is labelled, far above the floor only");

// ── Toronto day keys across the 1 Nov 2026 DST end ───────────────────────
assert.equal(day(Date.UTC(2026, 10, 1, 5, 30)), "2026-11-01", "01:30 EDT");
assert.equal(day(Date.UTC(2026, 10, 1, 6, 30)), "2026-11-01", "01:30 EST, the repeated hour");
assert.equal(day(Date.UTC(2026, 10, 2, 4, 59)), "2026-11-01", "23:59 EST on the 25-hour day");
assert.equal(day(Date.UTC(2026, 10, 2, 5, 0)), "2026-11-02");
assert.deepEqual(digest.dayKeysEndingAt(Date.UTC(2026, 10, 3, 12), 5, TZ), ["2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03"]);
assert.equal(digest.dayStartMillis("2026-11-01", TZ), Date.UTC(2026, 10, 1, 4), "EDT midnight");
assert.equal(digest.dayStartMillis("2026-11-02", TZ), Date.UTC(2026, 10, 2, 5), "EST midnight, 25 h later");
assert.equal(day(T0), "2026-09-11");

// ── Fixture plumbing ─────────────────────────────────────────────────────
const ts = (ms, extraNanos = 0) => ({ seconds: Math.floor(ms / 1000), nanoseconds: (ms % 1000) * 1_000_000 + extraNanos });
const tupleMillis = (t) => t.seconds * 1000 + Math.floor(t.nanoseconds / 1_000_000);
function postDoc(owner, options = {}) {
  const seed = options.seed ?? 5_000, organic = options.organic ?? 0, boost = options.boost ?? 0;
  const radius = Math.min(MAX, seed + organic + boost);
  return { userID: owner, channelId: options.channelId ?? "live", latitude: options.lat ?? 43.65, longitude: options.lng ?? -79.38,
    radiusMeters: radius, radius, seedRadiusMeters: seed, organicRadiusMeters: organic, boostedRadiusMeters: boost,
    viewCount: options.viewCount ?? 0, status: "published", audience: "public", ...(options.extra ?? {}) };
}
/** A ledger with running state, so every entry's delta is what a writer would have stored. */
function ledger() {
  const rows = [];
  let s = { radius: 0, organic: 0, seed: 0, boost: 0 };
  const total = (n) => Math.min(MAX, n.organic + n.seed + n.boost);
  const push = (id, at, cause, writer, next, extra = {}) => {
    const radius = next.radius ?? total(next);
    rows.push({ id, data: { atMillis: at, cause, writer, radiusMeters: radius, organicRadiusMeters: next.organic, seedRadiusMeters: next.seed,
      boostedRadiusMeters: next.boost, delta: rows.length ? radius - s.radius : 0, organicDelta: rows.length ? next.organic - s.organic : 0, ...extra } });
    s = { organic: next.organic, seed: next.seed, boost: next.boost, radius };
  };
  const api = {
    rows, state: () => ({ ...s }),
    create(at, seed, o = {}) { push("create", at, "create", o.writer ?? "radiusHistoryOnPostCreated", { organic: o.organic ?? 0, seed, boost: o.boost ?? 0 }); return api; },
    engage(at, kind, meters, eid, o = {}) { push(`eng_${eid}`, at, "engagement", o.writer ?? "recordPostEngagement", { ...s, organic: Math.max(0, s.organic + meters), radius: undefined }, { kind, ...(o.noId ? {} : { engagementId: eid }) }); return api; },
    resync(at, kind, eid, radiusDelta) { push(`eng_${eid}`, at, "engagement", "recordPostEngagement", { ...s, radius: s.radius + radiusDelta }, { kind, engagementId: eid }); return api; },
    decay(at, from, trial) {
      const next = policy.calculateRadiusDecay({ organicRadiusMeters: s.organic, seedRadiusMeters: s.seed, boostedRadiusMeters: s.boost, radiusMeters: s.radius, decayedAt: from }, at, undefined, trial);
      assert.ok(next, `fixture decay at ${at} changed nothing`);
      push(`decay_${at}`, at, "decay", "radiusDecay", { organic: next.organicRadiusMeters, seed: next.seedRadiusMeters ?? s.seed, boost: next.boostedRadiusMeters ?? s.boost, radius: next.radiusMeters });
      return api;
    },
    stress(at, from) {
      const factor = 2 ** (-(at - from) / (4 * H));
      const shrink = (m) => { const n = Math.floor(m * factor); return n < 10 ? 0 : n; };
      push(`decay_${at}`, at, "decay", "radiusDecay", { organic: shrink(s.organic), seed: shrink(s.seed), boost: s.boost });
      return api;
    },
    decayTo(at, organic, writer = "radiusDecay") { push(`decay_${at}`, at, "decay", writer, { ...s, organic, radius: undefined }); return api; },
    boost(at, meters, expiresAt) { push(`boost_${at}`, at, "boost", "radiusBoost", { ...s, boost: s.boost + meters, radius: undefined }, { boostExpiresAtMillis: expiresAt }); return api; },
    raw(id, at, cause, writer, organicDelta) { push(id, at, cause, writer, { ...s, organic: s.organic + organicDelta, radius: undefined }); return api; },
  };
  return api;
}
const predict = (organic, elapsed, m) => digest.predictDecayed(organic, elapsed, m, T0 - 30 * D);

class FakeReader {
  constructor(world, options = {}) { this.world = world; this.failAuth = options.failAuth === true; this.calls = { auth: 0, sweep: [], ledger: [], create: [], engagement: 0, user: 0, post: 0 }; }
  async authPage() { this.calls.auth += 1; if (this.failAuth) throw new Error("auth down"); return { ...this.world.auth }; }
  async sweepPage(query) {
    this.calls.sweep.push({ ...query });
    let rows = [...this.world.posts.entries()].map(([id, post]) => ({ id, path: `posts/${id}`, data: post.data, createdAt: post.createdAt }))
      .filter((row) => tupleMillis(row.createdAt) <= query.toMillis && (query.fromMillis == null || tupleMillis(row.createdAt) >= query.fromMillis));
    const compare = (a, b) => a.createdAt.seconds - b.createdAt.seconds || a.createdAt.nanoseconds - b.createdAt.nanoseconds || (a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
    rows.sort(compare);
    if (query.after) rows = rows.filter((row) => compare(row, { createdAt: query.after, path: query.after.path }) > 0);
    return rows.slice(0, query.limit);
  }
  async ledgerPage(query) {
    this.calls.ledger.push({ ...query });
    let rows = [...(this.world.ledgers.get(query.postId) ?? [])].filter((row) => row.data.atMillis <= query.horizonMillis);
    rows.sort((a, b) => a.data.atMillis - b.data.atMillis || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
    if (query.after) rows = rows.filter((row) => row.data.atMillis > query.after.atMillis || (row.data.atMillis === query.after.atMillis && row.id > query.after.id));
    return rows.slice(0, query.limit);
  }
  async createEntry(postId) { this.calls.create.push(postId); return (this.world.ledgers.get(postId) ?? []).find((row) => row.id === "create") ?? null; }
  async engagement(postId, id) { this.calls.engagement += 1; return this.world.engagements.get(`${postId}/${id}`) ?? null; }
  async user(uid) { this.calls.user += 1; return this.world.users.get(uid) ?? null; }
  async post(postId) { this.calls.post += 1; return this.world.posts.get(postId)?.data ?? null; }
}
const switchesOn = { simulationEnabled: false, runnerEnabled: true, dailySimulationEnabled: true, simulationOwnerUid: MARK, dueDecayEnabled: true, sampledAtMillis: T0,
  decayTrial: { enabled: true, multiplier: 5, scope: "all-users", effectiveAtMillis: 1788826046064, boostedEffectiveAtMillis: 1788845178241 } };
const switchesOff = { ...switchesOn, decayTrial: { ...switchesOn.decayTrial, enabled: false } };
const config = (overrides = {}) => digest.digestConfig(overrides);
async function run(world, state, now, options = {}) {
  const reader = new FakeReader(world, options);
  const outcome = await digest.runDigestFold({ state, config: options.config ?? config(), switches: options.switches ?? switchesOn, reader,
    runStartMillis: now, runId: options.runId ?? `run-${now}`, timeZone: TZ });
  return { outcome, reader };
}

// ── The world (§6 fixtures) ──────────────────────────────────────────────
function buildWorld() {
  const posts = new Map(), ledgers = new Map(), engagements = new Map();
  const add = (id, owner, createdAt, docOptions, entries) => {
    posts.set(id, { data: postDoc(owner, docOptions), createdAt: ts(createdAt) });
    ledgers.set(id, entries);
  };
  // The engagement document id is the entry's engagementId; the entry's own id is `eng_` + that.
  const joined = (postId, eid, actorUid, surface) => engagements.set(`${postId}/${eid.replace(/^eng_/, "")}`, { actorUid, kind: "x", ...(surface ? { surface } : {}) });

  // P1 — tester A's real post: every engagement shape, every decay shape.
  const C1 = T0 - 5 * D, D0 = C1 + 3 * H;
  const p1 = ledger().create(C1, 5_000)
    .engage(C1 + 10 * MIN, "like", 1_000, "m1").engage(C1 + 20 * MIN, "view", 1_000, "r1")
    .engage(C1 + 30 * MIN, "view", 1_000, "b1").engage(C1 + 40 * MIN, "like", 1_000, "b2").engage(C1 + 50 * MIN, "comment", 2_000, "b3")
    .engage(C1 + 60 * MIN, "view", 1_000, "q1").engage(C1 + 70 * MIN, "view", 1_000, "gone").engage(C1 + 80 * MIN, "view", 1_000, "s1")
    .engage(C1 + 90 * MIN, "like", 1_000, "g1").engage(C1 + 100 * MIN, "view", 500, "b4").engage(C1 + 110 * MIN, "dislike", -1_000, "b5")
    .resync(C1 + 120 * MIN, "view", "b6", -1_200)
    .engage(C1 + 121 * MIN, "view", 250, "b7").engage(C1 + 122 * MIN, "view", 125, "b8")
    .boost(C1 + 130 * MIN, 1_000, C1 + 130 * MIN + 24 * H)
    .raw(`lab_${C1 + 140 * MIN}`, C1 + 140 * MIN, "growth", "radius-lab", 300)
    .raw(`lab_${C1 + 150 * MIN}`, C1 + 150 * MIN, "decay", "radius-lab", -100);
  const o0 = p1.state().organic;
  p1.decayTo(D0, predict(o0, H, 1));                         // no previous decay entry → undetermined
  p1.decayTo(D0 + H, predict(p1.state().organic, H, 1));     // ×1 rate → normal
  p1.decayTo(D0 + 2 * H, predict(p1.state().organic, H, 5)); // ×5 rate, seed untouched → trial ×5 by rate
  p1.stress(D0 + 3 * H, D0 + 2 * H);                         // 16 %/h → stress
  p1.decay(D0 + 4 * H, D0 + 3 * H, trialAt(D0 + 3 * H));     // seed drop → trial
  p1.decay(D0 + 5 * H, D0 + 4 * H, trialAt(D0 + 4 * H, 5, true)); // boost drop → trial
  add("post-tester-a-1", TESTER_A, C1, { channelId: "live", organic: p1.state().organic, boost: p1.state().boost, seed: p1.state().seed, viewCount: 40 }, p1.rows);
  joined("post-tester-a-1", "eng_m1", MARK, "map"); joined("post-tester-a-1", "eng_r1", REVIEW, "feed");
  joined("post-tester-a-1", "eng_b1", TESTER_B, "feed"); joined("post-tester-a-1", "eng_b2", TESTER_B, "map"); joined("post-tester-a-1", "eng_b3", TESTER_B, "profile");
  joined("post-tester-a-1", "eng_q1", QA, "profile"); joined("post-tester-a-1", "eng_s1", STRANGER, null); joined("post-tester-a-1", "eng_g1", GHOST, "feed");
  joined("post-tester-a-1", "eng_b4", TESTER_B, "feed"); joined("post-tester-a-1", "eng_b5", TESTER_B, "map"); joined("post-tester-a-1", "eng_b6", TESTER_B, "feed");
  joined("post-tester-a-1", "eng_b7", TESTER_B, "feed"); joined("post-tester-a-1", "eng_b8", TESTER_B, "feed");

  // P2 — tester A, channel food: low-organic decays, no create yet (the trigger is late).
  const C2 = T0 - 3 * D;
  const p2rows = [
    { id: `decay_${C2 + H}`, data: { atMillis: C2 + H, cause: "decay", writer: "radiusDecay", radiusMeters: 5_300, organicRadiusMeters: 300, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: -1, organicDelta: -1 } },
    { id: `decay_${C2 + 2 * H}`, data: { atMillis: C2 + 2 * H, cause: "decay", writer: "radiusDecay", radiusMeters: 5_299, organicRadiusMeters: 299, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: -1, organicDelta: -1 } },
  ];
  add("post-tester-a-2", TESTER_A, C2, { channelId: "food", organic: 299, extra: { radiusDecayAnchorMillis: C2 + 2 * H, radiusDecayOrganicPerDay: 1 - 0.95 ** 5, radiusDecaySeedPerDay: 1 - 0.95 ** 5, radiusDecayBoostPerDay: 0 } }, p2rows);

  // P3 — mark's own real post (owner column): old real like, a sim view, a backfill ladder.
  const C3 = T0 - 12 * D;
  const p3 = ledger().create(C3, 5_000).engage(C3 + H, "like", 1_000, "oldb");
  p3.decayTo(C3 + 2 * H, predict(p3.state().organic, H, 1));
  p3.engage(T0 - D, "view", 1_000, "sim1");
  for (let i = 0; i < 58; i++) p3.engage(T0 - D + i * MIN, "view", 500, `bf${i}`, { writer: "backfillRadiusHistory", noId: true });
  add("post-owner-1", MARK, C3, { channelId: "live", organic: p3.state().organic, viewCount: 90 }, p3.rows);
  joined("post-owner-1", "eng_oldb", TESTER_B, "feed"); joined("post-owner-1", "eng_sim1", SIM, "map");

  // P4 — sim-daily post, P7 — lab post: never registered, ledgers never opened.
  posts.set("post-sim-2026-09-11T10-sim-food-001-0", { data: postDoc(SIM, { extra: { syntheticBeta: true, syntheticCohort: true, syntheticSource: "scheduled-test-simulation" } }), createdAt: ts(T0 - 7 * H) });
  ledgers.set("post-sim-2026-09-11T10-sim-food-001-0", ledger().create(T0 - 7 * H, 5_000).rows);
  posts.set("post-radius-lab-1", { data: postDoc(LAB_OWNER, { extra: { syntheticBeta: true, syntheticSource: "radius-lab-server" } }), createdAt: ts(T0 - 2 * D) });
  ledgers.set("post-radius-lab-1", ledger().create(T0 - 2 * D, 5_000).raw("lab_1", T0 - 2 * D + MIN, "growth", "radius-lab", 400).raw("lab_2", T0 - 2 * D + 2 * MIN, "decay", "radius-lab", -50).rows);

  // P5 — official anchor stored as boost (production's form), P6 — stored as organic (the re-seed form).
  const C5 = T0 - 8 * D;
  const p5 = ledger().create(C5, 0, { boost: MAX });
  p5.decay(T0 - 2 * D, T0 - 2 * D - H, trialAt(T0 - 2 * D - H, 5, true)).decay(T0 - 2 * D + H, T0 - 2 * D, trialAt(T0 - 2 * D, 5, true));
  add("post-official-cartoon-drive-ad", POPLURTEST, C5, { seed: 0, boost: p5.state().boost, extra: { officialContent: true } }, p5.rows);
  const p6 = ledger().create(C5, 0, { organic: MAX });
  p6.decay(T0 - 2 * D, T0 - 2 * D - H, trialAt(T0 - 2 * D - H));
  add("post-official-organic-1", POPLURTEST, C5, { seed: 0, organic: p6.state().organic, extra: { officialContent: true } }, p6.rows);

  // P8 — tester B's seed-only drop (created, never engaged).
  add("post-tester-b-seedonly", TESTER_B, T0 - 2 * D, { channelId: "live", lat: 43.66, lng: -79.39 }, ledger().create(T0 - 2 * D, 5_000).rows);
  // P11 — tester A, channel music: vanishes before the second run.
  add("post-tester-a-vanishes", TESTER_A, T0 - D, { channelId: "music", organic: 1_000 }, ledger().create(T0 - D, 5_000).engage(T0 - D + H, "like", 1_000, "c1").rows);
  joined("post-tester-a-vanishes", "eng_c1", TESTER_C, "feed");
  // P12 — tester C: first seen through a decay entry; its create lands later with a clock AHEAD of the cursor.
  add("post-tester-c-clockahead", TESTER_C, T0 - 3 * D, { organic: 997, channelId: "sports" }, [
    { id: `decay_${T0 - 3 * H}`, data: { atMillis: T0 - 3 * H, cause: "decay", writer: "radiusDecay", radiusMeters: 5_997, organicRadiusMeters: 997, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: -3, organicDelta: -3 } },
  ]);
  // P10 — tester C: no create, ever (an old "Beta Runner" post).
  add("post-tester-c-nocreate", TESTER_C, T0 - 6 * D, { organic: 997, channelId: "news" }, [
    { id: `decay_${T0 - 4 * H}`, data: { atMillis: T0 - 4 * H, cause: "decay", writer: "radiusDecay", radiusMeters: 5_997, organicRadiusMeters: 997, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: -3, organicDelta: -3 } },
  ]);
  return { auth: { ...AUTH }, posts, ledgers, engagements, users: new Map(USERS) };
}

// ── Run 1: cold start ────────────────────────────────────────────────────
(async () => {
  const world = buildWorld();
  const { outcome: run1, reader: reader1 } = await run(world, digest.initialState(), T0);
  assert.equal(run1.status, "ok");
  const published1 = run1.published;
  const payload1 = run1.state.payload;

  // Sweep: unbounded on the first run, no startAfter on its first page, exact tuple cursor.
  assert.equal(reader1.calls.sweep[0].after, null, "the first page carries no startAfter");
  assert.equal(reader1.calls.sweep[0].fromMillis, null, "cold start sweeps with no lower bound");
  assert.equal(run1.state.sweep.coldStartDone, true);
  const registered = Object.keys(payload1.postMeta).sort();
  assert.deepEqual(registered, ["post-official-cartoon-drive-ad", "post-official-organic-1", "post-owner-1", "post-tester-a-1", "post-tester-a-2",
    "post-tester-a-vanishes", "post-tester-b-seedonly", "post-tester-c-clockahead", "post-tester-c-nocreate"]);
  assert.ok(!payload1.postMeta["post-sim-2026-09-11T10-sim-food-001-0"], "a post-sim-* post is never registered");
  assert.ok(!payload1.postMeta["post-radius-lab-1"], "a lab post is never registered");
  assert.ok(reader1.calls.ledger.every((q) => q.postId !== "post-radius-lab-1" && !q.postId.startsWith("post-sim-")), "synthetic and lab ledgers are never opened");
  assert.deepEqual(published1.coverage.registeredPosts, { real: 6, owner: 1, review: 0, official: 2 });
  const newest = [...world.posts.entries()].sort((a, b) => tupleMillis(a[1].createdAt) - tupleMillis(b[1].createdAt)).pop();
  assert.deepEqual(run1.state.sweep.cursor, { ...newest[1].createdAt, path: `posts/${newest[0]}` }, "the cursor is the exact {seconds, nanoseconds} of the last document");
  assert.equal(published1.windows.d30.postsCreated.synthetic, 1);
  assert.equal(published1.windows.d30.postsCreated.lab, 1);
  assert.equal(published1.windows.d30.postsCreated.official, 2);
  assert.equal(published1.windows.d30.postsCreated.owner, 1);
  assert.equal(published1.windows.d30.postsCreated.real, 6);
  assert.equal(published1.windows.d7.postsCreated.real, 6, "every tester drop is inside 7 d (P10 at 6 d); mark's (12 d) and the officials (8 d) are not");
  assert.equal(published1.windows.d7.postsCreated.owner, 0);
  assert.equal(payload1.postMeta["post-owner-1"].ownerClass, "o");
  assert.equal(payload1.postMeta["post-tester-a-1"].ownerClass, "r");

  // Per-post pages: first page without startAfter, cursor at the last (atMillis, id).
  const p1Pages = reader1.calls.ledger.filter((q) => q.postId === "post-tester-a-1");
  assert.equal(p1Pages.length, 1);
  assert.equal(p1Pages[0].after, null);
  assert.equal(p1Pages[0].horizonMillis, T0 - 30 * MIN);
  const p1Last = world.ledgers.get("post-tester-a-1").at(-1);
  assert.deepEqual(payload1.postMeta["post-tester-a-1"].cursor, { atMillis: p1Last.data.atMillis, id: p1Last.id });
  assert.equal(payload1.postMeta["post-tester-b-seedonly"].hasCreate, true, "a seed-only tester post is found by the sweep and its create folded");
  assert.equal(payload1.postMeta["post-tester-b-seedonly"].createFetch, null);
  assert.equal(payload1.postMeta["post-tester-a-2"].hasCreate, false);
  assert.deepEqual(payload1.postMeta["post-tester-a-2"].createFetch, { requestedRun: 1, lastRun: null }, "a post first seen through a decay entry requests the fetch");
  assert.equal(reader1.calls.create.length, 0, "the fetch waits for the next run");
  assert.equal(published1.coverage.complete, true);
  assert.equal(published1.coverage.capped, false);
  assert.equal(published1.cost.authPages, 1);
  assert.equal(published1.cost.postsPolled, 9);
  assert.equal(published1.cost.sweepReads, 11);
  const pageReads = registered.reduce((n, postId) => n + Math.max(1, world.ledgers.get(postId).length), 0);
  assert.equal(published1.cost.engagementJoins, 17, "one join per engagement entry carrying an engagementId on a registered post");
  assert.equal(published1.cost.userLookups, 2, "one users/{uid} read each for the stranger and the ghost");
  assert.equal(published1.cost.reads, 8 + 11 + pageReads + 17 + 2, "reads = 8 fixed + sweep + max(1, entries) per polled post + joins + lookups");
  assert.equal(published1.cost.entriesProcessed, pageReads);
  assert.equal(published1.cost.refreshReads, 0, "registration already read every post document today");
  assert.equal(payload1.actorClassByUid[STRANGER], "r");
  assert.equal(payload1.actorClassByUid[GHOST], "u");
  assert.equal(published1.cost.capInForce, 6000);
  assert.equal(published1.cost.writes, 3 + 7 + 1, "state + published + lease, then the first-deploy backfill: 7 report days and the index (§2.7)");
  assert.equal(run1.reports.length, 7); assert.ok(run1.reportIndex);
  assert.equal(run1.state.readsToday, published1.cost.reads);
  assert.equal(run1.state.digestVersion, 1);
  assert.equal(run1.state.refresh.lastRefreshDay, "2026-09-11");

  // M1 by kind and actor, 7 days.
  const g7 = published1.windows.d7.realPostGain;
  assert.deepEqual(g7.real, { view: 2_875, like: 2_000, comment: 2_000, dislike: -1_000, total: 5_875, n: 9, firstViews: 2, repeatViews: 3, repeatMeters: 875, clamped: 0, resync: 1, clampedDislikes: 0, clampedDislikeMeters: 0 });
  assert.deepEqual(g7.owner, { view: 0, like: 1_000, comment: 0, dislike: 0, total: 1_000, n: 1, firstViews: 0, repeatViews: 0, repeatMeters: 0, clamped: 0, resync: 0, clampedDislikes: 0, clampedDislikeMeters: 0 }, "mark engaging a stranger's post lands in owner, never real");
  assert.deepEqual(g7.review, { view: 1_000, like: 0, comment: 0, dislike: 0, total: 1_000, n: 1, firstViews: 1, repeatViews: 0, repeatMeters: 0, clamped: 0, resync: 0, clampedDislikes: 0, clampedDislikeMeters: 0 }, "a review tap never enters a REAL figure");
  assert.equal(g7.synthetic.total, 2_000); assert.equal(g7.synthetic.n, 2);
  assert.equal(g7.unknown.total, 2_000 + 58 * 500); assert.equal(g7.unknown.n, 60);
  assert.equal(published1.windows.d7.distinctRealViewers, 2);
  assert.equal(published1.windows.d7.distinctRealLikers, 2);
  assert.equal(published1.windows.d7.distinctRealCommenters, 1);
  assert.deepEqual(published1.windows.d7.surfaces, { feed: 8, map: 4, profile: 2, unknown: 1 }, "surface labels counted off the engagement documents");
  assert.deepEqual(published1.windows.d7.realSurfaces, { feed: 6, map: 2, profile: 1, unknown: 1 });
  assert.deepEqual(published1.windows.d7.unknownActorEntries, { real: 60, official: 0 });
  assert.equal(published1.windows.d30.realPostGain.real.like, 3_000, "the 11-day-old like on mark's post is inside 30 d");
  assert.equal(published1.windows.d7.boosts.n, 1); assert.equal(published1.windows.d7.boosts.meters, 1_000);

  // Fold additions (reports design §2.3): real-actor kind counts on the fold, per-uid entries in the STATE day cell only,
  // distinct counts on the published day, the kind-split stamp at 0 on a cold start.
  assert.deepEqual(payload1.folds["post-tester-a-1"].rk, { v: 5, l: 1, c: 1, d: 1 }, "B's four views + the stranger's, B's like, comment and dislike; the resync, the owner, review, sim and ghost never count");
  const c1Cell = payload1.days[day(T0 - 5 * D)];
  assert.deepEqual(c1Cell.realActorEntries, { [TESTER_B]: { v: 4, l: 1, c: 1, d: 1 }, [STRANGER]: { v: 1, l: 0, c: 0, d: 0 } }, "per uid per kind, state only");
  const c1Row = published1.days.find((row) => row.day === day(T0 - 5 * D));
  assert.equal(c1Row.realActorEntries, undefined, "publishedDay strips the uid map");
  assert.deepEqual(c1Row.people, { actors: 2, viewers: 2, likers: 1, commenters: 1, maxShare: 0.875 }, "…and publishes counts: B's 7 of the day's 8 real entries (the resync is in neither)");
  assert.ok(!JSON.stringify(published1).includes(TESTER_B) && !JSON.stringify(published1).includes(STRANGER), "no uid reaches the published digest");
  assert.equal(payload1.coverage.kindSplitSinceMillis, 0, "introduced on an empty payload: every entry passed through the new code");
  assert.deepEqual(published1.windows.d7.realPostGain.real.clampedDislikes, 0);
  assert.equal(typeof published1.intercept.opportunity.nearMissPairs, "number");
  assert.equal(run1.state.runsToday, 1); assert.deepEqual(run1.state.readsPrev, { day: null, reads: 0, runs: 0 });
  assert.equal(run1.state.report.lastReportedDay, "2026-09-05", "the cold start backfilled 7 days (30 Aug … 5 Sep) of the 14 the state holds cells for");

  // Resync counted, never in n, first/repeat or M16; clamped and repeat ladder in M16; backfill excluded.
  assert.deepEqual(published1.coverage.resync, { view: 1 });
  assert.equal(published1.observed.resync, 1);
  assert.deepEqual(published1.observed.grants.repeat.byMeters, { "500": 1, "250": 1, "125": 1 }, "a 500×58 backfill ladder leaves seen at 500/250/125");
  assert.equal(published1.observed.grants.view.n, 6, "first views seen in 7 d across every actor class (P3's sim view included)");
  assert.equal(published1.observed.grants.like.modeMeters, 1_000);
  assert.equal(published1.observed.grants.like.n, 4, "P3's 11-day-old like is outside 7 d");
  assert.equal(published1.observed.grants.comment.modeMeters, 2_000);
  assert.equal(published1.observed.grants.dislike.modeMeters, -1_000);
  assert.equal(published1.observed.seedSeen.modeMeters, 5_000);
  assert.deepEqual(published1.observed.boostSeen.meters.byMeters, { "1000": 1 });
  assert.deepEqual(published1.observed.boostSeen.hours.byMeters, { "24": 1 });
  assert.equal(published1.observed.clamped, 0);

  // Decay attribution: only writer radiusDecay; lab growth/decay → other.unknown, radius still applied.
  const f1 = payload1.folds["post-tester-a-1"];
  assert.equal(f1.other.unknown, 2);
  assert.deepEqual(published1.coverage.unknownCauses, { growth: 1, decay: 1 });
  assert.equal(f1.lastRadius, p1Last.data.radiusMeters, "the post state follows every entry, whatever its cause");
  assert.deepEqual(f1.modeCounts, { normal: 1, trial: 3, stress: 1, undetermined: 1 }, "decay mode per entry: rate ×1 → normal, ×5 → trial, 16 %/h → stress, seed/boost drop → trial, first decay → undetermined");
  assert.equal(published1.windows.d7.realPostDecayLoss.trialMultiplierSeen, 5);
  assert.equal(published1.windows.d7.realPostDecayLoss.inferred, true);
  assert.ok(f1.seedLoss > 0 && f1.boostLoss > 0);
  assert.equal(f1.decayPaths.seed, 3, "the stress pass and both trial passes shrank the seed"); assert.equal(f1.decayPaths.boost, 1);
  const f2 = payload1.folds["post-tester-a-2"];
  assert.deepEqual(f2.modeCounts, { normal: 0, trial: 1, stress: 0, undetermined: 1 }, "below 468 m the projection fields decide the anchored entry; the other has none → undetermined");
  assert.equal(published1.coverage.undeterminedMode, 6, "the first decay entry of P1, P3, P6, P12 and P10 (no previous decay, nothing to vouch) plus P2's unanchored one");
  const byMode7 = published1.windows.d7.realPostDecayLoss.byMode;
  const totalLoss7 = byMode7.normal + byMode7.trial + byMode7.stress + byMode7.undetermined;
  const byClass7 = published1.windows.d7.realPostDecayLoss.byClass;
  approx(byClass7.real + byClass7.owner + byClass7.review + byClass7.synthetic + byClass7.unknown, totalLoss7, 1, "pro-rated loss sums to the loss");
  // Pool at decay time: real 5,500 scaled by the dislike (9,500/10,500) plus the two later repeats;
  // total 9,500 + 375 of repeats + 300 of lab growth (the lab decay scales every bucket alike).
  const expectedRealShare = (5_500 * 9_500 / 10_500 + 375) / (9_500 + 375 + 300);
  approx(f1.lossDecay.byClass.real / (f1.lossDecay.byMode.normal + f1.lossDecay.byMode.trial + f1.lossDecay.byMode.stress + f1.lossDecay.byMode.undetermined), expectedRealShare, 0.001, "real share of P1's decay = real share of its pool");
  const { outcome: runOff } = await run(buildWorld(), digest.initialState(), T0, { switches: switchesOff });
  assert.deepEqual(runOff.published.windows.d7.realPostDecayLoss.byMode, byMode7, "the same fixture folded with the trial switch off yields identical byMode");
  assert.equal(runOff.published.headline.trialOn, false);
  assert.equal(runOff.published.seedRest.valid, true);

  // Owner and review gain excluded from netReal, gainPerPostDay, firstRealEngagement.
  assert.equal(f1.firstRealAt, T0 - 5 * D + 30 * MIN, "the owner like and the review view before it never set firstRealAt");
  const net7 = published1.windows.d7.netReal;
  assert.equal(net7.all.posts, 6, "tester-owned posts only");
  assert.equal(net7.byAge.lt7d.posts, 6);
  assert.equal(net7.all.netPositive, 2, "P1 and the vanishing post are net-positive");
  approx(net7.all.postDays, 20, 0.05, "post-days in the window");
  assert.equal(net7.all.gainRealMeters, 5_875);
  assert.ok(net7.all.perPostDay > 0);
  assert.equal(published1.windows.d7.netOwner.all.posts, 1, "mark's post is published beside, never inside");
  assert.equal(published1.windows.d30.netReal.byAge.lt7d.posts, 6);
  assert.equal(published1.windows.d30.netOwner.byAge.d7to30.posts, 1);
  const live = published1.channels.find((row) => row.channelId === "live");
  assert.equal(live.realPosts, 2, "P1 and the seed-only post; mark's live post is not a tester post");
  assert.equal(live.realGainMeters, 4_875, "real actors only");
  assert.equal(live.sufficient, false); assert.equal(live.gainPerPostDay, null, "unranked below MIN_CHANNEL_POSTS");
  assert.equal(live.medianMinutesToFirstRealEngagement, null);

  // Two denominators: M4 pairs include mark's post; M6/M8/M10/M11 count only ownerClass real.
  assert.equal(published1.intercept.opportunity.realAccountsWithLocation, 3, "A, B and C, each located by their most recent drop");
  // Every live real-class post (mark's included) × every other tester within its radius: A→4, B→6, C→5.
  assert.equal(published1.intercept.opportunity.pairs, 15, "pairs from coarse cells; mark's post is a legitimate target");
  assert.equal(published1.intercept.opportunity.postsWithAnyPair, 7);
  assert.equal(published1.intercept.realized.distinctActors, 3, "B, C and the stranger");
  assert.equal(published1.seedRest.valid, false, "hidden while the trial runs");
  assert.equal(published1.seedRest.livePosts, 6);
  assert.equal(published1.seedRest.atClaim, 1, "the seed-only drop rests at its claim");
  assert.equal(published1.seedRest.everAboveClaim, 5);
  assert.equal(published1.seedRest.cleanPosts, 2, "P8 and P11 were never pumped; a history that starts mid-life is not known to be clean");
  assert.equal(published1.seedRest.peakOverClaim.p50, null, "null below MIN_POSTS");
  assert.equal(published1.seedRest.owner.livePosts, 1);
  assert.equal(published1.claims.d30.count, 3, "create entries folded on tester posts: P1, P8, P11");
  assert.equal(published1.claims.d30.atFloor, 3);
  assert.equal(published1.claims.d30.medianMeters, 5_000);
  assert.equal(published1.claims.d30.owner.count, 1, "mark's 12-day-old drop is inside 30 d and published in the owner column");
  assert.equal(published1.contamination.d7.syntheticMeters, 2_000);
  assert.equal(published1.contamination.d7.ownerMeters, 1_000);
  assert.equal(published1.contamination.d7.simulationOwnerUid, MARK);
  const contaminated = published1.contamination.d7.posts.find((row) => row.postId === "post-tester-a-1");
  approx(contaminated.share, (1_000 * 9_500 / 10_500) / (9_500 + 375 + 300), 0.001, "syntheticShare = pool.syn / Σpool");

  // Anchors and the headline reflect the trial doc.
  assert.equal(published1.anchors.everAtWorld, 2);
  assert.equal(published1.anchors.atWorld, 0);
  const cartoon = published1.anchors.rows.find((row) => row.postId === "post-official-cartoon-drive-ad");
  assert.equal(cartoon.decayPathSeen, "boost", "production's official posts decay through the boosted trial path");
  approx(cartoon.ratePerPassSeen, 1 - 0.95 ** (5 / 24), 0.0001, "≈ 1.06 %/pass at ×5");
  assert.equal(published1.anchors.rows.find((row) => row.postId === "post-official-organic-1").decayPathSeen, "organic");
  assert.equal(published1.headline.trialOn, true);
  assert.equal(published1.headline.trialMultiplier, 5);
  assert.equal(published1.headline.trialSinceMillis, 1788826046064);
  assert.equal(published1.headline.boostedSinceMillis, 1788845178241);
  assert.equal(published1.headline.anchorsEver, 2);
  assert.equal(published1.headline.worstAnchor.postId, "post-official-cartoon-drive-ad");
  assert.equal(published1.switches.decayTrial.scope, "all-users");
  assert.equal(published1.curve.trial.multiplier, 5);
  assert.ok(published1.curve.trial.seedDaysToFloor > 10);
  assert.equal(published1.curve.stress.halfLifeHours, 4);

  // Post rows, gates, versions.
  const row1 = published1.posts.find((row) => row.postId === "post-tester-a-1");
  assert.equal(row1.ownerClass, "real"); assert.equal(row1.clean, false); assert.equal(row1.decayModeSeen, "trial");
  assert.equal(row1.realGain, 4_875); assert.equal(row1.ownerGain, 1_000); assert.equal(row1.reviewGain, 1_000); assert.equal(row1.syntheticGain, 1_000); assert.equal(row1.unknownGain, 2_300);
  assert.equal(row1.viewCount, 40);
  assert.equal(published1.posts.find((row) => row.postId === "post-owner-1").ownerClass, "owner");
  assert.equal(published1.posts.find((row) => row.postId === "post-official-cartoon-drive-ad").ownerClass, "official");
  assert.equal(published1.posts.find((row) => row.postId === "post-tester-b-seedonly").atClaim, true);
  assert.equal(published1.questions.c.sufficient, false); assert.equal(published1.questions.c.n, 9); assert.equal(published1.questions.c.minN, 30);
  assert.equal(published1.questions.f.sufficient, false);
  assert.equal(published1.knobs.sourcePolicyVersion, digest.sourcePolicyVersion());
  assert.equal(published1.observedPolicyVersions.length, 1);
  assert.equal(published1.observedPolicy.version, run1.state.observedPolicyVersions[0].version);
  assert.equal(published1.observedPolicy.complete, true);
  assert.equal(published1.sourceMatchesObserved, true, "production paid what the source declares");
  assert.equal(published1.days.length, 30);
  assert.equal(published1.days.at(-1).day, "2026-09-11");
  assert.equal(published1.gates.minEvents, 30);
  assert.equal(published1.version, 1);
  assert.equal(published1.coverage.timeZone, TZ);
  assert.deepEqual(published1.gaps.map((gap) => gap.id), ["decayMode", "ceilingMeters", "surface"]);

  // Determinism: byte-identical output for the same input.
  const { outcome: again } = await run(buildWorld(), digest.initialState(), T0);
  assert.equal(JSON.stringify(again.published), JSON.stringify(published1));
  assert.equal(JSON.stringify(again.state), JSON.stringify(run1.state));

  // Idempotency: the same ledgers again from the committed state fold nothing.
  const { outcome: idle } = await run(world, run1.state, T0 + H);
  assert.equal(idle.cost.entriesProcessed, 0);
  assert.equal(idle.published.windows.d7.realPostGain.real.total, 5_875);
  assert.ok(digest.cursorsEqual(idle.startCursors, digest.startCursorsOf(run1.state)));

  // ── Run 2: next day — fetches, the create guard, the refresh, the horizon, the exact sweep cursor ──
  const T1 = T0 + 25 * H;
  world.ledgers.get("post-tester-a-2").push({ id: "create", data: { atMillis: T0 - 3 * D, cause: "create", writer: "radiusHistoryOnPostCreated", radiusMeters: 5_000, organicRadiusMeters: 0, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: 0, organicDelta: 0 } });
  world.ledgers.get("post-tester-a-2").push({ id: `decay_${T1 - 40 * MIN}`, data: { atMillis: T1 - 40 * MIN, cause: "decay", writer: "radiusDecay", radiusMeters: 5_298, organicRadiusMeters: 298, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: -1, organicDelta: -1 } });
  world.ledgers.get("post-tester-a-2").push({ id: `decay_${T1 - 20 * MIN}`, data: { atMillis: T1 - 20 * MIN, cause: "decay", writer: "radiusDecay", radiusMeters: 5_297, organicRadiusMeters: 297, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: -1, organicDelta: -1 } });
  world.ledgers.get("post-tester-c-clockahead").push({ id: "create", data: { atMillis: T0 - 2 * H, cause: "create", writer: "radiusHistoryOnPostCreated", radiusMeters: 6_000, organicRadiusMeters: 1_000, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: 0, organicDelta: 0 } });
  world.posts.delete("post-tester-a-vanishes");
  world.posts.set("post-tester-b-2", { data: postDoc(TESTER_B, { channelId: "sports" }), createdAt: ts(tupleMillis(newest[1].createdAt), 551_000) });
  world.ledgers.set("post-tester-b-2", ledger().create(tupleMillis(newest[1].createdAt), 5_000).rows);
  const { outcome: run2, reader: reader2 } = await run(world, run1.state, T1);
  assert.equal(run2.status, "ok");
  const payload2 = run2.state.payload, published2 = run2.published;
  assert.deepEqual(reader2.calls.sweep[0].after, run1.state.sweep.cursor, "the second run starts after the exact stored tuple");
  assert.deepEqual(reader2.calls.sweep[0].fromMillis, null);
  assert.equal(published2.coverage.sweep.sweptPosts, 1, "only the post 551 µs after the cursor is read; nothing is re-read");
  assert.ok(payload2.postMeta["post-tester-b-2"], "a new tester post is registered by the sweep");
  assert.deepEqual(reader2.calls.create.sort(), ["post-tester-a-2", "post-tester-c-clockahead", "post-tester-c-nocreate"], "the direct create fetch runs at the next run for posts whose first page had no create");
  assert.equal(payload2.postMeta["post-tester-a-2"].hasCreate, true, "a late create behind the cursor is folded once by the fetch");
  assert.equal(payload2.folds["post-tester-a-2"].birthSeed, 5_000);
  assert.equal(payload2.folds["post-tester-a-2"].firstAt, T0 - 3 * D);
  assert.equal(payload2.postMeta["post-tester-c-clockahead"].hasCreate, true);
  assert.equal(published2.coverage.createFetched, 2);
  assert.equal(published2.coverage.createSkipped, 1, "the page met P12's create after the fetch had folded it → skipped");
  assert.equal(published2.cost.createSkipped, 1);
  assert.equal(published2.coverage.createMissing, 1, "P10 has no create anywhere");
  assert.deepEqual(payload2.postMeta["post-tester-c-nocreate"].createFetch, { requestedRun: 1, lastRun: 2 }, "…and retries daily");
  assert.equal(payload2.folds["post-tester-c-clockahead"].n, 2, "create + decay, the create exactly once");
  const f2b = payload2.folds["post-tester-a-2"];
  assert.deepEqual(f2b.modeCounts, { normal: 0, trial: 2, stress: 0, undetermined: 1 }, "an entry newer than the last refresh, below 468 m, takes the projection's mode");
  assert.equal(reader2.calls.ledger.find((q) => q.postId === "post-tester-a-2").horizonMillis, T1 - 30 * MIN);
  assert.equal(payload2.postMeta["post-tester-a-2"].cursor.atMillis, T1 - 40 * MIN, "the horizon excludes the entry 20 min old");
  const { outcome: run3 } = await run(world, run2.state, T1 + H);
  assert.equal(run3.state.payload.postMeta["post-tester-a-2"].cursor.atMillis, T1 - 20 * MIN, "…which the next run folds");
  assert.equal(run3.cost.entriesProcessed, 1);

  // Refresh: not-found → deletedAtMillis, out of livePosts, fold kept; viewCount samples land on the day.
  assert.equal(run2.state.refresh.lastRefreshDay, "2026-09-12");
  assert.equal(published2.cost.refreshReads, 9, "every registered post except the one registered today");
  const gone = payload2.postMeta["post-tester-a-vanishes"];
  assert.equal(gone.deletedAtMillis, T1); assert.equal(gone.live, false);
  assert.equal(published2.coverage.postsDeleted, 1); assert.equal(published2.coverage.postsGone, 1);
  assert.ok(payload2.folds["post-tester-a-vanishes"], "the fold is kept for history");
  assert.equal(published2.posts.find((row) => row.postId === "post-tester-a-vanishes").deletedAtMillis, T1);
  assert.equal(published2.seedRest.livePosts, 6, "P11 left, P2/P1/P8/P12/P10 + the new tester post");
  assert.equal(published2.intercept.opportunity.pairs, 15, "the deleted post's two pairs are out; B's new post brings two in");
  assert.equal(published2.intercept.opportunity.postsWithAnyPair, 7);
  assert.equal(payload2.folds["post-tester-a-1"].days["2026-09-12"].vc, 40, "the refresh writes today's viewCount sample");
  assert.equal(payload2.folds["post-tester-a-1"].days["2026-09-11"].vc, 40, "registration sampled the day it read the document");
  const music = published2.channels.find((row) => row.channelId === "music");
  approx(music.postDays, (T1 - (T0 - D)) / D, 0.01, "channel post-days end at deletedAtMillis");
  assert.equal(run2.state.readsDay, "2026-09-12");
  assert.equal(run2.state.readsToday, published2.cost.reads, "readsToday rolled with the Toronto day");
  assert.equal(published2.digestVersion, 2);
  assert.equal(published2.coverage.complete, true);

  // ── Failed Auth page: aborts before any fold ──
  const { outcome: authFailed, reader: readerFailed } = await run(buildWorld(), digest.initialState(), T0, { failAuth: true });
  assert.equal(authFailed.status, "auth-failed");
  assert.equal(readerFailed.calls.sweep.length, 0); assert.equal(readerFailed.calls.ledger.length, 0);
  assert.equal(authFailed.cost.reads, 0);

  // ── resetRequestedAtMillis wipes the payload and every cursor ──
  const { outcome: reset, reader: resetReader } = await run(world, run2.state, T1 + 2 * H, { config: config({ resetRequestedAtMillis: T1 + H }) });
  assert.equal(resetReader.calls.sweep[0].after, null, "after a reset the sweep starts over, unbounded");
  assert.equal(resetReader.calls.sweep[0].fromMillis, null);
  assert.equal(reset.state.lastResetAtMillis, T1 + H);
  assert.ok(digest.cursorsEqual(reset.startCursors, digest.startCursorsOf(run2.state)), "the commit still compares against the pre-reset cursors");
  assert.equal(reset.state.payload.coverage.entriesFolded, reset.cost.entriesProcessed, "everything re-folded from scratch");
  assert.equal(reset.state.digestVersion, 3);
  assert.equal(reset.state.payload.coverage.kindSplitSinceMillis, 0, "a reset re-fold introduces the fold additions on an empty payload");
  assert.equal(reset.state.report.lastReportedDay, run2.state.report.lastReportedDay, "the report's memory survives a reset (decision 5)");
  assert.equal(reset.state.report.rows.length, run2.state.report.rows.length, "rows are superseded in place, never dropped (the vanished post's day is re-folded without it → one amendment)");
  assert.deepEqual(reset.reports.map((r) => [r.day, r.revision]), [[day(T0 - D), 2]], "…and that is the only report the reset run writes: no re-backfill");
  assert.equal(reset.state.readsToday, run2.state.readsToday + reset.cost.reads, "…and so do the day counters");
  const { outcome: noReset } = await run(world, reset.state, T1 + 3 * H, { config: config({ resetRequestedAtMillis: T1 + H }) });
  assert.equal(noReset.cost.entriesProcessed, 0, "an already-applied reset stamp does not wipe again");

  // ── Budget and cursors on ties: 600 same-millis engagement entries ──
  const pagingWorld = { auth: { ...AUTH }, posts: new Map(), ledgers: new Map(), engagements: new Map(), users: new Map() };
  const P = "post-tester-paging", TP = T0 - D;
  const paging = ledger().create(TP, 5_000);
  for (let i = 0; i < 600; i++) { const eid = `e${String(i).padStart(4, "0")}`; paging.engage(TP + 1_000, "view", 1, eid); pagingWorld.engagements.set(`${P}/${eid}`, { actorUid: TESTER_B, surface: "feed" }); }
  pagingWorld.posts.set(P, { data: postDoc(TESTER_A, { organic: 600 }), createdAt: ts(TP) });
  pagingWorld.ledgers.set(P, paging.rows);
  const { outcome: capped, reader: cappedReader } = await run(pagingWorld, digest.initialState(), T0, { config: config({ maxReadsPerRun: 800 }) });
  assert.equal(capped.cost.budgetHit, true); assert.equal(capped.published.coverage.capped, true); assert.equal(capped.published.coverage.complete, false);
  assert.equal(capped.published.coverage.postsBehindHorizon, 1);
  // 8 fixed + 1 sweep + 500 page reads, then one join per entry while 2 reads of headroom remain: entries 0…289.
  assert.deepEqual(capped.state.payload.postMeta[P].cursor, { atMillis: TP + 1_000, id: "eng_e0289" }, "the cursor stops on the last fully processed entry, join included");
  assert.equal(capped.cost.reads, 799, "never past the cap");
  assert.equal(capped.cost.entriesProcessed, 291, "the create and 290 joined entries");
  assert.equal(cappedReader.calls.engagement, 290);
  assert.equal(capped.state.refresh.lastRefreshDay, null, "a capped run does not refresh");
  const { outcome: resumed, reader: resumedReader } = await run(pagingWorld, capped.state, T0 + H);
  const pages = resumedReader.calls.ledger.filter((q) => q.postId === P);
  assert.deepEqual(pages[0].after, { atMillis: TP + 1_000, id: "eng_e0289" }, "later pages start after (atMillis, id) — ties by id");
  assert.equal(resumed.cost.entriesProcessed, 310);
  assert.deepEqual(resumed.state.payload.postMeta[P].cursor, { atMillis: TP + 1_000, id: "eng_e0599" });
  assert.equal(resumed.published.windows.d7.realPostGain.real.n, 600, "every entry exactly once across the cap");
  assert.equal(resumed.published.coverage.complete, true);

  // ── Cost strip arithmetic ──
  assert.equal(published1.cost.monthlyReadsProjected, published1.cost.reads * 24 * 30);
  approx(published1.cost.monthlyCadProjected, published1.cost.reads * 720 / 100_000 * 0.05, 0.0001, "CA$0.05 per 100k reads");

  console.log("algorithm digest policy (engine): all assertions passed");
  await directTests();
  console.log("algorithm digest policy: all assertions passed");
})().catch((error) => { console.error(error); process.exit(1); });

// ── Direct fold tests: pro-rating, clamps, gates, viewWorth, bounds, versions ──
async function directTests() {
  const meta = (overrides = {}) => ({ cls: "r", ownerUid: TESTER_A, ownerClass: "r", ch: "live", createdAtMillis: T0 - 3 * D, lat: 43.65, lng: -79.38, hasCreate: false, cursor: null,
    live: true, expiredAtMillis: null, deletedAtMillis: null, viewCount: 0, viewCountAtMillis: null, lastDecayAt: null, lastOrganic: null, lastSeed: null, lastBoost: null,
    decayAnchorMillis: null, decayOrganicPerDay: null, decaySeedPerDay: null, decayBoostPerDay: null, refreshedAtMillis: null, docRadiusMeters: null, createFetch: null, registeredRun: 1, ...overrides });
  const foldRun = () => ({ knobs: digest.KNOBS, timeZone: TZ, digestVersion: 1, touchedDays: new Set() });
  const actor = (cls, surface = "feed", uid = null) => ({ cls, surface, joined: true, uid });
  const entry = (row) => digest.parseEntry(row);
  const renderWith = (payload, now, switches = switchesOn, cfg = config()) => {
    const state = { ...digest.initialState(), digestVersion: 1, payload };
    return digest.renderDigest({ state, config: cfg, switches, runStartMillis: now, runId: "direct", knobs: digest.KNOBS, stamp: digest.SYNC_STAMP, timeZone: TZ,
      cost: { reads: 8, writes: 3, entriesProcessed: 0, postsPolled: 0, postsWithEntries: 0, engagementJoins: 0, postLookups: 0, createFetches: 0, createSkipped: 0, sweepReads: 0, refreshReads: 0, userLookups: 0, authPages: 1, runMs: 0, budgetHit: false, capInForce: 6000 },
      runCoverage: { postsBehindHorizon: 0, sweptPosts: 0, evicted: 0, trimmed: false, capped: false, postsDeleted: 0, registeredThisRun: 0, refreshed: true, payloadOverflow: false } });
  };

  // Pool pro-rating: 1,000 real + 9,000 synthetic losing 500 m books 50 m to real.
  {
    const payload = digest.emptyPayload();
    payload.postMeta.p = meta();
    const l = ledger().create(T0 - 3 * D, 5_000).engage(T0 - 3 * D + MIN, "view", 1_000, "r");
    for (let i = 0; i < 9; i++) l.engage(T0 - 3 * D + (2 + i) * MIN, "view", 1_000, `s${i}`);
    l.decayTo(T0 - 2 * D, 9_500);
    const rows = l.rows;
    digest.foldEntry(payload, "p", entry(rows[0]), null, foldRun());
    digest.foldEntry(payload, "p", entry(rows[1]), actor("real"), foldRun());
    for (let i = 2; i < 11; i++) digest.foldEntry(payload, "p", entry(rows[i]), actor("synthetic"), foldRun());
    digest.foldEntry(payload, "p", entry(rows[11]), null, foldRun());
    approx(payload.folds.p.lossDecay.byClass.real, 50, 1e-9, "real share of a 500 m loss on a 10 % real pool");
    approx(payload.folds.p.lossDecay.byClass.syn, 450, 1e-9);
    approx(payload.folds.p.pool.real, 950, 1e-9);
    assert.equal(payload.folds.p.everPumped, true);
    // Expiry zeroes the pool.
    digest.foldEntry(payload, "p", entry({ id: "decay_x", data: { atMillis: T0 - D, cause: "decay", writer: "radiusDecay", radiusMeters: 0, organicRadiusMeters: 0, seedRadiusMeters: 0, boostedRadiusMeters: 0, delta: -14_500, organicDelta: -9_500 } }), null, foldRun());
    assert.deepEqual(payload.folds.p.pool, { real: 0, owner: 0, review: 0, syn: 0, unknown: 0 });
    assert.equal(payload.folds.p.zeroAt, T0 - D); assert.equal(payload.postMeta.p.live, false);
    approx(payload.folds.p.lossDecay.byClass.real, 50 + 950, 1e-9, "the expiry's loss is pro-rated too");
  }
  // A clean post books everything to real.
  {
    const payload = digest.emptyPayload();
    payload.postMeta.p = meta();
    const rows = ledger().create(T0 - 3 * D, 5_000).engage(T0 - 3 * D + MIN, "like", 1_000, "r").decayTo(T0 - 2 * D, 900).rows;
    digest.foldEntry(payload, "p", entry(rows[0]), null, foldRun());
    digest.foldEntry(payload, "p", entry(rows[1]), actor("real", "map"), foldRun());
    digest.foldEntry(payload, "p", entry(rows[2]), null, foldRun());
    assert.equal(payload.folds.p.lossDecay.byClass.real, 100);
    assert.equal(payload.folds.p.everPumped, false);
    assert.equal(payload.days[day(T0 - 3 * D + MIN)].realSurfaces.map, 1);
  }
  // Clamped: at the ceiling, and a partial dislike; resync never in n.
  {
    const at = T0 - D;
    assert.equal(digest.isClamped(entry({ id: "e", data: { atMillis: at, cause: "engagement", kind: "like", radiusMeters: MAX, organicRadiusMeters: MAX, delta: 0, organicDelta: 3 } })), true);
    assert.equal(digest.isClamped(entry({ id: "e", data: { atMillis: at, cause: "engagement", kind: "dislike", radiusMeters: 9_000, organicRadiusMeters: 4_000, delta: -400, organicDelta: -400 } })), true, "a partial dislike");
    assert.equal(digest.isClamped(entry({ id: "e", data: { atMillis: at, cause: "engagement", kind: "like", radiusMeters: MAX - 500, organicRadiusMeters: 1, delta: 500, organicDelta: 500 } })), true, "a like paid short within 2 km of the ceiling");
    assert.equal(digest.isClamped(entry({ id: "e", data: { atMillis: at, cause: "engagement", kind: "like", radiusMeters: 9_000, organicRadiusMeters: 4_000, delta: 1_000, organicDelta: 1_000 } })), false);
    const payload = digest.emptyPayload();
    payload.postMeta.p = meta();
    digest.foldEntry(payload, "p", entry({ id: "create", data: { atMillis: at - H, cause: "create", writer: "w", radiusMeters: MAX, organicRadiusMeters: MAX - 3, seedRadiusMeters: 0, boostedRadiusMeters: 0, delta: 0, organicDelta: 0 } }), null, foldRun());
    digest.foldEntry(payload, "p", entry({ id: "eng_b", data: { atMillis: at + 1, cause: "engagement", writer: "recordPostEngagement", kind: "like", engagementId: "b", radiusMeters: MAX, organicRadiusMeters: MAX, seedRadiusMeters: 0, boostedRadiusMeters: 0, delta: 0, organicDelta: 3 } }), actor("real"), foldRun());
    const cell = payload.days[day(at)];
    assert.equal(cell.realPostGain.real.clamped, 1); assert.equal(cell.realPostGain.real.n, 1); assert.equal(cell.distinctRealLikers, 0, "a clamped like is not a distinct-liker signal");
    assert.deepEqual(cell.realActorEntries, {}, "a clamped entry never enters the per-uid map");
    assert.equal(payload.folds.p.rk.l, 0);
    assert.equal(payload.observed[day(at)].clamped.n, 1); assert.equal(payload.observed[day(at)].like, undefined, "clamped entries never enter M16");
    digest.foldEntry(payload, "p", entry({ id: "eng_c", data: { atMillis: at + 2, cause: "engagement", writer: "recordPostEngagement", kind: "view", engagementId: "c", radiusMeters: MAX - 100, organicRadiusMeters: MAX, seedRadiusMeters: 0, boostedRadiusMeters: 0, delta: -100, organicDelta: 0 } }), actor("real"), foldRun());
    assert.equal(cell.realPostGain.real.resync, 1); assert.equal(cell.realPostGain.real.n, 1, "resync never in n");
    assert.equal(payload.observed[day(at)].resync.n, 1); assert.equal(payload.observed[day(at)].view, undefined, "…nor M16");
    // Fold addition 2: a partial dislike (organicDelta in (−1,000, 0)) is counted apart from its partial delta.
    digest.foldEntry(payload, "p", entry({ id: "eng_d", data: { atMillis: at + 3, cause: "engagement", writer: "recordPostEngagement", kind: "dislike", engagementId: "d", radiusMeters: MAX - 400, organicRadiusMeters: MAX - 400, seedRadiusMeters: 0, boostedRadiusMeters: 0, delta: -400, organicDelta: -400 } }), actor("real", "map", TESTER_B), foldRun());
    assert.equal(cell.realPostGain.real.clampedDislikes, 1); assert.equal(cell.realPostGain.real.clampedDislikeMeters, -400);
    assert.equal(cell.realPostGain.real.dislike, -400, "gain.dislike still takes the partial delta"); assert.equal(cell.realPostGain.real.clamped, 2); assert.equal(cell.realPostGain.real.n, 2);
    assert.equal(payload.folds.p.rk.d, 0, "clamped: not a real-actor kind count"); assert.deepEqual(cell.realActorEntries, {});
  }
  // Decay mode inference, direct.
  {
    const base = { prev: { organic: 100_000, seed: 5_000, boost: 0 }, seedDrop: 0, boostDrop: 0, projection: { refreshedAtMillis: null, decayAnchorMillis: null, decayOrganicPerDay: null, decaySeedPerDay: null, decayBoostPerDay: null } };
    const decayEntry = (organic, at = T0) => entry({ id: `decay_${at}`, data: { atMillis: at, cause: "decay", writer: "radiusDecay", radiusMeters: organic + 5_000, organicRadiusMeters: organic, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: organic - 100_000, organicDelta: organic - 100_000 } });
    assert.deepEqual(digest.inferDecayMode({ ...base, entry: decayEntry(predict(100_000, H, 1)), lastDecayAt: T0 - H }), { mode: "normal", multiplier: null, rule: 2 }, "0.21 %/h → normal");
    assert.deepEqual(digest.inferDecayMode({ ...base, entry: decayEntry(predict(100_000, H, 5)), lastDecayAt: T0 - H }), { mode: "trial", multiplier: 5, rule: 2 }, "1.06 %/h → trial ×5");
    assert.deepEqual(digest.inferDecayMode({ ...base, entry: decayEntry(Math.floor(100_000 * 2 ** (-1 / 4))), lastDecayAt: T0 - H }), { mode: "stress", multiplier: null, rule: 2 }, "16 %/h → stress");
    assert.deepEqual(digest.inferDecayMode({ ...base, entry: decayEntry(predict(100_000, H, 5)), lastDecayAt: T0 - H, seedDrop: 53 }), { mode: "trial", multiplier: 5, rule: 1 }, "a seed drop → trial");
    assert.deepEqual(digest.inferDecayMode({ ...base, entry: decayEntry(predict(100_000, H, 3)), lastDecayAt: T0 - H, boostDrop: 11 }), { mode: "trial", multiplier: 3, rule: 1 }, "a boost drop → trial");
    assert.deepEqual(digest.inferDecayMode({ ...base, entry: decayEntry(predict(100_000, H, 1)), lastDecayAt: null }), { mode: "undetermined", multiplier: null, rule: 0 }, "no previous decay entry, nothing to vouch → undetermined, never a guess");
    const low = { ...base, prev: { organic: 300, seed: 5_000, boost: 0 }, lastDecayAt: T0 - H };
    const lowEntry = entry({ id: "decay_x", data: { atMillis: T0, cause: "decay", writer: "radiusDecay", radiusMeters: 5_299, organicRadiusMeters: 299, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: -1, organicDelta: -1 } });
    assert.equal(digest.inferDecayMode({ ...low, entry: lowEntry }).mode, "undetermined", "below 468 m the rate says nothing");
    const vouched = { refreshedAtMillis: T0 - D, decayAnchorMillis: T0 - 2 * H, decayOrganicPerDay: 1 - 0.95 ** 5, decaySeedPerDay: 1 - 0.95 ** 5, decayBoostPerDay: 0 };
    assert.deepEqual(digest.inferDecayMode({ ...low, entry: lowEntry, projection: vouched }), { mode: "trial", multiplier: 5, rule: 3 }, "…so the post's projection fields decide");
    assert.deepEqual(digest.inferDecayMode({ ...low, entry: lowEntry, projection: { ...vouched, decayAnchorMillis: 0 } }), { mode: "stress", multiplier: null, rule: 3 });
    assert.deepEqual(digest.inferDecayMode({ ...low, entry: lowEntry, projection: { ...vouched, decayOrganicPerDay: 0.05, decaySeedPerDay: 0 } }), { mode: "normal", multiplier: null, rule: 3 });
    assert.equal(digest.inferDecayMode({ ...low, entry: lowEntry, projection: { ...vouched, refreshedAtMillis: T0 + H } }).mode, "undetermined", "older than the last refresh and unanchored → undetermined");
    assert.equal(digest.inferDecayMode({ ...low, entry: lowEntry, projection: { ...vouched, refreshedAtMillis: T0 + H, decayAnchorMillis: T0 } }).mode, "trial", "the anchored pass itself is always decided");
  }
  // Gates: sufficient false at n = 29, true at 30; SIM counts never satisfy REAL.
  {
    const build = (n, cls) => {
      const payload = digest.emptyPayload();
      payload.postMeta.p = meta({ hasCreate: true });
      payload.realActorUids = [TESTER_B, TESTER_C];
      digest.foldEntry(payload, "p", entry({ id: "create", data: { atMillis: T0 - 3 * D, cause: "create", writer: "w", radiusMeters: 5_000, organicRadiusMeters: 0, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: 0, organicDelta: 0 } }), null, foldRun());
      for (let i = 0; i < n; i++) digest.foldEntry(payload, "p", entry({ id: `eng_${i}`, data: { atMillis: T0 - D + i * MIN, cause: "engagement", writer: "recordPostEngagement", kind: "view", engagementId: String(i), radiusMeters: 5_000 + 1_000 * (i + 1), organicRadiusMeters: 1_000 * (i + 1), seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: 1_000, organicDelta: 1_000 } }), actor(cls), foldRun());
      return renderWith(payload, T0);
    };
    assert.equal(build(29, "real").questions.c.sufficient, false);
    assert.equal(build(29, "real").questions.c.n, 29);
    assert.equal(build(30, "real").questions.c.sufficient, true);
    assert.equal(build(30, "synthetic").questions.c.n, 0, "SIM counts never satisfy a REAL threshold");
    assert.equal(build(30, "synthetic").questions.c.sufficient, false);
    assert.equal(build(30, "synthetic").windows.d7.realPostGain.synthetic.n, 30, "…but SIM columns are always shown");
  }
  // viewWorth.views from per-day vc samples on clean posts only; null until two samples bracket the window.
  {
    const payload = digest.emptyPayload();
    payload.postMeta.p = meta({ createdAtMillis: T0 - 20 * D });
    digest.foldEntry(payload, "p", entry({ id: "create", data: { atMillis: T0 - 20 * D, cause: "create", writer: "w", radiusMeters: 5_000, organicRadiusMeters: 0, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: 0, organicDelta: 0 } }), null, foldRun());
    payload.folds.p.days["2026-09-10"] = { gr: 0, go: 0, gv: 0, gs: 0, gu: 0, dl: 0, dlr: 0, vc: 25 };
    assert.equal(renderWith(payload, T0).windows.d7.viewWorth.views, null, "no sample before the window");
    payload.folds.p.days["2026-09-01"] = { gr: 0, go: 0, gv: 0, gs: 0, gu: 0, dl: 0, dlr: 0, vc: 10 };
    const worth = renderWith(payload, T0).windows.d7.viewWorth;
    assert.equal(worth.views, 15); assert.equal(worth.cleanPosts, 1); assert.equal(worth.viewSampleDays, 1);
    payload.folds.p.everPumped = true;
    assert.equal(renderWith(payload, T0).windows.d7.viewWorth.views, null, "a pumped post's viewCount is never a real-view count");
  }
  // seedRest p50/p90 over clean tester posts, null below MIN_POSTS, valid: false while the trial runs.
  {
    const payload = digest.emptyPayload();
    for (let i = 0; i < 9; i++) {
      const id = `p${i}`;
      payload.postMeta[id] = meta({ createdAtMillis: T0 - (i + 1) * D, ownerUid: `Tester${i}` });
      const rows = ledger().create(T0 - (i + 1) * D, 5_000).engage(T0 - (i + 1) * D + (i + 1) * H, "like", 1_000 * (i + 1), "r").rows;
      digest.foldEntry(payload, id, entry(rows[0]), null, foldRun());
      digest.foldEntry(payload, id, entry(rows[1]), actor("real"), foldRun());
    }
    const off = renderWith(payload, T0, switchesOff);
    assert.equal(off.seedRest.valid, true); assert.equal(off.seedRest.cleanPosts, 9); assert.equal(off.seedRest.everAboveClaim, 9); assert.equal(off.seedRest.atClaim, 0);
    assert.equal(off.seedRest.peakOverClaim.p50, 2, "peak/claim: (5,000 + 5,000) / 5,000 for the fifth post");
    assert.equal(off.seedRest.peakOverClaim.p90, 2.8);
    assert.equal(off.seedRest.timeToPeakHours.p50, 5);
    assert.equal(off.seedRest.claimShareMedian, 0.5);
    assert.equal(renderWith(payload, T0, switchesOn).seedRest.valid, false, "valid: false while the trial switch is on");
    for (const id of ["p7", "p8"]) { delete payload.postMeta[id]; delete payload.folds[id]; }
    assert.equal(renderWith(payload, T0, switchesOff).seedRest.peakOverClaim.p50, null, "null below MIN_POSTS");
    assert.equal(renderWith(payload, T0, switchesOff).seedRest.peakOverClaim.n, 7);
  }
  // Bounds: channels fold to other at 13, posts 50, days 30 published while the state keeps 400 day cells.
  {
    const payload = digest.emptyPayload();
    for (let i = 0; i < 55; i++) {
      const id = `post-${String(i).padStart(2, "0")}`;
      payload.postMeta[id] = meta({ ch: `ch${i % 14}`, ownerUid: `T${i}`, createdAtMillis: T0 - (i + 1) * H });
      digest.foldEntry(payload, id, entry({ id: "create", data: { atMillis: T0 - (i + 1) * H, cause: "create", writer: "w", radiusMeters: 5_000, organicRadiusMeters: 0, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: 0, organicDelta: 0 } }), null, foldRun());
    }
    for (let i = 0; i < 400; i++) payload.days[day(T0 - i * D)] ??= digest.emptyDayCell(day(T0 - i * D));
    const doc = renderWith(payload, T0);
    assert.equal(doc.channels.length, 13); assert.equal(doc.channels.at(-1).channelId, "other");
    assert.equal(doc.channels.reduce((n, row) => n + row.realPosts, 0), 55);
    assert.equal(doc.posts.length, 50);
    assert.equal(doc.days.length, 30);
    assert.equal(Object.keys(payload.days).length, 400, "state keeps every day cell");
    const trimmed = digest.trimPayload(payload, T0, TZ);
    assert.equal(trimmed.trimmed, false); assert.equal(Object.keys(payload.days).length, 400, "no eviction under 700 KB");
  }
  // Payload trim order: fold day cells older than 400 d → actor cache → stale finished folds; days never.
  {
    const build = () => {
      const payload = digest.emptyPayload();
      for (let i = 0; i < 500; i++) payload.days[day(T0 - i * D)] = digest.emptyDayCell(day(T0 - i * D));
      for (let i = 0; i < 500; i++) payload.actorClassByUid[`uid-${String(i).padStart(24, "x")}`] = "r";
      for (let i = 0; i < 100; i++) {
        const id = `post-${i}`;
        payload.postMeta[id] = meta({ createdAtMillis: T0 - 500 * D, deletedAtMillis: i < 50 ? T0 - 100 * D : null, live: i >= 50 });
        digest.foldEntry(payload, id, entry(ledger().create(T0 - 500 * D, 5_000).rows[0]), null, foldRun());
        for (let d = 0; d < 20; d++) payload.folds[id].days[day(T0 - (450 - d) * D)] = { gr: 1, go: 0, gv: 0, gs: 0, gu: 0, dl: 0, dlr: 0 };
        payload.folds[id].lastAt = T0 - (i < 50 ? 200 : 1) * D;
      }
      return payload;
    };
    const full = digest.compactPayloadBytes(build());
    const afterDays = build(); for (const fold of Object.values(afterDays.folds)) fold.days = {};
    const afterCache = digest.deepClone(afterDays); for (const key of Object.keys(afterCache.actorClassByUid).slice(0, 250)) delete afterCache.actorClassByUid[key];
    const step1 = digest.compactPayloadBytes(afterDays), step2 = digest.compactPayloadBytes(afterCache);
    assert.ok(full > step1 && step1 > step2, "each step frees bytes");
    assert.ok(full < 700_000, "the compact form of 500 day cells + 100 folds stays far under the guard");
    const untouched = build();
    assert.deepEqual(digest.trimPayload(untouched, T0, TZ), { bytes: full, evicted: 0, trimmed: false, overflow: false });
    const one = build();
    const r1 = digest.trimPayload(one, T0, TZ, { trim: step1 + 100, hard: 900_000 });
    assert.equal(r1.trimmed, true);
    assert.equal(Object.keys(one.folds["post-60"].days).length, 0, "fold day cells older than 400 days go first");
    assert.equal(Object.keys(one.actorClassByUid).length, 500, "…and nothing else when that is enough");
    assert.ok(one.folds["post-0"]);
    const two = build();
    digest.trimPayload(two, T0, TZ, { trim: step2 + 100, hard: 900_000 });
    assert.equal(Object.keys(two.actorClassByUid).length, 250, "then the actor cache LRU, oldest half");
    assert.ok(two.folds["post-0"], "…finished folds still untouched");
    const three = build();
    const dayCells = Object.keys(three.days).length;
    const r3 = digest.trimPayload(three, T0, TZ, { trim: 1_000, hard: 2_000 });
    assert.equal(three.folds["post-0"], undefined, "then finished folds idle for 90 days");
    assert.ok(three.folds["post-60"], "a live fold stays");
    assert.equal(three.coverage.evicted, 50); assert.equal(r3.evicted, 50);
    assert.equal(Object.keys(three.days).length, dayCells, "day cells are never evicted");
    assert.equal(r3.overflow, true, "and the run says so rather than halting");
    const roundTrip = digest.hydratePayload(JSON.parse(JSON.stringify(digest.compactPayload(build()))));
    assert.deepEqual(roundTrip, build(), "compact → hydrate is lossless");
    const withPeople = build();
    digest.foldEntry(withPeople, "post-60", entry({ id: "eng_r", data: { atMillis: T0 - D, cause: "engagement", writer: "recordPostEngagement", kind: "like", engagementId: "r", radiusMeters: 6_000, organicRadiusMeters: 1_000, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: 1_000, organicDelta: 1_000 } }), actor("real", "feed", TESTER_B), foldRun());
    const peopleTrip = digest.hydratePayload(JSON.parse(JSON.stringify(digest.compactPayload(withPeople))));
    assert.deepEqual(peopleTrip, withPeople, "…including rk, the per-uid map (inner zeros restored) and the clamp counters");
  }
  // Published 400 KB guard: halve posts → days 14 → drop contamination.posts, trimmed: true.
  {
    const fat = (n) => Array.from({ length: n }, (_, i) => ({ postId: `post-${i}`, blob: "x".repeat(20_000) }));
    const doc = digest.guardPublished({ coverage: { trimmed: false }, posts: fat(30), days: fat(30), contamination: { d7: { posts: fat(20) } } });
    assert.equal(doc.coverage.trimmed, true);
    assert.equal(doc.posts.length, 15); assert.equal(doc.days.length, 14); assert.equal(doc.contamination.d7.posts.length, 0);
    const slim = digest.guardPublished({ coverage: { trimmed: false }, posts: fat(2), days: fat(2), contamination: { d7: { posts: [] } } });
    assert.equal(slim.coverage.trimmed, false); assert.equal(slim.posts.length, 2);
  }
  // Associativity: folding pages A then B equals folding A∪B.
  {
    const rows = ledger().create(T0 - 3 * D, 5_000).engage(T0 - 3 * D + MIN, "view", 1_000, "a").engage(T0 - 3 * D + 2 * MIN, "like", 1_000, "b")
      .decayTo(T0 - 2 * D, 1_990).engage(T0 - 2 * D + MIN, "comment", 2_000, "c").decayTo(T0 - D, 3_980).rows;
    const actors = [null, actor("real"), actor("synthetic"), null, actor("owner"), null];
    const one = digest.emptyPayload(); one.postMeta.p = meta();
    rows.forEach((row, i) => digest.foldEntry(one, "p", entry(row), actors[i], foldRun()));
    const two = digest.emptyPayload(); two.postMeta.p = meta();
    rows.slice(0, 3).forEach((row, i) => digest.foldEntry(two, "p", entry(row), actors[i], foldRun()));
    rows.slice(3).forEach((row, i) => digest.foldEntry(two, "p", entry(row), actors[i + 3], foldRun()));
    assert.deepEqual(two, one);
  }
  // observedPolicyVersions appends when the 7-day signature changes; day cells carry it; source ≠ observed is surfaced.
  {
    const world = { auth: { ...AUTH }, posts: new Map(), ledgers: new Map(), engagements: new Map(), users: new Map() };
    const id = "post-tester-versions", created = T0 - 3 * D;
    const l = ledger().create(created, 5_000);
    for (let i = 0; i < 31; i++) { l.engage(created + (i + 1) * MIN, "like", 1_000, `l${i}`); world.engagements.set(`${id}/l${i}`, { actorUid: `Real${i}`, surface: "feed" }); }
    l.engage(created + 40 * MIN, "view", 1_000, "v0"); world.engagements.set(`${id}/v0`, { actorUid: TESTER_B, surface: "feed" });
    l.engage(created + 41 * MIN, "view", 500, "v1"); world.engagements.set(`${id}/v1`, { actorUid: TESTER_B, surface: "feed" });
    l.engage(created + 42 * MIN, "comment", 2_000, "c0"); world.engagements.set(`${id}/c0`, { actorUid: TESTER_B, surface: "feed" });
    l.engage(created + 43 * MIN, "dislike", -1_000, "d0"); world.engagements.set(`${id}/d0`, { actorUid: TESTER_B, surface: "feed" });
    world.posts.set(id, { data: postDoc(TESTER_A, { organic: l.state().organic }), createdAt: ts(created) });
    world.ledgers.set(id, l.rows);
    const { outcome: first } = await run(world, digest.initialState(), T0);
    assert.equal(first.state.observedPolicyVersions.length, 1);
    assert.deepEqual(first.state.observedPolicyVersions[0].signature, { view: 1_000, like: 1_000, comment: 2_000, dislike: -1_000, repeatBase: 500, seedSeen: 5_000 });
    assert.equal(first.published.sourceMatchesObserved, true);
    assert.equal(first.state.payload.days[day(created)].observedPolicy, first.state.observedPolicyVersions[0].version, "a day with ≥ 30 entries carries the version in force");
    const T1 = T0 + D;
    for (let i = 0; i < 40; i++) { l.engage(T1 - 2 * H + i * MIN, "like", 2_000, `k${i}`); world.engagements.set(`${id}/k${i}`, { actorUid: `Other${i}`, surface: "map" }); }
    const { outcome: second } = await run(world, first.state, T1);
    assert.equal(second.state.observedPolicyVersions.length, 2, "the 7-day signature changed (likes now 2,000) → a new version");
    assert.equal(second.state.observedPolicyVersions[1].fromMillis, T1);
    assert.equal(second.state.observedPolicyVersions[1].signature.like, 2_000);
    assert.equal(second.published.sourceMatchesObserved, false, "source ≠ observed is surfaced");
    assert.equal(second.state.payload.days[day(T1 - 2 * H)].observedPolicy, second.state.observedPolicyVersions[1].version);
    assert.equal(second.state.payload.days[day(created)].observedPolicy, first.state.observedPolicyVersions[0].version, "an earlier day keeps the version it was folded under");
    assert.equal(second.published.windows.d7.observedPolicySpanned.length, 2, "a window spanning two versions says so");
    const thin = second.published.days.find((row) => row.day === day(T0 - D));
    assert.equal(thin.observedPolicy, first.state.observedPolicyVersions[0].version, "a thin day inherits the previous version");
  }
}
