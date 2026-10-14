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
exports.betaInstallsOnUserDeleted = exports.betaInstallsOnUserCreated = exports.INSTALLS_VERSION = exports.INSTALLS_DOC = void 0;
exports.countBetaInstalls = countBetaInstalls;
exports.publishBetaInstalls = publishBetaInstalls;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-functions/v2/firestore");
const betaScorecard_1 = require("./betaScorecard");
const syntheticIdentity_1 = require("./syntheticIdentity");
/**
 * The live installs count the landing page shows (Mark, 10 Oct 2026: "I want
 * installs, not emails sent — this is for YC to see"). ONE world-readable
 * document, `public/betaInstalls`, rewritten the moment an account's
 * `users/{uid}` profile is created or deleted, so the number on poplur.ca
 * moves in real time and costs nothing while nothing happens — unlike the
 * scorecard, which runs on a (paused) 15-minute schedule.
 *
 * An install is a HUMAN Firebase Auth account — the desk's `real` class,
 * never owner, review or synthetic — created on or after the scorecard's
 * window start (testControl/betaScorecard.startAtMillis, else the default).
 * Counts and dates only; no uid or email leaves this function.
 */
exports.INSTALLS_DOC = "public/betaInstalls";
exports.INSTALLS_VERSION = 1;
const millisOf = (value) => {
    const n = Number(value);
    if (Number.isFinite(n) && n > 0)
        return n;
    const stamp = value;
    const ms = typeof stamp?.toMillis === "function" ? Number(stamp.toMillis()) : NaN;
    return Number.isFinite(ms) && ms > 0 ? ms : 0;
};
async function countBetaInstalls(db, nowMillis = Date.now()) {
    const config = (await db.doc(betaScorecard_1.SCORECARD_CONFIG_DOC).get()).data() ?? {};
    const startMillis = millisOf(config.startAtMillis ?? config.startAt) || betaScorecard_1.DEFAULT_WINDOW_START_MILLIS;
    const accounts = [];
    let pageToken;
    do {
        const page = await admin.auth().listUsers(1000, pageToken);
        for (const u of page.users)
            accounts.push({ uid: u.uid, email: u.email ?? "", createdAtMillis: Date.parse(u.metadata.creationTime ?? "") || 0 });
        pageToken = page.pageToken;
    } while (pageToken);
    const inWindow = accounts.filter(a => a.createdAtMillis >= startMillis);
    let installs = 0;
    for (let i = 0; i < inWindow.length; i += 100) {
        const part = inWindow.slice(i, i + 100);
        const snaps = await db.getAll(...part.map(a => db.collection("users").doc(a.uid)));
        snaps.forEach((s, j) => {
            const profile = s.data() ?? {};
            if ((0, syntheticIdentity_1.actorClass)(part[j].uid, profile, part[j].email || profile.email || "", s.exists) === "real")
                installs += 1;
        });
    }
    return { version: exports.INSTALLS_VERSION, installs, startMillis, updatedAtMillis: nowMillis };
}
async function publishBetaInstalls(db) {
    const count = await countBetaInstalls(db);
    await db.doc(exports.INSTALLS_DOC).set(count, { merge: true });
    return count;
}
const trigger = { document: "users/{uid}", region: "us-central1", memory: "256MiB", cpu: "gcf_gen1", concurrency: 1, maxInstances: 2 };
exports.betaInstallsOnUserCreated = (0, firestore_1.onDocumentCreated)(trigger, async () => { await publishBetaInstalls(admin.firestore()); });
exports.betaInstallsOnUserDeleted = (0, firestore_1.onDocumentDeleted)(trigger, async () => { await publishBetaInstalls(admin.firestore()); });
