import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { initializeTestEnvironment, assertFails } from '@firebase/rules-unit-testing';
import { doc, setDoc, getDoc, deleteDoc, Timestamp, serverTimestamp, updateDoc } from 'firebase/firestore';
import { publishWithAdmission } from './postAdmissionTestHelpers.mjs';

const env = await initializeTestEnvironment({
  projectId: 'demo-poplur-post-admission',
  firestore: { host: '127.0.0.1', port: Number(process.env.FIRESTORE_EMULATOR_HOST?.split(':').pop() ?? 18580),
    rules: readFileSync(new URL('../../firestore.rules', import.meta.url), 'utf8') },
});
let checks = 0;
const uid = 'atomic-owner';
const db = env.authenticatedContext(uid).firestore();
const post = (owner = uid, more = {}) => ({ userID: owner, radius: 5000, seedRadiusMeters: 5000, organicRadiusMeters: 0,
  viewCount: 0, mediaURL: 'https://example.test/test.jpg', mediaStoragePath: `posts/${owner}/test.jpg`,
  audience: 'public', locationVisibility: 'hidden', status: 'published', ...more });
const rateRef = doc(db, 'postAdmissions', uid);
const publish = (id, options = {}, data = post()) => publishWithAdmission(db, uid, id, data, options);
const seed = async (path, data) => env.withSecurityRulesDisabled(ctx => setDoc(doc(ctx.firestore(), path), data));
const reset = async (account = {}) => { await env.clearFirestore(); await seed(`users/${uid}`, { username: uid, ...account }); };
const existingRate = (more = {}) => ({ postId: 'older', lastPostAt: Timestamp.fromMillis(Date.now() - 120_000),
  windowStartedAt: Timestamp.fromMillis(Date.now() - 3_600_000), postsInWindow: 1, ...more });
async function check(name, fn) { await fn(); checks++; console.log(`PASS ${name}`); }
try {
  await check('12 simultaneous distinct posts: exactly one commits, no trigger involved', async () => {
    await reset();
    const results = await Promise.allSettled(Array.from({ length: 12 }, (_, i) => publishWithAdmission(
      env.authenticatedContext(uid).firestore(), uid, `burst-${i}`, post())));
    assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
    assert.equal((await getDoc(rateRef)).data().postsInWindow, 1);
    const posts = await Promise.all(Array.from({ length: 12 }, (_, i) => getDoc(doc(db, 'posts', `burst-${i}`))));
    assert.equal(posts.filter(p => p.exists()).length, 1);
  });
  await check('12 simultaneous retries: one post, one slot; later retry preserves earned reach', async () => {
    await reset();
    await Promise.all(Array.from({ length: 12 }, () => publishWithAdmission(env.authenticatedContext(uid).firestore(), uid, 'same-id', post())));
    assert.equal((await getDoc(rateRef)).data().postsInWindow, 1);
    await env.withSecurityRulesDisabled(ctx => updateDoc(doc(ctx.firestore(), 'posts', 'same-id'), { radius: 6000, organicRadiusMeters: 1000, viewCount: 1 }));
    await publish('same-id');
    assert.equal((await getDoc(doc(db, 'posts', 'same-id'))).data().radius, 6000);
    assert.equal((await getDoc(rateRef)).data().postsInWindow, 1);
  });
  await check('invalid post rolls back its slot and private location', async () => {
    await reset(); await assertFails(publish('invalid', {}, post(uid, { radius: 5001, seedRadiusMeters: 5001 })));
    assert.equal((await getDoc(rateRef)).exists(), false);
    assert.equal((await getDoc(doc(db, 'users', uid, 'postLocations', 'invalid'))).exists(), false);
    await publish('valid');
  });
  await check('direct writes and multiple posts per slot fail', async () => {
    await reset(); await assertFails(setDoc(doc(db, 'posts', 'direct'), post()));
    await assertFails(publish('first', { extraPost: 'second' }));
    assert.equal((await getDoc(rateRef)).exists(), false);
    await assertFails(setDoc(rateRef, { ...existingRate(), postId: 'missing', lastPostAt: serverTimestamp() }));
  });
  await check('client timestamps, counter resets and premature window resets fail', async () => {
    await reset(); await seed(`postAdmissions/${uid}`, existingRate({ postsInWindow: 10 }));
    for (const mutateAdmission of [
      a => ({ ...a, lastPostAt: Timestamp.fromMillis(Date.now() + 60000) }),
      a => ({ ...a, lastPostAt: Timestamp.fromMillis(Date.now() - 60000) }),
      a => ({ ...a, postsInWindow: 1 }),
      a => ({ ...a, postsInWindow: 11.5 }),
      a => ({ ...a, windowStartedAt: serverTimestamp() }),
      a => ({ ...a, syntheticBeta: true }),
    ]) await assertFails(publish('forged', { mutateAdmission }));
    assert.equal((await getDoc(rateRef)).data().postsInWindow, 10);
    await publish('honest');
  });
  await check('cooldown uses server time even when the phone clock is advanced', async () => {
    await reset(); await seed(`postAdmissions/${uid}`, existingRate({ lastPostAt: Timestamp.fromMillis(Date.now() - 1000) }));
    await assertFails(publish('fast-clock', { now: Date.now() + 120_000 }));
    await seed(`postAdmissions/${uid}`, existingRate({ lastPostAt: Timestamp.fromMillis(Date.now() - 61_000) }));
    await publish('after-minute');
  });
  await check('legacy count migrates at 29; 30 succeeds and 31 fails', async () => {
    await reset({ postWindowStartMillis: Date.now() - 3_600_000, postsInWindow: 29, lastPostAtMillis: Date.now() - 120_000 });
    await publish('thirtieth');
    assert.equal((await getDoc(rateRef)).data().postsInWindow, 30);
    await env.withSecurityRulesDisabled(ctx => updateDoc(doc(ctx.firestore(), 'postAdmissions', uid), { lastPostAt: Timestamp.fromMillis(Date.now() - 120_000) }));
    await assertFails(publish('thirty-first'));
  });
  await check('legacy cooldown and full day cannot be bypassed by first admission', async () => {
    await reset({ lastPostAtMillis: Date.now() }); await assertFails(publish('recent'));
    await reset({ postWindowStartMillis: Date.now() - 3_600_000, postsInWindow: 30 }); await assertFails(publish('full'));
    await assertFails(publish('reset', { mutateAdmission: a => ({ ...a, postsInWindow: 1, windowStartedAt: serverTimestamp() }) }));
  });
  await check('expired window resets; recent post still requires cooldown', async () => {
    await reset(); await seed(`postAdmissions/${uid}`, existingRate({ postsInWindow: 30, windowStartedAt: Timestamp.fromMillis(Date.now() - 86_401_000) }));
    await publish('new-day'); assert.equal((await getDoc(rateRef)).data().postsInWindow, 1);
    await seed(`postAdmissions/${uid}`, existingRate({ postsInWindow: 30, lastPostAt: Timestamp.now(), windowStartedAt: Timestamp.fromMillis(Date.now() - 86_401_000) }));
    await assertFails(publish('new-day-too-soon'));
  });
  await check('deletion, standalone edits, and reusing the old post ID do not reset admission', async () => {
    await reset(); await publish('delete-me'); await deleteDoc(doc(db, 'posts', 'delete-me'));
    await assertFails(deleteDoc(rateRef)); await assertFails(updateDoc(rateRef, { postsInWindow: 0 }));
    await assertFails(publish('after-delete')); await assertFails(publish('delete-me'));
    assert.equal((await getDoc(rateRef)).data().postsInWindow, 1);
  });
  await check('admissions stay private and cannot charge another account', async () => {
    await reset(); await publish('owned');
    const other = env.authenticatedContext('other-owner').firestore();
    await assertFails(getDoc(doc(other, 'postAdmissions', uid)));
    await assertFails(setDoc(doc(other, 'postAdmissions', uid), existingRate()));
    await assertFails(publishWithAdmission(other, 'other-owner', 'spoof', post()));
    await assertFails(setDoc(doc(env.unauthenticatedContext().firestore(), 'posts', 'anonymous'), post()));
  });
  await check('delayed legacy trigger cannot double-charge the authoritative window', async () => {
    await reset(); await seed(`postAdmissions/${uid}`, existingRate({ postsInWindow: 3 }));
    await seed(`users/${uid}`, { lastPostAtMillis: Date.now(), postWindowStartMillis: Date.now(), postsInWindow: 30 });
    await publish('fourth'); assert.equal((await getDoc(rateRef)).data().postsInWindow, 4);
  });
  await check('new account without legacy state succeeds; hidden/seed rules remain enforced', async () => {
    await env.clearFirestore(); await publish('first-ever');
    await reset(); await assertFails(publish('forged-owner', {}, post('another-owner')));
    await reset({ privateAccount: true });
    await assertFails(publish('precise', {}, post(uid, { locationVisibility: 'approximate', latitude: 25, longitude: 121, latitudeCell: 25000, longitudeCell: 121000 })));
  });
  await check('only existing authenticated synthetic identities keep the cadence exemption', async () => {
    await reset(); await assertFails(setDoc(doc(db, 'posts', 'fake-synthetic'), post(uid, { syntheticBeta: true })));
    const actor = 'sim-atomic-test'; const actorDb = env.authenticatedContext(actor).firestore();
    await publishWithAdmission(actorDb, actor, 'synthetic-1', post(actor));
    await publishWithAdmission(actorDb, actor, 'synthetic-2', post(actor));
    await assertFails(publishWithAdmission(actorDb, actor, 'synthetic-radius-forgery', post(actor, { radius: 5001, seedRadiusMeters: 5001 })));
  });
  console.log(`Atomic post admission: ${checks} scenario groups PASS`);
} finally { await env.cleanup(); }
