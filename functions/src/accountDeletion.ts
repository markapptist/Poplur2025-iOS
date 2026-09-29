import * as admin from "firebase-admin";
import { DocumentReference, FieldValue, Firestore, Query } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

if (admin.apps.length === 0) admin.initializeApp();

// Server-only tombstones also stop stale client tokens and delayed radius
// triggers from recreating an account. No email, name or media is retained here.
export const ACCOUNT_DELETIONS = "accountDeletions";

export function validateDeletionRequest(
  auth: { uid: string; token: { auth_time?: unknown } } | undefined,
  data: unknown,
  nowSeconds = Date.now() / 1000,
): string {
  if (!auth) throw new HttpsError("unauthenticated", "Sign in to delete your account.");
  if (!data || (data as { confirm?: unknown }).confirm !== true) {
    throw new HttpsError("invalid-argument", "Confirm account deletion first.");
  }
  const expectedUid = (data as { expectedUid?: unknown }).expectedUid;
  if (typeof expectedUid !== "string" || expectedUid.length === 0) {
    throw new HttpsError("invalid-argument", "Confirm which account to delete.");
  }
  if (expectedUid !== auth.uid) {
    throw new HttpsError("failed-precondition", "The signed-in account changed. Start account deletion again.");
  }
  const authTime = Number(auth.token.auth_time);
  if (!Number.isFinite(authTime) || authTime > nowSeconds + 60 || nowSeconds - authTime > 300) {
    throw new HttpsError("failed-precondition", "Verify your password again before deleting your account.");
  }
  // expectedUid binds the confirmation to the session; it is never a selector.
  // The caller cannot supply another account's uid as the deletion target.
  return auth.uid;
}

type StorageBucket = ReturnType<ReturnType<typeof admin.storage>["bucket"]>;

async function deleteTracked(db: Firestore, uid: string, refs: DocumentReference[]): Promise<void> {
  // recursiveDelete may remove a parent before failing on a child. Keep each
  // path until the entire subtree is gone, so a retry can still find it.
  const queue = db.collection(ACCOUNT_DELETIONS).doc(uid).collection("pending");
  const tasks = refs.map(ref => queue.doc(Buffer.from(ref.path).toString("base64url")));
  const batch = db.batch();
  refs.forEach((ref, index) => batch.set(tasks[index], { path: ref.path }));
  await batch.commit();
  // Bounded parallelism reduces time spent waiting on large histories.
  // Await every worker before reporting a failure; unfinished paths remain
  // recorded for retry, including a parent that disappeared before its children.
  let next = 0;
  const errors: unknown[] = [];
  await Promise.all(Array.from({ length: Math.min(16, refs.length) }, async () => {
    while (next < refs.length) {
      const index = next++;
      try {
        await db.recursiveDelete(refs[index]);
        await tasks[index].delete();
      } catch (error) { errors.push(error); }
    }
  }));
  if (errors.length) throw errors[0];
}

async function deleteQuery(db: Firestore, uid: string, query: Query): Promise<void> {
  // Bounded pages, including nested documents. Missing documents on a retry
  // are successful deletions; real network/storage failures are never swallowed.
  while (true) {
    const page = await query.limit(100).get();
    if (page.empty) return;
    await deleteTracked(db, uid, page.docs.map(doc => doc.ref));
  }
}

/** Resumable, owner-scoped cleanup. Auth is removed only AFTER this succeeds. */
export async function deleteAccountData(db: Firestore, bucket: StorageBucket, uid: string): Promise<void> {
  const pending = db.collection(ACCOUNT_DELETIONS).doc(uid).collection("pending");
  while (true) {
    const tasks = await pending.limit(100).get();
    if (tasks.empty) break;
    for (const task of tasks.docs) {
      await db.recursiveDelete(db.doc(task.data().path));
      await task.ref.delete();
    }
  }
  // Remove uploaded media before its references, so retries can still discover it.
  for (const prefix of ["posts", "music", "musicArt", "generated", "businessModels"]) {
    await bucket.deleteFiles({ prefix: `${prefix}/${uid}/` });
  }
  for (const prefix of ["profile_pictures", "profile_selfies"]) {
    await bucket.deleteFiles({ prefix: `${prefix}/${uid}.` });
  }

  const threads = await db.collection("dmThreads").where("participants", "array-contains", uid).get();
  for (const thread of threads.docs) {
    await bucket.deleteFiles({ prefix: `dmMedia/${thread.id}/${uid}/` });
    await deleteQuery(db, uid, thread.ref.collection("messages").where("senderId", "==", uid));
    // Preserve the other participant's own messages; remove the deleted
    // person's profile and any cached preview of a message they sent.
    const data = thread.data();
    const names = { ...(data.participantNames ?? {}) };
    const photos = { ...(data.participantPhotos ?? {}) };
    delete names[uid]; delete photos[uid];
    const remaining = await thread.ref.collection("messages").orderBy("createdAt", "desc").limit(1).get();
    const last = remaining.docs[0]?.data();
    await thread.ref.update({
      participantNames: names, participantPhotos: photos,
      lastMessage: last?.kind === "text" || !last?.kind ? (last?.text ?? "") : "Media message",
      lastSenderId: last?.senderId ?? "",
    });
  }

  const posts = new Map<string, admin.firestore.QueryDocumentSnapshot>();
  for (const field of ["userID", "userId", "ownerId"]) {
    const snapshot = await db.collection("posts").where(field, "==", uid).get();
    snapshot.docs.forEach(doc => {
      const data = doc.data();
      // Match the same ownership precedence as postOwnerUid. A stale alias
      // must never cause deletion of another person's post.
      if ((data.userID ?? data.userId ?? data.ownerId) === uid) posts.set(doc.id, doc);
    });
  }
  for (const post of posts.values()) {
    // These projections/receipts use the post id, not the user id.
    const projections = ["mapPostIndex", "mapDiscoveryJobs", "radiusDecayQueue", "accountPostRadiusContributions", "accountRadiusDeletions"];
    await deleteTracked(db, uid, [...projections.map(collection => db.collection(collection).doc(post.id)), post.ref]);
  }

  // Contributions on OTHER people's posts and notification copies are personal
  // data too. Dedicated collection-group indexes are shipped with this feature.
  for (const group of ["comments", "engagements", "engagementActors", "notifications"]) {
    await deleteQuery(db, uid, db.collectionGroup(group).where("actorUid", "==", uid));
  }

  const ownedCollections: Array<[string, string]> = [
    ["tracks", "userId"], ["tracks", "userID"], ["tracks", "ownerUid"],
    ["businesses", "ownerUserId"], ["aiCampaigns", "ownerUid"],
    ["aiGenerationJobs", "userId"], ["generatedAssets", "userId"],
    ["creatorCreditTransactions", "userId"], ["radiusBoostTransactions", "userId"],
    ["meshyJobs", "uid"], ["wardrobeGarmentJobs", "uid"], ["retroGameBuilds", "uid"], ["retroGameBuilds", "userId"],
    ["testBetaPosts", "uid"], ["testFeedback", "uid"], ["appPresenceSessions", "uid"],
    ["reports", "reporterUid"], ["reports", "reporterId"],
    ["calls", "callerId"], ["calls", "calleeId"],
  ];
  // Pending model files are keyed by job id rather than by uid.
  const models = await db.collection("meshyJobs").where("uid", "==", uid).get();
  for (const job of models.docs) {
    for (const prefix of ["landmarks/pending", "ar-filters/pending"]) {
      await bucket.file(`${prefix}/${job.id}.glb`).delete({ ignoreNotFound: true });
    }
  }
  for (const [collection, field] of ownedCollections) {
    await deleteQuery(db, uid, db.collection(collection).where(field, "==", uid));
  }
  await deleteQuery(db, uid, db.collection("calls").where("participants", "array-contains", uid));

  const passes = await db.collection("walletPasses").where("userId", "==", uid).get();
  for (const pass of passes.docs) {
    await deleteQuery(db, uid, db.collection("walletPassRegistrations").where("serialNumber", "==", pass.id));
    await deleteTracked(db, uid, [pass.ref]);
  }
  // Keep only a consumed-receipt fingerprint to prevent a purchased credit
  // pack from being claimed twice. Discard the account and transaction payload.
  const receipts = await db.collection("verifiedStorePurchases").where("userId", "==", uid).get();
  for (const receipt of receipts.docs) await receipt.ref.set({ consumed: true });

  for (const collection of ["users", "profiles", "creatorCreditBalances", "postAdmissions", "testActivity", "cameraScanRate", "gameConfigRate", "retroGameRate", "mapDiscoveryRate"]) {
    await deleteTracked(db, uid, [db.collection(collection).doc(uid)]);
  }
}

export async function deleteAuthenticatedAccount(
  services: { db: Firestore; bucket: StorageBucket; auth: admin.auth.Auth },
  request: { auth?: { uid: string; token: { auth_time?: unknown } }; data: unknown },
): Promise<{ deleted: true }> {
    const uid = validateDeletionRequest(request.auth, request.data);
    const { db, bucket, auth } = services;
    const status = db.collection(ACCOUNT_DELETIONS).doc(uid);
    const previous = await status.get();
    if (previous.data()?.state === "completed") return { deleted: true };
    try {
      const user = await auth.getUser(uid);
      if (user.disabled) throw new HttpsError("permission-denied", "This account is unavailable.");
    } catch (error) {
      // A lost response after Auth deletion must still be recoverable with the
      // same recent identity. Never infer completion from an absent user alone.
      if ((error as { code?: string }).code !== "auth/user-not-found" || !previous.exists) throw error;
    }
    await status.set({ state: "deleting", requestedAt: FieldValue.serverTimestamp() }, { merge: true });
    try {
      await deleteAccountData(db, bucket, uid);
      try { await auth.deleteUser(uid); }
      catch (error) { if ((error as { code?: string }).code !== "auth/user-not-found") throw error; }
    } catch (error) {
      // Preserve the request and the authenticated identity so the person can
      // retry. Never show success after only part of the data was removed.
      await status.set({ state: "retry", updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      throw new HttpsError("unavailable", "Deletion is incomplete. Please retry to finish removing your account.");
    }
    // The account and its data are already gone. A failure writing this minimal
    // receipt must not turn successful deletion into an unrecoverable UI error.
    await status.set({ state: "completed", completedAt: FieldValue.serverTimestamp() }).catch(() => {});
    return { deleted: true };
}

export const deleteMyAccount = onCall(
  { region: "us-east1", timeoutSeconds: 540, memory: "512MiB", cpu: "gcf_gen1", concurrency: 1, maxInstances: 2 },
  request => deleteAuthenticatedAccount({ db: admin.firestore(), bucket: admin.storage().bucket(), auth: admin.auth() }, request),
);
