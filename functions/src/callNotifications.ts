import * as admin from "firebase-admin";
import { DocumentData, FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";

/**
 * Calls that ring when Poplur is closed (A7 in .codex/mvp-finish-plan.md).
 *
 * The web page owns every call (clay-map webCall.ts), and while Poplur is open
 * the app's own listener rings for it. With Poplur closed nothing listens, so
 * when a WebRTC call starts ringing this sends the callee's Android devices a
 * high-priority DATA message. Unlike a notification payload, it reaches the app
 * even when the app was killed, and the app draws its own incoming-call screen
 * (Android IncomingCallNotifier.kt). When the call stops ringing (answered,
 * declined, hung up or timed out) a cancel takes that screen down.
 *
 * iPhones ring through PushKit and CallKit, which need VoIP pushes signed with
 * an APNs key; their tokens are left out until that exists.
 */

const REGION = "us-central1";
/** The caller gives up after 45 s (webCall.ts OUTGOING_NO_ANSWER_MS). */
export const RING_TTL_MS = 45_000;

export interface CallPush {
  calleeId: string;
  ttlMs: number;
  data: Record<string, string>;
}

function text(value: unknown, max: number): string {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}

function isRinging(call: DocumentData | undefined): boolean {
  return call?.status === "ringing" && call?.provider === "webrtc";
}

/** What a write to calls/{callId} should push, if anything. */
export function callPushFor(
  callId: string,
  before: DocumentData | undefined,
  after: DocumentData | undefined
): CallPush | null {
  if (after && isRinging(after) && !isRinging(before)) {
    const calleeId = text(after.calleeId, 128);
    const callerId = text(after.callerId, 128);
    if (!calleeId || !callerId || calleeId === callerId) return null;
    return {
      calleeId,
      ttlMs: RING_TTL_MS,
      data: {
        kind: "incoming_call",
        callId,
        callerId,
        callerName: text(after.callerName, 80) || "Someone",
        video: after.video === true ? "true" : "false",
        context: text(after.context, 40) || "default",
      },
    };
  }
  if (before && isRinging(before) && !isRinging(after)) {
    const calleeId = text(before.calleeId, 128);
    if (!calleeId) return null;
    return {
      calleeId,
      ttlMs: RING_TTL_MS,
      data: { kind: "call_cancel", callId, status: text(after?.status, 20) || "ended" },
    };
  }
  return null;
}

/** The callee's Android devices. iPhones wait for CallKit (see the header). */
export function androidTokens(user: DocumentData | undefined): string[] {
  const tokens = (user?.fcmTokens ?? {}) as Record<string, { platform?: unknown } | undefined>;
  return Object.entries(tokens)
    .filter(([token, entry]) => token.length > 0 && entry?.platform === "android")
    .map(([token]) => token);
}

export const notifyOnCall = onDocumentWritten(
  { document: "calls/{callId}", region: REGION, memory: "512MiB", maxInstances: 3 },
  async (event) => {
    const callId = event.params.callId;
    const push = callPushFor(callId, event.data?.before?.data(), event.data?.after?.data());
    if (!push) return;
    if (admin.apps.length === 0) admin.initializeApp();
    const db = admin.firestore();

    if (push.data.kind === "incoming_call") {
      // The create rule refuses a call between blocked accounts; this keeps a
      // block made after the call opened from ringing.
      const blocked = await db.collection("users").doc(push.calleeId)
        .collection("blocked").doc(push.data.callerId).get();
      if (blocked.exists) {
        logger.info("call not rung: the callee blocked the caller", { callId });
        return;
      }
    }

    const userRef = db.collection("users").doc(push.calleeId);
    const tokens = androidTokens((await userRef.get()).data());
    if (tokens.length === 0) {
      logger.info("call push skipped: no Android device", { callId, kind: push.data.kind });
      return;
    }

    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      data: push.data,
      android: { priority: "high", ttl: push.ttlMs },
    });

    const dead: string[] = [];
    response.responses.forEach((result, index) => {
      const code = result.error?.code;
      if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") {
        dead.push(tokens[index]);
      }
    });
    if (dead.length > 0) {
      const updates: Record<string, unknown> = {};
      dead.forEach((token) => {
        updates[`fcmTokens.${token}`] = FieldValue.delete();
      });
      await userRef.update(updates).catch(() => undefined);
    }

    logger.info("call push sent", {
      callId,
      kind: push.data.kind,
      sent: response.successCount,
      failed: response.failureCount,
      pruned: dead.length,
    });
  }
);
