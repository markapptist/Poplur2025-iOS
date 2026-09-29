import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, setDoc } from 'firebase/firestore';
const require = createRequire(import.meta.url);
if (!process.env.GCLOUD_PROJECT?.startsWith('demo-') || !process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error('Emulators only');
const admin = require('firebase-admin');
admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT });
const staged = process.env.ACCOUNT_DELETION_TEST_STAGE;
const { validateDeletionRequest, deleteAuthenticatedAccount } = require(staged ? `${staged}/deletion/lib/accountDeletion.js` : '../lib/accountDeletion.js');
const { reconcileAccountPostRadius } = require(staged ? `${staged}/radius/lib/accountTotalRadius.js` : '../lib/accountTotalRadius.js');
const { accountRadiusOnPostDeleted } = require(staged ? `${staged}/deleted/lib/accountRadiusOnPostDeleted.js` : '../lib/accountRadiusOnPostDeleted.js');
const db = admin.firestore(), auth = admin.auth(), uid = 'deleting-owner', other = 'preserved-owner';
const request = { auth: { uid, token: { auth_time: Date.now() / 1000 } }, data: { confirm: true, expectedUid: uid, uid: other } };
let checks = 0;
const check = async (name, fn) => { await fn(); console.log(`PASS ${name}`); checks++; };
const files = new Set([`posts/${uid}/a.jpg`, `posts/${uid}-other/a.jpg`, `posts/${other}/a.jpg`, `profile_pictures/${uid}.jpg`, `profile_pictures/${uid}-other.jpg`, `generated/${uid}/job/a.jpg`, `dmMedia/thread/${uid}/a.jpg`, `dmMedia/thread/${other}/b.jpg`]);
let failStorage = false;
const bucket = {
  async deleteFiles({ prefix }) { if (failStorage) throw new Error('storage offline'); for (const path of files) if (path.startsWith(prefix)) files.delete(path); },
  file(path) { return { async delete() { if (failStorage) throw new Error('storage offline'); files.delete(path); } }; },
};
const put = (path, value) => db.doc(path).set(value);
const exists = async path => (await db.doc(path).get()).exists;
const env = await initializeTestEnvironment({ projectId: process.env.GCLOUD_PROJECT, firestore: { host: '127.0.0.1', port: Number(process.env.FIRESTORE_EMULATOR_HOST.split(':')[1]), rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8') } });
try {
  await check('fresh authentication and explicit confirmation required; client uid ignored', async () => {
    assert.throws(() => validateDeletionRequest(undefined, { confirm: true }), /Sign in/);
    assert.throws(() => validateDeletionRequest(request.auth, { confirm: false }), /Confirm/);
    assert.throws(() => validateDeletionRequest({ uid, token: { auth_time: 1 } }, { confirm: true, expectedUid: uid }), /password/);
    assert.throws(() => validateDeletionRequest({ uid, token: {} }, { confirm: true, expectedUid: uid }), /password/);
    assert.equal(validateDeletionRequest(request.auth, request.data), uid);
  });
  await auth.createUser({ uid, email: 'delete@example.test', password: 'emulator-password' });
  await auth.createUser({ uid: other, email: 'keep@example.test', password: 'emulator-password' });
  await check('missing or switched confirmation identity cannot start deletion', async () => {
    for (const data of [{ confirm: true }, { confirm: true, expectedUid: other }]) {
      await assert.rejects(deleteAuthenticatedAccount({ db, bucket, auth }, { ...request, data }),
        error => ['invalid-argument', 'failed-precondition'].includes(error.code));
    }
    const switchedSession = { auth: { uid: other, token: { auth_time: Date.now() / 1000 } }, data: request.data };
    await assert.rejects(deleteAuthenticatedAccount({ db, bucket, auth }, switchedSession), /signed-in account changed/);
    assert.equal((await auth.getUser(uid)).uid, uid);
    assert.equal((await auth.getUser(other)).uid, other);
    assert.equal(await exists(`accountDeletions/${uid}`), false);
    assert.equal(await exists(`accountDeletions/${other}`), false);
  });
  await Promise.all([
    put(`users/${uid}`, { email: 'delete@example.test' }), put(`users/${uid}/postLocations/p`, { latitude: 1 }),
    put(`users/${other}`, { username: 'Keep me' }), put('posts/p', { userID: uid, radius: 5000 }),
    put('posts/legacy', { userId: uid }), put('posts/p/comments/c', { actorUid: other, text: 'reply' }),
    put('posts/legacyOwner', { ownerId: uid }), put('posts/staleAlias', { userID: other, ownerId: uid }),
    put('calls/legacyCall', { callerId: uid, calleeId: other }), put('calls/foreignCall', { callerId: other, calleeId: 'third-owner' }),
    put('posts/foreign', { userID: other }), put('posts/foreign/comments/own', { actorUid: uid, text: 'remove' }),
    put('posts/foreign/comments/other', { actorUid: other, text: 'preserve' }),
    put(`posts/foreign/engagementActors/${uid}`, { actorUid: uid }),
    put(`users/${other}/notifications/own`, { actorUid: uid, body: 'remove name' }),
    put('dmThreads/thread', { participants: [uid, other], participantNames: { [uid]: 'Delete Name', [other]: 'Keep Name' }, lastMessage: 'remove', lastSenderId: uid }),
    put('dmThreads/thread/messages/a', { senderId: uid, text: 'remove', createdAt: admin.firestore.Timestamp.now() }),
    put('dmThreads/thread/messages/b', { senderId: other, text: 'preserve', createdAt: admin.firestore.Timestamp.now() }),
    put(`creatorCreditBalances/${uid}`, { availableCredits: 20 }), put('verifiedStorePurchases/receipt', { userId: uid, receipt: 'private' }),
    put('tracks/own', { userID: uid }), put('tracks/foreign', { userID: other }),
    put(`testActivity/${uid}`, { email: 'delete@example.test' }), put('generatedAssets/a', { userId: uid }),
  ]);
  await check('storage failure is not success and leaves Auth available for retry', async () => {
    failStorage = true;
    await assert.rejects(deleteAuthenticatedAccount({ db, bucket, auth }, request), /incomplete/);
    assert.equal((await auth.getUser(uid)).uid, uid);
    assert.equal(await exists(`users/${uid}`), true);
    assert.equal((await db.doc(`accountDeletions/${uid}`).get()).data().state, 'retry');
    failStorage = false;
  });
  await check('deletion marker blocks stale client writes, not other accounts', async () => {
    await assertFails(setDoc(doc(env.authenticatedContext(uid).firestore(), 'users', uid), { username: 'recreate' }));
    await assertSucceeds(setDoc(doc(env.authenticatedContext(other).firestore(), 'users', other), { username: 'Keep me' }, { merge: true }));
    await assertFails(setDoc(doc(env.authenticatedContext(uid).firestore(), 'accountDeletions', uid), { state: 'completed' }));
  });
  await check('retry deletes owned data/media and Auth, preserving unrelated data', async () => {
    assert.deepEqual(await deleteAuthenticatedAccount({ db, bucket, auth }, request), { deleted: true });
    for (const path of [`users/${uid}`, `users/${uid}/postLocations/p`, 'posts/p', 'posts/p/comments/c', 'posts/legacy', 'posts/foreign/comments/own', `posts/foreign/engagementActors/${uid}`, `users/${other}/notifications/own`, 'dmThreads/thread/messages/a', `creatorCreditBalances/${uid}`, 'tracks/own', `testActivity/${uid}`, 'generatedAssets/a']) assert.equal(await exists(path), false, path);
    for (const path of [`users/${other}`, 'posts/foreign', 'posts/foreign/comments/other', 'dmThreads/thread/messages/b', 'tracks/foreign']) assert.equal(await exists(path), true, path);
    for (const path of ['posts/legacyOwner', 'calls/legacyCall']) assert.equal(await exists(path), false, path);
    for (const path of ['posts/staleAlias', 'calls/foreignCall']) assert.equal(await exists(path), true, path);
    const thread = (await db.doc('dmThreads/thread').get()).data();
    assert.equal(thread.participantNames[uid], undefined);
    assert.equal(thread.participantNames[other], 'Keep Name');
    assert.equal(thread.lastMessage, 'preserve');
    assert.deepEqual((await db.doc('verifiedStorePurchases/receipt').get()).data(), { consumed: true });
    assert.deepEqual([...files].sort(), [`posts/${uid}-other/a.jpg`, `posts/${other}/a.jpg`, `profile_pictures/${uid}-other.jpg`, `dmMedia/thread/${other}/b.jpg`].sort());
    await assert.rejects(auth.getUser(uid), e => e.code === 'auth/user-not-found');
    assert.equal((await auth.getUser(other)).uid, other);
  });
  await check('duplicate request after a lost response remains successful', async () => {
    assert.deepEqual(await deleteAuthenticatedAccount({ db, bucket, auth }, request), { deleted: true });
  });
  await check('delayed post triggers cannot recreate deleted user or receipts', async () => {
    await put('accountPostRadiusContributions/late', { ownerUid: uid, radiusMeters: 5000, earnedMeters: 100 });
    await reconcileAccountPostRadius(db, 'late');
    await accountRadiusOnPostDeleted.run({ params: { postId: 'late' }, data: { data: () => ({ userID: uid, radius: 5100, seedRadiusMeters: 5000, organicRadiusMeters: 100 }) } });
    assert.equal(await exists(`users/${uid}`), false);
    assert.equal(await exists('accountPostRadiusContributions/late'), false);
    assert.equal(await exists('accountRadiusDeletions/late'), false);
  });
  await check('retry removes orphaned children after a partial recursive deletion', async () => {
    const partial = 'partial-owner';
    await auth.createUser({ uid: partial, email: 'partial@example.test', password: 'emulator-password' });
    await put('posts/partial', { userID: partial });
    await put('posts/partial/comments/child', { actorUid: other, text: 'nested' });
    const partialRequest = { auth: { uid: partial, token: { auth_time: Date.now() / 1000 } }, data: { confirm: true, expectedUid: partial } };
    const recursiveDelete = db.recursiveDelete.bind(db);
    db.recursiveDelete = async ref => {
      if (ref.path === 'posts/partial') {
        await ref.delete();
        throw new Error('lost connection after parent deletion');
      }
      return recursiveDelete(ref);
    };
    try { await assert.rejects(deleteAuthenticatedAccount({ db, bucket, auth }, partialRequest), /incomplete/); }
    finally { db.recursiveDelete = recursiveDelete; }
    assert.equal(await exists('posts/partial'), false);
    assert.equal(await exists('posts/partial/comments/child'), true);
    assert.deepEqual(await deleteAuthenticatedAccount({ db, bucket, auth }, partialRequest), { deleted: true });
    assert.equal(await exists('posts/partial/comments/child'), false);
    assert.equal((await db.collection(`accountDeletions/${partial}/pending`).get()).empty, true);
  });
  console.log(`${checks} account-deletion checks passed`);
} finally { await env.cleanup(); await admin.app().delete(); }
