// Demo-project emulators only: never seed, count, or mutate production data.
const assert = require('node:assert/strict');
if (!process.env.GCLOUD_PROJECT?.startsWith('demo-')
  || !/^127\.0\.0\.1:\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || '')
  || !/^127\.0\.0\.1:\d+$/.test(process.env.FIREBASE_AUTH_EMULATOR_HOST || '')) {
  throw new Error('Run npm run test:beta-costs against the local demo emulators.');
}
const admin = require('firebase-admin');
admin.initializeApp({projectId:process.env.GCLOUD_PROJECT});
const db = admin.firestore(), {Timestamp} = admin.firestore;
const {dispatchDueDecay, reconcileDecayPost, runDecayShard, decayShard,
  DECAY_DISPATCH_CANDIDATE_LIMIT} = require('../lib/radiusDecayQueue');
const {runSyntheticDailySimulation} = require('../lib/syntheticDailySimulation');

(async()=>{
  const now = Date.parse('2026-09-08T12:00:00Z');
  const jobs = [];
  const enqueue = async(shard,id)=>{jobs.push({shard,id});};
  assert.deepEqual(await dispatchDueDecay(db,enqueue,now),{candidates:0,dispatched:0});
  await db.doc('mapDiscovery/config').set({dueDecayEnabled:true});
  assert.deepEqual(await dispatchDueDecay(db,enqueue,now),{candidates:0,dispatched:0});
  assert.equal(jobs.length,0,'an empty queue must not launch any workers');

  await db.doc('users/owner').set({claimRadiusMeters:100000});
  const post = {userID:'owner',seedRadiusMeters:5000,organicRadiusMeters:10000,
    radiusMeters:15000,decayedAt:Timestamp.fromMillis(now-4*3600_000)};
  // Two posts in one shard prove dispatch deduplicates by actual due shard.
  const first='cost-test-0', shard=decayShard(first);
  let same='';
  for(let i=1;!same;i++)if(decayShard(`cost-test-${i}`)===shard)same=`cost-test-${i}`;
  const future='cost-test-future';
  for(const id of [first,same]){await db.doc(`posts/${id}`).set(post);await reconcileDecayPost(id);}
  await db.doc(`posts/${future}`).set({...post,decayedAt:Timestamp.fromMillis(now)});
  await reconcileDecayPost(future);
  assert.deepEqual(await dispatchDueDecay(db,enqueue,now),{candidates:2,dispatched:1});
  assert.equal(jobs[0].shard,shard);
  await dispatchDueDecay(db,enqueue,now+1000);
  assert.equal(jobs[0].id,jobs[1].id,'scheduler retries use the same task id');
  await dispatchDueDecay(db,async()=>{throw {code:'functions/task-already-exists'};},now);
  await assert.rejects(()=>dispatchDueDecay(db,async()=>{throw new Error('transport failure');},now));
  await runDecayShard(shard,now);
  const radius=(await db.doc(`posts/${first}`).get()).data().radiusMeters;
  assert(radius<15000,'elapsed radius decay must still happen');
  await runDecayShard(shard,now);
  assert.equal((await db.doc(`posts/${first}`).get()).data().radiusMeters,radius,'retry must not charge decay twice');
  assert.equal((await db.doc(`posts/${future}`).get()).data().radiusMeters,15000);
  assert.equal((await db.collection(`posts/${first}/radiusHistory`).get()).size,1);
  assert.deepEqual(await dispatchDueDecay(db,enqueue,now),{candidates:0,dispatched:0});

  const batch=db.batch();
  for(let i=0;i<DECAY_DISPATCH_CANDIDATE_LIMIT+10;i++)batch.set(db.doc(`radiusDecayQueue/backlog-${i}`),{
    shard:i%256,dueAt:Timestamp.fromMillis(now-10000+i),
  });
  await batch.commit();
  assert.equal((await dispatchDueDecay(db,enqueue,now)).candidates,DECAY_DISPATCH_CANDIDATE_LIMIT,'backlog reads stay bounded');
  assert.deepEqual(await dispatchDueDecay(db,enqueue,now-20000),{candidates:0,dispatched:0});

  await db.doc('testControl/syntheticDailySimulation').set({enabled:false});
  await db.doc('testControl/syntheticBrowserRunner').set({enabled:true});
  assert.equal((await runSyntheticDailySimulation(now)).status,'paused');
  await db.doc('testControl/syntheticDailySimulation').set({enabled:true});
  await db.doc('testControl/syntheticBrowserRunner').set({enabled:false});
  assert.equal((await runSyntheticDailySimulation(now)).status,'paused');
  assert.equal((await db.collection('testDailySimulationRuns').get()).size,0);
  console.log('Beta cost controls: PASS (idle=0 workers, due-only dispatch, retry safety, bounded backlog, elapsed decay, production simulation switches).');
})().catch(error=>{console.error(error);process.exitCode=1;}).finally(()=>admin.app().delete());
