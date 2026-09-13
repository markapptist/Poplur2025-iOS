/**
 * Algorithm desk digest — the pure half.
 *
 * "Is the radius algorithm working on real people?" is answered from the
 * radiusHistory ledgers of the registered real and official posts, folded per
 * entry into a private state document and rendered as one published document
 * for the owner's desk. Every fold rule, classification call, confidence gate
 * and curve lives here and is exercised by scripts/testAlgorithmDigestPolicy.js
 * against an in-memory reader; algorithmDigest.ts owns Firestore and Auth.
 *
 * Design: /Users/matrix/Developer/.codex/algorithm-desk-design.md (§1–§3).
 * Knobs come from the synced policy module (src/shared, pinned by
 * scripts/testSharedSync.js) — nothing the owner can change is typed here.
 */
import { createHash } from "node:crypto";
import * as policy from "./shared/postEngagementPolicy";
import * as identity from "./shared/syntheticIdentity";
import stampJson from "./shared/sync-stamp.json";
import type { ReportState } from "./algorithmReportPolicy";
import { emptyReportState, hydrateReportState, runReportStep } from "./algorithmReportPolicy";

// ── Constants ───────────────────────────────────────────────────────────────

export const DIGEST_SCHEMA_VERSION = 1;
export const TIME_ZONE = "America/Toronto";
const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;

/** Confidence gates (§1.3): a REAL rate, average or percentile is never
 *  rendered below these; the document ships numerator, denominator and n. */
export const GATES = Object.freeze({ minEvents: 30, minPosts: 8, minChannelPosts: 5, minActors: 2 });

export const FIXED_READS_PER_RUN = 8;
export const WRITES_PER_RUN = 3;
export const LEASE_MS = 9 * 60_000;
export const SWEEP_MARGIN_MS = 60_000;
export const SWEEP_LOOKBACK_MS = 24 * HOUR_MS;
export const SWEEP_PAGE_SIZE = 200;
export const LEDGER_PAGE_SIZE = 500;
export const PASS_MINUTES = 60;
export const PASS_MINUTES_SLOW = 65;
export const PUBLISHED_GUARD_BYTES = 400_000;
export const PAYLOAD_TRIM_BYTES = 700_000;
export const PAYLOAD_HARD_BYTES = 900_000;
export const ACTOR_CACHE_LIMIT = 500;
export const MAP_KEY_LIMIT = 16;
export const OBSERVED_VERSIONS_LIMIT = 8;
export const OBSERVED_WINDOW_DAYS = 7;
export const CAD_PER_100K_READS = 0.05;
export const CLAMP_NEAR_CEILING_METERS = 2_000;
export const FOLD_DAY_RETENTION_DAYS = 400;
export const STALE_FOLD_DAYS = 90;
export const ANCHOR_ROWS = 8;
export const CONTAMINATION_ROWS = 20;
export const DECAY_WRITER = "radiusDecay";
export const BACKFILL_WRITER = "backfillRadiusHistory";
export const MAX_TRIAL_MULTIPLIER = 10;
/** Per-day real-actor entries (fold addition 3) are kept this long: d30 plus a 7-day `before` window plus slack. */
export const REAL_ACTOR_ENTRIES_DAYS = 45;

export interface DigestConfig {
  enabled: boolean; maxReadsPerRun: number; horizonMs: number; daysPublished: number; channelLimit: number;
  postLimit: number; registeredPostLimit: number; pollExpiredEveryRuns: number; refreshEveryRuns: number;
  resetRequestedAtMillis: number | null;
}
export const DEFAULT_CONFIG: DigestConfig = Object.freeze({
  enabled: true, maxReadsPerRun: 6000, horizonMs: 1_800_000, daysPublished: 30, channelLimit: 12, postLimit: 50,
  registeredPostLimit: 500, pollExpiredEveryRuns: 24, refreshEveryRuns: 24, resetRequestedAtMillis: null,
});

// ── Knobs (from the synced policy module + the sync stamp) ──────────────────

export interface SyncStamp {
  syncedAtMillis: number; policySha256: string; identitySha256: string;
  extracted: { seedMeters: number; boostDefaultMeters: number; boostDefaultHours: number; stressHalfLifeHours: number;
    sourceLines: Record<string, string> };
}
export const SYNC_STAMP = stampJson as unknown as SyncStamp;

export interface Knobs {
  firstViewMeters: number; likeMeters: number; dislikeMeters: number; commentMeters: number;
  repeatViewBaseMeters: number; repeatViewMinMs: number; repeatViewLifetimeMeters: number;
  decayPerDay: number; decayHalfLifeDays: number; decayFloorMeters: number; maxRadiusMeters: number;
  syntheticStressHalfLifeHours: number; seedMeters: number; boostDefaultMeters: number; boostDefaultHours: number;
}

/** The grants are literals inside the policy's radiusDelta, so they are
 *  measured by driving the synced mutation with a fresh actor rather than
 *  typed: "declared" on the desk is what the shipped source pays. */
function measuredGrant(kind: policy.PostEngagementKind, actor: policy.PostEngagementActorState): number {
  const post = { radiusMeters: 1_000_000, organicRadiusMeters: 1_000_000, seedRadiusMeters: 0, boostedRadiusMeters: 0 };
  return policy.calculatePostEngagementMutation(post, kind, 1_000_000_000_000, actor).radiusDeltaMeters;
}
export function repeatLifetime(base: number): number {
  let total = 0;
  for (let n = 0; n < 64; n++) { const meters = Math.floor(base / 2 ** n); if (meters <= 0) break; total += meters; }
  return total;
}
const FRESH_ACTOR: policy.PostEngagementActorState = { lastViewAtMillis: null };
export const KNOBS: Knobs = Object.freeze({
  firstViewMeters: measuredGrant("view", FRESH_ACTOR),
  likeMeters: measuredGrant("like", FRESH_ACTOR),
  dislikeMeters: measuredGrant("dislike", FRESH_ACTOR),
  commentMeters: measuredGrant("comment", FRESH_ACTOR),
  repeatViewBaseMeters: policy.REPEAT_VIEW_BASE_METERS,
  repeatViewMinMs: policy.REPEAT_VIEW_MIN_MS,
  repeatViewLifetimeMeters: repeatLifetime(policy.REPEAT_VIEW_BASE_METERS),
  decayPerDay: policy.RADIUS_DECAY_PER_DAY,
  decayHalfLifeDays: Math.round(Math.log(0.5) / Math.log(1 - policy.RADIUS_DECAY_PER_DAY) * 100) / 100,
  decayFloorMeters: policy.RADIUS_DECAY_FLOOR_METERS,
  maxRadiusMeters: policy.MAX_POST_RADIUS_METERS,
  syntheticStressHalfLifeHours: SYNC_STAMP.extracted.stressHalfLifeHours,
  seedMeters: SYNC_STAMP.extracted.seedMeters,
  boostDefaultMeters: SYNC_STAMP.extracted.boostDefaultMeters,
  boostDefaultHours: SYNC_STAMP.extracted.boostDefaultHours,
});
export const KNOBS_SOURCE = "functions-digest/src/shared/postEngagementPolicy.ts (synced copy) + sync-stamp.extracted";

/** Below this organic a 60-minute pass at ×1 loses exactly 1 m (the integer
 *  floor), so a per-entry rate says nothing about the multiplier. */
export const RATE_INFORMATIVE_MIN_ORGANIC = Math.floor(1 / (1 - Math.pow(1 - KNOBS.decayPerDay, 1 / 24)));

export function sha8(value: unknown): string {
  return createHash("sha256").update(canonicalJson(value)).digest("hex").slice(0, 8);
}
export function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(record[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}
/** What the source declares, in the same shape as the 7-day observed
 *  signature (§2.5), so the two versions agree exactly when production pays
 *  what the repo says and differ when a knob commit has not shipped. */
export function declaredSignature(knobs: Knobs = KNOBS): ObservedSignature {
  return { view: knobs.firstViewMeters, like: knobs.likeMeters, comment: knobs.commentMeters, dislike: knobs.dislikeMeters,
    repeatBase: knobs.repeatViewBaseMeters, seedSeen: knobs.seedMeters };
}
export function sourcePolicyVersion(knobs: Knobs = KNOBS): string { return sha8(declaredSignature(knobs)); }

// ── Time: calendar days in the owner's zone ─────────────────────────────────

const formatters = new Map<string, Intl.DateTimeFormat>();
export function dayKey(millis: number, timeZone = TIME_ZONE): string {
  let format = formatters.get(timeZone);
  if (!format) {
    format = new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" });
    formatters.set(timeZone, format);
  }
  return format.format(new Date(millis));
}
/** The last `count` calendar days ending on the day of `nowMillis`, oldest
 *  first. Half-day steps so a DST change can neither skip nor double a day. */
export function dayKeysEndingAt(nowMillis: number, count: number, timeZone = TIME_ZONE): string[] {
  const keys: string[] = [];
  for (let step = 0; keys.length < count && step < count * 4; step++) {
    const key = dayKey(nowMillis - step * 43_200_000, timeZone);
    if (!keys.includes(key)) keys.push(key);
  }
  return keys.reverse();
}
/** Midnight of a day key in the zone (whole-hour offsets only, which Toronto has). */
export function dayStartMillis(day: string, timeZone = TIME_ZONE): number {
  const [year, month, date] = day.split("-").map(Number);
  let cursor = Date.UTC(year, month - 1, date, 12);
  while (dayKey(cursor - HOUR_MS, timeZone) === day) cursor -= HOUR_MS;
  while (dayKey(cursor, timeZone) !== day) cursor += HOUR_MS;
  return cursor;
}

// ── Classes ─────────────────────────────────────────────────────────────────

export type PostClass = "official" | "lab" | "synthetic" | "real";
export type ActorClass = "owner" | "review" | "synthetic" | "real" | "unknown";
export type OwnerClass = "real" | "owner" | "review";
export type DecayMode = "normal" | "trial" | "stress" | "undetermined";
export type Surface = "feed" | "map" | "profile" | "unknown";
export type EngagementKind = policy.PostEngagementKind;
type ShortClass = "r" | "o";
type ShortOwner = "r" | "o" | "v";
type ShortActor = "r" | "o" | "v" | "s" | "u";

const ACTOR_SHORT: Record<ActorClass, ShortActor> = { real: "r", owner: "o", review: "v", synthetic: "s", unknown: "u" };
const ACTOR_LONG: Record<ShortActor, ActorClass> = { r: "real", o: "owner", v: "review", s: "synthetic", u: "unknown" };
const OWNER_LONG: Record<ShortOwner, OwnerClass> = { r: "real", o: "owner", v: "review" };
export const SURFACES: readonly Surface[] = ["feed", "map", "profile", "unknown"];
export const KINDS: readonly EngagementKind[] = policy.POST_ENGAGEMENT_KINDS;

export const postClass: (postId: string, post: Record<string, unknown>, ownerSynthetic: boolean) => PostClass = identity.postClass;
export const actorClass: (uid: string, profile: Record<string, unknown> | undefined, email: string | null, known: boolean) => ActorClass = identity.actorClass;
export const isSyntheticAccount: (uid: string, profile: Record<string, unknown> | undefined, email: string | null) => boolean = identity.isSyntheticAccount;

export function surfaceOf(value: unknown): Surface {
  return value === "feed" || value === "map" || value === "profile" ? value : "unknown";
}

// ── State ───────────────────────────────────────────────────────────────────

export interface LedgerCursor { atMillis: number; id: string }
/** The sweep cursor is the exact Timestamp the last document carried — a
 *  millisecond re-encoding sorts before a microsecond commit time and re-reads
 *  the last row of every page. */
export interface SweepCursor { seconds: number; nanoseconds: number; path: string }

export interface PostMeta {
  cls: ShortClass; ownerUid: string; ownerClass: ShortOwner; ch: string; createdAtMillis: number;
  lat: number | null; lng: number | null; hasCreate: boolean; cursor: LedgerCursor | null;
  live: boolean; expiredAtMillis: number | null; deletedAtMillis: number | null;
  viewCount: number; viewCountAtMillis: number | null;
  lastDecayAt: number | null; lastOrganic: number | null; lastSeed: number | null; lastBoost: number | null;
  decayAnchorMillis: number | null; decayOrganicPerDay: number | null; decaySeedPerDay: number | null; decayBoostPerDay: number | null;
  refreshedAtMillis: number | null; docRadiusMeters: number | null;
  createFetch: { requestedRun: number; lastRun: number | null } | null; registeredRun: number;
}
export interface FoldDay { gr: number; go: number; gv: number; gs: number; gu: number; dl: number; dlr: number; vc?: number }
export interface Pool { real: number; owner: number; review: number; syn: number; unknown: number }
export interface ModeMeters { normal: number; trial: number; stress: number; undetermined: number }
export interface ClassMeters { real: number; owner: number; review: number; synthetic: number; unknown: number }
export interface PostFold {
  seed: number; birthSeed: number; organic: number; boost: number; lastRadius: number;
  peak: number; peakOrganic: number; peakAtMillis: number | null; firstAt: number | null; lastAt: number | null;
  lastCause: string | null; n: number;
  gainReal: number; gainOwner: number; gainReview: number; gainSyn: number; gainUnknown: number;
  pool: Pool; lossDecay: { byMode: ModeMeters; byClass: Pool }; seedLoss: number; boostLoss: number;
  firstRealAt: number | null; lastRealAt: number | null; zeroAt: number | null;
  days: Record<string, FoldDay>; modeCounts: ModeMeters; decayPaths: { organic: number; boost: number; seed: number };
  boostExpiresAtMillis: number | null; lastDecayRate: number | null; seededFromEntry: boolean; everPumped: boolean;
  other: { synthetic: number; lab: number; backfill: number; unknown: number }; resync: number;
  /** Real-actor engagement entries by kind (view/like/comment/dislike), non-clamped — fold addition 1, forward-only. */
  rk: KindCounts;
}
export interface KindCounts { v: number; l: number; c: number; d: number }
export interface ActorGain {
  view: number; like: number; comment: number; dislike: number; total: number; n: number;
  firstViews: number; repeatViews: number; repeatMeters: number; clamped: number; resync: number;
  /** A dislike whose partial delta hit zero (fold addition 2): `gain.dislike` still took the partial delta,
   *  so dislikes are counted exactly as clamped + (|dislike m| − |clamped m|) / |grant|. */
  clampedDislikes: number; clampedDislikeMeters: number;
}
export interface SurfaceCounts { feed: number; map: number; profile: number; unknown: number }
export interface DayCell {
  day: string; observedPolicy: string | null;
  postsCreated: { real: number; owner: number; review: number; synthetic: number; official: number; lab: number };
  entries: { real: number; official: number; unknownCause: number };
  realPostGain: { real: ActorGain; owner: ActorGain; review: ActorGain; synthetic: ActorGain; unknown: ActorGain };
  realPostDecayLoss: { byMode: ModeMeters; byClass: ClassMeters; trialMultipliers: Record<string, number> };
  realPostSeedLoss: number; realPostBoostLoss: number;
  boosts: { n: number; meters: number };
  unknownActorEntries: { real: number; official: number };
  distinctRealViewers: number; distinctRealLikers: number; distinctRealCommenters: number;
  surfaces: SurfaceCounts; realSurfaces: SurfaceCounts;
  /** STATE ONLY (fold addition 3): non-clamped real engagement entries on real posts per uid per kind, ≤ 16 uids + "other".
   *  publishedDay strips it and publishes distinct counts; no uid reaches a published document. */
  realActorEntries: Record<string, KindCounts>;
}
export interface ObservedKind { byMeters: Record<string, number>; min: number | null; max: number | null; n: number }
export type ObservedDay = Record<string, ObservedKind>;
export interface LifetimeCoverage {
  entriesFolded: number; createFetched: number; createMissing: number; createSkipped: number;
  unknownCauses: Record<string, number>; resync: Record<string, number>; undeterminedMode: number;
  postsDeleted: number; evicted: number; sweptPosts: number; registryFull: boolean;
  /** runStart of the run that introduced the three fold additions on a payload that already held entries; 0 when
   *  they were introduced on an empty payload (every entry passed through the new code); null before either. */
  kindSplitSinceMillis: number | null;
}
export interface Payload {
  postMeta: Record<string, PostMeta>; folds: Record<string, PostFold>; actorClassByUid: Record<string, ShortActor>;
  realActorUids: string[]; days: Record<string, DayCell>; observed: Record<string, ObservedDay>; coverage: LifetimeCoverage;
}
export interface ObservedSignature {
  view: number | null; like: number | null; comment: number | null; dislike: number | null; repeatBase: number | null; seedSeen: number | null;
}
export interface ObservedVersion { version: string; fromMillis: number; signature: ObservedSignature }
export interface DigestState {
  version: number; digestVersion: number; runId: string | null; leaseUntilMillis: number;
  readsDay: string | null; readsToday: number; runsToday: number;
  /** The previous day's totals, stashed at the day roll so the report of D reads D's cost (§2.2 step 5). */
  readsPrev: { day: string | null; reads: number; runs: number } | null;
  sweep: { cursor: SweepCursor | null; coldStartDone: boolean };
  refresh: { lastRefreshDay: string | null };
  observedPolicyVersions: ObservedVersion[]; authPageFailedRuns: number; lastResetAtMillis: number;
  payload: Payload;
  /** The daily report's own state (algorithmReportPolicy.ts), stored as one JSON string beside `payload`. */
  report: ReportState;
}

export function emptyPayload(): Payload {
  return {
    postMeta: {}, folds: {}, actorClassByUid: {}, realActorUids: [], days: {}, observed: {},
    coverage: { entriesFolded: 0, createFetched: 0, createMissing: 0, createSkipped: 0, unknownCauses: {}, resync: {},
      undeterminedMode: 0, postsDeleted: 0, evicted: 0, sweptPosts: 0, registryFull: false, kindSplitSinceMillis: null },
  };
}
export function initialState(): DigestState {
  return {
    version: DIGEST_SCHEMA_VERSION, digestVersion: 0, runId: null, leaseUntilMillis: 0, readsDay: null, readsToday: 0, runsToday: 0, readsPrev: null,
    sweep: { cursor: null, coldStartDone: false }, refresh: { lastRefreshDay: null },
    observedPolicyVersions: [], authPageFailedRuns: 0, lastResetAtMillis: 0, payload: emptyPayload(), report: emptyReportState(),
  };
}

const zeroPool = (): Pool => ({ real: 0, owner: 0, review: 0, syn: 0, unknown: 0 });
const zeroModes = (): ModeMeters => ({ normal: 0, trial: 0, stress: 0, undetermined: 0 });
const zeroClasses = (): ClassMeters => ({ real: 0, owner: 0, review: 0, synthetic: 0, unknown: 0 });
const zeroSurfaces = (): SurfaceCounts => ({ feed: 0, map: 0, profile: 0, unknown: 0 });
const zeroGain = (): ActorGain => ({ view: 0, like: 0, comment: 0, dislike: 0, total: 0, n: 0, firstViews: 0, repeatViews: 0, repeatMeters: 0, clamped: 0, resync: 0, clampedDislikes: 0, clampedDislikeMeters: 0 });
const zeroKinds = (): KindCounts => ({ v: 0, l: 0, c: 0, d: 0 });
function newFold(): PostFold {
  return {
    seed: 0, birthSeed: 0, organic: 0, boost: 0, lastRadius: 0, peak: 0, peakOrganic: 0, peakAtMillis: null,
    firstAt: null, lastAt: null, lastCause: null, n: 0, gainReal: 0, gainOwner: 0, gainReview: 0, gainSyn: 0, gainUnknown: 0,
    pool: zeroPool(), lossDecay: { byMode: zeroModes(), byClass: zeroPool() }, seedLoss: 0, boostLoss: 0,
    firstRealAt: null, lastRealAt: null, zeroAt: null, days: {}, modeCounts: zeroModes(),
    decayPaths: { organic: 0, boost: 0, seed: 0 }, boostExpiresAtMillis: null, lastDecayRate: null,
    seededFromEntry: false, everPumped: false, other: { synthetic: 0, lab: 0, backfill: 0, unknown: 0 }, resync: 0, rk: zeroKinds(),
  };
}
export function emptyDayCell(day: string): DayCell {
  return {
    day, observedPolicy: null,
    postsCreated: { real: 0, owner: 0, review: 0, synthetic: 0, official: 0, lab: 0 },
    entries: { real: 0, official: 0, unknownCause: 0 },
    realPostGain: { real: zeroGain(), owner: zeroGain(), review: zeroGain(), synthetic: zeroGain(), unknown: zeroGain() },
    realPostDecayLoss: { byMode: zeroModes(), byClass: zeroClasses(), trialMultipliers: {} },
    realPostSeedLoss: 0, realPostBoostLoss: 0, boosts: { n: 0, meters: 0 }, unknownActorEntries: { real: 0, official: 0 },
    distinctRealViewers: 0, distinctRealLikers: 0, distinctRealCommenters: 0, surfaces: zeroSurfaces(), realSurfaces: zeroSurfaces(),
    realActorEntries: {},
  };
}
function ensureDay(payload: Payload, day: string): DayCell {
  return payload.days[day] ??= emptyDayCell(day);
}

// ── Stored form: compact on the way out, full shapes on the way in ─────────
//
// A day cell is ≈ 1.2 KB with every zero written out and ≈ 60 B without, so
// the state document stores the payload with zeros, nulls, falses and empty
// maps dropped and rebuilds the full shapes from these templates on load.

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}
function withDefaults<T>(template: T, stored: unknown): T {
  if (!isPlainObject(template) || !isPlainObject(stored)) return (stored === undefined ? template : stored) as T;
  const out: Record<string, unknown> = { ...stored };
  for (const [key, value] of Object.entries(template as Record<string, unknown>)) out[key] = withDefaults(value, out[key]);
  return out as T;
}
function compact(value: unknown, key = ""): unknown {
  if (Array.isArray(value)) return value.length ? value : undefined;
  if (isPlainObject(value)) {
    const out: Record<string, unknown> = {};
    for (const [childKey, child] of Object.entries(value)) {
      const compacted = compact(child, childKey);
      if (compacted !== undefined) out[childKey] = compacted;
    }
    return Object.keys(out).length ? out : undefined;
  }
  // A viewCount sample of 0 is a sample and a kind-split stamp of 0 means "since the beginning"; every other zero is a default.
  if (key !== "vc" && key !== "kindSplitSinceMillis" && (value === 0 || value === null || value === false || value === "")) return undefined;
  return value === undefined ? undefined : value;
}
const META_TEMPLATE: PostMeta = {
  cls: "r", ownerUid: "", ownerClass: "r", ch: "", createdAtMillis: 0, lat: null, lng: null, hasCreate: false, cursor: null, live: false,
  expiredAtMillis: null, deletedAtMillis: null, viewCount: 0, viewCountAtMillis: null, lastDecayAt: null, lastOrganic: null, lastSeed: null,
  lastBoost: null, decayAnchorMillis: null, decayOrganicPerDay: null, decaySeedPerDay: null, decayBoostPerDay: null, refreshedAtMillis: null,
  docRadiusMeters: null, createFetch: null, registeredRun: 0,
};
const FOLD_DAY_TEMPLATE: FoldDay = { gr: 0, go: 0, gv: 0, gs: 0, gu: 0, dl: 0, dlr: 0 };
const OBSERVED_KIND_TEMPLATE: ObservedKind = { byMeters: {}, min: null, max: null, n: 0 };

export function compactPayload(payload: Payload): Record<string, unknown> {
  return (compact(payload) ?? {}) as Record<string, unknown>;
}
export function compactPayloadBytes(payload: Payload): number { return JSON.stringify(compactPayload(payload)).length; }
export function hydratePayload(stored: unknown): Payload {
  const payload = withDefaults(emptyPayload(), isPlainObject(stored) ? stored : {});
  for (const [postId, meta] of Object.entries(payload.postMeta)) payload.postMeta[postId] = withDefaults(META_TEMPLATE, meta);
  for (const [postId, fold] of Object.entries(payload.folds)) {
    const full = withDefaults(newFold(), fold);
    for (const [day, cell] of Object.entries(full.days)) full.days[day] = withDefaults(FOLD_DAY_TEMPLATE, cell);
    payload.folds[postId] = full;
  }
  for (const postId of Object.keys(payload.postMeta)) payload.folds[postId] ??= newFold();
  for (const [day, cell] of Object.entries(payload.days)) {
    const full = withDefaults(emptyDayCell(day), cell);
    for (const [uid, counts] of Object.entries(full.realActorEntries)) full.realActorEntries[uid] = withDefaults(zeroKinds(), counts);
    payload.days[day] = full;
  }
  for (const observedDay of Object.values(payload.observed)) {
    for (const [key, slot] of Object.entries(observedDay)) observedDay[key] = withDefaults(OBSERVED_KIND_TEMPLATE, slot);
  }
  return payload;
}

// ── Number helpers ──────────────────────────────────────────────────────────

function finite(value: unknown): number | null {
  const number = typeof value === "number" ? value : Number(value);
  return typeof value !== "boolean" && value !== null && value !== "" && Number.isFinite(number) ? number : null;
}
function meters(value: unknown, fallback = 0): number { return finite(value) ?? fallback; }
export function millisOf(value: unknown): number | null {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (!value || typeof value !== "object") return null;
  const stamp = value as { toMillis?: () => number; seconds?: unknown; _seconds?: unknown; nanoseconds?: unknown; _nanoseconds?: unknown };
  if (typeof stamp.toMillis === "function") { const millis = Number(stamp.toMillis()); return Number.isFinite(millis) ? millis : null; }
  const seconds = finite(stamp.seconds ?? stamp._seconds);
  if (seconds == null) return null;
  const nanos = finite(stamp.nanoseconds ?? stamp._nanoseconds) ?? 0;
  return seconds * 1000 + Math.floor(nanos / 1_000_000);
}
export function round(value: number, places = 0): number { const scale = 10 ** places; return Math.round(value * scale) / scale; }
function sumPool(pool: Pool): number { return pool.real + pool.owner + pool.review + pool.syn + pool.unknown; }
function poolShares(pool: Pool): Pool {
  const total = sumPool(pool);
  if (total <= 0) return { real: 0, owner: 0, review: 0, syn: 0, unknown: 1 };
  return { real: pool.real / total, owner: pool.owner / total, review: pool.review / total, syn: pool.syn / total, unknown: pool.unknown / total };
}
function bumpKey(map: Record<string, number>, key: string, limit = MAP_KEY_LIMIT): void {
  const slot = key in map || Object.keys(map).length < limit ? key : "other";
  map[slot] = (map[slot] ?? 0) + 1;
}
export function median(values: number[]): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}
function percentile(values: number[], p: number): number | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.max(0, Math.ceil(p * sorted.length) - 1))];
}
export function modeKey(map: Record<string, number>): number | null {
  let best: string | null = null;
  for (const key of Object.keys(map).filter((k) => k !== "other").sort((a, b) => Number(a) - Number(b))) {
    if (best == null || map[key] > map[best]) best = key;
  }
  return best == null ? null : Number(best);
}
export function maxKey(map: Record<string, number>): number | null {
  const keys = Object.keys(map).filter((k) => k !== "other").map(Number);
  return keys.length ? Math.max(...keys) : null;
}
/** Recursive numeric sum of matching keys — window cells are day cells added up. */
function addInto(target: Record<string, unknown>, source: Record<string, unknown>): void {
  for (const [key, value] of Object.entries(source)) {
    if (typeof value === "number") target[key] = (Number(target[key]) || 0) + value;
    else if (value && typeof value === "object" && !Array.isArray(value)) {
      const nested = (target[key] ??= {}) as Record<string, unknown>;
      addInto(nested, value as Record<string, unknown>);
    }
  }
}
export function deepClone<T>(value: T): T { return JSON.parse(JSON.stringify(value)) as T; }
const EARTH_RADIUS_METERS = 6_371_000;
export function haversineMeters(aLat: number, aLng: number, bLat: number, bLng: number): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLng / 2) ** 2;
  return EARTH_RADIUS_METERS * 2 * Math.asin(Math.min(1, Math.sqrt(h)));
}

// ── Config and switches ─────────────────────────────────────────────────────

export function digestConfig(raw: Record<string, unknown> | undefined | null): DigestConfig {
  const source = raw ?? {};
  const positive = (key: keyof DigestConfig, fallback: number) => {
    const value = finite(source[key]);
    return value != null && value > 0 ? Math.floor(value) : fallback;
  };
  const reset = finite(source.resetRequestedAtMillis);
  return {
    enabled: source.enabled !== false,
    maxReadsPerRun: positive("maxReadsPerRun", DEFAULT_CONFIG.maxReadsPerRun),
    horizonMs: positive("horizonMs", DEFAULT_CONFIG.horizonMs),
    daysPublished: Math.min(30, positive("daysPublished", DEFAULT_CONFIG.daysPublished)),
    channelLimit: positive("channelLimit", DEFAULT_CONFIG.channelLimit),
    postLimit: positive("postLimit", DEFAULT_CONFIG.postLimit),
    registeredPostLimit: positive("registeredPostLimit", DEFAULT_CONFIG.registeredPostLimit),
    pollExpiredEveryRuns: positive("pollExpiredEveryRuns", DEFAULT_CONFIG.pollExpiredEveryRuns),
    refreshEveryRuns: positive("refreshEveryRuns", DEFAULT_CONFIG.refreshEveryRuns),
    resetRequestedAtMillis: reset != null && reset > 0 ? reset : null,
  };
}

export interface DecayTrialSwitch {
  enabled: boolean; multiplier: number | null; scope: string | null; effectiveAtMillis: number | null; boostedEffectiveAtMillis: number | null;
}
export interface Switches {
  simulationEnabled: boolean; runnerEnabled: boolean; dailySimulationEnabled: boolean; simulationOwnerUid: string;
  decayTrial: DecayTrialSwitch | null; dueDecayEnabled: boolean; sampledAtMillis: number;
}
export function readSwitches(docs: {
  simulation?: Record<string, unknown> | null; runner?: Record<string, unknown> | null; daily?: Record<string, unknown> | null;
  trial?: Record<string, unknown> | null; mapConfig?: Record<string, unknown> | null;
}, sampledAtMillis: number): Switches {
  const trial = docs.trial;
  return {
    simulationEnabled: docs.simulation?.enabled === true,
    runnerEnabled: docs.runner?.enabled === true,
    dailySimulationEnabled: docs.daily?.enabled === true,
    simulationOwnerUid: typeof docs.daily?.ownerUid === "string" ? docs.daily.ownerUid : "",
    decayTrial: trial ? {
      enabled: trial.enabled === true,
      multiplier: finite(trial.multiplier),
      scope: typeof trial.scope === "string" ? trial.scope : null,
      effectiveAtMillis: finite(trial.effectiveAtMillis),
      boostedEffectiveAtMillis: finite(trial.boostedEffectiveAtMillis),
    } : null,
    dueDecayEnabled: docs.mapConfig?.dueDecayEnabled === true,
    sampledAtMillis,
  };
}
/** The trial as calculateRadiusDecay would see it (radiusDecay.ts:82). */
export function liveTrial(switches: Switches): { multiplier: number; effectiveAtMillis: number; boostedEffectiveAtMillis?: number } | undefined {
  const trial = switches.decayTrial;
  if (!trial?.enabled || trial.multiplier == null || trial.effectiveAtMillis == null) return undefined;
  return { multiplier: trial.multiplier, effectiveAtMillis: trial.effectiveAtMillis,
    ...(trial.boostedEffectiveAtMillis != null ? { boostedEffectiveAtMillis: trial.boostedEffectiveAtMillis } : {}) };
}

// ── Ledger entries ──────────────────────────────────────────────────────────

export interface LedgerRow { id: string; data: Record<string, unknown> }
export interface ParsedEntry {
  id: string; atMillis: number; cause: string; writer: string; radiusMeters: number; organicRadiusMeters: number;
  seedRadiusMeters: number; boostedRadiusMeters: number; delta: number; organicDelta: number;
  kind: EngagementKind | null; engagementId: string | null; boostExpiresAtMillis: number | null;
}
export type EntryRoute = "engagement" | "decay" | "create" | "boost" | "synthetic" | "lab" | "backfill" | "unknown";

export function parseEntry(row: LedgerRow): ParsedEntry {
  const data = row.data;
  const kind = typeof data.kind === "string" && (KINDS as readonly string[]).includes(data.kind) ? data.kind as EngagementKind : null;
  return {
    id: row.id, atMillis: meters(data.atMillis, millisOf(data.at) ?? 0),
    cause: typeof data.cause === "string" ? data.cause : "", writer: typeof data.writer === "string" ? data.writer : "",
    radiusMeters: meters(data.radiusMeters), organicRadiusMeters: meters(data.organicRadiusMeters),
    seedRadiusMeters: meters(data.seedRadiusMeters), boostedRadiusMeters: meters(data.boostedRadiusMeters),
    delta: meters(data.delta), organicDelta: meters(data.organicDelta), kind,
    engagementId: typeof data.engagementId === "string" && data.engagementId ? data.engagementId : null,
    boostExpiresAtMillis: finite(data.boostExpiresAtMillis),
  };
}
/** §1.2 partition: decay counts only when the functions worker wrote it —
 *  the lab writes `decay` (and `growth`) under writer radius-lab. */
export function entryRoute(entry: ParsedEntry): EntryRoute {
  switch (entry.cause) {
    case "engagement": return "engagement";
    case "create": return "create";
    case "boost": return "boost";
    case "decay": return entry.writer === DECAY_WRITER ? "decay" : "unknown";
    case "synthetic": case "lab": case "backfill": return entry.cause;
    default: return "unknown";
  }
}
/** Grants are exact below the ceiling; clipped entries say nothing about knobs. */
export function isClamped(entry: ParsedEntry, knobs: Knobs = KNOBS): boolean {
  if (entry.radiusMeters >= knobs.maxRadiusMeters) return true;
  const delta = entry.organicDelta;
  if (entry.kind === "dislike" && delta < 0 && delta > knobs.dislikeMeters) return true;
  if (entry.radiusMeters >= knobs.maxRadiusMeters - CLAMP_NEAR_CEILING_METERS) {
    if (entry.kind === "like" && delta < knobs.likeMeters) return true;
    if (entry.kind === "comment" && delta < knobs.commentMeters) return true;
    if (entry.kind === "view" && delta < knobs.firstViewMeters) return true;
  }
  return false;
}

// ── Decay mode, inferred per entry ──────────────────────────────────────────

export interface DecayInferenceInput {
  entry: ParsedEntry; prev: { organic: number; seed: number; boost: number }; lastDecayAt: number | null;
  seedDrop: number; boostDrop: number;
  projection: { refreshedAtMillis: number | null; decayAnchorMillis: number | null; decayOrganicPerDay: number | null;
    decaySeedPerDay: number | null; decayBoostPerDay: number | null };
  knobs?: Knobs;
}
export interface DecayInference { mode: DecayMode; multiplier: number | null; rule: 0 | 1 | 2 | 3 }

/** What the synced decay step would leave of `previous` after `elapsedMs` at
 *  multiplier m — the fold's predictions use the shipped arithmetic, floor included. */
export function predictDecayed(previous: number, elapsedMs: number, multiplier: number, from: number, knobs: Knobs = KNOBS): number {
  const post = { organicRadiusMeters: previous, seedRadiusMeters: 0, boostedRadiusMeters: 0, radiusMeters: previous, decayedAt: from };
  const trial = multiplier > 1 ? { multiplier, effectiveAtMillis: from } : undefined;
  const next = policy.calculateRadiusDecay(post, from + elapsedMs, knobs.decayPerDay, trial);
  return next ? next.organicRadiusMeters : previous;
}
function predictStress(previous: number, elapsedMs: number, knobs: Knobs): number {
  const next = Math.floor(previous * 2 ** (-elapsedMs / (knobs.syntheticStressHalfLifeHours * HOUR_MS)));
  return next < knobs.decayFloorMeters ? 0 : next;
}
/** Nearest multiplier 1..10 by prediction; the multiplier is null on a tie (never a guess). */
function nearestMultiplier(previous: number, observed: number, elapsedMs: number, from: number, knobs: Knobs): { multiplier: number | null; distance: number } {
  let best: { m: number; distance: number }[] = [];
  for (let m = 1; m <= MAX_TRIAL_MULTIPLIER; m++) {
    const distance = Math.abs(predictDecayed(previous, elapsedMs, m, from, knobs) - observed);
    if (best.length === 0 || distance < best[0].distance) best = [{ m, distance }];
    else if (distance === best[0].distance) best.push({ m, distance });
  }
  return { multiplier: best.length === 1 ? best[0].m : null, distance: best[0].distance };
}
export function multiplierFromPerDay(perDay: number, ratePerDay: number): number {
  if (!(perDay > 0) || perDay >= 1) return 1;
  return Math.max(1, Math.min(MAX_TRIAL_MULTIPLIER, Math.round(Math.log(1 - perDay) / Math.log(1 - ratePerDay))));
}

export function inferDecayMode(input: DecayInferenceInput): DecayInference {
  const knobs = input.knobs ?? KNOBS;
  const { entry, prev, projection } = input;
  const from = input.lastDecayAt;
  const elapsed = from != null && entry.atMillis > from ? entry.atMillis - from : null;
  const informative = (value: number) => value >= RATE_INFORMATIVE_MIN_ORGANIC;
  // Rule 1: outside a trial the seed and boost components are preserved, so
  // a drop in either is a trial — unless the component fell at the stress
  // rate (the sim's retention decay expires the seed too, an order of
  // magnitude faster than any multiplier).
  if (input.seedDrop > 0 || input.boostDrop > 0) {
    let multiplier: number | null = null;
    let stress = false;
    if (elapsed != null && from != null) {
      const component = informative(prev.organic) ? { previous: prev.organic, next: entry.organicRadiusMeters }
        : input.seedDrop > 0 && informative(prev.seed) ? { previous: prev.seed, next: entry.seedRadiusMeters }
        : input.boostDrop > 0 && informative(prev.boost) ? { previous: prev.boost, next: entry.boostedRadiusMeters } : null;
      if (component) {
        const nearest = nearestMultiplier(component.previous, component.next, elapsed, from, knobs);
        multiplier = nearest.multiplier;
        stress = Math.abs(predictStress(component.previous, elapsed, knobs) - component.next) < nearest.distance;
      }
    }
    return stress ? { mode: "stress", multiplier: null, rule: 1 } : { mode: "trial", multiplier, rule: 1 };
  }
  // Rule 2: the entry's own rate over the gap since the previous decay entry.
  if (elapsed != null && from != null && informative(prev.organic)) {
    const observed = entry.organicRadiusMeters;
    const candidates: { mode: DecayMode; multiplier: number | null; distance: number }[] = [];
    for (let m = 1; m <= MAX_TRIAL_MULTIPLIER; m++) {
      candidates.push({ mode: m === 1 ? "normal" : "trial", multiplier: m === 1 ? null : m,
        distance: Math.abs(predictDecayed(prev.organic, elapsed, m, from, knobs) - observed) });
    }
    candidates.push({ mode: "stress", multiplier: null, distance: Math.abs(predictStress(prev.organic, elapsed, knobs) - observed) });
    candidates.sort((a, b) => a.distance - b.distance);
    if (candidates[0].distance < candidates[1].distance) return { mode: candidates[0].mode, multiplier: candidates[0].multiplier, rule: 2 };
  }
  // Rule 3: the post's projection fields, for entries the last refresh can vouch for.
  const vouched = projection.refreshedAtMillis != null && projection.decayOrganicPerDay != null
    && (entry.atMillis >= projection.refreshedAtMillis || entry.atMillis === projection.decayAnchorMillis);
  if (vouched) {
    if (projection.decayAnchorMillis === 0) return { mode: "stress", multiplier: null, rule: 3 };
    const multiplier = multiplierFromPerDay(projection.decayOrganicPerDay ?? 0, knobs.decayPerDay);
    if ((projection.decaySeedPerDay ?? 0) > 0 || (projection.decayBoostPerDay ?? 0) > 0 || multiplier > 1) {
      return { mode: "trial", multiplier, rule: 3 };
    }
    return { mode: "normal", multiplier: null, rule: 3 };
  }
  return { mode: "undetermined", multiplier: null, rule: 0 };
}

// ── The fold ────────────────────────────────────────────────────────────────

export interface ResolvedActor { cls: ActorClass; surface: Surface; joined: boolean; uid?: string | null }
export const UNJOINED_ACTOR: ResolvedActor = Object.freeze({ cls: "unknown", surface: "unknown", joined: false, uid: null });
export interface FoldRun { knobs: Knobs; timeZone: string; digestVersion: number; touchedDays: Set<string> }

function poolKey(cls: ActorClass): keyof Pool { return cls === "synthetic" ? "syn" : cls; }
function observe(payload: Payload, day: string, key: string, value: number | null): void {
  const observedDay = payload.observed[day] ??= {};
  const slot = observedDay[key] ??= { byMeters: {}, min: null, max: null, n: 0 };
  slot.n += 1;
  if (value == null) return;
  bumpKey(slot.byMeters, String(value));
  slot.min = slot.min == null ? value : Math.min(slot.min, value);
  slot.max = slot.max == null ? value : Math.max(slot.max, value);
}
function addGain(fold: PostFold, day: FoldDay, cls: ActorClass, delta: number): void {
  switch (cls) {
    case "real": fold.gainReal += delta; day.gr += delta; break;
    case "owner": fold.gainOwner += delta; day.go += delta; break;
    case "review": fold.gainReview += delta; day.gv += delta; break;
    case "synthetic": fold.gainSyn += delta; day.gs += delta; break;
    default: fold.gainUnknown += delta; day.gu += delta;
  }
}

/**
 * One ledger entry into the state. Pure and synchronous: the actor is resolved
 * by the caller (a join on the private engagement document), so the same
 * entries in the same order always produce the same state.
 */
export function foldEntry(payload: Payload, postId: string, entry: ParsedEntry, actor: ResolvedActor | null, run: FoldRun): void {
  const meta = payload.postMeta[postId];
  if (!meta) return;
  const fold = payload.folds[postId] ??= newFold();
  const coverage = payload.coverage;
  const route = entryRoute(entry);
  const day = dayKey(entry.atMillis, run.timeZone);
  const isReal = meta.cls === "r";
  const knobs = run.knobs;

  if (route === "create") {
    // Decision 4: the create point folds exactly once, whichever route met it.
    if (meta.hasCreate) { coverage.createSkipped += 1; return; }
    meta.hasCreate = true;
    run.touchedDays.add(day);
    ensureDay(payload, day).entries[isReal ? "real" : "official"] += 1;
    coverage.entriesFolded += 1;
    fold.birthSeed = entry.seedRadiusMeters;
    fold.firstAt = fold.firstAt == null ? entry.atMillis : Math.min(fold.firstAt, entry.atMillis);
    if (fold.n === 0) {
      fold.seed = entry.seedRadiusMeters; fold.organic = entry.organicRadiusMeters; fold.boost = entry.boostedRadiusMeters;
      fold.lastRadius = entry.radiusMeters; fold.peak = entry.radiusMeters; fold.peakOrganic = entry.organicRadiusMeters;
      fold.peakAtMillis = entry.organicRadiusMeters > 0 ? entry.atMillis : null;
      if (entry.organicRadiusMeters > 0) { fold.pool.unknown = entry.organicRadiusMeters; fold.everPumped = true; }
      fold.lastAt = entry.atMillis; fold.lastCause = "create";
    }
    fold.n += 1;
    if (isReal && meta.ownerClass === "r") observe(payload, day, "seed", entry.seedRadiusMeters);
    return;
  }

  run.touchedDays.add(day);
  const cell = ensureDay(payload, day);
  const foldDay = fold.days[day] ??= { gr: 0, go: 0, gv: 0, gs: 0, gu: 0, dl: 0, dlr: 0 };
  let prev = { radius: fold.lastRadius, organic: fold.organic, seed: fold.seed, boost: fold.boost };
  if (fold.n === 0) {
    // No create yet: the post's history starts at the reach this entry stepped from.
    prev = { radius: entry.radiusMeters - entry.delta, organic: entry.organicRadiusMeters - entry.organicDelta,
      seed: entry.seedRadiusMeters, boost: entry.boostedRadiusMeters };
    fold.seededFromEntry = true; fold.birthSeed = entry.seedRadiusMeters; fold.firstAt = entry.atMillis;
    fold.lastRadius = prev.radius; fold.organic = prev.organic; fold.seed = prev.seed; fold.boost = prev.boost;
    fold.peak = prev.radius; fold.peakOrganic = Math.max(0, prev.organic);
    if (prev.organic > 0) { fold.pool.unknown = prev.organic; fold.everPumped = true; }
    if (!meta.hasCreate && !meta.createFetch) meta.createFetch = { requestedRun: run.digestVersion, lastRun: null };
  }
  coverage.entriesFolded += 1;
  cell.entries[isReal ? "real" : "official"] += 1;

  // The organic pool by source class: credits go to the actor's bucket,
  // losses come out of every bucket in proportion (§1.2).
  const sharesBefore = poolShares(fold.pool);
  const credit: keyof Pool = route === "engagement" ? poolKey((actor ?? UNJOINED_ACTOR).cls) : "unknown";
  const organicAfter = Math.max(0, entry.organicRadiusMeters);
  const poolTotal = sumPool(fold.pool);
  if (organicAfter <= 0) fold.pool = zeroPool();
  else if (organicAfter > poolTotal) {
    fold.pool[credit] += organicAfter - poolTotal;
    if (credit !== "real") fold.everPumped = true;
  } else if (organicAfter < poolTotal) {
    const scale = organicAfter / poolTotal;
    for (const key of Object.keys(fold.pool) as (keyof Pool)[]) fold.pool[key] *= scale;
  }

  if (route === "engagement") {
    const resolved = actor ?? UNJOINED_ACTOR;
    const cls = resolved.cls;
    const kind = entry.kind;
    const delta = entry.organicDelta;
    const resync = delta === 0 && entry.delta !== 0;
    if (cls === "unknown") cell.unknownActorEntries[isReal ? "real" : "official"] += 1;
    // The surface label lives on the private engagement document (owner
    // decision, 11 Sep): counted only where that document was read.
    if (resolved.joined) {
      cell.surfaces[resolved.surface] += 1;
      if (isReal && cls === "real") cell.realSurfaces[resolved.surface] += 1;
    }
    const gain = isReal ? cell.realPostGain[cls] : null;
    if (resync) {
      // A stale stored total re-synced: the ledger moved, the policy paid nothing.
      fold.resync += 1;
      if (gain) gain.resync += 1;
      bumpKey(coverage.resync, kind ?? "none");
      observe(payload, day, "resync", null);
    } else {
      const clamped = isClamped(entry, knobs);
      const firstView = kind === "view" && delta === knobs.firstViewMeters;
      const repeatView = kind === "view" && delta > 0 && delta < knobs.firstViewMeters;
      if (gain) {
        gain.n += 1; gain.total += delta;
        if (kind) gain[kind] += delta;
        if (clamped) {
          gain.clamped += 1;
          if (kind === "dislike") { gain.clampedDislikes += 1; gain.clampedDislikeMeters += delta; }
        }
        else if (firstView) gain.firstViews += 1;
        else if (repeatView) { gain.repeatViews += 1; gain.repeatMeters += delta; }
      }
      if (isReal && cls === "real" && !clamped) {
        if (firstView) cell.distinctRealViewers += 1;
        if (kind === "like" && delta > 0) cell.distinctRealLikers += 1;
        if (kind === "comment" && delta > 0) cell.distinctRealCommenters += 1;
        if (kind) {
          const short = kind === "view" ? "v" : kind === "like" ? "l" : kind === "comment" ? "c" : "d";
          fold.rk[short] += 1;
          // Per uid per kind, the bumpKey discipline: the 17th uid and beyond share "other" (≤ 1 person, conservative).
          const uid = resolved.uid || "other";
          const slot = uid in cell.realActorEntries || Object.keys(cell.realActorEntries).length < MAP_KEY_LIMIT ? uid : "other";
          (cell.realActorEntries[slot] ??= zeroKinds())[short] += 1;
        }
      }
      addGain(fold, foldDay, cls, delta);
      if (cls === "real") { fold.firstRealAt ??= entry.atMillis; fold.lastRealAt = entry.atMillis; }
      if (clamped) observe(payload, day, "clamped", null);
      else if (kind && entry.writer !== BACKFILL_WRITER) observe(payload, day, repeatView ? "repeat" : kind, delta);
    }
  } else if (route === "decay") {
    const loss = Math.max(0, -entry.organicDelta);
    const seedDrop = Math.max(0, prev.seed - entry.seedRadiusMeters);
    // A boost that lapsed at its expiry is not the trial decaying it.
    const boostExpired = entry.boostedRadiusMeters === 0 && fold.boostExpiresAtMillis != null && entry.atMillis >= fold.boostExpiresAtMillis;
    const boostDrop = boostExpired ? 0 : Math.max(0, prev.boost - entry.boostedRadiusMeters);
    const inference = inferDecayMode({
      entry, prev, lastDecayAt: meta.lastDecayAt, seedDrop, boostDrop, knobs,
      projection: { refreshedAtMillis: meta.refreshedAtMillis, decayAnchorMillis: meta.decayAnchorMillis,
        decayOrganicPerDay: meta.decayOrganicPerDay, decaySeedPerDay: meta.decaySeedPerDay, decayBoostPerDay: meta.decayBoostPerDay },
    });
    const mode = inference.mode;
    fold.lossDecay.byMode[mode] += loss;
    for (const key of Object.keys(sharesBefore) as (keyof Pool)[]) fold.lossDecay.byClass[key] += loss * sharesBefore[key];
    foldDay.dl += loss; foldDay.dlr += loss * sharesBefore.real;
    fold.seedLoss += seedDrop; fold.boostLoss += boostDrop; fold.modeCounts[mode] += 1;
    if (loss > 0) fold.decayPaths.organic += 1;
    if (seedDrop > 0) fold.decayPaths.seed += 1;
    if (boostDrop > 0) fold.decayPaths.boost += 1;
    if (isReal) {
      const dayLoss = cell.realPostDecayLoss;
      dayLoss.byMode[mode] += loss;
      dayLoss.byClass.real += loss * sharesBefore.real; dayLoss.byClass.owner += loss * sharesBefore.owner;
      dayLoss.byClass.review += loss * sharesBefore.review; dayLoss.byClass.synthetic += loss * sharesBefore.syn;
      dayLoss.byClass.unknown += loss * sharesBefore.unknown;
      cell.realPostSeedLoss += seedDrop; cell.realPostBoostLoss += boostDrop;
      if (inference.multiplier != null) bumpKey(dayLoss.trialMultipliers, String(inference.multiplier));
    }
    if (mode === "undetermined") coverage.undeterminedMode += 1;
    fold.lastDecayRate = prev.radius > 0 ? Math.max(0, -entry.delta) / prev.radius : null;
    meta.lastDecayAt = entry.atMillis; meta.lastOrganic = entry.organicRadiusMeters;
    meta.lastSeed = entry.seedRadiusMeters; meta.lastBoost = entry.boostedRadiusMeters;
  } else if (route === "boost") {
    fold.boostExpiresAtMillis = entry.boostExpiresAtMillis;
    if (isReal) { cell.boosts.n += 1; cell.boosts.meters += entry.delta; }
    observe(payload, day, "boost", entry.delta);
    if (entry.boostExpiresAtMillis != null) observe(payload, day, "boostHours", Math.round((entry.boostExpiresAtMillis - entry.atMillis) / HOUR_MS));
  } else if (route === "unknown") {
    // Counted, never dropped: the radius moved, so the post state follows it
    // and any organic it added is booked to nobody in particular.
    fold.other.unknown += 1; cell.entries.unknownCause += 1;
    bumpKey(coverage.unknownCauses, entry.cause || "(none)");
    if (entry.organicDelta > 0) addGain(fold, foldDay, "unknown", entry.organicDelta);
  } else {
    fold.other[route] += 1;
  }

  fold.organic = entry.organicRadiusMeters; fold.seed = entry.seedRadiusMeters; fold.boost = entry.boostedRadiusMeters;
  fold.lastRadius = entry.radiusMeters;
  fold.peak = Math.max(fold.peak, entry.radiusMeters);
  if (entry.organicRadiusMeters > fold.peakOrganic) { fold.peakOrganic = entry.organicRadiusMeters; fold.peakAtMillis = entry.atMillis; }
  fold.n += 1; fold.lastAt = fold.lastAt == null ? entry.atMillis : Math.max(fold.lastAt, entry.atMillis); fold.lastCause = entry.cause;
  if (entry.radiusMeters <= 0) {
    fold.zeroAt ??= entry.atMillis; fold.pool = zeroPool();
    meta.live = false; meta.expiredAtMillis ??= entry.atMillis;
  } else if (fold.zeroAt != null) {
    fold.zeroAt = null; meta.live = meta.deletedAtMillis == null; meta.expiredAtMillis = null;
  }
}

// ── Registration and refresh (0 reads beyond the document already read) ─────

export interface SweepRow { id: string; path: string; data: Record<string, unknown>; createdAt: { seconds: number; nanoseconds: number } }

function postOwner(post: Record<string, unknown>): string {
  for (const key of ["userID", "userId", "ownerUid", "uid"]) if (typeof post[key] === "string" && post[key]) return post[key] as string;
  return "";
}
function coordinate(value: unknown, limit: number): number | null {
  const number = finite(value);
  return number != null && Math.abs(number) <= limit ? number : null;
}
function ownerShort(cls: ActorClass): ShortOwner { return cls === "owner" ? "o" : cls === "review" ? "v" : "r"; }

/** Reads the current parts and projection fields off a post document. */
function applyPostDocument(meta: PostMeta, fold: PostFold | undefined, post: Record<string, unknown>, nowMillis: number, day: string): void {
  const parts = policy.postRadiusParts(post, nowMillis);
  const status = post.visibilityStatus ?? post.status;
  meta.viewCount = Math.max(0, Math.floor(meters(post.viewCount)));
  meta.viewCountAtMillis = nowMillis;
  meta.docRadiusMeters = parts.stored ?? parts.total;
  meta.refreshedAtMillis = nowMillis;
  meta.decayAnchorMillis = finite(post.radiusDecayAnchorMillis);
  meta.decayOrganicPerDay = finite(post.radiusDecayOrganicPerDay);
  meta.decaySeedPerDay = finite(post.radiusDecaySeedPerDay);
  meta.decayBoostPerDay = finite(post.radiusDecayBoostPerDay);
  const expired = status === "expired" || (parts.stored ?? parts.total) <= 0;
  if (expired) { meta.live = false; meta.expiredAtMillis ??= millisOf(post.expiredAt) ?? nowMillis; }
  else if (meta.deletedAtMillis == null && status !== "deleted") { meta.live = true; meta.expiredAtMillis = null; }
  if (status === "deleted") { meta.live = false; meta.deletedAtMillis ??= nowMillis; }
  if (fold) (fold.days[day] ??= { gr: 0, go: 0, gv: 0, gs: 0, gu: 0, dl: 0, dlr: 0 }).vc = meta.viewCount;
}

export function registerPost(payload: Payload, row: SweepRow, cls: "real" | "official", ownerClass: OwnerClass, nowMillis: number,
  digestVersion: number, timeZone: string): PostMeta {
  const post = row.data;
  const meta: PostMeta = {
    cls: cls === "real" ? "r" : "o", ownerUid: postOwner(post), ownerClass: ownerShort(ownerClass),
    ch: typeof post.channelId === "string" ? post.channelId.slice(0, 64) : "",
    createdAtMillis: row.createdAt.seconds * 1000 + Math.floor(row.createdAt.nanoseconds / 1_000_000),
    lat: coordinate(post.latitude, 90), lng: coordinate(post.longitude, 180), hasCreate: false, cursor: null,
    live: true, expiredAtMillis: null, deletedAtMillis: null, viewCount: 0, viewCountAtMillis: null,
    lastDecayAt: null, lastOrganic: null, lastSeed: null, lastBoost: null,
    decayAnchorMillis: null, decayOrganicPerDay: null, decaySeedPerDay: null, decayBoostPerDay: null,
    refreshedAtMillis: null, docRadiusMeters: null, createFetch: null, registeredRun: digestVersion,
  };
  payload.postMeta[row.id] = meta;
  payload.folds[row.id] ??= newFold();
  applyPostDocument(meta, payload.folds[row.id], post, nowMillis, dayKey(nowMillis, timeZone));
  return meta;
}

// ── Observed policy (§2.5) ──────────────────────────────────────────────────

export function observedSlice(payload: Payload, days: string[]): ObservedDay {
  const merged: ObservedDay = {};
  for (const day of days) {
    const observedDay = payload.observed[day];
    if (!observedDay) continue;
    for (const [key, slot] of Object.entries(observedDay)) {
      const target = merged[key] ??= { byMeters: {}, min: null, max: null, n: 0 };
      target.n += slot.n;
      for (const [meter, count] of Object.entries(slot.byMeters)) target.byMeters[meter] = (target.byMeters[meter] ?? 0) + count;
      if (slot.min != null) target.min = target.min == null ? slot.min : Math.min(target.min, slot.min);
      if (slot.max != null) target.max = target.max == null ? slot.max : Math.max(target.max, slot.max);
    }
  }
  return merged;
}
export function observedSignature(slice: ObservedDay): ObservedSignature {
  const mode = (key: string) => slice[key] ? modeKey(slice[key].byMeters) : null;
  return { view: mode("view"), like: mode("like"), comment: mode("comment"), dislike: mode("dislike"),
    repeatBase: slice.repeat ? maxKey(slice.repeat.byMeters) : null, seedSeen: mode("seed") };
}
export function observedVersion(signature: ObservedSignature): string { return sha8(signature); }

// ── The run ─────────────────────────────────────────────────────────────────

export interface DigestReader {
  /** uid → email for one Auth page; must throw when the page cannot be read. */
  authPage(): Promise<Record<string, string>>;
  sweepPage(query: { after: SweepCursor | null; fromMillis: number | null; toMillis: number; limit: number }): Promise<SweepRow[]>;
  ledgerPage(query: { postId: string; after: LedgerCursor | null; horizonMillis: number; limit: number }): Promise<LedgerRow[]>;
  createEntry(postId: string): Promise<LedgerRow | null>;
  engagement(postId: string, engagementId: string): Promise<Record<string, unknown> | null>;
  user(uid: string): Promise<Record<string, unknown> | null>;
  post(postId: string): Promise<Record<string, unknown> | null>;
}
export interface RunCost {
  reads: number; writes: number; entriesProcessed: number; postsPolled: number; postsWithEntries: number; engagementJoins: number;
  postLookups: number; createFetches: number; createSkipped: number; sweepReads: number; refreshReads: number; userLookups: number;
  authPages: number; runMs: number; budgetHit: boolean; capInForce: number;
}
export interface StartCursors { sweep: SweepCursor | null; posts: Record<string, LedgerCursor | null> }
export interface FoldInput {
  state: DigestState; config: DigestConfig; switches: Switches; reader: DigestReader; runStartMillis: number; runId: string;
  knobs?: Knobs; stamp?: SyncStamp; timeZone?: string; fixedReads?: number;
}
export interface ReportWrite { day: string; document: Record<string, unknown>; indexRow: Record<string, unknown>; revision: number }
export interface ReportStepResult {
  reports: ReportWrite[]; reportIndex: Record<string, unknown> | null; reportDeferredReason: string | null;
  amendDeferredReason: string | null; amendSkipped: string[]; reportBytes: number;
  /** state.report as it was before this run's report step — what a retry-without-reports commits (§2.7). */
  reportStateBefore: ReportState;
}
export type FoldOutcome =
  | { status: "auth-failed"; cost: RunCost }
  | { status: "ok"; state: DigestState; published: Record<string, unknown>; cost: RunCost; startCursors: StartCursors;
      payloadBytes: number; publishedBytes: number; runCoverage: RunCoverage } & ReportStepResult;
export interface RunCoverage {
  postsBehindHorizon: number; sweptPosts: number; evicted: number; trimmed: boolean; capped: boolean; postsDeleted: number;
  registeredThisRun: number; refreshed: boolean; payloadOverflow: boolean;
}

function emptyCost(capInForce: number): RunCost {
  return { reads: 0, writes: WRITES_PER_RUN, entriesProcessed: 0, postsPolled: 0, postsWithEntries: 0, engagementJoins: 0, postLookups: 0,
    createFetches: 0, createSkipped: 0, sweepReads: 0, refreshReads: 0, userLookups: 0, authPages: 0, runMs: 0, budgetHit: false, capInForce };
}
export function startCursorsOf(state: DigestState): StartCursors {
  const posts: Record<string, LedgerCursor | null> = {};
  for (const [postId, meta] of Object.entries(state.payload.postMeta)) posts[postId] = meta.cursor ? { ...meta.cursor } : null;
  return { sweep: state.sweep.cursor ? { ...state.sweep.cursor } : null, posts };
}
export function cursorsEqual(a: StartCursors, b: StartCursors): boolean {
  if (canonicalJson(a.sweep) !== canonicalJson(b.sweep)) return false;
  for (const [postId, cursor] of Object.entries(a.posts)) if (canonicalJson(cursor) !== canonicalJson(b.posts[postId] ?? null)) return false;
  return true;
}
function touchActor(payload: Payload, uid: string, cls: ActorClass): void {
  delete payload.actorClassByUid[uid];
  payload.actorClassByUid[uid] = ACTOR_SHORT[cls];
  const keys = Object.keys(payload.actorClassByUid);
  for (let i = 0; keys.length - i > ACTOR_CACHE_LIMIT; i++) delete payload.actorClassByUid[keys[i]];
}

/**
 * One run over an in-memory state: Auth page → sweep → per-post ledger pages →
 * daily refresh → derive → render. Nothing here writes; the caller commits the
 * returned state and document together (or nothing).
 */
export async function runDigestFold(input: FoldInput): Promise<FoldOutcome> {
  const knobs = input.knobs ?? KNOBS;
  const stamp = input.stamp ?? SYNC_STAMP;
  const timeZone = input.timeZone ?? TIME_ZONE;
  const config = input.config;
  const runStart = input.runStartMillis;
  const cost = emptyCost(config.maxReadsPerRun);
  const fixedReads = input.fixedReads ?? FIXED_READS_PER_RUN;
  const runCoverage: RunCoverage = { postsBehindHorizon: 0, sweptPosts: 0, evicted: 0, trimmed: false, capped: false, postsDeleted: 0,
    registeredThisRun: 0, refreshed: false, payloadOverflow: false };
  let state = deepClone(input.state);
  // The commit compares against the cursors the stored state carried when
  // this run began — before any reset — so a reset run can still commit.
  const startCursors = startCursorsOf(state);
  if (config.resetRequestedAtMillis != null && config.resetRequestedAtMillis > state.lastResetAtMillis) {
    // The report's memory and the day's read counters survive a reset (decision 5): a re-fold must neither
    // re-backfill nor overwrite written revisions, and a mid-day reset must not under-report readsOnDay.
    state = { ...initialState(), digestVersion: state.digestVersion, authPageFailedRuns: state.authPageFailedRuns,
      observedPolicyVersions: state.observedPolicyVersions, lastResetAtMillis: config.resetRequestedAtMillis,
      report: state.report, readsPrev: state.readsPrev, readsDay: state.readsDay, readsToday: state.readsToday, runsToday: state.runsToday };
  }
  const digestVersion = state.digestVersion + 1;
  state.payload = hydratePayload(state.payload);
  state.report = hydrateReportState(state.report);
  const payload = state.payload;
  // Fold additions 1–3 accrue from here: entries folded before this stamp carry no kind split (§2.3 accrual rule).
  if (payload.coverage.kindSplitSinceMillis == null) payload.coverage.kindSplitSinceMillis = payload.coverage.entriesFolded > 0 ? runStart : 0;
  const createSkippedBefore = payload.coverage.createSkipped;
  const today = dayKey(runStart, timeZone);
  // maxReadsPerRun bounds the whole run: the fixed reads are spent before any page.
  const budget = () => config.maxReadsPerRun - fixedReads - cost.reads;
  const hitBudget = () => { cost.budgetHit = true; runCoverage.capped = true; };

  // 3. Auth page — a failure aborts before any fold (§3.3).
  let emailByUid: Record<string, string>;
  try { emailByUid = await input.reader.authPage(); cost.authPages = 1; }
  catch { return { status: "auth-failed", cost }; }

  const knownActor = (uid: string): boolean => uid in emailByUid;
  const classifyOwner = (uid: string): ActorClass => {
    if (!uid) return "unknown";
    const cached = payload.actorClassByUid[uid];
    if (knownActor(uid)) return actorClass(uid, undefined, emailByUid[uid] ?? null, true);
    if (cached) return ACTOR_LONG[cached];
    return actorClass(uid, undefined, null, false);
  };

  // 4a. New-post sweep — the discovery path (§3.2, §3.4 cold start).
  const coldStart = !state.sweep.coldStartDone;
  const fromMillis = coldStart ? null : state.sweep.cursor ? null : runStart - SWEEP_LOOKBACK_MS;
  const toMillis = runStart - SWEEP_MARGIN_MS;
  for (;;) {
    if (budget() < 1) { hitBudget(); break; }
    const rows = await input.reader.sweepPage({ after: state.sweep.cursor, fromMillis, toMillis, limit: SWEEP_PAGE_SIZE });
    cost.reads += Math.max(1, rows.length); cost.sweepReads += Math.max(1, rows.length);
    for (const row of rows) {
      runCoverage.sweptPosts += 1; payload.coverage.sweptPosts += 1;
      const ownerUid = postOwner(row.data);
      const ownerCls = classifyOwner(ownerUid);
      const ownerSynthetic = ownerCls === "synthetic" || isSyntheticAccount(ownerUid, undefined, emailByUid[ownerUid] ?? null);
      const cls = postClass(row.id, row.data, ownerSynthetic);
      const createdMillis = row.createdAt.seconds * 1000 + Math.floor(row.createdAt.nanoseconds / 1_000_000);
      const cell = ensureDay(payload, dayKey(createdMillis, timeZone));
      const ownerClass: OwnerClass = ownerCls === "owner" ? "owner" : ownerCls === "review" ? "review" : "real";
      cell.postsCreated[cls === "real" ? ownerClass : cls] += 1;
      state.sweep.cursor = { seconds: row.createdAt.seconds, nanoseconds: row.createdAt.nanoseconds, path: row.path };
      if (cls !== "real" && cls !== "official") continue;
      if (payload.postMeta[row.id]) continue;
      if (Object.keys(payload.postMeta).length >= config.registeredPostLimit) { payload.coverage.registryFull = true; continue; }
      registerPost(payload, row, cls, ownerClass, runStart, digestVersion, timeZone);
      runCoverage.registeredThisRun += 1;
    }
    if (rows.length < SWEEP_PAGE_SIZE) break;
  }
  state.sweep.coldStartDone = true;

  // Actor class of an engagement entry: the join, then Auth, then the cache,
  // then one users/{uid} read for a random uid nobody has seen (§1.2).
  const resolveActor = async (postId: string, entry: ParsedEntry): Promise<ResolvedActor> => {
    if (!entry.engagementId) return UNJOINED_ACTOR;
    const engagement = await input.reader.engagement(postId, entry.engagementId);
    cost.reads += 1; cost.engagementJoins += 1;
    if (!engagement) return UNJOINED_ACTOR;
    const uid = typeof engagement.actorUid === "string" ? engagement.actorUid : "";
    const surface = surfaceOf(engagement.surface);
    let cls: ActorClass;
    if (!uid) cls = "unknown";
    else if (knownActor(uid)) cls = actorClass(uid, undefined, emailByUid[uid] ?? null, true);
    else if (payload.actorClassByUid[uid]) { cls = ACTOR_LONG[payload.actorClassByUid[uid]]; touchActor(payload, uid, cls); }
    else {
      const profile = await input.reader.user(uid);
      cost.reads += 1; cost.userLookups += 1;
      cls = actorClass(uid, profile ?? undefined, null, profile != null);
      touchActor(payload, uid, cls);
    }
    if (cls === "real" && !payload.realActorUids.includes(uid) && payload.realActorUids.length < ACTOR_CACHE_LIMIT) payload.realActorUids.push(uid);
    return { cls, surface, joined: true, uid };
  };

  // 4b. Per-post ledger pages, oldest cursor first (§3.2).
  const foldRun: FoldRun = { knobs, timeZone, digestVersion, touchedDays: new Set<string>() };
  const horizon = runStart - config.horizonMs;
  const pollExpired = digestVersion % config.pollExpiredEveryRuns === 0;
  const due = Object.entries(payload.postMeta)
    .filter(([, meta]) => meta.live || pollExpired || meta.registeredRun === digestVersion)
    .sort(([idA, a], [idB, b]) => (a.cursor?.atMillis ?? -1) - (b.cursor?.atMillis ?? -1) || (idA < idB ? -1 : 1));
  for (const [postId, meta] of due) {
    if (cost.budgetHit) { runCoverage.postsBehindHorizon += 1; continue; }
    // The direct create fetch, one read, at the run after a first page without one, then daily.
    const fetch = meta.createFetch;
    if (fetch && !meta.hasCreate && fetch.requestedRun < digestVersion
      && (fetch.lastRun == null || digestVersion - fetch.lastRun >= config.refreshEveryRuns)) {
      if (budget() < 1) { hitBudget(); runCoverage.postsBehindHorizon += 1; continue; }
      const row = await input.reader.createEntry(postId);
      cost.reads += 1; cost.createFetches += 1; fetch.lastRun = digestVersion;
      if (row) {
        foldEntry(payload, postId, parseEntry(row), null, foldRun);
        if (meta.hasCreate) { payload.coverage.createFetched += 1; meta.createFetch = null; }
      } else payload.coverage.createMissing += 1;
    }
    let cursor = meta.cursor;
    let entries = 0;
    let behind = false;
    for (;;) {
      if (budget() < 1) { hitBudget(); behind = true; break; }
      const rows = await input.reader.ledgerPage({ postId, after: cursor, horizonMillis: horizon, limit: LEDGER_PAGE_SIZE });
      cost.reads += Math.max(1, rows.length);
      let stopped = false;
      for (const row of rows) {
        const entry = parseEntry(row);
        const route = entryRoute(entry);
        // The budget is checked before an entry's joins: the cursor never
        // passes an entry that was not fully processed.
        if (route === "engagement" && entry.engagementId && budget() < 2) { hitBudget(); stopped = true; break; }
        const actor = route === "engagement" ? await resolveActor(postId, entry) : null;
        foldEntry(payload, postId, entry, actor, foldRun);
        cursor = { atMillis: entry.atMillis, id: row.id };
        entries += 1; cost.entriesProcessed += 1;
      }
      meta.cursor = cursor;
      if (stopped) { behind = true; break; }
      if (rows.length < LEDGER_PAGE_SIZE) break;
    }
    cost.postsPolled += 1;
    if (entries > 0) cost.postsWithEntries += 1;
    if (behind) runCoverage.postsBehindHorizon += 1;
  }
  cost.createSkipped = payload.coverage.createSkipped - createSkippedBefore;

  // 5. Daily post refresh: viewCount samples, parts, projection fields, deletions.
  if (state.refresh.lastRefreshDay !== today && !cost.budgetHit) {
    let complete = true;
    for (const postId of Object.keys(payload.postMeta).sort()) {
      const meta = payload.postMeta[postId];
      if (meta.refreshedAtMillis != null && dayKey(meta.refreshedAtMillis, timeZone) === today) continue;
      if (budget() < 1) { hitBudget(); complete = false; break; }
      const post = await input.reader.post(postId);
      cost.reads += 1; cost.refreshReads += 1; cost.postLookups += 1;
      if (!post) {
        if (meta.deletedAtMillis == null) { meta.deletedAtMillis = runStart; payload.coverage.postsDeleted += 1; runCoverage.postsDeleted += 1; }
        meta.live = false; meta.refreshedAtMillis = runStart;
        continue;
      }
      applyPostDocument(meta, payload.folds[postId], post, runStart, today);
    }
    if (complete) { state.refresh.lastRefreshDay = today; runCoverage.refreshed = true; }
  }

  // 7. Observed policy version, day stamps (§2.5).
  const observedDays = dayKeysEndingAt(runStart, OBSERVED_WINDOW_DAYS, timeZone);
  const signature = observedSignature(observedSlice(payload, observedDays));
  const version = observedVersion(signature);
  const versions = state.observedPolicyVersions;
  if (versions.length === 0 || versions[versions.length - 1].version !== version) {
    versions.push({ version, fromMillis: runStart, signature });
    while (versions.length > OBSERVED_VERSIONS_LIMIT) versions.shift();
  }
  for (const day of foldRun.touchedDays) {
    const cell = payload.days[day];
    if (cell && cell.entries.real + cell.entries.official >= GATES.minEvents) cell.observedPolicy = version;
  }

  // Cost and the day's running total.
  cost.reads += fixedReads;
  if (state.readsDay !== today) {
    state.readsPrev = { day: state.readsDay, reads: state.readsToday, runs: state.runsToday };
    state.readsDay = today; state.readsToday = 0; state.runsToday = 0;
  }
  state.readsToday += cost.reads; state.runsToday += 1;
  state.digestVersion = digestVersion;
  state.runId = input.runId;
  state.leaseUntilMillis = 0;

  // 8. Render, then keep the state under its own guard (§2.2).
  const trim = trimPayload(payload, runStart, timeZone);
  runCoverage.evicted += trim.evicted; runCoverage.trimmed = trim.trimmed; runCoverage.payloadOverflow = trim.overflow;
  const published = renderDigest({ state, config, switches: input.switches, runStartMillis: runStart, runId: input.runId, cost,
    runCoverage, knobs, stamp, timeZone });
  // 8b. The daily report — a pure render of `published` + `state.payload`, never a re-scan (decision 1).
  const report = runReportStep({ state, published, config, switches: input.switches, runStartMillis: runStart, runId: input.runId, cost,
    runCoverage, knobs, stamp, timeZone });
  cost.writes = WRITES_PER_RUN + report.reports.length + (report.reportIndex ? 1 : 0);
  (published.cost as Record<string, unknown>).writes = cost.writes;
  return { status: "ok", state, published, cost, startCursors, payloadBytes: trim.bytes, publishedBytes: JSON.stringify(published).length, runCoverage, ...report };
}

// ── Size guards ─────────────────────────────────────────────────────────────

/** Eviction order when the stored payload would exceed 700 KB: fold day cells
 *  older than 400 days → actor cache LRU → stale finished folds. Never day
 *  cells. Sizes are of the compact form, which is what gets stored. */
export function trimPayload(payload: Payload, nowMillis: number, timeZone = TIME_ZONE,
  limits: { trim: number; hard: number } = { trim: PAYLOAD_TRIM_BYTES, hard: PAYLOAD_HARD_BYTES }): { bytes: number; evicted: number; trimmed: boolean; overflow: boolean } {
  // Per-day real-actor entries (fold addition 3) are bounded by retention, not by size: cells older than 45 days
  // keep every count and lose only the uid map. Runs every time, whatever the payload weighs.
  const actorCutoff = dayKey(nowMillis - REAL_ACTOR_ENTRIES_DAYS * DAY_MS, timeZone);
  for (const [day, cell] of Object.entries(payload.days)) if (day < actorCutoff && Object.keys(cell.realActorEntries).length) cell.realActorEntries = {};
  let bytes = compactPayloadBytes(payload);
  let evicted = 0;
  let trimmed = false;
  if (bytes <= limits.trim) return { bytes, evicted, trimmed, overflow: false };
  trimmed = true;
  const cutoffDay = dayKey(nowMillis - FOLD_DAY_RETENTION_DAYS * DAY_MS, timeZone);
  for (const fold of Object.values(payload.folds)) for (const day of Object.keys(fold.days)) if (day < cutoffDay) delete fold.days[day];
  bytes = compactPayloadBytes(payload);
  if (bytes > limits.trim) {
    const keys = Object.keys(payload.actorClassByUid);
    for (const key of keys.slice(0, Math.ceil(keys.length / 2))) delete payload.actorClassByUid[key];
    bytes = compactPayloadBytes(payload);
  }
  const evictFinished = (staleBefore: number) => {
    for (const [postId, meta] of Object.entries(payload.postMeta)) {
      const fold = payload.folds[postId];
      const lastAt = fold?.lastAt ?? meta.createdAtMillis;
      // Expired posts cannot be engaged again; deleted ones have no document.
      const finished = (fold?.lastRadius ?? 1) <= 0 || meta.deletedAtMillis != null;
      if (finished && lastAt < staleBefore) { delete payload.postMeta[postId]; delete payload.folds[postId]; evicted += 1; }
    }
  };
  if (bytes > limits.trim) { evictFinished(nowMillis - STALE_FOLD_DAYS * DAY_MS); bytes = compactPayloadBytes(payload); }
  if (bytes > limits.hard) { evictFinished(Number.POSITIVE_INFINITY); bytes = compactPayloadBytes(payload); }
  payload.coverage.evicted += evicted;
  return { bytes, evicted, trimmed, overflow: bytes > limits.hard };
}

// ── Derive and render (§1.4, §2.1) ──────────────────────────────────────────

export interface Gate { n: number; minN: number; sufficient: boolean; basis: string }
interface NetBucket { posts: number; netPositive: number; postDays: number; gainRealMeters: number; lossRealShareMeters: number; perPostDay: number | null }
const emptyBucket = (): NetBucket => ({ posts: 0, netPositive: 0, postDays: 0, gainRealMeters: 0, lossRealShareMeters: 0, perPostDay: null });

export interface RenderInput {
  state: DigestState; config: DigestConfig; switches: Switches; runStartMillis: number; runId: string; cost: RunCost;
  runCoverage: RunCoverage; knobs: Knobs; stamp: SyncStamp; timeZone: string;
}

export function postEndMillis(meta: PostMeta, nowMillis: number): number {
  return Math.min(nowMillis, meta.expiredAtMillis ?? Number.POSITIVE_INFINITY, meta.deletedAtMillis ?? Number.POSITIVE_INFINITY);
}
export function isLive(meta: PostMeta, fold: PostFold | undefined): boolean {
  return meta.live && meta.deletedAtMillis == null && (fold?.lastRadius ?? meta.docRadiusMeters ?? 0) > 0;
}
function dominantMode(fold: PostFold): DecayMode | "none" {
  const counts = fold.modeCounts;
  const decided = (["normal", "trial", "stress"] as const).filter((mode) => counts[mode] > 0).sort((a, b) => counts[b] - counts[a]);
  if (decided.length > 0) return decided[0];
  return counts.undetermined > 0 ? "undetermined" : "none";
}
function decayPathSeen(fold: PostFold): "organic" | "boost" | "seed" | "none" {
  const paths = fold.decayPaths;
  const best = (["organic", "boost", "seed"] as const).filter((path) => paths[path] > 0).sort((a, b) => paths[b] - paths[a]);
  return best[0] ?? "none";
}
/** Distinct-uid counts of a day's real-actor entries — what publishedDay prints in place of the uid map. */
export function dayPeople(entries: Record<string, KindCounts>, events: number): { actors: number; viewers: number; likers: number; commenters: number; maxShare: number | null } {
  let actors = 0, viewers = 0, likers = 0, commenters = 0, largest = 0;
  for (const counts of Object.values(entries)) {
    actors += 1;
    if (counts.v > 0) viewers += 1;
    if (counts.l > 0) likers += 1;
    if (counts.c > 0) commenters += 1;
    largest = Math.max(largest, counts.v + counts.l + counts.c + counts.d);
  }
  return { actors, viewers, likers, commenters, maxShare: events > 0 && actors > 0 ? round(largest / events, 4) : null };
}
/** The uid map never rides the spread (refuter 1): it is destructured OUT before `...rest`. */
export function publishedDay(cell: DayCell, inherited: string | null = null): Record<string, unknown> {
  const { trialMultipliers, ...loss } = cell.realPostDecayLoss;
  const { realActorEntries, ...rest } = cell;
  const seen = modeKey(trialMultipliers);
  return { ...rest, observedPolicy: cell.observedPolicy ?? inherited,
    realPostDecayLoss: { ...loss, trialMultiplierSeen: seen, inferred: true },
    people: dayPeople(realActorEntries, cell.realPostGain.real.n) };
}

/** The same window ending at an explicit instant: `windowStats` derives `now` from runStartMillis at every
 *  site (window end, post end, the clip, ageDays), so overriding it moves all four together and a live post
 *  cannot leak past the report's day (§2.1). */
export function windowStatsAt(input: Pick<RenderInput, "state" | "timeZone">, days: string[], endMillis: number): Record<string, unknown> {
  return windowStats({ ...input, runStartMillis: endMillis }, days);
}
export function windowStats(input: Pick<RenderInput, "state" | "runStartMillis" | "timeZone">, days: string[]): Record<string, unknown> {
  const { state, runStartMillis: now, timeZone } = input;
  const payload = state.payload;
  const sum = emptyDayCell("window") as unknown as Record<string, unknown>;
  delete sum.day; delete sum.observedPolicy;
  const spanned = new Set<string>();
  let inherited: string | null = null;
  for (const day of Object.keys(payload.days).sort()) {
    const cell = payload.days[day];
    if (cell.observedPolicy) inherited = cell.observedPolicy;
    if (days.includes(day)) {
      const { day: _day, observedPolicy, realActorEntries: _entries, ...numbers } = cell;
      addInto(sum, numbers as unknown as Record<string, unknown>);
      const version = observedPolicy ?? inherited;
      if (version) spanned.add(version);
    }
  }
  const loss = sum.realPostDecayLoss as { byMode: ModeMeters; byClass: ClassMeters; trialMultipliers: Record<string, number> };
  const windowStart = dayStartMillis(days[0], timeZone);
  const windowEnd = now;
  const daySet = new Set(days);

  const net = { real: { byAge: { lt7d: emptyBucket(), d7to30: emptyBucket(), gt30d: emptyBucket() }, all: emptyBucket() },
    owner: { byAge: { lt7d: emptyBucket(), d7to30: emptyBucket(), gt30d: emptyBucket() }, all: emptyBucket() } };
  let views: number | null = null;
  let cleanPosts = 0;
  const sampleDays = new Set<string>();
  for (const [postId, meta] of Object.entries(payload.postMeta)) {
    if (meta.cls !== "r") continue;
    const fold = payload.folds[postId];
    if (!fold) continue;
    const end = postEndMillis(meta, now);
    if (meta.createdAtMillis > windowEnd || end < windowStart) continue;
    let gain = 0; let lossReal = 0;
    for (const [day, cellDay] of Object.entries(fold.days)) if (daySet.has(day)) { gain += cellDay.gr; lossReal += cellDay.dlr; }
    const postDays = Math.max(0, Math.min(end, windowEnd) - Math.max(meta.createdAtMillis, windowStart)) / DAY_MS;
    const ageDays = (windowEnd - meta.createdAtMillis) / DAY_MS;
    const target = meta.ownerClass === "r" ? net.real : net.owner;
    const bucket = ageDays < 7 ? target.byAge.lt7d : ageDays <= 30 ? target.byAge.d7to30 : target.byAge.gt30d;
    for (const slot of [bucket, target.all]) {
      slot.posts += 1; slot.postDays += postDays; slot.gainRealMeters += gain; slot.lossRealShareMeters += lossReal;
      if (gain - lossReal > 0) slot.netPositive += 1;
    }
    if (meta.ownerClass === "r" && !fold.everPumped) {
      cleanPosts += 1;
      const sampled = Object.keys(fold.days).filter((day) => fold.days[day].vc != null).sort();
      const inWindow = sampled.filter((day) => day >= days[0] && day <= days[days.length - 1]);
      const before = sampled.filter((day) => day < days[0]);
      for (const day of inWindow) sampleDays.add(day);
      if (inWindow.length && before.length) {
        views = (views ?? 0) + Math.max(0, (fold.days[inWindow[inWindow.length - 1]].vc ?? 0) - (fold.days[before[before.length - 1]].vc ?? 0));
      }
    }
  }
  const finish = (block: { byAge: Record<string, NetBucket>; all: NetBucket }) => {
    for (const bucket of [...Object.values(block.byAge), block.all]) {
      bucket.postDays = round(bucket.postDays, 2);
      bucket.gainRealMeters = round(bucket.gainRealMeters); bucket.lossRealShareMeters = round(bucket.lossRealShareMeters);
      bucket.perPostDay = bucket.postDays > 0 ? round((bucket.gainRealMeters - bucket.lossRealShareMeters) / bucket.postDays) : null;
    }
    return block;
  };
  const gain = sum.realPostGain as Record<string, ActorGain>;
  return {
    days: days.length, observedPolicySpanned: [...spanned].sort(),
    postsCreated: sum.postsCreated, entries: sum.entries, realPostGain: sum.realPostGain,
    realPostDecayLoss: { byMode: roundRecord(loss.byMode), trialMultiplierSeen: modeKey(loss.trialMultipliers), byClass: roundRecord(loss.byClass), inferred: true },
    realPostSeedLoss: sum.realPostSeedLoss, realPostBoostLoss: sum.realPostBoostLoss,
    netReal: finish(net.real), netOwner: finish(net.owner),
    viewWorth: { metersPaid: gain.real.view, paidViews: gain.real.firstViews + gain.real.repeatViews, views, cleanPosts, viewSampleDays: sampleDays.size },
    boosts: sum.boosts, unknownActorEntries: sum.unknownActorEntries,
    distinctRealViewers: sum.distinctRealViewers, distinctRealLikers: sum.distinctRealLikers, distinctRealCommenters: sum.distinctRealCommenters,
    surfaces: sum.surfaces, realSurfaces: sum.realSurfaces,
  };
}
function roundRecord<T extends object>(record: T): T {
  const out: Record<string, number> = {};
  for (const [key, value] of Object.entries(record)) out[key] = round(value as number);
  return out as T;
}

/** Stepped through the synced calculateRadiusDecay once per pass (M7). */
export function decayCurve(startOrganic: number, options: { passMinutes?: number; seedMeters?: number; boostMeters?: number;
  trial?: { multiplier: number } | null; knobs?: Knobs } = {}): { passes: number; days: number; seedPasses: number | null; seedDays: number | null; boostDays: number | null } {
  const knobs = options.knobs ?? KNOBS;
  const passMs = (options.passMinutes ?? PASS_MINUTES) * 60_000;
  const t0 = 1_700_000_000_000;
  const trial = options.trial ? { multiplier: options.trial.multiplier, effectiveAtMillis: t0, boostedEffectiveAtMillis: t0 } : undefined;
  const post: Record<string, unknown> = { organicRadiusMeters: startOrganic, seedRadiusMeters: options.seedMeters ?? 0,
    boostedRadiusMeters: options.boostMeters ?? 0, radiusMeters: startOrganic + (options.seedMeters ?? 0) + (options.boostMeters ?? 0), decayedAt: t0 };
  let passes = 0; let organicZeroAt: number | null = startOrganic > 0 ? null : 0;
  let seedZeroAt: number | null = null;
  let boostZeroAt: number | null = null;
  for (let pass = 1; pass <= 200_000; pass++) {
    const now = (post.decayedAt as number) + passMs;
    const next = policy.calculateRadiusDecay(post, now, knobs.decayPerDay, trial);
    if (!next) break;
    passes = pass;
    post.organicRadiusMeters = next.organicRadiusMeters;
    if (next.seedRadiusMeters != null) post.seedRadiusMeters = next.seedRadiusMeters;
    if (next.boostedRadiusMeters != null) post.boostedRadiusMeters = next.boostedRadiusMeters;
    post.radiusMeters = next.radiusMeters; post.decayedAt = now;
    if (organicZeroAt == null && next.organicRadiusMeters <= 0) organicZeroAt = pass;
    if (seedZeroAt == null && (options.seedMeters ?? 0) > 0 && (next.seedRadiusMeters ?? 1) <= 0) seedZeroAt = pass;
    if (boostZeroAt == null && (options.boostMeters ?? 0) > 0 && (next.boostedRadiusMeters ?? 1) <= 0) boostZeroAt = pass;
  }
  const days = (n: number | null) => n == null ? null : round(n * passMs / DAY_MS, 1);
  return { passes: organicZeroAt ?? passes, days: days(organicZeroAt ?? passes) ?? 0, seedPasses: seedZeroAt, seedDays: days(seedZeroAt), boostDays: days(boostZeroAt) };
}
export function curveBlock(passMinutes: number, knobs: Knobs, medianTesterPeak: number | null, trial: { multiplier: number } | null): Record<string, unknown> {
  const multiplier = trial?.multiplier ?? 1;
  const at = (organic: number) => decayCurve(organic, { passMinutes, trial, knobs }).days;
  // Below this organic a pass at this multiplier loses exactly 1 m: the linear tail.
  const linearFloorMeters = Math.floor(1 / (1 - Math.pow(1 - knobs.decayPerDay, multiplier / 24)));
  const block: Record<string, unknown> = {
    passMinutes, multiplier,
    daysToFloor: { "1000": at(1_000), "10000": at(10_000), "100000": at(100_000), medianTesterPeak: medianTesterPeak != null && medianTesterPeak > 0 ? at(medianTesterPeak) : null },
    daysToFloorAt468m: at(RATE_INFORMATIVE_MIN_ORGANIC),
    linearFloorMeters, linearTailDays: at(linearFloorMeters),
    halfLifeDays: round(Math.log(0.5) / Math.log(1 - knobs.decayPerDay) / multiplier, 2),
    halfLifeNote: "far above the floor only",
  };
  if (trial) {
    const seed = decayCurve(0, { passMinutes, seedMeters: knobs.seedMeters, trial, knobs });
    block.claimMeters = knobs.seedMeters; block.seedDaysToFloor = seed.seedDays;
  }
  return block;
}

export function renderDigest(input: RenderInput): Record<string, unknown> {
  const { state, config, switches, runStartMillis: now, cost, runCoverage, knobs, stamp, timeZone } = input;
  const payload = state.payload;
  const trialOn = switches.decayTrial?.enabled === true;
  const metas = Object.entries(payload.postMeta);
  const foldOf = (postId: string) => payload.folds[postId];

  // Anchors (M13) and the headline.
  const anchorRows: Record<string, unknown>[] = [];
  let everAtWorld = 0; let atWorld = 0;
  for (const [postId, meta] of metas) {
    const fold = foldOf(postId);
    if (meta.cls !== "o" || !fold || fold.peak < knobs.maxRadiusMeters) continue;
    everAtWorld += 1;
    const isAtWorld = fold.lastRadius >= knobs.maxRadiusMeters;
    if (isAtWorld) atWorld += 1;
    anchorRows.push({ postId, radiusMeters: fold.lastRadius, atWorld: isAtWorld, belowSinceMillis: isAtWorld ? null : firstBelowWorld(fold, knobs),
      lastAtMillis: fold.lastAt, decayPathSeen: decayPathSeen(fold), ratePerPassSeen: fold.lastDecayRate == null ? null : round(fold.lastDecayRate, 5) });
  }
  anchorRows.sort((a, b) => (a.radiusMeters as number) - (b.radiusMeters as number) || String(a.postId).localeCompare(String(b.postId)));
  const worst = anchorRows[0];
  const headline = {
    trialOn, trialSinceMillis: switches.decayTrial?.effectiveAtMillis ?? null, trialMultiplier: switches.decayTrial?.multiplier ?? null,
    boostedSinceMillis: switches.decayTrial?.boostedEffectiveAtMillis ?? null, anchorsAtWorld: atWorld, anchorsEver: everAtWorld,
    worstAnchor: worst ? { postId: worst.postId, radiusMeters: worst.radiusMeters, ratePerPassSeen: worst.ratePerPassSeen } : null,
  };

  // Windows.
  const d7Days = dayKeysEndingAt(now, 7, timeZone);
  const d30Days = dayKeysEndingAt(now, 30, timeZone);
  const d7 = windowStats(input, d7Days);
  const d30 = windowStats(input, d30Days);

  // Post-side populations (§1.2): tester-owned versus owner/review-owned.
  const tester = metas.filter(([, meta]) => meta.cls === "r" && meta.ownerClass === "r");
  const ownerSide = metas.filter(([, meta]) => meta.cls === "r" && meta.ownerClass !== "r");
  const seedRestOver = (rows: [string, PostMeta][], distributions: boolean) => {
    const live = rows.filter(([postId, meta]) => isLive(meta, foldOf(postId)));
    let atClaim = 0; let everAbove = 0; let clean = 0;
    const shares: number[] = []; const peakOver: number[] = []; const toPeak: number[] = [];
    for (const [postId] of live) {
      const fold = foldOf(postId)!;
      if (fold.organic === 0 && fold.seed > 0 && fold.seed === fold.birthSeed) atClaim += 1;
      if (fold.peakOrganic > 0) everAbove += 1;
      if (fold.everPumped) continue;
      clean += 1;
      if (fold.lastRadius > 0) shares.push(round(fold.seed / fold.lastRadius, 4));
      if (fold.birthSeed > 0) peakOver.push(round(fold.peak / fold.birthSeed, 3));
      if (fold.peakOrganic > 0 && fold.peakAtMillis != null && fold.firstAt != null) toPeak.push(round((fold.peakAtMillis - fold.firstAt) / HOUR_MS, 2));
    }
    const enough = clean >= GATES.minPosts;
    const dist = (values: number[]) => ({ n: values.length, p50: distributions && enough ? percentile(values, 0.5) : null, p90: distributions && enough ? percentile(values, 0.9) : null });
    return { livePosts: live.length, atClaim, everAboveClaim: everAbove, cleanPosts: clean,
      claimShareMedian: distributions && enough ? median(shares) : null, peakOverClaim: dist(peakOver), timeToPeakHours: dist(toPeak) };
  };
  const seedRest = { valid: !trialOn, ...seedRestOver(tester, true), owner: seedRestOver(ownerSide, false) };

  const claimsOver = (rows: [string, PostMeta][]) => {
    const births = rows.map(([postId]) => foldOf(postId)).filter((fold): fold is PostFold => !!fold && fold.firstAt != null && fold.firstAt >= now - 30 * DAY_MS);
    const withCreate = rows.filter(([postId, meta]) => meta.hasCreate && (foldOf(postId)?.firstAt ?? 0) >= now - 30 * DAY_MS).map(([postId]) => foldOf(postId)!);
    const seeds = withCreate.map((fold) => fold.birthSeed);
    return { count: withCreate.length, atFloor: seeds.filter((seed) => seed === knobs.seedMeters).length,
      medianMeters: median(seeds), maxMeters: seeds.length ? Math.max(...seeds) : 0,
      aboveFloorThatEarned: withCreate.filter((fold) => fold.birthSeed > knobs.seedMeters && fold.peakOrganic > 0).length,
      dropsSeen: births.length };
  };
  const claims = { d30: { ...claimsOver(tester), owner: claimsOver(ownerSide) } };

  // Contamination (M9) over the 7-day window.
  const d7Set = new Set(d7Days);
  const contaminationPosts = metas.filter(([, meta]) => meta.cls === "r").map(([postId]) => {
    const fold = foldOf(postId)!;
    let syn = 0; let owner = 0;
    for (const [day, cell] of Object.entries(fold.days)) if (d7Set.has(day)) { syn += cell.gs; owner += cell.go; }
    const total = sumPool(fold.pool);
    return { postId, syntheticMeters: syn, ownerMeters: owner, share: total > 0 ? round(fold.pool.syn / total, 4) : 0 };
  }).filter((row) => row.syntheticMeters !== 0 || row.ownerMeters !== 0)
    .sort((a, b) => b.syntheticMeters - a.syntheticMeters || a.postId.localeCompare(b.postId)).slice(0, CONTAMINATION_ROWS);
  const d7Gain = d7.realPostGain as Record<string, ActorGain>;
  const contamination = { d7: { syntheticMeters: d7Gain.synthetic.total, syntheticEntries: d7Gain.synthetic.n, ownerMeters: d7Gain.owner.total,
    ownerEntries: d7Gain.owner.n, reviewMeters: d7Gain.review.total, reviewEntries: d7Gain.review.n, simulationOwnerUid: switches.simulationOwnerUid, posts: contaminationPosts } };

  // Interception (M3/M4): realized from the ledger, opportunity from coarse cells.
  const realPosts = metas.filter(([, meta]) => meta.cls === "r");
  const d30Gain = d30.realPostGain as Record<string, ActorGain>;
  const realized = { entries: d30Gain.real.n, distinctPosts: realPosts.filter(([postId]) => (foldOf(postId)?.lastRealAt ?? 0) >= now - 30 * DAY_MS).length,
    distinctActors: payload.realActorUids.length };
  const accountLocation = new Map<string, { lat: number; lng: number; at: number }>();
  for (const [, meta] of tester) {
    if (meta.lat == null || meta.lng == null) continue;
    const current = accountLocation.get(meta.ownerUid);
    if (!current || meta.createdAtMillis > current.at) accountLocation.set(meta.ownerUid, { lat: meta.lat, lng: meta.lng, at: meta.createdAtMillis });
  }
  let pairs = 0; let nearMissPairs = 0; const postsWithPair = new Set<string>();
  for (const [postId, meta] of realPosts) {
    const fold = foldOf(postId);
    if (!isLive(meta, fold) || meta.lat == null || meta.lng == null || !fold) continue;
    for (const [uid, location] of accountLocation) {
      if (uid === meta.ownerUid) continue;
      const distance = haversineMeters(location.lat, location.lng, meta.lat, meta.lng);
      if (distance <= fold.lastRadius) { pairs += 1; postsWithPair.add(postId); }
      // Within twice the reach of a clean post (a pumped post's lastRadius includes synthetic organic) — the seedReach finding only.
      else if (!fold.everPumped && distance <= 2 * fold.lastRadius) nearMissPairs += 1;
    }
  }
  const intercept = { realized, opportunity: { pairs, nearMissPairs, postsWithAnyPair: postsWithPair.size, realAccountsWithLocation: accountLocation.size } };

  // Channels (M10) over tester posts.
  const byChannel = new Map<string, [string, PostMeta][]>();
  for (const row of tester) { const key = row[1].ch || "other"; (byChannel.get(key) ?? byChannel.set(key, []).get(key)!).push(row); }
  const channelRow = (channelId: string, rows: [string, PostMeta][]) => {
    let gain = 0; let postDays = 0; let n = 0; const firsts: number[] = [];
    for (const [postId, meta] of rows) {
      const fold = foldOf(postId);
      if (!fold) continue;
      gain += fold.gainReal; postDays += Math.max(0, postEndMillis(meta, now) - meta.createdAtMillis) / DAY_MS;
      for (const cell of Object.values(fold.days)) n += cell.gr !== 0 ? 1 : 0;
      if (fold.firstRealAt != null && fold.firstAt != null) firsts.push((fold.firstRealAt - fold.firstAt) / 60_000);
    }
    const realEntries = rows.reduce((total, [postId]) => total + countRealEntries(foldOf(postId)), 0);
    const sufficient = rows.length >= GATES.minChannelPosts && realEntries >= GATES.minEvents;
    return { channelId, realPosts: rows.length, realGainMeters: round(gain), postDays: round(postDays, 2),
      gainPerPostDay: sufficient && postDays > 0 ? round(gain / postDays) : null,
      medianMinutesToFirstRealEngagement: sufficient ? median(firsts) : null, n: realEntries, sufficient };
  };
  // ≤ channelLimit named rows by tester-post count; everything past the cut
  // (and posts with no channel) folds into "other".
  const ranked = [...byChannel.entries()].filter(([id]) => id !== "other").sort((a, b) => b[1].length - a[1].length || a[0].localeCompare(b[0]));
  const channels = ranked.slice(0, config.channelLimit).map(([id, rows]) => channelRow(id, rows));
  const otherRows = [...ranked.slice(config.channelLimit).flatMap(([, rows]) => rows), ...(byChannel.get("other") ?? [])];
  if (otherRows.length) channels.push(channelRow("other", otherRows));

  // Post rows (panel K).
  const posts = metas.map(([postId, meta]) => {
    const fold = foldOf(postId) ?? newFold();
    return {
      postId, cls: meta.cls === "r" ? "real" : "official", ownerClass: meta.cls === "o" ? "official" : OWNER_LONG[meta.ownerClass],
      channelId: meta.ch, createdAtMillis: meta.createdAtMillis, seedMeters: fold.birthSeed, currentMeters: fold.lastRadius,
      organicMeters: fold.organic, boostMeters: fold.boost, peakMeters: fold.peak, peakAtMillis: fold.peakAtMillis, entries: fold.n,
      realGain: fold.gainReal, ownerGain: fold.gainOwner, reviewGain: fold.gainReview, syntheticGain: fold.gainSyn, unknownGain: fold.gainUnknown,
      decayLoss: round(sumModes(fold.lossDecay.byMode)), decayLossRealShare: round(fold.lossDecay.byClass.real), decayModeSeen: dominantMode(fold),
      clean: !fold.everPumped, viewCount: meta.viewCount, firstRealEngagementAtMillis: fold.firstRealAt, lastAtMillis: fold.lastAt,
      lastCause: fold.lastCause, atClaim: fold.organic === 0 && fold.seed > 0 && fold.seed === fold.birthSeed,
      expired: fold.lastRadius <= 0 && fold.n > 0, deletedAtMillis: meta.deletedAtMillis,
    };
  }).sort((a, b) => (b.lastAtMillis ?? 0) - (a.lastAtMillis ?? 0) || a.postId.localeCompare(b.postId));

  // Curve (M7).
  const testerPeaks = tester.map(([postId]) => foldOf(postId)?.peakOrganic ?? 0).filter((peak) => peak > 0);
  const medianPeak = median(testerPeaks);
  const trial = liveTrial(switches);
  const curve = {
    passMinutes: PASS_MINUTES, normal: curveBlock(PASS_MINUTES, knobs, medianPeak, null), normal65: curveBlock(PASS_MINUTES_SLOW, knobs, medianPeak, null),
    trial: trial ? curveBlock(PASS_MINUTES, knobs, medianPeak, { multiplier: trial.multiplier }) : null,
    stress: { halfLifeHours: knobs.syntheticStressHalfLifeHours, suppressedWhileTrial: trialOn },
  };

  // Observed grants (M16), 7 days.
  const slice = observedSlice(payload, d7Days);
  const grant = (key: string) => { const slot = slice[key]; return slot ? { n: slot.n, modeMeters: modeKey(slot.byMeters), min: slot.min, max: slot.max, byMeters: slot.byMeters } : { n: 0, modeMeters: null, min: null, max: null, byMeters: {} }; };
  const observed = { grants: { view: grant("view"), repeat: grant("repeat"), like: grant("like"), dislike: grant("dislike"), comment: grant("comment") },
    seedSeen: grant("seed"), boostSeen: { meters: grant("boost"), hours: grant("boostHours") },
    sampleEntries: ["view", "repeat", "like", "dislike", "comment"].reduce((total, key) => total + (slice[key]?.n ?? 0), 0),
    clamped: slice.clamped?.n ?? 0, resync: slice.resync?.n ?? 0 };
  const latestObserved = state.observedPolicyVersions[state.observedPolicyVersions.length - 1];

  // Gates.
  const withRealEngagement = tester.filter(([postId]) => foldOf(postId)?.firstRealAt != null).length;
  const liveTester = tester.filter(([postId, meta]) => isLive(meta, foldOf(postId))).length;
  const gate = (n: number, minN: number, sufficient: boolean, basis: string): Gate => ({ n, minN, sufficient, basis });
  const questions = {
    c: gate(d7Gain.real.n, GATES.minEvents, d7Gain.real.n >= GATES.minEvents && payload.realActorUids.length >= GATES.minActors, "real posts × real actors · engagement entries · organicDelta · 7 d"),
    d: gate(withRealEngagement, GATES.minPosts, withRealEngagement >= GATES.minPosts, "tester posts with ≥ 1 real engagement · gainReal − real share of decay"),
    f: gate(liveTester, GATES.minPosts, liveTester >= GATES.minPosts && !trialOn, "live tester posts · seed vs organic · hidden while the trial runs"),
    g: gate(d7Gain.synthetic.n + d7Gain.owner.n, 0, true, "synthetic and owner actors on real posts · 7 d"),
    h: gate(tester.length, GATES.minChannelPosts, channels.some((row) => row.sufficient), "tester posts by channelId · real actors only"),
    i: gate(claims.d30.count, 0, true, "create entries on tester posts · 30 d · counts and medians only"),
    k: gate(posts.length, 0, true, "registered real, owner, review and official posts"),
  };
  const modeTotals = Object.values(payload.folds).reduce((acc, fold) => { acc.decided += fold.modeCounts.normal + fold.modeCounts.trial + fold.modeCounts.stress; acc.undetermined += fold.modeCounts.undetermined; return acc; }, { decided: 0, undetermined: 0 });
  const surfaceEntries = Object.values(payload.days).reduce((total, cell) => total + cell.surfaces.feed + cell.surfaces.map + cell.surfaces.profile, 0);
  const gaps = [
    { id: "decayMode", measured: true, inferredEntries: modeTotals.decided, undeterminedEntries: modeTotals.undetermined },
    { id: "ceilingMeters", measured: false },
    { id: "surface", measured: surfaceEntries > 0, labelledEntries: surfaceEntries },
  ];

  // Coverage (M18) and cost (M17).
  const registered = { real: 0, owner: 0, review: 0, official: 0 };
  for (const [, meta] of metas) registered[meta.cls === "o" ? "official" : OWNER_LONG[meta.ownerClass]] += 1;
  const unknownActor = Object.values(payload.days).reduce((acc, cell) => { acc.real += cell.unknownActorEntries.real; acc.official += cell.unknownActorEntries.official; return acc; }, { real: 0, official: 0 });
  const coverage = {
    entriesFolded: payload.coverage.entriesFolded, complete: runCoverage.postsBehindHorizon === 0 && !cost.budgetHit && runCoverage.evicted === 0,
    capped: runCoverage.capped, registeredPosts: registered,
    sweep: { cursorCreatedAtMillis: state.sweep.cursor ? state.sweep.cursor.seconds * 1000 + Math.floor(state.sweep.cursor.nanoseconds / 1_000_000) : null, sweptPosts: runCoverage.sweptPosts },
    horizonMillis: now - config.horizonMs, postsBehindHorizon: runCoverage.postsBehindHorizon,
    createFetched: payload.coverage.createFetched, createMissing: payload.coverage.createMissing, createSkipped: payload.coverage.createSkipped,
    unknownCauses: payload.coverage.unknownCauses, unknownActorEntries: unknownActor, resync: payload.coverage.resync,
    undeterminedMode: payload.coverage.undeterminedMode, postsGone: metas.filter(([, meta]) => meta.deletedAtMillis != null).length,
    postsDeleted: runCoverage.postsDeleted, evicted: payload.coverage.evicted, trimmed: runCoverage.trimmed,
    authPageFailedRuns: state.authPageFailedRuns, timeZone, registryFull: payload.coverage.registryFull, payloadOverflow: runCoverage.payloadOverflow,
  };
  const monthlyReads = cost.reads * 24 * 30;
  const costBlock = { ...cost, readsToday: state.readsToday, monthlyReadsProjected: monthlyReads, monthlyCadProjected: round(monthlyReads / 100_000 * CAD_PER_100K_READS, 4) };

  // Days, oldest first, zero-filled, inheriting the observed version.
  const published = dayKeysEndingAt(now, config.daysPublished, timeZone);
  const publishedSet = new Set(published);
  let inherited: string | null = null;
  const dayRows: Record<string, unknown>[] = [];
  for (const day of [...new Set([...Object.keys(payload.days), ...published])].sort()) {
    if (day > published[published.length - 1]) break;
    const cell = payload.days[day];
    // A thin day inherits the observed version of the last day that earned one.
    if (publishedSet.has(day)) dayRows.push(publishedDay(cell ?? emptyDayCell(day), inherited));
    if (cell?.observedPolicy) inherited = cell.observedPolicy;
  }

  const sourceVersion = sourcePolicyVersion(knobs);
  const observedComplete = latestObserved ? Object.values(latestObserved.signature).every((value) => value != null) : false;
  const knobsBlock = { ...knobs, sourcePolicyVersion: sourceVersion, sourceSignature: declaredSignature(knobs), policySha256: stamp.policySha256,
    identitySha256: stamp.identitySha256, syncedAtMillis: stamp.syncedAtMillis, extractedFrom: stamp.extracted.sourceLines, source: KNOBS_SOURCE };
  const document: Record<string, unknown> = {
    version: DIGEST_SCHEMA_VERSION, digestVersion: state.digestVersion, generatedAtMillis: now, runId: input.runId, runMs: cost.runMs,
    headline, cost: costBlock, coverage, knobs: knobsBlock,
    observedPolicy: latestObserved ? { version: latestObserved.version, since: latestObserved.fromMillis, signature: latestObserved.signature, complete: observedComplete } : null,
    observedPolicyVersions: state.observedPolicyVersions.map(({ version, fromMillis }) => ({ version, fromMillis })),
    // null until every grant has been seen; then false is "source ahead of production".
    sourceMatchesObserved: observedComplete && latestObserved ? latestObserved.version === sourceVersion : null,
    observed, switches, gates: { ...GATES }, windows: { d7, d30 }, days: dayRows, channels, posts: posts.slice(0, config.postLimit),
    anchors: { worldMeters: knobs.maxRadiusMeters, everAtWorld, atWorld, rows: anchorRows.slice(0, ANCHOR_ROWS) },
    seedRest, claims, contamination, intercept, curve, questions, gaps,
  };
  return guardPublished(document);
}
function countRealEntries(fold: PostFold | undefined): number {
  return fold ? Object.values(fold.days).filter((cell) => cell.gr !== 0).length : 0;
}
function sumModes(modes: ModeMeters): number { return modes.normal + modes.trial + modes.stress + modes.undetermined; }
function firstBelowWorld(fold: PostFold, knobs: Knobs): number | null {
  // The fold keeps no per-entry history; the first day cell with a loss after the peak is the best witness.
  const days = Object.keys(fold.days).sort().filter((day) => fold.days[day].dl > 0);
  return fold.lastRadius < knobs.maxRadiusMeters && days.length ? dayStartMillis(days[0]) : null;
}

/** Hard guard at 400 KB serialized: halve posts, trim days to 14, drop the
 *  contamination list — in that order — and say so (§2.1). */
export function guardPublished(document: Record<string, unknown>): Record<string, unknown> {
  const size = () => JSON.stringify(document).length;
  if (size() <= PUBLISHED_GUARD_BYTES) return document;
  const coverage = document.coverage as Record<string, unknown>;
  const posts = document.posts as unknown[];
  document.posts = posts.slice(0, Math.ceil(posts.length / 2));
  coverage.trimmed = true;
  if (size() <= PUBLISHED_GUARD_BYTES) return document;
  const days = document.days as unknown[];
  document.days = days.slice(Math.max(0, days.length - 14));
  if (size() <= PUBLISHED_GUARD_BYTES) return document;
  const contamination = document.contamination as { d7: { posts: unknown[] } };
  contamination.d7.posts = [];
  return document;
}
