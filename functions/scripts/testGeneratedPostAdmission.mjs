import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
const { publishGeneratedPost } = await import(process.env.GENERATED_POST_MODULE || new URL('../lib/generatedPostPublishing.js', import.meta.url).href);
import { nextPostAdmission } from '../lib/postAdmission.js';
import { publishWithAdmission } from './postAdmissionTestHelpers.mjs';
assert.ok(process.env.FIRESTORE_EMULATOR_HOST, 'Emulator required: never run against production');
const projectId = 'demo-poplur-generated-admission';
const app = initializeApp({ projectId }, projectId);
const admin = getFirestore(app);
const env = await initializeTestEnvironment({ projectId, firestore: {
  host: '127.0.0.1', port: Number(process.env.FIRESTORE_EMULATOR_HOST.split(':').pop()),
  rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8'),
} });
const uid = 'ai-human-owner';
const input = { latitude: 25.028812, longitude: 121.56473, channelId: 'news', radiusMeters: 500_000 };
const choose = channel => channel;
const publish = job => publishGeneratedPost(admin, uid, job, input, choose);
const rate = admin.doc(`postAdmissions/${uid}`);
let checks = 0;
async function reset(account = {}) { await env.clearFirestore(); await admin.doc(`users/${uid}`).set(account); }
async function job(id, extra = {}) { await admin.doc(`aiGenerationJobs/${id}`).set({ userId: uid, status: 'completed', outputAssetIds: ['asset'], ...extra }); }
async function check(name, fn) { await fn(); console.log(`PASS ${name}`); checks++; }
try {
  await check('server policy has exact minute/day boundaries', async () => {
    const now = 2_000_000_000;
    const previous = { lastPostAt: Timestamp.fromMillis(now - 59_999), windowStartedAt: Timestamp.fromMillis(now - 3_600_000), postsInWindow: 29 };
    assert.throws(() => nextPostAdmission(previous, {}, 'p', now), e => e.status === 429 && e.code === 'post_cooldown');
    previous.lastPostAt = Timestamp.fromMillis(now - 60_000);
    assert.equal(nextPostAdmission(previous, {}, 'p', now).postsInWindow, 30);
    previous.postsInWindow = 30;
    assert.throws(() => nextPostAdmission(previous, {}, 'p', now), e => e.code === 'post_daily_limit');
    previous.windowStartedAt = Timestamp.fromMillis(now - 86_400_000);
    assert.equal(nextPostAdmission(previous, {}, 'p', now).postsInWindow, 1);
  });
  await check('AI and native bursts share one server-checked admission', async () => {
    await reset(); await Promise.all(Array.from({ length: 5 }, (_, i) => job(`burst-${i}`)));
    const results = await Promise.allSettled([
      ...Array.from({ length: 5 }, (_, i) => publish(`burst-${i}`)),
      ...Array.from({ length: 5 }, (_, i) => publishWithAdmission(env.authenticatedContext(uid).firestore(), uid, `native-${i}`, {
        userID: uid, radius: 5000, seedRadiusMeters: 5000, organicRadiusMeters: 0, locationVisibility: 'hidden',
      })),
    ]);
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal((await admin.collection('posts').get()).size, 1);
    assert.equal((await rate.get()).data().postsInWindow, 1);
  });
  await check('repeated publish of one AI job has one permanent receipt and one slot', async () => {
    await reset(); await job('retry');
    const results = await Promise.all(Array.from({ length: 10 }, () => publish('retry')));
    assert.equal(new Set(results.map(r => r.postId)).size, 1);
    assert.equal((await rate.get()).data().postsInWindow, 1);
    const ref = admin.doc(`posts/${results[0].postId}`);
    const data = (await ref.get()).data();
    assert.equal(data.radius, 5000); assert.equal(data.organicRadiusMeters, 0);
    assert.equal(data.seedRadiusMeters, 5000);
    assert.equal((await admin.doc(`users/${uid}`).get()).data().claimRadiusMeters, undefined);
    await ref.update({ radius: 6000, radiusMeters: 6000, organicRadiusMeters: 1000 });
    await publish('retry'); assert.equal((await ref.get()).data().organicRadiusMeters, 1000);
    await ref.delete(); await publish('retry'); assert.equal((await ref.get()).exists, false);
    assert.equal((await rate.get()).data().postsInWindow, 1);
  });
  await check('wrong owner, incomplete jobs and invalid coordinates consume no slot', async () => {
    await reset(); await job('private', { userId: 'other' }); await job('pending', { status: 'processing' });
    await assert.rejects(publish('private'), e => e.status === 404);
    await assert.rejects(publish('pending'), e => e.status === 409);
    await assert.rejects(publishGeneratedPost(admin, uid, 'private', { ...input, latitude: 91 }, choose), e => e.status === 400);
    assert.equal((await rate.get()).exists, false);
  });
  await check('AI migrates the legacy cap, preserves origin privacy, and earns no creation radius', async () => {
    await reset({ privateAccount: true, earnedClaimMeters: 20_000, committedClaimMeters: 10_000,
      postWindowStartMillis: Date.now() - 3_600_000, postsInWindow: 29 });
    await job('last'); const result = await publish('last');
    const p = (await admin.doc(`posts/${result.postId}`).get()).data();
    assert.equal(p.radius, 15000); assert.equal(p.organicRadiusMeters, 0);
    assert.equal(p.locationVisibility, 'hidden'); assert.equal('latitude' in p, false);
    assert.equal((await admin.doc(`users/${uid}/postLocations/${result.postId}`).get()).data().latitude, input.latitude);
    assert.equal((await rate.get()).data().postsInWindow, 30);
    await rate.update({ lastPostAt: Timestamp.fromMillis(Date.now() - 120_000) }); await job('over');
    await assert.rejects(publish('over'), e => e.status === 429 && e.code === 'post_daily_limit');
    assert.equal((await admin.doc('aiGenerationJobs/over').get()).data().publishedPostId, undefined);
    assert.equal((await admin.collection('posts').get()).size, 1);
  });
  console.log(`Generated post admission: ${checks} scenario groups PASS`);
} finally { await env.cleanup(); await admin.terminate(); await deleteApp(app); }
