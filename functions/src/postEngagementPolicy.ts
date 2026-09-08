import { createHash } from "node:crypto";

export const POST_ENGAGEMENT_KINDS = ["view", "like", "dislike", "comment"] as const;
export type PostEngagementKind = typeof POST_ENGAGEMENT_KINDS[number];

/** The top of the radius scale is the Earth's own radius (6,371 km / 3,959
 *  mi), the ceiling every client surface counts "of". A post there has taken
 *  over the world — the clients treat it as reaching everyone — so no radius
 *  is ever stored above it. (Was the planet's circumference, 40,075 km, which
 *  displayed as 24,901 mi over a 3,959 mi ceiling.) */
export const MAX_POST_RADIUS_METERS = 6_371_000;
/** The largest discovery seed a post may be created with. */
// The most ground one drop can be created with: the 5 km discovery seed plus
// whatever the composer let the account claim on top. Since 6 Sep 2026 that
// is the account's whole earned total rather than a flat 25 km, so the bound
// here is the planet — clipping a seed below what the client legitimately
// claimed would silently shrink the post on its first like. Every metre of it
// is spent reach, never earned; see seedRadiusMeters below.
export const MAX_POST_SEED_METERS = MAX_POST_RADIUS_METERS;
export const MAX_POST_ENGAGEMENT_COUNT = 1_000_000_000;
export const REPEAT_VIEW_MIN_MS = 30_000;
/** Each PAID repeat view halves the next one: 500, 250, 125 … ~994 m lifetime.
 * Measured 2 Sep 2026: uncapped, one account's 30s-cadence script earned
 * +29 km in 30 minutes — world radius in ~29 days. Halving bounds what time
 * alone can buy while "more watching still pays" stays true; scaling the farm
 * now requires accounts, not patience. */
export const REPEAT_VIEW_BASE_METERS = 500;
/** Organic radius is a score you defend: it halves in ~13.5 days untouched.
 * Boost is paid product with its own expiry and never decays here. */
export const RADIUS_DECAY_PER_DAY = 0.05;
/** Below this, decayed dust snaps to zero instead of shrinking forever. */
export const RADIUS_DECAY_FLOOR_METERS = 10;

const POST_ID_PATTERN = /^[A-Za-z0-9._:-]{1,128}$/;
const EVENT_ID_PATTERN = /^[A-Za-z0-9._:-]{16,128}$/;
const ALLOWED_INPUT_KEYS = new Set(["postId", "eventId", "kind", "text"]);

export interface PostEngagementInput {
  postId: string;
  eventId: string;
  kind: PostEngagementKind;
  text?: string;
}

export interface PostEngagementCounters {
  radiusMeters: number;
  organicRadiusMeters: number;
  viewCount: number;
  likeCount: number;
  downvoteCount: number;
  commentCount: number;
}

/**
 * What this actor has already been GRANTED on this post. Reach is earned from
 * people, not from taps: a like is a boolean an account holds, so holding it
 * twice must not pay twice.
 */
export interface PostEngagementActorState {
  /** When this actor last had a view granted, for the repeat-view gate. */
  lastViewAtMillis: number | null;
  liked?: boolean;
  disliked?: boolean;
  /** A second comment still counts as a comment; it just stops paying radius. */
  commentGranted?: boolean;
  /** How many repeat views this actor has been PAID for — the halving index. */
  paidRepeatViews?: number;
}

export interface PostEngagementMutation {
  applied: boolean;
  radiusDeltaMeters: number;
  counters: PostEngagementCounters;
  postUpdate: Record<string, number>;
  nextViewAtMillis: number | null;
  /** Fields to merge into this actor's state doc so the grant cannot repeat. */
  actorStateUpdate: Record<string, boolean | number>;
  /** The reach as it stood BEFORE this event — what a history entry steps from. */
  previous: { radiusMeters: number; organicRadiusMeters: number };
  /** The seed and active boost that sat under the total, so a history entry
   *  can carry the parts and not just the sum. */
  radius: { seed: number; boost: number };
}

// ── Radius history ───────────────────────────────────────────────────────────
//
// A pop has a history: every change to its reach is one entry in
// posts/{postId}/radiusHistory, written in the SAME transaction or batch as the
// change itself, by the writer that made it. Nothing here is reconstructed by
// guessing — an entry exists because a write happened, with its cause.
// Entries carry no actor identity (the engagements documents are deliberately
// private); an engagement entry names its engagement doc id, which only the
// actor and the owner can open.

export type RadiusHistoryCause =
  | "create" | "engagement" | "decay" | "boost" | "synthetic" | "lab" | "backfill";

export interface RadiusHistoryEntry {
  atMillis: number;
  cause: RadiusHistoryCause;
  radiusMeters: number;
  organicRadiusMeters: number;
  seedRadiusMeters: number;
  boostedRadiusMeters: number;
  /** radiusMeters − the previous entry's radiusMeters (0 for the first). */
  delta: number;
  organicDelta: number;
  writer: string;
  kind?: PostEngagementKind;
  engagementId?: string;
  boostTransactionId?: string;
  boostExpiresAtMillis?: number | null;
}

export const RADIUS_HISTORY_COLLECTION = "radiusHistory";

/** Pure: one history entry from the reach before and after a change. */
export function buildRadiusHistoryEntry(input: {
  atMillis: number;
  cause: RadiusHistoryCause;
  writer: string;
  previous: { radiusMeters: number; organicRadiusMeters: number } | null;
  next: { radiusMeters: number; organicRadiusMeters: number };
  seedRadiusMeters: number;
  boostedRadiusMeters: number;
  kind?: PostEngagementKind;
  engagementId?: string;
  boostTransactionId?: string;
  boostExpiresAtMillis?: number | null;
}): RadiusHistoryEntry {
  const previous = input.previous;
  const entry: RadiusHistoryEntry = {
    atMillis: input.atMillis,
    cause: input.cause,
    radiusMeters: input.next.radiusMeters,
    organicRadiusMeters: input.next.organicRadiusMeters,
    seedRadiusMeters: input.seedRadiusMeters,
    boostedRadiusMeters: input.boostedRadiusMeters,
    delta: previous ? input.next.radiusMeters - previous.radiusMeters : 0,
    organicDelta: previous ? input.next.organicRadiusMeters - previous.organicRadiusMeters : 0,
    writer: input.writer,
  };
  if (input.kind) entry.kind = input.kind;
  if (input.engagementId) entry.engagementId = input.engagementId;
  if (input.boostTransactionId) entry.boostTransactionId = input.boostTransactionId;
  if (input.boostExpiresAtMillis !== undefined) entry.boostExpiresAtMillis = input.boostExpiresAtMillis;
  return entry;
}

/** Deterministic entry ids, so a retried transaction or a redelivered
 *  trigger writes the same document instead of a duplicate point. */
export const radiusHistoryEntryId = {
  create: () => "create",
  engagement: (engagementDocId: string) => `eng_${engagementDocId}`,
  decay: (atMillis: number) => `decay_${atMillis}`,
  boost: (boostTransactionId: string) => `boost_${boostTransactionId}`,
  synthetic: (sequence: number) => `syn_${sequence}`,
  lab: (atMillis: number) => `lab_${atMillis}`,
  backfill: (atMillis: number, tag: string) => `backfill_${tag}_${atMillis}`,
};

/** The reach a stored post document declares right now, as its three parts.
 *  Exported so every history writer reads the same parts the policy uses. */
export function postRadiusParts(
  post: Record<string, unknown>,
  nowMillis: number,
): { organic: number; boost: number; seed: number; total: number; stored: number | null } {
  const radius = currentRadius(post, nowMillis);
  const declared = post.radiusMeters ?? post.radius;
  const stored = declared == null || !Number.isFinite(Number(declared))
    ? null
    : boundedInteger(declared, MAX_POST_RADIUS_METERS);
  return {
    ...radius,
    total: Math.min(MAX_POST_RADIUS_METERS, radius.organic + radius.boost + radius.seed),
    // What the document SAYS its reach is — the number every pin and feed
    // card shows. A history entry steps from this, not from what the policy
    // would compute: the two differ wherever an older writer left the field
    // behind (the decay that dropped the seed), and the change a person sees
    // is measured from what they were looking at.
    stored,
  };
}

export class PostEngagementValidationError extends Error {}

function plainObject(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null
    ? value as Record<string, unknown>
    : null;
}

/** The callable accepts validated comment text, but no client-selected metrics.
 * Counters and radius grants are calculated in the production transaction. */
export function parsePostEngagementInput(value: unknown): PostEngagementInput {
  const row = plainObject(value);
  if (!row || Object.keys(row).some(key => !ALLOWED_INPUT_KEYS.has(key))) {
    throw new PostEngagementValidationError("Send only postId, eventId and kind.");
  }
  const postId = typeof row.postId === "string" ? row.postId.trim() : "";
  const eventId = typeof row.eventId === "string" ? row.eventId.trim() : "";
  const kind = typeof row.kind === "string" ? row.kind.trim() : "";
  if (!POST_ID_PATTERN.test(postId)) {
    throw new PostEngagementValidationError("Invalid post id.");
  }
  if (!EVENT_ID_PATTERN.test(eventId)) {
    throw new PostEngagementValidationError("Invalid engagement event id.");
  }
  if (!(POST_ENGAGEMENT_KINDS as readonly string[]).includes(kind)) {
    throw new PostEngagementValidationError("Unsupported engagement kind.");
  }
  if (row.text !== undefined && (kind !== "comment" || typeof row.text !== "string" || !row.text.trim() || row.text.length > 500)) {
    throw new PostEngagementValidationError("Comment text must contain 1–500 characters and belong to a comment.");
  }
  return { postId, eventId, kind: kind as PostEngagementKind, ...(typeof row.text === "string" ? { text: row.text.trim() } : {}) };
}

/** Firestore ids never contain the caller's UID/event text directly. The hash
 * still makes one event idempotent for one signed-in actor on one post. */
export function postEngagementDocumentId(actorUid: string, eventId: string): string {
  return createHash("sha256").update(`${actorUid}\u0000${eventId}`).digest("hex");
}

export function postEngagementActorStateId(actorUid: string): string {
  return createHash("sha256").update(actorUid).digest("hex");
}

function boundedInteger(value: unknown, maximum = MAX_POST_ENGAGEMENT_COUNT): number {
  const numberValue = Number(value);
  if (!Number.isFinite(numberValue)) return 0;
  return Math.max(0, Math.min(maximum, Math.round(numberValue)));
}

function timestampMillis(value: unknown): number | null {
  if (value && typeof (value as { toMillis?: unknown }).toMillis === "function") {
    const millis = Number((value as { toMillis: () => number }).toMillis());
    return Number.isFinite(millis) ? millis : null;
  }
  if (value && typeof value === "object") {
    const seconds = Number((value as { seconds?: unknown; _seconds?: unknown }).seconds
      ?? (value as { _seconds?: unknown })._seconds);
    return Number.isFinite(seconds) ? seconds * 1_000 : null;
  }
  const millis = Number(value);
  return Number.isFinite(millis) ? millis : null;
}

function activeBoostMeters(post: Record<string, unknown>, nowMillis: number): number {
  const boost = boundedInteger(post.boostedRadiusMeters, MAX_POST_RADIUS_METERS);
  if (boost === 0) return 0;
  const expiresAt = timestampMillis(post.boostExpiresAt);
  return expiresAt == null || expiresAt > nowMillis ? boost : 0;
}

/**
 * The discovery seed a post was created with. It is what lets a first post be
 * found at all, and it is deliberately NOT earned: it never counts toward what
 * the author may claim next, so publishing a thousand posts buys a thousand
 * discovery windows and no entitlement at all.
 */
export function seedRadiusMeters(post: Record<string, unknown>): number {
  return boundedInteger(post.seedRadiusMeters, MAX_POST_SEED_METERS);
}

function currentRadius(
  post: Record<string, unknown>,
  nowMillis: number,
): { organic: number; boost: number; seed: number } {
  const boost = activeBoostMeters(post, nowMillis);
  const seed = seedRadiusMeters(post);
  const total = boundedInteger(post.radiusMeters ?? post.radius, MAX_POST_RADIUS_METERS);
  const declaredOrganic = Number(post.organicRadiusMeters);
  // A post from before seeds existed has no seed, so its total minus boost is
  // all earned, exactly as before. A seeded post never counts its seed as
  // earned, which is what keeps post count out of the entitlement pool.
  const organic = Number.isFinite(declaredOrganic)
    ? boundedInteger(declaredOrganic, MAX_POST_RADIUS_METERS)
    : Math.max(0, total - boost - seed);
  return { organic, boost, seed };
}

type DeltaOutcome = {
  applied: boolean;
  meters: number;
  nextViewAtMillis: number | null;
  actorStateUpdate: Record<string, boolean | number>;
};

const NO_GRANT: DeltaOutcome = {
  applied: false, meters: 0, nextViewAtMillis: null, actorStateUpdate: {},
};

function radiusDelta(
  kind: PostEngagementKind,
  nowMillis: number,
  actor: PostEngagementActorState,
  isOwner: boolean,
): DeltaOutcome {
  // You cannot grow your own reach by engaging with yourself. Radius is what
  // OTHER people's attention has earned you, so an owner's own view or like
  // records nothing at all — not the radius, and not the counter that would
  // otherwise let a post rank on attention it never received.
  if (isOwner) return NO_GRANT;

  // A like is a state, not an event: one account either likes this post or it
  // does not. Paying every repeat tap let one signed-in account add unlimited
  // radius, which is the whole product bought with a finger.
  if (kind === "like") {
    return actor.liked === true
      ? NO_GRANT
      : { applied: true, meters: 1_000, nextViewAtMillis: null, actorStateUpdate: { liked: true } };
  }
  if (kind === "dislike") {
    return actor.disliked === true
      ? NO_GRANT
      : { applied: true, meters: -1_000, nextViewAtMillis: null, actorStateUpdate: { disliked: true } };
  }
  // Commenting twice is ordinary and stays counted; only the radius it pays is
  // once per account, for the same reason as the like above.
  if (kind === "comment") {
    return actor.commentGranted === true
      ? { applied: true, meters: 0, nextViewAtMillis: null, actorStateUpdate: {} }
      : { applied: true, meters: 2_000, nextViewAtMillis: null, actorStateUpdate: { commentGranted: true } };
  }
  if (actor.lastViewAtMillis == null) {
    return { applied: true, meters: 1_000, nextViewAtMillis: nowMillis, actorStateUpdate: {} };
  }
  if (nowMillis - actor.lastViewAtMillis >= REPEAT_VIEW_MIN_MS) {
    // Halve every paid repeat. An exhausted repeat still counts as a view and
    // still advances the 30s clock — only the radius it pays reaches zero.
    const paidRepeats = boundedInteger(actor.paidRepeatViews, 64);
    const meters = Math.floor(REPEAT_VIEW_BASE_METERS / 2 ** paidRepeats);
    return {
      applied: true,
      meters,
      nextViewAtMillis: nowMillis,
      actorStateUpdate: meters > 0 ? { paidRepeatViews: paidRepeats + 1 } : {},
    };
  }
  return NO_GRANT;
}

/**
 * Pure decay step used by the scheduled radiusDecay function and its test.
 * Returns the shrunken counters, or null when nothing should be written:
 * no organic radius, no decayedAt baseline yet (the scheduler stamps one
 * without decaying — decay accrues only from a server-written baseline),
 * less than a minute elapsed, or rounding produced no change. The clock is
 * post.decayedAt, server-owned; boost never decays and is re-added on top.
 */
export function calculateRadiusDecay(
  post: Record<string, unknown>,
  nowMillis: number,
  ratePerDay = RADIUS_DECAY_PER_DAY,
  trial?: { multiplier: number; effectiveAtMillis: number },
): { organicRadiusMeters: number; seedRadiusMeters?: number; radiusMeters: number } | null {
  if (trial && (!Number.isFinite(trial.multiplier) || trial.multiplier < 1 || trial.multiplier > 10
    || !Number.isFinite(trial.effectiveAtMillis))) trial = undefined;
  const radius = currentRadius(post, nowMillis);
  if (radius.organic <= 0 && !(trial && radius.seed > 0)) return null;
  const decayedAtMillis = timestampMillis(post.decayedAt);
  if (decayedAtMillis == null) return null;
  const elapsedMs = nowMillis - decayedAtMillis;
  if (elapsedMs < 60_000) return null;
  const multiplier = trial && Number.isFinite(trial.multiplier) && trial.multiplier >= 1 && trial.multiplier <= 10
    && Number.isFinite(trial.effectiveAtMillis) ? trial.multiplier : 1;
  const trialElapsedMs = trial ? Math.max(0, nowMillis - Math.max(decayedAtMillis, trial.effectiveAtMillis)) : 0;
  const weightedElapsedMs = elapsedMs + trialElapsedMs * (multiplier - 1);
  const factor = Math.pow(1 - ratePerDay, weightedElapsedMs / 86_400_000);
  let organic = Math.floor(radius.organic * factor);
  if (organic < RADIUS_DECAY_FLOOR_METERS) organic = 0;
  // The trial expires the free discovery grant too; otherwise every post
  // would keep a permanent seed even after all its earned reach was gone.
  const seedFactor = Math.pow(1 - ratePerDay, trialElapsedMs * multiplier / 86_400_000);
  let seed = trial ? Math.floor(radius.seed * seedFactor) : radius.seed;
  if (trial && seed < RADIUS_DECAY_FLOOR_METERS) seed = 0;
  if (organic >= radius.organic && seed >= radius.seed) return null;
  // Keep the stored component sum exact. Outside the trial the seed is
  // preserved; active paid boosts retain their existing expiry policy.
  return {
    organicRadiusMeters: organic,
    ...(trial ? { seedRadiusMeters: seed } : {}),
    radiusMeters: Math.min(MAX_POST_RADIUS_METERS, organic + radius.boost + seed),
  };
}

/** Accepts the legacy bare `lastViewAtMillis` so existing callers/tests that
 *  predate per-actor like state keep their exact meaning. */
function normalizeActorState(
  value: PostEngagementActorState | number | null | undefined,
): PostEngagementActorState {
  if (value == null) return { lastViewAtMillis: null };
  if (typeof value === "number") return { lastViewAtMillis: value };
  return value;
}

/** Pure policy used by the transaction and its focused test. All values come
 * from the stored post plus a bounded enum; the caller cannot choose a delta. */
export function calculatePostEngagementMutation(
  post: Record<string, unknown>,
  kind: PostEngagementKind,
  nowMillis: number,
  actorState: PostEngagementActorState | number | null,
  isOwner = false,
): PostEngagementMutation {
  const viewCount = boundedInteger(post.viewCount);
  const likeCount = boundedInteger(post.likeCount ?? post.upvoteCount);
  const downvoteCount = boundedInteger(post.downvoteCount ?? post.dislikeCount);
  const commentCount = boundedInteger(post.commentCount);
  const radius = currentRadius(post, nowMillis);
  const delta = radiusDelta(kind, nowMillis, normalizeActorState(actorState), isOwner);

  const declaredTotal = post.radiusMeters ?? post.radius;
  const storedTotal = declaredTotal == null || !Number.isFinite(Number(declaredTotal))
    ? null
    : boundedInteger(declaredTotal, MAX_POST_RADIUS_METERS);
  // Where this event steps FROM is the reach the document declared — what the
  // pin showed — with the policy's own sum only when nothing was stored.
  const previous = {
    radiusMeters: storedTotal ?? Math.min(MAX_POST_RADIUS_METERS, radius.organic + radius.boost + radius.seed),
    organicRadiusMeters: radius.organic,
  };
  const parts = { seed: radius.seed, boost: radius.boost };

  if (!delta.applied) {
    return {
      applied: false,
      radiusDeltaMeters: 0,
      counters: {
        radiusMeters: previous.radiusMeters,
        organicRadiusMeters: radius.organic,
        viewCount,
        likeCount,
        downvoteCount,
        commentCount,
      },
      postUpdate: {},
      nextViewAtMillis: null,
      actorStateUpdate: {},
      previous,
      radius: parts,
    };
  }

  const maximumOrganic = Math.max(0, MAX_POST_RADIUS_METERS - radius.boost - radius.seed);
  const organicRadiusMeters = Math.max(
    0,
    Math.min(maximumOrganic, radius.organic + delta.meters),
  );
  // Reach is seed plus earned plus boost; entitlement, computed elsewhere from
  // organicRadiusMeters alone, never sees the seed.
  const radiusMeters = Math.min(
    MAX_POST_RADIUS_METERS,
    organicRadiusMeters + radius.boost + radius.seed,
  );
  const counters: PostEngagementCounters = {
    radiusMeters,
    organicRadiusMeters,
    viewCount: kind === "view" ? Math.min(MAX_POST_ENGAGEMENT_COUNT, viewCount + 1) : viewCount,
    likeCount: kind === "like" ? Math.min(MAX_POST_ENGAGEMENT_COUNT, likeCount + 1) : likeCount,
    downvoteCount: kind === "dislike"
      ? Math.min(MAX_POST_ENGAGEMENT_COUNT, downvoteCount + 1)
      : downvoteCount,
    commentCount: kind === "comment"
      ? Math.min(MAX_POST_ENGAGEMENT_COUNT, commentCount + 1)
      : commentCount,
  };

  return {
    applied: true,
    radiusDeltaMeters: organicRadiusMeters - radius.organic,
    counters,
    postUpdate: {
      radiusMeters: counters.radiusMeters,
      radius: counters.radiusMeters,
      organicRadiusMeters: counters.organicRadiusMeters,
      viewCount: counters.viewCount,
      likeCount: counters.likeCount,
      downvoteCount: counters.downvoteCount,
      commentCount: counters.commentCount,
    },
    nextViewAtMillis: delta.nextViewAtMillis,
    actorStateUpdate: delta.actorStateUpdate,
    previous,
    radius: parts,
  };
}
