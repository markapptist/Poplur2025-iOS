import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";

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

export const NOTIFICATION_PREFS_FIELD = "notificationPrefs";

/** Which switch governs a notification. Mirrors the device shells' own
 *  grouping, so a preference set here means the same thing on the phone. */
export type PrefGroup = "messages" | "engagement" | "radius";

export interface NotificationPrefs {
  /** Direct messages. */
  messages: boolean;
  /** Likes, views, dislikes and comments on your pops.
   *  `highlights` exists in the device enums but nothing defines what a
   *  highlight IS, so the server treats it as `every` rather than inventing a
   *  rule — see the note on normalisePrefs. */
  engagement: "every" | "off";
  /** Radius news. Already throttled to one push a day per person by the
   *  reservation in radiusLossNotifications; this turns it off entirely. */
  radius: "daily" | "off";
}

/** Absent means permissive. Every account that predates this feature has no
 *  field at all, and must keep behaving exactly as it did. */
export const DEFAULT_NOTIFICATION_PREFS: NotificationPrefs = Object.freeze({
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
export function normalisePrefs(stored: unknown): NotificationPrefs {
  const raw = (stored ?? {}) as Partial<Record<keyof NotificationPrefs, unknown>>;
  return {
    messages: raw.messages === false ? false : true,
    engagement: raw.engagement === "off" ? "off" : "every",
    radius: raw.radius === "off" ? "off" : "daily",
  };
}

/** Read the switches off a user document's data. */
export function prefsFromUser(userData: unknown): NotificationPrefs {
  const data = (userData ?? {}) as Record<string, unknown>;
  return normalisePrefs(data[NOTIFICATION_PREFS_FIELD]);
}

/** Whether a push in this group may be sent to this person. */
export function pushAllowed(prefs: NotificationPrefs, group: PrefGroup): boolean {
  if (group === "messages") return prefs.messages;
  if (group === "engagement") return prefs.engagement !== "off";
  return prefs.radius !== "off";
}

/** The write path, validated. Only the three known switches, only known
 *  values; anything else is refused rather than merged, so a typo in a client
 *  cannot park an unreadable value on the account. Partial updates are the
 *  point — a screen toggling one switch must not have to send the others. */
export function validatedPatch(input: unknown): Partial<NotificationPrefs> {
  const raw = (input ?? {}) as Record<string, unknown>;
  const patch: Partial<NotificationPrefs> = {};
  for (const [key, value] of Object.entries(raw)) {
    if (key === "messages") {
      if (typeof value !== "boolean") throw new HttpsError("invalid-argument", "messages must be true or false.");
      patch.messages = value;
    } else if (key === "engagement") {
      if (value !== "every" && value !== "off" && value !== "highlights") {
        throw new HttpsError("invalid-argument", "engagement must be every, highlights or off.");
      }
      patch.engagement = value === "off" ? "off" : "every";
    } else if (key === "radius") {
      if (value !== "daily" && value !== "off") throw new HttpsError("invalid-argument", "radius must be daily or off.");
      patch.radius = value;
    } else {
      throw new HttpsError("invalid-argument", `Unknown notification preference: ${key}`);
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
export const notificationPreferences = onCall(
  { region: "us-central1", timeoutSeconds: 15 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in to Poplur.");
    // Find the DEFAULT app by name. `apps.length` is not the same question:
    // verifying this request's bearer token makes firebase-functions create its
    // own private app, so the count is already 1 by the time we get here and a
    // count-based guard skips the init it needed to do. See appPresence.ts.
    if (!admin.apps.some((app) => app?.name === "[DEFAULT]")) admin.initializeApp();
    const db = admin.firestore();
    const ref = db.collection("users").doc(request.auth.uid);

    const patch = validatedPatch((request.data ?? {}).set);
    if (Object.keys(patch).length > 0) {
      // Merge the one field, never the document: this path must not be able to
      // touch fcmTokens, radius, or anything else living on the account.
      const update: Record<string, unknown> = {};
      for (const [key, value] of Object.entries(patch)) update[`${NOTIFICATION_PREFS_FIELD}.${key}`] = value;
      await ref.set({ [NOTIFICATION_PREFS_FIELD]: patch }, { merge: true });
    }

    const snapshot = await ref.get();
    return { prefs: prefsFromUser(snapshot.data()) };
  },
);
