import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, runTransaction } from 'firebase/firestore';

const env = await initializeTestEnvironment({
  projectId: 'demo-poplur-upload',
  firestore: { host: '127.0.0.1', port: 8281, rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8') },
});
const uid = 'upload-owner';
const db = env.authenticatedContext(uid).firestore();
const account = doc(db, 'users', uid);
const postRef = doc(db, 'posts', 'retryable-photo');
const locationRef = doc(db, 'users', uid, 'postLocations', 'retryable-photo');
const draft = {
  userID: uid, mediaType: 'photo', mediaURL: 'https://example.test/photo.jpg',
  mediaStoragePath: `posts/${uid}/retryable-photo.jpg`, playbackURL: 'https://example.test/photo.jpg',
  radius: 56500, seedRadiusMeters: 56500, organicRadiusMeters: 0, viewCount: 0,
  audience: 'public', locationVisibility: 'approximate',
  latitude: 25.029, longitude: 121.565, latitudeCell: 25029, longitudeCell: 121565,
  status: 'published', processingStatus: 'ready', schemaVersion: 2, photoViewSeconds: 10,
};
try {
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(), 'users', uid), { claimRadiusMeters: 42893 });
    await setDoc(doc(ctx.firestore(), 'config', 'claimRadius'), { backfilled: true });
  });
  await assertFails(setDoc(postRef, draft)); // The screenshot's stale 56.5km draft.
  const publish = () => runTransaction(db, async tx => {
    const existing = await tx.get(postRef);
    if (existing.exists()) {
      assert.equal(existing.data().userID, uid);
      assert.equal(existing.data().mediaStoragePath, draft.mediaStoragePath);
      return;
    }
    const user = (await tx.get(account)).data();
    const radius = Math.min(draft.radius, Math.min(6371000, Math.max(0, user?.claimRadiusMeters ?? 0) + 5000));
    tx.set(postRef, { ...draft, radius, seedRadiusMeters: radius });
    tx.set(locationRef, { latitude: 25.028812, longitude: 121.56473, source: 'post-upload' }, { merge: true });
  });
  await publish();
  assert.equal((await getDoc(postRef)).data().radius, 47893);
  assert.equal((await getDoc(locationRef)).data().latitude, 25.028812);
  await env.withSecurityRulesDisabled(async ctx => {
    await setDoc(doc(ctx.firestore(), 'posts', 'retryable-photo'), { radius: 48093, organicRadiusMeters: 200, viewCount: 1 }, { merge: true });
  });
  await publish(); // Retry after a lost acknowledgement must preserve earned growth.
  assert.equal((await getDoc(postRef)).data().radius, 48093);
  assert.equal((await getDoc(postRef)).data().viewCount, 1);
  console.log('Upload transaction: stale draft accepted within current allowance; retry preserves engagement; private origin saved. PASS');
} finally { await env.cleanup(); }
