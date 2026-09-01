"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.PostEngagementValidationError = exports.REPEAT_VIEW_MIN_MS = exports.MAX_POST_ENGAGEMENT_COUNT = exports.MAX_POST_RADIUS_METERS = exports.POST_ENGAGEMENT_KINDS = void 0;
exports.parsePostEngagementInput = parsePostEngagementInput;
exports.postEngagementDocumentId = postEngagementDocumentId;
exports.postEngagementActorStateId = postEngagementActorStateId;
exports.calculatePostEngagementMutation = calculatePostEngagementMutation;
const node_crypto_1 = require("node:crypto");
exports.POST_ENGAGEMENT_KINDS = ["view", "like", "dislike", "comment"];
exports.MAX_POST_RADIUS_METERS = 40_075_000;
exports.MAX_POST_ENGAGEMENT_COUNT = 1_000_000_000;
exports.REPEAT_VIEW_MIN_MS = 30_000;
const POST_ID_PATTERN = /^[A-Za-z0-9._:-]{1,128}$/;
const EVENT_ID_PATTERN = /^[A-Za-z0-9._:-]{16,128}$/;
const ALLOWED_INPUT_KEYS = new Set(["postId", "eventId", "kind"]);
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
/** The callable accepts no client-selected metrics or content. In particular,
 * comment text is deliberately absent: this slice records only the count. */
function parsePostEngagementInput(value) {
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
    if (!exports.POST_ENGAGEMENT_KINDS.includes(kind)) {
        throw new PostEngagementValidationError("Unsupported engagement kind.");
    }
    return { postId, eventId, kind: kind };
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
function currentRadius(post, nowMillis) {
    const boost = activeBoostMeters(post, nowMillis);
    const total = boundedInteger(post.radiusMeters ?? post.radius, exports.MAX_POST_RADIUS_METERS);
    const declaredOrganic = Number(post.organicRadiusMeters);
    const organic = Number.isFinite(declaredOrganic)
        ? boundedInteger(declaredOrganic, exports.MAX_POST_RADIUS_METERS)
        : Math.max(0, total - boost);
    return { organic, boost };
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
        return { applied: true, meters: 500, nextViewAtMillis: nowMillis, actorStateUpdate: {} };
    }
    return NO_GRANT;
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
    if (!delta.applied) {
        return {
            applied: false,
            radiusDeltaMeters: 0,
            counters: {
                radiusMeters: Math.min(exports.MAX_POST_RADIUS_METERS, radius.organic + radius.boost),
                organicRadiusMeters: radius.organic,
                viewCount,
                likeCount,
                downvoteCount,
                commentCount,
            },
            postUpdate: {},
            nextViewAtMillis: null,
            actorStateUpdate: {},
        };
    }
    const maximumOrganic = Math.max(0, exports.MAX_POST_RADIUS_METERS - radius.boost);
    const organicRadiusMeters = Math.max(0, Math.min(maximumOrganic, radius.organic + delta.meters));
    const radiusMeters = Math.min(exports.MAX_POST_RADIUS_METERS, organicRadiusMeters + radius.boost);
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
    };
}
