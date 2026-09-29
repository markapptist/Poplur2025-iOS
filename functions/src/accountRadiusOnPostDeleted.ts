import * as admin from "firebase-admin";
import { FieldValue } from "firebase-admin/firestore";
import { onDocumentDeleted } from "firebase-functions/v2/firestore";
import {
  ACCOUNT_CLAIM_RADIUS_FIELD,
  CLAIM_RADIUS_RECEIPTS,
  postEarnedRadiusMeters,
  postOwnerUid,
} from "./accountRadius";

if (admin.apps.length === 0) admin.initializeApp();

/**
 * Take a deleted post's earned radius back out of its owner's entitlement.
 *
 * See accountRadius.ts for why: the aggregate the create rule reads has to
 * stay equal to a sum over the posts, and a post that is gone contributes
 * nothing to that sum. The receipt document makes a repeated delivery a no-op,
 * and is the only reason this can use a plain increment.
 */
export const accountRadiusOnPostDeleted = onDocumentDeleted(
  { document: "posts/{postId}", region: "us-central1" },
  async event => {
    const post = event.data?.data() ?? {};
    const ownerUid = postOwnerUid(post);
    const earned = postEarnedRadiusMeters(post);
    if (!ownerUid || earned <= 0) return;

    const db = admin.firestore();
    const receiptRef = db.collection(CLAIM_RADIUS_RECEIPTS).doc(event.params.postId);
    await db.runTransaction(async transaction => {
      const [receipt, deletion] = await Promise.all([
        transaction.get(receiptRef),
        transaction.get(db.collection("accountDeletions").doc(ownerUid)),
      ]);
      if (deletion.exists) return;
      if (receipt.exists) return;
      transaction.create(receiptRef, {
        ownerUid,
        earnedRadiusMeters: earned,
        deletedAt: FieldValue.serverTimestamp(),
      });
      transaction.set(db.collection("users").doc(ownerUid), {
        [ACCOUNT_CLAIM_RADIUS_FIELD]: FieldValue.increment(-earned),
        claimRadiusUpdatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    });
  },
);
