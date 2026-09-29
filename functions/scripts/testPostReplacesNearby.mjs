import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const admin = require('firebase-admin');
admin.initializeApp({ projectId: 'poplur-replace-nearby-test' });
const { replaceNearbyOwnPops, nearbyOwnPops, haversineMeters, NEARBY_OWN_POP_METERS } = require('../lib/postReplacesNearby');
const { reconcileAccountPostRadius } = require('../lib/accountTotalRadius');
const db = admin.firestore();
const T = 1_700_000_000_000;
const pop = (userID, latitude, longitude, extra = {}) => ({
  userID, latitude, longitude, latitudeCell: Math.round(latitude * 1000), longitudeCell: Math.round(longitude * 1000),
  locationVisibility: 'approximate', audience: 'public', status: 'published', visibilityStatus: 'published',
  radiusMeters: 5_000, radius: 5_000, seedRadiusMeters: 5_000, organicRadiusMeters: 0, ...extra,
});
try {
  // Pure: 5 km is the line, own pops only, hidden origins never take part.
  assert.ok(Math.abs(haversineMeters({ latitude: 43.6487, longitude: -79.3811 }, { latitude: 43.6937, longitude: -79.3811 }) - 5_004) < 20);
  const me = { id: 'new', data: pop('me', 43.6487, -79.3811, { createdAtMillis: T + 10 }) };
  const near = { id: 'near', data: pop('me', 43.6550, -79.3900, { createdAtMillis: T }) };
  const far = { id: 'far', data: pop('me', 43.7290, -79.6070, { createdAtMillis: T }) };
  const theirs = { id: 'theirs', data: pop('you', 43.6487, -79.3811, { createdAtMillis: T }) };
  const hidden = { id: 'hidden', data: { ...pop('me', 43.6487, -79.3811, { createdAtMillis: T }), locationVisibility: 'hidden' } };
  const later = { id: 'later', data: pop('me', 43.6487, -79.3811, { createdAtMillis: T + 20 }) };
  const dead = { id: 'dead', data: pop('me', 43.6487, -79.3811, { createdAtMillis: T, visibilityStatus: 'expired', radiusMeters: 0, radius: 0 }) };
  assert.deepEqual(nearbyOwnPops(me, [near, far, theirs, hidden, later, dead, me]).map(c => c.id), ['near'],
    'only the owner\'s own live, public, older pop within 5 km');
  assert.equal(NEARBY_OWN_POP_METERS, 5_000);

  // Through the transaction: the old pop expires, the new one inherits its earned reach.
  await db.doc('posts/old').set(pop('me', 43.6550, -79.3900, { createdAtMillis: T, radiusMeters: 45_000, radius: 45_000, seedRadiusMeters: 25_000, organicRadiusMeters: 20_000, likeCount: 12 }));
  await db.doc('posts/elsewhere').set(pop('me', 43.7290, -79.6070, { createdAtMillis: T, radiusMeters: 12_000, radius: 12_000, seedRadiusMeters: 5_000, organicRadiusMeters: 7_000 }));
  await db.doc('posts/yours').set(pop('you', 43.6487, -79.3811, { createdAtMillis: T }));
  await db.doc('posts/new').set(pop('me', 43.6487, -79.3811, { createdAtMillis: T + 10 }));
  for (const id of ['old', 'elsewhere', 'yours', 'new']) await reconcileAccountPostRadius(db, id, { countPostRate: false });
  const sums = async uid => { const u = (await db.doc(`users/${uid}`).get()).data() ?? {}; return [u.earnedClaimMeters ?? 0, u.committedClaimMeters ?? 0]; };
  assert.deepEqual(await sums('me'), [27_000, 20_000], 'before: 20 + 7 km earned, 20 km out on the old pop');

  const replaced = await replaceNearbyOwnPops(db, 'new', T + 10);
  assert.deepEqual(replaced, ['old']);
  const oldNow = (await db.doc('posts/old').get()).data();
  assert.equal(oldNow.visibilityStatus, 'expired');
  assert.equal(oldNow.expiryReason, 'replaced-by-nearby-pop');
  assert.equal(oldNow.replacedByPostId, 'new');
  assert.equal(oldNow.radiusMeters, 0);
  assert.equal(oldNow.likeCount, 12, 'its history stays with it');
  const newNow = (await db.doc('posts/new').get()).data();
  assert.equal(newNow.organicRadiusMeters, 20_000, 'the earned reach moved');
  assert.equal(newNow.radiusMeters, 25_000, 'seed 5 km + inherited 20 km');
  assert.deepEqual(newNow.replacedPostIds, ['old']);
  assert.equal((await db.doc('posts/elsewhere').get()).data().radiusMeters, 12_000, '8+ km away is untouched');
  assert.equal((await db.doc('posts/yours').get()).data().radiusMeters, 5_000, 'other people are untouched');
  assert.equal((await db.doc('posts/old/radiusHistory/replaced_new').get()).data().cause, 'replaced');
  const inherited = (await db.collection('posts/new/radiusHistory').where('cause', '==', 'inherited').get()).docs;
  assert.equal(inherited.length, 1);
  assert.equal(inherited[0].data().organicDelta, 20_000);

  // Redelivery is a no-op: the replaced pop is no longer live.
  assert.deepEqual(await replaceNearbyOwnPops(db, 'new', T + 11), []);
  assert.equal((await db.doc('posts/new').get()).data().organicRadiusMeters, 20_000, 'not inherited twice');

  // The account's live reach is unchanged and the old claim is back in the allowance.
  for (const id of ['old', 'new']) await reconcileAccountPostRadius(db, id, { countPostRate: false });
  assert.deepEqual(await sums('me'), [27_000, 0], 'after: same earned, nothing out — nothing minted, nothing lost');

  // A hidden-origin post replaces nothing and is replaced by nothing.
  await db.doc('posts/ghost').set({ ...pop('me', 43.6487, -79.3811, { createdAtMillis: T + 30 }), locationVisibility: 'hidden' });
  assert.deepEqual(await replaceNearbyOwnPops(db, 'ghost', T + 30), []);
  assert.equal((await db.doc('posts/new').get()).data().visibilityStatus, 'published');
  console.log('PASS: one live pop per place — replace, inherit, redelivery, distance, ownership, hidden origin, aggregate neutrality');
} finally { await admin.app().delete(); }
