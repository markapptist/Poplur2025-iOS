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
exports.ringIphoneCalls = exports.APNS_HOSTS = exports.VOIP_TOPIC = exports.APNS_TEAM_ID = void 0;
exports.voipTokens = voipTokens;
exports.voipPayload = voipPayload;
exports.apnsJwt = apnsJwt;
exports.isDeadToken = isDeadToken;
exports.sendVoip = sendVoip;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const firebase_functions_1 = require("firebase-functions");
const params_1 = require("firebase-functions/params");
const firestore_2 = require("firebase-functions/v2/firestore");
const node_crypto_1 = require("node:crypto");
const node_http2_1 = require("node:http2");
const callNotifications_1 = require("./callNotifications");
/**
 * Calls that ring a closed or locked iPhone (A7 in .codex/mvp-finish-plan.md,
 * the iPhone half; Android's is callNotifications.ts).
 *
 * Android rings from a high-priority FCM data message. An iPhone cannot: only a
 * PushKit VoIP push wakes a suspended or killed app, and iOS then requires the
 * app to show the call through CallKit at once (Poplur2025/PoplurCallKit.swift).
 * FCM cannot address PushKit tokens, so this talks to APNs directly, signed
 * with the team's APNs auth key (.p8).
 *
 * NOT exported from index.ts until that key exists, because binding a secret
 * Secret Manager does not hold fails the deploy. To switch it on:
 *   1. Mark: .codex/build-products/set-apns-key.sh ~/Downloads/AuthKey_<KEYID>.p8
 *   2. add `export { ringIphoneCalls } from "./callRingApple";` to index.ts, build
 *   3. Mark: .codex/build-products/deploy-functions.sh ringIphoneCalls
 *
 * Only a call that starts ringing is pushed. A VoIP push must always become a
 * CallKit call, so there is no cancel push: the phone watches the call
 * document while it rings and takes its own ringing screen down.
 */
const APNS_AUTH_KEY = (0, params_1.defineSecret)("APNS_AUTH_KEY");
const APNS_KEY_ID = (0, params_1.defineSecret)("APNS_KEY_ID");
exports.APNS_TEAM_ID = "VDQS4882Z8";
exports.VOIP_TOPIC = "com.apptist.Poplur2025.voip";
exports.APNS_HOSTS = {
    production: "https://api.push.apple.com",
    development: "https://api.sandbox.push.apple.com",
};
/**
 * The callee's iPhones. The app keeps them as
 * users/{uid}.voipTokens = { "<hex token>": { env: "production" | "development", updatedAt } };
 * a development-signed install only works against the sandbox.
 */
function voipTokens(user) {
    const entries = (user?.voipTokens ?? {});
    return Object.entries(entries)
        .filter(([token]) => /^(?:[0-9a-f]{2}){32,100}$/i.test(token))
        .map(([token, entry]) => ({
        token: token.toLowerCase(),
        env: entry?.env === "development" ? "development" : "production",
    }));
}
/** What CallKit needs to ring at once, before Firebase is even up; the phone
 *  also checks the call is for the account signed in on it. */
function voipPayload(data, calleeId) {
    return JSON.stringify({ aps: {}, ...data, calleeId });
}
const base64url = (input) => Buffer.from(input).toString("base64").replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
/** The ES256 provider token APNs authenticates every request with. */
function apnsJwt(p8, keyId, teamId, issuedAtSeconds) {
    const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId }));
    const claims = base64url(JSON.stringify({ iss: teamId, iat: issuedAtSeconds }));
    const signature = (0, node_crypto_1.sign)("sha256", Buffer.from(`${header}.${claims}`), { key: p8, dsaEncoding: "ieee-p1363" });
    return `${header}.${claims}.${base64url(signature)}`;
}
// Apple refuses a provider token older than an hour, and one replaced more often
// than every 20 minutes, so one is reused for 40.
const JWT_REUSE_SECONDS = 40 * 60;
let cachedJwt = null;
function providerToken(p8, keyId, nowMs) {
    const now = Math.floor(nowMs / 1000);
    if (cachedJwt && cachedJwt.keyId === keyId && now - cachedJwt.issuedAt < JWT_REUSE_SECONDS)
        return cachedJwt.jwt;
    const jwt = apnsJwt(p8, keyId, exports.APNS_TEAM_ID, now);
    cachedJwt = { keyId, issuedAt: now, jwt };
    return jwt;
}
/** APNs says this token will never ring anything: the app is gone, or the token
 *  is not this app's or this environment's. */
function isDeadToken(result) {
    return result.status === 410 ||
        (result.status === 400 && (result.reason === "BadDeviceToken" || result.reason === "DeviceTokenNotForTopic"));
}
function post(session, token, body, jwt, expirationSeconds) {
    return new Promise((resolve) => {
        const request = session.request({
            ":method": "POST",
            ":path": `/3/device/${token}`,
            "authorization": `bearer ${jwt}`,
            "apns-topic": exports.VOIP_TOPIC,
            "apns-push-type": "voip",
            "apns-priority": "10",
            // A phone that comes back online after the caller has given up must not ring.
            "apns-expiration": String(expirationSeconds),
            "content-type": "application/json",
        });
        let status = 0;
        let text = "";
        request.setEncoding("utf8");
        request.on("response", (headers) => {
            status = Number(headers[":status"] ?? 0);
        });
        request.on("data", (chunk) => {
            text += chunk;
        });
        request.on("end", () => {
            let reason;
            try {
                reason = text ? JSON.parse(text).reason : undefined;
            }
            catch {
                reason = undefined;
            }
            resolve({ token, status, reason });
        });
        request.on("error", (error) => resolve({ token, status: 0, reason: error.message }));
        request.setTimeout(10_000, () => {
            request.close();
            resolve({ token, status: 0, reason: "timeout" });
        });
        request.end(body);
    });
}
/** One HTTP/2 connection per APNs environment, one request per token. */
async function sendVoip(tokens, body, jwt, expirationSeconds, hosts = exports.APNS_HOSTS) {
    const results = [];
    for (const env of ["production", "development"]) {
        const group = tokens.filter((entry) => entry.env === env);
        if (group.length === 0)
            continue;
        const session = (0, node_http2_1.connect)(hosts[env]);
        // A refused connection also fails every request on it, which reports it.
        session.on("error", () => undefined);
        try {
            results.push(...await Promise.all(group.map((entry) => post(session, entry.token, body, jwt, expirationSeconds))));
        }
        finally {
            session.close();
        }
    }
    return results;
}
exports.ringIphoneCalls = (0, firestore_2.onDocumentWritten)({
    document: "calls/{callId}",
    region: "us-central1",
    memory: "256MiB",
    maxInstances: 3,
    secrets: [APNS_AUTH_KEY, APNS_KEY_ID],
}, async (event) => {
    const callId = event.params.callId;
    const push = (0, callNotifications_1.callPushFor)(callId, event.data?.before?.data(), event.data?.after?.data());
    if (!push || push.data.kind !== "incoming_call")
        return;
    if (admin.apps.length === 0)
        admin.initializeApp();
    const db = admin.firestore();
    // The create rule refuses a call between blocked accounts; this keeps a block
    // made after the call opened from ringing (as notifyOnCall does).
    const blocked = await db.collection("users").doc(push.calleeId)
        .collection("blocked").doc(push.data.callerId).get();
    if (blocked.exists) {
        firebase_functions_1.logger.info("iPhone ring skipped: the callee blocked the caller", { callId });
        return;
    }
    const userRef = db.collection("users").doc(push.calleeId);
    const tokens = voipTokens((await userRef.get()).data());
    if (tokens.length === 0) {
        firebase_functions_1.logger.info("iPhone ring skipped: no iPhone", { callId });
        return;
    }
    const now = Date.now();
    const jwt = providerToken(APNS_AUTH_KEY.value().trim(), APNS_KEY_ID.value().trim(), now);
    const results = await sendVoip(tokens, voipPayload(push.data, push.calleeId), jwt, Math.floor((now + push.ttlMs) / 1000));
    const dead = results.filter(isDeadToken).map((result) => result.token);
    if (dead.length > 0) {
        const updates = {};
        dead.forEach((token) => {
            updates[`voipTokens.${token}`] = firestore_1.FieldValue.delete();
        });
        await userRef.update(updates).catch(() => undefined);
    }
    const failures = results.filter((result) => result.status !== 200);
    firebase_functions_1.logger.info("iPhone ring sent", {
        callId,
        sent: results.length - failures.length,
        failed: failures.length,
        pruned: dead.length,
        reasons: [...new Set(failures.map((result) => `${result.status} ${result.reason ?? ""}`.trim()))],
    });
});
