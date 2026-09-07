import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { FieldValue } from "firebase-admin/firestore";

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

export type EngagementKind = "like" | "view" | "dislike" | "comment";

export interface EngagementDoc {
  actorUid?: string;
  actorHandle?: string;
  kind?: EngagementKind;
  postOwnerUid?: string;
  body?: string;
  applied?: boolean;
  radiusDeltaMeters?: number;
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
            sound: "default",
          },
        },
      },
      android: {
        priority: "high",
        notification: {
          channelId: "poplur_alerts",
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
