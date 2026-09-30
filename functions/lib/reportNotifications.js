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
exports.notifyOnReport = exports.REPORT_PUSH_COOLDOWN_MS = exports.REPORT_MODERATOR_UIDS = void 0;
exports.reportSummary = reportSummary;
exports.withinCooldown = withinCooldown;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const firebase_functions_1 = require("firebase-functions");
const firestore_2 = require("firebase-functions/v2/firestore");
const syntheticIdentity_1 = require("./syntheticIdentity");
if (admin.apps.length === 0)
    admin.initializeApp();
/**
 * Who hears about each new report. The owner accounts review reports: the App
 * Store (guideline 1.2) and Google Play's user-generated-content policy both
 * expect reports of people and pops to reach someone who acts on them.
 */
exports.REPORT_MODERATOR_UIDS = syntheticIdentity_1.DESK_OWNER_UIDS;
/** A second report from the same person inside this window does not push again. */
exports.REPORT_PUSH_COOLDOWN_MS = 10 * 60 * 1000;
const text = (value) => (typeof value === "string" ? value.trim() : "");
/** The push a moderator sees. Names the reported account and, for a pop, says so. */
function reportSummary(report) {
    const handle = text(report.username).replace(/^@+/, "");
    const who = handle ? `@${handle}` : "An account";
    const subject = text(report.postId) ? `A pop by ${handle ? `@${handle}` : "an account"}` : who;
    const reason = text(report.reason);
    const body = reason ? `${subject} was reported: ${reason}.` : `${subject} was reported.`;
    return { title: "New report on Poplur", body: body.length > 180 ? `${body.slice(0, 177)}…` : body };
}
function millis(value) {
    if (value && typeof value.toMillis === "function") {
        return value.toMillis();
    }
    return null;
}
/** True when the same reporter already filed a report inside the cooldown. */
function withinCooldown(otherReportTimes, now) {
    return otherReportTimes.some((time) => time !== null && now - time >= 0 && now - time < exports.REPORT_PUSH_COOLDOWN_MS);
}
exports.notifyOnReport = (0, firestore_2.onDocumentCreated)({ document: "reports/{reportId}", region: "us-central1" }, async (event) => {
    const report = event.data?.data();
    if (!report)
        return;
    const reportId = event.params.reportId;
    const reporterId = text(report.reporterId);
    const db = admin.firestore();
    // One push per reporter per window, so a burst of reports cannot flood the
    // moderators' phones. Every report is still stored in `reports`.
    if (reporterId) {
        const earlier = await db.collection("reports").where("reporterId", "==", reporterId).limit(25).get();
        const times = earlier.docs.filter((doc) => doc.id !== reportId).map((doc) => millis(doc.get("createdAt")));
        if (withinCooldown(times, Date.now())) {
            firebase_functions_1.logger.info("Report stored; push skipped inside the cooldown", { reportId });
            return;
        }
    }
    const { title, body } = reportSummary(report);
    for (const moderatorUid of exports.REPORT_MODERATOR_UIDS) {
        const userRef = db.collection("users").doc(moderatorUid);
        const tokens = Object.keys((((await userRef.get()).data() ?? {}).fcmTokens ?? {}));
        if (tokens.length === 0)
            continue;
        const response = await admin.messaging().sendEachForMulticast({
            tokens,
            notification: { title, body },
            data: { kind: "report", reportId },
            apns: { payload: { aps: { sound: "poplur_pop.wav" } } },
        });
        // Drop tokens the messaging service says will never work again.
        const dead = response.responses
            .map((result, index) => ({ result, token: tokens[index] }))
            .filter(({ result }) => !result.success && [
            "messaging/registration-token-not-registered",
            "messaging/invalid-registration-token",
        ].includes(result.error?.code ?? ""))
            .map(({ token }) => token);
        for (const token of dead) {
            await userRef.update(new firestore_1.FieldPath("fcmTokens", token), firestore_1.FieldValue.delete()).catch(() => undefined);
        }
        firebase_functions_1.logger.info("Report push sent", { reportId, moderatorUid, sent: response.successCount, dead: dead.length });
    }
});
