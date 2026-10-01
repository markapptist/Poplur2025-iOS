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
exports.notifyOnCall = exports.RING_TTL_MS = void 0;
exports.callPushFor = callPushFor;
exports.androidTokens = androidTokens;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const firebase_functions_1 = require("firebase-functions");
const firestore_2 = require("firebase-functions/v2/firestore");
/**
 * Calls that ring when Poplur is closed (A7 in .codex/mvp-finish-plan.md).
 *
 * The web page owns every call (clay-map webCall.ts), and while Poplur is open
 * the app's own listener rings for it. With Poplur closed nothing listens, so
 * when a WebRTC call starts ringing this sends the callee's Android devices a
 * high-priority DATA message. Unlike a notification payload, it reaches the app
 * even when the app was killed, and the app draws its own incoming-call screen
 * (Android IncomingCallNotifier.kt). When the call stops ringing (answered,
 * declined, hung up or timed out) a cancel takes that screen down.
 *
 * iPhones ring through PushKit and CallKit, which need VoIP pushes signed with
 * an APNs key; their tokens are left out until that exists.
 */
const REGION = "us-central1";
/** The caller gives up after 45 s (webCall.ts OUTGOING_NO_ANSWER_MS). */
exports.RING_TTL_MS = 45_000;
function text(value, max) {
    return typeof value === "string" ? value.trim().slice(0, max) : "";
}
function isRinging(call) {
    return call?.status === "ringing" && call?.provider === "webrtc";
}
/** What a write to calls/{callId} should push, if anything. */
function callPushFor(callId, before, after) {
    if (after && isRinging(after) && !isRinging(before)) {
        const calleeId = text(after.calleeId, 128);
        const callerId = text(after.callerId, 128);
        if (!calleeId || !callerId || calleeId === callerId)
            return null;
        return {
            calleeId,
            ttlMs: exports.RING_TTL_MS,
            data: {
                kind: "incoming_call",
                callId,
                callerId,
                callerName: text(after.callerName, 80) || "Someone",
                video: after.video === true ? "true" : "false",
                context: text(after.context, 40) || "default",
            },
        };
    }
    if (before && isRinging(before) && !isRinging(after)) {
        const calleeId = text(before.calleeId, 128);
        if (!calleeId)
            return null;
        return {
            calleeId,
            ttlMs: exports.RING_TTL_MS,
            data: { kind: "call_cancel", callId, status: text(after?.status, 20) || "ended" },
        };
    }
    return null;
}
/** The callee's Android devices. iPhones wait for CallKit (see the header). */
function androidTokens(user) {
    const tokens = (user?.fcmTokens ?? {});
    return Object.entries(tokens)
        .filter(([token, entry]) => token.length > 0 && entry?.platform === "android")
        .map(([token]) => token);
}
exports.notifyOnCall = (0, firestore_2.onDocumentWritten)({ document: "calls/{callId}", region: REGION, memory: "512MiB", maxInstances: 3 }, async (event) => {
    const callId = event.params.callId;
    const push = callPushFor(callId, event.data?.before?.data(), event.data?.after?.data());
    if (!push)
        return;
    if (admin.apps.length === 0)
        admin.initializeApp();
    const db = admin.firestore();
    if (push.data.kind === "incoming_call") {
        // The create rule refuses a call between blocked accounts; this keeps a
        // block made after the call opened from ringing.
        const blocked = await db.collection("users").doc(push.calleeId)
            .collection("blocked").doc(push.data.callerId).get();
        if (blocked.exists) {
            firebase_functions_1.logger.info("call not rung: the callee blocked the caller", { callId });
            return;
        }
    }
    const userRef = db.collection("users").doc(push.calleeId);
    const tokens = androidTokens((await userRef.get()).data());
    if (tokens.length === 0) {
        firebase_functions_1.logger.info("call push skipped: no Android device", { callId, kind: push.data.kind });
        return;
    }
    const response = await admin.messaging().sendEachForMulticast({
        tokens,
        data: push.data,
        android: { priority: "high", ttl: push.ttlMs },
    });
    const dead = [];
    response.responses.forEach((result, index) => {
        const code = result.error?.code;
        if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") {
            dead.push(tokens[index]);
        }
    });
    if (dead.length > 0) {
        const updates = {};
        dead.forEach((token) => {
            updates[`fcmTokens.${token}`] = firestore_1.FieldValue.delete();
        });
        await userRef.update(updates).catch(() => undefined);
    }
    firebase_functions_1.logger.info("call push sent", {
        callId,
        kind: push.data.kind,
        sent: response.successCount,
        failed: response.failureCount,
        pruned: dead.length,
    });
});
