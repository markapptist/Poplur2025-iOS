import * as admin from "firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import {
  PostEngagementValidationError,
  calculatePostEngagementMutation,
  parsePostEngagementInput,
  postEngagementActorStateId,
  postEngagementDocumentId,
  type PostEngagementCounters,
} from "./postEngagementPolicy";

if (admin.apps.length === 0) admin.initializeApp();

const db = admin.firestore();
const region = "us-central1";

interface StoredEngagementResult {
  postId: string;
  eventId: string;
  kind: "view" | "like" | "dislike" | "comment";
  applied: boolean;
  radiusDeltaMeters: number;
  counters: PostEngagementCounters;
}

function boundedText(value: unknown, maximum: number): string {
  return typeof value === "string" ? value.trim().replace(/\s+/g, " ").slice(0, maximum) : "";
}

function postOwnerUid(post: Record<string, unknown>): string {
  return boundedText(post.ownerId ?? post.userID ?? post.userId, 128);
}

function publishedPost(post: Record<string, unknown>): boolean {
  const audience = boundedText(post.audience, 24).toLowerCase();
  const status = boundedText(post.visibilityStatus ?? post.status, 24).toLowerCase();
  return (!audience || audience === "public")
    && (!status || status === "published" || status === "live");
}

function actorHandle(user: Record<string, unknown>): string {
  const value = boundedText(user.username ?? user.handle ?? user.displayName, 40);
  if (!value) return "";
  return value.startsWith("@") ? value : `@${value}`;
}

function storedResult(value: unknown): StoredEngagementResult | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const result = value as Partial<StoredEngagementResult>;
  if (typeof result.postId !== "string" || typeof result.eventId !== "string"
    || typeof result.kind !== "string" || typeof result.applied !== "boolean"
    || typeof result.radiusDeltaMeters !== "number" || !result.counters) return null;
  return result as StoredEngagementResult;
}

/**
 * The only client write path for post reach/counters. Authentication supplies
 * the actor; the transaction supplies the post owner, deltas, counters and
 * timestamps. Retrying the same event id returns the stored result without a
 * second increment.
 */
export const recordPostEngagement = onCall(
  { region, timeoutSeconds: 15, memory: "256MiB" },
  async request => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in to react to a post.");

    let input;
    try {
      input = parsePostEngagementInput(request.data);
    } catch (error) {
      if (error instanceof PostEngagementValidationError) {
        throw new HttpsError("invalid-argument", error.message);
      }
      throw error;
    }

    const postRef = db.collection("posts").doc(input.postId);
    const eventRef = postRef.collection("engagements")
      .doc(postEngagementDocumentId(uid, input.eventId));
    const actorStateRef = postRef.collection("engagementActors")
      .doc(postEngagementActorStateId(uid));
    const actorRef = db.collection("users").doc(uid);
    const nowMillis = Date.now();

    return db.runTransaction(async transaction => {
      const eventSnapshot = await transaction.get(eventRef);
      if (eventSnapshot.exists) {
        const event = eventSnapshot.data() ?? {};
        if (event.actorUid !== uid || event.clientEventId !== input.eventId || event.kind !== input.kind) {
          throw new HttpsError("already-exists", "That engagement id belongs to another action.");
        }
        const result = storedResult(event.result);
        if (!result) throw new HttpsError("data-loss", "The stored engagement result is invalid.");
        return { ...result, duplicate: true };
      }

      const postSnapshot = await transaction.get(postRef);
      if (!postSnapshot.exists) throw new HttpsError("not-found", "Post not found.");
      const post = postSnapshot.data() ?? {};
      const ownerUid = postOwnerUid(post);
      if (!ownerUid || !publishedPost(post)) {
        throw new HttpsError("failed-precondition", "This post is not available for engagement.");
      }

      const actorStateSnapshot = await transaction.get(actorStateRef);
      const actorSnapshot = await transaction.get(actorRef);
      const lastViewAt = actorStateSnapshot.data()?.lastViewAt;
      const lastViewAtMillis = lastViewAt && typeof lastViewAt.toMillis === "function"
        ? Number(lastViewAt.toMillis())
        : null;
      const mutation = calculatePostEngagementMutation(
        post,
        input.kind,
        nowMillis,
        Number.isFinite(lastViewAtMillis) ? lastViewAtMillis : null,
      );
      const result: StoredEngagementResult = {
        postId: input.postId,
        eventId: input.eventId,
        kind: input.kind,
        applied: mutation.applied,
        radiusDeltaMeters: mutation.radiusDeltaMeters,
        counters: mutation.counters,
      };

      if (mutation.applied) {
        transaction.update(postRef, {
          ...mutation.postUpdate,
          lastEngagementAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      if (mutation.nextViewAtMillis != null) {
        transaction.set(actorStateRef, {
          actorUid: uid,
          lastViewAt: Timestamp.fromMillis(mutation.nextViewAtMillis),
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      transaction.create(eventRef, {
        actorUid: uid,
        actorHandle: actorHandle(actorSnapshot.data() ?? {}),
        postOwnerUid: ownerUid,
        clientEventId: input.eventId,
        kind: input.kind,
        applied: mutation.applied,
        radiusDeltaMeters: mutation.radiusDeltaMeters,
        createdAt: FieldValue.serverTimestamp(),
        result,
      });
      return { ...result, duplicate: false };
    });
  },
);
