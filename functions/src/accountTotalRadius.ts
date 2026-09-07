import * as admin from "firebase-admin";
import { FieldValue, Firestore } from "firebase-admin/firestore";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { postOwnerUid } from "./accountRadius";
import { MAX_POST_RADIUS_METERS } from "./postEngagementPolicy";

export const ACCOUNT_TOTAL_RADIUS_FIELD = "totalPostRadiusMeters";
export const ACCOUNT_TOTAL_CONTRIBUTIONS = "accountPostRadiusContributions";

/** Match the profile's sum: each current post contributes its full displayed radius. */
export function postTotalRadiusMeters(post: Record<string, unknown>): number {
  const value = Number(post.radiusMeters ?? post.radius ?? 0);
  return Number.isFinite(value) ? Math.round(Math.max(0, Math.min(MAX_POST_RADIUS_METERS, value))) : 0;
}

/** Read current state, not an event snapshot: duplicate and out-of-order events
 * converge on the same contribution. Deletion and owner changes remove the old
 * contribution in the same transaction that installs the new one. */
export async function reconcileAccountPostRadius(db: Firestore, postId: string): Promise<void> {
  const postRef = db.collection("posts").doc(postId);
  const receiptRef = db.collection(ACCOUNT_TOTAL_CONTRIBUTIONS).doc(postId);
  await db.runTransaction(async tx => {
    const [post, receipt] = await Promise.all([tx.get(postRef), tx.get(receiptRef)]);
    const previous = receipt.data();
    const current = post.data();
    const oldOwner = typeof previous?.ownerUid === "string" ? previous.ownerUid : "";
    const oldRadius = Number(previous?.radiusMeters ?? 0);
    const ownerUid = current ? postOwnerUid(current) : "";
    const radiusMeters = current && ownerUid ? postTotalRadiusMeters(current) : 0;
    if (oldOwner === ownerUid && oldRadius === radiusMeters && receipt.exists) return;
    const deltas = new Map<string, number>();
    if (oldOwner) deltas.set(oldOwner, -oldRadius);
    if (ownerUid) deltas.set(ownerUid, (deltas.get(ownerUid) ?? 0) + radiusMeters);
    for (const [uid, delta] of deltas) {
      tx.set(db.collection("users").doc(uid), {
        [ACCOUNT_TOTAL_RADIUS_FIELD]: FieldValue.increment(delta),
        totalPostRadiusUpdatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    tx.set(receiptRef, { ownerUid, radiusMeters, updatedAt: FieldValue.serverTimestamp() });
  });
}

if (admin.apps.length === 0) admin.initializeApp();
export const accountTotalRadiusOnPostWritten = onDocumentWritten(
  { document: "posts/{postId}", region: "us-central1", retry: true },
  async event => reconcileAccountPostRadius(admin.firestore(), event.params.postId),
);
