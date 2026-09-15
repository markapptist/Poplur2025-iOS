"use strict";

/**
 * The daily algorithm report, rendered against in-memory state: the due test,
 * idempotency, read cost, reset preservation, catch-up and backfill, amendments,
 * windows ending on D, the gate-below-never-a-number invariant, the trial line,
 * every rule of §2.5 on its constructed window, the people bound, R3/R4, R2/R6,
 * the outcome loop, the fold additions, real-vs-simulation, versions, the guard
 * and the retry-without-reports path, the index, and the no-identity pin.
 *
 *   npm run test:algorithm-report
 *
 * Design: /Users/matrix/Developer/.codex/algorithm-reports-design.md §6.
 */
const assert = require("node:assert/strict");
const path = require("node:path");

const libDir = process.argv[2] || path.resolve(__dirname, "..", "lib");
const digest = require(path.join(libDir, "algorithmDigestPolicy.js"));
const report = require(path.join(libDir, "algorithmReportPolicy.js"));
const rules = require(path.join(libDir, "algorithmReportRules.js"));
const io = require(path.join(libDir, "algorithmDigest.js"));
const policy = require(path.join(libDir, "shared", "postEngagementPolicy.js"));

const MIN = 60_000, H = 3_600_000, D = 86_400_000;
const TZ = "America/Toronto";
const MAX = policy.MAX_POST_RADIUS_METERS;
const KNOBS = digest.KNOBS;
const day = (ms) => digest.dayKey(ms, TZ);
const start = (d) => digest.dayStartMillis(d, TZ);
const approx = (actual, expected, tolerance, message) => assert.ok(Math.abs(actual - expected) <= tolerance, `${message}: ${actual} ≠ ${expected} ± ${tolerance}`);
const verdictOf = (doc, knob) => doc.verdicts.find((row) => row.knob === knob);
const kinds = (doc) => JSON.stringify(Object.fromEntries(doc.verdicts.map((row) => [row.knob, `${row.verdict}/${row.reason}`])));
const NEVER = ["K6", "K8", "K9", "K10", "K11", "K12", "K13", "K14", "K15", "K16", "K17"];
const assertNeverSuggest = (doc, label) => {
  for (const knob of NEVER) { const row = verdictOf(doc, knob); assert.notEqual(row.verdict, "suggest", `${label}: ${knob} must never suggest`); assert.equal(row.suggestion, null); }
  assert.equal(doc.decision.appliedByReport, false, `${label}: nothing is applied`);
  for (const row of doc.verdicts) if (row.suggestion) assert.ok(row.gates.filter((g) => g.id !== "Gprod").every((g) => g.sufficient), `${label}: ${row.knob} suggests under an insufficient gate`);
};

// ── Actors and switches ──────────────────────────────────────────────────
const MARK = "eoP2Z0ElxIa0Eua7xpFxNlr6tur1";
const REAL = Array.from({ length: 40 }, (_, i) => `RealActor${String(i + 1).padStart(19, "0")}`);
const [R1, R2, R3, R4, R5, R6, R7, R8, R9] = REAL;
const SYN = Array.from({ length: 8 }, (_, i) => `sim-food-00${i + 1}`);
const T_RUN = Date.UTC(2026, 8, 13, 4, 45); // 00:45 Toronto, 13 Sep → the closed day is 12 Sep
const DAY = "2026-09-12";
const switchesOff = { simulationEnabled: false, runnerEnabled: true, dailySimulationEnabled: true, simulationOwnerUid: MARK, dueDecayEnabled: true, sampledAtMillis: T_RUN,
  decayTrial: { enabled: false, multiplier: 5, scope: "all-users", effectiveAtMillis: 1788826046064, boostedEffectiveAtMillis: 1788845178241 } };
const switchesOn = { ...switchesOff, decayTrial: { ...switchesOff.decayTrial, enabled: true } };
const config = (overrides = {}) => digest.digestConfig(overrides);
const emptyLoop = () => ({ open: null, adopted: {}, withdrawn: {}, knobChanges: {} });

// ── Fixture: a payload built by folding entries directly (0 reads, no reader) ──
/** `at(daysBefore, hours)` = an instant `daysBefore` days before the base day (D unless `withBase` says otherwise) at `hours` o'clock Toronto. */
let BASE = DAY;
const at = (daysBefore, hours = 12, minutes = 0) => start(BASE) - daysBefore * D + hours * H + minutes * MIN;
function withBase(base, build) { const previous = BASE; BASE = base; try { return build(); } finally { BASE = previous; } }
function fixture(options = {}) {
  const payload = digest.emptyPayload();
  payload.coverage.kindSplitSinceMillis = options.kindSplitSinceMillis ?? 0;
  const foldRun = { knobs: options.knobs ?? KNOBS, timeZone: TZ, digestVersion: 1, touchedDays: new Set() };
  const posts = new Map();
  let seq = 0;
  const api = {
    payload,
    /** A tester post (real class, real owner) unless `cls`/`ownerClass` say otherwise; folds its create entry. */
    post(id, createdAt, o = {}) {
      const cls = o.cls ?? "r", ownerClass = o.ownerClass ?? "r";
      payload.postMeta[id] = { cls, ownerUid: o.owner ?? `Owner${id}`, ownerClass, ch: o.ch ?? "live", createdAtMillis: createdAt, lat: o.lat ?? 43.65, lng: o.lng ?? -79.38,
        hasCreate: false, cursor: null, live: true, expiredAtMillis: null, deletedAtMillis: null, viewCount: 0, viewCountAtMillis: null, lastDecayAt: null, lastOrganic: null,
        lastSeed: null, lastBoost: null, decayAnchorMillis: null, decayOrganicPerDay: null, decaySeedPerDay: null, decayBoostPerDay: null, refreshedAtMillis: null,
        docRadiusMeters: null, createFetch: null, registeredRun: 1 };
      const s = { organic: o.organic ?? 0, seed: o.seed ?? 5_000, boost: 0, lastDecayAt: null };
      posts.set(id, s);
      const entry = { id: "create", data: { atMillis: createdAt, cause: "create", writer: "radiusHistoryOnPostCreated", radiusMeters: s.seed + s.organic, organicRadiusMeters: s.organic,
        seedRadiusMeters: s.seed, boostedRadiusMeters: 0, delta: 0, organicDelta: 0 } };
      digest.foldEntry(payload, id, digest.parseEntry(entry), null, foldRun);
      return api;
    },
    /** One engagement entry with the delta the writer would have stored; the actor is resolved as `cls` with its uid. */
    engage(id, atMillis, kind, meters, uid, cls = "real") {
      const s = posts.get(id);
      const next = Math.max(0, s.organic + meters);
      const organicDelta = next - s.organic;
      const eid = `e${seq++}`;
      const entry = { id: `eng_${eid}`, data: { atMillis, cause: "engagement", writer: "recordPostEngagement", kind, engagementId: eid, radiusMeters: Math.min(MAX, s.seed + next + s.boost),
        organicRadiusMeters: next, seedRadiusMeters: s.seed, boostedRadiusMeters: s.boost, delta: organicDelta, organicDelta } };
      s.organic = next;
      digest.foldEntry(payload, id, digest.parseEntry(entry), { cls, surface: "feed", joined: true, uid }, foldRun);
      if (cls === "real" && !payload.realActorUids.includes(uid)) payload.realActorUids.push(uid);
      return api;
    },
    /** An unknown-cause organic growth (the lab's shape): books to nobody and pumps the post. */
    growth(id, atMillis, meters) {
      const s = posts.get(id);
      s.organic += meters;
      digest.foldEntry(payload, id, digest.parseEntry({ id: `lab_${atMillis}`, data: { atMillis, cause: "growth", writer: "radius-lab", radiusMeters: s.seed + s.organic, organicRadiusMeters: s.organic,
        seedRadiusMeters: s.seed, boostedRadiusMeters: 0, delta: meters, organicDelta: meters } }), null, foldRun);
      return api;
    },
    /** A decay entry at multiplier m through the shipped arithmetic, so the fold infers normal (m = 1) or trial ×m. */
    decay(id, atMillis, m = 1) {
      const s = posts.get(id);
      const from = s.lastDecayAt ?? atMillis - H;
      const next = digest.predictDecayed(s.organic, atMillis - from, m, from);
      assert.ok(next < s.organic, `fixture decay on ${id} at ${atMillis} changed nothing (${s.organic})`);
      digest.foldEntry(payload, id, digest.parseEntry({ id: `decay_${atMillis}`, data: { atMillis, cause: "decay", writer: "radiusDecay", radiusMeters: s.seed + next, organicRadiusMeters: next,
        seedRadiusMeters: s.seed, boostedRadiusMeters: 0, delta: next - s.organic, organicDelta: next - s.organic } }), null, foldRun);
      s.organic = next; s.lastDecayAt = atMillis;
      return api;
    },
    /** A stress-shaped decay (the sim's 4 h half-life): mode stress. */
    stress(id, atMillis) {
      const s = posts.get(id);
      const from = s.lastDecayAt ?? atMillis - H;
      const next = Math.floor(s.organic * 2 ** (-(atMillis - from) / (4 * H)));
      digest.foldEntry(payload, id, digest.parseEntry({ id: `decay_${atMillis}`, data: { atMillis, cause: "decay", writer: "radiusDecay", radiusMeters: s.seed + next, organicRadiusMeters: next,
        seedRadiusMeters: s.seed, boostedRadiusMeters: 0, delta: next - s.organic, organicDelta: next - s.organic } }), null, foldRun);
      s.organic = next; s.lastDecayAt = atMillis;
      return api;
    },
    organic: (id) => posts.get(id).organic,
    /** Posts created on `dayKey` by class, as the new-post sweep files them (`cell.postsCreated`, by server createdAt) —
     *  the fixture has no reader, so the feedPool check's input is written straight onto the day cell. */
    created(dayKey, counts) {
      const cell = payload.days[dayKey] ??= digest.emptyDayCell(dayKey);
      for (const [cls, n] of Object.entries(counts)) { assert.ok(cls in cell.postsCreated, `postsCreated has no class ${cls}`); cell.postsCreated[cls] += n; }
      return api;
    },
    /** Production seen paying the declared grants by synthetic actors on an OFFICIAL post: feeds M16/Gprod/drift
     *  (observe() is class-agnostic) and never a REAL figure (no realPostGain on an official post). */
    pump(o = {}) {
      const n = o.n ?? 40, id = o.id ?? "post-official-pump", daysBefore = o.daysBefore ?? 3;
      if (!posts.has(id)) api.post(id, at(daysBefore + 1), { cls: "o", ownerClass: "o", owner: "PoplurTestUid000000000000000", organic: 0, seed: 0 });
      let t = at(daysBefore, 1);
      const each = (kind, meters, count) => { for (let i = 0; i < count; i++) { api.engage(id, t, kind, meters, SYN[i % SYN.length], "synthetic"); t += MIN; } };
      each("view", o.view ?? KNOBS.firstViewMeters, o.views ?? n);
      each("like", o.like ?? KNOBS.likeMeters, o.likes ?? n);
      each("comment", o.comment ?? KNOBS.commentMeters, o.comments ?? n);
      each("view", o.repeat ?? KNOBS.repeatViewBaseMeters, o.repeats ?? n);
      each("dislike", o.dislike ?? KNOBS.dislikeMeters, o.dislikes ?? n);
      return api;
    },
  };
  return api;
}

/** renderDigest at 00:45 of D+1, then renderReport for D — the exact order runDigestFold uses. */
function renderAt(payload, dayKey, o = {}) {
  const runStart = start(report.nextDay(dayKey, TZ)) + 45 * MIN;
  const knobs = o.knobs ?? KNOBS;
  const state = { ...digest.initialState(), digestVersion: o.digestVersion ?? 1, payload, observedPolicyVersions: o.versions ?? [], lastResetAtMillis: o.lastResetAtMillis ?? 0 };
  const switches = o.switches ?? switchesOff;
  const cost = { reads: 8, writes: 3, entriesProcessed: 0, postsPolled: 0, postsWithEntries: 0, engagementJoins: 0, postLookups: 0, createFetches: 0, createSkipped: 0, sweepReads: 0, refreshReads: 0, userLookups: 0, authPages: 1, runMs: 0, budgetHit: false, capInForce: 6000 };
  const runCoverage = { postsBehindHorizon: 0, sweptPosts: 0, evicted: 0, trimmed: false, capped: false, postsDeleted: 0, registeredThisRun: 0, refreshed: true, payloadOverflow: false };
  const published = digest.renderDigest({ state, config: config(), switches, runStartMillis: runStart, runId: o.runId ?? "direct", knobs, stamp: digest.SYNC_STAMP, timeZone: TZ, cost, runCoverage });
  if (o.published) Object.assign(published, o.published);
  const render = report.renderReport({ state, published, config: config(), switches, knobs, stamp: o.stamp ?? digest.SYNC_STAMP, timeZone: TZ, day: dayKey, runStartMillis: runStart,
    runId: o.runId ?? "direct", digestVersion: o.digestVersion ?? 1, flags: o.flags ?? { partial: false, backfilled: false, catchUp: false }, revision: o.revision ?? 1, supersedes: null,
    readsOnDay: o.readsOnDay ?? null, runsOnDay: null, nonLivePollLagRuns: 0, complete: o.complete ?? true, loop: o.loop ?? emptyLoop(), last: o.last ?? null,
    lastResetAtMillis: o.lastResetAtMillis ?? 0, amendment: o.amendment ?? null });
  return { ...render, published, evidence: JSON.parse(render.document.evidence) };
}

// ── Worlds ───────────────────────────────────────────────────────────────
/** 10 tester posts aged 20 d, each viewed by R1 and R2 and liked by one of four likers (30 real events, 6 actors, max share 0.33 —
 *  four likers so K2-C, "never lower on ≤ 3 likers", does not pre-empt K2's other rules), production pumped at the declared grants. */
const LIKERS = [R3, R5, R6, R7];
function grantsWorld(o = {}) {
  const f = fixture(o);
  const n = o.posts ?? 10;
  for (let i = 0; i < n; i++) {
    const id = `post-${i}`;
    f.post(id, at(20, 12), { owner: `Tester${i}`, lat: 43.65 + i * 0.001 });
    f.engage(id, at(20, 12, 10), "view", KNOBS.firstViewMeters, R1).engage(id, at(20, 12, 20), "view", KNOBS.firstViewMeters, R2).engage(id, at(20, 12, 30), "like", KNOBS.likeMeters, LIKERS[i % 4]);
  }
  if (o.pump !== false) f.pump(o.pumpOptions ?? {});
  return f;
}
/** grantsWorld where 8 of the 10 liked posts are net-zero (three dislikes each) and two stay positive: K2-R fires → 1,250. */
function k2RaiseWorld(o = {}) {
  const f = grantsWorld(o);
  const netZero = o.netZero ?? 8;
  for (let i = 0; i < netZero; i++) for (const uid of [R1, R2, R4]) f.engage(`post-${i}`, at(19, 12, 10), "dislike", KNOBS.dislikeMeters, uid);
  return f;
}
/** A comment pump that paid 1,500 m until D−10 and 2,000 m from D−9: the rolling 7-day mode flips at B = D−6 (a production boundary inside d30). */
function boundaryPump(f, o = {}) {
  const id = "post-official-pump";
  f.post(id, at(25), { cls: "o", ownerClass: "o", owner: "PoplurTestUid000000000000000", organic: 0, seed: 0 });
  for (let d = 20; d >= 0; d--) {
    let t = at(d, 1);
    const comment = d >= 10 ? (o.oldComment ?? 1_500) : KNOBS.commentMeters;
    for (let i = 0; i < 6; i++) { f.engage(id, t, "comment", comment, SYN[i], "synthetic"); t += MIN; }
    for (let i = 0; i < 6; i++) { f.engage(id, t, "view", KNOBS.firstViewMeters, SYN[i], "synthetic"); t += MIN; f.engage(id, t, "like", KNOBS.likeMeters, SYN[i], "synthetic"); t += MIN; }
    for (let i = 0; i < 6; i++) { f.engage(id, t, "view", KNOBS.repeatViewBaseMeters, SYN[i], "synthetic"); t += MIN; f.engage(id, t, "dislike", KNOBS.dislikeMeters, SYN[i], "synthetic"); t += MIN; }
  }
  return f;
}
/** 8 viewed-only posts (2 first views at D−20, ×1 decay weekly, two passes inside `after`) — the stale-reach shape. */
function staleViewedPosts(f, o = {}) {
  const n = o.n ?? 8;
  for (let i = 0; i < n; i++) {
    const id = `post-viewed-${i}`;
    f.post(id, at(20, 12), { owner: `TesterV${i}`, lat: 43.7 + i * 0.001 });
    f.engage(id, at(20, 12, 10), "view", KNOBS.firstViewMeters, R1).engage(id, at(20, 12, 20), "view", KNOBS.firstViewMeters, R2);
    f.decay(id, at(20, 14)).decay(id, at(13, 14)).decay(id, at(5, 14)).decay(id, at(1, 14));
  }
  return f;
}

// ═══════════════════════════════════════════════════════════════════════════
(async () => {
  // ── Test 8: gate-below never a number (the n = 0 world) ──
  {
    const f = fixture();
    f.post("post-quiet", at(3), { owner: "TesterQ" });
    const { document: doc, evidence } = renderAt(f.payload, DAY, { switches: switchesOn });
    for (const knob of rules.TUNABLE_KNOBS) {
      const row = verdictOf(doc, knob);
      assert.equal(row.verdict, "insufficient", `${knob} insufficient at n = 0`);
      assert.equal(row.reason, knob === "K7" ? "trial" : "gate", `${knob} reason`);
      assert.equal(row.suggestion, null);
      for (const cell of row.evidence) if (cell.id.startsWith("M1.") && cell.unit === "m") assert.equal(cell.value, 0, "no metre value of the knob's own kind beyond the zero sum");
    }
    assert.equal(doc.decision.kind, "none");
    assert.equal(doc.decision.appliedByReport, false);
    assert.ok(doc.decision.sentence.includes("0/30") && doc.decision.sentence.includes("0/2") && doc.decision.sentence.includes("0/8"), doc.decision.sentence);
    assert.ok(doc.decision.sentence.startsWith("NO SUGGESTION TODAY."));
    assert.ok(!/\bapplied\b(?! by this report)/.test(doc.decision.sentence), "never reads as applied");
    assert.equal(evidence.metrics["share.like.d30"].value, null); assert.equal(evidence.metrics["share.like.d30"].numerator, 0); assert.equal(evidence.metrics["share.like.d30"].denominator, 0);
    assert.equal(evidence.metrics["netPos.lt7d.d30"].value, null); assert.equal(evidence.metrics["netPos.lt7d.d30"].denominator, 1);
    assert.equal(evidence.windows.d1.netReal.byAge.lt7d.perPostDay, null, "a rate over 1 post is null in the document");
    assert.equal(evidence.windows.d30.viewWorth.views, null);
    assert.equal(typeof evidence.windows.d30.netReal.byAge.lt7d.postDays, "number", "the raw sums stay");
    assert.deepEqual(doc.verdictCounts, { suggest: 0, verify: 0, hold: 0, insufficient: 7, fixed: 10 }, "refuter 19: 7 insufficient (K1–K5 gate, K6 unmeasured, K7 trial) + 10 fixed = 17");
    assert.equal(Object.values(doc.verdictCounts).reduce((a, b) => a + b, 0), 17);
    assertNeverSuggest(doc, "n = 0");
    // Rates over 2 / 3 posts are null while the sums stay (refuter 21).
    const g = fixture();
    for (let i = 0; i < 3; i++) { g.post(`p${i}`, at(2), { owner: `T${i}` }); g.payload.folds[`p${i}`].days[report.dayPlus(DAY, -1)] = { gr: 0, go: 0, gv: 0, gs: 0, gu: 0, dl: 0, dlr: 0, vc: 3 }; g.payload.folds[`p${i}`].days[DAY] = { gr: 0, go: 0, gv: 0, gs: 0, gu: 0, dl: 0, dlr: 0, vc: 9 }; }
    const two = renderAt(g.payload, DAY).evidence.windows.d1;
    assert.equal(two.netReal.byAge.lt7d.posts, 3); assert.equal(two.netReal.byAge.lt7d.perPostDay, null); assert.equal(two.viewWorth.cleanPosts, 3); assert.equal(two.viewWorth.views, null);
    assert.equal(two.viewWorth.paidViews, 0);
  }

  // ── Test 10: every rule fires on its constructed window ──
  {
    // K2-R → 1,250 with the arithmetic pinned.
    const { document: doc, loop } = renderAt(k2RaiseWorld().payload, DAY);
    const k2 = verdictOf(doc, "K2");
    assert.equal(k2.verdict, "suggest", kinds(doc));
    assert.deepEqual({ from: k2.suggestion.from, to: k2.suggestion.to, direction: k2.suggestion.direction, ruleId: k2.suggestion.ruleId }, { from: 1_000, to: 1_250, direction: "raise", ruleId: "K2-R" });
    assert.equal(k2.arithmetic, "posts.liked = 10 ≥ 8 ∧ netPosLiked(d7to30) = 2 / 10 = 0.20 < 0.50 ∧ lossRatio(d7to30) = 0 / 6,000 = 0.00 ≤ 1.50");
    assert.equal(doc.decision.kind, "suggest"); assert.equal(doc.decision.knob, "K2"); assert.equal(doc.primarySuggestion, "K2");
    assert.ok(doc.decision.sentence.startsWith("suggest raising the like grant 1,000 → 1,250 m"), doc.decision.sentence);
    assert.ok(doc.decision.sentence.includes("nothing is applied by this report; production pays 1,000 m until you deploy"), doc.decision.sentence);
    assert.deepEqual(doc.decision.action, { where: "functions/src/postEngagementPolicy.ts · radiusDelta · like literal", from: 1_000, to: 1_250, unit: "m", deploy: ["deploy recordPostEngagement", "node scripts/syncShared.js (functions-digest)", ".codex/deploy-nearby-pops-digest.sh"] });
    assert.equal(k2.productionPays, 1_000); assert.ok(k2.seenN >= 30); assert.equal(k2.seenBasis, "production · ALL actor classes incl. simulation · 7 d");
    assert.equal(verdictOf(doc, "K7").verdict, "hold"); assert.equal(verdictOf(doc, "K7").reason, "in-range");
    assert.equal(verdictOf(doc, "K1").verdict, "hold");
    assert.equal(verdictOf(doc, "K4").reason, "gate", "24 dislikes < 30");
    assert.deepEqual(loop.open, { knob: "K2", sinceDay: DAY, from: 1_000, to: 1_250, ruleId: "K2-R", direction: "raise", missedReports: 0 });
    assert.equal(k2.outcome, "open"); assert.equal(k2.openSinceDay, DAY);
    assertNeverSuggest(doc, "K2-R");
    // One event short of the gate → insufficient/gate with "29 of 30".
    const short = fixture();
    for (let i = 0; i < 10; i++) { short.post(`post-${i}`, at(20), { owner: `T${i}` }); short.engage(`post-${i}`, at(20, 13), "view", 1_000, R1).engage(`post-${i}`, at(20, 14), "view", 1_000, R2); }
    for (let i = 0; i < 9; i++) short.engage(`post-${i}`, at(20, 15), "like", 1_000, R3);
    short.pump();
    const shortDoc = renderAt(short.payload, DAY).document;
    assert.equal(verdictOf(shortDoc, "K2").reason, "gate"); assert.ok(verdictOf(shortDoc, "K2").reasonText.includes("29 of 30"), verdictOf(shortDoc, "K2").reasonText);
    // One actor supplying 70 % → insufficient/gate (maxShare 0.70 > 0.60).
    const heavy = fixture();
    for (let i = 0; i < 10; i++) { heavy.post(`post-${i}`, at(20), { owner: `T${i}` }); for (const k of ["view", "like", "comment"]) heavy.engage(`post-${i}`, at(20, 13), k, k === "comment" ? 2_000 : 1_000, R1); }
    for (let i = 0; i < 10; i++) heavy.engage(`post-${i}`, at(19, 13), "view", 1_000, R2);
    heavy.engage("post-0", at(19, 14), "view", 1_000, R3).engage("post-1", at(19, 14), "view", 1_000, R3).engage("post-2", at(19, 14), "view", 1_000, R3);
    heavy.pump();
    const heavyDoc = renderAt(heavy.payload, DAY).document;
    const gc = verdictOf(heavyDoc, "K2").gates.find((g) => g.id === "Gc");
    assert.equal(gc.n, 43); assert.equal(gc.sufficient, false); assert.ok(gc.note.includes("max share 0.70"), gc.note);
    assert.equal(verdictOf(heavyDoc, "K2").reason, "gate");
  }
  {
    // K1-L → 750 (not clamped by K5's ladder); the same fixture's K5 carries repeatLadder and K5-R is invariant-capped.
    const f = fixture();
    // 32 viewers over two days: a day cell keeps 16 uids + other, so one day would read 17 people (the conservative bound test 11 pins).
    for (let i = 0; i < 10; i++) { f.post(`post-${i}`, at(3), { owner: `T${i}` }); for (let v = 0; v < 32; v++) f.engage(`post-${i}`, at(v < 16 ? 3 : 2, 13, v), "view", 1_000, REAL[v]); }
    f.engage("post-0", at(2, 14), "like", 1_000, R1);
    f.pump();
    const { document: doc } = renderAt(f.payload, DAY);
    const k1 = verdictOf(doc, "K1");
    assert.equal(k1.verdict, "suggest", kinds(doc)); assert.equal(k1.suggestion.to, 750); assert.equal(k1.suggestion.ruleId, "K1-L");
    assert.ok(k1.arithmetic.startsWith("share.view = 320,000 / 321,000 = 1.00 ≥ 0.80 ∧ M6.lt7d.posts = 10 ≥ 8 ∧ netPos(lt7d) = 10 / 10 = 1.00 ≥ 0.90 ∧ likersPerViewer = 1 / 32 = 0.03 < 0.10"), k1.arithmetic);
    const k5 = verdictOf(doc, "K5");
    assert.equal(k5.verdict, "hold"); assert.equal(k5.reason, "invariant-capped"); assert.equal(k5.reasonText, "capped by repeatLifetime ≤ firstView");
    const ladder = k5.evidence.find((cell) => cell.id === "repeatLadder");
    assert.ok(ladder && ladder.value === 994 && ladder.label.includes("750"), JSON.stringify(ladder));
    assert.equal(doc.primarySuggestion, "K1");
    assertNeverSuggest(doc, "K1-L");
  }
  {
    // K3-L → 1,500.
    const f = fixture();
    for (let i = 0; i < 10; i++) { f.post(`post-${i}`, at(3), { owner: `T${i}` }); for (const uid of [R1, R2, R3]) f.engage(`post-${i}`, at(3, 13), "comment", 2_000, uid); f.engage(`post-${i}`, at(3, 14), "view", 1_000, R4); }
    f.pump();
    const { document: doc } = renderAt(f.payload, DAY);
    const k3 = verdictOf(doc, "K3");
    assert.equal(k3.verdict, "suggest", kinds(doc)); assert.equal(k3.suggestion.to, 1_500); assert.equal(k3.suggestion.ruleId, "K3-L");
    assert.equal(doc.primarySuggestion, "K3");
    // K2-C: three likers → hold/concentration; K2-L with four → capped by view ≤ like.
    const c = fixture();
    for (let i = 0; i < 10; i++) { c.post(`post-${i}`, at(3), { owner: `T${i}` }); for (const uid of [R1, R2, R3]) c.engage(`post-${i}`, at(3, 13), "like", 1_000, uid); c.engage(`post-${i}`, at(3, 14), "view", 1_000, R4); }
    c.pump();
    const cDoc = renderAt(c.payload, DAY).document;
    assert.equal(verdictOf(cDoc, "K2").verdict, "hold"); assert.equal(verdictOf(cDoc, "K2").reason, "concentration");
    const l = fixture();
    for (let i = 0; i < 10; i++) { l.post(`post-${i}`, at(3), { owner: `T${i}` }); for (const uid of [R1, R2, R3, R4]) l.engage(`post-${i}`, at(3, 13), "like", 1_000, uid); l.engage(`post-${i}`, at(3, 14), "view", 1_000, R5); }
    l.pump();
    const lDoc = renderAt(l.payload, DAY).document;
    assert.equal(verdictOf(lDoc, "K2").verdict, "hold"); assert.equal(verdictOf(lDoc, "K2").reason, "invariant-capped"); assert.equal(verdictOf(lDoc, "K2").reasonText, "capped by view ≤ like");
    assert.equal(verdictOf(lDoc, "K2").rule.id, "K2-L");
    assertNeverSuggest(lDoc, "K2-L");
  }
  {
    // K4-L → −750 via clampedDislikes / clampedDislikeMeters: 12 clamped at −300 + 24 full → n 36, clamped share 0.33.
    const f = fixture();
    for (let i = 0; i < 12; i++) { f.post(`post-c${i}`, at(20), { owner: `TC${i}` }); f.growth(`post-c${i}`, at(20, 13), 300); f.engage(`post-c${i}`, at(20, 14), "dislike", -1_000, R1); }
    for (let i = 0; i < 8; i++) { f.post(`post-f${i}`, at(20), { owner: `TF${i}` }); for (const uid of [R2, R3, R4]) f.engage(`post-f${i}`, at(20, 13), "view", 1_000, uid); for (const uid of [R1, R5, R6]) f.engage(`post-f${i}`, at(20, 14), "dislike", -1_000, uid); }
    f.pump();
    const { document: doc, evidence } = renderAt(f.payload, DAY);
    const gain = evidence.windows.d30.realPostGain.real;
    assert.equal(gain.clampedDislikes, 12); assert.equal(gain.clampedDislikeMeters, -3_600); assert.equal(gain.dislike, -27_600);
    assert.equal(evidence.metrics["dislike.n.d30"].value, 36, "12 + (27,600 − 3,600) / 1,000");
    const k4 = verdictOf(doc, "K4");
    assert.equal(k4.verdict, "suggest", kinds(doc)); assert.equal(k4.suggestion.to, -750); assert.equal(k4.suggestion.ruleId, "K4-L");
    assert.ok(k4.arithmetic.startsWith("dislike.clampedShare = 12 / 36 = 0.33 ≥ 0.30"), k4.arithmetic);
    assert.equal(doc.primarySuggestion, "K4");
    // Pre-counter path (window not accrued): exact when no clamp exists, unmeasured when one does — and never a gate's n.
    const stamp = at(10);
    const g = fixture({ kindSplitSinceMillis: stamp });
    for (let i = 0; i < 8; i++) { g.post(`post-${i}`, at(20), { owner: `T${i}` }); for (const uid of [R1, R2]) g.engage(`post-${i}`, at(20, 13), "view", 1_000, uid); for (const uid of [R1, R2]) g.engage(`post-${i}`, at(20, 14), "dislike", -1_000, uid); }
    g.pump();
    const exact = renderAt(g.payload, DAY);
    assert.equal(exact.evidence.windows.d30.realPostGain.real.clamped, 0);
    assert.equal(exact.evidence.metrics["dislike.n.d30"].value, 16, "no clamp → |dislike m| / 1,000 is exact");
    assert.equal(verdictOf(exact.document, "K4").reason, "kind-split-unavailable", "the window straddles the stamp");
    g.growth("post-0", at(19, 13), 300); g.engage("post-0", at(19, 14), "dislike", -1_000, R3);
    const unmeasured = renderAt(g.payload, DAY);
    assert.equal(unmeasured.evidence.metrics["dislike.n.d30"].value, null);
    assert.equal(verdictOf(unmeasured.document, "K4").reason, "unmeasured");
    assert.equal(verdictOf(unmeasured.document, "K4").gates.find((gate) => gate.id === "Gdislike").n, 0, "the lower bound is never the gate's n");
    assert.equal(verdictOf(unmeasured.document, "K4").evidence.find((cell) => cell.id === "dislike.lowerBound.d30").value, 16, "round(16,300 / 1,000)");
  }
  {
    // K5-L → 400 (lifetime 797) only with ≥ 8 tester posts engaged in W; 2 posts by 2 people is insufficient/gate with Gd 2/8.
    const build = (posts) => {
      const f = fixture();
      const ladder = [500, 250, 125, 62, 31];
      for (let i = 0; i < posts; i++) {
        f.post(`post-${i}`, at(20), { owner: `T${i}` });
        for (const uid of [R1, R2]) { f.engage(`post-${i}`, at(20, 13), "view", 1_000, uid); ladder.forEach((m, k) => f.engage(`post-${i}`, at(20, 14, k), "view", m, uid)); }
      }
      f.pump();
      return renderAt(f.payload, DAY);
    };
    const ten = build(10);
    const k5 = verdictOf(ten.document, "K5");
    assert.equal(k5.verdict, "suggest", kinds(ten.document)); assert.equal(k5.suggestion.to, 400); assert.equal(k5.suggestion.ruleId, "K5-L");
    assert.ok(k5.reasonText.includes("(lifetime 797 m)"), k5.reasonText);
    assert.equal(ten.evidence.metrics["repeatDepth.d30"].value, 50);
    const two = build(2);
    const k5two = verdictOf(two.document, "K5");
    assert.equal(k5two.verdict, "insufficient"); assert.equal(k5two.reason, "gate");
    assert.ok(k5two.reasonText.includes("Gd 2/8"), k5two.reasonText);
    assert.equal(k5two.gates.find((g) => g.id === "Gc").n, 24, "12 entries per actor per post × 2 × 2 — Gc alone would not stop it");
  }
  {
    // A production boundary (comment 1,500 → 2,000 at B = D−6) makes W = after; K3 is frozen; K1-R fires and is capped.
    const f = fixture();
    boundaryPump(f);
    staleViewedPosts(f);
    for (let i = 0; i < 8; i++) {
      const id = `post-liked-${i}`;
      f.post(id, at(20, 12), { owner: `TesterL${i}`, lat: 43.8 + i * 0.001 });
      f.engage(id, at(3, 13), "view", 1_000, R1).engage(id, at(3, 13, 1), "view", 1_000, R2).engage(id, at(3, 13, 2), "like", 1_000, R3).engage(id, at(3, 13, 3), "comment", 2_000, R4);
    }
    const { document: doc, evidence } = renderAt(f.payload, DAY);
    const B = report.dayPlus(DAY, -6);
    assert.equal(doc.epochs.length, 2, JSON.stringify(doc.epochs));
    assert.equal(doc.epochs[0].boundaryCause, "window-start");
    assert.deepEqual({ cause: doc.epochs[1].boundaryCause, from: doc.epochs[1].fromDay, moved: doc.epochs[1].movedFields }, { cause: "grant", from: B, moved: ["comment"] });
    assert.equal(evidence.windows.after.days, 7); assert.equal(evidence.windows.before.days, 7);
    assert.deepEqual(evidence.windows.after.spanned, [doc.epochs[1].id]); assert.equal(evidence.windows.d30.spanned.length, 2);
    const k3 = verdictOf(doc, "K3");
    assert.equal(k3.verdict, "hold"); assert.equal(k3.reason, "changed-recently"); assert.equal(k3.frozenUntilDay, report.dayPlus(B, 30));
    const k7 = verdictOf(doc, "K7");
    assert.equal(`${k7.verdict}/${k7.reason}`, "hold/in-range", JSON.stringify([k7.reasonText, k7.gates]));
    const k1 = verdictOf(doc, "K1");
    assert.equal(`${k1.verdict}/${k1.reason}`, "hold/invariant-capped", kinds(doc));
    assert.equal(k1.reasonText, "capped by view ≤ like"); assert.ok(!k1.reasonText.includes("K2"), "never a cross-knob imperative");
    assert.equal(k1.rule.id, "K1-R");
    assert.ok(k1.evidence.some((cell) => cell.id === "M1.gain.after"), "judged on the window after B");
    assert.equal(doc.decision.kind, "none");
    // Three days after B every windowed knob is epoch-young and K3 stays frozen.
    const young = renderAt(f.payload, report.dayPlus(B, 3)).document;
    for (const knob of ["K1", "K2", "K4", "K5", "K7"]) assert.equal(`${verdictOf(young, knob).verdict}/${verdictOf(young, knob).reason}`, "insufficient/epoch-young", knob);
    assert.ok(verdictOf(young, "K1").reasonText.includes(`resumes ${report.dayPlus(B, 6)}`), verdictOf(young, "K1").reasonText);
    assert.equal(verdictOf(young, "K3").reason, "changed-recently");
    assertNeverSuggest(doc, "boundary");
  }
  {
    // K7-L → 0.04 on `after`: 8 stale viewed posts decaying, 32 one-metre repeats by two people so Gc/Gd pass; K5-L fires too and defers (K7 outranks).
    const f = fixture();
    boundaryPump(f, { oldComment: KNOBS.commentMeters }); // no boundary from the pump itself
    f.pump({ id: "post-official-pump-2" });
    // A trial boundary: real-post decay ran at ×5 until D−7 and at ×1 from D−6. The post is pumped to 2,000 km of
    // (unknown-class) organic so every daily pass stays above the 468 m informative floor and out-votes the viewed posts' normal passes.
    const trialPost = "post-trialled";
    f.post(trialPost, at(28), { owner: "TesterT" }); f.engage(trialPost, at(28, 13), "view", 1_000, R1).engage(trialPost, at(28, 13, 1), "view", 1_000, R2).engage(trialPost, at(28, 13, 2), "comment", 2_000, R3).engage(trialPost, at(28, 13, 3), "like", 1_000, R4).engage(trialPost, at(28, 13, 4), "like", 1_000, R5);
    f.growth(trialPost, at(28, 13, 5), 2_000_000);
    f.decay(trialPost, at(28, 15)); for (let d = 27; d >= 7; d--) f.decay(trialPost, at(d, 15), 5);
    for (let d = 6; d >= 0; d--) f.decay(trialPost, at(d, 15), 1);
    staleViewedPosts(f);
    for (let i = 0; i < 8; i++) for (const uid of [R1, R2]) for (let k = 0; k < 2; k++) f.engage(`post-viewed-${i}`, at(3, 13, k), "view", 1, uid);
    const { document: doc, evidence } = renderAt(f.payload, DAY);
    const B = report.dayPlus(DAY, -6);
    const trialEpoch = doc.epochs.find((epoch) => epoch.boundaryCause === "trial");
    assert.ok(trialEpoch && trialEpoch.fromDay === B, JSON.stringify(doc.epochs));
    assert.equal(evidence.days.find((row) => row.day === report.dayPlus(B, -1)).trialClass, "trial");
    assert.equal(evidence.days.find((row) => row.day === B).trialClass, "normal");
    const k7 = verdictOf(doc, "K7");
    assert.equal(k7.verdict, "insufficient", "the d30 window still carries ×5 loss — K7 waits whatever `after` says");
    assert.equal(k7.reason, "trial");
    assert.ok(k7.reasonText.includes("30-day window still mixed with trial loss"), k7.reasonText);
    assert.equal(evidence.windows.after.realPostDecayLoss.byMode.trial, 0, "after is clean");
    assert.ok(evidence.metrics["trialShare.d30"].value >= 0.1);
    for (const knob of ["K1", "K2", "K4", "K5"]) assert.ok(verdictOf(doc, knob).evidence.some((cell) => cell.id === "M1.gain.after"), `${knob} is judged on after, never on the straddling d30`);
    const k5 = verdictOf(doc, "K5");
    assert.equal(`${k5.verdict}/${k5.reason}`, "suggest/in-range", kinds(doc));
    assert.equal(k5.suggestion.to, 400);
    assert.equal(doc.firstLine.slice(0, 22), "Decay ×1 · no trial · ");
    assert.ok(doc.firstLine.includes("30-day window still mixed with trial loss"), doc.firstLine);
    assertNeverSuggest(doc, "trial end");
  }
  {
    // K7-L on a clean `after` (comment boundary): every viewed post net-negative, loss ≫ the 32 m of repeats → 0.04; curve slower than today's; K5-L defers behind K7 (R3).
    const f = fixture();
    boundaryPump(f);
    staleViewedPosts(f);
    for (let i = 0; i < 8; i++) for (const uid of [R1, R2]) for (let k = 0; k < 2; k++) f.engage(`post-viewed-${i}`, at(3, 13, k), "view", 1, uid);
    const { document: doc, evidence } = renderAt(f.payload, DAY);
    const k7 = verdictOf(doc, "K7");
    assert.equal(k7.verdict, "suggest", kinds(doc)); assert.equal(k7.suggestion.to, 0.04); assert.equal(k7.suggestion.ruleId, "K7-L");
    assert.ok(k7.curveAtSuggested.daysToFloor["1000"] > 29.8, JSON.stringify(k7.curveAtSuggested.daysToFloor));
    assert.ok(k7.curveAtSuggested.daysToFloor["1000"] > k7.curveCurrent.daysToFloor["1000"]);
    assert.equal(doc.primarySuggestion, "K7");
    const k5 = verdictOf(doc, "K5");
    assert.equal(`${k5.verdict}/${k5.reason}`, "hold/deferred"); assert.deepEqual(k5.deferred, { to: 400, ruleId: "K5-L" });
    assert.deepEqual(doc.decision.deferred, [{ knob: "K5", to: 400, ruleId: "K5-L" }]);
    assert.ok(evidence.metrics["lossRatio.d7to30.after"].value > 1.5);
    // K1-R is false here: decay IS the explanation (lossRatio > 1.5).
    assert.equal(verdictOf(doc, "K1").verdict, "hold"); assert.equal(verdictOf(doc, "K1").reason, "in-range");
    assertNeverSuggest(doc, "K7-L");
    // Both K7 triggers true (8 stale clean posts join) → hold/conflicting-evidence, and K7hold is false so no raise can ride it.
    for (let i = 0; i < 8; i++) {
      const id = `post-stale-${i}`;
      f.post(id, at(40), { owner: `TesterS${i}`, lat: 43.9 + i * 0.001 });
      for (const uid of [R1, R2, R3, R4]) f.engage(id, at(40, 13), "view", 1_000, uid);
      f.decay(id, at(40, 15)); for (let d = 33; d >= 5; d -= 7) f.decay(id, at(d, 15));
    }
    f.post("post-pumped", at(10), { owner: "TesterP" }); f.engage("post-pumped", at(10, 13), "view", 1_000, SYN[0], "synthetic");
    const conflict = renderAt(f.payload, DAY);
    const k7c = verdictOf(conflict.document, "K7");
    assert.equal(`${k7c.verdict}/${k7c.reason}`, "hold/conflicting-evidence", kinds(conflict.document));
    assert.ok(k7c.arithmetic.includes("K7-L:") && k7c.arithmetic.includes("K7-R:"), k7c.arithmetic);
    assert.equal(conflict.evidence.metrics["posts.liveTesterClean468"].value, 16, "a cohort-pumped post with pool.real 0 never counts");
    assert.equal(conflict.evidence.metrics["stale.share"].value, 0.5);
    const evalResult = rules.evaluateKnobs === undefined ? null : null; void evalResult;
  }
  {
    // K7-R → 0.06 only on clean, stale posts.
    const f = fixture();
    boundaryPump(f, { oldComment: KNOBS.commentMeters });
    for (let i = 0; i < 8; i++) { f.post(`post-fresh-${i}`, at(20), { owner: `TF${i}` }); for (const uid of [R1, R2, R3, R4]) f.engage(`post-fresh-${i}`, at(20, 13), "view", 1_000, uid); }
    for (let i = 0; i < 8; i++) {
      const id = `post-stale-${i}`;
      f.post(id, at(40), { owner: `TS${i}`, lat: 43.9 + i * 0.001 });
      for (const uid of [R1, R2, R3, R4]) f.engage(id, at(40, 13), "view", 1_000, uid);
      f.decay(id, at(40, 15)); for (let d = 33; d >= 5; d -= 7) f.decay(id, at(d, 15));
    }
    f.post("post-pumped", at(10), { owner: "TesterP" }); f.engage("post-pumped", at(10, 13), "view", 1_000, SYN[0], "synthetic");
    const { document: doc, evidence } = renderAt(f.payload, DAY);
    const k7 = verdictOf(doc, "K7");
    assert.equal(`${k7.verdict}/${k7.reason}`, "suggest/in-range", kinds(doc)); assert.equal(k7.suggestion.to, 0.06); assert.equal(k7.suggestion.ruleId, "K7-R");
    assert.equal(evidence.metrics["posts.liveTesterClean468"].value, 16); assert.equal(evidence.metrics["stale.count"].value, 8);
    assert.equal(verdictOf(doc, "K9").verdict, "hold"); assert.equal(verdictOf(doc, "K9").reason, "owner-fixed");
    assert.ok(verdictOf(doc, "K9").evidence.some((cell) => cell.id === "M4.nearMissPairs" && typeof cell.value === "number"), "the seedReach finding carries nearMissPairs");
    assert.equal(doc.checks.find((check) => check.id === "seedReach").status, "finding");
    // Catch-up: the snapshot-dependent K7 is insufficient/backfilled; the seedReach finding says so.
    const catchUp = renderAt(f.payload, DAY, { flags: { partial: false, backfilled: false, catchUp: true } }).document;
    assert.equal(`${verdictOf(catchUp, "K7").verdict}/${verdictOf(catchUp, "K7").reason}`, "insufficient/backfilled");
    assert.equal(catchUp.catchUp, true); assert.equal(typeof catchUp.snapshotsAsOfMillis, "number");
    // K7-R's third trigger is `M6.gt30d.gainRealMeters = 0`, never `≤ 0`: one real dislike on a > 30 d post drives the
    // signed sum negative — real engagement on an old post — so K7-R must NOT fire even with stale.share still ≥ 0.5
    // (two more stale posts keep it there; the disliked post's real pool hits 0 and leaves liveTesterClean468).
    for (let i = 8; i < 10; i++) {
      const id = `post-stale-${i}`;
      f.post(id, at(40), { owner: `TS${i}`, lat: 43.9 + i * 0.001 });
      for (const uid of [R1, R2, R3, R4]) f.engage(id, at(40, 13), "view", 1_000, uid);
      f.decay(id, at(40, 15)); for (let d = 33; d >= 5; d -= 7) f.decay(id, at(d, 15));
    }
    f.engage("post-stale-0", at(3, 13), "dislike", KNOBS.dislikeMeters, R3);
    const disliked = renderAt(f.payload, DAY);
    assert.ok(disliked.evidence.metrics["M6.gt30d.gainRealMeters.d30"].value < 0, String(disliked.evidence.metrics["M6.gt30d.gainRealMeters.d30"].value));
    assert.equal(disliked.evidence.metrics["posts.liveTesterClean468"].value, 17); assert.equal(disliked.evidence.metrics["stale.count"].value, 9);
    assert.ok(disliked.evidence.metrics["stale.share"].value >= 0.5, "stale.share alone would still let K7-R through");
    const k7d = verdictOf(disliked.document, "K7");
    assert.equal(`${k7d.verdict}/${k7d.reason}`, "hold/in-range", kinds(disliked.document));
    assert.ok(/K7-R: .*M6\.gt30d\.gainRealMeters = -\d[\d,]* = 0$/.test(k7d.arithmetic), k7d.arithmetic);
    assert.equal(k7d.suggestion, null); assert.equal(disliked.document.decision.kind, "none");
    // Adoption freeze and the reversal guard on K2 (R4-style).
    const raise = k2RaiseWorld().payload;
    const frozen = renderAt(raise, DAY, { loop: { ...emptyLoop(), adopted: { K2: { day: report.dayPlus(DAY, -10), direction: "raise" } } } }).document;
    assert.equal(`${verdictOf(frozen, "K2").verdict}/${verdictOf(frozen, "K2").reason}`, "hold/changed-recently");
    assert.equal(verdictOf(frozen, "K2").frozenUntilDay, report.dayPlus(DAY, 20));
    const lower = fixture();
    for (let i = 0; i < 10; i++) { lower.post(`post-${i}`, at(3), { owner: `T${i}` }); for (const uid of [R1, R2, R3, R4]) lower.engage(`post-${i}`, at(3, 13), "like", 1_250, uid); lower.engage(`post-${i}`, at(3, 14), "view", 1_000, R5); }
    lower.pump({ like: 1_250 });
    const reversal = renderAt(lower.payload, DAY, { knobs: { ...KNOBS, likeMeters: 1_250 }, loop: { ...emptyLoop(), adopted: { K2: { day: report.dayPlus(DAY, -40), direction: "raise" } } }, }).document;
    assert.equal(`${verdictOf(reversal, "K2").verdict}/${verdictOf(reversal, "K2").reason}`, "hold/reversal-guard", kinds(reversal));
  }

  // ── Test 9: trial first ──
  {
    const f = k2RaiseWorld();
    const on = renderAt(f.payload, DAY, { switches: switchesOn });
    assert.ok(on.document.firstLine.startsWith("DECAY TRIAL ×5 ON since 8 Sep 00:07Z (boost path since 8 Sep 05:26Z)"), on.document.firstLine);
    assert.ok(on.document.firstLine.includes(`Seen on ${DAY}: none — no decay entry on a real post folded that day`), on.document.firstLine);
    assert.equal(on.document.trialOnDay, true); assert.equal(on.document.trialMultiplierOnDay, 5); assert.equal(on.document.headline.trialSeenOnDay, null);
    const k7 = verdictOf(on.document, "K7");
    assert.equal(`${k7.verdict}/${k7.reason}`, "insufficient/trial", "even with 54 real events");
    assert.equal(verdictOf(on.document, "K8").reason, "finding"); assert.equal(verdictOf(on.document, "K10").reason, "finding"); assert.equal(verdictOf(on.document, "K9").reason, "owner-fixed");
    assert.equal(verdictOf(on.document, "K14").reason, "experiment-switch"); assert.equal(on.document.decision.ownerQuestion, "is the ×5 trial a decision or an incident? (K14)");
    // A grant raise never fires while K7hold is false: the K2-R world stays hold with the note.
    const k2 = verdictOf(on.document, "K2");
    assert.equal(`${k2.verdict}/${k2.reason}`, "hold/in-range", kinds(on.document));
    assert.ok(k2.reasonText.includes("K7hold false"), k2.reasonText);
    assert.equal(on.document.decision.kind, "none");
    assert.equal(on.document.checks.find((check) => check.id === "seedReach").status, "hidden");
    // An OPEN K7 suggestion with the switch on: insufficient/trial (not hold/open), restated beneath, the clock frozen.
    const openK7 = { open: { knob: "K7", sinceDay: report.dayPlus(DAY, -3), from: 0.05, to: 0.04, ruleId: "K7-L", direction: "lower", missedReports: 1 }, adopted: {}, withdrawn: {}, knobChanges: {} };
    const held = renderAt(f.payload, DAY, { switches: switchesOn, loop: openK7 });
    assert.equal(`${verdictOf(held.document, "K7").verdict}/${verdictOf(held.document, "K7").reason}`, "insufficient/trial");
    assert.deepEqual(held.document.decision.open, [{ knob: "K7", to: 0.04, ruleId: "K7-L", openSinceDay: report.dayPlus(DAY, -3), outcome: "open", missedReports: 1 }]);
    assert.equal(held.loop.open.missedReports, 1, "the withdrawal clock does not run while the rule cannot be judged");
    assert.equal(held.document.decision.kind, "suggest", "the card keeps the open knob");
    assert.equal(held.document.decision.knob, "K7");
    assert.ok(held.document.decision.sentence.includes("open since"), held.document.decision.sentence);
    // Switch off but the 30-day window carries trial loss → K7 insufficient/trial, and a d30-judged grant is insufficient/trial too (Gtrial).
    const g = grantsWorld();
    g.post("post-trialled", at(25), { owner: "TesterT" });
    for (const uid of [R1, R2, R3, R4]) g.engage("post-trialled", at(25, 13), "view", 1_000, uid);
    g.growth("post-trialled", at(25, 13, 5), 2_000_000);
    g.decay("post-trialled", at(25, 15)); for (let d = 24; d >= 0; d--) g.decay("post-trialled", at(d, 15), 5);
    const off = renderAt(g.payload, DAY, { switches: switchesOff });
    assert.ok(off.evidence.metrics["trialShare.d30"].value >= 0.1, String(off.evidence.metrics["trialShare.d30"].value));
    assert.equal(`${verdictOf(off.document, "K7").verdict}/${verdictOf(off.document, "K7").reason}`, "insufficient/trial");
    for (const knob of ["K1", "K2", "K3", "K5"]) assert.equal(`${verdictOf(off.document, knob).verdict}/${verdictOf(off.document, knob).reason}`, "insufficient/trial", `${knob} (refuter 11)`);
    assert.equal(off.document.trialOnDay, true, "the day's own cells saw ×5 — per DAY, never the switch alone");
    assert.ok(off.document.firstLine.startsWith("DECAY TRIAL ×5 ON since"), off.document.firstLine);
    // Gtrial(W) holds for K7 too (refuter 11): a grant boundary at B = D−6 makes W = after (7 d); the d30 share is < 10 %
    // (heavy normal-mode loss before B) while `after` is mostly stress loss on a real post — stress votes for no trial class,
    // so no trial boundary is minted and only Gtrial(after) can stop K7. Its counted gates all hold on `after`, so the
    // K7-L shape below would otherwise fire on stress-inflated lossRatio.
    const s = fixture();
    boundaryPump(s);
    s.post("post-big", at(28), { owner: "TesterB" }); for (const uid of [R1, R2, R3, R4]) s.engage("post-big", at(28, 13), "view", 1_000, uid);
    s.growth("post-big", at(28, 13, 5), 2_000_000);
    s.decay("post-big", at(28, 15)); for (let d = 27; d >= 7; d--) s.decay("post-big", at(d, 15), 1);
    s.post("post-s", at(4), { owner: "TesterS" }); for (const uid of [R1, R2]) s.engage("post-s", at(4, 13), "view", 1_000, uid);
    s.growth("post-s", at(4, 13, 5), 200_000); s.stress("post-s", at(3, 13));
    staleViewedPosts(s);
    for (let i = 0; i < 8; i++) for (const uid of [R1, R2]) for (let k = 0; k < 2; k++) s.engage(`post-viewed-${i}`, at(3, 13, k), "view", 1, uid);
    const stressed = renderAt(s.payload, DAY, { switches: switchesOff });
    assert.equal(stressed.document.epochs.find((epoch) => epoch.boundaryCause === "grant").fromDay, report.dayPlus(DAY, -6));
    assert.equal(stressed.document.epochs.some((epoch) => epoch.boundaryCause === "trial"), false, "stress loss mints no trial boundary");
    assert.equal(stressed.evidence.windows.after.days, 7);
    assert.ok(stressed.evidence.metrics["trialShare.d30"].value < 0.1, String(stressed.evidence.metrics["trialShare.d30"].value));
    assert.ok(stressed.evidence.metrics["trialShare.after"].value >= 0.1, String(stressed.evidence.metrics["trialShare.after"].value));
    assert.equal(stressed.document.trialOnDay, false);
    const k7s = verdictOf(stressed.document, "K7");
    assert.equal(`${k7s.verdict}/${k7s.reason}`, "insufficient/trial", kinds(stressed.document));
    assert.ok(k7s.reasonText.startsWith("window after carries") && k7s.reasonText.includes("(Gtrial)"), k7s.reasonText);
    assert.ok(k7s.gates.filter((g) => g.id !== "Gprod").every((g) => g.sufficient), "Gc/Gd/Gage hold on `after` — Gtrial alone stopped K7");
    assert.ok(k7s.evidence.some((cell) => cell.id === "M1.gain.after"), "judged on `after`");
    assert.equal(k7s.suggestion, null);
    for (const knob of ["K1", "K2", "K4", "K5"]) assert.equal(`${verdictOf(stressed.document, knob).verdict}/${verdictOf(stressed.document, knob).reason}`, "insufficient/trial", knob);
    assert.equal(stressed.document.decision.kind, "none");
    assertNeverSuggest(stressed.document, "Gtrial(after) on K7");
  }

  // ── Test 11: people bound ──
  {
    const f = fixture();
    const ladder = [500, 250, 125];
    for (let i = 0; i < 18; i++) { f.post(`post-${i}`, at(20), { owner: `T${i}` }); f.engage(`post-${i}`, at(4 + (i % 4), 13), "like", 1_000, R1); }
    for (const [k, uid] of [R2, R3, R4].entries()) { f.engage(`post-${k}`, at(3, 13), "view", 1_000, uid); ladder.forEach((m, j) => f.engage(`post-${k}`, at(3, 14, j), "view", m, uid)); }
    f.pump();
    const { document: doc, evidence } = renderAt(f.payload, DAY);
    assert.equal(evidence.metrics["M3.likersDay.d30"].value, 18, "day-distinct sum");
    assert.equal(evidence.metrics["M3.actorsW.d30"].value, 4); assert.equal(evidence.metrics["M3.likersW.d30"].value, 1); assert.equal(evidence.metrics["maxShare.d30"].value, 0.6);
    assert.equal(evidence.metrics["M3.likersDay.d30"].gate, null, "gates nothing");
    const k2 = verdictOf(doc, "K2");
    assert.equal(`${k2.verdict}/${k2.reason}`, "hold/concentration", kinds(doc));
    assert.ok(k2.evidence.find((cell) => cell.id === "M3.likersDay.d30").label === "(day-distinct)");
    // A lifetime second actor outside W leaves actorsW = 1 while lifetime M3.actors = 2.
    const g = fixture();
    for (let i = 0; i < 10; i++) { g.post(`post-${i}`, at(20), { owner: `T${i}` }); for (const k of ["view", "like", "comment"]) g.engage(`post-${i}`, at(20, 13), k, k === "comment" ? 2_000 : 1_000, R1); }
    g.post("post-old", at(40), { owner: "TO" }); g.engage("post-old", at(40, 13), "view", 1_000, R9);
    g.pump();
    const gDoc = renderAt(g.payload, DAY);
    assert.equal(gDoc.evidence.metrics["M3.actorsW.d30"].value, 1); assert.equal(gDoc.evidence.metrics["M3.actors"].value, 2);
    assert.ok(gDoc.evidence.metrics["M3.actors"].basis.includes("lifetime"));
    assert.equal(verdictOf(gDoc.document, "K2").reason, "gate");
    assert.equal(verdictOf(gDoc.document, "K2").gates.find((gate) => gate.id === "Gc").sufficient, false);
    // 17 distinct likers on one day fold as 16 keys + other and read 17; 20 read 17 too; other is one person's share.
    const h = fixture();
    for (let i = 0; i < 17; i++) { h.post(`post-${i}`, at(2), { owner: `T${i}` }); }
    for (let i = 0; i < 17; i++) h.engage(`post-${i}`, at(2, 13, i), "like", 1_000, REAL[i]);
    const cell = h.payload.days[day(at(2, 13))];
    assert.equal(Object.keys(cell.realActorEntries).length, 17); assert.ok("other" in cell.realActorEntries);
    assert.equal(renderAt(h.payload, DAY).evidence.metrics["M3.likersW.d30"].value, 17);
    for (let i = 17; i < 20; i++) h.engage(`post-${i % 17}`, at(2, 14, i), "like", 1_000, REAL[i]);
    const twenty = renderAt(h.payload, DAY).evidence;
    assert.equal(twenty.metrics["M3.likersW.d30"].value, 17, "a lower bound — conservative for every ≥ floor");
    assert.equal(twenty.metrics["maxShare.d30"].value, 0.2, "other's aggregate (4 of 20) is one person's share");
    assert.equal(twenty.days.at(-1).people.likers, 0); assert.equal(twenty.days.find((row) => row.day === day(at(2, 13))).people.likers, 17);
  }

  // ── Test 12: R3 / R4 ──
  {
    // K2-R and K5-L fire: exactly one suggest, the other deferred; the next day the card stays with the open knob.
    const f = k2RaiseWorld();
    const ladder = [500, 250, 125, 62, 31];
    for (const id of ["post-8", "post-9"]) for (const uid of [R1, R2]) ladder.forEach((m, k) => f.engage(id, at(18, 13, k), "view", m, uid));
    const first = renderAt(f.payload, DAY);
    assert.equal(first.document.primarySuggestion, "K2", kinds(first.document));
    assert.equal(`${verdictOf(first.document, "K5").verdict}/${verdictOf(first.document, "K5").reason}`, "hold/deferred");
    assert.deepEqual(verdictOf(first.document, "K5").deferred, { to: 400, ruleId: "K5-L" });
    assert.equal(first.document.verdicts.filter((row) => row.verdict === "suggest").length, 1);
    assert.equal(first.loop.open.knob, "K2");
    const next = renderAt(f.payload, report.dayPlus(DAY, 1), { loop: first.loop, last: first.memo });
    assert.equal(next.document.primarySuggestion, "K2", "sticky"); assert.equal(next.document.decision.knob, "K2");
    assert.equal(`${verdictOf(next.document, "K2").verdict}/${verdictOf(next.document, "K2").reason}`, "hold/open");
    assert.equal(`${verdictOf(next.document, "K5").verdict}/${verdictOf(next.document, "K5").reason}`, "hold/deferred");
    assert.equal(next.loop.open.knob, "K2");
    assert.equal(next.document.previous.day, DAY);
    assert.ok(next.document.previous.verdictChanges.some((change) => change.knob === "K2" && change.from.verdict === "suggest" && change.to.verdict === "hold"));
    // Grants ordered by real n: five commenters beat four likers, so K3-R leads and K2-R defers.
    const g = fixture();
    const COMMENTERS = [R4, R9, REAL[10], REAL[11], REAL[12]];
    for (let i = 0; i < 10; i++) {
      g.post(`post-${i}`, at(20), { owner: `T${i}` });
      g.engage(`post-${i}`, at(20, 13), "view", 1_000, R1).engage(`post-${i}`, at(20, 13, 1), "view", 1_000, R2).engage(`post-${i}`, at(20, 13, 2), "like", 1_000, LIKERS[i % 4]).engage(`post-${i}`, at(20, 13, 3), "comment", 2_000, COMMENTERS[i % 5]);
    }
    for (let i = 0; i < 8; i++) for (const uid of [R1, R2, R5, R6, R7, R8]) g.engage(`post-${i}`, at(19, 13), "dislike", -1_000, uid);
    g.pump();
    const ordered = renderAt(g.payload, DAY).document;
    assert.equal(ordered.primarySuggestion, "K3", kinds(ordered));
    assert.equal(verdictOf(ordered, "K3").suggestion.to, 2_500);
    assert.equal(`${verdictOf(ordered, "K2").verdict}/${verdictOf(ordered, "K2").reason}`, "hold/deferred"); assert.equal(verdictOf(ordered, "K2").deferred.to, 1_250);
    assertNeverSuggest(ordered, "ordered");
  }

  // ── Test 13: R2 / R6 ──
  {
    // A lone dislike mints no boundary; a seedSeen flicker (one tester create, seven quiet days) mints none either.
    const f = grantsWorld();
    f.engage("post-0", at(15, 13), "dislike", -1_000, R4);
    f.post("post-newborn", at(10), { owner: "TesterN" });
    const { document: doc, evidence } = renderAt(f.payload, DAY);
    assert.equal(doc.epochs.length, 1, JSON.stringify(doc.epochs)); assert.equal(evidence.windows.d30.spanned.length, 1);
    // A ×5 → ×3 change between two trial days mints a boundary; stress/undetermined-only days are trialClass null and mint none.
    const g = grantsWorld();
    g.post("post-t", at(28), { owner: "TesterT" }); for (const uid of [R1, R2, R3, R4]) g.engage("post-t", at(28, 13), "view", 1_000, uid);
    g.growth("post-t", at(28, 13, 5), 2_000_000);
    g.decay("post-t", at(28, 15)); for (let d = 27; d >= 14; d--) g.decay("post-t", at(d, 15), 5); for (let d = 13; d >= 8; d--) g.decay("post-t", at(d, 15), 3);
    g.post("post-s", at(6), { owner: "TesterS" }); for (const uid of [R1, R2]) g.engage("post-s", at(6, 13), "view", 1_000, uid); g.decay("post-s", at(6, 14)); g.stress("post-s", at(5, 13));
    const gDoc = renderAt(g.payload, DAY).document;
    const multiplierBoundary = gDoc.epochs.find((epoch) => epoch.boundaryCause === "trial");
    assert.ok(multiplierBoundary && multiplierBoundary.fromDay === report.dayPlus(DAY, -13), JSON.stringify(gDoc.epochs));
    assert.equal(multiplierBoundary.signature.trialMultiplier, 3);
    const stressRow = renderAt(g.payload, DAY).evidence.days.find((row) => row.day === report.dayPlus(DAY, -5));
    assert.equal(stressRow.trialClass, null); assert.ok(stressRow.realPostDecayLoss.byMode.stress > 0);
    assert.equal(gDoc.epochs.length, 2);
    // sourceMatchesObserved false → source-ahead.
    const versions = [{ version: "deadbeef", fromMillis: at(5), signature: { view: 1_000, like: 1_000, comment: 2_000, dislike: -1_000, repeatBase: 500, seedSeen: 5_000 } }];
    const ahead = renderAt(k2RaiseWorld().payload, DAY, { versions });
    assert.equal(ahead.published.sourceMatchesObserved, false);
    assert.equal(`${verdictOf(ahead.document, "K2").verdict}/${verdictOf(ahead.document, "K2").reason}`, "insufficient/source-ahead", kinds(ahead.document));
    // Like mode 1,500 at n 42 → drift verify: decision verify, every tunable insufficient/drift, the like row carries the verify.
    const drift = renderAt(k2RaiseWorld({ pumpOptions: { like: 1_500, likes: 32 } }).payload, DAY).document;
    assert.equal(drift.checks.find((check) => check.id === "drift").status, "verify");
    assert.equal(drift.decision.kind, "verify");
    assert.equal(verdictOf(drift, "K2").verdict, "verify"); assert.equal(verdictOf(drift, "K2").reason, "drift");
    for (const knob of ["K1", "K3", "K4", "K5", "K7"]) assert.equal(`${verdictOf(drift, knob).verdict}/${verdictOf(drift, knob).reason}`, "insufficient/drift", knob);
    assert.equal(Object.values(drift.verdictCounts).reduce((a, b) => a + b, 0), 17); assert.equal(drift.verdictCounts.verify, 1);
    assert.equal(drift.decision.appliedByReport, false);
    // observed7d.like.n = 12 → hold/production-unverified.
    const thin = renderAt(k2RaiseWorld({ pumpOptions: { likes: 12 } }).payload, DAY).document;
    assert.equal(verdictOf(thin, "K2").seenN, 12);
    assert.equal(`${verdictOf(thin, "K2").verdict}/${verdictOf(thin, "K2").reason}`, "hold/production-unverified", kinds(thin));
  }

  // ── Test 14: the outcome loop ──
  {
    const f = k2RaiseWorld();
    const first = renderAt(f.payload, DAY);
    assert.equal(first.loop.open.knob, "K2");
    const knobs1250 = { ...KNOBS, likeMeters: 1_250 };
    const changeDay = report.dayPlus(DAY, 1);
    const loopAfterSource = { ...first.loop, knobChanges: { likeMeters: { day: changeDay, from: 1_000, to: 1_250 } } };
    const source = renderAt(f.payload, report.dayPlus(DAY, 2), { knobs: knobs1250, loop: loopAfterSource, last: first.memo });
    const k2 = verdictOf(source.document, "K2");
    assert.equal(k2.outcome, "adopted-in-source");
    assert.equal(`${k2.verdict}/${k2.reason}`, "hold/open", "not re-evaluated even though K2-R would fire again at 1,250 → 1,500");
    assert.equal(k2.declaredValue, 1_250); assert.equal(k2.seenValue, 1_000);
    assert.ok(source.document.decision.sentence.includes("production pays 1,000 m until you deploy"), source.document.decision.sentence);
    assert.equal(source.document.checks.find((check) => check.id === "drift").status, "clear", "the lag is the open suggestion awaiting its deploy, not drift");
    assert.deepEqual(source.document.checks.find((check) => check.id === "drift").awaitingDeploy, ["like"]);
    assert.equal(source.loop.open.knob, "K2");
    assert.equal(source.loop.open.missedReports, 0, "the clock is frozen once adopted in source");
    // Production seen paying 1,250 (n ≥ 30) on days after the source change → adopted in production, open cleared, K2 frozen.
    f.pump({ id: "post-official-pump-2", like: 1_250, likes: 40, views: 0, comments: 0, repeats: 0, dislikes: 0, daysBefore: 0 });
    for (let i = 0; i < 40; i++) f.engage("post-official-pump-2", start(report.dayPlus(DAY, 3)) + 13 * H + i * MIN, "like", 1_250, SYN[i % 8], "synthetic");
    const prodDay = report.dayPlus(DAY, 3);
    const prod = renderAt(f.payload, prodDay, { knobs: knobs1250, loop: source.loop, last: source.memo });
    const k2p = verdictOf(prod.document, "K2");
    assert.equal(k2p.outcome, "adopted-in-production", JSON.stringify([k2p.verdict, k2p.reason, k2p.reasonText]));
    assert.equal(`${k2p.verdict}/${k2p.reason}`, "hold/changed-recently"); assert.equal(k2p.frozenUntilDay, report.dayPlus(prodDay, 30));
    assert.equal(prod.loop.open, null); assert.deepEqual(prod.loop.adopted.K2, { day: prodDay, direction: "raise" });
    assert.equal(prod.document.decision.kind, "none");
    assert.deepEqual(prod.document.decision.open[0].outcome, "adopted-in-production", "listed once more with its outcome");
    const frozenNext = renderAt(f.payload, report.dayPlus(prodDay, 10), { knobs: knobs1250, loop: prod.loop, last: prod.memo }).document;
    assert.equal(`${verdictOf(frozenNext, "K2").verdict}/${verdictOf(frozenNext, "K2").reason}`, "hold/changed-recently");
    // K7: adopted in source, production unverifiable — never adopted-in-production.
    const k7World = fixture();
    boundaryPump(k7World); staleViewedPosts(k7World);
    for (let i = 0; i < 8; i++) for (const uid of [R1, R2]) for (let k = 0; k < 2; k++) k7World.engage(`post-viewed-${i}`, at(3, 13, k), "view", 1, uid);
    const k7first = renderAt(k7World.payload, DAY);
    assert.equal(k7first.loop.open.knob, "K7");
    const k7src = renderAt(k7World.payload, report.dayPlus(DAY, 2), { knobs: { ...KNOBS, decayPerDay: 0.04 }, loop: { ...k7first.loop, knobChanges: { decayPerDay: { day: report.dayPlus(DAY, 1), from: 0.05, to: 0.04 } } }, last: k7first.memo });
    assert.equal(verdictOf(k7src.document, "K7").outcome, "adopted-in-source"); assert.equal(verdictOf(k7src.document, "K7").outcomeNote, "production unverifiable");
    assert.equal(`${verdictOf(k7src.document, "K7").verdict}/${verdictOf(k7src.document, "K7").reason}`, "hold/changed-recently", "frozen 30 d from knobChanges.decayPerDay.day");
    assert.equal(k7src.document.policy.decay.observedRatePerDay, null);
    const k7later = renderAt(k7World.payload, report.dayPlus(DAY, 40), { knobs: { ...KNOBS, decayPerDay: 0.04 }, loop: k7src.loop, last: k7src.memo });
    assert.equal(verdictOf(k7later.document, "K7").outcome, "adopted-in-source", "never adopted-in-production");
    // Withdrawal: the rule silent on 3 consecutive complete reports.
    const quiet = grantsWorld().payload;
    let loop = first.loop, memo = first.memo, doc = null;
    for (let i = 1; i <= 3; i++) {
      const render = renderAt(quiet, report.dayPlus(DAY, i), { loop, last: memo });
      loop = render.loop; memo = render.memo; doc = render.document;
      if (i < 3) { assert.equal(loop.open.missedReports, i); assert.equal(verdictOf(doc, "K2").outcome, "open"); assert.equal(verdictOf(doc, "K2").reason, "open"); }
    }
    assert.equal(verdictOf(doc, "K2").outcome, "withdrawn"); assert.equal(verdictOf(doc, "K2").withdrawnDay, report.dayPlus(DAY, 3));
    assert.ok(verdictOf(doc, "K2").reasonText.startsWith(`withdrawn since ${report.dayPlus(DAY, 3)} — the evidence no longer supports it`), verdictOf(doc, "K2").reasonText);
    assert.equal(loop.open, null); assert.deepEqual(loop.withdrawn.K2, { day: report.dayPlus(DAY, 3), ruleId: "K2-R", completeReportsSince: 0 });
    assert.equal(doc.decision.kind, "none"); assert.equal(doc.decision.open[0].outcome, "withdrawn");
    // Test 21: the re-open cool-down, then the same rule needs the 1.2× margin; a different rule needs only the plain gates.
    // The world is built relative to D+11 (the re-open day) with a second pump so production is seen on every judged day.
    const again = withBase(report.dayPlus(DAY, 11), () => { const w = k2RaiseWorld(); w.pump({ id: "post-official-pump-early", daysBefore: 10 }); return w.payload; });
    const cooling = renderAt(again, report.dayPlus(DAY, 4), { loop, last: memo });
    assert.equal(`${verdictOf(cooling.document, "K2").verdict}/${verdictOf(cooling.document, "K2").reason}`, "hold/cool-down");
    assert.ok(verdictOf(cooling.document, "K2").reasonText.includes("re-evaluated after 7 complete reports"), verdictOf(cooling.document, "K2").reasonText);
    assert.equal(cooling.loop.withdrawn.K2.completeReportsSince, 1);
    let loop2 = cooling.loop;
    for (let i = 5; i <= 10; i++) loop2 = renderAt(again, report.dayPlus(DAY, i), { loop: loop2 }).loop;
    assert.equal(loop2.withdrawn.K2.completeReportsSince, 7);
    const reopened = renderAt(again, report.dayPlus(DAY, 11), { loop: loop2 });
    assert.equal(verdictOf(reopened.document, "K2").verdict, "suggest", "54/36 events, 10/10 posts, 4/3 actors clear the margin");
    assert.equal(reopened.loop.withdrawn.K2, undefined, "a new suggestion clears the withdrawal");
    const thinAgain = withBase(report.dayPlus(DAY, 11), () => k2RaiseWorld({ posts: 8, netZero: 6 }).payload);
    const margin = renderAt(thinAgain, report.dayPlus(DAY, 11), { loop: loop2 });
    assert.equal(`${verdictOf(margin.document, "K2").verdict}/${verdictOf(margin.document, "K2").reason}`, "hold/cool-down", kinds(margin.document));
    assert.ok(verdictOf(margin.document, "K2").reasonText.includes("1.2×") && verdictOf(margin.document, "K2").reasonText.includes("Gd 8/10"), verdictOf(margin.document, "K2").reasonText);
    const lowerPayload = withBase(report.dayPlus(DAY, 11), () => {
      const lowerWorld = fixture();
      for (let i = 0; i < 10; i++) { lowerWorld.post(`post-${i}`, at(3), { owner: `T${i}` }); for (const uid of [R1, R2, R3, R4]) lowerWorld.engage(`post-${i}`, at(3, 13), "like", 1_000, uid); lowerWorld.engage(`post-${i}`, at(3, 14), "view", 1_000, R5); }
      lowerWorld.pump();
      return lowerWorld.payload;
    });
    const otherRule = renderAt(lowerPayload, report.dayPlus(DAY, 11), { loop: loop2 }).document;
    assert.equal(`${verdictOf(otherRule, "K2").verdict}/${verdictOf(otherRule, "K2").reason}`, "hold/invariant-capped", "K2-L after the cool-down needs only the plain gates (it is capped, not cooled)");
  }

  // ── Test 15: fold additions ──
  {
    const f = fixture();
    f.post("p", at(2), { owner: "T" });
    f.engage("p", at(2, 13), "view", 1_000, R1).engage("p", at(2, 13, 1), "like", 1_000, R1).engage("p", at(2, 13, 2), "comment", 2_000, R2).engage("p", at(2, 13, 3), "dislike", -1_000, R3);
    const fold = f.payload.folds.p, cell = f.payload.days[day(at(2, 13))];
    assert.deepEqual(fold.rk, { v: 1, l: 1, c: 1, d: 1 });
    assert.deepEqual(cell.realActorEntries, { [R1]: { v: 1, l: 1, c: 0, d: 0 }, [R2]: { v: 0, l: 0, c: 1, d: 0 }, [R3]: { v: 0, l: 0, c: 0, d: 1 } });
    const compact = digest.compactPayload(f.payload);
    assert.equal(JSON.stringify(compact).includes('"clampedDislikes"'), false, "zeros are dropped");
    assert.equal(compact.days[day(at(2, 13))].realActorEntries[R2].v, undefined);
    assert.deepEqual(digest.hydratePayload(JSON.parse(JSON.stringify(compact))), f.payload, "compact → hydrate is lossless for the additions");
    const empty = fixture(); empty.post("q", at(2), { owner: "T" });
    assert.equal(JSON.stringify(digest.compactPayload(empty.payload)).includes("realActorEntries"), false, "an empty map is dropped");
    // The straddling window (refuters 4/17): 40 pre-stamp events by one person + 10 post-stamp split two ways.
    const stamp = at(9);
    const g = fixture({ kindSplitSinceMillis: stamp });
    for (let i = 0; i < 10; i++) { g.post(`post-${i}`, at(20), { owner: `T${i}` }); for (const k of ["view", "like", "comment", "dislike"]) g.engage(`post-${i}`, at(15, 13), k, k === "comment" ? 2_000 : k === "dislike" ? -1_000 : 1_000, R1); }
    for (let i = 0; i < 5; i++) { g.engage(`post-${i}`, at(5, 13), "view", 1_000, R2); g.engage(`post-${i}`, at(5, 14), "view", 1_000, R3); }
    g.pump();
    const straddle = renderAt(g.payload, DAY);
    for (const knob of ["K1", "K2", "K3", "K4", "K5"]) assert.equal(`${verdictOf(straddle.document, knob).verdict}/${verdictOf(straddle.document, knob).reason}`, "insufficient/kind-split-unavailable", knob);
    assert.equal(straddle.evidence.metrics["maxShare.d30"].value, null, "never a gate");
    assert.ok(straddle.evidence.metrics["maxShare.d30"].gate.sufficient === false);
    const since = verdictOf(straddle.document, "K1").evidence.find((cell) => cell.id === "maxShare.d30");
    assert.equal(since.value, 0.5, "printed as since-<day> evidence over the accrued days only"); assert.ok(since.label.startsWith(`since ${day(stamp)}`), since.label);
    assert.equal(straddle.evidence.metrics["posts.kindMixUnknown"].value, 10, "every post first engaged before the stamp");
    assert.ok(verdictOf(straddle.document, "K1").evidence.find((cell) => cell.id === "posts.kindMixUnknown").label === "kind-split-unavailable");
    // Accrued the first day the whole d30 lies after the stamp (the stamp is at noon, so the window must start the day after it);
    // K5 carries no subset rule, so it reads the plain gate then — K1–K3 still wait on Gkinds while every post predates the stamp.
    const firstClean = report.dayPlus(day(stamp), 30);
    assert.equal(verdictOf(renderAt(g.payload, report.dayPlus(firstClean, -1)).document, "K5").reason, "kind-split-unavailable");
    assert.equal(verdictOf(renderAt(g.payload, firstClean).document, "K5").reason, "gate");
    assert.equal(verdictOf(renderAt(g.payload, firstClean).document, "K1").reason, "kind-split-unavailable", "every tester post was first engaged before the stamp (Gkinds)");
    assert.notEqual(verdictOf(renderAt(grantsWorld().payload, DAY).document, "K1").reason, "kind-split-unavailable", "kindSplitSinceMillis 0 = accrued from day one");
    assert.equal(renderAt(g.payload, DAY).evidence.metrics["M3.actors"].value, 3, "lifetime is printed, never substituted");
    // trimPayload prunes realActorEntries older than 45 days while the cells survive.
    const h = fixture();
    h.post("old", at(50), { owner: "T" }); h.engage("old", at(50, 13), "view", 1_000, R1);
    h.post("new", at(2), { owner: "T2" }); h.engage("new", at(2, 13), "view", 1_000, R2);
    const cells = Object.keys(h.payload.days).length;
    digest.trimPayload(h.payload, start(DAY) + D, TZ);
    assert.deepEqual(h.payload.days[day(at(50, 13))].realActorEntries, {}); assert.equal(h.payload.days[day(at(50, 13))].realPostGain.real.n, 1, "the counts survive");
    assert.deepEqual(Object.keys(h.payload.days[day(at(2, 13))].realActorEntries), [R2]);
    assert.equal(Object.keys(h.payload.days).length, cells, "day cells are never evicted");
  }

  // ── Test 16: real vs simulation ──
  {
    const f = grantsWorld();
    f.post("post-owner", at(5), { owner: MARK, ownerClass: "o" });
    for (let i = 0; i < 100; i++) f.engage("post-owner", at(4, 10, i), "view", 1_000, SYN[i % 8], "synthetic");
    for (let i = 0; i < 100; i++) f.engage("post-owner", at(3, 10, i), "like", 1_000, SYN[i % 8], "synthetic");
    const { evidence } = renderAt(f.payload, DAY);
    assert.equal(evidence.metrics["M9.synthMeters.d7"].value, 200_000); assert.equal(evidence.metrics["M9.synthEntries.d7"].value, 200);
    assert.equal(evidence.metrics["M1.gain.d30"].value, 30_000, "synthetic metres never reach M1");
    assert.equal(evidence.metrics["M1.gain.d7"].value, 0);
    assert.equal(evidence.windows.d7.realPostGain.synthetic.total, 200_000); assert.equal(evidence.windows.d7.realPostGain.real.total, 0);
    assert.equal(evidence.metrics["M9.synthShare.d7"].value, 1); assert.equal(evidence.metrics["M9.synthShare.d7"].population, "sim");
  }

  // ── Test 17: versions ──
  {
    assert.equal(rules.ruleSetVersion(), digest.sha8(rules.RULES));
    assert.notEqual(digest.sha8({ ...rules.RULES, thresholds: { ...rules.RULES.thresholds, K2: { ...rules.RULES.thresholds.K2, shareLike: 0.61 } } }), rules.ruleSetVersion(), "a threshold change moves the version");
    assert.ok(Object.isFrozen(rules.RULES));
    const base = renderAt(grantsWorld().payload, DAY).document;
    const slower = renderAt(grantsWorld().payload, DAY, { knobs: { ...KNOBS, decayPerDay: 0.04 } }).document;
    assert.notEqual(slower.knobsHash, base.knobsHash); assert.equal(slower.sourcePolicyVersion, base.sourcePolicyVersion, "sourcePolicyVersion covers six knobs, never the decay rate");
    assert.equal(slower.productionEpoch, base.productionEpoch, "a source change is never a production boundary");
    assert.equal(slower.policy.decay.observedRatePerDay, null); assert.equal(base.policy.decay.observedRatePerDay, null);
    assert.equal(slower.ruleSetVersion, base.ruleSetVersion);
    // The trial class moving between two non-null days moves productionEpoch.
    const g = grantsWorld();
    g.post("post-t", at(28), { owner: "TesterT" }); for (const uid of [R1, R2, R3, R4]) g.engage("post-t", at(28, 13), "view", 1_000, uid);
    g.growth("post-t", at(28, 13, 5), 2_000_000);
    g.decay("post-t", at(28, 15)); for (let d = 27; d >= 10; d--) g.decay("post-t", at(d, 15), 5); for (let d = 9; d >= 1; d--) g.decay("post-t", at(d, 15), 1);
    const moved = renderAt(g.payload, DAY).document;
    assert.notEqual(moved.productionEpoch, renderAt(g.payload, report.dayPlus(DAY, -12)).document.productionEpoch);
    assert.equal(moved.epochs.find((epoch) => epoch.boundaryCause === "trial").fromDay, report.dayPlus(DAY, -9));
  }

  // ── Test 18 (guard) and 19 (index) ──
  {
    const fat = (n) => Array.from({ length: n }, (_, i) => ({ postId: `post-${i}`, dayGain: { gr: 1 }, rk: { v: 1 }, blob: "x".repeat(6_000) }));
    const evidence = { posts: fat(60), days: fat(30), snapshots: { contamination: { d7: { posts: fat(20) } } }, metrics: {} };
    const guarded = report.guardReport(evidence, 200_000);
    assert.equal(guarded.trimmed, true); assert.equal(guarded.evidence.posts.length, 30); assert.equal(guarded.evidence.days.length, 14);
    assert.equal(guarded.evidence.snapshots.contamination.d7.posts.length, 0);
    assert.equal(guarded.evidence.posts[0].dayGain, undefined); assert.equal(guarded.evidence.posts[0].rk, undefined);
    assert.ok(JSON.stringify(guarded.evidence).length < 400_000);
    assert.equal(report.guardReport({ posts: fat(2), days: fat(2), snapshots: null, metrics: {} }).trimmed, false);
    const rows = [];
    let list = rows;
    for (let i = 0; i < 130; i++) list = report.reportIndexRows(list, { day: report.dayPlus("2026-01-01", i), revision: 1 });
    assert.equal(list.length, 120); assert.equal(list[0].day, report.dayPlus("2026-01-01", 129)); assert.equal(list.at(-1).day, report.dayPlus("2026-01-01", 10));
    const replaced = report.reportIndexRows(list, { day: list[3].day, revision: 2 });
    assert.equal(replaced.length, 120); assert.equal(replaced[3].revision, 2);
    const index = report.reportIndexDocument({ ...report.emptyReportState(), lastReportedDay: "2026-09-12", rows: list }, "run", 1);
    assert.ok(Array.isArray(index.days) && index.days.length === 120 && index.lastReportedDay === "2026-09-12" && index.version === 1);
  }

  // ── Test 26: the feed pool check — the shared newest-N window, evidence only ──
  {
    const feedPool = (doc) => doc.checks.find((check) => check.id === "feedPool");
    const turnover = (pool, perDay) => digest.round(pool / (perDay / 24), 1);
    // (a) 40 simulation + 2 real on D (lab counts as simulation, review/owner as real), the six days before it at the
    //     measured ≈ 450/day (one of them with 5 official): the web pool turns over in < 24 h and D is ≥ ½ simulation → watch.
    const f = grantsWorld();
    f.created(DAY, { synthetic: 37, lab: 3, real: 1, review: 1 });
    for (let d = 2; d <= 6; d++) f.created(report.dayPlus(DAY, -d), { synthetic: 450 });
    f.created(report.dayPlus(DAY, -1), { synthetic: 450, official: 5 });
    f.created(report.dayPlus(DAY, -7), { synthetic: 1_000 }); // outside the 7 days ending D — never counted
    const { document: doc } = renderAt(f.payload, DAY);
    const check = feedPool(doc);
    assert.equal(doc.checks.length, 7, "the seventh check");
    assert.equal(doc.checks.indexOf(check), 6, "after seedReach");
    assert.equal(check.status, "watch");
    assert.deepEqual({ createdOnDay: check.createdOnDay, createdReal: check.createdReal, createdOfficial: check.createdOfficial, createdSynthetic: check.createdSynthetic, poolNative: check.poolNative, poolWeb: check.poolWeb },
      { createdOnDay: 42, createdReal: 2, createdOfficial: 0, createdSynthetic: 40, poolNative: 96, poolWeb: 160 });
    assert.equal(check.simShare, 40 / 42);
    const perDay7 = (42 + 455 + 5 * 450) / 7;
    assert.equal(check.perDay7, perDay7, "mean of every class over the 7 days ending D; D−7 is outside");
    assert.equal(check.turnoverHoursNative, turnover(96, perDay7)); assert.equal(check.turnoverHoursWeb, turnover(160, perDay7));
    assert.equal(check.turnoverHoursNative, 5.9); assert.equal(check.turnoverHoursWeb, 9.8);
    assert.equal(check.basis, "posts created on D by class (sweep on server createdAt) against the shared pool sizes: native relay newest-96 (iOS/Android), browser newest-160");
    assert.equal(check.text, `≈ 392 pops/day over the 7 d ending ${DAY} (42 on ${DAY}: 40 simulation, 2 real, 0 official) — the newest-96 pool (phone) turns over in ≈ 5.9 h and the newest-160 pool (web) in ≈ 9.8 h; a real pop leaves other testers' Feed and Map after that unless it is their own`);
    assert.ok(!("rows" in check) && !("verify" in check), "a check, never a rule");
    assert.equal(doc.policy.ruleSetVersion, rules.ruleSetVersion(), "checks are not rules: the rule set did not move");
    assertNeverSuggest(doc, "feedPool watch");
    for (const knob of rules.TUNABLE_KNOBS) assert.notEqual(verdictOf(doc, knob).reason, "drift", `${knob}: a feedPool watch pre-empts nothing`);
    // Nothing on the day cell is read but postsCreated: the check is identical with and without the world's engagement.
    const bare = fixture(); bare.created(DAY, { synthetic: 37, lab: 3, real: 1, review: 1 }); for (let d = 2; d <= 6; d++) bare.created(report.dayPlus(DAY, -d), { synthetic: 450 }); bare.created(report.dayPlus(DAY, -1), { synthetic: 450, official: 5 });
    assert.deepEqual(feedPool(renderAt(bare.payload, DAY).document), check);
    // (b) A quiet day: no creations on D or in the week → clear, the fixed sentence, both turnovers null.
    const quiet = fixture(); quiet.post("post-quiet", at(9), { owner: "TesterQ" });
    const q = feedPool(renderAt(quiet.payload, DAY).document);
    assert.equal(q.status, "clear"); assert.equal(q.text, `no pops created on ${DAY}; the pool did not turn over`);
    assert.deepEqual({ createdOnDay: q.createdOnDay, createdReal: q.createdReal, createdOfficial: q.createdOfficial, createdSynthetic: q.createdSynthetic, simShare: q.simShare, perDay7: q.perDay7, turnoverHoursNative: q.turnoverHoursNative, turnoverHoursWeb: q.turnoverHoursWeb },
      { createdOnDay: 0, createdReal: 0, createdOfficial: 0, createdSynthetic: 0, simShare: null, perDay7: 0, turnoverHoursNative: null, turnoverHoursWeb: null });
    assert.equal(feedPool(renderAt(fixture().payload, DAY).document).text, `no pops created on ${DAY}; the pool did not turn over`, "no day cell at all");
    // 0 on D but a busy week: the sentence is keyed on D's creations, the turnovers on the week; simShare null → clear.
    const busyWeek = fixture(); for (let d = 1; d <= 6; d++) busyWeek.created(report.dayPlus(DAY, -d), { synthetic: 700 });
    const bw = feedPool(renderAt(busyWeek.payload, DAY).document);
    assert.equal(bw.status, "clear"); assert.equal(bw.text, `no pops created on ${DAY}; the pool did not turn over`);
    assert.equal(bw.perDay7, 600); assert.equal(bw.turnoverHoursWeb, 6.4); assert.equal(bw.turnoverHoursNative, 3.8); assert.equal(bw.simShare, null);
    // (c) A real-only day with a fast turnover → clear (simShare 0 < ½); just under half → clear; exactly half → watch.
    const realOnly = fixture(); realOnly.created(DAY, { real: 30, owner: 10, review: 2 }); for (let d = 1; d <= 6; d++) realOnly.created(report.dayPlus(DAY, -d), { real: 450 });
    const ro = feedPool(renderAt(realOnly.payload, DAY).document);
    assert.equal(ro.status, "clear"); assert.equal(ro.simShare, 0); assert.equal(ro.createdReal, 42); assert.equal(ro.createdSynthetic, 0);
    assert.ok(ro.turnoverHoursWeb < 24, `turnover ${ro.turnoverHoursWeb} h is fast, and still clear`);
    assert.ok(ro.text.includes(`(42 on ${DAY}: 0 simulation, 42 real, 0 official)`), ro.text);
    const under = fixture(); under.created(DAY, { synthetic: 20, real: 22 }); for (let d = 1; d <= 6; d++) under.created(report.dayPlus(DAY, -d), { synthetic: 450 });
    assert.equal(feedPool(renderAt(under.payload, DAY).document).status, "clear"); assert.equal(feedPool(renderAt(under.payload, DAY).document).simShare, 20 / 42);
    const half = fixture(); half.created(DAY, { synthetic: 21, real: 21 }); for (let d = 1; d <= 6; d++) half.created(report.dayPlus(DAY, -d), { synthetic: 450 });
    assert.equal(feedPool(renderAt(half.payload, DAY).document).status, "watch"); assert.equal(feedPool(renderAt(half.payload, DAY).document).simShare, 0.5);
    // A slow week is clear whatever D's mix: 42 on D alone → 6/day → the web pool holds 640 h.
    const slow = fixture(); slow.created(DAY, { synthetic: 40, real: 2 });
    const sl = feedPool(renderAt(slow.payload, DAY).document);
    assert.equal(sl.status, "clear"); assert.equal(sl.perDay7, 6); assert.equal(sl.turnoverHoursWeb, 640); assert.equal(sl.turnoverHoursNative, 384); assert.equal(sl.simShare, 40 / 42);
    assert.ok(sl.text.startsWith(`≈ 6 pops/day over the 7 d ending ${DAY} (42 on ${DAY}: 40 simulation, 2 real, 0 official) — the newest-96 pool (phone) turns over in ≈ 384.0 h and the newest-160 pool (web) in ≈ 640.0 h;`), sl.text);
    // (d) Present, with the same numbers, on a backfilled and a catch-up report: it needs no snapshot.
    for (const flags of [{ partial: false, backfilled: true, catchUp: false }, { partial: false, backfilled: false, catchUp: true }, { partial: true, backfilled: false, catchUp: false }]) {
      const flagged = renderAt(f.payload, DAY, { flags });
      assert.deepEqual(feedPool(flagged.document), check, JSON.stringify(flags));
      if (flags.backfilled) assert.equal(flagged.evidence.snapshots, null, "snapshots are null on a backfilled report and the check is still there");
    }
    // The pure helper, direct: a missing day cell counts 0 in the mean; the contract's shape.
    const direct = report.feedPoolCheck(f.payload, DAY, report.daysEnding(DAY, 7, TZ));
    assert.deepEqual(direct, check);
    assert.deepEqual(Object.keys(direct), ["id", "status", "basis", "text", "createdOnDay", "createdReal", "createdOfficial", "createdSynthetic", "simShare", "perDay7", "turnoverHoursNative", "turnoverHoursWeb", "poolNative", "poolWeb"]);
    assert.equal(report.FEED_POOL_NATIVE, 96); assert.equal(report.FEED_POOL_WEB, 160);
  }

  console.log("algorithm report policy (rules): all assertions passed");
  await runLevelTests();
  console.log("algorithm report policy: all assertions passed");
})().catch((error) => { console.error(error); process.exit(1); });

// ═══════════════════════════════════════════════════════════════════════════
// Run-level tests: the due test, idempotency, read cost, reset, catch-up, amendments, windows on D, identity, IO retry.
async function runLevelTests() {
  const AUTH = { [MARK]: "mark@apptist.ca", [R1]: "r1@gmail.com", [R2]: "r2@gmail.com", [R3]: "r3@gmail.com", TesterA00000000000000000000: "ta@gmail.com", TesterB00000000000000000000: "tb@gmail.com" };
  const TA = "TesterA00000000000000000000", TB = "TesterB00000000000000000000";
  const ts = (ms) => ({ seconds: Math.floor(ms / 1000), nanoseconds: (ms % 1000) * 1_000_000 });
  const tupleMillis = (t) => t.seconds * 1000 + Math.floor(t.nanoseconds / 1_000_000);
  const postDoc = (owner, o = {}) => ({ userID: owner, channelId: o.channelId ?? "live", latitude: o.lat ?? 43.65, longitude: o.lng ?? -79.38, radiusMeters: 5_000 + (o.organic ?? 0),
    radius: 5_000 + (o.organic ?? 0), seedRadiusMeters: 5_000, organicRadiusMeters: o.organic ?? 0, boostedRadiusMeters: 0, viewCount: o.viewCount ?? 0, status: o.status ?? "published", audience: "public" });
  class FakeReader {
    constructor(world) { this.world = world; this.calls = { create: [] }; }
    async authPage() { return { ...this.world.auth }; }
    async sweepPage(query) {
      let rows = [...this.world.posts.entries()].map(([id, post]) => ({ id, path: `posts/${id}`, data: post.data, createdAt: post.createdAt }))
        .filter((row) => tupleMillis(row.createdAt) <= query.toMillis && (query.fromMillis == null || tupleMillis(row.createdAt) >= query.fromMillis));
      const compare = (a, b) => a.createdAt.seconds - b.createdAt.seconds || a.createdAt.nanoseconds - b.createdAt.nanoseconds || (a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
      rows.sort(compare);
      if (query.after) rows = rows.filter((row) => compare(row, { createdAt: query.after, path: query.after.path }) > 0);
      return rows.slice(0, query.limit);
    }
    async ledgerPage(query) {
      let rows = [...(this.world.ledgers.get(query.postId) ?? [])].filter((row) => row.data.atMillis <= query.horizonMillis);
      rows.sort((a, b) => a.data.atMillis - b.data.atMillis || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
      if (query.after) rows = rows.filter((row) => row.data.atMillis > query.after.atMillis || (row.data.atMillis === query.after.atMillis && row.id > query.after.id));
      return rows.slice(0, query.limit);
    }
    async createEntry(postId) { this.calls.create.push(postId); return (this.world.ledgers.get(postId) ?? []).find((row) => row.id === "create") ?? null; }
    async engagement(postId, id) { return this.world.engagements.get(`${postId}/${id}`) ?? null; }
    async user(uid) { return this.world.users.get(uid) ?? null; }
    async post(postId) { return this.world.posts.get(postId)?.data ?? null; }
  }
  const run = (world, state, now, options = {}) => digest.runDigestFold({ state, config: options.config ?? config(), switches: options.switches ?? switchesOn, reader: new FakeReader(world),
    runStartMillis: now, runId: options.runId ?? `run-${now}`, timeZone: TZ, ...(options.knobs ? { knobs: options.knobs } : {}), ...(options.stamp ? { stamp: options.stamp } : {}) });
  /** A ledger with running state (the digest test's shape). */
  function ledger() {
    const rows = []; let s = { radius: 0, organic: 0, seed: 0, boost: 0 };
    const push = (id, atMillis, cause, writer, next, extra = {}) => {
      const radius = Math.min(MAX, next.organic + next.seed + next.boost);
      rows.push({ id, data: { atMillis, cause, writer, radiusMeters: radius, organicRadiusMeters: next.organic, seedRadiusMeters: next.seed, boostedRadiusMeters: next.boost,
        delta: rows.length ? radius - s.radius : 0, organicDelta: rows.length ? next.organic - s.organic : 0, ...extra } });
      s = { organic: next.organic, seed: next.seed, boost: next.boost, radius };
    };
    const api = {
      rows, state: () => ({ ...s }),
      create(atMillis, seed = 5_000) { push("create", atMillis, "create", "radiusHistoryOnPostCreated", { organic: 0, seed, boost: 0 }); return api; },
      engage(atMillis, kind, meters, eid) { push(`eng_${eid}`, atMillis, "engagement", "recordPostEngagement", { ...s, organic: Math.max(0, s.organic + meters) }, { kind, engagementId: eid }); return api; },
      decayTo(atMillis, organic) { push(`decay_${atMillis}`, atMillis, "decay", "radiusDecay", { ...s, organic }); return api; },
    };
    return api;
  }
  const worldOf = () => ({ auth: { ...AUTH }, posts: new Map(), ledgers: new Map(), engagements: new Map(), users: new Map() });
  const addPost = (world, id, owner, createdAt, entries, o = {}) => { world.posts.set(id, { data: postDoc(owner, o), createdAt: ts(createdAt) }); world.ledgers.set(id, entries); };
  const join = (world, postId, eid, uid) => world.engagements.set(`${postId}/${eid}`, { actorUid: uid, surface: "feed" });
  const T_D = start(DAY);                      // midnight of 12 Sep
  const T_NEXT = start(report.dayPlus(DAY, 1)); // midnight of 13 Sep
  function baseWorld() {
    const world = worldOf();
    const l = ledger().create(T_D - 3 * D + 12 * H).engage(T_D + 10 * H, "view", 1_000, "v1").engage(T_D + 11 * H, "like", 1_000, "l1").engage(T_D + 12 * H, "comment", 2_000, "c1");
    addPost(world, "post-a", TA, T_D - 3 * D + 12 * H, l.rows, { organic: l.state().organic });
    join(world, "post-a", "v1", R1); join(world, "post-a", "l1", R2); join(world, "post-a", "c1", R3);
    // Six days of history, so the first-deploy backfill (oldest first, ≤ 7 per run) reaches the closed day in one run.
    addPost(world, "post-b", TB, T_D - 5 * D, ledger().create(T_D - 5 * D).rows, { lat: 43.66 });
    return world;
  }

  // ── Test 1: timing ──
  {
    const world = baseWorld();
    const early = await run(world, digest.initialState(), T_NEXT + 5 * MIN);
    assert.equal(early.reports.length, 0); assert.equal(early.reportDeferredReason, "horizon", "00:05 → horizon 23:35 < midnight: defer");
    assert.equal(early.cost.writes, 3);
    assert.equal(early.state.report.lastReportedDay, null);
    const onTime = await run(world, early.state, T_NEXT + 45 * MIN);
    assert.equal(onTime.reportDeferredReason, null);
    const days = onTime.reports.map((r) => r.day);
    assert.equal(days.at(-1), DAY, "the 00:45 run writes D");
    assert.deepEqual(days, Array.from({ length: 6 }, (_, i) => report.dayPlus(DAY, -5 + i)), "first deploy: from the first day with a cell, oldest first, ≤ 7");
    // With more history the closed day lands in the second run (oldest first, 7 per run).
    const long = baseWorld();
    addPost(long, "post-old", TB, T_D - 12 * D, ledger().create(T_D - 12 * D).rows, { lat: 43.67 });
    const batch1 = await run(long, digest.initialState(), T_NEXT + 45 * MIN);
    assert.deepEqual(batch1.reports.map((r) => r.day), Array.from({ length: 7 }, (_, i) => report.dayPlus(DAY, -12 + i)));
    const batch2 = await run(long, batch1.state, T_NEXT + 105 * MIN);
    assert.deepEqual(batch2.reports.map((r) => r.day), Array.from({ length: 6 }, (_, i) => report.dayPlus(DAY, -5 + i)), "13 days ≤ 14 backfilled over two runs");
    assert.equal(onTime.reports.every((r) => r.document.backfilled === true), true);
    const doc = onTime.reports.at(-1).document, evidence = JSON.parse(doc.evidence);
    const cell = onTime.state.payload.days[DAY];
    const { trialMultipliers: _tm, trialClass: _tc, earnedPolicy: _ep, productionEpoch: _pe, ...dayRow } = evidence.day;
    assert.deepEqual(dayRow, JSON.parse(JSON.stringify(digest.publishedDay(cell, null))), "evidence.day equals publishedDay(payload.days[D])");
    assert.equal(evidence.windows.d30.days, 30); assert.equal(evidence.days.length, 30); assert.equal(evidence.days.at(-1).day, DAY); assert.equal(evidence.days[0].day, report.dayPlus(DAY, -29));
    assert.equal(evidence.windows.d30.realPostGain.real.n, 3);
    assert.equal(onTime.cost.writes, 3 + days.length + 1);
    assert.equal(onTime.state.report.lastReportedDay, DAY);
    assert.ok(onTime.reportIndex.days.length === days.length && onTime.reportIndex.days[0].day === DAY, "index newest first");
    // Incomplete (a capped run) defers; at 06:45 it writes a partial report that never suggests.
    const capped = await run(baseWorld(), digest.initialState(), T_NEXT + 45 * MIN, { config: config({ maxReadsPerRun: 12 }) });
    assert.equal(capped.cost.budgetHit, true); assert.ok(capped.runCoverage.postsBehindHorizon >= 1);
    assert.equal(capped.reports.length, 0); assert.equal(capped.reportDeferredReason, "incomplete");
    const partial = await run(baseWorld(), digest.initialState(), T_NEXT + 6 * H + 45 * MIN, { config: config({ maxReadsPerRun: 12 }) });
    assert.ok(partial.reports.length >= 1, "at 06:45 the partial escape writes");
    for (const r of partial.reports) {
      assert.equal(r.document.partial, true);
      for (const knob of rules.TUNABLE_KNOBS) { const row = verdictOf(r.document, knob); assert.equal(`${row.verdict}/${row.reason}`, "insufficient/partial"); assert.equal(row.suggestion, null); }
      assert.equal(r.indexRow.partial, true);
    }
    // Test 3 (part): coverageComplete false when evicted > 0 even with postsBehindHorizon 0 and no budget hit.
    const plan = report.reportsDue({ report: report.emptyReportState(), payload: digest.emptyPayload(), config: config(), runStartMillis: T_NEXT + 45 * MIN, timeZone: TZ,
      runCoverage: { postsBehindHorizon: 0, evicted: 1 }, cost: { budgetHit: false } });
    assert.equal(plan.complete, false); assert.equal(plan.deferredReason, "incomplete");
  }

  // ── Test 2: idempotency and reproducibility ──
  {
    const world = baseWorld();
    const first = await run(world, digest.initialState(), T_NEXT + 45 * MIN);
    const second = await run(world, first.state, T_NEXT + 105 * MIN);
    assert.equal(second.reports.length, 0); assert.equal(second.reportIndex, null); assert.equal(second.reportDeferredReason, null);
    assert.equal(second.cost.writes, 3);
    assert.equal(second.state.report.lastReportedDay, DAY);
    const a = renderAt(k2RaiseWorld().payload, DAY, { runId: "one" }).document, b = renderAt(k2RaiseWorld().payload, DAY, { runId: "two" }).document;
    for (const doc of [a, b]) { delete doc.runId; delete doc.generatedAtMillis; delete doc.snapshotsAsOfMillis; delete doc.policy.runId; delete doc.headline.coverage.trimmed; }
    assert.deepEqual(a, b, "renderReport is a pure function of its inputs");
    assert.deepEqual(JSON.parse(JSON.stringify(a)), a, "no undefined anywhere");
    assert.ok(!JSON.stringify(a).includes("undefined"));
  }

  // ── Test 3: read cost ──
  {
    const world = baseWorld();
    const eve = await run(world, digest.initialState(), T_D + 22 * H + 45 * MIN);
    const eveAgain = await run(world, eve.state, T_D + 23 * H + 45 * MIN);
    const readsOnD = eveAgain.state.readsToday;
    assert.equal(eveAgain.state.runsToday, 2);
    const early = await run(world, eveAgain.state, T_NEXT + 5 * MIN);
    assert.deepEqual(early.state.readsPrev, { day: DAY, reads: readsOnD, runs: 2 }, "the roll stashes D's totals");
    assert.equal(early.reportDeferredReason, "horizon");
    const onTime = await run(world, early.state, T_NEXT + 45 * MIN);
    assert.deepEqual(onTime.state.readsPrev, { day: DAY, reads: readsOnD, runs: 2 }, "…and it survives the deferred report");
    const doc = onTime.reports.find((r) => r.day === DAY).document;
    assert.equal(doc.headline.cost.readsOnDay, readsOnD); assert.equal(doc.headline.cost.runsOnDay, 2);
    approx(doc.headline.cost.cadOnDay, readsOnD / 100_000 * 0.05, 1e-6, "cadOnDay");
    assert.equal(JSON.parse(doc.evidence).metrics["M17.readsOnDay"].value, readsOnD);
    assert.deepEqual(onTime.reports.map((r) => r.day), [DAY], "the eve run already backfilled the earlier days");
    assert.equal(eve.reports.find((r) => r.day === report.dayPlus(DAY, -1)).document.headline.cost.readsOnDay, null, "only the rolled day's cost is ever known");
    // A mid-day reset keeps the counters.
    const resetMidDay = await run(world, eve.state, T_D + 23 * H + 45 * MIN, { config: config({ resetRequestedAtMillis: T_D + 23 * H }) });
    assert.equal(resetMidDay.state.lastResetAtMillis, T_D + 23 * H);
    assert.equal(resetMidDay.state.runsToday, 2); assert.ok(resetMidDay.state.readsToday > eve.state.readsToday);
    const afterReset = await run(world, resetMidDay.state, T_NEXT + 45 * MIN, { config: config({ resetRequestedAtMillis: T_D + 23 * H }) });
    assert.equal(afterReset.state.readsPrev.reads, resetMidDay.state.readsToday);
    assert.equal(afterReset.reports.find((r) => r.day === DAY).document.headline.cost.readsOnDay, resetMidDay.state.readsToday);
  }

  // ── Test 4: reset preservation ──
  {
    const world = baseWorld();
    const first = await run(world, digest.initialState(), T_NEXT + 45 * MIN);
    const before = JSON.parse(JSON.stringify(first.state.report));
    const reset = await run(world, first.state, T_NEXT + 2 * H, { config: config({ resetRequestedAtMillis: T_NEXT + H }) });
    assert.equal(reset.state.payload.coverage.kindSplitSinceMillis, 0, "a reset re-fold introduces the additions on an empty payload");
    assert.equal(reset.state.report.lastReportedDay, before.lastReportedDay);
    assert.deepEqual(reset.state.report.rows, before.rows); assert.deepEqual(reset.state.report.revisions, before.revisions); assert.deepEqual(reset.state.report.open, before.open);
    assert.equal(reset.reports.length, 0, "no re-backfill");
    const nextDayRun = await run(world, reset.state, T_NEXT + D + 45 * MIN, { config: config({ resetRequestedAtMillis: T_NEXT + H }) });
    const doc = nextDayRun.reports.find((r) => r.day === report.dayPlus(DAY, 1)).document;
    assert.equal(doc.previous, null); assert.equal(doc.previousUnavailable, "reset");
    const following = await run(world, nextDayRun.state, T_NEXT + 2 * D + 45 * MIN, { config: config({ resetRequestedAtMillis: T_NEXT + H }) });
    assert.ok(following.reports[0].document.previous, "the memo works again once written after the reset");
    assert.equal(following.reports[0].document.previous.day, report.dayPlus(DAY, 1));
  }

  // ── Test 5: catch-up and backfill, the first line per day ──
  {
    const world = baseWorld();
    const first = await run(world, digest.initialState(), T_NEXT + 45 * MIN);
    const behind = { ...first.state, report: { ...first.state.report, lastReportedDay: report.dayPlus(DAY, -10) } };
    const catchUp = await run(world, behind, T_NEXT + 105 * MIN);
    assert.deepEqual(catchUp.reports.map((r) => r.day), Array.from({ length: 7 }, (_, i) => report.dayPlus(DAY, -9 + i)), "7 oldest first");
    assert.ok(catchUp.reports.every((r) => r.document.catchUp === true && r.document.backfilled === false && r.document.snapshotsAsOfMillis === T_NEXT + 105 * MIN));
    assert.ok(catchUp.reports.every((r) => `${verdictOf(r.document, "K7").verdict}/${verdictOf(r.document, "K7").reason}` === "insufficient/backfilled"));
    assert.equal(catchUp.state.report.lastReportedDay, report.dayPlus(DAY, -3));
    const rest = await run(world, catchUp.state, T_NEXT + 165 * MIN);
    assert.deepEqual(rest.reports.map((r) => r.day), [report.dayPlus(DAY, -2), report.dayPlus(DAY, -1), DAY]);
    assert.equal(rest.state.report.lastReportedDay, DAY);
    // First deploy on an empty report state → ≤ 14 days, backfilled, snapshots null, tunables backfilled.
    assert.ok(first.reports.every((r) => r.document.backfilled && JSON.parse(r.document.evidence).snapshots === null && r.document.snapshotsAsOfMillis === null));
    for (const r of first.reports) for (const knob of rules.TUNABLE_KNOBS) assert.equal(`${verdictOf(r.document, knob).verdict}/${verdictOf(r.document, knob).reason}`, "insufficient/backfilled");
    // Per-day trial line: with the switch on (effective 8 Sep 00:07Z = 7 Sep 20:07 Toronto) a 5 Sep backfill says no trial; the closed day says ON.
    const longWorld = baseWorld();
    addPost(longWorld, "post-old", TB, T_D - 12 * D, ledger().create(T_D - 12 * D).rows, { lat: 43.67 });
    const longFirst = await run(longWorld, digest.initialState(), T_NEXT + 45 * MIN);
    const old = longFirst.reports.find((r) => r.day === "2026-09-05");
    assert.ok(old, longFirst.reports.map((r) => r.day).join(","));
    assert.ok(old.document.firstLine.startsWith("Decay ×1 · no trial"), old.document.firstLine); assert.equal(old.document.trialOnDay, false); assert.equal(old.indexRow.trialOn, false);
    // The parenthetical tells the truth about the writing run: the switch is ON, effective after this day — never "switch off".
    assert.ok(old.document.firstLine.includes("(switch ON ×5 at the writing run, effective 8 Sep 00:07Z — after this day; no multiplier seen on 2026-09-05)"), old.document.firstLine);
    assert.ok(!old.document.firstLine.includes("switch off"), old.document.firstLine);
    const longSecond = await run(longWorld, longFirst.state, T_NEXT + 105 * MIN);
    assert.equal(longSecond.reports.find((r) => r.day === "2026-09-07").document.trialOnDay, true, "the switch vouches for 7 Sep from 20:07 Toronto");
    const closed = first.reports.find((r) => r.day === DAY);
    assert.ok(closed.document.firstLine.startsWith("DECAY TRIAL ×5 ON since 8 Sep 00:07Z"), closed.document.firstLine); assert.equal(closed.indexRow.trialOn, true);
    // With the switch OFF at the writing run, a catch-up day whose cell saw ×5 still opens with the trial line.
    const trialWorld = baseWorld();
    const l = ledger().create(T_D - 6 * D).engage(T_D - 6 * D + H, "view", 1_000, "v1").engage(T_D - 6 * D + 2 * H, "view", 1_000, "v2").engage(T_D - 6 * D + 3 * H, "view", 1_000, "v3");
    let organic = l.state().organic, from = T_D - 6 * D + 4 * H;
    l.decayTo(from, digest.predictDecayed(organic, H, 1, from - H)); organic = l.state().organic;
    for (let d = 5; d >= 1; d--) { const atMillis = T_D - d * D + 4 * H; l.decayTo(atMillis, digest.predictDecayed(organic, atMillis - from, 5, from)); organic = l.state().organic; from = atMillis; }
    addPost(trialWorld, "post-t", TA, T_D - 6 * D, l.rows, { organic });
    join(trialWorld, "post-t", "v1", R1); join(trialWorld, "post-t", "v2", R2); join(trialWorld, "post-t", "v3", R3);
    const offRun = await run(trialWorld, digest.initialState(), T_NEXT + 45 * MIN, { switches: switchesOff });
    const sawTrial = offRun.reports.find((r) => r.day === report.dayPlus(DAY, -3)).document;
    assert.equal(sawTrial.trialOnDay, true); assert.equal(sawTrial.trialMultiplierOnDay, 5);
    assert.ok(sawTrial.firstLine.startsWith("DECAY TRIAL ×5 ON since"), sawTrial.firstLine);
    assert.ok(sawTrial.firstLine.includes(`Seen on ${report.dayPlus(DAY, -3)}: ×5 on`), sawTrial.firstLine);
    const quietDay = offRun.reports.find((r) => r.day === DAY).document;
    assert.equal(quietDay.trialOnDay, false, "the switch is off and D's cells saw nothing");
    assert.ok(quietDay.firstLine.startsWith("Decay ×1 · no trial · last trial multiplier seen on"), quietDay.firstLine);
    assert.ok(quietDay.firstLine.includes(`(switch off at the writing run; no multiplier seen on ${DAY})`), quietDay.firstLine);
    assert.deepEqual(offRun.reports.map((r) => r.indexRow.trialOn), offRun.reports.map((r) => r.document.trialOnDay), "the identity columns follow the day");
  }

  // ── Test 6: amendments ──
  {
    const world = baseWorld();
    // post-c: first seen through a decay entry on D−1 (no create in the page) — the fetch lands its create on D−1 a run later.
    const created = T_D - D + 8 * H;
    const decayRow = { id: `decay_${created + 4 * H}`, data: { atMillis: created + 4 * H, cause: "decay", writer: "radiusDecay", radiusMeters: 5_997, organicRadiusMeters: 997, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: -3, organicDelta: -3 } };
    addPost(world, "post-c", TB, created, [decayRow], { organic: 997 });
    const first = await run(world, digest.initialState(), T_NEXT + 45 * MIN);
    const dm1 = report.dayPlus(DAY, -1);
    assert.equal(first.state.report.revisions[dm1], 1);
    const entriesBefore = first.state.payload.days[dm1].entries.real + first.state.payload.days[dm1].entries.official;
    world.ledgers.get("post-c").push({ id: "create", data: { atMillis: created, cause: "create", writer: "radiusHistoryOnPostCreated", radiusMeters: 5_000, organicRadiusMeters: 0, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: 0, organicDelta: 0 } });
    // An incomplete run (capped) defers the amendment; revision 1 stands — also at 06:45 (no partial amendment exists).
    const capped = await run(world, first.state, T_NEXT + 105 * MIN, { config: config({ maxReadsPerRun: 12 }) });
    assert.equal(capped.amendDeferredReason, "incomplete"); assert.equal(capped.reports.length, 0); assert.equal(capped.state.report.revisions[dm1], 1);
    const cappedLate = await run(world, first.state, T_NEXT + 6 * H + 45 * MIN, { config: config({ maxReadsPerRun: 12 }) });
    assert.equal(cappedLate.amendDeferredReason, "incomplete"); assert.equal(cappedLate.reports.length, 0);
    // A complete run: the create fetch changes D−1's cell → revision 2 with supersedes, the stored revision moves, ≤ 2 per run.
    const complete = await run(world, first.state, T_NEXT + 105 * MIN, { knobs: { ...KNOBS, likeMeters: 2_000 } });
    assert.ok(complete.state.payload.postMeta["post-c"].hasCreate);
    assert.deepEqual(complete.reports.map((r) => r.day), [dm1]);
    const amended = complete.reports[0];
    assert.equal(amended.revision, 2); assert.equal(amended.document.revision, 2);
    assert.deepEqual(amended.document.supersedes, { runId: first.reports.find((r) => r.day === dm1).document.runId, generatedAtMillis: T_NEXT + 45 * MIN, entriesOnDay: entriesBefore });
    assert.equal(complete.state.report.revisions[dm1], 2); assert.equal(complete.reportIndex.days.find((row) => row.day === dm1).revision, 2);
    assert.equal(amended.document.policy.source.knobs.likeMeters, 1_000, "rendered with the ORIGINAL stamp's knobs");
    assert.equal(amended.document.knobsHash, first.reports.find((r) => r.day === dm1).document.knobsHash);
    assert.equal(amended.document.productionEpoch, first.reports.find((r) => r.day === dm1).document.productionEpoch);
    assert.equal(amended.document.previous, null); assert.equal(amended.document.previousUnavailable, "amendment");
    assert.equal(amended.document.day, dm1);
    assert.equal(complete.state.report.lastReportedDay, DAY, "later days' windows are not rewritten");
    // Decisions 12 and 20: an amendment keeps the revision's own flags. D−1 was BACKFILLED by the first deploy, so its
    // revision 2 is backfilled too — snapshots null, every tunable insufficient/backfilled, the BACKFILL chip on the row.
    assert.equal(first.state.report.stamps[dm1].flags.backfilled, true);
    assert.deepEqual({ partial: amended.document.partial, backfilled: amended.document.backfilled, catchUp: amended.document.catchUp }, { partial: false, backfilled: true, catchUp: false });
    assert.equal(amended.document.snapshotsAsOfMillis, null); assert.equal(JSON.parse(amended.document.evidence).snapshots, null);
    for (const knob of rules.TUNABLE_KNOBS) assert.equal(`${verdictOf(amended.document, knob).verdict}/${verdictOf(amended.document, knob).reason}`, "insufficient/backfilled", knob);
    assert.equal(amended.indexRow.backfilled, true); assert.equal(complete.reportIndex.days.find((row) => row.day === dm1).backfilled, true);
    assert.equal(report.amendmentFlags({ flags: undefined }).backfilled, false, "a flagless stamp reads as a plain day");
    // Unchanged cells write nothing; the same hash again → amendSkipped.
    const again = await run(world, complete.state, T_NEXT + 165 * MIN);
    assert.equal(again.reports.length, 0); assert.ok(again.amendSkipped.includes(dm1)); assert.equal(again.amendDeferredReason, null);
    // A plain day's amendment stays plain: D+1 is written normally, then a client-clock-behind view lands in its cell a run
    // later → revision 2 with the snapshot as of the amending run and no BACKFILL/CATCH-UP chip.
    const plainDay = report.dayPlus(DAY, 1);
    const plainFirst = await run(world, complete.state, T_NEXT + D + 45 * MIN);
    assert.deepEqual(plainFirst.reports.map((r) => [r.day, r.document.backfilled, r.document.catchUp]), [[plainDay, false, false]]);
    world.ledgers.get("post-a").push({ id: "eng_late2", data: { atMillis: T_NEXT + 3 * H, cause: "engagement", writer: "recordPostEngagement", kind: "view", engagementId: "late2", radiusMeters: 10_000, organicRadiusMeters: 5_000, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: 1_000, organicDelta: 1_000 } });
    join(world, "post-a", "late2", R2);
    const plainAmend = await run(world, plainFirst.state, T_NEXT + D + 105 * MIN);
    assert.deepEqual(plainAmend.reports.map((r) => [r.day, r.revision]), [[plainDay, 2]]);
    const plainDoc = plainAmend.reports[0].document;
    assert.deepEqual({ partial: plainDoc.partial, backfilled: plainDoc.backfilled, catchUp: plainDoc.catchUp }, { partial: false, backfilled: false, catchUp: false });
    assert.equal(plainDoc.snapshotsAsOfMillis, T_NEXT + D + 105 * MIN); assert.notEqual(JSON.parse(plainDoc.evidence).snapshots, null);
    assert.equal(plainAmend.reportIndex.days.find((row) => row.day === plainDay).backfilled, false);
    // A catch-up day's amendment keeps CATCH-UP: snapshot as of the amending run, K7 snapshot-blind, the chip on the row.
    const cuWorld = baseWorld();
    const cuFirst = await run(cuWorld, digest.initialState(), T_NEXT + 45 * MIN);
    const cuCatch = await run(cuWorld, { ...cuFirst.state, report: { ...cuFirst.state.report, lastReportedDay: report.dayPlus(DAY, -10) } }, T_NEXT + 105 * MIN);
    const cuRest = await run(cuWorld, cuCatch.state, T_NEXT + 165 * MIN);
    const dm3 = report.dayPlus(DAY, -3);
    assert.equal(cuRest.state.report.lastReportedDay, DAY); assert.equal(cuRest.state.report.stamps[dm3].flags.catchUp, true);
    cuWorld.ledgers.get("post-b").push({ id: "eng_cu", data: { atMillis: T_D - 3 * D + 13 * H, cause: "engagement", writer: "recordPostEngagement", kind: "view", engagementId: "cu", radiusMeters: 6_000, organicRadiusMeters: 1_000, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: 1_000, organicDelta: 1_000 } });
    join(cuWorld, "post-b", "cu", R1);
    const cuAmend = await run(cuWorld, cuRest.state, T_NEXT + 225 * MIN);
    assert.deepEqual(cuAmend.reports.map((r) => [r.day, r.revision]), [[dm3, 2]]);
    const cuDoc = cuAmend.reports[0].document;
    assert.deepEqual({ partial: cuDoc.partial, backfilled: cuDoc.backfilled, catchUp: cuDoc.catchUp }, { partial: false, backfilled: false, catchUp: true });
    assert.equal(cuDoc.snapshotsAsOfMillis, T_NEXT + 225 * MIN); assert.notEqual(JSON.parse(cuDoc.evidence).snapshots, null);
    assert.equal(`${verdictOf(cuDoc, "K7").verdict}/${verdictOf(cuDoc, "K7").reason}`, "insufficient/backfilled");
    assert.equal(cuAmend.reportIndex.days.find((row) => row.day === dm3).catchUp, true);
    assert.equal(cuAmend.reportIndex.days.find((row) => row.day === dm3).revision, 2);
    // A rule-set mismatch refuses the amendment and flags the row.
    const tampered = JSON.parse(JSON.stringify(complete.state));
    tampered.report.stamps[dm1].ruleSetVersion = "00000000"; tampered.report.stamps[dm1].dayHash = "deadbeef";
    const refused = await run(world, tampered, T_NEXT + 225 * MIN);
    assert.equal(refused.amendDeferredReason, "rules-changed"); assert.equal(refused.reports.length, 0);
    assert.equal(refused.state.report.rows.find((row) => row.day === dm1).staleData, true);
    // A reset whose re-fold is capped amends nothing; the first complete run after it — reproducing every cell — amends nothing either.
    const resetCapped = await run(world, complete.state, T_NEXT + 285 * MIN, { config: config({ resetRequestedAtMillis: T_NEXT + 280 * MIN, maxReadsPerRun: 12 }) });
    assert.equal(resetCapped.reports.length, 0); assert.equal(resetCapped.amendDeferredReason, "incomplete");
    let resumed = resetCapped;
    for (let i = 0; i < 6 && resumed.cost.budgetHit; i++) resumed = await run(world, resumed.state, T_NEXT + (345 + i * 60) * MIN, { config: config({ resetRequestedAtMillis: T_NEXT + 280 * MIN, maxReadsPerRun: 40 }) });
    assert.equal(resumed.cost.budgetHit, false, "the re-fold completes");
    assert.equal(resumed.reports.length, 0, "a deterministic re-fold reproduces the cell: no revision minted");
    assert.ok(resumed.amendSkipped.includes(dm1));
    // A late entry on an expired post lands only at a pollExpiredEveryRuns boundary and then amends.
    const expiredWorld = baseWorld();
    const ex = ledger().create(T_D - 5 * D).engage(T_D - 5 * D + H, "view", 1_000, "x1").decayTo(T_D - 4 * D, 0);
    addPost(expiredWorld, "post-x", TB, T_D - 5 * D, ex.rows, { organic: 0, status: "expired" });
    join(expiredWorld, "post-x", "x1", R1);
    const cfg = config({ pollExpiredEveryRuns: 3 });
    const e1 = await run(expiredWorld, digest.initialState(), T_NEXT + 45 * MIN, { config: cfg });
    assert.equal(e1.state.payload.postMeta["post-x"].live, false);
    expiredWorld.ledgers.get("post-x").push({ id: `decay_${T_D + 3 * H}`, data: { atMillis: T_D + 3 * H, cause: "decay", writer: "radiusDecay", radiusMeters: 5_000, organicRadiusMeters: 0, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: 0, organicDelta: 0 } });
    const e2 = await run(expiredWorld, e1.state, T_NEXT + 105 * MIN, { config: cfg });
    assert.equal(e2.reports.length, 0, "digestVersion 2: not a poll boundary");
    const e3 = await run(expiredWorld, e2.state, T_NEXT + 165 * MIN, { config: cfg });
    assert.equal(e3.state.digestVersion, 3);
    assert.deepEqual(e3.reports.map((r) => [r.day, r.revision]), [[DAY, 2]], "the boundary run folds the late entry and amends D");
    assert.equal(e3.reports[0].document.headline.coverage.nonLivePollLagRuns, 0);
  }

  // ── Test 7: windows end on D ──
  {
    const world = baseWorld();
    world.ledgers.get("post-a").push({ id: "eng_late", data: { atMillis: T_NEXT + 10 * MIN, cause: "engagement", writer: "recordPostEngagement", kind: "view", engagementId: "late", radiusMeters: 10_000, organicRadiusMeters: 5_000, seedRadiusMeters: 5_000, boostedRadiusMeters: 0, delta: 1_000, organicDelta: 1_000 } });
    join(world, "post-a", "late", R2);
    const out = await run(world, digest.initialState(), T_NEXT + 45 * MIN);
    assert.equal(out.published.windows.d7.realPostGain.real.n, 4, "the published window (ending at the run) sees the 00:10 entry");
    const evidence = JSON.parse(out.reports.find((r) => r.day === DAY).document.evidence);
    assert.equal(evidence.windows.d7.realPostGain.real.n, 3); assert.equal(evidence.windows.d1.realPostGain.real.n, 3); assert.equal(evidence.windows.d30.realPostGain.real.n, 3);
    const clipped = digest.windowStatsAt({ state: out.state, timeZone: TZ }, [DAY], T_NEXT);
    const live = digest.windowStats({ state: out.state, runStartMillis: T_NEXT + 45 * MIN, timeZone: TZ }, [DAY]);
    approx(clipped.netReal.byAge.lt7d.postDays, 2, 0.01, "post-a's post-days clip at D's last millisecond");
    assert.ok(live.netReal.byAge.lt7d.postDays > clipped.netReal.byAge.lt7d.postDays);
  }

  // ── Test 18: isolation — oversize refusal, cost.writes, the IO retry without reports ──
  {
    const world = baseWorld();
    const first = await run(world, digest.initialState(), T_NEXT + 45 * MIN);
    const next = await run(world, first.state, T_NEXT + D + 45 * MIN);
    assert.deepEqual(next.reports.map((r) => r.day), [report.dayPlus(DAY, 1)]);
    assert.equal(next.cost.writes, digest.WRITES_PER_RUN + 2); assert.equal(next.published.cost.writes, digest.WRITES_PER_RUN + 2);
    assert.equal(next.reportBytes, JSON.stringify(next.reports[0].document).length);
    // Oversize: a run whose published headline drags a 1 MB blob into the report is refused in-process.
    const huge = renderAt(grantsWorld().payload, DAY, { published: { headline: { anchorsAtWorld: 0, anchorsEver: 0, worstAnchor: { blob: "x".repeat(950_000) } } } });
    assert.ok(huge.document.bytes > report.REPORT_OVERSIZE_BYTES);
    const stepState = { ...digest.initialState(), digestVersion: 2, payload: grantsWorld().payload, report: { ...report.emptyReportState(), lastReportedDay: report.dayPlus(DAY, -1) } };
    const step = report.runReportStep({ state: stepState, published: { ...huge.published }, config: config(), switches: switchesOff, runStartMillis: T_NEXT + 45 * MIN, runId: "big",
      cost: { budgetHit: false, reads: 0 }, runCoverage: { postsBehindHorizon: 0, evicted: 0 }, knobs: KNOBS, stamp: digest.SYNC_STAMP, timeZone: TZ });
    assert.equal(step.reportDeferredReason, "oversize"); assert.equal(step.reports.length, 0); assert.equal(stepState.report.lastReportedDay, report.dayPlus(DAY, -1), "the day stays unreported");
    // The IO retry: a fake transaction that throws once while reports are present.
    const sets = [];
    let calls = 0;
    const runCommit = async (body) => {
      calls += 1;
      const tx = { get: async () => ({ ...io.encodeState(first.state), runId: next.state.runId }), set: (path, data) => { sets.push({ call: calls, path, data }); } };
      const result = await body(tx);
      if (calls === 1) { sets.length = 0; throw new Error("document too large"); }
      return result;
    };
    const encode = (state) => ({ runId: state.runId, report: JSON.stringify(state.report) });
    const logged = [];
    const outcome = await io.commitDigest(runCommit, next, next.published, next.state.runId, encode, { error: (message, fields) => logged.push({ message, fields }) });
    assert.equal(logged.length, 1); assert.deepEqual(logged[0].fields.days, [report.dayPlus(DAY, 1)]);
    assert.equal(calls, 2); assert.equal(outcome.committed, true); assert.equal(outcome.reportWriteFailed, "document too large"); assert.deepEqual(outcome.reportsWritten, []);
    assert.deepEqual(sets.map((s) => s.path), ["testControl/algorithmDigestState", "testControl/algorithmDigest"], "the retry carries no report document");
    assert.equal(JSON.parse(sets[0].data.report).lastReportedDay, DAY, "lastReportedDay unadvanced (restored to its pre-report value)");
    assert.equal(next.state.report.lastReportedDay, report.dayPlus(DAY, 1), "…while the in-memory outcome had advanced it");
    const ok = [];
    const good = await io.commitDigest(async (body) => body({ get: async () => ({ ...io.encodeState(first.state), runId: next.state.runId }), set: (path, data) => ok.push([path, data]) }), next, next.published, next.state.runId, encode);
    assert.deepEqual(good, { committed: true, reportsWritten: [report.dayPlus(DAY, 1)], reportWriteFailed: null });
    assert.deepEqual(ok.map(([path]) => path), ["testControl/algorithmDigestState", "testControl/algorithmDigest", `testControl/algorithmReports/daily/${report.dayPlus(DAY, 1)}`, "testControl/algorithmReports"]);
    assert.equal(JSON.parse(ok[0][1].report).lastReportedDay, report.dayPlus(DAY, 1));
    assert.ok(Array.isArray(ok[3][1].days), "the index is a full days array");
    // decode/encode round-trip of the report state and the day counters.
    const encoded = io.encodeState(next.state);
    assert.equal(typeof encoded.report, "string"); assert.equal(encoded.runsToday, next.state.runsToday); assert.deepEqual(encoded.readsPrev, next.state.readsPrev);
    const decoded = io.decodeState({ ...encoded, sweep: { ...encoded.sweep, cursorCreatedAt: null } });
    assert.deepEqual(decoded.report, next.state.report); assert.deepEqual(decoded.readsPrev, next.state.readsPrev); assert.equal(decoded.runsToday, next.state.runsToday);
    assert.deepEqual(io.decodeState({}).report, report.emptyReportState());
  }

  // ── Test 13 (part): the seedSeen null → 5,000 → null flicker inflates the digest's hash-based span, never the report's epochs ──
  {
    const world = worldOf();
    const created = T_D - 20 * D;
    const l = ledger().create(created);
    for (let i = 0; i < 31; i++) { l.engage(created + (i + 1) * MIN, "like", 1_000, `l${i}`); join(world, "post-v", `l${i}`, REAL[i]); }
    l.engage(created + 40 * MIN, "view", 1_000, "v0").engage(created + 41 * MIN, "view", 500, "v1").engage(created + 42 * MIN, "comment", 2_000, "c0").engage(created + 43 * MIN, "dislike", -1_000, "d0");
    for (const eid of ["v0", "v1", "c0", "d0"]) join(world, "post-v", eid, R2);
    addPost(world, "post-v", TA, created, l.rows, { organic: l.state().organic });
    const first = await run(world, digest.initialState(), created + D, { switches: switchesOff });
    assert.equal(first.state.observedPolicyVersions.length, 1);
    const quietThen = T_D - 10 * D;
    for (let i = 0; i < 40; i++) { l.engage(quietThen + i * MIN, "like", 1_000, `k${i}`); join(world, "post-v", `k${i}`, REAL[i]); }
    const second = await run(world, first.state, quietThen + 5 * H, { switches: switchesOff });
    assert.equal(second.state.observedPolicyVersions.length, 2, "the digest minted a version on the seedSeen flicker");
    // Catch-up runs 7 days per hour until the closed day is reported.
    let third = await run(world, second.state, T_NEXT + 45 * MIN, { switches: switchesOff });
    for (let i = 1; i < 6 && third.state.report.lastReportedDay !== DAY; i++) third = await run(world, third.state, T_NEXT + (45 + 60 * i) * MIN, { switches: switchesOff });
    const doc = third.reports.find((r) => r.day === DAY).document, evidence = JSON.parse(doc.evidence);
    assert.equal(doc.policy.production.observedPolicySpanned.d30.length, 2, "digest, hash-based");
    assert.equal(evidence.windows.d30.spanned.length, 1, "the report's own epochs: a null flicker is unseen, never changed");
    assert.equal(doc.epochs.length, 1);
    for (const knob of ["K1", "K2", "K3"]) assert.notEqual(verdictOf(doc, knob).reason, "mixed-policy", knob);
  }

  // ── Test 20: no identity leaves the state ──
  {
    const world = baseWorld();
    const out = await run(world, digest.initialState(), T_NEXT + 45 * MIN);
    const uids = out.state.payload.realActorUids;
    assert.equal(uids.length, 3);
    assert.ok(Object.keys(out.state.payload.days[DAY].realActorEntries).length === 3 && uids.every((uid) => uid in out.state.payload.days[DAY].realActorEntries), "the state holds them");
    const surfaces = [JSON.stringify(out.published), JSON.stringify(out.reportIndex), ...out.reports.map((r) => JSON.stringify(r.document)), ...out.reports.map((r) => r.document.evidence)];
    for (const text of surfaces) { for (const uid of uids) assert.ok(!text.includes(uid), "no uid leaves the state"); assert.ok(!text.includes("realActorEntries")); }
    // The daily simulation's owner uid (switches.simulationOwnerUid) rides the published digest by design (Admin-only, the
    // desk prints it); the report, its index and its CSV schema never carry it — masked to set/unset everywhere.
    assert.ok(surfaces[0].includes(MARK), "the digest carries it (pre-existing, desk-visible)");
    for (const text of surfaces.slice(1)) assert.ok(!text.includes(MARK), "the simulation owner uid never reaches a report document or the index");
    const masked = renderAt(grantsWorld().payload, DAY, { switches: switchesOn });
    assert.ok(!JSON.stringify(masked.document).includes(MARK), "…nor a non-backfilled report with snapshots");
    assert.equal(masked.evidence.snapshots.contamination.d7.simulationOwnerUid, "set");
    assert.equal(typeof masked.evidence.snapshots.contamination.d7.syntheticMeters, "number", "the rest of the block is copied");
    assert.equal(masked.document.policy.simulation.simulationOwnerUid, "set");
    assert.equal(renderAt(grantsWorld().payload, DAY, { switches: { ...switchesOn, simulationOwnerUid: "" } }).evidence.snapshots.contamination.d7.simulationOwnerUid, "unset");
    assert.equal(report.maskContamination(null), null); assert.deepEqual(report.maskContamination({ d7: { posts: [] } }), { d7: { posts: [] } });
    const csv = out.reports.at(-1).document.csvColumns;
    for (const table of ["verdicts", "metrics", "days", "posts"]) { assert.ok(Array.isArray(csv[table]) && csv[table].length); assert.ok(csv[table].every((column) => !column.includes("realActorEntries") && !uids.some((uid) => column.includes(uid)) && !column.includes(MARK))); }
    assert.ok(csv.days.some((column) => column.startsWith("people.")), "the people counts are the days CSV's columns");
    assert.ok(csv.identityPrefix.includes("appliedByReport") && csv.identityPrefix.includes("productionPaysValue"));
    const published = digest.publishedDay(out.state.payload.days[DAY], null);
    assert.equal(published.realActorEntries, undefined); assert.deepEqual(published.people, { actors: 3, viewers: 1, likers: 1, commenters: 1, maxShare: 0.3333 });
    assert.ok(out.published.days.every((row) => row.realActorEntries === undefined && row.people));
  }

  // ── Test 27: the feed pool check reads the sweep's postsCreated — synthetic-owned posts through the reader ──
  {
    // 40 simulation posts (sim-daily owners, `post-sim-` ids) and 2 more tester posts created on D. The sweep files EVERY
    // swept post by its creation day (P:1074) whether or not it registers — synthetic posts never do — so the check sees
    // them with 0 extra reads, on the first deploy's backfilled report.
    const simPosts = (world, dayStart, n, offset = 0) => { for (let i = 0; i < n; i++) { const t = dayStart + 2 * H + (offset + i) * MIN; addPost(world, `post-sim-${dayStart}-${i}`, SYN[i % SYN.length], t, ledger().create(t).rows, { lat: 43.7 + i * 0.0001 }); } };
    const world = baseWorld();
    simPosts(world, T_D, 40);
    addPost(world, "post-c", TA, T_D + 3 * H, ledger().create(T_D + 3 * H).rows, { lat: 43.68 });
    addPost(world, "post-d", TB, T_D + 4 * H, ledger().create(T_D + 4 * H).rows, { lat: 43.69 });
    const out = await run(world, digest.initialState(), T_NEXT + 45 * MIN);
    const doc = out.reports.find((r) => r.day === DAY).document;
    assert.equal(doc.backfilled, true, "first deploy: the closed day is backfilled");
    assert.equal(JSON.parse(doc.evidence).snapshots, null);
    assert.deepEqual(out.state.payload.days[DAY].postsCreated, { real: 2, owner: 0, review: 0, synthetic: 40, official: 0, lab: 0 });
    const check = doc.checks.find((c) => c.id === "feedPool");
    const perDay7 = (42 + 1 + 1) / 7; // post-a (D−3) and post-b (D−5) are inside the week
    assert.deepEqual(check, report.feedPoolCheck(out.state.payload, DAY, report.daysEnding(DAY, 7, TZ)));
    assert.deepEqual({ status: check.status, createdOnDay: check.createdOnDay, createdReal: check.createdReal, createdSynthetic: check.createdSynthetic, createdOfficial: check.createdOfficial, simShare: check.simShare, perDay7: check.perDay7 },
      { status: "clear", createdOnDay: 42, createdReal: 2, createdSynthetic: 40, createdOfficial: 0, simShare: 40 / 42, perDay7 });
    assert.equal(check.turnoverHoursWeb, digest.round(160 / (perDay7 / 24), 1)); assert.equal(check.turnoverHoursNative, digest.round(96 / (perDay7 / 24), 1));
    assert.ok(check.turnoverHoursWeb > 24, "a slow week: ≥ ½ simulation on D alone is not a watch");
    const dm3 = out.reports.find((r) => r.day === report.dayPlus(DAY, -3)).document.checks.find((c) => c.id === "feedPool");
    assert.equal(dm3.createdOnDay, 1); assert.equal(dm3.createdReal, 1); assert.equal(dm3.createdSynthetic, 0);
    assert.ok(dm3.text.startsWith(`≈ 0 pops/day over the 7 d ending ${report.dayPlus(DAY, -3)} (1 on ${report.dayPlus(DAY, -3)}: 0 simulation, 1 real, 0 official)`), dm3.text);
    // The measured shape through the reader: the six days before D at 200 simulation posts each → the web pool turns
    // over in < 24 h and D is 40/42 simulation → watch; the next run re-renders nothing and the number is stable.
    const busy = baseWorld();
    simPosts(busy, T_D, 40);
    addPost(busy, "post-c", TA, T_D + 3 * H, ledger().create(T_D + 3 * H).rows, { lat: 43.68 });
    addPost(busy, "post-d", TB, T_D + 4 * H, ledger().create(T_D + 4 * H).rows, { lat: 43.69 });
    for (let d = 1; d <= 6; d++) simPosts(busy, T_D - d * D, 200);
    const busyOut = await run(busy, digest.initialState(), T_NEXT + 45 * MIN);
    assert.equal(busyOut.cost.budgetHit, false);
    const busyDoc = busyOut.reports.find((r) => r.day === DAY).document;
    const busyCheck = busyDoc.checks.find((c) => c.id === "feedPool");
    const busyPerDay7 = (42 + 1 + 1 + 6 * 200) / 7;
    assert.equal(busyCheck.status, "watch");
    assert.equal(busyCheck.perDay7, busyPerDay7); assert.equal(busyCheck.turnoverHoursWeb, digest.round(160 / (busyPerDay7 / 24), 1)); assert.equal(busyCheck.turnoverHoursWeb, 21.6); assert.equal(busyCheck.turnoverHoursNative, 13);
    assert.equal(busyCheck.simShare, 40 / 42);
    assert.equal(busyCheck.text, `≈ 178 pops/day over the 7 d ending ${DAY} (42 on ${DAY}: 40 simulation, 2 real, 0 official) — the newest-96 pool (phone) turns over in ≈ 13.0 h and the newest-160 pool (web) in ≈ 21.6 h; a real pop leaves other testers' Feed and Map after that unless it is their own`);
    assert.equal(busyDoc.decision.kind === "verify", false, "a check, never a verify");
    assert.ok(!JSON.stringify(busyDoc).includes("sim-food"), "no synthetic uid reaches the report");
  }
}
