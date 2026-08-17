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

const db = admin.firestore();
const messaging = admin.messaging();

/** Likes inside this window collapse into one digest instead of one each. */
const LIKE_COALESCE_WINDOW_MS = 5 * 60 * 1000;

type EngagementKind = "like" | "view" | "comment";

interface EngagementDoc {
  actorUid?: string;
  actorHandle?: string;
  kind?: EngagementKind;
  postOwnerUid?: string;
  body?: string;
}

interface TokenEntry {
  platform?: string;
}

/**
 * Decides whether this engagement notifies, and with what copy.
 *
 * Views never notify. Instagram does not notify per view, and radius is the
 * product here -- a post reaching thousands of people is the GOAL, so per-view
 * notifications would scale exactly with success and turn the feature into a
 * pager. Views are still recorded and still appear in the in-app list; they
 * just do not light up the phone.
 *
 * Likes coalesce; comments never do. A comment is a conversation and a delayed
 * one reads as broken, whereas a like is an applause count and reads fine
 * summarised.
 */
async function resolveNotification(
  postId: string,
  engagement: EngagementDoc,
): Promise<{ title: string; body: string } | null> {
  const handle = engagement.actorHandle?.trim() || "Someone";

  if (engagement.kind === "view") return null;

  if (engagement.kind === "comment") {
    const comment = engagement.body?.trim();
    return {
      title: `${handle} commented`,
      body: comment && comment.length > 0 ? comment : "commented on your post",
    };
  }

  if (engagement.kind !== "like") return null;

  // Coalescing state lives on the post so the trigger needs one document, and
  // the transaction makes concurrent likes safe: two arriving at once cannot
  // both decide they are the first in the window.
  const postRef = db.collection("posts").doc(postId);
  const decision = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(postRef);
    const data = snapshot.data() ?? {};
    const lastNotifyAt: number = data.likeNotifyAt ?? 0;
    const pending: number = data.likesPendingNotify ?? 0;
    const now = Date.now();

    if (now - lastNotifyAt >= LIKE_COALESCE_WINDOW_MS) {
      // Window is open. Send now, and carry any likes that accumulated while it
      // was closed -- this is also what flushes them, so no scheduled function
      // is needed to drain the backlog.
      tx.set(
        postRef,
        { likeNotifyAt: now, likesPendingNotify: 0 },
        { merge: true },
      );
      return { send: true, alsoPending: pending };
    }

    tx.set(
      postRef,
      { likesPendingNotify: FieldValue.increment(1) },
      { merge: true },
    );
    return { send: false, alsoPending: 0 };
  });

  if (!decision.send) return null;

  if (decision.alsoPending > 0) {
    return {
      title: "Your post is popping",
      body: `${handle} and ${decision.alsoPending} other${decision.alsoPending === 1 ? "" : "s"} liked your post`,
    };
  }
  return { title: `${handle} liked your post`, body: "Tap to see it" };
}

export const notifyOnEngagement = onDocumentCreated(
  {
    document: "posts/{postId}/engagements/{engagementId}",
    region: "us-central1",
  },
  async (event) => {
    const engagement = event.data?.data() as EngagementDoc | undefined;
    if (!engagement) return;

    const { postId, engagementId } = event.params;
    const ownerUid = engagement.postOwnerUid;
    if (!ownerUid) {
      logger.warn("engagement has no postOwnerUid", { postId, engagementId });
      return;
    }

    // Never notify someone about their own action on their own post.
    if (engagement.actorUid === ownerUid) return;

    const notification = await resolveNotification(postId, engagement);
    if (!notification) return; // a view, or a like inside the coalesce window

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
