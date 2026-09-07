// Explicit project, resumable administrator migration. No credentials are logged.
const admin=require('firebase-admin');
const project=process.argv[2], mode=process.argv[3];
if(!project || !['backfill','status','verify','enable','requeue'].includes(mode)) throw new Error('Usage: node mapDiscoveryAdmin.js PROJECT backfill|status|verify|enable|requeue');
admin.initializeApp({projectId:project});
const db=admin.firestore(), m=require('../lib/mapDiscovery');
(async()=>{
 if(mode==='backfill'){
  for(const [phase,run] of [['posts',m.backfillMapDiscovery],['engagements',m.backfillMapEngagements]]){
   for(;;){const s=await run();console.log(JSON.stringify({phase,processed:s.processed,complete:s.complete}));if(s.complete)break;}
  }
 }
 if(mode==='requeue'){
  const jobs=await db.collection('mapDiscoveryJobs').where('dueAt','<=',admin.firestore.Timestamp.now()).limit(500).get();
  const b=db.batch();for(const j of jobs.docs)b.update(j.ref,{generation:admin.firestore.FieldValue.increment(1),dueAt:admin.firestore.Timestamp.now()});if(jobs.size)await b.commit();console.log({requeued:jobs.size});
 }
 if(mode==='status'){
  for(const name of ['mapPostIndex','mapPostRanks','mapCellSummaries','mapRegionSummaries','mapDiscoveryJobs','radiusDecayQueue']) console.log(name,(await db.collection(name).count().get()).data().count);
  console.log({config:(await db.doc('mapDiscovery/config').get()).data()});
 }
 if(mode==='verify'){
  const owner=(await db.doc('testControl/syntheticDailySimulation').get()).data()?.ownerUid;
  if(!owner)throw new Error('No configured rollout owner');
  await db.doc('mapDiscovery/config').set({canaryUids:admin.firestore.FieldValue.arrayUnion(owner)},{merge:true});
  const indexes=await db.collection('mapPostIndex').limit(100).get();
  const runs=[];
  const queries=[{bounds:{west:-180,east:180,south:-90,north:90},zoom:2,includeTest:true},...indexes.docs.slice(0,10).map(d=>{const p=d.data();return {bounds:{west:p.longitude-.01,east:p.longitude+.01,south:Math.max(-90,p.latitude-.01),north:Math.min(90,p.latitude+.01)},zoom:14,includeTest:true}})];
  for(const query of queries){const start=Date.now(),r=await m.runMapDiscoveryQuery(owner,query);if(!r.enabled)throw new Error('Canary disabled');if(r.posts.length>200)throw new Error('Feature budget exceeded');runs.push({mode:r.mode,posts:r.posts.length,bytes:Buffer.byteLength(JSON.stringify(r)),milliseconds:Date.now()-start,hasNext:Boolean(r.nextCursor)});}
  if(!runs.some(r=>r.posts>0))throw new Error('No discoverable posts');
  console.log(JSON.stringify({verified:true,runs},null,2));
 }
 if(mode==='enable'){
  const [posts,engagements]=await db.getAll(db.doc('mapDiscovery/migration'),db.doc('mapDiscovery/engagementMigration'));
  if(!posts.data()?.complete || !engagements.data()?.complete)throw new Error('Migration incomplete');
  const summaries=await db.collection('mapRegionSummaries').limit(1).get();if(summaries.empty)throw new Error('No region summaries');
  await db.doc('mapDiscovery/config').set({enabled:true,dueDecayEnabled:true,enabledAt:admin.firestore.FieldValue.serverTimestamp(),schema:1},{merge:true});
  console.log({enabled:true,dueDecayEnabled:true});
 }
})().catch(e=>{console.error(e.message);process.exitCode=1}).finally(()=>admin.app().delete());
