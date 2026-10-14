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
exports.postReplacesNearbyOwnPops = exports.REPLACED_EXPIRY_REASON = exports.NEARBY_OWN_POP_METERS = void 0;
exports.haversineMeters = haversineMeters;
exports.postOrigin = postOrigin;
exports.isLivePost = isLivePost;
exports.nearbyOwnPops = nearbyOwnPops;
exports.replaceNearbyOwnPops = replaceNearbyOwnPops;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const firestore_2 = require("firebase-functions/v2/firestore");
const accountRadius_1 = require("./accountRadius");
const postEngagementPolicy_1 = require("./postEngagementPolicy");
const radiusHistory_1 = require("./radiusHistory");
/**
 * One live pop per place, per person.
 *
 * Owner rule 18 Sep 2026: a pop posted within 5 km — the discovery seed — of
 * one of the owner's own live pops REPLACES it. The old pop expires (reach
 * zero, hidden everywhere an expired pop is hidden) and the new pop inherits
 * the earned reach the old one held, so posting again from the same campus is
 * an update, not a penalty. Nothing is minted: the account's live reach is the
 * same before and after, and the claim the old pop had out comes back to the
 * allowance through accountTotalRadiusOnPostWritten like any expiry.
 *
 * Server-side because a client could skip it; redelivery-safe because a
 * replaced pop is no longer live and is not found the second time. The
 * composer warns before publishing (poplur-clay-map ownPops.ts) — this is the
 * rule, that is the courtesy.
 */
exports.NEARBY_OWN_POP_METERS = 5_000;
exports.REPLACED_EXPIRY_REASON = "replaced-by-nearby-pop";
function finite(value) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
}
function haversineMeters(a, b) {
    const toRad = (deg) => (deg * Math.PI) / 180;
    const dLat = toRad(b.latitude - a.latitude);
    const dLng = toRad(b.longitude - a.longitude);
    const h = Math.sin(dLat / 2) ** 2
        + Math.cos(toRad(a.latitude)) * Math.cos(toRad(b.latitude)) * Math.sin(dLng / 2) ** 2;
    return 2 * 6_371_000 * Math.asin(Math.min(1, Math.sqrt(h)));
}
/** A pop's public origin; hidden origins have none and take part in nothing. */
function postOrigin(post) {
    if (post.locationVisibility === "hidden")
        return null;
    const latitude = finite(post.latitude);
    const longitude = finite(post.longitude);
    if (latitude === null || longitude === null)
        return null;
    if (Math.abs(latitude) > 90 || Math.abs(longitude) > 180)
        return null;
    return { latitude, longitude };
}
function isLivePost(post) {
    if (post.visibilityStatus === "expired" || post.status === "deleted" || post.deleted === true)
        return false;
    return (finite(post.radiusMeters ?? post.radius) ?? 0) > 0;
}
function createdAtMillisOf(post) {
    const declared = finite(post.createdAtMillis);
    if (declared !== null && declared > 0)
        return declared;
    const stamp = post.createdAt;
    const millis = typeof stamp?.toMillis === "function" ? Number(stamp.toMillis()) : NaN;
    return Number.isFinite(millis) && millis > 0 ? millis : null;
}
/**
 * Pure: which of `candidates` the new pop replaces — the same owner's OTHER
 * live pops with a public origin within 5 km, created no later than it.
 * Ordering by creation keeps two pops written in the same second from
 * replacing each other (the later one wins; equal stamps fall to id order).
 */
function nearbyOwnPops(post, candidates) {
    const owner = (0, accountRadius_1.postOwnerUid)(post.data);
    const here = postOrigin(post.data);
    if (!owner || !here || !isLivePost(post.data))
        return [];
    const createdAt = createdAtMillisOf(post.data);
    return candidates.filter(candidate => {
        if (candidate.id === post.id || (0, accountRadius_1.postOwnerUid)(candidate.data) !== owner)
            return false;
        if (!isLivePost(candidate.data))
            return false;
        const there = postOrigin(candidate.data);
        if (!there || haversineMeters(here, there) > exports.NEARBY_OWN_POP_METERS)
            return false;
        const theirs = createdAtMillisOf(candidate.data);
        if (createdAt !== null && theirs !== null) {
            if (theirs > createdAt)
                return false;
            if (theirs === createdAt && candidate.id > post.id)
                return false;
        }
        return true;
    });
}
/** Apply the rule for one just-created post. Returns the replaced ids. */
async function replaceNearbyOwnPops(db, postId, nowMillis = Date.now()) {
    const postRef = db.collection("posts").doc(postId);
    return db.runTransaction(async (tx) => {
        const snapshot = await tx.get(postRef);
        const post = snapshot.data();
        if (!snapshot.exists || !post)
            return [];
        const owner = (0, accountRadius_1.postOwnerUid)(post);
        if (!owner || !postOrigin(post) || !isLivePost(post))
            return [];
        // The officialContent seed layer is ambient world-radius content, not a
        // person's pop: one owner (PoplurTest) holds dozens of seeds a few hundred
        // metres apart by design, so the one-live-pop-per-place rule neither
        // applies to a new seed nor lets any pop expire an existing seed.
        if (post.officialContent === true)
            return [];
        const own = await tx.get(db.collection("posts").where("userID", "==", owner));
        const replaced = nearbyOwnPops({ id: postId, data: post }, own.docs.map(doc => ({ id: doc.id, data: doc.data() })).filter(doc => doc.data.officialContent !== true));
        if (replaced.length === 0)
            return [];
        let inherited = 0;
        for (const old of replaced) {
            const parts = (0, postEngagementPolicy_1.postRadiusParts)(old.data, nowMillis);
            inherited += parts.organic;
            const oldRef = db.collection("posts").doc(old.id);
            tx.update(oldRef, {
                visibilityStatus: "expired",
                expiredAt: firestore_1.Timestamp.fromMillis(nowMillis),
                expiryReason: exports.REPLACED_EXPIRY_REASON,
                replacedByPostId: postId,
                radiusMeters: 0, radius: 0,
                organicRadiusMeters: 0, seedRadiusMeters: 0, boostedRadiusMeters: 0,
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
            tx.set((0, radiusHistory_1.radiusHistoryRef)(oldRef, `replaced_${postId}`), (0, radiusHistory_1.radiusHistoryDocument)((0, postEngagementPolicy_1.buildRadiusHistoryEntry)({
                atMillis: nowMillis, cause: "replaced", writer: "postReplacesNearbyOwnPops",
                previous: { radiusMeters: parts.total, organicRadiusMeters: parts.organic },
                next: { radiusMeters: 0, organicRadiusMeters: 0 },
                seedRadiusMeters: 0, boostedRadiusMeters: 0,
            })));
        }
        const before = (0, postEngagementPolicy_1.postRadiusParts)(post, nowMillis);
        const organic = Math.min(postEngagementPolicy_1.MAX_POST_RADIUS_METERS, before.organic + inherited);
        const total = Math.min(postEngagementPolicy_1.MAX_POST_RADIUS_METERS, organic + before.seed + before.boost);
        tx.update(postRef, {
            organicRadiusMeters: organic, radiusMeters: total, radius: total,
            replacedPostIds: firestore_1.FieldValue.arrayUnion(...replaced.map(old => old.id)),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        if (inherited > 0) {
            tx.set((0, radiusHistory_1.radiusHistoryRef)(postRef, `inherited_${nowMillis}`), (0, radiusHistory_1.radiusHistoryDocument)((0, postEngagementPolicy_1.buildRadiusHistoryEntry)({
                atMillis: nowMillis, cause: "inherited", writer: "postReplacesNearbyOwnPops",
                previous: { radiusMeters: before.total, organicRadiusMeters: before.organic },
                next: { radiusMeters: total, organicRadiusMeters: organic },
                seedRadiusMeters: before.seed, boostedRadiusMeters: before.boost,
            })));
        }
        return replaced.map(old => old.id);
    });
}
if (admin.apps.length === 0)
    admin.initializeApp();
// 512 MiB: the whole codebase loads for every function and a NEW function at
// the 256 MiB default is OOM-killed before it logs (11 Sep 2026, nearbyPopsDigest).
exports.postReplacesNearbyOwnPops = (0, firestore_2.onDocumentCreated)({ document: "posts/{postId}", region: "us-central1", retry: true, memory: "512MiB", cpu: 1 }, async (event) => { await replaceNearbyOwnPops(admin.firestore(), event.params.postId); });
