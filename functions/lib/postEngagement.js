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
exports.recordPostEngagement = void 0;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const postEngagementPolicy_1 = require("./postEngagementPolicy");
if (admin.apps.length === 0)
    admin.initializeApp();
const db = admin.firestore();
const region = "us-central1";
function boundedText(value, maximum) {
    return typeof value === "string" ? value.trim().replace(/\s+/g, " ").slice(0, maximum) : "";
}
function postOwnerUid(post) {
    return boundedText(post.ownerId ?? post.userID ?? post.userId, 128);
}
function publishedPost(post) {
    const audience = boundedText(post.audience, 24).toLowerCase();
    const status = boundedText(post.visibilityStatus ?? post.status, 24).toLowerCase();
    return (!audience || audience === "public")
        && (!status || status === "published" || status === "live");
}
function actorHandle(user) {
    const value = boundedText(user.username ?? user.handle ?? user.displayName, 40);
    if (!value)
        return "";
    return value.startsWith("@") ? value : `@${value}`;
}
function storedResult(value) {
    if (!value || typeof value !== "object" || Array.isArray(value))
        return null;
    const result = value;
    if (typeof result.postId !== "string" || typeof result.eventId !== "string"
        || typeof result.kind !== "string" || typeof result.applied !== "boolean"
        || typeof result.radiusDeltaMeters !== "number" || !result.counters)
        return null;
    return result;
}
/**
 * The only client write path for post reach/counters. Authentication supplies
 * the actor; the transaction supplies the post owner, deltas, counters and
 * timestamps. Retrying the same event id returns the stored result without a
 * second increment.
 */
exports.recordPostEngagement = (0, https_1.onCall)({ region, timeoutSeconds: 15, memory: "256MiB" }, async (request) => {
    const uid = request.auth?.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in to react to a post.");
    let input;
    try {
        input = (0, postEngagementPolicy_1.parsePostEngagementInput)(request.data);
    }
    catch (error) {
        if (error instanceof postEngagementPolicy_1.PostEngagementValidationError) {
            throw new https_1.HttpsError("invalid-argument", error.message);
        }
        throw error;
    }
    const postRef = db.collection("posts").doc(input.postId);
    const eventRef = postRef.collection("engagements")
        .doc((0, postEngagementPolicy_1.postEngagementDocumentId)(uid, input.eventId));
    const actorStateRef = postRef.collection("engagementActors")
        .doc((0, postEngagementPolicy_1.postEngagementActorStateId)(uid));
    const actorRef = db.collection("users").doc(uid);
    const nowMillis = Date.now();
    return db.runTransaction(async (transaction) => {
        const eventSnapshot = await transaction.get(eventRef);
        if (eventSnapshot.exists) {
            const event = eventSnapshot.data() ?? {};
            if (event.actorUid !== uid || event.clientEventId !== input.eventId || event.kind !== input.kind) {
                throw new https_1.HttpsError("already-exists", "That engagement id belongs to another action.");
            }
            const result = storedResult(event.result);
            if (!result)
                throw new https_1.HttpsError("data-loss", "The stored engagement result is invalid.");
            return { ...result, duplicate: true };
        }
        const postSnapshot = await transaction.get(postRef);
        if (!postSnapshot.exists)
            throw new https_1.HttpsError("not-found", "Post not found.");
        const post = postSnapshot.data() ?? {};
        const ownerUid = postOwnerUid(post);
        if (!ownerUid || !publishedPost(post)) {
            throw new https_1.HttpsError("failed-precondition", "This post is not available for engagement.");
        }
        const actorStateSnapshot = await transaction.get(actorStateRef);
        const actorSnapshot = await transaction.get(actorRef);
        const lastViewAt = actorStateSnapshot.data()?.lastViewAt;
        const lastViewAtMillis = lastViewAt && typeof lastViewAt.toMillis === "function"
            ? Number(lastViewAt.toMillis())
            : null;
        const mutation = (0, postEngagementPolicy_1.calculatePostEngagementMutation)(post, input.kind, nowMillis, Number.isFinite(lastViewAtMillis) ? lastViewAtMillis : null);
        const result = {
            postId: input.postId,
            eventId: input.eventId,
            kind: input.kind,
            applied: mutation.applied,
            radiusDeltaMeters: mutation.radiusDeltaMeters,
            counters: mutation.counters,
        };
        if (mutation.applied) {
            transaction.update(postRef, {
                ...mutation.postUpdate,
                lastEngagementAt: firestore_1.FieldValue.serverTimestamp(),
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
        }
        if (mutation.nextViewAtMillis != null) {
            transaction.set(actorStateRef, {
                actorUid: uid,
                lastViewAt: firestore_1.Timestamp.fromMillis(mutation.nextViewAtMillis),
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            }, { merge: true });
        }
        transaction.create(eventRef, {
            actorUid: uid,
            actorHandle: actorHandle(actorSnapshot.data() ?? {}),
            postOwnerUid: ownerUid,
            clientEventId: input.eventId,
            kind: input.kind,
            applied: mutation.applied,
            radiusDeltaMeters: mutation.radiusDeltaMeters,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
            result,
        });
        return { ...result, duplicate: false };
    });
});
