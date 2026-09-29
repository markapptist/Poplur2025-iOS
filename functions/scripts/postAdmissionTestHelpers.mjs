import { doc, getDocFromServer, runTransaction, serverTimestamp, Timestamp } from 'firebase/firestore';

// Match the two native clients' transaction. All policy checks in these tests
// are performed by the real rules engine, not a JavaScript preflight check.
export async function publishWithAdmission(db, uid, id, post, { now = Date.now(), mutateAdmission, extraPost } = {}) {
  try { return await runTransaction(db, async tx => {
    const ref = doc(db, 'posts', id);
    const existing = await tx.get(ref);
    if (existing.exists()) {
      if ((existing.data().userID ?? existing.data().userId) !== uid) throw new Error('Post ID collision');
      return;
    }
    const account = (await tx.get(doc(db, 'users', uid))).data() ?? {};
    const rateRef = doc(db, 'postAdmissions', uid);
    const rate = (await tx.get(rateRef)).data();
    const start = rate?.windowStartedAt ?? (account.postWindowStartMillis ? Timestamp.fromMillis(account.postWindowStartMillis) : null);
    const count = rate?.postsInWindow ?? account.postsInWindow ?? 0;
    const active = start && start.toMillis() > 0 && now - start.toMillis() < 86_400_000;
    const admission = {
      postId: id, lastPostAt: serverTimestamp(),
      windowStartedAt: active ? start : serverTimestamp(), postsInWindow: active ? Math.max(0, count) + 1 : 1,
    };
    tx.set(ref, post);
    if (!/^(sim|synthetic)-/.test(uid)) tx.set(rateRef, mutateAdmission ? mutateAdmission(admission) : admission);
    tx.set(doc(db, 'users', uid, 'postLocations', id), { latitude: 25.028812, longitude: 121.56473, source: 'post-upload' });
    if (extraPost) tx.set(doc(db, 'posts', extraPost), { ...post });
  }, { maxAttempts: 20 });
  } catch (error) {
    // Firestore may evaluate create rules after another identical request won
    // and reject instead of retrying. Native uploaders also confirm this case.
    const existing = await getDocFromServer(doc(db, 'posts', id));
    if (existing.exists() && (existing.data().userID ?? existing.data().userId) === uid
      && existing.data().mediaStoragePath === post.mediaStoragePath) return;
    throw error;
  }
}
