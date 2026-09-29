import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { prefsFromUser, pushAllowed } from "./notificationPrefs";

if (admin.apps.length === 0) admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

interface DirectMessage {
  senderId?: string;
  text?: string;
  kind?: "text" | "image" | "video" | "audio";
}

interface TokenEntry {
  platform?: string;
}

function preview(message: DirectMessage): string {
  if (message.kind === "image") return "Sent a photo";
  if (message.kind === "video") return "Sent a video";
  if (message.kind === "audio") return "Sent a voice message";
  const sticker = /^\[\[poplur:sticker:([a-z]+)\]\]$/.exec(message.text?.trim() ?? "");
  if (sticker) return "Sent a Poplur sticker";
  const text = message.text?.trim() ?? "";
  return text.length > 140 ? `${text.slice(0, 137)}…` : text || "Sent a message";
}

export const notifyOnDirectMessage = onDocumentCreated(
  {
    document: "dmThreads/{threadId}/messages/{messageId}",
    region: "us-central1",
  },
  async (event) => {
    const message = event.data?.data() as DirectMessage | undefined;
    const senderId = message?.senderId;
    if (!message || !senderId) return;

    const { threadId, messageId } = event.params;
    const threadSnapshot = await db.collection("dmThreads").doc(threadId).get();
    const thread = threadSnapshot.data();
    const participants = Array.isArray(thread?.participants)
      ? thread.participants.filter((value): value is string => typeof value === "string")
      : [];
    const recipientId = participants.find((uid) => uid !== senderId);
    if (!recipientId || !participants.includes(senderId)) {
      logger.warn("DM notification has no valid recipient", { threadId, messageId, senderId });
      return;
    }

    const [senderSnapshot, recipientSnapshot] = await Promise.all([
      db.collection("users").doc(senderId).get(),
      db.collection("users").doc(recipientId).get(),
    ]);
    const sender = senderSnapshot.data() ?? {};
    const participantNames = thread?.participantNames as Record<string, unknown> | undefined;
    const senderName = (typeof participantNames?.[senderId] === "string" && participantNames[senderId])
      || (typeof sender.username === "string" && sender.username)
      || (typeof sender.displayName === "string" && sender.displayName)
      || "Someone on Poplur";
    // Muting messages stops the push; the thread and its unread state are
    // untouched, so nothing is lost — only the interruption.
    if (!pushAllowed(prefsFromUser(recipientSnapshot.data()), "messages")) return;
    const tokenMap = (recipientSnapshot.data()?.fcmTokens ?? {}) as Record<string, TokenEntry>;
    const notificationId = `dm:${threadId}:${messageId}`;
    const messagePreview = preview(message);

    // Persist before checking for a device token. A person with notifications
    // disabled—or no registered phone yet—still owns a complete in-app inbox
    // when they next sign in.
    await db.collection("users").doc(recipientId)
      .collection("notifications").doc(notificationId)
      .set({
        id: notificationId,
        kind: "dm",
        actorUid: senderId,
        actorHandle: String(senderName),
        title: String(senderName),
        detail: messagePreview,
        createdAt: FieldValue.serverTimestamp(),
        isUnread: true,
        isDismissed: false,
        threadId,
        messageId,
      }, { merge: true });

    const tokens = Object.keys(tokenMap);
    if (tokens.length === 0) {
      logger.info("DM recipient has no registered devices", { threadId, messageId, recipientId });
      return;
    }

    const response = await messaging.sendEachForMulticast({
      tokens,
      notification: { title: String(senderName), body: messagePreview },
      data: {
        kind: "dm",
        threadId,
        messageId,
        senderId,
        notificationId,
      },
      apns: {
        payload: {
          aps: {
            "thread-id": threadId,
            sound: "poplur_pop.wav",
          },
        },
      },
      android: {
        priority: "high",
        notification: {
          channelId: "poplur_alerts_pop_v2",
          sound: "poplur_pop",
          tag: threadId,
          clickAction: "com.apptists.poplur2025.OPEN_DM",
        },
      },
    });

    const dead: string[] = [];
    response.responses.forEach((result, index) => {
      const code = result.error?.code;
      if (code === "messaging/registration-token-not-registered"
        || code === "messaging/invalid-registration-token") {
        dead.push(tokens[index]);
      }
    });
    if (dead.length > 0) {
      const updates: Record<string, unknown> = {};
      dead.forEach((token) => { updates[`fcmTokens.${token}`] = FieldValue.delete(); });
      await db.collection("users").doc(recipientId).update(updates);
    }

    logger.info("DM notification sent", {
      threadId,
      messageId,
      recipientId,
      sent: response.successCount,
      failed: response.failureCount,
      pruned: dead.length,
    });
  },
);
