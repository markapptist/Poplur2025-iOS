/**
 * Daily algorithm report — the pure generator (design §1–§2).
 *
 * One report per Toronto day, rendered inside runDigestFold as step 8b from
 * the digest's in-memory state plus the document renderDigest just produced:
 * never before the cost roll, never from a re-scan, 0 reads. Every figure a
 * rule reads is gated (§2.5); every derived ratio is null below its gate in
 * the document itself; no uid ever leaves the state (fold addition 3 is
 * stripped by publishedDay and published as counts). Nothing here writes a
 * policy document: the report has no writer for one.
 *
 * Design: /Users/matrix/Developer/.codex/algorithm-reports-design.md.
 */
import type {
  ActorGain, DayCell, DigestConfig, DigestState, KindCounts, Knobs, ModeMeters, ObservedSignature, Payload, PostFold, PostMeta,
  RunCost, RunCoverage, Switches, SyncStamp,
} from "./algorithmDigestPolicy";
// Every import below is used at call time only: this module and algorithmDigestPolicy import each other.
import {
  CAD_PER_100K_READS, DIGEST_SCHEMA_VERSION, GATES, PUBLISHED_GUARD_BYTES, RATE_INFORMATIVE_MIN_ORGANIC, canonicalJson, dayKey,
  dayKeysEndingAt, dayPeople, dayStartMillis, declaredSignature, deepClone, emptyDayCell, isLive, maxKey, median, modeKey, observedSignature,
  observedSlice, postEndMillis, publishedDay, repeatLifetime, round, sha8, sourcePolicyVersion, windowStatsAt,
} from "./algorithmDigestPolicy";
import type {
  DriftCheck, EvalInput, EvidenceCell, GrantKind, KnobId, ObservedBlock, ObservedGrant, Outcome, PostCounts, Ratio, ReportGate,
  ReportLoopState, Subset, Verdict, VerdictKind, Reason, WindowMetrics,
} from "./algorithmReportRules";
import { KIND_TO_KNOB, KNOB_CATALOGUE, RULES, TUNABLE_KNOBS, computeGates, evaluateKnobs, ruleSetVersion } from "./algorithmReportRules";

// ── Constants ───────────────────────────────────────────────────────────────

export const REPORT_SCHEMA_VERSION = 1;
export const REPORT_INDEX_ROWS = 120;
export const REPORT_BACKFILL_DAYS = 14;
export const REPORT_CATCHUP_PER_RUN = 7;
export const REPORT_AMEND_PER_RUN = 2;
export const REPORT_AMEND_LOOKBACK_DAYS = 7;
export const REPORT_STAMP_DAYS = 14;
export const REPORT_PARTIAL_AFTER_MS = 6 * 3_600_000;
export const REPORT_OVERSIZE_BYTES = 900_000;
export const REPORT_FIELD_LIMIT_BYTES = 1_048_576;
export const REPORT_DAYS_PUBLISHED = 30;
const HOUR_MS = 3_600_000;
const DAY_MS = 86_400_000;

// ── State (stored as one JSON string beside `payload`) ──────────────────────

export interface IndexRow {
  day: string; generatedAtMillis: number; digestVersion: number; revision: number; partial: boolean; backfilled: boolean; catchUp: boolean;
  trialOn: boolean; trialMultiplier: number | null; decision: "suggest" | "verify" | "none"; knob: KnobId | null; to: number | null;
  counts: { suggest: number; verify: number; hold: number; insufficient: number; fixed: number };
  productionEpoch: string; sourcePolicyVersion: string; bytes: number; staleData?: boolean;
}
export type ReportFlags = { partial: boolean; backfilled: boolean; catchUp: boolean };
export interface DayStamp {
  knobs: Knobs; knobsHash: string; sourcePolicyVersion: string; ruleSetVersion: string; productionEpoch: string; dayHash: string;
  runId: string; generatedAtMillis: number; entriesOnDay: number; loop: ReportLoopState;
  outcomes: Partial<Record<KnobId, { outcome: Outcome | null; outcomeNote: string | null; openSinceDay: string | null; withdrawnDay: string | null }>>;
  /** How the revision was rendered: an amendment keeps `backfilled`/`catchUp` (decisions 12 and 20) and is never `partial` (§2.4). */
  flags: ReportFlags;
}
export interface ReportMemo {
  day: string; runId: string; revision: number; productionEpoch: string; digestResetAtMillis: number;
  metrics: Record<string, number | null>; gated: Record<string, boolean>;
  verdicts: Partial<Record<KnobId, { verdict: VerdictKind; reason: Reason; to: number | null }>>;
}
export interface ReportState {
  lastReportedDay: string | null; rows: IndexRow[]; revisions: Record<string, number>; stamps: Record<string, DayStamp>;
  last: ReportMemo | null; open: ReportLoopState["open"]; adopted: ReportLoopState["adopted"]; withdrawn: ReportLoopState["withdrawn"];
  lastKnobs: Record<string, number> | null; knobChanges: ReportLoopState["knobChanges"];
}
export function emptyReportState(): ReportState {
  return { lastReportedDay: null, rows: [], revisions: {}, stamps: {}, last: null, open: null, adopted: {}, withdrawn: {}, lastKnobs: null, knobChanges: {} };
}
const isRecord = (value: unknown): value is Record<string, unknown> => !!value && typeof value === "object" && !Array.isArray(value);
/** Stored verbatim (≈ 35 KB at 120 rows): a compact() pass would drop the zeros in `last.metrics` and make a 0 → n
 *  change invisible to `previous.changed`, so only the shape is defaulted here. */
export function hydrateReportState(stored: unknown): ReportState {
  const base = emptyReportState();
  if (!isRecord(stored)) return base;
  const out: ReportState = { ...base, ...(stored as Partial<ReportState>) };
  out.rows = Array.isArray(out.rows) ? out.rows.filter((row) => isRecord(row) && typeof row.day === "string").slice(0, REPORT_INDEX_ROWS) : [];
  for (const key of ["revisions", "stamps", "adopted", "withdrawn", "knobChanges"] as const) if (!isRecord(out[key])) (out as unknown as Record<string, unknown>)[key] = {};
  if (!isRecord(out.last)) out.last = null;
  if (!isRecord(out.open)) out.open = null;
  if (!isRecord(out.lastKnobs)) out.lastKnobs = null;
  if (typeof out.lastReportedDay !== "string") out.lastReportedDay = null;
  return out;
}

// ── Time ────────────────────────────────────────────────────────────────────

/** The day after `day` in the zone: +30 h from its midnight lands inside the next day whatever DST did. */
export function nextDay(day: string, timeZone: string): string { return dayKey(dayStartMillis(day, timeZone) + 30 * HOUR_MS, timeZone); }
export function dayEndMillis(day: string, timeZone: string): number { return dayStartMillis(nextDay(day, timeZone), timeZone); }
export function daysEnding(day: string, count: number, timeZone: string): string[] { return dayKeysEndingAt(dayEndMillis(day, timeZone) - 1, count, timeZone); }
export function dayPlus(day: string, days: number): string {
  const [y, m, d] = day.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + days, 12)).toISOString().slice(0, 10);
}
const utcStamp = (millis: number | null): string => {
  if (millis == null) return "?";
  const date = new Date(millis);
  return `${date.getUTCDate()} ${["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"][date.getUTCMonth()]} ${String(date.getUTCHours()).padStart(2, "0")}:${String(date.getUTCMinutes()).padStart(2, "0")}Z`;
};
const fmt = (value: number | null | undefined, places = 0): string => value == null || !Number.isFinite(value) ? "—"
  : value.toLocaleString("en-CA", { minimumFractionDigits: places, maximumFractionDigits: places });

// ── Production epochs (§1.9) ────────────────────────────────────────────────

export type TrialClass = "trial" | "normal" | null;
export function trialClass(cell: DayCell | undefined): TrialClass {
  if (!cell) return null;
  const modes = cell.realPostDecayLoss.byMode;
  if (modes.trial > 0 && modes.trial >= modes.normal) return "trial";
  if (modes.normal > modes.trial) return "normal";
  return null;
}
export function trialSeenOnDay(cell: DayCell | undefined): number | null { return cell ? modeKey(cell.realPostDecayLoss.trialMultipliers) : null; }

export interface Epoch { id: string; fromDay: string; toDay: string; days: number; signature: Record<string, unknown>; boundaryCause: "grant" | "trial" | "window-start"; movedFields: string[] }
interface EpochStrip { epochs: Epoch[]; byDay: Record<string, string>; signatures: Record<string, ObservedSignature> }
const SIGNATURE_FIELDS: (keyof ObservedSignature)[] = ["view", "like", "comment", "dislike", "repeatBase", "seedSeen"];

/** Every trailing day since the cold start: the rolling 7-day signature, the day's trial class and multiplier,
 *  and a boundary wherever a field goes non-null → a DIFFERENT non-null (null ↔ value is "unseen", never
 *  "changed"). The epoch id is the signature at the day the boundary was detected, so it is stable across
 *  reports; a strip never depends on the digest's hash-based versions (a null flicker mints one there). */
export function epochStrip(payload: Payload, day: string, timeZone: string): EpochStrip {
  const firstDay = [...Object.keys(payload.days), ...Object.keys(payload.observed), day].sort()[0];
  const days: string[] = [];
  for (let d = firstDay; d <= day && days.length < 4_000; d = nextDay(d, timeZone)) days.push(d);
  const epochs: Epoch[] = []; const byDay: Record<string, string> = {}; const signatures: Record<string, ObservedSignature> = {};
  let prevSig: ObservedSignature | null = null; let lastTrial: TrialClass = null; let lastMultiplier: number | null = null;
  const epochSignature = (sig: ObservedSignature, trial: TrialClass, multiplier: number | null) => {
    const grants: Record<string, number> = {};
    for (const field of SIGNATURE_FIELDS) if (sig[field] != null) grants[field] = sig[field] as number;
    return { grants, trial, trialMultiplier: multiplier };
  };
  for (const d of days) {
    const sig = observedSignature(observedSlice(payload, daysEnding(d, 7, timeZone)));
    signatures[d] = sig;
    const cell = payload.days[d];
    const trial = trialClass(cell);
    const multiplier = trialSeenOnDay(cell);
    const moved: string[] = [];
    if (prevSig) for (const field of SIGNATURE_FIELDS) if (prevSig[field] != null && sig[field] != null && prevSig[field] !== sig[field]) moved.push(field);
    let cause: Epoch["boundaryCause"] | null = epochs.length === 0 ? "window-start" : null;
    if (moved.length) cause = "grant";
    else if (trial != null && lastTrial != null && trial !== lastTrial) cause = "trial";
    else if (trial === "trial" && multiplier != null && lastMultiplier != null && multiplier !== lastMultiplier) cause = "trial";
    if (cause) {
      const signature = epochSignature(sig, trial, multiplier);
      epochs.push({ id: sha8(signature), fromDay: d, toDay: d, days: 1, signature, boundaryCause: cause, movedFields: moved });
    } else { const current = epochs[epochs.length - 1]; current.toDay = d; current.days += 1; }
    byDay[d] = epochs[epochs.length - 1].id;
    prevSig = sig;
    if (trial != null) lastTrial = trial;
    if (trial === "trial" && multiplier != null) lastMultiplier = multiplier;
  }
  return { epochs, byDay, signatures };
}

// ── Windows and their metrics ───────────────────────────────────────────────

interface NetBucket { posts: number; netPositive: number; postDays: number; gainRealMeters: number; lossRealShareMeters: number; perPostDay: number | null }
interface WindowContext { state: DigestState; timeZone: string; knobs: Knobs; strip: EpochStrip; kindSplitSince: number | null }
const ratio = (numerator: number, denominator: number): Ratio => ({ value: denominator > 0 ? round(numerator / denominator, 4) : null, numerator, denominator });
const isTester = (meta: PostMeta) => meta.cls === "r" && meta.ownerClass === "r";

/** windowStatsAt + the report's gating (rates null below their bucket's gate, §1.7) + `spanned` from the
 *  report's own epochs + the per-window people figures (fold addition 3) + the typed metrics the rules read. */
export function reportWindow(ctx: WindowContext, name: string, days: string[], endMillis: number): { stats: Record<string, unknown>; metrics: WindowMetrics } {
  const { state, timeZone, knobs } = ctx;
  const payload = state.payload;
  const stats = windowStatsAt({ state, timeZone }, days, endMillis);
  const gateBuckets = (block: { byAge: Record<string, NetBucket>; all: NetBucket }) => {
    for (const bucket of [...Object.values(block.byAge), block.all]) if (bucket.posts < GATES.minPosts) bucket.perPostDay = null;
  };
  gateBuckets(stats.netReal as { byAge: Record<string, NetBucket>; all: NetBucket });
  gateBuckets(stats.netOwner as { byAge: Record<string, NetBucket>; all: NetBucket });
  const worth = stats.viewWorth as { views: number | null; cleanPosts: number };
  if (worth.cleanPosts < GATES.minPosts) worth.views = null;
  const spanned = [...new Set(days.map((d) => ctx.strip.byDay[d]).filter((id): id is string => !!id))];
  stats.spanned = spanned;

  // Accrual (§2.3): the whole window lies after the kind-split stamp, or the stamp is 0 (introduced on an empty payload).
  const since = ctx.kindSplitSince;
  const accrued = since === 0 || (since != null && dayStartMillis(days[0], timeZone) >= since);
  const accruedDays = accrued ? days : since == null ? [] : days.filter((d) => dayStartMillis(d, timeZone) >= since);
  const merged: Record<string, KindCounts> = {};
  let events = 0;
  for (const d of accruedDays) {
    const cell = payload.days[d];
    if (!cell) continue;
    events += cell.realPostGain.real.n;
    for (const [uid, counts] of Object.entries(cell.realActorEntries)) {
      const slot = merged[uid] ??= { v: 0, l: 0, c: 0, d: 0 };
      slot.v += counts.v; slot.l += counts.l; slot.c += counts.c; slot.d += counts.d;
    }
  }
  const people = { ...dayPeople(merged, events), events };
  const gain = (stats.realPostGain as Record<string, ActorGain>).real;
  const loss = stats.realPostDecayLoss as { byMode: ModeMeters; byClass: { real: number } };
  const modeTotal = loss.byMode.normal + loss.byMode.trial + loss.byMode.stress + loss.byMode.undetermined;
  const trialShare = ratio(loss.byMode.trial + loss.byMode.stress + loss.byMode.undetermined, modeTotal);

  // Tester posts with a real engagement INSIDE the window (gr ≠ 0: a dislike-only day counts, refuter 7a).
  const daySet = new Set(days);
  let testerWithReal = 0;
  const windowStart = dayStartMillis(days[0], timeZone);
  const subsets = { viewsOnly: { posts: 0, netPositive: 0 }, liked: { posts: 0, netPositive: 0 }, commented: { posts: 0, netPositive: 0 } };
  for (const [postId, meta] of Object.entries(payload.postMeta)) {
    if (!isTester(meta)) continue;
    const fold = payload.folds[postId];
    if (!fold) continue;
    if (Object.entries(fold.days).some(([d, cell]) => daySet.has(d) && cell.gr !== 0)) testerWithReal += 1;
    // The P:1255-1270 loop restricted to the d7to30 bucket and a kind-split-known subset.
    const end = postEndMillis(meta, endMillis);
    if (meta.createdAtMillis > endMillis || end < windowStart) continue;
    const ageDays = (endMillis - meta.createdAtMillis) / DAY_MS;
    if (ageDays < 7 || ageDays > 30) continue;
    if (!kindSplitKnown(fold, since)) continue;
    let net = 0;
    for (const [d, cell] of Object.entries(fold.days)) if (daySet.has(d)) net += cell.gr - cell.dlr;
    const bump = (subset: Subset) => { subset.posts += 1; if (net > 0) subset.netPositive += 1; };
    if (fold.rk.v > 0 && fold.rk.l + fold.rk.c + fold.rk.d === 0) bump(subsets.viewsOnly);
    if (fold.rk.l > 0) bump(subsets.liked);
    if (fold.rk.c > 0) bump(subsets.commented);
  }

  // Dislikes (fold addition 2, refuters 9/26): exact once the counters have accrued; before that exact only with no clamp in W.
  const grant = Math.abs(knobs.dislikeMeters) || 1;
  const lowerBound = Math.round(Math.abs(gain.dislike) / grant);
  let dislikeN: number | null; let exact: boolean; let note: string;
  if (accrued) { dislikeN = gain.clampedDislikes + Math.round((Math.abs(gain.dislike) - Math.abs(gain.clampedDislikeMeters)) / grant); exact = true; note = "clamped dislikes + full dislikes"; }
  else if (gain.clamped === 0) { dislikeN = lowerBound; exact = true; note = "no clamp in the window — |dislike m| / grant is exact"; }
  else { dislikeN = null; exact = false; note = `unmeasured: ${gain.clamped} clamped entries of every kind in the window and no per-kind counter yet`; }
  const metrics: WindowMetrics = {
    name, days, spanned, accrued, accrualSinceDay: since ? dayKey(since, timeZone) : null,
    gain, dayDistinct: { viewers: stats.distinctRealViewers as number, likers: stats.distinctRealLikers as number, commenters: stats.distinctRealCommenters as number },
    people, modes: loss.byMode, trialShare, realLoss: loss.byClass.real, seedLoss: stats.realPostSeedLoss as number, boostLoss: stats.realPostBoostLoss as number, net: (stats.netReal as { byAge: Record<"lt7d" | "d7to30" | "gt30d", NetBucket>; all: NetBucket }).byAge as WindowMetrics["net"],
    subsets, testerWithReal, dislike: { n: dislikeN, lowerBound, clampedShare: ratio(gain.clampedDislikes, dislikeN ?? 0), exact, note },
    boosts: stats.boosts as { n: number; meters: number },
  };
  metrics.net = { ...metrics.net, all: (stats.netReal as { all: NetBucket }).all };
  return { stats, metrics };
}
function kindSplitKnown(fold: PostFold, since: number | null): boolean {
  return since === 0 || (since != null && fold.firstRealAt != null && fold.firstRealAt >= since);
}

/** Post-side counts the rules read (§2.5 metric ids `posts.*`, `stale.count`). */
export function postCounts(payload: Payload, dayEnd: number, since: number | null): PostCounts {
  const out: PostCounts = { testerWithReal: 0, liveTester: 0, liveTester7d: 0, liveTesterClean468: 0, stale: 0, viewsOnly: 0, liked: 0, commented: 0, kindMixUnknown: 0, expired: 0 };
  for (const [postId, meta] of Object.entries(payload.postMeta)) {
    const fold = payload.folds[postId];
    if (!fold) continue;
    if (fold.lastRadius <= 0 && fold.n > 0) out.expired += 1;
    if (!isTester(meta)) continue;
    if (fold.firstRealAt != null) {
      out.testerWithReal += 1;
      if (!kindSplitKnown(fold, since)) out.kindMixUnknown += 1;
      else {
        if (fold.rk.v > 0 && fold.rk.l + fold.rk.c + fold.rk.d === 0) out.viewsOnly += 1;
        if (fold.rk.l > 0) out.liked += 1;
        if (fold.rk.c > 0) out.commented += 1;
      }
    }
    if (!isLive(meta, fold)) continue;
    out.liveTester += 1;
    if (meta.createdAtMillis <= dayEnd - 7 * DAY_MS) out.liveTester7d += 1;
    // Clean = never pumped AND a REAL pool ≥ 468 m (fold.organic is every class's organic — refuter 15).
    if (!fold.everPumped && fold.pool.real >= RATE_INFORMATIVE_MIN_ORGANIC) {
      out.liveTesterClean468 += 1;
      if (fold.lastRealAt != null && fold.lastRealAt < dayEnd - 30 * DAY_MS) out.stale += 1;
    }
  }
  return out;
}

const grantOf = (slice: Record<string, { byMeters: Record<string, number>; min: number | null; max: number | null; n: number }>, key: string): ObservedGrant => {
  const slot = slice[key];
  return slot ? { n: slot.n, modeMeters: modeKey(slot.byMeters), min: slot.min, max: slot.max, byMeters: slot.byMeters } : { n: 0, modeMeters: null, min: null, max: null, byMeters: {} };
};
/** The published observed block (P:1512-1517) over an explicit day list — the 7 days ending D, never the run's. */
export function observedBlock(payload: Payload, days: string[]): ObservedBlock {
  const slice = observedSlice(payload, days);
  return { grants: { view: grantOf(slice, "view"), repeat: grantOf(slice, "repeat"), like: grantOf(slice, "like"), dislike: grantOf(slice, "dislike"), comment: grantOf(slice, "comment") },
    seedSeen: grantOf(slice, "seed"), boostSeen: { meters: grantOf(slice, "boost"), hours: grantOf(slice, "boostHours") },
    sampleEntries: ["view", "repeat", "like", "dislike", "comment"].reduce((total, key) => total + (slice[key]?.n ?? 0), 0),
    clamped: slice.clamped?.n ?? 0, resync: slice.resync?.n ?? 0 };
}

// ── The metric table ────────────────────────────────────────────────────────

export interface MetricRow {
  id: string; value: number | null; unit: string; n: number | null; gate: ReportGate | null; window: string; population: string; basis: string;
  numerator: number | null; denominator: number | null;
}
const WINDOW_METRIC_TEMPLATE = [
  "M1.gain.{W}", "M1.view.{W}", "M1.like.{W}", "M1.comment.{W}", "M1.dislike.{W}", "M1.firstViews.{W}", "M1.repeatViews.{W}", "M1.repeatMeters.{W}", "M1.clamped.{W}", "M1.clampedDislikes.{W}",
  "M3.viewersDay.{W}", "M3.likersDay.{W}", "M3.commentersDay.{W}", "M3.actorsW.{W}", "M3.viewersW.{W}", "M3.likersW.{W}", "M3.commentersW.{W}", "maxShare.{W}",
  "M5.trial.{W}", "M5.normal.{W}", "M5.stress.{W}", "M5.undetermined.{W}", "M5.real.{W}", "M5.seedLoss.{W}", "M5.boostLoss.{W}",
  "M6.lt7d.posts.{W}", "M6.lt7d.netPositive.{W}", "M6.lt7d.gainRealMeters.{W}", "M6.lt7d.lossRealShareMeters.{W}", "M6.lt7d.perPostDay.{W}",
  "M6.d7to30.posts.{W}", "M6.d7to30.netPositive.{W}", "M6.d7to30.gainRealMeters.{W}", "M6.d7to30.lossRealShareMeters.{W}", "M6.d7to30.perPostDay.{W}",
  "M6.gt30d.posts.{W}", "M6.gt30d.netPositive.{W}", "M6.gt30d.gainRealMeters.{W}", "M6.gt30d.lossRealShareMeters.{W}", "M6.gt30d.perPostDay.{W}",
  "M6.all.posts.{W}", "M6.all.perPostDay.{W}", "M12.boosts.n.{W}", "M12.boosts.m.{W}", "posts.testerWithRealW.{W}", "dislike.n.{W}", "dislike.clampedShare.{W}",
  "share.view.{W}", "share.like.{W}", "share.comment.{W}", "share.dislike.{W}", "likersPerViewer.{W}", "repeatDepth.{W}", "repeatShare.{W}", "trialShare.{W}",
  "netPos.lt7d.{W}", "netPos.d7to30.{W}", "netPos.gt30d.{W}", "lossRatio.lt7d.{W}", "lossRatio.d7to30.{W}", "lossRatio.gt30d.{W}",
  "netPosViewsOnly.d7to30.{W}", "netPosLiked.d7to30.{W}", "netPosCommented.d7to30.{W}",
];
const FIXED_METRIC_IDS = [
  "M3.actors", "M9.synthShare.d7", "M9.synthMeters.d7", "M9.synthEntries.d7", "M1.gain.d7", "M1.gain.d1",
  "M4.pairs", "M4.realAccounts", "M4.realized", "M4.nearMissPairs", "M4.interceptRate", "M8.atClaimShare", "M8.livePosts", "M8.cleanPosts",
  "M11.count", "M11.atFloor", "M11.median", "M11.aboveFloorThatEarned", "M13.atWorld", "M13.everAtWorld",
  "M16.view.seen", "M16.view.n", "M16.like.seen", "M16.like.n", "M16.comment.seen", "M16.comment.n", "M16.dislike.seen", "M16.dislike.n", "M16.repeat.seen", "M16.repeat.n",
  "M17.readsOnDay", "M17.cadOnDay", "M17.monthlyCad", "M18.complete", "M18.postsBehindHorizon",
  "posts.testerWithReal", "posts.liveTester", "posts.liveTester7d", "posts.liveTesterClean468", "stale.count", "stale.share", "posts.viewsOnly", "posts.liked", "posts.commented", "posts.kindMixUnknown",
];
/** The compare key space: every id a report publishes for its d30 window plus the snapshot and lifetime ids. */
export const METRIC_IDS: readonly string[] = Object.freeze([...WINDOW_METRIC_TEMPLATE.map((id) => id.replace("{W}", "d30")), ...FIXED_METRIC_IDS]);
const SNAPSHOT_METRIC_PREFIXES = ["M4.", "M8.", "M11.", "M13.", "M18."];

function windowMetricRows(W: WindowMetrics, day: string, posts: PostCounts, gKinds: boolean): MetricRow[] {
  const g = computeGates(W, day);
  const row = (id: string, value: number | null, unit: string, extra: Partial<MetricRow> = {}): MetricRow =>
    ({ id: `${id}.${W.name}`, value, unit, n: W.gain.n, gate: null, window: W.name, population: "real", basis: `real posts × real actors · ${W.name}`, numerator: null, denominator: null, ...extra });
  const gated = (id: string, r: Ratio, gate: ReportGate): MetricRow => row(id, gate.sufficient ? r.value : null, "ratio", { gate, numerator: r.numerator, denominator: r.denominator });
  const total = Math.max(0, W.gain.total);
  const bucketGate = (b: "lt7d" | "d7to30" | "gt30d"): ReportGate => ({ id: `Gposts.${b}`, label: `≥ ${GATES.minPosts} tester posts in the ${b} age bucket`, n: W.net[b].posts, minN: GATES.minPosts, sufficient: W.net[b].posts >= GATES.minPosts, basis: "netReal.byAge" });
  const subsetGate = (label: string, s: Subset): ReportGate => ({ id: "Gkinds", label: `≥ ${GATES.minPosts} kind-split-known ${label} posts aged 7–30 d`, n: s.posts, minN: GATES.minPosts, sufficient: gKinds && s.posts >= GATES.minPosts, basis: "PostFold.rk" });
  const peopleGate = { ...g.Gc, id: "Gsplit", label: "per-window people figures (fold addition 3) accrued over the whole window" };
  const rows: MetricRow[] = [
    row("M1.gain", W.gain.total, "m", { gate: g.Gc }), row("M1.view", W.gain.view, "m", { gate: g.Gc }), row("M1.like", W.gain.like, "m", { gate: g.Gc }),
    row("M1.comment", W.gain.comment, "m", { gate: g.Gc }), row("M1.dislike", W.gain.dislike, "m", { gate: g.Gc }),
    row("M1.firstViews", W.gain.firstViews, "count"), row("M1.repeatViews", W.gain.repeatViews, "count"), row("M1.repeatMeters", W.gain.repeatMeters, "m"),
    row("M1.clamped", W.gain.clamped, "count"), row("M1.clampedDislikes", W.gain.clampedDislikes, "count"),
    row("M3.viewersDay", W.dayDistinct.viewers, "count", { basis: "Σ day-distinct real viewers (day-distinct, gates nothing)" }),
    row("M3.likersDay", W.dayDistinct.likers, "count", { basis: "Σ day-distinct real likers (day-distinct, gates nothing)" }),
    row("M3.commentersDay", W.dayDistinct.commenters, "count", { basis: "Σ day-distinct real commenters (day-distinct, gates nothing)" }),
    row("M3.actorsW", W.accrued ? W.people.actors : null, "count", { gate: peopleGate, basis: W.accrued ? "distinct real uids in the window (other ≤ 1 person)" : `since ${W.accrualSinceDay ?? "?"} only: ${W.people.actors}` }),
    row("M3.viewersW", W.accrued ? W.people.viewers : null, "count", { gate: peopleGate }), row("M3.likersW", W.accrued ? W.people.likers : null, "count", { gate: peopleGate }),
    row("M3.commentersW", W.accrued ? W.people.commenters : null, "count", { gate: peopleGate }),
    row("maxShare", W.accrued ? W.people.maxShare : null, "ratio", { gate: peopleGate, numerator: null, denominator: W.people.events }),
    row("M5.trial", round(W.modes.trial), "m"), row("M5.normal", round(W.modes.normal), "m"), row("M5.stress", round(W.modes.stress), "m"), row("M5.undetermined", round(W.modes.undetermined), "m"),
    row("M5.real", round(W.realLoss), "m"), row("M5.seedLoss", round(W.seedLoss), "m"), row("M5.boostLoss", round(W.boostLoss), "m"),
  ];
  for (const b of ["lt7d", "d7to30", "gt30d"] as const) {
    const bucket = W.net[b];
    rows.push(row(`M6.${b}.posts`, bucket.posts, "count", { n: bucket.posts }), row(`M6.${b}.netPositive`, bucket.netPositive, "count", { n: bucket.posts }),
      row(`M6.${b}.gainRealMeters`, bucket.gainRealMeters, "m", { n: bucket.posts }), row(`M6.${b}.lossRealShareMeters`, bucket.lossRealShareMeters, "m", { n: bucket.posts }),
      row(`M6.${b}.perPostDay`, bucket.perPostDay, "m/post-day", { n: bucket.posts, gate: bucketGate(b) }));
  }
  rows.push(row("M6.all.posts", W.net.all.posts, "count", { n: W.net.all.posts }), row("M6.all.perPostDay", W.net.all.perPostDay, "m/post-day", { n: W.net.all.posts }),
    row("M12.boosts.n", W.boosts.n, "count", { population: "paid" }), row("M12.boosts.m", W.boosts.meters, "m", { population: "paid" }),
    row("posts.testerWithRealW", W.testerWithReal, "count", { gate: g.Gd }),
    row("dislike.n", W.dislike.n, "count", { gate: g.Gdislike, basis: W.dislike.note }), gated("dislike.clampedShare", W.dislike.clampedShare, g.Gdislike),
    gated("share.view", ratio(W.gain.view, total), g.Gc), gated("share.like", ratio(W.gain.like, total), g.Gc), gated("share.comment", ratio(W.gain.comment, total), g.Gc),
    gated("share.dislike", ratio(Math.abs(W.gain.dislike), total), g.Gc), gated("likersPerViewer", ratio(W.people.likers, W.people.viewers), g.Gc),
    gated("repeatDepth", ratio(W.gain.repeatViews, W.people.viewers), g.Gc), gated("repeatShare", ratio(W.gain.repeatMeters, total), g.Gc),
    row("trialShare", W.trialShare.value, "ratio", { numerator: W.trialShare.numerator, denominator: W.trialShare.denominator, population: "real posts · decay loss by mode" }));
  for (const b of ["lt7d", "d7to30", "gt30d"] as const) {
    rows.push(gated(`netPos.${b}`, ratio(W.net[b].netPositive, W.net[b].posts), bucketGate(b)), gated(`lossRatio.${b}`, ratio(W.net[b].lossRealShareMeters, W.net[b].gainRealMeters), bucketGate(b)));
  }
  rows.push(gated("netPosViewsOnly.d7to30", ratio(W.subsets.viewsOnly.netPositive, W.subsets.viewsOnly.posts), subsetGate("viewed-only", W.subsets.viewsOnly)),
    gated("netPosLiked.d7to30", ratio(W.subsets.liked.netPositive, W.subsets.liked.posts), subsetGate("liked", W.subsets.liked)),
    gated("netPosCommented.d7to30", ratio(W.subsets.commented.netPositive, W.subsets.commented.posts), subsetGate("commented", W.subsets.commented)));
  void posts;
  return rows;
}

// ── The render ──────────────────────────────────────────────────────────────

export interface ReportRenderInput {
  state: DigestState; published: Record<string, unknown>; config: DigestConfig; switches: Switches; knobs: Knobs; stamp: SyncStamp; timeZone: string;
  day: string; runStartMillis: number; runId: string; digestVersion: number;
  flags: { partial: boolean; backfilled: boolean; catchUp: boolean }; revision: number;
  supersedes: { runId: string; generatedAtMillis: number; entriesOnDay: number } | null;
  readsOnDay: number | null; runsOnDay: number | null; nonLivePollLagRuns: number; complete: boolean;
  loop: ReportLoopState; last: ReportMemo | null; lastResetAtMillis: number;
  /** An amendment renders with the ORIGINAL revision's stamp and copies its outcome fields (§2.4). */
  amendment: DayStamp | null;
}
export interface ReportRender {
  document: Record<string, unknown>; indexRow: IndexRow; stamp: DayStamp; loop: ReportLoopState; memo: ReportMemo; trimmed: boolean;
}

export function renderReport(input: ReportRenderInput): ReportRender {
  const { state, published, switches, timeZone, day, runStartMillis, flags } = input;
  const knobs = input.amendment ? input.amendment.knobs : input.knobs;
  const payload = state.payload;
  const dayStart = dayStartMillis(day, timeZone), dayEnd = dayEndMillis(day, timeZone);
  const cell = payload.days[day] ?? emptyDayCell(day);
  const since = payload.coverage.kindSplitSinceMillis;
  const strip = epochStrip(payload, day, timeZone);
  const ctx: WindowContext = { state, timeZone, knobs, strip, kindSplitSince: since };
  const rules = input.amendment ? input.amendment.ruleSetVersion : ruleSetVersion();

  // Trial per DAY, never the run-time switch alone (§1.3).
  const trial = switches.decayTrial;
  const dayTrialClass = trialClass(cell);
  const seenOnDay = trialSeenOnDay(cell);
  const trialOnDay = dayTrialClass === "trial" || (trial?.enabled === true && (trial.effectiveAtMillis == null || trial.effectiveAtMillis <= dayEnd));
  const trialMultiplierOnDay = seenOnDay ?? (trialOnDay ? trial?.multiplier ?? null : null);

  // Windows: d1 / d7 / d30 end at D's last millisecond; before/after around the newest boundary inside d30.
  const d30Days = daysEnding(day, 30, timeZone), d7Days = daysEnding(day, 7, timeZone);
  const d1 = reportWindow(ctx, "d1", [day], dayEnd), d7 = reportWindow(ctx, "d7", d7Days, dayEnd), d30 = reportWindow(ctx, "d30", d30Days, dayEnd);
  const boundaries = strip.epochs.filter((epoch) => epoch.boundaryCause !== "window-start" && epoch.fromDay > d30Days[0] && epoch.fromDay <= day);
  const newest = boundaries[boundaries.length - 1] ?? null;
  let before: ReturnType<typeof reportWindow> | null = null, after: ReturnType<typeof reportWindow> | null = null;
  if (newest) {
    const afterDays = d30Days.filter((d) => d >= newest.fromDay);
    after = reportWindow(ctx, "after", afterDays, dayEnd);
    const beforeEnd = dayStartMillis(newest.fromDay, timeZone);
    before = reportWindow(ctx, "before", dayKeysEndingAt(beforeEnd - 1, 7, timeZone), beforeEnd);
  }
  const W: WindowMetrics | null = !newest ? d30.metrics : after && after.metrics.days.length >= RULES.epochMinDays ? after.metrics : null;
  const epochYoungResumesDay = newest && !W ? dayPlus(newest.fromDay, RULES.epochMinDays - 1) : null;
  const epochs: Epoch[] = strip.epochs.filter((epoch) => epoch.toDay >= d30Days[0] && epoch.fromDay <= day).map((epoch) => {
    const fromDay = epoch.fromDay < d30Days[0] ? d30Days[0] : epoch.fromDay;
    return { ...epoch, fromDay, toDay: epoch.toDay > day ? day : epoch.toDay, days: d30Days.filter((d) => d >= fromDay && d <= epoch.toDay).length,
      boundaryCause: epoch.fromDay < d30Days[0] ? "window-start" as const : epoch.boundaryCause };
  });
  const productionEpoch = input.amendment ? input.amendment.productionEpoch : strip.byDay[day];
  // Freeze (§1.9, §2.5): the knob whose field moved at a boundary inside the last 30 days is hold/changed-recently until B + 30.
  const frozen: EvalInput["frozen"] = {};
  for (const epoch of strip.epochs) {
    if (epoch.boundaryCause !== "grant" || dayPlus(epoch.fromDay, RULES.freezeDays) <= day || epoch.fromDay > day) continue;
    for (const field of epoch.movedFields) {
      const kind = field === "repeatBase" ? "repeat" : field;
      const knob = (KIND_TO_KNOB as Record<string, KnobId>)[kind];
      if (knob) frozen[knob] = { untilDay: dayPlus(epoch.fromDay, RULES.freezeDays), cause: `${field} grant moved in production on ${epoch.fromDay} (detected as a rolling 7-day mode, all actor classes)` };
    }
  }
  for (const [knob, adoption] of Object.entries(input.loop.adopted) as [KnobId, { day: string; direction: "lower" | "raise" }][]) {
    if (dayPlus(adoption.day, RULES.freezeDays) > day) frozen[knob] = { untilDay: dayPlus(adoption.day, RULES.freezeDays), cause: `adopted in production on ${adoption.day}` };
  }

  // Observed grants over the 7 days ending D (never the run's day), the checks, the posts.
  const observed7d = observedBlock(payload, d7Days);
  const observedOnDay = observedBlock(payload, [day]);
  const posts = postCounts(payload, dayEnd, since);
  const open = input.loop.open;
  const drift: DriftCheck = { status: "clear", verify: [], awaitingDeploy: [], rows: {} };
  const driftRow = (kind: string, seen: number | null, declared: number, n: number, minN: number, knobId: KnobId | null) => {
    const awaiting = !!(open && knobId && open.knob === knobId && knobs[KNOB_CATALOGUE.find((s) => s.id === knobId)!.knob!] === open.to && seen === open.from);
    const status = n < minN ? "unseen" : seen === declared ? "clear" : awaiting ? "awaiting-deploy" : "verify";
    drift.rows[kind] = { seen, declared, n, status };
    if (status === "verify") { drift.verify.push(`${kind} ${fmt(seen)} ≠ ${fmt(declared)} (n ${n})`); drift.status = "verify"; }
    if (status === "awaiting-deploy") drift.awaitingDeploy.push(kind);
  };
  driftRow("view", observed7d.grants.view.modeMeters, knobs.firstViewMeters, observed7d.grants.view.n, GATES.minEvents, "K1");
  driftRow("like", observed7d.grants.like.modeMeters, knobs.likeMeters, observed7d.grants.like.n, GATES.minEvents, "K2");
  driftRow("comment", observed7d.grants.comment.modeMeters, knobs.commentMeters, observed7d.grants.comment.n, GATES.minEvents, "K3");
  driftRow("dislike", observed7d.grants.dislike.modeMeters, knobs.dislikeMeters, observed7d.grants.dislike.n, GATES.minEvents, "K4");
  driftRow("repeat", maxKey(observed7d.grants.repeat.byMeters), knobs.repeatViewBaseMeters, observed7d.grants.repeat.n, GATES.minEvents, "K5");
  driftRow("seed", observed7d.seedSeen.modeMeters, knobs.seedMeters, observed7d.seedSeen.n, RULES.gates.minSeedSeen, null);
  const farmCeiling = knobs.firstViewMeters + knobs.likeMeters + knobs.commentMeters + repeatLifetime(knobs.repeatViewBaseMeters);
  const farmBound = farmCeiling * payload.realActorUids.length;
  const farmViolations = Object.entries(payload.postMeta).filter(([postId, meta]) => meta.cls === "r" && (payload.folds[postId]?.gainReal ?? 0) > farmBound).length;
  const farm = { status: farmViolations > 0 ? "verify" as const : "clear" as const, detail: `per-actor ceiling ${fmt(farmCeiling)} m × ${payload.realActorUids.length} lifetime real actors = ${fmt(farmBound)} m; ${farmViolations} real post(s) above it (aggregate bound — per-post actor sets are not in state)` };

  // Snapshots — as of the writing run, null when backfilled (decision 12). The digest's contamination block carries the
  // daily simulation's owner uid verbatim (Admin-only, the desk prints it); the report masks it the way `policy.simulation`
  // and the K17 row do, so no uid reaches the report body (decision 8, test 20).
  const snapshots = flags.backfilled ? null : {
    seedRest: published.seedRest ?? null, claims: published.claims ?? null, contamination: maskContamination(published.contamination), intercept: published.intercept ?? null,
    anchors: published.anchors ?? null, curve: published.curve ?? null, questions: published.questions ?? null, gaps: published.gaps ?? null,
  };
  const headlinePub = (published.headline ?? {}) as Record<string, unknown>;
  const coveragePub = (published.coverage ?? {}) as Record<string, unknown>;
  const intercept = (snapshots?.intercept ?? null) as { realized: { entries: number; distinctPosts: number; distinctActors: number }; opportunity: { pairs: number; nearMissPairs: number; realAccountsWithLocation: number } } | null;
  const seedRest = (snapshots?.seedRest ?? null) as { valid: boolean; livePosts: number; atClaim: number; cleanPosts: number } | null;
  const claims = (snapshots?.claims ?? null) as { d30: { count: number; atFloor: number; medianMeters: number | null; aboveFloorThatEarned: number } } | null;
  const gaps = (snapshots?.gaps ?? null) as { id: string; labelledEntries?: number }[] | null;
  const anchorsAtWorld = (headlinePub.anchorsAtWorld as number) ?? 0, anchorsEver = (headlinePub.anchorsEver as number) ?? 0;
  const medianTesterPeak = median(Object.entries(payload.postMeta).filter(([, meta]) => isTester(meta)).map(([id]) => payload.folds[id]?.peakOrganic ?? 0).filter((peak) => peak > 0));
  const adoptedProduction = (() => {
    if (!open) return null;
    const spec = KNOB_CATALOGUE.find((s) => s.id === open.knob)!;
    if (!spec.kind || !spec.knob) return null;
    const change = input.loop.knobChanges[spec.knob];
    if (!change) return null;
    const days: string[] = [];
    for (let d = nextDay(change.day, timeZone); d <= day && days.length < 400; d = nextDay(d, timeZone)) days.push(d);
    if (!days.length) return { value: null, n: 0 };
    const block = observedBlock(payload, days);
    const slot = block.grants[spec.kind];
    return { value: spec.kind === "repeat" ? maxKey(slot.byMeters) : slot.modeMeters, n: slot.n };
  })();
  const extraEvidence: EvalInput["extraEvidence"] = {
    K8: [{ id: "posts.expired", value: posts.expired, unit: "count" }],
    K9: [{ id: "M8.atClaimShare", value: seedRest && seedRest.valid && seedRest.livePosts >= GATES.minPosts ? round(seedRest.atClaim / seedRest.livePosts, 4) : null, unit: "ratio", numerator: seedRest?.atClaim ?? 0, denominator: seedRest?.livePosts ?? 0, label: seedRest ? (trialOnDay ? "hidden while the trial runs" : "proxy: last post location") : "no snapshot (backfilled)" },
      { id: "M8.livePosts", value: seedRest?.livePosts ?? null, unit: "count" }, { id: "M4.pairs", value: intercept?.opportunity.pairs ?? null, unit: "count" }, { id: "M4.nearMissPairs", value: intercept?.opportunity.nearMissPairs ?? null, unit: "count", label: "clean posts · within 2 × reach" }],
    K10: [{ id: "M11.count", value: claims?.d30.count ?? null, unit: "count" }, { id: "M11.atFloor", value: claims?.d30.atFloor ?? null, unit: "count" }, { id: "M11.median", value: claims?.d30.medianMeters ?? null, unit: "m" }, { id: "M11.aboveFloorThatEarned", value: claims?.d30.aboveFloorThatEarned ?? null, unit: "count" }],
    K12: [{ id: "M12.boosts.n.d30", value: d30.metrics.boosts.n, unit: "count" }, { id: "M12.boosts.m.d30", value: d30.metrics.boosts.meters, unit: "m" }, { id: "M16.boost.seen", value: observed7d.boostSeen.meters.modeMeters, unit: "m", n: observed7d.boostSeen.meters.n }],
    K13: [{ id: "M13.atWorld", value: anchorsAtWorld, unit: "count" }, { id: "M13.everAtWorld", value: anchorsEver, unit: "count" }],
    K14: [{ id: "trialSeenOnDay", value: seenOnDay, unit: "×" }, { id: "M5.trial.d1", value: round(cell.realPostDecayLoss.byMode.trial), unit: "m" }, { id: "M5.normal.d1", value: round(cell.realPostDecayLoss.byMode.normal), unit: "m" }],
    K15: [{ id: "stressSuppressedWhileTrial", value: trialOnDay, unit: "bool" }],
    K16: [{ id: "channels.sufficient", value: ((published.channels as { sufficient: boolean }[] | undefined) ?? []).filter((row) => row.sufficient).length, unit: "count" }],
    K17: [{ id: "M9.synthMeters.d7", value: (d7.stats.realPostGain as Record<string, ActorGain>).synthetic.total, unit: "m", n: (d7.stats.realPostGain as Record<string, ActorGain>).synthetic.n }, { id: "M9.ownerMeters.d7", value: (d7.stats.realPostGain as Record<string, ActorGain>).owner.total, unit: "m" }, { id: "simulationOwnerUid", value: switches.simulationOwnerUid ? "set (console note: the daily simulation's owner account)" : "unset", unit: "note" }],
  };
  const countsAsComplete = input.complete && !flags.partial && !flags.backfilled;
  const evalInput: EvalInput = {
    day, knobs, flags, trialOnDay, trialMultiplierOnDay, d30: d30.metrics, W, epochYoungResumesDay, frozen, posts, observed7d,
    sourceMatchesObserved: (published.sourceMatchesObserved as boolean | null) ?? null, checks: { drift, farmBound: farm },
    channelsSufficient: ((published.channels as { sufficient: boolean }[] | undefined) ?? []).some((row) => row.sufficient),
    loop: input.amendment ? input.amendment.loop : input.loop, openProduction: adoptedProduction, medianTesterPeak, extraEvidence,
    previousVerdicts: input.amendment ? null : input.last?.verdicts ?? null, frozenOutcomes: input.amendment ? input.amendment.outcomes : null, countsAsComplete,
  };
  const result = evaluateKnobs(evalInput);

  // Checks (§1.5).
  const surfaceEntries = gaps?.find((gap) => gap.id === "surface")?.labelledEntries ?? 0;
  const aboveFloor = claims ? claims.d30.count - claims.d30.atFloor : 0;
  const claimDirection = !!claims && aboveFloor >= RULES.gates.minPosts && claims.d30.aboveFloorThatEarned / aboveFloor < 0.25;
  const staleShare = ratio(posts.stale, posts.liveTesterClean468);
  const checks = [
    { id: "drift", status: drift.status, basis: "seen in production by ALL actor classes incl. simulation · 7 d ending D", rows: drift.rows, verify: drift.verify, awaitingDeploy: drift.awaitingDeploy },
    { id: "farmBound", status: farm.status, detail: farm.detail, ceilingMeters: farmCeiling, lifetimeRealActors: payload.realActorUids.length, violations: farmViolations },
    { id: "claimCeiling", status: "finding", asOfCommit: "ab6489ba", text: "three definitions: firestore.rules sums the full radius incl. seeds since ab6489ba; the picker sums organic; accountRadius adds 5 km — a human retires this finding when the rules file moves",
      claimsD30: claims?.d30 ?? null, direction: claimDirection ? "most above-floor claims never earned reach" : null },
    { id: "anchors", status: trialOnDay ? "watch" : anchorsAtWorld === anchorsEver ? "clear" : "watch", atWorld: anchorsAtWorld, everAtWorld: anchorsEver, worst: headlinePub.worstAnchor ?? null },
    { id: "surface", status: surfaceEntries > 0 ? "measured" : "unmeasured", labelledEntries: surfaceEntries, note: surfaceEntries > 0 ? null : "no per-surface figure is claimed" },
    { id: "seedReach", status: trialOnDay ? "hidden" : !seedRest ? "unavailable" : "finding", basis: "proxy: last post location", atClaimShare: extraEvidence.K9![0].value, livePosts: seedRest?.livePosts ?? null,
      pairs: intercept?.opportunity.pairs ?? null, nearMissPairs: intercept?.opportunity.nearMissPairs ?? null, cleanPosts: seedRest?.cleanPosts ?? null, note: flags.backfilled ? "insufficient/backfilled — no snapshot as of this day" : null },
  ];

  // First line and headline (§1.3): the switch is never the evidence.
  const lossTrial = cell.realPostDecayLoss.byMode.trial;
  const trialShareD30 = d30.metrics.trialShare.value;
  const lastTrialDay = [...d30Days].reverse().find((d) => trialSeenOnDay(payload.days[d]) != null) ?? null;
  let firstLine: string;
  if (trialOnDay) {
    const since = trial?.effectiveAtMillis != null ? utcStamp(trial.effectiveAtMillis) : "an unknown time (switch off at the writing run; the day's cells saw it)";
    const boost = trial?.boostedEffectiveAtMillis != null ? ` (boost path since ${utcStamp(trial.boostedEffectiveAtMillis)})` : "";
    const seen = lossTrial > 0 ? `Seen on ${day}: ×${seenOnDay ?? "?"} on ${fmt(round(lossTrial))} m of real-post loss.` : `Seen on ${day}: none — no decay entry on a real post folded that day.`;
    firstLine = `DECAY TRIAL ×${trialMultiplierOnDay ?? "?"} ON since ${since}${boost} — every seed and every official anchor is decaying; the 5 km floor decision is not in force. ${seen} Anchors ${anchorsAtWorld}/${anchorsEver} at world.`;
  } else {
    firstLine = `Decay ×1 · no trial · ${lastTrialDay ? `last trial multiplier seen on ${lastTrialDay}` : "no trial multiplier seen in 30 d"} (switch off at the writing run; no multiplier seen on ${day})`;
    if ((trialShareD30 ?? 0) >= RULES.gates.trialShareMax) firstLine += ` — 30-day window still mixed with trial loss (${fmt((trialShareD30 ?? 0) * 100, 1)} %); decay verdicts wait`;
  }
  const readsOnDay = input.readsOnDay;
  const headline = {
    trialOnDay, trialMultiplierOnDay, switchAtRun: { enabled: trial?.enabled === true, multiplier: trial?.multiplier ?? null }, trialSinceMillis: trial?.effectiveAtMillis ?? null,
    boostedSinceMillis: trial?.boostedEffectiveAtMillis ?? null, trialSeenOnDay: seenOnDay, trialClassOnDay: dayTrialClass, trialShareD30, anchorsAtWorld, anchorsEver, worstAnchor: headlinePub.worstAnchor ?? null,
    coverage: { complete: input.complete, postsBehindHorizon: (coveragePub.postsBehindHorizon as number) ?? 0, evicted: (coveragePub.evicted as number) ?? 0, entriesFoldedOnDay: cell.entries.real + cell.entries.official,
      registeredPosts: coveragePub.registeredPosts ?? null, nonLivePollLagRuns: input.nonLivePollLagRuns, kindSplitSinceMillis: since, trimmed: false },
    cost: { readsOnDay, runsOnDay: input.runsOnDay, cadOnDay: readsOnDay == null ? null : round(readsOnDay / 100_000 * CAD_PER_100K_READS, 6), monthlyCadProjected: ((published.cost as Record<string, unknown> | undefined)?.monthlyCadProjected as number) ?? null },
  };

  // Policy stamp (§1.6).
  const knobsHash = sha8(knobs);
  const sourceVersion = sourcePolicyVersion(knobs);
  const knobChangedDays: Record<string, string | null> = {};
  for (const key of Object.keys(knobs)) knobChangedDays[key] = input.loop.knobChanges[key as keyof Knobs]?.day ?? null;
  const observedPolicyPub = (published.observedPolicy ?? null) as Record<string, unknown> | null;
  const windowsPub = (published.windows ?? {}) as Record<string, { observedPolicySpanned?: string[] }>;
  const daySig = strip.signatures[day] ?? observedSignature(observedSlice(payload, [day]));
  const policy = {
    reportSchemaVersion: REPORT_SCHEMA_VERSION, digestSchema: DIGEST_SCHEMA_VERSION, ruleSetVersion: rules, digestVersion: input.digestVersion, runId: input.runId,
    source: { knobs, knobsHash, sourcePolicyVersion: sourceVersion, sourceSignature: declaredSignature(knobs), policySha256: input.stamp.policySha256, identitySha256: input.stamp.identitySha256,
      syncedAtMillis: input.stamp.syncedAtMillis, knobsStale: dayEnd - input.stamp.syncedAtMillis > 14 * DAY_MS, knobChangedDays, lastSyncDay: dayKey(input.stamp.syncedAtMillis, timeZone), lastSyncNote: "last sync (every deploy) — gates nothing" },
    production: { observedPolicy: observedPolicyPub, dayObservedPolicy: { version: cell.observedPolicy ?? inheritedPolicy(payload, day), earned: payload.days[day]?.observedPolicy != null },
      dayObservedSignature: { ...observedSignature(observedSlice(payload, [day])), n: observedOnDay.sampleEntries }, rolling7dSignature: daySig,
      observedPolicySpanned: { d7: windowsPub.d7?.observedPolicySpanned ?? [], d30: windowsPub.d30?.observedPolicySpanned ?? [], after: after ? (after.stats.observedPolicySpanned as string[]) : null, note: "digest, hash-based — a null flicker inflates it; Gpolicy reads the report's own epochs" },
      sourceMatchesObserved: (published.sourceMatchesObserved as boolean | null) ?? null },
    decay: { switch: switches.decayTrial, dueDecayEnabled: switches.dueDecayEnabled, seenOnDay: { trialMultiplierSeen: seenOnDay, byMode: cell.realPostDecayLoss.byMode, trialClass: dayTrialClass },
      declaredRatePerDay: knobs.decayPerDay, observedRatePerDay: null, observedRateNote: "unobservable from state; a K7 change shows as knobsHash/knobChangedDays only" },
    simulation: { simulationEnabled: switches.simulationEnabled, runnerEnabled: switches.runnerEnabled, dailySimulationEnabled: switches.dailySimulationEnabled, simulationOwnerUid: switches.simulationOwnerUid ? "set" : "unset" },
    productionEpoch,
  };

  // Metrics (§1.7): the compare key space.
  const gKinds = (W ?? d30.metrics).accrued && posts.kindMixUnknown / Math.max(1, posts.testerWithReal) <= RULES.gates.kindMixUnknownMax;
  const metricRows: MetricRow[] = [...windowMetricRows(d30.metrics, day, posts, gKinds)];
  if (after) metricRows.push(...windowMetricRows(after.metrics, day, posts, gKinds));
  const fixed = (id: string, value: number | null, unit: string, extra: Partial<MetricRow> = {}): MetricRow =>
    ({ id, value, unit, n: null, gate: null, window: "lifetime", population: "real", basis: "", numerator: null, denominator: null, ...extra });
  const d7Gain = d7.stats.realPostGain as Record<string, ActorGain>;
  const synthAll = Object.values(d7Gain).reduce((total, gainRow) => total + gainRow.total, 0);
  const gatesD30 = computeGates(d30.metrics, day);
  const gf: ReportGate = { id: "Gf", label: "Gf · live tester posts · seed vs organic · hidden while the trial runs", n: posts.liveTester, minN: GATES.minPosts, sufficient: posts.liveTester >= GATES.minPosts && !trialOnDay, basis: "seedRest" };
  const interceptGate: ReportGate = { ...gatesD30.Gc, id: "Gc∧Gf", sufficient: gatesD30.Gc.sufficient && gf.sufficient };
  metricRows.push(
    fixed("M3.actors", payload.realActorUids.length, "count", { basis: "lifetime real actors (≤ 500) — printed as lifetime, gates nothing" }),
    fixed("M9.synthShare.d7", synthAll > 0 ? round(d7Gain.synthetic.total / synthAll, 4) : null, "ratio", { window: "d7", population: "sim", numerator: d7Gain.synthetic.total, denominator: synthAll }),
    fixed("M9.synthMeters.d7", d7Gain.synthetic.total, "m", { window: "d7", population: "sim", n: d7Gain.synthetic.n }), fixed("M9.synthEntries.d7", d7Gain.synthetic.n, "count", { window: "d7", population: "sim" }),
    fixed("M1.gain.d7", d7Gain.real.total, "m", { window: "d7", n: d7Gain.real.n }), fixed("M1.gain.d1", (d1.stats.realPostGain as Record<string, ActorGain>).real.total, "m", { window: "d1", n: (d1.stats.realPostGain as Record<string, ActorGain>).real.n }),
    fixed("M4.pairs", intercept?.opportunity.pairs ?? null, "count", { window: "snapshot" }), fixed("M4.realAccounts", intercept?.opportunity.realAccountsWithLocation ?? null, "count", { window: "snapshot" }),
    fixed("M4.realized", intercept?.realized.entries ?? null, "count", { window: "snapshot" }), fixed("M4.nearMissPairs", intercept?.opportunity.nearMissPairs ?? null, "count", { window: "snapshot", basis: "clean posts · within 2 × reach" }),
    fixed("M4.interceptRate", intercept && interceptGate.sufficient && intercept.opportunity.pairs > 0 ? round(intercept.realized.entries / intercept.opportunity.pairs, 4) : null, "ratio", { window: "snapshot", gate: interceptGate, numerator: intercept?.realized.entries ?? 0, denominator: intercept?.opportunity.pairs ?? 0 }),
    fixed("M8.atClaimShare", extraEvidence.K9![0].value as number | null, "ratio", { window: "snapshot", gate: gf, numerator: seedRest?.atClaim ?? 0, denominator: seedRest?.livePosts ?? 0 }),
    fixed("M8.livePosts", seedRest?.livePosts ?? null, "count", { window: "snapshot" }), fixed("M8.cleanPosts", seedRest?.cleanPosts ?? null, "count", { window: "snapshot" }),
    fixed("M11.count", claims?.d30.count ?? null, "count", { window: "snapshot", population: "tester" }), fixed("M11.atFloor", claims?.d30.atFloor ?? null, "count", { window: "snapshot", population: "tester" }),
    fixed("M11.median", claims?.d30.medianMeters ?? null, "m", { window: "snapshot", population: "tester" }), fixed("M11.aboveFloorThatEarned", claims?.d30.aboveFloorThatEarned ?? null, "count", { window: "snapshot", population: "tester" }),
    fixed("M13.atWorld", anchorsAtWorld, "count", { window: "snapshot", population: "official" }), fixed("M13.everAtWorld", anchorsEver, "count", { window: "snapshot", population: "official" }),
  );
  for (const kind of ["view", "like", "comment", "dislike", "repeat"] as GrantKind[]) {
    const slot = observed7d.grants[kind];
    metricRows.push(fixed(`M16.${kind}.seen`, kind === "repeat" ? maxKey(slot.byMeters) : slot.modeMeters, "m", { window: "d7", population: "all", basis: "production · ALL actor classes incl. simulation · 7 d", n: slot.n }),
      fixed(`M16.${kind}.n`, slot.n, "count", { window: "d7", population: "all" }));
  }
  metricRows.push(
    fixed("M17.readsOnDay", readsOnDay, "count", { window: "d1", population: "cost" }), fixed("M17.cadOnDay", headline.cost.cadOnDay, "cad", { window: "d1", population: "cost" }),
    fixed("M17.monthlyCad", headline.cost.monthlyCadProjected, "cad", { window: "snapshot", population: "cost" }),
    fixed("M18.complete", input.complete ? 1 : 0, "bool", { window: "snapshot", population: "coverage" }), fixed("M18.postsBehindHorizon", headline.coverage.postsBehindHorizon, "count", { window: "snapshot", population: "coverage" }),
    fixed("posts.testerWithReal", posts.testerWithReal, "count", { basis: "lifetime (firstRealAt != null) — printed beside Gd as lifetime" }), fixed("posts.liveTester", posts.liveTester, "count"),
    fixed("posts.liveTester7d", posts.liveTester7d, "count"), fixed("posts.liveTesterClean468", posts.liveTesterClean468, "count", { basis: "live tester posts · never pumped · REAL pool ≥ 468 m" }),
    fixed("stale.count", posts.stale, "count", { basis: "of liveTesterClean468, lastRealAt older than 30 d" }),
    fixed("stale.share", posts.liveTesterClean468 >= RULES.gates.minCleanPostsForStale ? staleShare.value : null, "ratio", { gate: { id: "Gstale", label: `≥ ${RULES.gates.minCleanPostsForStale} clean live tester posts`, n: posts.liveTesterClean468, minN: RULES.gates.minCleanPostsForStale, sufficient: posts.liveTesterClean468 >= RULES.gates.minCleanPostsForStale, basis: "K7-R's own floor" }, numerator: posts.stale, denominator: posts.liveTesterClean468 }),
    fixed("posts.viewsOnly", posts.viewsOnly, "count", { basis: "kind-split-known tester posts" }), fixed("posts.liked", posts.liked, "count", { basis: "kind-split-known tester posts" }),
    fixed("posts.commented", posts.commented, "count", { basis: "kind-split-known tester posts" }), fixed("posts.kindMixUnknown", posts.kindMixUnknown, "count", { basis: "tester posts folded before kindSplitSinceMillis" }),
  );
  const metrics: Record<string, MetricRow> = {};
  for (const row of metricRows) metrics[row.id] = row;

  // Previous (§1.7): from the memo of what was actually written — never a re-render of D−1.
  const last = input.last;
  const memoUsable = !!last && !input.amendment && last.digestResetAtMillis === input.lastResetAtMillis;
  let previous: Record<string, unknown> | null = null;
  if (input.amendment) previous = null;
  else if (memoUsable && last) {
    const changed: Record<string, unknown>[] = [];
    for (const id of Object.keys(metrics)) {
      if (!(id in last.metrics)) continue;
      if (SNAPSHOT_METRIC_PREFIXES.some((prefix) => id.startsWith(prefix)) && flags.backfilled) continue;
      const from = last.metrics[id], to = metrics[id].value;
      const gateFrom = last.gated[id], gateTo = metrics[id].gate?.sufficient;
      const gateFlip = gateFrom != null && gateTo != null && gateFrom !== gateTo ? (gateTo ? "gained" : "lost") : null;
      if (from === to && !gateFlip) continue;
      changed.push({ id, from, to, delta: from != null && to != null ? round(to - from, 4) : null, gateFlip });
    }
    const verdictChanges: Record<string, unknown>[] = [];
    for (const row of result.verdicts) {
      const was = last.verdicts[row.knob];
      const now = { verdict: row.verdict, reason: row.reason, to: row.suggestion?.to ?? row.deferred?.to ?? null };
      if (was && (was.verdict !== now.verdict || was.reason !== now.reason || was.to !== now.to)) verdictChanges.push({ knob: row.knob, from: was, to: now });
    }
    previous = { day: last.day, runId: last.runId, revision: last.revision, productionEpoch: last.productionEpoch, sameEpoch: last.productionEpoch === productionEpoch,
      gap: last.day !== dayPlus(day, -1), changed, verdictChanges };
  }

  // Evidence (§1.7).
  const dayRows: Record<string, unknown>[] = [];
  let inherited: string | null = null;
  const publishedSet = new Set(d30Days);
  for (const d of [...new Set([...Object.keys(payload.days), ...d30Days])].sort()) {
    if (d > day) break;
    const cellOf = payload.days[d];
    if (publishedSet.has(d)) dayRows.push({ ...publishedDay(cellOf ?? emptyDayCell(d), inherited), productionEpoch: strip.byDay[d] ?? null, trialClass: trialClass(cellOf) });
    if (cellOf?.observedPolicy) inherited = cellOf.observedPolicy;
  }
  const publishedPosts = ((published.posts as Record<string, unknown>[] | undefined) ?? []).slice(0, input.config.postLimit);
  const postRows = publishedPosts.map((row) => {
    const postId = row.postId as string;
    const fold = payload.folds[postId];
    const meta = payload.postMeta[postId];
    const dayGain = fold?.days[day] ?? null;
    const realGainD30 = fold ? d30Days.reduce((total, d) => total + (fold.days[d]?.gr ?? 0), 0) : 0;
    const ageDays = meta ? (dayEnd - meta.createdAtMillis) / DAY_MS : null;
    return { ...row, dayGain, realGainD30, rk: fold?.rk ?? null, lastRealAtMillis: fold?.lastRealAt ?? null,
      ageBucketAtD: ageDays == null ? null : ageDays < 7 ? "lt7d" : ageDays <= 30 ? "d7to30" : "gt30d" };
  });
  const channelRows = ((published.channels as Record<string, unknown>[] | undefined) ?? []).map((row) => {
    const channelId = row.channelId as string;
    let dayGainMeters = 0, d30GainMeters = 0;
    for (const [postId, meta] of Object.entries(payload.postMeta)) {
      if (!isTester(meta) || (meta.ch || "other") !== channelId) continue;
      const fold = payload.folds[postId];
      if (!fold) continue;
      dayGainMeters += fold.days[day]?.gr ?? 0;
      for (const d of d30Days) d30GainMeters += fold.days[d]?.gr ?? 0;
    }
    return { ...row, dayGainMeters: round(dayGainMeters), d30GainMeters: round(d30GainMeters) };
  });
  const windows: Record<string, unknown> = { d1: d1.stats, d7: d7.stats, d30: d30.stats };
  if (before) windows.before = before.stats;
  if (after) windows.after = after.stats;
  const evidence: Record<string, unknown> = {
    day: { ...publishedDay(cell, inheritedPolicy(payload, day)), trialMultipliers: cell.realPostDecayLoss.trialMultipliers, trialClass: dayTrialClass, earnedPolicy: payload.days[day]?.observedPolicy != null, productionEpoch },
    windows, days: dayRows, observedOnDay, observed7d, posts: postRows, channels: channelRows, snapshots, metrics,
  };
  const { evidence: guarded, trimmed } = guardReport(evidence);
  headline.coverage.trimmed = trimmed;

  const csvColumns = {
    verdicts: VERDICTS_CSV_COLUMNS, metrics: METRICS_CSV_COLUMNS, days: daysCsvColumns(dayRows, windows), posts: POSTS_CSV_COLUMNS,
    identityPrefix: CSV_IDENTITY_PREFIX,
  };
  const evidenceJson = JSON.stringify(guarded);
  const document: Record<string, unknown> = {
    version: REPORT_SCHEMA_VERSION, digestSchema: DIGEST_SCHEMA_VERSION, day, timeZone, dayStartMillis: dayStart, dayEndMillis: dayEnd,
    generatedAtMillis: runStartMillis, runId: input.runId, digestVersion: input.digestVersion, revision: input.revision, supersedes: input.supersedes,
    partial: flags.partial, backfilled: flags.backfilled, catchUp: flags.catchUp, snapshotsAsOfMillis: flags.backfilled ? null : runStartMillis,
    productionEpoch, sourcePolicyVersion: sourceVersion, knobsHash, ruleSetVersion: rules, trialOnDay, trialMultiplierOnDay,
    primarySuggestion: result.primarySuggestion, verdictCounts: result.counts, bytes: 0, firstLine, headline, decision: result.decision, policy,
    verdicts: result.verdicts, checks, previous, previousUnavailable: input.amendment ? "amendment" : previous ? null : last ? "reset" : "first-report",
    epochs, csvColumns, evidence: evidenceJson,
  };
  document.bytes = JSON.stringify(document).length;
  const memoMetrics: Record<string, number | null> = {}; const gated: Record<string, boolean> = {};
  for (const row of metricRows) { memoMetrics[row.id] = row.value; if (row.gate) gated[row.id] = row.gate.sufficient; }
  const memoVerdicts: ReportMemo["verdicts"] = {};
  for (const row of result.verdicts) memoVerdicts[row.knob] = { verdict: row.verdict, reason: row.reason, to: row.suggestion?.to ?? row.deferred?.to ?? null };
  const memo: ReportMemo = { day, runId: input.runId, revision: input.revision, productionEpoch, digestResetAtMillis: input.lastResetAtMillis, metrics: memoMetrics, gated, verdicts: memoVerdicts };
  const outcomes: DayStamp["outcomes"] = {};
  for (const row of result.verdicts) if (row.outcome || row.withdrawnDay) outcomes[row.knob] = { outcome: row.outcome, outcomeNote: row.outcomeNote, openSinceDay: row.openSinceDay, withdrawnDay: row.withdrawnDay };
  const stamp: DayStamp = { knobs, knobsHash, sourcePolicyVersion: sourceVersion, ruleSetVersion: rules, productionEpoch, dayHash: dayHashOf(cell),
    runId: input.runId, generatedAtMillis: runStartMillis, entriesOnDay: cell.entries.real + cell.entries.official, loop: input.amendment ? input.amendment.loop : input.loop, outcomes,
    flags: { ...flags } };
  const indexRow: IndexRow = { day, generatedAtMillis: runStartMillis, digestVersion: input.digestVersion, revision: input.revision, partial: flags.partial, backfilled: flags.backfilled,
    catchUp: flags.catchUp, trialOn: trialOnDay, trialMultiplier: trialMultiplierOnDay, decision: result.decision.kind, knob: result.decision.knob,
    to: result.decision.action?.to ?? null, counts: result.counts, productionEpoch, sourcePolicyVersion: sourceVersion, bytes: document.bytes as number };
  return { document, indexRow, stamp, loop: input.amendment ? input.loop : result.loop, memo, trimmed };
}
function inheritedPolicy(payload: Payload, day: string): string | null {
  let inherited: string | null = null;
  for (const d of Object.keys(payload.days).sort()) { if (d > day) break; if (payload.days[d].observedPolicy) inherited = payload.days[d].observedPolicy; }
  return inherited;
}
/** The published contamination block with `d7.simulationOwnerUid` reduced to set/unset (the identity discipline of decision 8). */
export function maskContamination(contamination: unknown): Record<string, unknown> | null {
  if (!isRecord(contamination)) return null;
  const d7 = contamination.d7;
  if (!isRecord(d7) || !("simulationOwnerUid" in d7)) return { ...contamination };
  return { ...contamination, d7: { ...d7, simulationOwnerUid: typeof d7.simulationOwnerUid === "string" && d7.simulationOwnerUid ? "set" : "unset" } };
}
export function dayHashOf(cell: DayCell): string { return sha8(canonicalJson(publishedDay(cell, null))); }

// ── CSV schema (the generator owns it, §4.2) ────────────────────────────────

export const CSV_IDENTITY_PREFIX = Object.freeze(["reportDay", "reportRunId", "reportRevision", "reportSchemaVersion", "productionEpoch", "sourcePolicyVersion", "knobsHash", "ruleSetVersion",
  "trialOnDay", "trialMultiplierOnDay", "trialSeenOnDay", "sourceMatchesObserved", "partial", "backfilled", "catchUp", "coverageComplete", "appliedByReport", "productionPaysKnob", "productionPaysValue", "firstLine"]);
export const VERDICTS_CSV_COLUMNS = Object.freeze(["knob", "name", "tunable", "declaredValue", "unit", "seenValue", "seenN", "seenBasis", "productionPays", "verdict", "reason", "reasonText", "ruleId", "direction",
  "from", "to", "step", "arithmetic", "gateIds", "gateN", "gateMinN", "gateSufficient", "evidenceIds", "respects", "where", "deploy", "previousVerdict", "previousTo", "outcome", "openSinceDay", "withdrawnDay", "frozenUntilDay"]);
export const METRICS_CSV_COLUMNS = Object.freeze(["id", "window", "population", "unit", "value", "n", "numerator", "denominator", "gate.n", "gate.minN", "gate.sufficient", "gate.basis", "previous.from", "previous.delta", "previous.gateFlip"]);
export const POSTS_CSV_COLUMNS = Object.freeze(["postId", "cls", "ownerClass", "channelId", "createdAtMillis", "seedMeters", "currentMeters", "organicMeters", "boostMeters", "peakMeters", "peakAtMillis", "entries",
  "realGain", "ownerGain", "reviewGain", "syntheticGain", "unknownGain", "decayLoss", "decayLossRealShare", "decayModeSeen", "clean", "viewCount", "firstRealEngagementAtMillis", "lastAtMillis", "lastCause",
  "atClaim", "expired", "deletedAtMillis", "day", "gr", "go", "gv", "gs", "gu", "dl", "dlr", "vc", "realGainD30", "rkView", "rkLike", "rkComment", "rkDislike", "lastRealAtMillis", "ageBucketAtD"]);
const WINDOW_ONLY_COLUMNS = ["netReal.", "netOwner.", "viewWorth.", "spanned", "observedPolicySpanned", "days"];
/** Flattened dotted paths of the day rows (uid map already stripped — pinned by test 20) plus the window-only columns. */
export function daysCsvColumns(dayRows: Record<string, unknown>[], windows: Record<string, unknown>): string[] {
  const columns = new Set<string>(["row"]);
  const walk = (value: unknown, prefix: string) => {
    if (isRecord(value)) { for (const [key, child] of Object.entries(value)) walk(child, prefix ? `${prefix}.${key}` : key); }
    else columns.add(prefix);
  };
  for (const row of dayRows) walk(row, "");
  for (const win of Object.values(windows)) walk(win, "");
  return [...columns].filter((column) => !column.startsWith("realActorEntries")).sort((a, b) => {
    const wa = WINDOW_ONLY_COLUMNS.some((p) => a.startsWith(p)) ? 1 : 0, wb = WINDOW_ONLY_COLUMNS.some((p) => b.startsWith(p)) ? 1 : 0;
    return wa - wb || a.localeCompare(b);
  });
}

// ── Guard (§1.7): the digest's order plus one step ──────────────────────────

export function guardReport(evidence: Record<string, unknown>, limit = PUBLISHED_GUARD_BYTES): { evidence: Record<string, unknown>; trimmed: boolean } {
  const size = () => JSON.stringify(evidence).length;
  if (size() <= limit) return { evidence, trimmed: false };
  const posts = evidence.posts as unknown[];
  evidence.posts = posts.slice(0, Math.ceil(posts.length / 2));
  if (size() <= limit) return { evidence, trimmed: true };
  const days = evidence.days as unknown[];
  evidence.days = days.slice(Math.max(0, days.length - 14));
  if (size() <= limit) return { evidence, trimmed: true };
  const snapshots = evidence.snapshots as { contamination?: { d7?: { posts?: unknown[] } } } | null;
  if (snapshots?.contamination?.d7) snapshots.contamination.d7.posts = [];
  if (size() <= limit) return { evidence, trimmed: true };
  evidence.posts = (evidence.posts as Record<string, unknown>[]).map((row) => { const { dayGain: _g, rk: _k, ...rest } = row; return rest; });
  return { evidence, trimmed: true };
}

// ── Index (§1.8): rebuilt wholesale from the bounded state list ─────────────

export function reportIndexRows(rows: IndexRow[], row: IndexRow): IndexRow[] {
  const next = rows.filter((existing) => existing.day !== row.day);
  next.push(row);
  next.sort((a, b) => b.day.localeCompare(a.day));
  return next.slice(0, REPORT_INDEX_ROWS);
}
export function reportIndexDocument(report: ReportState, runId: string, updatedAtMillis: number): Record<string, unknown> {
  return { version: REPORT_SCHEMA_VERSION, lastReportedDay: report.lastReportedDay, updatedAtMillis, runId, days: report.rows.slice(0, REPORT_INDEX_ROWS) };
}

// ── Due test (§2.2) ─────────────────────────────────────────────────────────

export interface DueInput {
  report: ReportState; payload: Payload; config: DigestConfig; runStartMillis: number; timeZone: string;
  runCoverage: RunCoverage; cost: RunCost;
}
export interface DuePlan { days: { day: string; flags: { partial: boolean; backfilled: boolean; catchUp: boolean } }[]; complete: boolean; deferredReason: string | null; closedDay: string }
export function reportsDue(input: DueInput): DuePlan {
  const { report, config, runStartMillis: runStart, timeZone, runCoverage, cost } = input;
  const closedDay = dayKeysEndingAt(runStart, 2, timeZone)[0];
  const today = dayKey(runStart, timeZone);
  const complete = runCoverage.postsBehindHorizon === 0 && !cost.budgetHit && runCoverage.evicted === 0;
  const plan: DuePlan = { days: [], complete, deferredReason: null, closedDay };
  if (report.lastReportedDay != null && report.lastReportedDay >= closedDay) return plan;
  // Fully folded for live posts: every entry of the closed day is ≤ the horizon.
  if (runStart - config.horizonMs < dayStartMillis(today, timeZone)) { plan.deferredReason = "horizon"; return plan; }
  let partial = false;
  if (!complete) {
    if (runStart - dayStartMillis(today, timeZone) < REPORT_PARTIAL_AFTER_MS) { plan.deferredReason = "incomplete"; return plan; }
    partial = true;
  }
  if (report.lastReportedDay == null) {
    const firstDay = Object.keys(input.payload.days).sort()[0] ?? closedDay;
    const window = daysEnding(closedDay, REPORT_BACKFILL_DAYS, timeZone);
    const start = firstDay > window[0] ? firstDay : window[0];
    for (const day of window) if (day >= start && day <= closedDay && plan.days.length < REPORT_CATCHUP_PER_RUN) plan.days.push({ day, flags: { partial, backfilled: true, catchUp: false } });
    if (!plan.days.length) plan.days.push({ day: closedDay, flags: { partial, backfilled: true, catchUp: false } });
    return plan;
  }
  let day = nextDay(report.lastReportedDay, timeZone);
  const catchUp = day < closedDay;
  while (day <= closedDay && plan.days.length < REPORT_CATCHUP_PER_RUN) { plan.days.push({ day, flags: { partial, backfilled: false, catchUp } }); day = nextDay(day, timeZone); }
  return plan;
}

// ── Step 8b: the report step inside runDigestFold (§2.1, §2.3, §2.4, §2.7) ──

export interface ReportStepInput {
  state: DigestState; published: Record<string, unknown>; config: DigestConfig; switches: Switches; runStartMillis: number; runId: string;
  cost: RunCost; runCoverage: RunCoverage; knobs: Knobs; stamp: SyncStamp; timeZone: string;
}
export interface ReportStepOutput {
  reports: { day: string; document: Record<string, unknown>; indexRow: Record<string, unknown>; revision: number }[];
  reportIndex: Record<string, unknown> | null; reportDeferredReason: string | null; amendDeferredReason: string | null; amendSkipped: string[]; reportBytes: number;
  reportStateBefore: ReportState;
}
export function runReportStep(input: ReportStepInput): ReportStepOutput {
  const { state, config, runStartMillis: runStart, timeZone, knobs } = input;
  const report = state.report;
  const today = dayKey(runStart, timeZone);

  // Source knob changes (§2.3): the first day the synced copy of a knob differed from the run before — never syncedAtMillis.
  if (report.lastKnobs) {
    for (const [key, value] of Object.entries(knobs) as [keyof Knobs, number][]) {
      if (report.lastKnobs[key] !== undefined && report.lastKnobs[key] !== value) report.knobChanges[key] = { day: today, from: report.lastKnobs[key], to: value };
    }
  }
  report.lastKnobs = { ...knobs };
  // What a retry-without-reports commits (§2.7): the knob stamping above is bookkeeping, not a report output, so it stays.
  const reportStateBefore = deepClone(report);
  const out: ReportStepOutput = { reports: [], reportIndex: null, reportDeferredReason: null, amendDeferredReason: null, amendSkipped: [], reportBytes: 0, reportStateBefore };

  const plan = reportsDue({ report, payload: state.payload, config, runStartMillis: runStart, timeZone, runCoverage: input.runCoverage, cost: input.cost });
  out.reportDeferredReason = plan.deferredReason;
  const rules = ruleSetVersion();
  const nonLivePollLagRuns = (config.pollExpiredEveryRuns - state.digestVersion % config.pollExpiredEveryRuns) % config.pollExpiredEveryRuns;
  const loopOf = (): ReportLoopState => ({ open: report.open, adopted: report.adopted, withdrawn: report.withdrawn, knobChanges: report.knobChanges });
  const writtenThisRun = new Set<string>();
  const commit = (day: string, render: ReportRender, revision: number): boolean => {
    // Isolation (§2.7): a JSON round-trip drops `undefined`; an oversize document is refused in-process.
    const document = JSON.parse(JSON.stringify(render.document)) as Record<string, unknown>;
    const bytes = JSON.stringify(document).length;
    if (bytes > REPORT_OVERSIZE_BYTES || (document.evidence as string).length > REPORT_FIELD_LIMIT_BYTES) { out.reportDeferredReason = "oversize"; return false; }
    out.reports.push({ day, document, indexRow: render.indexRow as unknown as Record<string, unknown>, revision });
    out.reportBytes += bytes;
    report.rows = reportIndexRows(report.rows, render.indexRow);
    report.revisions[day] = revision;
    report.stamps[day] = render.stamp;
    trimKeyed(report.revisions); trimKeyed(report.stamps);
    writtenThisRun.add(day);
    return true;
  };
  for (const { day, flags } of plan.days) {
    const render = renderReport({
      state, published: input.published, config, switches: input.switches, knobs, stamp: input.stamp, timeZone, day, runStartMillis: runStart, runId: input.runId,
      digestVersion: state.digestVersion, flags, revision: 1, supersedes: null,
      readsOnDay: state.readsPrev?.day === day ? state.readsPrev.reads : null, runsOnDay: state.readsPrev?.day === day ? state.readsPrev.runs : null,
      nonLivePollLagRuns, complete: plan.complete, loop: loopOf(), last: report.last, lastResetAtMillis: state.lastResetAtMillis, amendment: null,
    });
    if (!commit(day, render, 1)) break;
    report.lastReportedDay = day;
    report.last = render.memo;
    report.open = render.loop.open; report.adopted = render.loop.adopted; report.withdrawn = render.loop.withdrawn;
  }

  // Amendments (§2.4): only a complete run; a changed day cell behind a written revision, ≤ 2 per run, oldest first.
  const lastReported = reportStateBefore.lastReportedDay;
  if (lastReported) {
    if (!plan.complete) out.amendDeferredReason = "incomplete";
    else {
      const candidates = Object.keys(report.stamps).filter((day) => day <= lastReported && day >= dayPlus(lastReported, -REPORT_AMEND_LOOKBACK_DAYS) && !writtenThisRun.has(day)).sort();
      let amended = 0;
      for (const day of candidates) {
        if (amended >= REPORT_AMEND_PER_RUN) break;
        const stamp = report.stamps[day];
        const cell = state.payload.days[day] ?? emptyDayCell(day);
        if (dayHashOf(cell) === stamp.dayHash) { out.amendSkipped.push(day); continue; }
        if (stamp.ruleSetVersion !== rules) {
          out.amendDeferredReason = "rules-changed";
          report.rows = report.rows.map((row) => row.day === day ? { ...row, staleData: true } : row);
          continue;
        }
        const revision = (report.revisions[day] ?? 1) + 1;
        // The amendment keeps the revision's own backfilled/catch-up flags: a backfilled day stays snapshot-less and every
        // tunable insufficient/backfilled, a catch-up day keeps its chip and its snapshot-blind K7-R/K9 (decisions 12, 20) —
        // a plain rev-2 rendered days later would otherwise judge K7-R on a snapshot the day never had. Never partial (§2.4).
        const written = amendmentFlags(stamp);
        const render = renderReport({
          state, published: input.published, config, switches: input.switches, knobs: stamp.knobs, stamp: input.stamp, timeZone, day, runStartMillis: runStart, runId: input.runId,
          digestVersion: state.digestVersion, flags: written, revision,
          supersedes: { runId: stamp.runId, generatedAtMillis: stamp.generatedAtMillis, entriesOnDay: stamp.entriesOnDay },
          readsOnDay: state.readsPrev?.day === day ? state.readsPrev.reads : null, runsOnDay: state.readsPrev?.day === day ? state.readsPrev.runs : null,
          nonLivePollLagRuns, complete: true, loop: loopOf(), last: null, lastResetAtMillis: state.lastResetAtMillis, amendment: stamp,
        });
        if (!commit(day, render, revision)) break;
        amended += 1;
      }
    }
  }
  if (out.reports.length) out.reportIndex = reportIndexDocument(report, input.runId, runStart);
  return out;
}
function trimKeyed<T>(record: Record<string, T>): void {
  const keys = Object.keys(record).sort();
  while (keys.length > REPORT_STAMP_DAYS) delete record[keys.shift()!];
}
/** A stamp written before `flags` existed carries none; treat it as a plain day (nothing deployed yet, so none exists). */
export function amendmentFlags(stamp: Pick<DayStamp, "flags">): ReportFlags {
  const flags = isRecord(stamp.flags) ? stamp.flags : null;
  return { partial: false, backfilled: flags?.backfilled === true, catchUp: flags?.catchUp === true };
}

// Re-exported for the tests and the IO half.
export { KNOB_CATALOGUE, RULES, TUNABLE_KNOBS, evaluateKnobs, ruleSetVersion } from "./algorithmReportRules";
export type { EvidenceCell, Verdict } from "./algorithmReportRules";
