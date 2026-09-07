const assert = require('node:assert/strict');
const admin = require('firebase-admin');
if(!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error('Emulators required');
admin.initializeApp({projectId:'demo-poplur-simulation'});
const {runSyntheticDailySimulation} = require('../lib/syntheticDailySimulation');
const {SYNTHETIC_BETA_PROFILES} = require('../lib/syntheticBetaCohort');
(async()=>{
const db=admin.firestore();
await db.doc('testControl/syntheticDailySimulation').set({enabled:true,ownerUid:'owner'});
await db.doc('testControl/syntheticBrowserRunner').set({enabled:true});
for (const profile of SYNTHETIC_BETA_PROFILES) {await admin.auth().createUser({uid:profile.id});await db.doc('users/'+profile.id).set({username:profile.id,syntheticBeta:true});}
await admin.auth().createUser({uid:'owner'});
await db.doc('users/owner').set({username:'owner',claimRadiusMeters:10000});
await db.doc('posts/post-fixture-official').set({officialContent:true,mediaURL:'https://example.com/fixture.jpg',mediaType:'photo',userID:'official',createdAtMillis:1});
await db.doc('posts/post-owner').set({userID:'owner',mediaURL:'https://example.com/owner.jpg',radius:10000,organicRadiusMeters:10000,createdAtMillis:2});
const now=Date.parse('2026-09-07T15:00:00Z');
const first=await runSyntheticDailySimulation(now);
assert.equal(first.status,'complete');assert.equal(first.testers,10);assert.equal(first.dailyPostTarget,20);
assert.equal((await db.collection('posts').where('syntheticSource','==','scheduled-test-simulation').get()).size,20);
const comments=await db.collection('posts/post-owner/comments').get();assert(comments.size>0);
const before=(await db.doc('posts/post-owner').get()).data().commentCount;
const second=await runSyntheticDailySimulation(now+1000);assert.equal(second.status,'already-running-or-complete');
assert.equal((await db.doc('posts/post-owner').get()).data().commentCount,before);
const next=await runSyntheticDailySimulation(now+86400000);assert.equal(next.testers,12);assert.equal(next.dailyPostTarget,24);
assert.equal((await db.collection('testDailySimulationActors').get()).size,4);
console.log('daily simulation emulator: PASS (20 then 24 posts, retries do not duplicate, real comments persisted)');
})().catch(e=>{console.error(e);process.exitCode=1});
