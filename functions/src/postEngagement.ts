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
  buildRadiusHistoryEntry,
  radiusHistoryEntryId,
} from "./postEngagementPolicy";
import { radiusHistoryDocument, radiusHistoryRef } from "./radiusHistory";
import { addAccountClaimRadius, claimRadiusDeltaMeters } from "./accountRadius";

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
    return applyPostEngagement(uid, request.data);
  },
);

/** Shared transaction for authenticated app traffic and labelled scheduled testers. */
export async function applyPostEngagement(uid: string, data: unknown) {
    let input;
    try {
      input = parsePostEngagementInput(data);
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

      // A block has to reach the engagement path, and only this function can
      // carry it there. firestore.rules gates dmThreads, messages and calls,
      // but engagement runs THROUGH this callable with admin credentials, so
      // rules never see it — without this check a blocked person still lights
      // up your phone by liking or commenting, and every radius they move is
      // still theirs to move.
      //
      // Symmetric, matching the rules: either direction closes the channel.
      // Read inside the transaction, never from anything the caller sent.
      if (ownerUid !== uid) {
        const [ownerBlocksActor, actorBlocksOwner] = await Promise.all([
          transaction.get(db.collection("users").doc(ownerUid).collection("blocked").doc(uid)),
          transaction.get(db.collection("users").doc(uid).collection("blocked").doc(ownerUid)),
        ]);
        if (ownerBlocksActor.exists || actorBlocksOwner.exists) {
          throw new HttpsError("permission-denied", "This post is not available for engagement.");
        }
      }

      const actorStateSnapshot = await transaction.get(actorStateRef);
      const actorSnapshot = await transaction.get(actorRef);
      const actorState = actorStateSnapshot.data() ?? {};
      const lastViewAt = actorState.lastViewAt;
      const lastViewAtMillis = lastViewAt && typeof lastViewAt.toMillis === "function"
        ? Number(lastViewAt.toMillis())
        : null;
      const mutation = calculatePostEngagementMutation(
        post,
        input.kind,
        nowMillis,
        {
          lastViewAtMillis: Number.isFinite(lastViewAtMillis) ? lastViewAtMillis : null,
          liked: actorState.liked === true,
          disliked: actorState.disliked === true,
          commentGranted: actorState.commentGranted === true,
          paidRepeatViews: typeof actorState.paidRepeatViews === "number"
            ? actorState.paidRepeatViews
            : 0,
        },
        // The post's own author. Read from the stored document inside the
        // transaction, never from anything the caller sent.
        ownerUid === uid,
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
        // The owner's entitlement moves with the post that earned it, in the
        // transaction that earned it. firestore.rules cannot sum a collection,
        // so the create rule reads this aggregate instead — and an aggregate
        // written anywhere but here would be a second source of truth free to
        // drift away from the posts it claims to summarise.
        addAccountClaimRadius(
          transaction,
          db.collection("users").doc(ownerUid),
          claimRadiusDeltaMeters(
            mutation.previous.organicRadiusMeters,
            mutation.counters.organicRadiusMeters,
          ),
        );
        // The pop's history, written with the change it records. A comment
        // after the first pays 0 m and moves nothing: it stays out of the
        // curve so the history is a line of changes, not a log of taps.
        if (mutation.counters.radiusMeters !== mutation.previous.radiusMeters) {
          transaction.create(
            radiusHistoryRef(postRef, radiusHistoryEntryId.engagement(eventRef.id)),
            radiusHistoryDocument(buildRadiusHistoryEntry({
              atMillis: nowMillis,
              cause: "engagement",
              writer: "recordPostEngagement",
              previous: mutation.previous,
              next: mutation.counters,
              seedRadiusMeters: mutation.radius.seed,
              boostedRadiusMeters: mutation.radius.boost,
              kind: input.kind,
              engagementId: eventRef.id,
            })),
          );
        }
      }
      const persistViewAt = mutation.nextViewAtMillis != null;
      const persistGrants = Object.keys(mutation.actorStateUpdate).length > 0;
      if (persistViewAt || persistGrants) {
        transaction.set(actorStateRef, {
          actorUid: uid,
          ...(persistViewAt
            ? { lastViewAt: Timestamp.fromMillis(mutation.nextViewAtMillis as number) }
            : {}),
          // What this account has already been paid for on this post. Written
          // in the same transaction as the counters, so a concurrent double-tap
          // cannot be granted twice.
          ...mutation.actorStateUpdate,
          updatedAt: FieldValue.serverTimestamp(),
        }, { merge: true });
      }
      if (input.kind === "comment" && input.text) {
        transaction.create(postRef.collection("comments").doc(eventRef.id), {
          actorUid: uid, handle: actorHandle(actorSnapshot.data() ?? {}), text: input.text,
          synthetic: actorSnapshot.data()?.syntheticBeta === true,
          createdAt: FieldValue.serverTimestamp(),
        });
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
}
