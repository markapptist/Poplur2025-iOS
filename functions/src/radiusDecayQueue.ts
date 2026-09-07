import * as admin from 'firebase-admin';
import { createHash } from 'crypto';
import { getFunctions } from 'firebase-admin/functions';
import { Timestamp } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { onTaskDispatched } from 'firebase-functions/v2/tasks';
import { postRadiusParts } from './postEngagementPolicy';
import { millis } from './mapDiscoveryPolicy';
import { runRadiusDecay } from './radiusDecay';
if (!admin.apps.length) admin.initializeApp();
const db=admin.firestore(), region='us-central1';
export const decayShard=(id:string)=>parseInt(createHash('sha256').update(id).digest('hex').slice(0,4),16)%256;
export function needsDecay(post: admin.firestore.DocumentData, now=Date.now()) {
  const parts=postRadiusParts(post,now);
  return parts.organic>0 || (post.syntheticBeta===true && post.simulationRetentionVersion===1 && parts.seed>0);
}
export async function reconcileDecayPost(postId:string) {
  await db.runTransaction(async tx=>{
    const ref=db.doc(`radiusDecayQueue/${postId}`);
    const [post,queue]=await tx.getAll(db.doc(`posts/${postId}`),ref);
    const data=post.data()||{};
    if(!post.exists || !needsDecay(data)) {if(queue.exists)tx.delete(ref);return;}
    const due=millis(data.decayedAt) ? millis(data.decayedAt)+3600_000 : 0;
    if(queue.exists && millis(queue.data()?.dueAt)===due) return;
    tx.set(ref,{shard:decayShard(postId),dueAt:Timestamp.fromMillis(due)});
  });
}
export const radiusDecayIndexChanged=onDocumentWritten({document:'posts/{postId}',region,retry:true,cpu:'gcf_gen1',concurrency:1,maxInstances:4},e=>reconcileDecayPost(e.params.postId));
export async function runDecayShard(shard:number,now=Date.now(),pages=5) {
  let processed=0;
  for(let page=0;page<Math.min(5,pages);page++){
    const due=await db.collection('radiusDecayQueue').where('shard','==',shard).where('dueAt','<=',Timestamp.fromMillis(now)).orderBy('dueAt').limit(200).get();
    if(due.empty)break;
    await runRadiusDecay(now,due.docs.map(d=>db.doc(`posts/${d.id}`)));
    processed+=due.size;
    if(due.size<200)break;
  }
  return processed;
}
export const radiusDecayDispatch=onSchedule({schedule:'every 1 minutes',region,timeoutSeconds:60,cpu:'gcf_gen1',maxInstances:1},async()=>{
  const config=(await db.doc('mapDiscovery/config').get()).data();
  if(config?.dueDecayEnabled!==true)return;
  const minute=Math.floor(Date.now()/60000), first=(minute%8)*32;
  await Promise.all(Array.from({length:32},(_,i)=>getFunctions().taskQueue(`locations/${region}/functions/radiusDecayWorker`)
    .enqueue({shard:first+i},{id:createHash('sha256').update(`decay:${minute}:${first+i}`).digest('hex'),dispatchDeadlineSeconds:300})
    .catch(e=>{if(e.code!=='functions/task-already-exists')throw e;})));
});
export const radiusDecayWorker=onTaskDispatched({region,timeoutSeconds:300,memory:'256MiB',cpu:1,concurrency:8,maxInstances:2,retryConfig:{maxAttempts:8,minBackoffSeconds:10,maxBackoffSeconds:300},rateLimits:{maxConcurrentDispatches:16,maxDispatchesPerSecond:16}},async request=>{
  const shard=request.data?.shard;
  if(!Number.isInteger(shard)||shard<0||shard>255)return;
  if((await db.doc('mapDiscovery/config').get()).data()?.dueDecayEnabled!==true)return;
  await runDecayShard(shard);
});
