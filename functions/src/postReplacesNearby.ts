import * as admin from "firebase-admin";
import { FieldValue, Firestore, Timestamp } from "firebase-admin/firestore";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { postOwnerUid } from "./accountRadius";
import { MAX_POST_RADIUS_METERS, buildRadiusHistoryEntry, postRadiusParts } from "./postEngagementPolicy";
import { radiusHistoryDocument, radiusHistoryRef } from "./radiusHistory";

/**
 * One live pop per place, per person.
 *
 * Owner rule 18 Sep 2026: a pop posted within 5 km — the discovery seed — of
 * one of the owner's own live pops REPLACES it. The old pop expires (reach
 * zero, hidden everywhere an expired pop is hidden) and the new pop inherits
 * the earned reach the old one held, so posting again from the same campus is
 * an update, not a penalty. Nothing is minted: the account's live reach is the
 * same before and after, and the claim the old pop had out comes back to the
 * allowance through accountTotalRadiusOnPostWritten like any expiry.
 *
 * Server-side because a client could skip it; redelivery-safe because a
 * replaced pop is no longer live and is not found the second time. The
 * composer warns before publishing (poplur-clay-map ownPops.ts) — this is the
 * rule, that is the courtesy.
 */
export const NEARBY_OWN_POP_METERS = 5_000;
export const REPLACED_EXPIRY_REASON = "replaced-by-nearby-pop";

type Post = Record<string, unknown>;
interface Candidate { id: string; data: Post }

function finite(value: unknown): number | null {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

export function haversineMeters(
  a: { latitude: number; longitude: number },
  b: { latitude: number; longitude: number },
): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(b.latitude - a.latitude);
  const dLng = toRad(b.longitude - a.longitude);
  const h = Math.sin(dLat / 2) ** 2
    + Math.cos(toRad(a.latitude)) * Math.cos(toRad(b.latitude)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6_371_000 * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** A pop's public origin; hidden origins have none and take part in nothing. */
export function postOrigin(post: Post): { latitude: number; longitude: number } | null {
  if (post.locationVisibility === "hidden") return null;
  const latitude = finite(post.latitude);
  const longitude = finite(post.longitude);
  if (latitude === null || longitude === null) return null;
  if (Math.abs(latitude) > 90 || Math.abs(longitude) > 180) return null;
  return { latitude, longitude };
}

export function isLivePost(post: Post): boolean {
  if (post.visibilityStatus === "expired" || post.status === "deleted" || post.deleted === true) return false;
  return (finite(post.radiusMeters ?? post.radius) ?? 0) > 0;
}

function createdAtMillisOf(post: Post): number | null {
  const declared = finite(post.createdAtMillis);
  if (declared !== null && declared > 0) return declared;
  const stamp = post.createdAt as { toMillis?: () => number } | undefined;
  const millis = typeof stamp?.toMillis === "function" ? Number(stamp.toMillis()) : NaN;
  return Number.isFinite(millis) && millis > 0 ? millis : null;
}

/**
 * Pure: which of `candidates` the new pop replaces — the same owner's OTHER
 * live pops with a public origin within 5 km, created no later than it.
 * Ordering by creation keeps two pops written in the same second from
 * replacing each other (the later one wins; equal stamps fall to id order).
 */
export function nearbyOwnPops(post: Candidate, candidates: readonly Candidate[]): Candidate[] {
  const owner = postOwnerUid(post.data);
  const here = postOrigin(post.data);
  if (!owner || !here || !isLivePost(post.data)) return [];
  const createdAt = createdAtMillisOf(post.data);
  return candidates.filter(candidate => {
    if (candidate.id === post.id || postOwnerUid(candidate.data) !== owner) return false;
    if (!isLivePost(candidate.data)) return false;
    const there = postOrigin(candidate.data);
    if (!there || haversineMeters(here, there) > NEARBY_OWN_POP_METERS) return false;
    const theirs = createdAtMillisOf(candidate.data);
    if (createdAt !== null && theirs !== null) {
      if (theirs > createdAt) return false;
      if (theirs === createdAt && candidate.id > post.id) return false;
    }
    return true;
  });
}

/** Apply the rule for one just-created post. Returns the replaced ids. */
export async function replaceNearbyOwnPops(
  db: Firestore,
  postId: string,
  nowMillis = Date.now(),
): Promise<string[]> {
  const postRef = db.collection("posts").doc(postId);
  return db.runTransaction(async tx => {
    const snapshot = await tx.get(postRef);
    const post = snapshot.data();
    if (!snapshot.exists || !post) return [];
    const owner = postOwnerUid(post);
    if (!owner || !postOrigin(post) || !isLivePost(post)) return [];
    // The officialContent seed layer is ambient world-radius content, not a
    // person's pop: one owner (PoplurTest) holds dozens of seeds a few hundred
    // metres apart by design, so the one-live-pop-per-place rule neither
    // applies to a new seed nor lets any pop expire an existing seed.
    if (post.officialContent === true) return [];
    const own = await tx.get(db.collection("posts").where("userID", "==", owner));
    const replaced = nearbyOwnPops(
      { id: postId, data: post },
      own.docs.map(doc => ({ id: doc.id, data: doc.data() })).filter(doc => doc.data.officialContent !== true),
    );
    if (replaced.length === 0) return [];

    let inherited = 0;
    for (const old of replaced) {
      const parts = postRadiusParts(old.data, nowMillis);
      inherited += parts.organic;
      const oldRef = db.collection("posts").doc(old.id);
      tx.update(oldRef, {
        visibilityStatus: "expired",
        expiredAt: Timestamp.fromMillis(nowMillis),
        expiryReason: REPLACED_EXPIRY_REASON,
        replacedByPostId: postId,
        radiusMeters: 0, radius: 0,
        organicRadiusMeters: 0, seedRadiusMeters: 0, boostedRadiusMeters: 0,
        updatedAt: FieldValue.serverTimestamp(),
      });
      tx.set(radiusHistoryRef(oldRef, `replaced_${postId}`), radiusHistoryDocument(buildRadiusHistoryEntry({
        atMillis: nowMillis, cause: "replaced", writer: "postReplacesNearbyOwnPops",
        previous: { radiusMeters: parts.total, organicRadiusMeters: parts.organic },
        next: { radiusMeters: 0, organicRadiusMeters: 0 },
        seedRadiusMeters: 0, boostedRadiusMeters: 0,
      })));
    }
    const before = postRadiusParts(post, nowMillis);
    const organic = Math.min(MAX_POST_RADIUS_METERS, before.organic + inherited);
    const total = Math.min(MAX_POST_RADIUS_METERS, organic + before.seed + before.boost);
    tx.update(postRef, {
      organicRadiusMeters: organic, radiusMeters: total, radius: total,
      replacedPostIds: FieldValue.arrayUnion(...replaced.map(old => old.id)),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (inherited > 0) {
      tx.set(radiusHistoryRef(postRef, `inherited_${nowMillis}`), radiusHistoryDocument(buildRadiusHistoryEntry({
        atMillis: nowMillis, cause: "inherited", writer: "postReplacesNearbyOwnPops",
        previous: { radiusMeters: before.total, organicRadiusMeters: before.organic },
        next: { radiusMeters: total, organicRadiusMeters: organic },
        seedRadiusMeters: before.seed, boostedRadiusMeters: before.boost,
      })));
    }
    return replaced.map(old => old.id);
  });
}

if (admin.apps.length === 0) admin.initializeApp();
// 512 MiB: the whole codebase loads for every function and a NEW function at
// the 256 MiB default is OOM-killed before it logs (11 Sep 2026, nearbyPopsDigest).
export const postReplacesNearbyOwnPops = onDocumentCreated(
  { document: "posts/{postId}", region: "us-central1", retry: true, memory: "512MiB", cpu: 1 },
  async event => { await replaceNearbyOwnPops(admin.firestore(), event.params.postId); },
);
