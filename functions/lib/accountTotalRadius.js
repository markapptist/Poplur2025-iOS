"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.accountTotalRadiusOnPostWritten = exports.POST_RATE_FIELDS = exports.POST_RATE_WINDOW_MS = exports.ACCOUNT_TOTAL_CONTRIBUTIONS = exports.ACCOUNT_COMMITTED_CLAIM_FIELD = exports.ACCOUNT_EARNED_CLAIM_FIELD = exports.ACCOUNT_TOTAL_RADIUS_FIELD = void 0;
exports.postTotalRadiusMeters = postTotalRadiusMeters;
exports.postEarnedClaimMeters = postEarnedClaimMeters;
exports.postCommittedClaimMeters = postCommittedClaimMeters;
exports.nextPostRate = nextPostRate;
exports.reconcileAccountPostRadius = reconcileAccountPostRadius;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const firestore_2 = require("firebase-functions/v2/firestore");
const accountRadius_1 = require("./accountRadius");
const postEngagementPolicy_1 = require("./postEngagementPolicy");
/** Σ full displayed radius over the account's posts — the PROFILE number only.
 *  It used to be the create ceiling too (7 Sep–17 Sep 2026): because seeds
 *  count in it, every drop could claim the sum of every drop before it, and
 *  thirteen posts with no engagement reached the world radius. */
exports.ACCOUNT_TOTAL_RADIUS_FIELD = "totalPostRadiusMeters";
/** Σ earned (organic) radius over live posts — the ground other people gave
 *  this account. The only thing a claim may draw on. */
exports.ACCOUNT_EARNED_CLAIM_FIELD = "earnedClaimMeters";
/** Σ (seed − 5 km) over live posts — the claims already sitting on pops. A
 *  claim is spent while its pop lives and comes back when the pop is deleted
 *  or its seed decays; it is never reused while it is out. */
exports.ACCOUNT_COMMITTED_CLAIM_FIELD = "committedClaimMeters";
exports.ACCOUNT_TOTAL_CONTRIBUTIONS = "accountPostRadiusContributions";
/** Post-rate state the create rule reads: one post a minute, thirty a rolling
 *  day. Counted from the trigger's own clock on the first sighting of a post,
 *  never from the document's createdAt, which a modified client may forge. */
exports.POST_RATE_WINDOW_MS = 86_400_000;
exports.POST_RATE_FIELDS = Object.freeze({
    lastPostAt: "lastPostAtMillis",
    windowStart: "postWindowStartMillis",
    count: "postsInWindow",
});
function finite(value) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
}
function boundedMeters(value) {
    const parsed = finite(value);
    return parsed === null ? 0 : Math.round(Math.max(0, Math.min(postEngagementPolicy_1.MAX_POST_RADIUS_METERS, parsed)));
}
function isLive(post) {
    return post.visibilityStatus !== "expired" && postTotalRadiusMeters(post) > 0;
}
/** Match the profile's sum: each current post contributes its full displayed radius. */
function postTotalRadiusMeters(post) {
    return boundedMeters(post.radiusMeters ?? post.radius ?? 0);
}
/** What a live post has earned; an expired or empty one holds nothing. Same
 *  reading as the web picker (accountRadiusPosts.ts) and postEarnedRadiusMeters. */
function postEarnedClaimMeters(post) {
    return isLive(post) ? (0, accountRadius_1.postEarnedRadiusMeters)(post) : 0;
}
/** The claim a live post is holding: its seed above the free discovery grant,
 *  never more than its live reach (decay shrinks the seed in step). */
function postCommittedClaimMeters(post) {
    if (!isLive(post))
        return 0;
    const seed = Math.min(boundedMeters(post.seedRadiusMeters), postTotalRadiusMeters(post));
    return Math.max(0, seed - accountRadius_1.POST_DISCOVERY_SEED_METERS);
}
/** Pure step of the post-rate window for a post first seen at `nowMillis`. */
function nextPostRate(current, nowMillis) {
    const last = finite(current.lastPostAtMillis) ?? 0;
    const start = finite(current.postWindowStartMillis);
    const count = finite(current.postsInWindow) ?? 0;
    const lastPostAtMillis = Math.max(last, nowMillis);
    if (start === null || nowMillis - start >= exports.POST_RATE_WINDOW_MS) {
        return { lastPostAtMillis, postWindowStartMillis: nowMillis, postsInWindow: 1 };
    }
    return { lastPostAtMillis, postWindowStartMillis: start, postsInWindow: Math.max(0, Math.round(count)) + 1 };
}
/** Read current state, not an event snapshot: duplicate and out-of-order events
 * converge on the same contributions. Deletion and owner changes remove the old
 * contribution in the same transaction that installs the new one. */
async function reconcileAccountPostRadius(db, postId, options = {}) {
    const countPostRate = options.countPostRate !== false;
    const postRef = db.collection("posts").doc(postId);
    const receiptRef = db.collection(exports.ACCOUNT_TOTAL_CONTRIBUTIONS).doc(postId);
    await db.runTransaction(async (tx) => {
        const [post, receipt] = await Promise.all([tx.get(postRef), tx.get(receiptRef)]);
        const previous = receipt.data();
        const current = post.data();
        const oldOwner = typeof previous?.ownerUid === "string" ? previous.ownerUid : "";
        const old = {
            radius: finite(previous?.radiusMeters) ?? 0,
            earned: finite(previous?.earnedMeters) ?? 0,
            claim: finite(previous?.claimMeters) ?? 0,
        };
        const ownerUid = current ? (0, accountRadius_1.postOwnerUid)(current) : "";
        const deletingOwners = new Set();
        for (const uid of new Set([oldOwner, ownerUid].filter(Boolean))) {
            if ((await tx.get(db.collection("accountDeletions").doc(uid))).exists)
                deletingOwners.add(uid);
        }
        const next = current && ownerUid
            ? { radius: postTotalRadiusMeters(current), earned: postEarnedClaimMeters(current), claim: postCommittedClaimMeters(current) }
            : { radius: 0, earned: 0, claim: 0 };
        const firstSighting = !receipt.exists && !!current && !!ownerUid;
        // Reads before writes: the rate window needs the owner's current state.
        const rate = firstSighting && countPostRate
            ? nextPostRate((await tx.get(db.collection("users").doc(ownerUid))).data() ?? {}, options.nowMillis ?? Date.now())
            : null;
        if (oldOwner === ownerUid && old.radius === next.radius && old.earned === next.earned
            && old.claim === next.claim && receipt.exists && !rate)
            return;
        const deltas = new Map();
        const add = (uid, sign, v) => {
            const row = deltas.get(uid) ?? { radius: 0, earned: 0, claim: 0 };
            row.radius += sign * v.radius;
            row.earned += sign * v.earned;
            row.claim += sign * v.claim;
            deltas.set(uid, row);
        };
        if (oldOwner)
            add(oldOwner, -1, old);
        if (ownerUid)
            add(ownerUid, 1, next);
        for (const [uid, delta] of deltas) {
            if (deletingOwners.has(uid))
                continue;
            const update = {};
            if (delta.radius !== 0)
                update[exports.ACCOUNT_TOTAL_RADIUS_FIELD] = firestore_1.FieldValue.increment(delta.radius);
            if (delta.earned !== 0)
                update[exports.ACCOUNT_EARNED_CLAIM_FIELD] = firestore_1.FieldValue.increment(delta.earned);
            if (delta.claim !== 0)
                update[exports.ACCOUNT_COMMITTED_CLAIM_FIELD] = firestore_1.FieldValue.increment(delta.claim);
            if (uid === ownerUid && rate)
                Object.assign(update, rate);
            if (Object.keys(update).length === 0)
                continue;
            update.totalPostRadiusUpdatedAt = firestore_1.FieldValue.serverTimestamp();
            tx.set(db.collection("users").doc(uid), update, { merge: true });
        }
        if (deletingOwners.has(ownerUid) || (!ownerUid && deletingOwners.has(oldOwner))) {
            tx.delete(receiptRef);
            return;
        }
        tx.set(receiptRef, {
            ownerUid, radiusMeters: next.radius, earnedMeters: next.earned, claimMeters: next.claim,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
    });
}
if (admin.apps.length === 0)
    admin.initializeApp();
exports.accountTotalRadiusOnPostWritten = (0, firestore_2.onDocumentWritten)({ document: "posts/{postId}", region: "us-central1", retry: true }, async (event) => reconcileAccountPostRadius(admin.firestore(), event.params.postId));
