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
exports.appPresence = exports.COUNT_SYNTHETIC_TESTERS = exports.PRESENCE_COLLECTION = exports.PRESENCE_LEASE_MS = void 0;
exports.presenceInput = presenceInput;
exports.countPresentPeople = countPresentPeople;
exports.updateAppPresence = updateAppPresence;
const admin = __importStar(require("firebase-admin"));
const node_crypto_1 = require("node:crypto");
const https_1 = require("firebase-functions/v2/https");
// A foreground lease, not analytics: no screen, location, device, or content.
// Clients renew once a minute. Crashes/disconnects expire after two minutes.
exports.PRESENCE_LEASE_MS = 120_000;
exports.PRESENCE_COLLECTION = "appPresenceSessions";
function presenceInput(data) {
    if (typeof data.session !== "string" || !/^[a-zA-Z0-9-]{16,80}$/.test(data.session)
        || !Number.isSafeInteger(data.sequence) || Number(data.sequence) < 1
        || typeof data.active !== "boolean") {
        throw new https_1.HttpsError("invalid-argument", "Invalid presence lease.");
    }
    return { session: data.session, sequence: Number(data.sequence), active: data.active };
}
/** BETA PHASE: there are no human testers yet, so the synthetic cohort is the
 *  audience the algorithm is being built against, and ONLINE NOW counts them
 *  (owner decision, 11 Sep 2026). Flip to `false` when humans arrive in the
 *  next testing phase and the number goes back to people only. The Test Center
 *  desk (testActivity.ts) has always counted actors apart and is unaffected. */
exports.COUNT_SYNTHETIC_TESTERS = true;
function countPresentPeople(rows, now, countSynthetic = exports.COUNT_SYNTHETIC_TESTERS) {
    return new Set(rows.filter(row => typeof row.uid === "string" && row.uid.length > 0
        && (countSynthetic || row.synthetic !== true) && typeof row.activeUntilMs === "number"
        && row.activeUntilMs > now && row.activeUntilMs <= now + exports.PRESENCE_LEASE_MS)
        .map(row => row.uid)).size;
}
/** Exported seam also used by the emulator test; identity comes from auth only. */
async function updateAppPresence(db, uid, synthetic, data, now = Date.now()) {
    const input = presenceInput(data);
    const key = (0, node_crypto_1.createHash)("sha256").update(`${uid}:${input.session}`).digest("hex");
    const ref = db.collection(exports.PRESENCE_COLLECTION).doc(key);
    await db.runTransaction(async (transaction) => {
        const existing = await transaction.get(ref);
        // An old foreground request arriving after background must not revive it.
        if (Number(existing.data()?.sequence ?? 0) >= input.sequence)
            return;
        transaction.set(ref, {
            uid, synthetic, sequence: input.sequence,
            activeUntil: admin.firestore.Timestamp.fromMillis(input.active ? now + exports.PRESENCE_LEASE_MS : now),
            // Retain the sequence briefly to reject delayed requests. TTL is cleanup
            // only; the query below expires leases even before Firestore removes them.
            expiresAt: admin.firestore.Timestamp.fromMillis(now + 24 * 60 * 60 * 1000),
        });
    });
    const asOfMs = Date.now();
    const snapshot = await db.collection(exports.PRESENCE_COLLECTION)
        .where("activeUntil", ">", admin.firestore.Timestamp.fromMillis(asOfMs))
        .select("uid", "synthetic", "activeUntil").get();
    const peopleOnline = countPresentPeople(snapshot.docs.map(doc => ({
        uid: doc.data().uid, synthetic: doc.data().synthetic,
        activeUntilMs: doc.data().activeUntil?.toMillis?.(),
    })), asOfMs);
    // Never expose the private identities or individual online states.
    return { peopleOnline, asOfMs, validForMs: exports.PRESENCE_LEASE_MS };
}
exports.appPresence = (0, https_1.onCall)({ region: "us-central1", timeoutSeconds: 15 }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in to Poplur.");
    // Look for the DEFAULT app by name, never by `apps.length`. Verifying this
    // request's bearer token made firebase-functions create its own private app
    // ("__FIREBASE_FUNCTIONS_SDK__") when no default existed — so by the time
    // this line ran, `apps.length` was already 1, the guard skipped
    // initializeApp(), and admin.firestore() threw "default app does not
    // exist" on every authenticated call. index.ts normally initialises the
    // default first, but this function has shipped as an isolated stub without
    // it, which is exactly the case the count-based guard cannot survive.
    if (!admin.apps.some(app => app?.name === "[DEFAULT]"))
        admin.initializeApp();
    return updateAppPresence(admin.firestore(), request.auth.uid, request.auth.token.syntheticBeta === true, request.data ?? {});
});
