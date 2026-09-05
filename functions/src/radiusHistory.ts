import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import {
  RADIUS_HISTORY_COLLECTION,
  buildRadiusHistoryEntry,
  postRadiusParts,
  radiusHistoryEntryId,
  type RadiusHistoryEntry,
} from "./postEngagementPolicy";

if (admin.apps.length === 0) admin.initializeApp();

/**
 * A pop has a history: posts/{postId}/radiusHistory holds one entry per change
 * to its reach, from the moment it was posted to now. Every server writer that
 * moves a radius appends its own entry in the same transaction or batch
 * (recordPostEngagement, radiusDecay, the boost and publish endpoints, the
 * synthetic runner); this module holds the shared plumbing and the ONE entry
 * no writer can add atomically — the first point of a post a client created.
 *
 * Clients cannot write the subcollection (firestore.rules: read public like the
 * post, write never), so the creation point of an RN/iOS/Android post lands
 * here, seconds after the post, stamped with the post's own createdAtMillis.
 * That is the honest first point: the clock is the post's, and nothing can
 * engage with a post before it exists.
 */

export function radiusHistoryRef(
  postRef: admin.firestore.DocumentReference,
  entryId: string,
): admin.firestore.DocumentReference {
  return postRef.collection(RADIUS_HISTORY_COLLECTION).doc(entryId);
}

/** The stored form: the pure entry plus a server Timestamp for ordering and TTL. */
export function radiusHistoryDocument(entry: RadiusHistoryEntry): Record<string, unknown> {
  return { ...entry, at: Timestamp.fromMillis(entry.atMillis) };
}

function createdAtMillisOf(post: Record<string, unknown>, fallbackMillis: number): number {
  const declared = Number(post.createdAtMillis);
  if (Number.isFinite(declared) && declared > 0) return declared;
  const stamp = post.createdAt as { toMillis?: () => number } | undefined;
  const millis = typeof stamp?.toMillis === "function" ? Number(stamp.toMillis()) : NaN;
  return Number.isFinite(millis) && millis > 0 ? millis : fallbackMillis;
}

/** The first point of a post as its document declares it. */
export function creationHistoryEntry(
  post: Record<string, unknown>,
  fallbackMillis: number,
  writer: string,
): RadiusHistoryEntry {
  const atMillis = createdAtMillisOf(post, fallbackMillis);
  const parts = postRadiusParts(post, atMillis);
  return buildRadiusHistoryEntry({
    atMillis,
    cause: "create",
    writer,
    previous: null,
    next: { radiusMeters: parts.total, organicRadiusMeters: parts.organic },
    seedRadiusMeters: parts.seed,
    boostedRadiusMeters: parts.boost,
  });
}

export const radiusHistoryOnPostCreated = onDocumentCreated(
  { document: "posts/{postId}", region: "us-central1" },
  async event => {
    const snapshot = event.data;
    if (!snapshot) return;
    const post = snapshot.data() ?? {};
    const eventMillis = Date.parse(event.time);
    const entry = creationHistoryEntry(
      post,
      Number.isFinite(eventMillis) ? eventMillis : Date.now(),
      "radiusHistoryOnPostCreated",
    );
    try {
      await radiusHistoryRef(snapshot.ref, radiusHistoryEntryId.create()).create(radiusHistoryDocument(entry));
    } catch (error) {
      // A server writer that created the post in a batch already wrote its
      // own 'create' point, and at-least-once delivery can run this twice:
      // both are the same document, so an existing one is the finished state.
      if ((error as { code?: number }).code !== 6) throw error;
    }
  },
);
