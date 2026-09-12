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
exports.notificationPreferences = exports.DEFAULT_NOTIFICATION_PREFS = exports.NOTIFICATION_PREFS_FIELD = void 0;
exports.normalisePrefs = normalisePrefs;
exports.prefsFromUser = prefsFromUser;
exports.pushAllowed = pushAllowed;
exports.validatedPatch = validatedPatch;
const admin = __importStar(require("firebase-admin"));
const https_1 = require("firebase-functions/v2/https");
/**
 * What a person has asked to be told about.
 *
 * The device shells have carried these gates for a long time
 * (Notifications+Names.swift, PoplurNotifications.kt) but the only screen that
 * could set them is orphaned, so they sat at their defaults, unsettable — which
 * is why an 804-a-day engagement burst had to be stopped in a deploy instead of
 * by tapping a switch. The preference lives on the account here, not on the
 * device: it survives a reinstall, and it reaches every phone the person signs
 * in on. The device gates stay where they are as a second line, and still own
 * the things only a device can know — sound, and what a foreground app draws.
 *
 * These gate the PUSH ONLY. The Notifications screen keeps showing everything:
 * "stop buzzing my phone about views" is not "hide views from me", and a row
 * nobody was interrupted for is still the record of what happened. (The one
 * thing that suppresses the row as well is simulation engagement, which nobody
 * should be told about at all — see NOTIFY_FOR_SYNTHETIC_ENGAGEMENT.)
 *
 * Reading them is free: all three senders already fetch the recipient's user
 * document for `fcmTokens`, and this rides on that same read.
 */
exports.NOTIFICATION_PREFS_FIELD = "notificationPrefs";
/** Absent means permissive. Every account that predates this feature has no
 *  field at all, and must keep behaving exactly as it did. */
exports.DEFAULT_NOTIFICATION_PREFS = Object.freeze({
    messages: true,
    engagement: "every",
    radius: "daily",
});
/**
 * A stored value, read back safely. Anything malformed falls back to the
 * permissive default for that one switch rather than the whole set, so a bad
 * write can never silence an account wholesale.
 *
 * `highlights` — a legal value in the iOS enum — normalises to `every`. The
 * device may still batch on its own; the server sends, because nothing anywhere
 * says which engagements are the highlights, and guessing would drop real
 * notifications under a name that promised fewer, not none.
 */
function normalisePrefs(stored) {
    const raw = (stored ?? {});
    return {
        messages: raw.messages === false ? false : true,
        engagement: raw.engagement === "off" ? "off" : "every",
        radius: raw.radius === "off" ? "off" : "daily",
    };
}
/** Read the switches off a user document's data. */
function prefsFromUser(userData) {
    const data = (userData ?? {});
    return normalisePrefs(data[exports.NOTIFICATION_PREFS_FIELD]);
}
/** Whether a push in this group may be sent to this person. */
function pushAllowed(prefs, group) {
    if (group === "messages")
        return prefs.messages;
    if (group === "engagement")
        return prefs.engagement !== "off";
    return prefs.radius !== "off";
}
/** The write path, validated. Only the three known switches, only known
 *  values; anything else is refused rather than merged, so a typo in a client
 *  cannot park an unreadable value on the account. Partial updates are the
 *  point — a screen toggling one switch must not have to send the others. */
function validatedPatch(input) {
    const raw = (input ?? {});
    const patch = {};
    for (const [key, value] of Object.entries(raw)) {
        if (key === "messages") {
            if (typeof value !== "boolean")
                throw new https_1.HttpsError("invalid-argument", "messages must be true or false.");
            patch.messages = value;
        }
        else if (key === "engagement") {
            if (value !== "every" && value !== "off" && value !== "highlights") {
                throw new https_1.HttpsError("invalid-argument", "engagement must be every, highlights or off.");
            }
            patch.engagement = value === "off" ? "off" : "every";
        }
        else if (key === "radius") {
            if (value !== "daily" && value !== "off")
                throw new https_1.HttpsError("invalid-argument", "radius must be daily or off.");
            patch.radius = value;
        }
        else {
            throw new https_1.HttpsError("invalid-argument", `Unknown notification preference: ${key}`);
        }
    }
    return patch;
}
/**
 * Read the switches, or change some of them.
 *
 * Called with no `set` it simply answers with the current state, which is what
 * the Settings screen opens on — a screen that rendered defaults while the
 * account said otherwise would lie about what the person had chosen.
 */
exports.notificationPreferences = (0, https_1.onCall)({ region: "us-central1", timeoutSeconds: 15 }, async (request) => {
    if (!request.auth)
        throw new https_1.HttpsError("unauthenticated", "Sign in to Poplur.");
    // Find the DEFAULT app by name. `apps.length` is not the same question:
    // verifying this request's bearer token makes firebase-functions create its
    // own private app, so the count is already 1 by the time we get here and a
    // count-based guard skips the init it needed to do. See appPresence.ts.
    if (!admin.apps.some((app) => app?.name === "[DEFAULT]"))
        admin.initializeApp();
    const db = admin.firestore();
    const ref = db.collection("users").doc(request.auth.uid);
    const patch = validatedPatch((request.data ?? {}).set);
    if (Object.keys(patch).length > 0) {
        // Merge the one field, never the document: this path must not be able to
        // touch fcmTokens, radius, or anything else living on the account.
        const update = {};
        for (const [key, value] of Object.entries(patch))
            update[`${exports.NOTIFICATION_PREFS_FIELD}.${key}`] = value;
        await ref.set({ [exports.NOTIFICATION_PREFS_FIELD]: patch }, { merge: true });
    }
    const snapshot = await ref.get();
    return { prefs: prefsFromUser(snapshot.data()) };
});
