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
exports.accountTotalRadiusOnPostWritten = exports.ACCOUNT_TOTAL_CONTRIBUTIONS = exports.ACCOUNT_TOTAL_RADIUS_FIELD = void 0;
exports.postTotalRadiusMeters = postTotalRadiusMeters;
exports.reconcileAccountPostRadius = reconcileAccountPostRadius;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const firestore_2 = require("firebase-functions/v2/firestore");
const accountRadius_1 = require("./accountRadius");
const postEngagementPolicy_1 = require("./postEngagementPolicy");
exports.ACCOUNT_TOTAL_RADIUS_FIELD = "totalPostRadiusMeters";
exports.ACCOUNT_TOTAL_CONTRIBUTIONS = "accountPostRadiusContributions";
/** Match the profile's sum: each current post contributes its full displayed radius. */
function postTotalRadiusMeters(post) {
    const value = Number(post.radiusMeters ?? post.radius ?? 0);
    return Number.isFinite(value) ? Math.round(Math.max(0, Math.min(postEngagementPolicy_1.MAX_POST_RADIUS_METERS, value))) : 0;
}
/** Read current state, not an event snapshot: duplicate and out-of-order events
 * converge on the same contribution. Deletion and owner changes remove the old
 * contribution in the same transaction that installs the new one. */
async function reconcileAccountPostRadius(db, postId) {
    const postRef = db.collection("posts").doc(postId);
    const receiptRef = db.collection(exports.ACCOUNT_TOTAL_CONTRIBUTIONS).doc(postId);
    await db.runTransaction(async (tx) => {
        const [post, receipt] = await Promise.all([tx.get(postRef), tx.get(receiptRef)]);
        const previous = receipt.data();
        const current = post.data();
        const oldOwner = typeof previous?.ownerUid === "string" ? previous.ownerUid : "";
        const oldRadius = Number(previous?.radiusMeters ?? 0);
        const ownerUid = current ? (0, accountRadius_1.postOwnerUid)(current) : "";
        const radiusMeters = current && ownerUid ? postTotalRadiusMeters(current) : 0;
        if (oldOwner === ownerUid && oldRadius === radiusMeters && receipt.exists)
            return;
        const deltas = new Map();
        if (oldOwner)
            deltas.set(oldOwner, -oldRadius);
        if (ownerUid)
            deltas.set(ownerUid, (deltas.get(ownerUid) ?? 0) + radiusMeters);
        for (const [uid, delta] of deltas) {
            tx.set(db.collection("users").doc(uid), {
                [exports.ACCOUNT_TOTAL_RADIUS_FIELD]: firestore_1.FieldValue.increment(delta),
                totalPostRadiusUpdatedAt: firestore_1.FieldValue.serverTimestamp(),
            }, { merge: true });
        }
        tx.set(receiptRef, { ownerUid, radiusMeters, updatedAt: firestore_1.FieldValue.serverTimestamp() });
    });
}
if (admin.apps.length === 0)
    admin.initializeApp();
exports.accountTotalRadiusOnPostWritten = (0, firestore_2.onDocumentWritten)({ document: "posts/{postId}", region: "us-central1", retry: true }, async (event) => reconcileAccountPostRadius(admin.firestore(), event.params.postId));
