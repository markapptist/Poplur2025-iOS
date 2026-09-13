/**
 * Daily algorithm report — the rules (design §2.5).
 *
 * One frozen RULES table holds every threshold, step, range, gate floor and
 * precedence the report judges by; its hash is the report's ruleSetVersion,
 * so a rule edit is as visible in the compare view as a knob edit. Nothing
 * here reads Firestore and nothing here writes a policy document: a verdict
 * is evidence plus, at most, a suggested value the owner may decide on.
 *
 * Design: /Users/matrix/Developer/.codex/algorithm-reports-design.md (§2.5–§2.6).
 */
import type { ActorGain, Gate, Knobs, ModeMeters } from "./algorithmDigestPolicy";
// Used at call time only: this module and algorithmDigestPolicy import each other.
import { curveBlock, repeatLifetime, sha8 } from "./algorithmDigestPolicy";

// ── The law ─────────────────────────────────────────────────────────────────

export const RULES = Object.freeze({
  version: 1,
  judgeWindowDays: 30, freezeDays: 30, epochMinDays: 7, reversalGuardDays: 90,
  withdrawAfterMissedReports: 3, reopenCooldownReports: 7, reopenGateMargin: 1.2,
  gates: {
    minEvents: 30, minPosts: 8, minChannelPosts: 5, minActors: 2, maxActorShare: 0.6, trialShareMax: 0.1,
    kindMixUnknownMax: 0.2, minObserved: 30, minSeedSeen: 8, minAgeBucketPosts: 8, minCleanPostsForStale: 8,
  },
  thresholds: {
    K1: { lowerShareView: 0.8, lowerNetPosYoung: 0.9, lowerLikersPerViewer: 0.1, raiseNetPosOld: 0.5, raiseLossRatio: 1.5 },
    K2: { shareLike: 0.6, concentrationLikers: 3, lowerLikers: 4, lowerNetPosYoung: 0.9, raiseNetPosOld: 0.5, raiseLossRatio: 1.5 },
    K3: { shareComment: 0.7, concentrationCommenters: 2, lowerCommenters: 3, lowerNetPosYoung: 0.9, raiseNetPosOld: 0.5, raiseLossRatio: 1.5 },
    K4: { lowerClampedShare: 0.3 },
    K5: { lowerRepeatShare: 0.3, lowerRepeatDepth: 4, raiseRepeatDepth: 1, raiseViewers: 30 },
    K7: { lowerNetPosOld: 0.5, lowerLossRatio: 1.5, raiseStaleShare: 0.5 },
  },
  steps: { K1: 250, K2: 250, K3: 500, K4: 250, K5: 100, K7: 0.01 },
  ranges: { K1: [500, 2_000], K2: [500, 3_000], K3: [1_000, 4_000], K4: [-3_000, -250], K5: [200, null], K7: [0.02, 0.1] },
  invariants: ["view ≤ like ≤ comment", "|dislike| ≤ like", "repeatLifetime(base) ≤ firstView", "seed fixed 5,000", "ceiling fixed 6,371,000"],
  precedence: ["K7", "K1-K4 by real n in W descending (ties K1 < K2 < K3 < K4)", "K5"],
  insufficientOrder: ["partial", "backfilled", "trial", "epoch-young", "kind-split-unavailable", "gate", "mixed-policy", "source-ahead", "drift"],
  holdOrder: ["changed-recently", "open", "production-unverified", "cool-down", "concentration", "conflicting-evidence", "reversal-guard", "invariant-capped", "in-range"],
  neverSuggest: ["K6", "K8", "K9", "K10", "K11", "K12", "K13", "K14", "K15", "K16", "K17"],
} as const);

export function ruleSetVersion(): string { return sha8(RULES); }

// ── Catalogue ───────────────────────────────────────────────────────────────

export type KnobId = "K1" | "K2" | "K3" | "K4" | "K5" | "K6" | "K7" | "K8" | "K9" | "K10" | "K11" | "K12" | "K13" | "K14" | "K15" | "K16" | "K17";
export type GrantKind = "view" | "like" | "comment" | "dislike" | "repeat";
export type VerdictKind = "insufficient" | "hold" | "suggest" | "verify";
export type InsufficientReason = "gate" | "trial" | "mixed-policy" | "source-ahead" | "drift" | "unmeasured" | "partial" | "backfilled" | "epoch-young" | "kind-split-unavailable";
export type HoldReason = "in-range" | "invariant-capped" | "concentration" | "conflicting-evidence" | "reversal-guard" | "open" | "cool-down"
  | "production-unverified" | "deferred" | "changed-recently" | "owner-fixed" | "paid" | "simulation" | "ui" | "finding" | "experiment-switch" | "rank-only";
export type VerifyReason = "drift" | "farm-bound";
export type Reason = InsufficientReason | HoldReason | VerifyReason;
export type Outcome = "adopted-in-source" | "adopted-in-production" | "changed-differently" | "withdrawn" | "open";
export type Direction = "lower" | "raise";
export const FIXED_REASONS: readonly HoldReason[] = ["owner-fixed", "paid", "ui", "simulation", "rank-only", "finding", "experiment-switch"];

export interface KnobSpec {
  id: KnobId; name: string; tunable: boolean; unit: string | null; knob: keyof Knobs | null; kind: GrantKind | null;
  where: string; deploy: string[]; fixedReason: HoldReason | null; note: string;
}
const GRANT_DEPLOY = ["deploy recordPostEngagement", "node scripts/syncShared.js (functions-digest)", ".codex/deploy-nearby-pops-digest.sh"];
const DECAY_DEPLOY = ["deploy radiusDecay", "node scripts/syncShared.js (functions-digest)", ".codex/deploy-nearby-pops-digest.sh"];
export const KNOB_CATALOGUE: readonly KnobSpec[] = Object.freeze([
  { id: "K1", name: "First-view grant", tunable: true, unit: "m", knob: "firstViewMeters", kind: "view", where: "functions/src/postEngagementPolicy.ts · radiusDelta · first-view literal", deploy: GRANT_DEPLOY, fixedReason: null, note: "" },
  { id: "K2", name: "Like grant", tunable: true, unit: "m", knob: "likeMeters", kind: "like", where: "functions/src/postEngagementPolicy.ts · radiusDelta · like literal", deploy: GRANT_DEPLOY, fixedReason: null, note: "" },
  { id: "K3", name: "Comment grant", tunable: true, unit: "m", knob: "commentMeters", kind: "comment", where: "functions/src/postEngagementPolicy.ts · radiusDelta · comment literal", deploy: GRANT_DEPLOY, fixedReason: null, note: "" },
  { id: "K4", name: "Dislike grant", tunable: true, unit: "m", knob: "dislikeMeters", kind: "dislike", where: "functions/src/postEngagementPolicy.ts · radiusDelta · dislike literal", deploy: GRANT_DEPLOY, fixedReason: null, note: "" },
  { id: "K5", name: "Repeat-view base", tunable: true, unit: "m", knob: "repeatViewBaseMeters", kind: "repeat", where: "functions/src/postEngagementPolicy.ts · REPEAT_VIEW_BASE_METERS", deploy: GRANT_DEPLOY, fixedReason: null, note: "the halving ladder's lifetime is printed beside every value" },
  { id: "K6", name: "Repeat-view interval", tunable: false, unit: "ms", knob: "repeatViewMinMs", kind: null, where: "functions/src/postEngagementPolicy.ts · REPEAT_VIEW_MIN_MS", deploy: GRANT_DEPLOY, fixedReason: null, note: "a refused repeat is NO_GRANT and writes no ledger entry — unmeasurable" },
  { id: "K7", name: "Earned-reach decay", tunable: true, unit: "/day", knob: "decayPerDay", kind: null, where: "functions/src/postEngagementPolicy.ts · RADIUS_DECAY_PER_DAY", deploy: DECAY_DEPLOY, fixedReason: null, note: "no observed decay rate exists in state; a change is visible as knobsHash only" },
  { id: "K8", name: "Dust floor", tunable: false, unit: "m", knob: "decayFloorMeters", kind: null, where: "functions/src/postEngagementPolicy.ts · RADIUS_DECAY_FLOOR_METERS", deploy: DECAY_DEPLOY, fixedReason: "finding", note: "" },
  { id: "K9", name: "Seed floor", tunable: false, unit: "m", knob: "seedMeters", kind: null, where: "six copies · functions/src/accountRadius.ts · poplur-clay-map/src/claimRadius.ts · RN src/services/posts.ts · iOS PostUploadService.swift · Android PostLoginWebActivity.kt · firestore.rules", deploy: [], fixedReason: "owner-fixed", note: "5 km FLOOR, owner-fixed 6 Sep; the seedReach finding rides this row, never a number" },
  { id: "K10", name: "Claim ceiling", tunable: false, unit: null, knob: null, kind: null, where: "three definitions · firestore.rules (Σ full radius incl. seeds since ab6489ba) · poplur-clay-map/src/claimRadius.ts (Σ organic) · functions/src/accountRadius.ts (+5 km)", deploy: [], fixedReason: "finding", note: "" },
  { id: "K11", name: "Slider step", tunable: false, unit: "m", knob: null, kind: null, where: "poplur-clay-map/src/claimRadius.ts · slider step", deploy: [], fixedReason: "ui", note: "not synced into the digest; no value is typed here" },
  { id: "K12", name: "Boost default", tunable: false, unit: "m", knob: "boostDefaultMeters", kind: null, where: "functions/src/index.ts · positiveInt(body.radiusMetersAdded) / positiveInt(body.durationHours)", deploy: [], fixedReason: "paid", note: "a boost replaces, never stacks" },
  { id: "K13", name: "World ceiling", tunable: false, unit: "m", knob: "maxRadiusMeters", kind: null, where: "functions/src/postEngagementPolicy.ts · MAX_POST_RADIUS_METERS", deploy: [], fixedReason: "owner-fixed", note: "owner-fixed 3 Sep" },
  { id: "K14", name: "Decay trial switch", tunable: false, unit: "×", knob: null, kind: null, where: "testControl/radiusDecayTrial (read by functions/src/radiusDecay.ts)", deploy: [], fixedReason: "experiment-switch", note: "owner question — no number is tuned from data" },
  { id: "K15", name: "Synthetic stress half-life", tunable: false, unit: "h", knob: "syntheticStressHalfLifeHours", kind: null, where: "functions/src/syntheticRetentionPolicy.ts · SYNTHETIC_RADIUS_HALF_LIFE_HOURS", deploy: [], fixedReason: "simulation", note: "suppressed while the trial runs (radiusDecay.ts)" },
  { id: "K16", name: "Feed weights", tunable: false, unit: null, knob: null, kind: null, where: "poplur-clay-map/src/feedDiscovery.ts · SIGNAL_WEIGHT / freshness / trendingVelocity / score", deploy: [], fixedReason: "rank-only", note: "owner: rank never delivery" },
  { id: "K17", name: "Simulation shape", tunable: false, unit: null, knob: null, kind: null, where: "functions/src/syntheticDailyPolicy.ts", deploy: [], fixedReason: "simulation", note: "" },
]);
export const TUNABLE_KNOBS: readonly KnobId[] = ["K1", "K2", "K3", "K4", "K5", "K7"];
export const KIND_TO_KNOB: Record<GrantKind, KnobId> = { view: "K1", like: "K2", comment: "K3", dislike: "K4", repeat: "K5" };

// ── What the rules read (computed by algorithmReportPolicy from state) ──────

export interface Ratio { value: number | null; numerator: number; denominator: number }
export interface NetBucketLike { posts: number; netPositive: number; postDays: number; gainRealMeters: number; lossRealShareMeters: number; perPostDay: number | null }
export interface Subset { posts: number; netPositive: number }
export interface PeopleCounts { actors: number; viewers: number; likers: number; commenters: number; maxShare: number | null; events: number }
export interface WindowMetrics {
  name: string; days: string[]; spanned: string[]; accrued: boolean; accrualSinceDay: string | null;
  gain: ActorGain; dayDistinct: { viewers: number; likers: number; commenters: number }; people: PeopleCounts;
  modes: ModeMeters; trialShare: Ratio; realLoss: number; seedLoss: number; boostLoss: number;
  net: Record<"lt7d" | "d7to30" | "gt30d" | "all", NetBucketLike>;
  subsets: { viewsOnly: Subset; liked: Subset; commented: Subset };
  testerWithReal: number;
  dislike: { n: number | null; lowerBound: number; clampedShare: Ratio; exact: boolean; note: string };
  boosts: { n: number; meters: number };
}
export interface PostCounts {
  testerWithReal: number; liveTester: number; liveTester7d: number; liveTesterClean468: number; stale: number;
  viewsOnly: number; liked: number; commented: number; kindMixUnknown: number; expired: number;
}
export interface ObservedGrant { n: number; modeMeters: number | null; min: number | null; max: number | null; byMeters: Record<string, number> }
export interface ObservedBlock {
  grants: Record<GrantKind, ObservedGrant>; seedSeen: ObservedGrant; boostSeen: { meters: ObservedGrant; hours: ObservedGrant };
  sampleEntries: number; clamped: number; resync: number;
}
export interface OpenSuggestion { knob: KnobId; sinceDay: string; from: number; to: number; ruleId: string; direction: Direction; missedReports: number }
export interface ReportLoopState {
  open: OpenSuggestion | null;
  adopted: Partial<Record<KnobId, { day: string; direction: Direction }>>;
  withdrawn: Partial<Record<KnobId, { day: string; ruleId: string; completeReportsSince: number }>>;
  knobChanges: Partial<Record<keyof Knobs, { day: string; from: number; to: number }>>;
}
export interface DriftCheck { status: "clear" | "verify" | "unseen"; verify: string[]; awaitingDeploy: string[]; rows: Record<string, { seen: number | null; declared: number; n: number; status: string }> }
export interface EvidenceCell { id: string; value: number | string | boolean | null; unit?: string; n?: number; numerator?: number; denominator?: number; label?: string }
export interface ReportGate extends Gate { id: string; label: string; note?: string }
export interface Suggestion { from: number; to: number; step: number; direction: Direction; ruleId: string; rationale: string; respects: string[] }
export interface Verdict {
  knob: KnobId; name: string; tunable: boolean; declaredValue: number | null; unit: string | null;
  seenValue: number | null; seenN: number; seenBasis: string; productionPays: number | null; where: string; deploy: string[];
  gates: ReportGate[]; evidence: EvidenceCell[]; verdict: VerdictKind; reason: Reason; reasonText: string;
  rule: { id: string; text: string; inputs: Record<string, number | string | boolean | null> } | null; arithmetic: string | null;
  suggestion: Suggestion | null; deferred: { to: number; ruleId: string } | null;
  curveAtSuggested: Record<string, unknown> | null; curveCurrent: Record<string, unknown> | null; frozenUntilDay: string | null;
  previous: { verdict: VerdictKind; reason: Reason; to: number | null } | null;
  outcome: Outcome | null; outcomeNote: string | null; openSinceDay: string | null; withdrawnDay: string | null;
}
export interface EvalInput {
  day: string; knobs: Knobs; flags: { partial: boolean; backfilled: boolean; catchUp: boolean };
  trialOnDay: boolean; trialMultiplierOnDay: number | null;
  d30: WindowMetrics; W: WindowMetrics | null; epochYoungResumesDay: string | null;
  /** Grant knobs whose signature moved at a boundary inside the freeze window (§1.9) and K7's source freeze (§2.3). */
  frozen: Partial<Record<KnobId, { untilDay: string; cause: string }>>;
  posts: PostCounts; observed7d: ObservedBlock; sourceMatchesObserved: boolean | null;
  checks: { drift: DriftCheck; farmBound: { status: "clear" | "verify"; detail: string } };
  channelsSufficient: boolean; loop: ReportLoopState;
  /** For the open knob: what production paid after the source change (all actor classes). */
  openProduction: { value: number | null; n: number } | null;
  medianTesterPeak: number | null;
  extraEvidence: Partial<Record<KnobId, EvidenceCell[]>>;
  previousVerdicts: Partial<Record<KnobId, { verdict: VerdictKind; reason: Reason; to: number | null }>> | null;
  /** An amendment copies the stored outcome fields instead of running the loop. */
  frozenOutcomes: Partial<Record<KnobId, { outcome: Outcome | null; outcomeNote: string | null; openSinceDay: string | null; withdrawnDay: string | null }>> | null;
  /** Counts toward the withdrawal clock and the cool-down (a complete, non-partial, non-backfilled report). */
  countsAsComplete: boolean;
}
export interface Decision {
  kind: "suggest" | "verify" | "none"; knob: KnobId | null; sentence: string; appliedByReport: false;
  productionPays: { knob: KnobId; value: number | null; n: number; basis: string } | null;
  action: { where: string; from: number; to: number; unit: string | null; deploy: string[] } | null;
  deferred: { knob: KnobId; to: number; ruleId: string }[];
  open: { knob: KnobId; to: number; ruleId: string; openSinceDay: string; outcome: Outcome | null; missedReports: number }[];
  counts: VerdictCounts; ownerQuestion: string | null;
}
export interface VerdictCounts { suggest: number; verify: number; hold: number; insufficient: number; fixed: number }
export interface EvalResult {
  verdicts: Verdict[]; decision: Decision; primarySuggestion: KnobId | null; counts: VerdictCounts;
  /** The outcome loop's next state (unchanged on an amendment). */
  loop: ReportLoopState; k7hold: boolean;
}

// ── Helpers ─────────────────────────────────────────────────────────────────

const fmt = (value: number | null | undefined, places = 0): string => value == null || !Number.isFinite(value) ? "—"
  : value.toLocaleString("en-CA", { minimumFractionDigits: places, maximumFractionDigits: places });
const ratioText = (ratio: Ratio, places = 2): string => `${fmt(ratio.numerator)} / ${fmt(ratio.denominator)} = ${ratio.value == null ? "—" : fmt(ratio.value, places)}`;
const ratio = (numerator: number, denominator: number): Ratio => ({ value: denominator > 0 ? Math.round(numerator / denominator * 10_000) / 10_000 : null, numerator, denominator });
const dayPlus = (day: string, days: number): string => {
  const [y, m, d] = day.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + days, 12)).toISOString().slice(0, 10);
};
const clampDecimals = (value: number, places: number): number => Math.round(value * 10 ** places) / 10 ** places;

function catalogue(id: KnobId): KnobSpec { return KNOB_CATALOGUE.find((spec) => spec.id === id)!; }

/** Gate shape P:1195 with the label the row prints. `basis` names the window. */
function gate(id: string, label: string, n: number, minN: number, sufficient: boolean, basis: string, note?: string): ReportGate {
  return { id, label, n, minN, sufficient, basis, ...(note ? { note } : {}) };
}
function windowLabel(W: WindowMetrics, day: string): string {
  return `${W.days.length} d ending ${day}${W.name === "after" ? ` (after ${W.days[0]})` : ""}`;
}

/** The counted gates of §2.5, at the plain floors or at the re-open margin. */
export function computeGates(W: WindowMetrics, day: string, margin = 1): { Gc: ReportGate; Gd: ReportGate; Gdislike: ReportGate; Gage: ReportGate } {
  const g = RULES.gates;
  const minEvents = Math.ceil(g.minEvents * margin), minPosts = Math.ceil(g.minPosts * margin), minActors = Math.ceil(g.minActors * margin);
  const label = windowLabel(W, day);
  const maxShare = W.people.maxShare;
  const Gc = gate("Gc", `Gc · real events · ${label} · ≥ ${minActors} real actors in the window · no one person > ${Math.round(g.maxActorShare * 100)} %`,
    W.gain.n, minEvents, W.accrued && W.gain.n >= minEvents && W.people.actors >= minActors && maxShare != null && maxShare <= g.maxActorShare,
    `real posts × real actors · engagement entries · organicDelta · ${W.name}`,
    W.accrued ? `actors ${W.people.actors}/${minActors} · max share ${maxShare == null ? "—" : fmt(maxShare, 2)}` : `kind split unavailable for this window${W.accrualSinceDay ? ` (accrues since ${W.accrualSinceDay})` : ""}`);
  const Gd = gate("Gd", `Gd · tester posts with ≥ 1 real engagement · ${label}`, W.testerWithReal, minPosts, W.testerWithReal >= minPosts,
    `tester posts with a real engagement inside the window (gr ≠ 0) · ${W.name}`);
  const dislikeN = W.dislike.n;
  const Gdislike = gate("Gdislike", `Gdislike · real dislikes · ${label} · ≥ ${minActors} real actors`, dislikeN ?? 0, minEvents,
    W.accrued && dislikeN != null && dislikeN >= minEvents && W.people.actors >= minActors, `clamped dislikes + full dislikes from |dislike m| · ${W.name}`,
    dislikeN == null ? `unmeasured — lower bound ${W.dislike.lowerBound} printed as evidence, never as n` : undefined);
  const Gage = gate("Gage", `Gage · tester posts aged 7–30 d at the window end · ${label}`, W.net.d7to30.posts, g.minAgeBucketPosts,
    W.net.d7to30.posts >= g.minAgeBucketPosts, `netReal.byAge.d7to30 · ${W.name}`);
  return { Gc, Gd, Gdislike, Gage };
}

interface RuleFire { fired: boolean; arithmetic: string; inputs: Record<string, number | string | boolean | null>; evaluable: boolean }
const cmp = (label: string, value: number | null, op: "≥" | "<" | "≤" | ">" | "=", threshold: number, places = 2, text?: string): { ok: boolean; text: string } => {
  const ok = value != null && (op === "≥" ? value >= threshold : op === "<" ? value < threshold : op === "≤" ? value <= threshold : op === "=" ? value === threshold : value > threshold);
  return { ok, text: `${label} = ${text ?? fmt(value, places)} ${op} ${fmt(threshold, places)}` };
};
function fire(parts: { ok: boolean; text: string }[], evaluable = true): RuleFire {
  return { fired: evaluable && parts.every((part) => part.ok), arithmetic: parts.map((part) => part.text).join(" ∧ "), inputs: {}, evaluable };
}

// ── The evaluation ──────────────────────────────────────────────────────────

export function evaluateKnobs(input: EvalInput): EvalResult {
  const { knobs, day, W, d30 } = input;
  const flags = input.flags;
  const th = RULES.thresholds;
  const loop: ReportLoopState = JSON.parse(JSON.stringify(input.loop));
  const open = loop.open;
  const trialShareD30 = d30.trialShare.value ?? 0;
  const k7Trial = input.trialOnDay || trialShareD30 >= RULES.gates.trialShareMax;
  const gates = W ? computeGates(W, day) : computeGates(d30, day);
  const evidenceWindow = W ?? d30;

  // Gtrial(W): the window's own real-post decay loss is < 10 % trial/stress/undetermined, or nothing decayed at all.
  const gTrial = (win: WindowMetrics): boolean => win.trialShare.denominator === 0 || (win.trialShare.value ?? 1) < RULES.gates.trialShareMax;
  const gKinds = evidenceWindow.accrued && input.posts.kindMixUnknown / Math.max(1, input.posts.testerWithReal) <= RULES.gates.kindMixUnknownMax;
  const gDrift = input.checks.drift.status !== "verify" && input.checks.farmBound.status === "clear";
  const gPolicySpan = evidenceWindow.spanned.length <= 1;
  const observedFor = (spec: KnobSpec): ObservedGrant | null => spec.kind ? input.observed7d.grants[spec.kind] : null;
  const seenValueOf = (spec: KnobSpec, observed: ObservedGrant | null): number | null =>
    !observed ? null : spec.kind === "repeat" ? maxKeyOf(observed.byMeters) : observed.modeMeters;

  // Derived ratios of the evidence window, gated in the document (§1.7): null below the named gate.
  const gained = (r: Ratio, sufficient: boolean): Ratio => sufficient ? r : { ...r, value: null };
  const total = Math.max(0, evidenceWindow.gain.total);
  const share = (kind: keyof ActorGain): Ratio => gained(ratio(evidenceWindow.gain[kind], total), gates.Gc.sufficient);
  const shareView = share("view"), shareLike = share("like"), shareComment = share("comment"), shareDislike = gained(ratio(Math.abs(evidenceWindow.gain.dislike), total), gates.Gc.sufficient);
  const likersPerViewer = gained(ratio(evidenceWindow.people.likers, evidenceWindow.people.viewers), gates.Gc.sufficient);
  const repeatDepth = gained(ratio(evidenceWindow.gain.repeatViews, evidenceWindow.people.viewers), gates.Gc.sufficient);
  const repeatShare = gained(ratio(evidenceWindow.gain.repeatMeters, total), gates.Gc.sufficient);
  const bucketGate = (bucket: NetBucketLike) => bucket.posts >= RULES.gates.minAgeBucketPosts;
  const netPos = (b: "lt7d" | "d7to30" | "gt30d"): Ratio => { const bucket = evidenceWindow.net[b]; return gained(ratio(bucket.netPositive, bucket.posts), bucketGate(bucket)); };
  const lossRatio = (b: "lt7d" | "d7to30" | "gt30d"): Ratio => { const bucket = evidenceWindow.net[b]; return gained(ratio(bucket.lossRealShareMeters, bucket.gainRealMeters), bucketGate(bucket)); };
  const subsetNetPos = (subset: Subset): Ratio => gained(ratio(subset.netPositive, subset.posts), gKinds && subset.posts >= RULES.gates.minPosts);
  const staleShare = gained(ratio(input.posts.stale, input.posts.liveTesterClean468), input.posts.liveTesterClean468 >= RULES.gates.minCleanPostsForStale);
  const clampedShare = gained(evidenceWindow.dislike.clampedShare, gates.Gdislike.sufficient);

  const commonEvidence = (spec: KnobSpec): EvidenceCell[] => {
    const w = evidenceWindow.name;
    const cells: EvidenceCell[] = [
      { id: `M1.gain.${w}`, value: evidenceWindow.gain.total, unit: "m", n: evidenceWindow.gain.n },
      { id: `M3.actors.${w}`, value: evidenceWindow.accrued ? evidenceWindow.people.actors : null, unit: "count", label: evidenceWindow.accrued ? "distinct real actors in the window" : `since ${evidenceWindow.accrualSinceDay ?? "?"} only (kind split unavailable)` },
      { id: `maxShare.${w}`, value: evidenceWindow.people.maxShare, unit: "ratio", label: evidenceWindow.accrued ? "largest one-person share of real events" : `since ${evidenceWindow.accrualSinceDay ?? "?"} only` },
      { id: `posts.testerWithReal.${w}`, value: evidenceWindow.testerWithReal, unit: "count" },
      { id: `trialShare.${w}`, value: evidenceWindow.trialShare.value, unit: "ratio", numerator: evidenceWindow.trialShare.numerator, denominator: evidenceWindow.trialShare.denominator },
    ];
    if (spec.kind) {
      const kind = spec.kind === "repeat" ? "repeatMeters" : spec.kind;
      cells.push({ id: `M1.${spec.kind}.${w}`, value: evidenceWindow.gain[kind as keyof ActorGain] as number, unit: "m", n: evidenceWindow.gain.n });
    }
    return cells;
  };
  const ratioCell = (id: string, r: Ratio, unit = "ratio"): EvidenceCell => ({ id, value: r.value, unit, numerator: r.numerator, denominator: r.denominator });

  // ── One tunable knob, before R3 ──
  interface Judged { verdict: Verdict; candidate: Suggestion | null; judgeable: boolean; opening: RuleFire | null }
  const judge = (id: KnobId, shadowOpen = false): Judged => {
    const spec = catalogue(id);
    const observed = observedFor(spec);
    const declared = spec.knob ? knobs[spec.knob] : null;
    const seenValue = seenValueOf(spec, observed);
    const seenN = observed?.n ?? 0;
    const prodOk = observed ? seenN >= RULES.gates.minObserved && seenValue === declared : true;
    const verdict: Verdict = {
      knob: id, name: spec.name, tunable: spec.tunable, declaredValue: declared, unit: spec.unit,
      seenValue, seenN, seenBasis: "production · ALL actor classes incl. simulation · 7 d", productionPays: seenN >= RULES.gates.minObserved ? seenValue : null,
      where: spec.where, deploy: spec.deploy, gates: [], evidence: [...commonEvidence(spec), ...(input.extraEvidence[id] ?? [])],
      verdict: "hold", reason: "in-range", reasonText: "", rule: null, arithmetic: null, suggestion: null, deferred: null,
      curveAtSuggested: null, curveCurrent: null, frozenUntilDay: null, previous: input.previousVerdicts?.[id] ?? null,
      outcome: null, outcomeNote: null, openSinceDay: null, withdrawnDay: null,
    };
    const done = (kind: VerdictKind, reason: Reason, text: string): Judged => {
      verdict.verdict = kind; verdict.reason = reason; verdict.reasonText = text;
      return { verdict, candidate: null, judgeable: kind !== "insufficient", opening: null };
    };
    const gateText = (): string => verdict.gates.map((g) => `${g.id} ${g.n}/${g.minN}${g.note ? ` (${g.note})` : ""}`).join(" · ");
    if (id === "K7") {
      verdict.gates = [gates.Gc, gates.Gd, gates.Gage];
      verdict.curveCurrent = curveBlock(60, knobs, input.medianTesterPeak, null);
      verdict.evidence.push(ratioCell("netPos.d7to30", netPos("d7to30")), ratioCell("lossRatio.d7to30", lossRatio("d7to30")),
        { id: "M6.d7to30.perPostDay", value: evidenceWindow.net.d7to30.perPostDay, unit: "m/post-day", n: evidenceWindow.net.d7to30.posts },
        { id: "M6.gt30d.gainRealMeters", value: evidenceWindow.net.gt30d.gainRealMeters, unit: "m", n: evidenceWindow.net.gt30d.posts },
        { id: "posts.liveTesterClean468", value: input.posts.liveTesterClean468, unit: "count" }, ratioCell("stale.share", staleShare),
        { id: "trialShare.d30", value: d30.trialShare.value, unit: "ratio", numerator: d30.trialShare.numerator, denominator: d30.trialShare.denominator });
    } else if (id === "K4") {
      verdict.gates = [gates.Gdislike, gates.Gd];
      verdict.evidence.push({ id: `dislike.n.${evidenceWindow.name}`, value: evidenceWindow.dislike.n, unit: "count", label: evidenceWindow.dislike.note },
        { id: `dislike.lowerBound.${evidenceWindow.name}`, value: evidenceWindow.dislike.lowerBound, unit: "count", label: "|dislike m| / 1,000 — a lower bound, never a gate's n" },
        ratioCell(`dislike.clampedShare.${evidenceWindow.name}`, clampedShare));
    } else {
      verdict.gates = [gates.Gc, gates.Gd];
      if (id === "K1") verdict.evidence.push(ratioCell(`share.view.${evidenceWindow.name}`, shareView), ratioCell(`likersPerViewer.${evidenceWindow.name}`, likersPerViewer), ratioCell("netPos.lt7d", netPos("lt7d")), { id: "posts.viewsOnly", value: input.posts.viewsOnly, unit: "count" }, ratioCell("netPosViewsOnly.d7to30", subsetNetPos(evidenceWindow.subsets.viewsOnly)), ratioCell("lossRatio.d7to30", lossRatio("d7to30")));
      if (id === "K2") verdict.evidence.push(ratioCell(`share.like.${evidenceWindow.name}`, shareLike), { id: `M3.likers.${evidenceWindow.name}`, value: evidenceWindow.accrued ? evidenceWindow.people.likers : null, unit: "count" }, { id: `M3.likersDay.${evidenceWindow.name}`, value: evidenceWindow.dayDistinct.likers, unit: "count", label: "(day-distinct)" }, ratioCell("netPos.lt7d", netPos("lt7d")), { id: "posts.liked", value: input.posts.liked, unit: "count" }, ratioCell("netPosLiked.d7to30", subsetNetPos(evidenceWindow.subsets.liked)), ratioCell("lossRatio.d7to30", lossRatio("d7to30")));
      if (id === "K3") verdict.evidence.push(ratioCell(`share.comment.${evidenceWindow.name}`, shareComment), { id: `M3.commenters.${evidenceWindow.name}`, value: evidenceWindow.accrued ? evidenceWindow.people.commenters : null, unit: "count" }, { id: `M3.commentersDay.${evidenceWindow.name}`, value: evidenceWindow.dayDistinct.commenters, unit: "count", label: "(day-distinct)" }, ratioCell("netPos.lt7d", netPos("lt7d")), { id: "posts.commented", value: input.posts.commented, unit: "count" }, ratioCell("netPosCommented.d7to30", subsetNetPos(evidenceWindow.subsets.commented)), ratioCell("lossRatio.d7to30", lossRatio("d7to30")));
      if (id === "K5") verdict.evidence.push(ratioCell(`repeatShare.${evidenceWindow.name}`, repeatShare), ratioCell(`repeatDepth.${evidenceWindow.name}`, repeatDepth), { id: `M3.viewers.${evidenceWindow.name}`, value: evidenceWindow.accrued ? evidenceWindow.people.viewers : null, unit: "count" }, { id: "repeatLifetime", value: repeatLifetime(knobs.repeatViewBaseMeters), unit: "m", label: "lifetime of the halving ladder at the declared base" });
      if (id === "K1" || id === "K2" || id === "K3") verdict.evidence.push({ id: "posts.kindMixUnknown", value: input.posts.kindMixUnknown, unit: "count", label: gKinds ? "kind split known" : "kind-split-unavailable" });
    }
    if (observed) verdict.gates.push(gate("Gprod", `Gprod · production seen paying the declared ${spec.kind} grant · 7 d · all classes`, seenN, RULES.gates.minObserved, prodOk, "observed7d"));

    // 1. The insufficient ladder (every insufficient reason before any hold; changed-recently is the one freeze that
    //    overrides the window — "whatever W says" — so it sits right after the report-level flags).
    if (flags.partial) return done("insufficient", "partial", "partial report (postsBehindHorizon > 0 at the 6 h deadline) — a partial fold never suggests");
    if (flags.backfilled) return done("insufficient", "backfilled", "backfilled report — day cells are exact but no snapshot was taken as of this day");
    if (id === "K7" && flags.catchUp) return done("insufficient", "backfilled", "catch-up report — K7-R reads snapshots stamped as of the writing run, and the direction guard needs both triggers");
    const frozen = input.frozen[id];
    if (frozen && frozen.untilDay > day) {
      verdict.frozenUntilDay = frozen.untilDay;
      const held = done("hold", "changed-recently", `${frozen.cause} — frozen until ${frozen.untilDay}`);
      held.judgeable = false;
      return held;
    }
    if (id === "K7" && k7Trial) return done("insufficient", "trial", input.trialOnDay
      ? `decay trial ×${input.trialMultiplierOnDay ?? "?"} on ${day} — the decay rate is unobservable while the trial runs`
      : `30-day window still mixed with trial loss (${fmt(trialShareD30 * 100, 1)} % of ${fmt(d30.trialShare.denominator)} m) — decay verdicts wait until it is under ${Math.round(RULES.gates.trialShareMax * 100)} %`);
    // Gtrial(W) holds for EVERY windowed knob, K7 included (refuter 11): netPos/lossRatio read dlr, which trial, stress and
    // unclassified loss inflate, so a verdict window carrying ≥ 10 % of it judges nothing — d30's own share (above) vouches
    // only for d30, never for an `after` window whose loss is concentrated behind a grant boundary.
    if (W && !gTrial(W)) return done("insufficient", "trial", `window ${W.name} carries ${fmt((W.trialShare.value ?? 0) * 100, 1)} % trial/stress/undetermined real-post decay loss — no windowed rule is judged on inflated or unclassified loss (Gtrial)`);
    if (!W) return done("insufficient", "epoch-young", input.epochYoungResumesDay ? `under a new policy epoch for fewer than ${RULES.epochMinDays} days — resumes ${input.epochYoungResumesDay}` : "policy epoch too young");
    if (id === "K4" && W.dislike.n == null) return done("insufficient", "unmeasured", `dislikes cannot be counted exactly while clamps exist in the window (${W.gain.clamped} clamped entries of every kind, no per-kind clamp counter accrued yet) — lower bound ${W.dislike.lowerBound} printed as evidence`);
    if (!W.accrued) return done("insufficient", "kind-split-unavailable", `the window starts before the fold's kind split was introduced${W.accrualSinceDay ? ` (accrues since ${W.accrualSinceDay})` : ""} — people and kind figures print as evidence only`);
    if ((id === "K1" || id === "K2" || id === "K3") && !gKinds) return done("insufficient", "kind-split-unavailable", `${input.posts.kindMixUnknown} of ${input.posts.testerWithReal} tester posts were folded before the kind split — the subset rules cannot be judged`);
    const named = verdict.gates.filter((g) => g.id !== "Gprod");
    if (named.some((g) => !g.sufficient)) {
      const failing = named.filter((g) => !g.sufficient);
      const gc = failing.find((g) => g.id === "Gc" || g.id === "Gdislike");
      const short = gc ? `${gc.n} of ${gc.minN}` : `${failing[0].n} of ${failing[0].minN}`;
      return done("insufficient", "gate", `n = ${short} · ${gateText()}${W.people.events === 0 ? " — no real person has engaged yet" : ""}`);
    }
    if (!gPolicySpan) return done("insufficient", "mixed-policy", `mixed policy — the window spans ${W.spanned.length} production epochs; compare days, not windows`);
    if (input.sourceMatchesObserved === false && !(open?.knob === id && spec.knob && knobs[spec.knob] === open.to)) return done("insufficient", "source-ahead", "the repo is ahead of production — suggestions wait until production pays what the source declares");
    const awaitingDeploy = open?.knob === id && spec.knob != null && knobs[spec.knob] === open.to;
    if (!gDrift && !(awaitingDeploy && spec.kind && input.checks.drift.awaitingDeploy.includes(spec.kind))) return done("insufficient", "drift", input.checks.drift.status === "verify"
      ? `drift: production pays ${input.checks.drift.verify.join(", ")} — verify before any knob moves` : `farm bound violated: ${input.checks.farmBound.detail}`);
    // Production seen paying something else at n ≥ 30 is drift by definition (R6), unless it is this row's own open suggestion awaiting its deploy.
    if (!prodOk && seenN >= RULES.gates.minObserved && !awaitingDeploy) return done("insufficient", "drift", `production pays ${fmt(seenValue)} (n ${seenN}, all classes) ≠ declared ${fmt(declared)} — verify before any knob moves`);
    if (id === "K7" && input.loop.knobChanges.decayPerDay && dayPlus(input.loop.knobChanges.decayPerDay.day, RULES.freezeDays) > day) {
      verdict.frozenUntilDay = dayPlus(input.loop.knobChanges.decayPerDay.day, RULES.freezeDays);
      return done("hold", "changed-recently", `decayPerDay changed in source on ${input.loop.knobChanges.decayPerDay.day} — frozen until ${verdict.frozenUntilDay} (production unverifiable)`);
    }

    // 2. Holds that precede the rules.
    if (open?.knob === id && !shadowOpen) return done("hold", "open", `open suggestion since ${open.sinceDay} — restated, not re-derived: ${id}-${open.direction === "lower" ? "L" : "R"} → ${fmt(open.to, id === "K7" ? 2 : 0)}`);
    if (!prodOk && seenN < RULES.gates.minObserved) return done("hold", "production-unverified", `production has not been seen paying the declared value (n ${seenN} < ${RULES.gates.minObserved} over 7 d, all classes) — the report cannot tell whether the source has shipped`);
    const withdrawn = loop.withdrawn[id];
    if (withdrawn && withdrawn.completeReportsSince < RULES.reopenCooldownReports) {
      verdict.withdrawnDay = withdrawn.day;
      return done("hold", "cool-down", `withdrawn ${withdrawn.day} · re-evaluated after ${RULES.reopenCooldownReports} complete reports (${withdrawn.completeReportsSince} so far)`);
    }

    // 3. The rules of the table, top to bottom.
    const from = declared as number;
    const step = RULES.steps[id as keyof typeof RULES.steps];
    let lower: RuleFire | null = null, raise: RuleFire | null = null, concentration: RuleFire | null = null;
    let lowerTo = from, raiseTo = from; const respects: string[] = []; let capNote = "";
    const k7hold = id !== "K7" && k7holdOf(); // computed below per call order (K7 is judged first)
    if (id === "K1") {
      lower = fire([cmp("share.view", shareView.value, "≥", th.K1.lowerShareView, 2, ratioText(shareView)), cmp("M6.lt7d.posts", W.net.lt7d.posts, "≥", RULES.gates.minAgeBucketPosts, 0),
        cmp("netPos(lt7d)", netPos("lt7d").value, "≥", th.K1.lowerNetPosYoung, 2, ratioText(netPos("lt7d"))), cmp("likersPerViewer", likersPerViewer.value, "<", th.K1.lowerLikersPerViewer, 2, ratioText(likersPerViewer))]);
      lowerTo = Math.max(RULES.ranges.K1[0], from - step);
      const sub = subsetNetPos(W.subsets.viewsOnly);
      raise = fire([cmp("posts.viewsOnly", input.posts.viewsOnly, "≥", RULES.gates.minPosts, 0), cmp("netPosViewsOnly(d7to30)", sub.value, "<", th.K1.raiseNetPosOld, 2, ratioText(sub)),
        cmp("lossRatio(d7to30)", lossRatio("d7to30").value, "≤", th.K1.raiseLossRatio, 2, ratioText(lossRatio("d7to30")))]);
      raiseTo = Math.min(RULES.ranges.K1[1], knobs.likeMeters, from + step);
      if (raiseTo === from) capNote = knobs.likeMeters <= from ? "capped by view ≤ like" : "capped by range";
      respects.push("view ≤ like", `range ${fmt(RULES.ranges.K1[0])}–${fmt(RULES.ranges.K1[1])} m`);
    } else if (id === "K2") {
      concentration = fire([cmp("share.like", shareLike.value, "≥", th.K2.shareLike, 2, ratioText(shareLike)), cmp("M3.likersW", W.people.likers, "≤", th.K2.concentrationLikers, 0)]);
      lower = fire([cmp("share.like", shareLike.value, "≥", th.K2.shareLike, 2, ratioText(shareLike)), cmp("M3.likersW", W.people.likers, "≥", th.K2.lowerLikers, 0),
        cmp("M6.lt7d.posts", W.net.lt7d.posts, "≥", RULES.gates.minAgeBucketPosts, 0), cmp("netPos(lt7d)", netPos("lt7d").value, "≥", th.K2.lowerNetPosYoung, 2, ratioText(netPos("lt7d")))]);
      lowerTo = Math.max(RULES.ranges.K2[0], knobs.firstViewMeters, Math.abs(knobs.dislikeMeters), from - step);
      const sub = subsetNetPos(W.subsets.liked);
      raise = fire([cmp("posts.liked", input.posts.liked, "≥", RULES.gates.minPosts, 0), cmp("netPosLiked(d7to30)", sub.value, "<", th.K2.raiseNetPosOld, 2, ratioText(sub)),
        cmp("lossRatio(d7to30)", lossRatio("d7to30").value, "≤", th.K2.raiseLossRatio, 2, ratioText(lossRatio("d7to30")))]);
      raiseTo = Math.min(RULES.ranges.K2[1], knobs.commentMeters, from + step);
      if (lowerTo === from) capNote = knobs.firstViewMeters >= from ? "capped by view ≤ like" : Math.abs(knobs.dislikeMeters) >= from ? "capped by |dislike| ≤ like" : "capped by range";
      else if (raiseTo === from) capNote = knobs.commentMeters <= from ? "capped by like ≤ comment" : "capped by range";
      respects.push("view ≤ like ≤ comment", "|dislike| ≤ like", `range ${fmt(RULES.ranges.K2[0])}–${fmt(RULES.ranges.K2[1])} m`);
    } else if (id === "K3") {
      concentration = fire([cmp("share.comment", shareComment.value, "≥", th.K3.shareComment, 2, ratioText(shareComment)), cmp("M3.commentersW", W.people.commenters, "≤", th.K3.concentrationCommenters, 0)]);
      lower = fire([cmp("share.comment", shareComment.value, "≥", th.K3.shareComment, 2, ratioText(shareComment)), cmp("M3.commentersW", W.people.commenters, "≥", th.K3.lowerCommenters, 0),
        cmp("M6.lt7d.posts", W.net.lt7d.posts, "≥", RULES.gates.minAgeBucketPosts, 0), cmp("netPos(lt7d)", netPos("lt7d").value, "≥", th.K3.lowerNetPosYoung, 2, ratioText(netPos("lt7d")))]);
      lowerTo = Math.max(RULES.ranges.K3[0], knobs.likeMeters, from - step);
      const sub = subsetNetPos(W.subsets.commented);
      raise = fire([cmp("posts.commented", input.posts.commented, "≥", RULES.gates.minPosts, 0), cmp("netPosCommented(d7to30)", sub.value, "<", th.K3.raiseNetPosOld, 2, ratioText(sub)),
        cmp("lossRatio(d7to30)", lossRatio("d7to30").value, "≤", th.K3.raiseLossRatio, 2, ratioText(lossRatio("d7to30")))]);
      raiseTo = Math.min(RULES.ranges.K3[1], from + step);
      if (lowerTo === from) capNote = knobs.likeMeters >= from ? "capped by like ≤ comment" : "capped by range";
      else if (raiseTo === from) capNote = "capped by range";
      respects.push("comment ≥ like", `range ${fmt(RULES.ranges.K3[0])}–${fmt(RULES.ranges.K3[1])} m`);
    } else if (id === "K4") {
      lower = fire([cmp("dislike.clampedShare", clampedShare.value, "≥", th.K4.lowerClampedShare, 2, ratioText(clampedShare))]);
      lowerTo = Math.min(RULES.ranges.K4[1], from + step);
      if (lowerTo === from) capNote = "capped by never ≥ 0";
      respects.push("|dislike| ≤ like", "never ≥ 0");
    } else if (id === "K5") {
      lower = fire([cmp("repeatShare", repeatShare.value, "≥", th.K5.lowerRepeatShare, 2, ratioText(repeatShare)), cmp("repeatDepth", repeatDepth.value, "≥", th.K5.lowerRepeatDepth, 2, ratioText(repeatDepth))]);
      lowerTo = Math.max(RULES.ranges.K5[0], from - step);
      raise = fire([cmp("repeatDepth", repeatDepth.value, "≤", th.K5.raiseRepeatDepth, 2, ratioText(repeatDepth)), cmp("M3.viewersW", W.people.viewers, "≥", th.K5.raiseViewers, 0)]);
      const upper = Math.floor(knobs.firstViewMeters / 2);
      raiseTo = from + step;
      if (repeatLifetime(raiseTo) > knobs.firstViewMeters || raiseTo > upper) { raiseTo = from; capNote = "capped by repeatLifetime ≤ firstView"; }
      respects.push("repeatLifetime(base) ≤ firstView", `range ${fmt(RULES.ranges.K5[0])}–${fmt(upper)} m`);
    } else if (id === "K7") {
      lower = fire([cmp("netPos(d7to30)", netPos("d7to30").value, "<", th.K7.lowerNetPosOld, 2, ratioText(netPos("d7to30"))), cmp("M6.d7to30.perPostDay", W.net.d7to30.perPostDay, "<", 0, 0),
        cmp("lossRatio(d7to30)", lossRatio("d7to30").value, ">", th.K7.lowerLossRatio, 2, ratioText(lossRatio("d7to30")))]);
      lowerTo = clampDecimals(Math.max(RULES.ranges.K7[0], from - step), 4);
      // The table says `= 0`, not `≤ 0`: gainRealMeters is Σ gr, signed, so a real dislike on an old post drives it
      // negative — that is real engagement, not "old posts earn nothing", and must not read as a faster-decay case.
      raise = fire([cmp("posts.liveTesterClean468", input.posts.liveTesterClean468, "≥", RULES.gates.minPosts, 0), cmp("stale.share", staleShare.value, "≥", th.K7.raiseStaleShare, 2, ratioText(staleShare)),
        cmp("M6.gt30d.gainRealMeters", W.net.gt30d.gainRealMeters, "=", 0, 0)], !flags.backfilled && !flags.catchUp);
      raiseTo = clampDecimals(Math.min(RULES.ranges.K7[1], from + step), 4);
      respects.push(`range ${RULES.ranges.K7[0]}–${RULES.ranges.K7[1]} per day`);
    }
    const ruleText = (which: Direction) => `${id}-${which === "lower" ? "L" : "R"}`;
    if (concentration?.fired) {
      verdict.arithmetic = concentration.arithmetic; verdict.rule = { id: `${id}-C`, text: "never lower on a handful of distinct people", inputs: {} };
      return done("hold", "concentration", `${id === "K2" ? "likes" : "comments"} concentrated on ${id === "K2" ? W.people.likers : W.people.commenters} distinct real people — never lower on so few`);
    }
    const raiseAllowed = raise?.fired === true && (id === "K4" || id === "K5" || id === "K7" || k7hold);
    if (lower?.fired && raise?.fired) {
      verdict.arithmetic = `${ruleText("lower")}: ${lower.arithmetic} ∥ ${ruleText("raise")}: ${raise.arithmetic}`;
      return done("hold", "conflicting-evidence", "both the lower and the raise trigger are true — no direction");
    }
    const which: Direction | null = lower?.fired ? "lower" : raiseAllowed ? "raise" : null;
    if (!which) {
      const note = raise?.fired && !raiseAllowed ? " — raise trigger true but K7 is not settled (K7hold false), so no raise is judged" : "";
      verdict.arithmetic = [lower ? `${ruleText("lower")}: ${lower.arithmetic}` : null, raise ? `${ruleText("raise")}: ${raise.arithmetic}` : null].filter(Boolean).join(" ∥ ");
      return done("hold", "in-range", `no rule fired on ${windowLabel(W, day)}${note}`);
    }
    const rule = which === "lower" ? lower! : raise!;
    const to = which === "lower" ? lowerTo : raiseTo;
    verdict.rule = { id: ruleText(which), text: rule.arithmetic, inputs: rule.inputs };
    verdict.arithmetic = rule.arithmetic;
    const judged: Judged = { verdict, candidate: null, judgeable: true, opening: rule };
    if (shadowOpen) return judged;
    const adopted = loop.adopted[id];
    if (adopted && adopted.direction !== which && dayPlus(adopted.day, RULES.reversalGuardDays) > day) {
      done("hold", "reversal-guard", `would reverse the ${adopted.direction} adopted on ${adopted.day} within ${RULES.reversalGuardDays} days`);
      return judged;
    }
    if (withdrawn && withdrawn.ruleId === verdict.rule.id) {
      const margin = computeGates(W, day, RULES.reopenGateMargin);
      const need = id === "K4" ? [margin.Gdislike, margin.Gd] : [margin.Gc, margin.Gd];
      if (need.some((g) => !g.sufficient)) {
        verdict.withdrawnDay = withdrawn.day;
        done("hold", "cool-down", `${verdict.rule.id} was withdrawn on ${withdrawn.day}; re-opening the same rule needs every gate at ${RULES.reopenGateMargin}× — ${need.map((g) => `${g.id} ${g.n}/${g.minN}`).join(" · ")}`);
        return judged;
      }
    }
    // "Lower" is a smaller grant: for K4 that is a smaller MAGNITUDE (−1,000 → −750), never a value at or above zero.
    const magnitude = (value: number) => (id === "K4" ? Math.abs(value) : value);
    const wrongSide = which === "lower" ? magnitude(to) >= magnitude(from) : magnitude(to) <= magnitude(from);
    if (to === from || wrongSide || (id === "K4" && to >= 0)) {
      done("hold", "invariant-capped", capNote || "capped by the knob's range");
      return judged;
    }
    const lifetimeNote = id === "K5" ? ` (lifetime ${fmt(repeatLifetime(to))} m)` : "";
    verdict.suggestion = { from, to, step, direction: which, ruleId: verdict.rule.id, rationale: rule.arithmetic, respects };
    if (id === "K7") verdict.curveAtSuggested = curveBlock(60, { ...knobs, decayPerDay: to }, input.medianTesterPeak, null);
    done("suggest", "in-range", `${which === "lower" ? "lower" : "raise"} ${fmt(from, id === "K7" ? 2 : 0)} → ${fmt(to, id === "K7" ? 2 : 0)}${lifetimeNote} · rule ${verdict.rule.id} · ${gateText()}`);
    judged.candidate = verdict.suggestion;
    return judged;
  };

  // K7hold (decision 7): one definition. K7 is judged first so the grants can read it.
  let k7: Judged | null = null;
  const k7holdOf = (): boolean => !!k7 && !input.trialOnDay && trialShareD30 < RULES.gates.trialShareMax && k7.verdict.verdict === "hold"
    && (k7.verdict.reason === "in-range" || k7.verdict.reason === "changed-recently" || k7.verdict.reason === "reversal-guard");
  k7 = judge("K7");
  const judgedBy: Partial<Record<KnobId, Judged>> = { K7: k7 };
  for (const id of ["K1", "K2", "K3", "K4", "K5"] as KnobId[]) judgedBy[id] = judge(id);

  // ── The outcome loop (0 reads) for the open knob, before R3 decides the card ──
  const outcomes: Partial<Record<KnobId, { outcome: Outcome | null; outcomeNote: string | null; openSinceDay: string | null; withdrawnDay: string | null }>> = {};
  if (input.frozenOutcomes) Object.assign(outcomes, input.frozenOutcomes);
  else if (open) {
    const spec = catalogue(open.knob);
    const declaredNow = spec.knob ? knobs[spec.knob] : null;
    const change = spec.knob ? loop.knobChanges[spec.knob] : undefined;
    let outcome: Outcome = "open"; let note: string | null = null;
    if (declaredNow === open.to) {
      outcome = "adopted-in-source";
      if (open.knob === "K7") note = "production unverifiable";
      else if (input.openProduction && input.openProduction.n >= RULES.gates.minObserved && input.openProduction.value === open.to) {
        outcome = "adopted-in-production";
        loop.adopted[open.knob] = { day, direction: open.direction };
        loop.open = null;
      }
    } else if (change && change.day >= open.sinceDay && declaredNow !== open.from) {
      outcome = "changed-differently"; note = `declared value moved to ${fmt(declaredNow, open.knob === "K7" ? 2 : 0)} instead`;
      loop.open = null;
    } else if (input.countsAsComplete) {
      const shadow = judge(open.knob, true);
      const frozenReason: Reason[] = ["trial", "partial", "backfilled", "epoch-young", "kind-split-unavailable"];
      // The clock runs only on a report where the rule COULD be judged: a gate lost is lapsed evidence,
      // an unjudgeable day (trial, partial, backfill, young epoch, missing kind split, a freeze) is not.
      const advance = shadow.judgeable || (shadow.verdict.verdict === "insufficient" && !frozenReason.includes(shadow.verdict.reason));
      if (advance) {
        const stillFires = shadow.opening?.fired === true && shadow.verdict.rule?.id === open.ruleId;
        const missed = stillFires ? 0 : open.missedReports + 1;
        if (loop.open) loop.open.missedReports = missed;
        if (missed >= RULES.withdrawAfterMissedReports) {
          outcome = "withdrawn";
          loop.withdrawn[open.knob] = { day, ruleId: open.ruleId, completeReportsSince: 0 };
          loop.open = null;
        }
      }
    }
    outcomes[open.knob] = { outcome, outcomeNote: note, openSinceDay: open.sinceDay, withdrawnDay: outcome === "withdrawn" ? day : null };
    const row = judgedBy[open.knob]!.verdict;
    if (outcome === "withdrawn") { row.verdict = "hold"; row.reason = "cool-down"; row.reasonText = `withdrawn since ${day} — the evidence no longer supports it (${open.ruleId} silent on ${RULES.withdrawAfterMissedReports} consecutive complete reports)`; row.suggestion = null; }
    if (outcome === "adopted-in-production") { row.verdict = "hold"; row.reason = "changed-recently"; row.frozenUntilDay = dayPlus(day, RULES.freezeDays); row.reasonText = `adopted in production (seen ${fmt(open.to)} at n ${input.openProduction?.n ?? 0}, all classes) — frozen until ${row.frozenUntilDay}`; row.suggestion = null; }
    if (outcome === "changed-differently") { row.suggestion = null; if (row.reason === "open") { row.reason = "in-range"; row.reasonText = note ?? ""; } }
  }
  for (const [id, w] of Object.entries(loop.withdrawn) as [KnobId, { completeReportsSince: number }][]) {
    if (input.countsAsComplete && !input.frozenOutcomes && !(open && open.knob === id && outcomes[id]?.outcome === "withdrawn")) w.completeReportsSince += 1;
  }

  // ── R3: one knob per report, sticky while a suggestion is open ──
  const nOf = (id: KnobId): number => {
    const w = evidenceWindow;
    return id === "K1" ? w.gain.firstViews + w.gain.repeatViews : id === "K2" ? w.people.likers : id === "K3" ? w.people.commenters : w.dislike.n ?? 0;
  };
  const grants = (["K1", "K2", "K3", "K4"] as KnobId[]).sort((a, b) => nOf(b) - nOf(a) || a.localeCompare(b, undefined, { numeric: true }));
  const order: KnobId[] = ["K7", ...grants, "K5"];
  const stickyOpen = loop.open && (outcomes[loop.open.knob]?.outcome === "open" || outcomes[loop.open.knob]?.outcome === "adopted-in-source") ? loop.open : null;
  let primary: KnobId | null = stickyOpen ? stickyOpen.knob : null;
  const deferred: Decision["deferred"] = [];
  for (const id of order) {
    const judged = judgedBy[id]!;
    if (judged.verdict.verdict !== "suggest" || !judged.candidate) continue;
    if (primary == null) {
      primary = id;
      if (!input.frozenOutcomes) {
        loop.open = { knob: id, sinceDay: day, from: judged.candidate.from, to: judged.candidate.to, ruleId: judged.candidate.ruleId, direction: judged.candidate.direction, missedReports: 0 };
        delete loop.withdrawn[id];
        outcomes[id] = { outcome: "open", outcomeNote: null, openSinceDay: day, withdrawnDay: null };
      }
      continue;
    }
    const row = judged.verdict;
    row.verdict = "hold"; row.reason = "deferred"; row.deferred = { to: judged.candidate.to, ruleId: judged.candidate.ruleId };
    row.reasonText = `also fired (${judged.candidate.ruleId} → ${fmt(judged.candidate.to, id === "K7" ? 2 : 0)}) — held by the one-knob rule while ${primary} is on the card`;
    row.suggestion = null;
    deferred.push({ knob: id, to: judged.candidate.to, ruleId: judged.candidate.ruleId });
  }

  // A K1 lower that leaves repeatLifetime(base) > firstView is K5's evidence, never a cross-knob imperative (refuter 10).
  const k1 = judgedBy.K1!.verdict, k5 = judgedBy.K5!.verdict;
  const k1To = k1.suggestion?.to ?? k1.deferred?.to ?? null;
  if (k1To != null && repeatLifetime(knobs.repeatViewBaseMeters) > k1To) {
    k5.evidence.push({ id: "repeatLadder", value: repeatLifetime(knobs.repeatViewBaseMeters), unit: "m", label: `repeat lifetime ${fmt(repeatLifetime(knobs.repeatViewBaseMeters))} m exceeds the suggested first-view grant ${fmt(k1To)} m — K5's range upper bound would be ${Math.floor(k1To / 2)} m` });
  }

  // ── The fixed and unmeasured rows ──
  const fixedRow = (id: KnobId): Verdict => {
    const spec = catalogue(id);
    const declared = spec.knob ? knobs[spec.knob] : null;
    const reason: Reason = spec.fixedReason ?? "unmeasured";
    const texts: Partial<Record<KnobId, string>> = {
      K6: "a refused repeat view is NO_GRANT and writes no ledger entry — unmeasurable, never suggested",
      K8: "dust floor — a finding row; never suggested", K9: "5 km seed is a FLOOR, owner-fixed 6 Sep; the seedReach finding rides this row — never a number",
      K10: "three definitions of the claim ceiling (rules Σ full radius incl. seeds since ab6489ba; picker Σ organic; server +5 km) — a human retires this finding",
      K11: "slider step — UI, never suggested", K12: "paid product, measured only — a boost replaces, never stacks", K13: "world ceiling 6,371 km — owner-fixed 3 Sep; the anchors line",
      K14: input.trialOnDay ? `decay trial ×${input.trialMultiplierOnDay ?? "?"} ON — owner question: is the trial a decision or an incident? No number is tuned from data` : "decay trial off — owner switch, never a number",
      K15: "simulation stress half-life — suppressed while the trial runs; never suggested", K16: input.channelsSufficient ? "rank never delivery — channel rows printed" : "rank never delivery — channel rows unranked below Gh",
      K17: "simulation shape / ownerUid — a finding, never a knob",
    };
    return {
      knob: id, name: spec.name, tunable: false, declaredValue: declared, unit: spec.unit, seenValue: null, seenN: 0,
      seenBasis: "—", productionPays: null, where: spec.where, deploy: spec.deploy, gates: [], evidence: input.extraEvidence[id] ?? [],
      verdict: id === "K6" ? "insufficient" : "hold", reason, reasonText: texts[id] ?? spec.note, rule: null, arithmetic: null, suggestion: null, deferred: null,
      curveAtSuggested: null, curveCurrent: null, frozenUntilDay: null, previous: input.previousVerdicts?.[id] ?? null,
      outcome: null, outcomeNote: null, openSinceDay: null, withdrawnDay: null,
    };
  };

  // ── R6: a verify pre-empts everything ──
  const verify = input.checks.drift.status === "verify" ? { reason: "drift" as VerifyReason, text: `drift: production pays ${input.checks.drift.verify.join(", ")} (all actor classes, 7 d) ≠ declared` }
    : input.checks.farmBound.status === "verify" ? { reason: "farm-bound" as VerifyReason, text: `farm bound violated: ${input.checks.farmBound.detail}` } : null;
  // The rows that carry the verify: the knob of each drifting grant kind (a kind with no tunable knob, or the
  // farm bound, rides the first-view row). Every other tunable row is insufficient/drift.
  const verifyRows = new Set<KnobId>();
  if (verify) {
    for (const kind of input.checks.drift.status === "verify" ? Object.keys(input.checks.drift.rows).filter((k) => input.checks.drift.rows[k].status === "verify") : []) {
      verifyRows.add((KIND_TO_KNOB as Record<string, KnobId>)[kind] ?? "K1");
    }
    if (verifyRows.size === 0) verifyRows.add("K1");
  }
  const verdicts: Verdict[] = [];
  for (const spec of KNOB_CATALOGUE) {
    const row = judgedBy[spec.id]?.verdict ?? fixedRow(spec.id);
    const stamp = outcomes[spec.id];
    if (stamp) { row.outcome = stamp.outcome; row.outcomeNote = stamp.outcomeNote; row.openSinceDay = stamp.openSinceDay; row.withdrawnDay = stamp.withdrawnDay ?? row.withdrawnDay; }
    if (verify && spec.tunable) {
      row.verdict = verifyRows.has(spec.id) ? "verify" : "insufficient"; row.reason = verifyRows.has(spec.id) ? verify.reason : "drift";
      row.reasonText = verify.text; row.suggestion = null; row.deferred = null;
    }
    // Invariant (decision 14): no suggestion under an insufficient gate, ever.
    if (row.suggestion && (row.verdict !== "suggest" || row.gates.some((g) => g.id !== "Gprod" && !g.sufficient))) { row.suggestion = null; row.verdict = "insufficient"; row.reason = "gate"; }
    verdicts.push(row);
  }
  if (verify) { primary = null; deferred.length = 0; if (!input.frozenOutcomes) loop.open = input.loop.open; }

  const counts: VerdictCounts = { suggest: 0, verify: 0, hold: 0, insufficient: 0, fixed: 0 };
  for (const row of verdicts) {
    if (row.verdict === "hold" && FIXED_REASONS.includes(row.reason as HoldReason)) counts.fixed += 1;
    else counts[row.verdict] += 1;
  }

  // ── The card ──
  const gcRow = gates.Gc, gdRow = gates.Gd;
  const clearedGate = TUNABLE_KNOBS.filter((id) => judgedBy[id]!.verdict.gates.filter((g) => g.id !== "Gprod").every((g) => g.sufficient)).length;
  const ownerQuestion = input.trialOnDay ? "is the ×5 trial a decision or an incident? (K14)" : null;
  let decision: Decision;
  // The open suggestion and its outcome, restated on the card until it is adopted or withdrawn (the day it
  // closes it is listed once more with that outcome, so the owner sees the loop close).
  const openRows: Decision["open"] = [];
  if (open) openRows.push({ knob: open.knob, to: open.to, ruleId: open.ruleId, openSinceDay: open.sinceDay, outcome: outcomes[open.knob]?.outcome ?? "open", missedReports: loop.open?.knob === open.knob ? loop.open.missedReports : open.missedReports });
  if (verify) {
    decision = { kind: "verify", knob: null, sentence: `VERIFY before any knob moves — ${verify.text}. Nothing is applied by this report.`, appliedByReport: false, productionPays: null, action: null, deferred: [], open: openRows, counts, ownerQuestion };
  } else if (primary) {
    const row = verdicts.find((v) => v.knob === primary)!;
    const spec = catalogue(primary);
    const isOpenRestated = !!(stickyOpen && stickyOpen.knob === primary && row.verdict !== "suggest");
    const from = isOpenRestated ? stickyOpen!.from : row.suggestion!.from;
    const to = isOpenRestated ? stickyOpen!.to : row.suggestion!.to;
    const direction = isOpenRestated ? stickyOpen!.direction : row.suggestion!.direction;
    const places = primary === "K7" ? 2 : 0;
    const pays = row.productionPays;
    const seenText = row.seenValue == null ? "unseen" : `${fmt(row.seenValue, places)} (n ${row.seenN}, all classes)`;
    const applyText = spec.deploy.length ? `to apply it you would edit ${spec.where}, ${spec.deploy.join(", ")}` : "";
    const sentence = `suggest ${direction === "lower" ? "lowering" : "raising"} the ${spec.name.toLowerCase()} ${fmt(from, places)} → ${fmt(to, places)}${spec.unit === "m" ? " m" : ""}${isOpenRestated ? ` (open since ${stickyOpen!.sinceDay}${row.outcome && row.outcome !== "open" ? ` · ${row.outcome}` : ""})` : ""} · declared ${fmt(row.declaredValue, places)} · seen ${seenText} — ${applyText} · nothing is applied by this report; production pays ${pays == null ? "an unverified value (n < 30)" : `${fmt(pays, places)}${spec.unit === "m" ? " m" : ""}`} until you deploy`;
    decision = { kind: "suggest", knob: primary, sentence, appliedByReport: false,
      productionPays: { knob: primary, value: pays, n: row.seenN, basis: "all actor classes incl. simulation · 7 d" },
      action: { where: spec.where, from, to, unit: spec.unit, deploy: spec.deploy }, deferred, open: openRows, counts, ownerQuestion };
  } else {
    const k7Note = k7.verdict.reason === "trial" ? " K7 (decay) is in trial mode." : "";
    const sentence = `NO SUGGESTION TODAY. ${clearedGate} of ${TUNABLE_KNOBS.length} tunable knobs cleared a gate: ${gcRow.n}/${gcRow.minN} real events in the ${windowLabel(evidenceWindow, day)}, ${evidenceWindow.accrued ? evidenceWindow.people.actors : 0}/${RULES.gates.minActors} real actors in that window, ${gdRow.n}/${gdRow.minN} tester posts with a real engagement in it.${k7Note} Nothing is applied by this report: production pays what the SEEN column shows until you deploy.${ownerQuestion ? ` Standing owner question: ${ownerQuestion}` : ""}`;
    decision = { kind: "none", knob: null, sentence, appliedByReport: false, productionPays: null, action: null, deferred, open: openRows, counts, ownerQuestion };
  }
  return { verdicts, decision, primarySuggestion: primary, counts, loop, k7hold: k7holdOf() };
}

function maxKeyOf(map: Record<string, number>): number | null {
  const keys = Object.keys(map).filter((k) => k !== "other").map(Number);
  return keys.length ? Math.max(...keys) : null;
}
