"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PostEngagementValidationError = exports.radiusHistoryEntryId = exports.RADIUS_HISTORY_COLLECTION = exports.RADIUS_DECAY_FLOOR_METERS = exports.RADIUS_DECAY_PER_DAY = exports.REPEAT_VIEW_BASE_METERS = exports.REPEAT_VIEW_MIN_MS = exports.MAX_POST_ENGAGEMENT_COUNT = exports.MAX_POST_SEED_METERS = exports.MAX_POST_RADIUS_METERS = exports.POST_ENGAGEMENT_SURFACES = exports.POST_ENGAGEMENT_KINDS = void 0;
exports.radiusInactivityDeadline = radiusInactivityDeadline;
exports.radiusDecayRates = radiusDecayRates;
exports.buildRadiusHistoryEntry = buildRadiusHistoryEntry;
exports.postRadiusParts = postRadiusParts;
exports.parsePostEngagementInput = parsePostEngagementInput;
exports.postEngagementDocumentId = postEngagementDocumentId;
exports.postEngagementActorStateId = postEngagementActorStateId;
exports.seedRadiusMeters = seedRadiusMeters;
exports.calculateRadiusDecay = calculateRadiusDecay;
exports.calculatePostEngagementMutation = calculatePostEngagementMutation;
const node_crypto_1 = require("node:crypto");
exports.POST_ENGAGEMENT_KINDS = ["view", "like", "dislike", "comment"];
/** Which screen produced the tap. A label for the owner's desk, carried on
 *  the private engagement document only — never a grant input, never on the
 *  world-readable radius history, never on the post. Older clients send none. */
exports.POST_ENGAGEMENT_SURFACES = ["feed", "map", "profile", "unknown"];
/** The top of the radius scale is the Earth's own radius (6,371 km / 3,959
 *  mi), the ceiling every client surface counts "of". A post there has taken
 *  over the world — the clients treat it as reaching everyone — so no radius
 *  is ever stored above it. (Was the planet's circumference, 40,075 km, which
 *  displayed as 24,901 mi over a 3,959 mi ceiling.) */
exports.MAX_POST_RADIUS_METERS = 6_371_000;
/** The largest discovery seed a post may be created with. */
// The most ground one drop can be created with: the 5 km discovery seed plus
// whatever the composer let the account claim on top. Since 6 Sep 2026 that
// is the account's whole earned total rather than a flat 25 km, so the bound
// here is the planet — clipping a seed below what the client legitimately
// claimed would silently shrink the post on its first like. Every metre of it
// is spent reach, never earned; see seedRadiusMeters below.
exports.MAX_POST_SEED_METERS = exports.MAX_POST_RADIUS_METERS;
exports.MAX_POST_ENGAGEMENT_COUNT = 1_000_000_000;
exports.REPEAT_VIEW_MIN_MS = 30_000;
/** Each PAID repeat view halves the next one: 500, 250, 125 … ~994 m lifetime.
 * Measured 2 Sep 2026: uncapped, one account's 30s-cadence script earned
 * +29 km in 30 minutes — world radius in ~29 days. Halving bounds what time
 * alone can buy while "more watching still pays" stays true; scaling the farm
 * now requires accounts, not patience. */
exports.REPEAT_VIEW_BASE_METERS = 500;
/** Organic radius is a score you defend: it halves in ~13.5 days untouched.
 * Boost is paid product with its own expiry and never decays here. */
exports.RADIUS_DECAY_PER_DAY = 0.05;
/** Below this a component snaps to zero, and a pop whose components are all
 *  zero expires (radiusDecay → visibilityStatus 'expired'). 10 m until 18 Sep
 *  2026: a dead pop then lingered for weeks at a reach nobody could find it in,
 *  still on its owner's profile. Owner decision 18 Sep: a pop nobody within a
 *  city block can find is gone. */
exports.RADIUS_DECAY_FLOOR_METERS = 500;
/** Creation time comes from Firestore document metadata, never an editable
 * client date. lastEngagementAt is already protected by the posting rules. */
function radiusInactivityDeadline(post, trial, createdAtMillis) {
    trial = validDecayTrial(trial);
    if (!trial || !Number.isFinite(trial.inactivityExpiryHours) || trial.inactivityExpiryHours < 1
        || trial.inactivityExpiryHours > 168 || !Number.isFinite(trial.inactivityEffectiveAtMillis)
        || !Number.isFinite(createdAtMillis))
        return null;
    const activity = timestampMillis(post.lastEngagementAt) ?? createdAtMillis;
    return Math.max(createdAtMillis, activity, trial.effectiveAtMillis, trial.inactivityEffectiveAtMillis)
        + trial.inactivityExpiryHours * 3600_000;
}
function validDecayTrial(trial) {
    return trial && Number.isFinite(trial.multiplier) && trial.multiplier >= 1 && trial.multiplier <= 10
        && Number.isFinite(trial.effectiveAtMillis) ? trial : undefined;
}
function rapidDecayStart(trial) {
    return trial && Number.isFinite(trial.halfLifeHours) && trial.halfLifeHours >= 1 && trial.halfLifeHours <= 24
        && Number.isFinite(trial.halfLifeEffectiveAtMillis)
        ? Math.max(trial.effectiveAtMillis, trial.halfLifeEffectiveAtMillis) : Infinity;
}
/** Split at activation boundaries so a missed worker catches up at the rate
 * that actually applied. Enabling a faster policy never backdates that rate. */
function radiusDecayFactor(start, end, rate, trial, component) {
    const componentStart = component === 'organic' ? start : Math.max(start, component === 'seed' ? trial?.effectiveAtMillis ?? Infinity : trial?.boostedEffectiveAtMillis ?? Infinity);
    if (end <= componentStart)
        return 1;
    const rapidStart = rapidDecayStart(trial);
    const oldEnd = Math.min(end, rapidStart);
    const oldMs = Math.max(0, oldEnd - componentStart);
    const multipliedMs = trial ? Math.max(0, oldEnd - Math.max(componentStart, trial.effectiveAtMillis)) : 0;
    const weightedMs = oldMs + multipliedMs * ((trial?.multiplier ?? 1) - 1);
    const rapidMs = Math.max(0, end - Math.max(componentStart, rapidStart));
    return Math.pow(1 - rate, weightedMs / 86_400_000)
        * (rapidMs > 0 ? Math.pow(0.5, rapidMs / (trial.halfLifeHours * 3600_000)) : 1);
}
/** The same policy drives the read-only client projection between ticks. */
function radiusDecayRates(nowMillis, trial, rate = exports.RADIUS_DECAY_PER_DAY) {
    trial = validDecayTrial(trial);
    const active = trial && nowMillis >= trial.effectiveAtMillis;
    const organic = nowMillis >= rapidDecayStart(trial)
        ? 1 - Math.pow(0.5, 24 / trial.halfLifeHours)
        : 1 - Math.pow(1 - rate, active ? trial.multiplier : 1);
    return { organic, seed: active ? organic : 0,
        boost: active && Number.isFinite(trial.boostedEffectiveAtMillis) && nowMillis >= trial.boostedEffectiveAtMillis ? organic : 0 };
}
const POST_ID_PATTERN = /^[A-Za-z0-9._:-]{1,128}$/;
const EVENT_ID_PATTERN = /^[A-Za-z0-9._:-]{16,128}$/;
const ALLOWED_INPUT_KEYS = new Set(["postId", "eventId", "kind", "text", "surface"]);
exports.RADIUS_HISTORY_COLLECTION = "radiusHistory";
/** Pure: one history entry from the reach before and after a change. */
function buildRadiusHistoryEntry(input) {
    const previous = input.previous;
    const entry = {
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
    if (input.kind)
        entry.kind = input.kind;
    if (input.engagementId)
        entry.engagementId = input.engagementId;
    if (input.boostTransactionId)
        entry.boostTransactionId = input.boostTransactionId;
    if (input.boostExpiresAtMillis !== undefined)
        entry.boostExpiresAtMillis = input.boostExpiresAtMillis;
    return entry;
}
/** Deterministic entry ids, so a retried transaction or a redelivered
 *  trigger writes the same document instead of a duplicate point. */
exports.radiusHistoryEntryId = {
    create: () => "create",
    engagement: (engagementDocId) => `eng_${engagementDocId}`,
    decay: (atMillis) => `decay_${atMillis}`,
    boost: (boostTransactionId) => `boost_${boostTransactionId}`,
    synthetic: (sequence) => `syn_${sequence}`,
    lab: (atMillis) => `lab_${atMillis}`,
    backfill: (atMillis, tag) => `backfill_${tag}_${atMillis}`,
};
/** The reach a stored post document declares right now, as its three parts.
 *  Exported so every history writer reads the same parts the policy uses. */
function postRadiusParts(post, nowMillis) {
    const radius = currentRadius(post, nowMillis);
    const declared = post.radiusMeters ?? post.radius;
    const stored = declared == null || !Number.isFinite(Number(declared))
        ? null
        : boundedInteger(declared, exports.MAX_POST_RADIUS_METERS);
    return {
        ...radius,
        total: Math.min(exports.MAX_POST_RADIUS_METERS, radius.organic + radius.boost + radius.seed),
        // What the document SAYS its reach is — the number every pin and feed
        // card shows. A history entry steps from this, not from what the policy
        // would compute: the two differ wherever an older writer left the field
        // behind (the decay that dropped the seed), and the change a person sees
        // is measured from what they were looking at.
        stored,
    };
}
class PostEngagementValidationError extends Error {
}
exports.PostEngagementValidationError = PostEngagementValidationError;
function plainObject(value) {
    if (!value || typeof value !== "object" || Array.isArray(value))
        return null;
    const prototype = Object.getPrototypeOf(value);
    return prototype === Object.prototype || prototype === null
        ? value
        : null;
}
/** The callable accepts validated comment text, but no client-selected metrics.
 * Counters and radius grants are calculated in the production transaction. */
function parsePostEngagementInput(value) {
    const row = plainObject(value);
    if (!row || Object.keys(row).some(key => !ALLOWED_INPUT_KEYS.has(key))) {
        throw new PostEngagementValidationError("Send only postId, eventId and kind (plus surface, and text for a comment).");
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
    if (!exports.POST_ENGAGEMENT_KINDS.includes(kind)) {
        throw new PostEngagementValidationError("Unsupported engagement kind.");
    }
    if (row.text !== undefined && (kind !== "comment" || typeof row.text !== "string" || !row.text.trim() || row.text.length > 500)) {
        throw new PostEngagementValidationError("Comment text must contain 1–500 characters and belong to a comment.");
    }
    // The surface is a label, not a grant input, so a name this build does not
    // know (or none at all, from an older client) is simply "unknown". Only
    // junk that is not a string is refused, the way the other fields refuse it.
    if (row.surface !== undefined && typeof row.surface !== "string") {
        throw new PostEngagementValidationError("Invalid engagement surface.");
    }
    const surfaceName = typeof row.surface === "string" ? row.surface.trim() : "";
    const surface = exports.POST_ENGAGEMENT_SURFACES.includes(surfaceName)
        ? surfaceName
        : "unknown";
    return {
        postId,
        eventId,
        kind: kind,
        surface,
        ...(typeof row.text === "string" ? { text: row.text.trim() } : {}),
    };
}
/** Firestore ids never contain the caller's UID/event text directly. The hash
 * still makes one event idempotent for one signed-in actor on one post. */
function postEngagementDocumentId(actorUid, eventId) {
    return (0, node_crypto_1.createHash)("sha256").update(`${actorUid}\u0000${eventId}`).digest("hex");
}
function postEngagementActorStateId(actorUid) {
    return (0, node_crypto_1.createHash)("sha256").update(actorUid).digest("hex");
}
function boundedInteger(value, maximum = exports.MAX_POST_ENGAGEMENT_COUNT) {
    const numberValue = Number(value);
    if (!Number.isFinite(numberValue))
        return 0;
    return Math.max(0, Math.min(maximum, Math.round(numberValue)));
}
function timestampMillis(value) {
    if (value && typeof value.toMillis === "function") {
        const millis = Number(value.toMillis());
        return Number.isFinite(millis) ? millis : null;
    }
    if (value && typeof value === "object") {
        const seconds = Number(value.seconds
            ?? value._seconds);
        return Number.isFinite(seconds) ? seconds * 1_000 : null;
    }
    const millis = Number(value);
    return Number.isFinite(millis) ? millis : null;
}
function activeBoostMeters(post, nowMillis) {
    const boost = boundedInteger(post.boostedRadiusMeters, exports.MAX_POST_RADIUS_METERS);
    if (boost === 0)
        return 0;
    const expiresAt = timestampMillis(post.boostExpiresAt);
    return expiresAt == null || expiresAt > nowMillis ? boost : 0;
}
/**
 * The discovery seed a post was created with. It is what lets a first post be
 * found at all, and it is deliberately NOT earned: it never counts toward what
 * the author may claim next, so publishing a thousand posts buys a thousand
 * discovery windows and no entitlement at all.
 */
function seedRadiusMeters(post) {
    return boundedInteger(post.seedRadiusMeters, exports.MAX_POST_SEED_METERS);
}
function currentRadius(post, nowMillis) {
    const boost = activeBoostMeters(post, nowMillis);
    const seed = seedRadiusMeters(post);
    const total = boundedInteger(post.radiusMeters ?? post.radius, exports.MAX_POST_RADIUS_METERS);
    const declaredOrganic = Number(post.organicRadiusMeters);
    // A post from before seeds existed has no seed, so its total minus boost is
    // all earned, exactly as before. A seeded post never counts its seed as
    // earned, which is what keeps post count out of the entitlement pool.
    const organic = Number.isFinite(declaredOrganic)
        ? boundedInteger(declaredOrganic, exports.MAX_POST_RADIUS_METERS)
        : Math.max(0, total - boost - seed);
    return { organic, boost, seed };
}
const NO_GRANT = {
    applied: false, meters: 0, nextViewAtMillis: null, actorStateUpdate: {},
};
function radiusDelta(kind, nowMillis, actor, isOwner) {
    // You cannot grow your own reach by engaging with yourself. Radius is what
    // OTHER people's attention has earned you, so an owner's own view or like
    // records nothing at all — not the radius, and not the counter that would
    // otherwise let a post rank on attention it never received.
    if (isOwner)
        return NO_GRANT;
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
    if (nowMillis - actor.lastViewAtMillis >= exports.REPEAT_VIEW_MIN_MS) {
        // Halve every paid repeat. An exhausted repeat still counts as a view and
        // still advances the 30s clock — only the radius it pays reaches zero.
        const paidRepeats = boundedInteger(actor.paidRepeatViews, 64);
        const meters = Math.floor(exports.REPEAT_VIEW_BASE_METERS / 2 ** paidRepeats);
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
 * post.decayedAt, server-owned. The all-user trial also decays legacy seeded
 * boost components from its explicit activation time, without retroactive loss.
 */
function calculateRadiusDecay(post, nowMillis, ratePerDay = exports.RADIUS_DECAY_PER_DAY, trial, createdAtMillis) {
    trial = validDecayTrial(trial);
    const radius = currentRadius(post, nowMillis);
    const decayBoost = trial && Number.isFinite(trial.boostedEffectiveAtMillis)
        && nowMillis >= trial.boostedEffectiveAtMillis;
    if (radius.organic <= 0 && !(trial && radius.seed > 0) && !(decayBoost && radius.boost > 0))
        return null;
    const decayedAtMillis = timestampMillis(post.decayedAt);
    if (decayedAtMillis == null)
        return null;
    const deadline = createdAtMillis == null ? null : radiusInactivityDeadline(post, trial, createdAtMillis);
    if (deadline != null && nowMillis >= deadline) {
        const boost = decayBoost ? 0 : radius.boost;
        return { organicRadiusMeters: 0, seedRadiusMeters: 0,
            ...(decayBoost ? { boostedRadiusMeters: 0 } : {}), radiusMeters: boost };
    }
    const elapsedMs = nowMillis - decayedAtMillis;
    if (elapsedMs < 60_000)
        return null;
    const factor = radiusDecayFactor(decayedAtMillis, nowMillis, ratePerDay, trial, 'organic');
    let organic = Math.floor(radius.organic * factor);
    if (organic < exports.RADIUS_DECAY_FLOOR_METERS)
        organic = 0;
    // The trial expires the free discovery grant too; otherwise every post
    // would keep a permanent seed even after all its earned reach was gone.
    const seedFactor = radiusDecayFactor(decayedAtMillis, nowMillis, ratePerDay, trial, 'seed');
    let seed = trial ? Math.floor(radius.seed * seedFactor) : radius.seed;
    if (trial && seed < exports.RADIUS_DECAY_FLOOR_METERS)
        seed = 0;
    let boost = decayBoost ? Math.floor(radius.boost * radiusDecayFactor(decayedAtMillis, nowMillis, ratePerDay, trial, 'boost')) : radius.boost;
    if (decayBoost && boost < exports.RADIUS_DECAY_FLOOR_METERS)
        boost = 0;
    if (organic >= radius.organic && seed >= radius.seed && boost >= radius.boost)
        return null;
    // Keep the stored component sum exact. Outside the trial the seed is
    // preserved; active paid boosts retain their existing expiry policy.
    return {
        organicRadiusMeters: organic,
        ...(trial ? { seedRadiusMeters: seed } : {}),
        ...(decayBoost ? { boostedRadiusMeters: boost } : {}),
        radiusMeters: Math.min(exports.MAX_POST_RADIUS_METERS, organic + boost + seed),
    };
}
/** Accepts the legacy bare `lastViewAtMillis` so existing callers/tests that
 *  predate per-actor like state keep their exact meaning. */
function normalizeActorState(value) {
    if (value == null)
        return { lastViewAtMillis: null };
    if (typeof value === "number")
        return { lastViewAtMillis: value };
    return value;
}
/** Pure policy used by the transaction and its focused test. All values come
 * from the stored post plus a bounded enum; the caller cannot choose a delta. */
function calculatePostEngagementMutation(post, kind, nowMillis, actorState, isOwner = false) {
    const viewCount = boundedInteger(post.viewCount);
    const likeCount = boundedInteger(post.likeCount ?? post.upvoteCount);
    const downvoteCount = boundedInteger(post.downvoteCount ?? post.dislikeCount);
    const commentCount = boundedInteger(post.commentCount);
    const radius = currentRadius(post, nowMillis);
    const delta = radiusDelta(kind, nowMillis, normalizeActorState(actorState), isOwner);
    const declaredTotal = post.radiusMeters ?? post.radius;
    const storedTotal = declaredTotal == null || !Number.isFinite(Number(declaredTotal))
        ? null
        : boundedInteger(declaredTotal, exports.MAX_POST_RADIUS_METERS);
    // Where this event steps FROM is the reach the document declared — what the
    // pin showed — with the policy's own sum only when nothing was stored.
    const previous = {
        radiusMeters: storedTotal ?? Math.min(exports.MAX_POST_RADIUS_METERS, radius.organic + radius.boost + radius.seed),
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
    const maximumOrganic = Math.max(0, exports.MAX_POST_RADIUS_METERS - radius.boost - radius.seed);
    const organicRadiusMeters = Math.max(0, Math.min(maximumOrganic, radius.organic + delta.meters));
    // Reach is seed plus earned plus boost; entitlement, computed elsewhere from
    // organicRadiusMeters alone, never sees the seed.
    const radiusMeters = Math.min(exports.MAX_POST_RADIUS_METERS, organicRadiusMeters + radius.boost + radius.seed);
    const counters = {
        radiusMeters,
        organicRadiusMeters,
        viewCount: kind === "view" ? Math.min(exports.MAX_POST_ENGAGEMENT_COUNT, viewCount + 1) : viewCount,
        likeCount: kind === "like" ? Math.min(exports.MAX_POST_ENGAGEMENT_COUNT, likeCount + 1) : likeCount,
        downvoteCount: kind === "dislike"
            ? Math.min(exports.MAX_POST_ENGAGEMENT_COUNT, downvoteCount + 1)
            : downvoteCount,
        commentCount: kind === "comment"
            ? Math.min(exports.MAX_POST_ENGAGEMENT_COUNT, commentCount + 1)
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
