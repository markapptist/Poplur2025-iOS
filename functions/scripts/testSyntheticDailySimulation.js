const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if(!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error('Emulators required');
admin.initializeApp({projectId:'demo-poplur-simulation'});
const {runSyntheticDailySimulation} = require('../lib/syntheticDailySimulation');
const {SYNTHETIC_BETA_PROFILES} = require('../lib/syntheticBetaCohort');
const {runRadiusDecay}=require('../lib/radiusDecay');
(async()=>{
const db=admin.firestore();
await db.doc('testControl/radiusDecayTrial').delete(); // Keep the retention fixture independent of other emulator suites.
await db.doc('testControl/syntheticDailySimulation').set({enabled:true,ownerUid:'owner'});
await db.doc('testControl/syntheticBrowserRunner').set({enabled:true});
for (const profile of SYNTHETIC_BETA_PROFILES) {await admin.auth().createUser({uid:profile.id});await db.doc('users/'+profile.id).set({username:profile.id,syntheticBeta:true});}
await admin.auth().createUser({uid:'owner'});
await db.doc('users/owner').set({username:'owner',claimRadiusMeters:10000});
await db.doc('posts/post-fixture-official').set({officialContent:true,mediaURL:'https://example.com/fixture.jpg',mediaType:'photo',userID:'official',createdAtMillis:1});
await db.doc('posts/post-owner').set({userID:'owner',mediaURL:'https://example.com/owner.jpg',radius:10000,organicRadiusMeters:10000,createdAtMillis:2});
const now=Date.parse('2026-09-07T15:00:00Z');
const first=await runSyntheticDailySimulation(now);
assert.equal(first.status,'complete');assert.equal(first.testers,10);assert.equal(first.dailyPostTarget,240);
assert.equal(first.hourlyPostTarget,10);
assert.equal((await db.collection('posts').where('syntheticSource','==','scheduled-test-simulation').get()).size,10);
const comments=await db.collection('posts/post-owner/comments').get();assert(comments.size>0);
const before=(await db.doc('posts/post-owner').get()).data().commentCount;
const second=await runSyntheticDailySimulation(now+1000);assert.equal(second.status,'already-running-or-complete');
assert.equal((await db.doc('posts/post-owner').get()).data().commentCount,before);
const hourly=await runSyntheticDailySimulation(now+3600000);assert.equal(hourly.postsCreatedThisAttempt,10);
const old=(await db.collection('posts').where('syntheticSource','==','scheduled-test-simulation').get()).docs.find(d=>d.data().createdAtMillis===now);
const original=old.data().radiusMeters;
await runRadiusDecay(now+4*3600000);
const decayed=(await old.ref.get()).data();assert(decayed.radiusMeters<original);assert(decayed.seedRadiusMeters<5000);
const decayHistory=(await old.ref.collection('radiusHistory').get()).docs.map(d=>d.data()).find(d=>d.cause==='decay');
assert.equal(decayHistory.seedRadiusMeters,decayed.seedRadiusMeters);
assert.equal(decayHistory.radiusMeters,decayed.radiusMeters);
assert((await db.collection('testRetentionDecaySlots').get()).size>0);
const next=await runSyntheticDailySimulation(now+86400000);assert.equal(next.testers,12);assert.equal(next.dailyPostTarget,288);
assert.equal((await db.collection('testDailySimulationActors').get()).size,4);
// Disabling the optional owner target must leave people alone while the
// cohort still exercises production posting/engagement/radius transactions.
await db.doc('testControl/syntheticDailySimulation').update({ownerUid:''});
const ownerBefore=(await db.doc('posts/post-owner').get()).data();
const cohortOnly=await runSyntheticDailySimulation(now+2*86400000);
assert.equal(cohortOnly.status,'complete');assert(cohortOnly.engagementsThisAttempt>0);
assert.deepEqual((await db.doc('posts/post-owner').get()).data(),ownerBefore);
console.log('Cohort-only simulation: real owner receives no synthetic writes; test accounts still engage');
console.log('hourly retention simulation emulator: PASS (new content each hour, same-slot retry deduped, seed/earned decay, comments retained)');
})().catch(e=>{console.error(e);process.exitCode=1});
