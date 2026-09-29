import * as admin from "firebase-admin";
import { FieldValue, Firestore } from "firebase-admin/firestore";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { POST_DISCOVERY_SEED_METERS, postEarnedRadiusMeters, postOwnerUid } from "./accountRadius";
import { MAX_POST_RADIUS_METERS } from "./postEngagementPolicy";

/** Σ full displayed radius over the account's posts — the PROFILE number only.
 *  It used to be the create ceiling too (7 Sep–17 Sep 2026): because seeds
 *  count in it, every drop could claim the sum of every drop before it, and
 *  thirteen posts with no engagement reached the world radius. */
export const ACCOUNT_TOTAL_RADIUS_FIELD = "totalPostRadiusMeters";
/** Σ earned (organic) radius over live posts — the ground other people gave
 *  this account. The only thing a claim may draw on. */
export const ACCOUNT_EARNED_CLAIM_FIELD = "earnedClaimMeters";
/** Σ (seed − 5 km) over live posts — the claims already sitting on pops. A
 *  claim is spent while its pop lives and comes back when the pop is deleted
 *  or its seed decays; it is never reused while it is out. */
export const ACCOUNT_COMMITTED_CLAIM_FIELD = "committedClaimMeters";
export const ACCOUNT_TOTAL_CONTRIBUTIONS = "accountPostRadiusContributions";

/** Post-rate state the create rule reads: one post a minute, thirty a rolling
 *  day. Counted from the trigger's own clock on the first sighting of a post,
 *  never from the document's createdAt, which a modified client may forge. */
export const POST_RATE_WINDOW_MS = 86_400_000;
export const POST_RATE_FIELDS = Object.freeze({
  lastPostAt: "lastPostAtMillis",
  windowStart: "postWindowStartMillis",
  count: "postsInWindow",
});

function finite(value: unknown): number | null {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function boundedMeters(value: unknown): number {
  const parsed = finite(value);
  return parsed === null ? 0 : Math.round(Math.max(0, Math.min(MAX_POST_RADIUS_METERS, parsed)));
}

function isLive(post: Record<string, unknown>): boolean {
  return post.visibilityStatus !== "expired" && postTotalRadiusMeters(post) > 0;
}

/** Match the profile's sum: each current post contributes its full displayed radius. */
export function postTotalRadiusMeters(post: Record<string, unknown>): number {
  return boundedMeters(post.radiusMeters ?? post.radius ?? 0);
}

/** What a live post has earned; an expired or empty one holds nothing. Same
 *  reading as the web picker (accountRadiusPosts.ts) and postEarnedRadiusMeters. */
export function postEarnedClaimMeters(post: Record<string, unknown>): number {
  return isLive(post) ? postEarnedRadiusMeters(post) : 0;
}

/** The claim a live post is holding: its seed above the free discovery grant,
 *  never more than its live reach (decay shrinks the seed in step). */
export function postCommittedClaimMeters(post: Record<string, unknown>): number {
  if (!isLive(post)) return 0;
  const seed = Math.min(boundedMeters(post.seedRadiusMeters), postTotalRadiusMeters(post));
  return Math.max(0, seed - POST_DISCOVERY_SEED_METERS);
}

export interface PostRateState {
  lastPostAtMillis?: unknown;
  postWindowStartMillis?: unknown;
  postsInWindow?: unknown;
}

/** Pure step of the post-rate window for a post first seen at `nowMillis`. */
export function nextPostRate(current: PostRateState, nowMillis: number): {
  lastPostAtMillis: number; postWindowStartMillis: number; postsInWindow: number;
} {
  const last = finite(current.lastPostAtMillis) ?? 0;
  const start = finite(current.postWindowStartMillis);
  const count = finite(current.postsInWindow) ?? 0;
  const lastPostAtMillis = Math.max(last, nowMillis);
  if (start === null || nowMillis - start >= POST_RATE_WINDOW_MS) {
    return { lastPostAtMillis, postWindowStartMillis: nowMillis, postsInWindow: 1 };
  }
  return { lastPostAtMillis, postWindowStartMillis: start, postsInWindow: Math.max(0, Math.round(count)) + 1 };
}

export interface ReconcileOptions {
  /** false for backfills: existing posts are not "posted now". */
  countPostRate?: boolean;
  nowMillis?: number;
}

/** Read current state, not an event snapshot: duplicate and out-of-order events
 * converge on the same contributions. Deletion and owner changes remove the old
 * contribution in the same transaction that installs the new one. */
export async function reconcileAccountPostRadius(
  db: Firestore,
  postId: string,
  options: ReconcileOptions = {},
): Promise<void> {
  const countPostRate = options.countPostRate !== false;
  const postRef = db.collection("posts").doc(postId);
  const receiptRef = db.collection(ACCOUNT_TOTAL_CONTRIBUTIONS).doc(postId);
  await db.runTransaction(async tx => {
    const [post, receipt] = await Promise.all([tx.get(postRef), tx.get(receiptRef)]);
    const previous = receipt.data();
    const current = post.data();
    const oldOwner = typeof previous?.ownerUid === "string" ? previous.ownerUid : "";
    const old = {
      radius: finite(previous?.radiusMeters) ?? 0,
      earned: finite(previous?.earnedMeters) ?? 0,
      claim: finite(previous?.claimMeters) ?? 0,
    };
    const ownerUid = current ? postOwnerUid(current) : "";
    const deletingOwners = new Set<string>();
    for (const uid of new Set([oldOwner, ownerUid].filter(Boolean))) {
      if ((await tx.get(db.collection("accountDeletions").doc(uid))).exists) deletingOwners.add(uid);
    }
    const next = current && ownerUid
      ? { radius: postTotalRadiusMeters(current), earned: postEarnedClaimMeters(current), claim: postCommittedClaimMeters(current) }
      : { radius: 0, earned: 0, claim: 0 };
    const firstSighting = !receipt.exists && !!current && !!ownerUid;
    // Reads before writes: the rate window needs the owner's current state.
    const rate = firstSighting && countPostRate
      ? nextPostRate((await tx.get(db.collection("users").doc(ownerUid))).data() ?? {}, options.nowMillis ?? Date.now())
      : null;
    if (oldOwner === ownerUid && old.radius === next.radius && old.earned === next.earned
      && old.claim === next.claim && receipt.exists && !rate) return;
    const deltas = new Map<string, { radius: number; earned: number; claim: number }>();
    const add = (uid: string, sign: 1 | -1, v: { radius: number; earned: number; claim: number }) => {
      const row = deltas.get(uid) ?? { radius: 0, earned: 0, claim: 0 };
      row.radius += sign * v.radius; row.earned += sign * v.earned; row.claim += sign * v.claim;
      deltas.set(uid, row);
    };
    if (oldOwner) add(oldOwner, -1, old);
    if (ownerUid) add(ownerUid, 1, next);
    for (const [uid, delta] of deltas) {
      if (deletingOwners.has(uid)) continue;
      const update: Record<string, unknown> = {};
      if (delta.radius !== 0) update[ACCOUNT_TOTAL_RADIUS_FIELD] = FieldValue.increment(delta.radius);
      if (delta.earned !== 0) update[ACCOUNT_EARNED_CLAIM_FIELD] = FieldValue.increment(delta.earned);
      if (delta.claim !== 0) update[ACCOUNT_COMMITTED_CLAIM_FIELD] = FieldValue.increment(delta.claim);
      if (uid === ownerUid && rate) Object.assign(update, rate);
      if (Object.keys(update).length === 0) continue;
      update.totalPostRadiusUpdatedAt = FieldValue.serverTimestamp();
      tx.set(db.collection("users").doc(uid), update, { merge: true });
    }
    if (deletingOwners.has(ownerUid) || (!ownerUid && deletingOwners.has(oldOwner))) {
      tx.delete(receiptRef);
      return;
    }
    tx.set(receiptRef, {
      ownerUid, radiusMeters: next.radius, earnedMeters: next.earned, claimMeters: next.claim,
      updatedAt: FieldValue.serverTimestamp(),
    });
  });
}

if (admin.apps.length === 0) admin.initializeApp();
export const accountTotalRadiusOnPostWritten = onDocumentWritten(
  { document: "posts/{postId}", region: "us-central1", retry: true },
  async event => reconcileAccountPostRadius(admin.firestore(), event.params.postId),
);
