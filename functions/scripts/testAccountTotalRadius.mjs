import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc } from 'firebase/firestore';
const require = createRequire(import.meta.url);
const admin = require('firebase-admin');
const projectId = 'poplur-total-radius-test';
admin.initializeApp({ projectId });
const {
  reconcileAccountPostRadius, postTotalRadiusMeters, postEarnedClaimMeters, postCommittedClaimMeters, nextPostRate,
} = require('../lib/accountTotalRadius');
const db = admin.firestore();
const env = await initializeTestEnvironment({ projectId, firestore: {
  rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
  host: '127.0.0.1', port: Number(process.env.FIRESTORE_EMULATOR_HOST.split(':').pop()),
}});
try {
  await env.clearFirestore();
  // Per-post readings.
  assert.equal(postTotalRadiusMeters({ radius: 20_000, organicRadiusMeters: 10 }), 20_000);
  assert.equal(postEarnedClaimMeters({ radius: 44_800, seedRadiusMeters: 20_000 }), 24_800, 'earned = total − seed when organic is undeclared');
  assert.equal(postEarnedClaimMeters({ radiusMeters: 45_632, organicRadiusMeters: 40_000, seedRadiusMeters: 5_632 }), 40_000);
  assert.equal(postCommittedClaimMeters({ radius: 44_800, seedRadiusMeters: 20_000 }), 15_000, 'committed = seed − 5 km');
  assert.equal(postCommittedClaimMeters({ radius: 5_000, seedRadiusMeters: 5_000 }), 0, 'the discovery seed is free');
  assert.equal(postCommittedClaimMeters({ radius: 2_000, seedRadiusMeters: 20_000 }), 0, 'a decayed pop cannot hold more claim than its reach');
  assert.equal(postCommittedClaimMeters({ radius: 30_000, seedRadiusMeters: 30_000, visibilityStatus: 'expired' }), 0, 'expired pops hold nothing');
  assert.equal(postEarnedClaimMeters({ radius: 0, organicRadiusMeters: 30_000 }), 0, 'nor do pops with no reach');
  // The rate window, purely.
  const t0 = 1_700_000_000_000;
  assert.deepEqual(nextPostRate({}, t0), { lastPostAtMillis: t0, postWindowStartMillis: t0, postsInWindow: 1 });
  assert.deepEqual(nextPostRate({ lastPostAtMillis: t0, postWindowStartMillis: t0, postsInWindow: 1 }, t0 + 5_000),
    { lastPostAtMillis: t0 + 5_000, postWindowStartMillis: t0, postsInWindow: 2 });
  assert.deepEqual(nextPostRate({ lastPostAtMillis: t0, postWindowStartMillis: t0, postsInWindow: 30 }, t0 + 86_400_000),
    { lastPostAtMillis: t0 + 86_400_000, postWindowStartMillis: t0 + 86_400_000, postsInWindow: 1 }, 'a day later the window rolls');

  // The aggregates, through the trigger's transaction.
  await db.doc('posts/a').set({ userID: 'owner', radius: 44_800, seedRadiusMeters: 20_000 });
  await db.doc('posts/b').set({ userID: 'owner', radiusMeters: 45_632, organicRadiusMeters: 40_000, seedRadiusMeters: 5_632 });
  await Promise.all(['a', 'b'].map(id => reconcileAccountPostRadius(db, id)));
  const user = async uid => (await db.doc(`users/${uid}`).get()).data() ?? {};
  const sums = async uid => { const u = await user(uid); return [u.totalPostRadiusMeters ?? 0, u.earnedClaimMeters ?? 0, u.committedClaimMeters ?? 0]; };
  assert.deepEqual(await sums('owner'), [90_432, 64_800, 15_632]);
  assert.equal((await user('owner')).postsInWindow, 2, 'two first sightings are two posts in the window');
  assert.ok((await user('owner')).lastPostAtMillis > 0);
  await Promise.all(Array.from({ length: 3 }, () => reconcileAccountPostRadius(db, 'a')));
  assert.deepEqual(await sums('owner'), [90_432, 64_800, 15_632], 'duplicate events must not move any sum');
  assert.equal((await user('owner')).postsInWindow, 2, 'nor count a post twice');
  await db.doc('posts/a').update({ radius: 40_000 });
  await reconcileAccountPostRadius(db, 'a');
  await reconcileAccountPostRadius(db, 'a');
  assert.deepEqual(await sums('owner'), [85_632, 60_000, 15_632], 'late events read current state');
  await db.doc('posts/a').update({ radius: 12_000 });
  await reconcileAccountPostRadius(db, 'a');
  assert.deepEqual(await sums('owner'), [57_632, 40_000, 7_632], 'as the seed decays under its reach the claim comes back');
  await db.doc('posts/c').set({ userID: 'owner', radius: 30_000, seedRadiusMeters: 30_000 });
  await reconcileAccountPostRadius(db, 'c', { countPostRate: false });
  assert.deepEqual(await sums('owner'), [87_632, 40_000, 32_632]);
  assert.equal((await user('owner')).postsInWindow, 2, 'a backfill does not "post now"');
  await db.doc('posts/c').update({ visibilityStatus: 'expired', radius: 0, radiusMeters: 0, seedRadiusMeters: 0 });
  await reconcileAccountPostRadius(db, 'c');
  assert.deepEqual(await sums('owner'), [57_632, 40_000, 7_632], 'an expired pop releases its claim');
  await db.doc('posts/a').update({ userID: 'other' });
  await reconcileAccountPostRadius(db, 'a');
  assert.deepEqual(await sums('owner'), [45_632, 40_000, 632]);
  assert.deepEqual(await sums('other'), [12_000, 0, 7_000]);
  await db.doc('posts/a').delete();
  await reconcileAccountPostRadius(db, 'a');
  await reconcileAccountPostRadius(db, 'a');
  assert.deepEqual(await sums('other'), [0, 0, 0], 'deletions debit once');

  // The rule against the sums the trigger just wrote: owner holds 40 km earned
  // with 632 m out → 39,368 m + the seed. The trigger stamped lastPostAtMillis
  // seconds ago, so back it off as a real minute would.
  await db.doc('users/owner').update({ lastPostAtMillis: Date.now() - 120_000 });
  const client = env.authenticatedContext('owner').firestore();
  const drop = radius => ({ userID: 'owner', mediaURL: 'https://example.test/a.jpg', mediaType: 'image',
    audience: 'public', status: 'published', locationVisibility: 'hidden', radius, radiusMeters: radius,
    seedRadiusMeters: radius, organicRadiusMeters: 0, viewCount: 0 });
  await assertSucceeds(setDoc(doc(client, 'posts', 'at-max'), drop(44_368)));
  await reconcileAccountPostRadius(db, 'at-max');
  await assertFails(setDoc(doc(client, 'posts', 'over-max'), drop(44_369)));
  assert.deepEqual(await sums('owner'), [90_000, 40_000, 40_000], 'the accepted claim is now out');
  await db.doc('users/owner').update({ lastPostAtMillis: Date.now() - 120_000 });
  await assertFails(setDoc(doc(client, 'posts', 'reuse'), drop(5_001)), 'and cannot be claimed again while it is out');
  await assertSucceeds(setDoc(doc(client, 'posts', 'seed-only'), drop(5_000)));
  for (const field of ['totalPostRadiusMeters', 'earnedClaimMeters', 'committedClaimMeters', 'lastPostAtMillis', 'postsInWindow']) {
    await assertFails(updateDoc(doc(client, 'users', 'owner'), { [field]: 6_371_000 }));
  }
  await assertFails(setDoc(doc(client, 'accountPostRadiusContributions', 'fake'), { ownerUid: 'owner', radiusMeters: 9e9 }));
  console.log('PASS: earned/committed/total sums, retries, stale events, decay, expiry, ownership changes, deletion, rate window, exact allowance, spent-once and field protection');
} finally { await env.cleanup(); await admin.app().delete(); }
