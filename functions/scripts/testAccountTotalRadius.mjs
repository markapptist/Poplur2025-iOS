import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc } from 'firebase/firestore';
const require = createRequire(import.meta.url);
const admin = require('firebase-admin');
const projectId = 'poplur-total-radius-test';
admin.initializeApp({ projectId });
const { reconcileAccountPostRadius, postTotalRadiusMeters } = require('../lib/accountTotalRadius');
const db = admin.firestore();
const env = await initializeTestEnvironment({ projectId, firestore: {
  rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
  host: '127.0.0.1', port: Number(process.env.FIRESTORE_EMULATOR_HOST.split(':').pop()),
}});
try {
  await env.clearFirestore();
  assert.equal(postTotalRadiusMeters({ radius: 20_000, organicRadiusMeters: 10 }), 20_000);
  await db.doc('posts/a').set({ userID: 'owner', radius: 44_800 });
  await db.doc('posts/b').set({ userID: 'owner', radiusMeters: 45_632 });
  await Promise.all(['a', 'b'].map(id => reconcileAccountPostRadius(db, id)));
  const total = async uid => (await db.doc(`users/${uid}`).get()).data().totalPostRadiusMeters;
  assert.equal(await total('owner'), 90_432);
  await Promise.all(Array.from({ length: 3 }, () => reconcileAccountPostRadius(db, 'a')));
  assert.equal(await total('owner'), 90_432, 'duplicate events must not increase the sum');
  await db.doc('posts/a').update({ radius: 40_000 });
  await reconcileAccountPostRadius(db, 'a');
  await reconcileAccountPostRadius(db, 'a');
  assert.equal(await total('owner'), 85_632, 'late events read current state');
  await db.doc('posts/a').update({ userID: 'other' });
  await reconcileAccountPostRadius(db, 'a');
  assert.equal(await total('owner'), 45_632);
  assert.equal(await total('other'), 40_000);
  await db.doc('posts/a').delete();
  await reconcileAccountPostRadius(db, 'a');
  await reconcileAccountPostRadius(db, 'a');
  assert.equal(await total('other'), 0, 'deletions debit once');
  const client = env.authenticatedContext('owner').firestore();
  const drop = radius => ({ userID: 'owner', mediaURL: 'https://example.test/a.jpg', mediaType: 'image',
    audience: 'public', status: 'published', locationVisibility: 'hidden', radius, radiusMeters: radius,
    seedRadiusMeters: radius, organicRadiusMeters: 0, viewCount: 0 });
  await assertSucceeds(setDoc(doc(client, 'posts', 'at-max'), drop(45_632)));
  await assertFails(setDoc(doc(client, 'posts', 'over-max'), drop(45_633)));
  await assertFails(updateDoc(doc(client, 'users', 'owner'), { totalPostRadiusMeters: 6_371_000 }));
  await assertFails(setDoc(doc(client, 'accountPostRadiusContributions', 'fake'), { ownerUid: 'owner', radiusMeters: 9e9 }));
  console.log('PASS: full sum, retries, stale events, ownership changes, deletion, exact allowance and field protection');
} finally { await env.cleanup(); await admin.app().delete(); }
