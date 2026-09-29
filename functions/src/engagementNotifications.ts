import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { isSyntheticAccount } from "./syntheticIdentity";
import { STUDENT_DEMO_EVENT_PREFIX } from "./studentDemoPolicy";
import { prefsFromUser, pushAllowed } from "./notificationPrefs";

/**
 * Phase 3 of engagement push notifications: turn a new engagement document into
 * a banner on the post owner's devices.
 *
 * Triggered by `posts/{postId}/engagements/{engagementId}`. Tokens come from
 * `users/{uid}.fcmTokens`, written by PoplurMessaging on both platforms as a map
 * keyed by token, which is what lets a dead token be deleted here without a
 * read-modify-write race against a device registering at the same moment.
 */

// This module reaches for Firestore and Messaging at import time, and
// index.ts re-exports it — ES re-exports evaluate BEFORE the importing
// module's own body, so index's initializeApp() had not run yet and deploy
// analysis died with app/no-app. Guarded so it is safe wherever it loads
// first, and safe to call again.
if (admin.apps.length === 0) admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

/** BETA PHASE (owner decision, 12 Sep 2026): a bot's attention is not news.
 *  The synthetic cohort is the only thing engaging right now, and because
 *  syntheticDailySimulation runs every 60 minutes and writes its whole batch at
 *  once — while this trigger fires per engagement document with no coalescing —
 *  it landed 32 banners on the owner's phone on the hour, every hour (804 in a
 *  day). Simulation engagement no longer notifies: no push, and no inbox row
 *  either, since a notification nobody should see is not worth storing.
 *
 *  Deliberately NOT suppressed anywhere else: the engagement documents
 *  themselves are untouched, so the Test Center desk and the algorithm digest
 *  still count every simulated view and comment. Only the human-facing alert
 *  goes away. Flip this to true to watch the simulation land on a device again.
 *  Real testers were never affected — they are not synthetic. */
export const NOTIFY_FOR_SYNTHETIC_ENGAGEMENT = false;

export type EngagementKind = "like" | "view" | "dislike" | "comment";

export interface EngagementDoc {
  actorUid?: string;
  actorHandle?: string;
  kind?: EngagementKind;
  postOwnerUid?: string;
  body?: string;
  applied?: boolean;
  radiusDeltaMeters?: number;
  clientEventId?: string;
}

interface TokenEntry { platform?: string; }

/** Only server-applied activity notifies. View/like deduplication already lives
 * in recordPostEngagement; do not silently drop its accepted events here. */
export function engagementNotification(engagement: EngagementDoc): { title: string; body: string; detail: string } | null {
  if (engagement.applied !== true || !engagement.kind) return null;
  const handle = engagement.actorHandle?.trim() || "Someone";
  const verb = { like: "liked your post", view: "viewed your post", dislike: "disliked your post", comment: "commented on your post" }[engagement.kind ?? "like"];
  if (!verb) return null;
  const meters = engagement.radiusDeltaMeters;
  const radius = typeof meters === "number" && Number.isFinite(meters) && meters !== 0
    ? `Radius ${meters > 0 ? "grew" : "decreased"} ${Number((Math.abs(meters) / 1000).toFixed(3))} km.`
    : "";
  const comment = engagement.kind === "comment" ? engagement.body?.trim() : "";
  return {
    title: `${handle} ${verb}`,
    body: [comment, radius].filter(Boolean).join(" ") || "Tap to see your post",
    detail: [verb, comment, radius].filter(Boolean).join(" · "),
  };
}

/** Whether an engagement came from a simulation account.
 *
 *  The uid-prefix rule in isSyntheticAccount answers for every cohort and lab
 *  actor (`sim-`, `synthetic-`) with no read at all, which is the overwhelming
 *  majority; only a sim-daily account that announces itself through a flag or a
 *  poplur.test mailbox costs the users/{uid} lookup.
 *
 *  An engagement with no actorUid is NOT treated as synthetic: we cannot tell,
 *  and silently dropping a real person's alert is the worse failure. Same rule
 *  if the lookup throws — fail open and notify, exactly as before this gate. */
export async function engagementIsSynthetic(actorUid: string | undefined): Promise<boolean> {
  if (!actorUid) return false;
  if (isSyntheticAccount(actorUid, null, null)) return true;
  try {
    const profile = (await db.collection("users").doc(actorUid).get()).data();
    return isSyntheticAccount(actorUid, profile, typeof profile?.email === "string" ? profile.email : null);
  } catch (error) {
    logger.warn("could not classify engagement actor; notifying", { actorUid, error });
    return false;
  }
}

export const notifyOnEngagement = onDocumentCreated(
  {
    document: "posts/{postId}/engagements/{engagementId}",
    region: "us-central1",
  },
  async (event) => {
    const engagement = event.data?.data() as EngagementDoc | undefined;
    if (!engagement) return;
    const notification = engagementNotification(engagement);
    if (!notification) return;

    const { postId, engagementId } = event.params;
    const ownerUid = engagement.postOwnerUid;
    if (!ownerUid) {
      logger.warn("engagement has no postOwnerUid", { postId, engagementId });
      return;
    }

    // Never notify someone about their own action on their own post.
    if (engagement.actorUid === ownerUid) return;

    // A bot's view is not news — see NOTIFY_FOR_SYNTHETIC_ENGAGEMENT. Checked
    // before the row is written, so the inbox stays as quiet as the lock screen.
    // This also stops the cohort notifying ITSELF: bot-to-bot engagement was
    // writing ~1,300 notification rows every three hours to accounts that hold
    // no device tokens and will never read them.
    // The student demo responder is the one synthetic source that MUST reach
    // a phone: its reactions exist so a student feels the app answer. Its
    // engagement ids carry the demo prefix, and its targets are real accounts
    // by construction (studentDemoResponder.ts), so the hourly simulation's
    // batch stays as silent as before.
    const studentDemo = typeof engagement.clientEventId === "string" && engagement.clientEventId.startsWith(STUDENT_DEMO_EVENT_PREFIX);
    if (!NOTIFY_FOR_SYNTHETIC_ENGAGEMENT && !studentDemo && await engagementIsSynthetic(engagement.actorUid)) {
      logger.debug("synthetic engagement, not notifying", { postId, engagementId, actorUid: engagement.actorUid });
      return;
    }

    // Stable event identity makes redelivery preserve read/dismiss state.
    const notificationId = `engagement:${postId}:${engagementId}`;
    const actorHandle = engagement.actorHandle?.trim() || "Someone";
    const created = await db.collection("users").doc(ownerUid)
      .collection("notifications").doc(notificationId)
      .create({
        id: notificationId,
        kind: engagement.kind ?? "like",
        actorUid: engagement.actorUid ?? "",
        actorHandle,
        title: actorHandle,
        detail: notification.detail,
        radiusDeltaMeters: engagement.radiusDeltaMeters ?? 0,
        createdAt: FieldValue.serverTimestamp(),
        isUnread: true,
        isDismissed: false,
        postId,
        engagementId,
      }).then(() => true).catch((error: { code?: number }) => {
        if (error.code !== 6) throw error; // ALREADY_EXISTS: keep the original row.
        return false;
      });

    if (!created) return;

    const userSnapshot = await db.collection("users").doc(ownerUid).get();
    // The row above is written either way. This switch governs the PUSH: not
    // being interrupted about views is not the same as not wanting to see them.
    // Free to read — we already have the document for its tokens.
    if (!pushAllowed(prefsFromUser(userSnapshot.data()), "engagement")) {
      logger.debug("engagement push muted by preference", { ownerUid, postId, engagementId });
      return;
    }
    const tokenMap = (userSnapshot.data()?.fcmTokens ?? {}) as Record<string, TokenEntry>;
    const tokens = Object.keys(tokenMap);
    if (tokens.length === 0) {
      logger.info("no registered devices for owner", { ownerUid, postId });
      return;
    }

    const response = await messaging.sendEachForMulticast({
      tokens,
      notification: { title: notification.title, body: notification.body },
      data: {
        // Everything the client needs to open the post with the engagement lit,
        // and to build the matching in-app row. All values must be strings.
        postId,
        engagementId,
        notificationId,
        kind: engagement.kind ?? "",
        actorHandle: engagement.actorHandle ?? "",
      },
      apns: {
        payload: {
          aps: {
            // One thread per post, so many engagements on the same post group
            // in Notification Center instead of stacking as unrelated banners.
            "thread-id": postId,
            sound: "poplur_pop.wav",
          },
        },
      },
      android: {
        priority: "high",
        notification: {
          channelId: "poplur_alerts_pop_v2",
          sound: "poplur_pop",
          tag: postId,
        },
      },
    });

    // Prune tokens FCM says are dead. Deleting by key needs no read and cannot
    // clobber a token another device registered a moment ago -- the reason the
    // map is keyed by token rather than being an array.
    const dead: string[] = [];
    response.responses.forEach((result, index) => {
      const code = result.error?.code;
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token"
      ) {
        dead.push(tokens[index]);
      }
    });
    if (dead.length > 0) {
      const updates: Record<string, unknown> = {};
      dead.forEach((token) => {
        updates[`fcmTokens.${token}`] = FieldValue.delete();
      });
      await db.collection("users").doc(ownerUid).update(updates);
    }

    logger.info("engagement notification sent", {
      postId,
      engagementId,
      kind: engagement.kind,
      sent: response.successCount,
      failed: response.failureCount,
      pruned: dead.length,
    });
  },
);
