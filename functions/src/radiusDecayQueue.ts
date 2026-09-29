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
  return post.visibilityStatus !== 'expired' && (parts.organic > 0 || parts.seed > 0 || parts.boost > 0);
}
export async function reconcileDecayPost(postId:string) {
  await db.runTransaction(async tx=>{
    const ref=db.doc(`radiusDecayQueue/${postId}`);
    const [post,queue]=await tx.getAll(db.doc(`posts/${postId}`),ref);
    const data=post.data()||{};
    if(!post.exists || !needsDecay(data)) {if(queue.exists)tx.delete(ref);return;}
    const due=millis(data.decayedAt) ? millis(data.decayedAt)+3600_000 : 0;
    const existingDue=millis(queue.data()?.dueAt);
    // The worker can schedule the inactivity deadline before the next hourly
    // tick. A post-change trigger must not push that deadline back an hour.
    if(queue.exists && (existingDue===due || (existingDue>millis(data.decayedAt) && existingDue<due))) return;
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
export const DECAY_DISPATCH_INTERVAL_MS = 5 * 60_000;
export const DECAY_DISPATCH_CANDIDATE_LIMIT = 256;

/** Find actual due work before launching workers. An idle beta used to
 * launch 46,080 workers/day, each reading configuration and an empty shard.
 * Oldest-first selection drains a backlog across ticks without a full scan;
 * each selected worker can drain up to 1,000 posts in its shard. */
export async function dispatchDueDecay(
  store: admin.firestore.Firestore = db,
  enqueue: (shard: number, taskId: string) => Promise<unknown> = (shard, id) =>
    getFunctions().taskQueue(`locations/${region}/functions/radiusDecayWorker`)
      .enqueue({shard}, {id, dispatchDeadlineSeconds:300}),
  now = Date.now(),
): Promise<{ candidates: number; dispatched: number }> {
  if ((await store.doc('mapDiscovery/config').get()).data()?.dueDecayEnabled !== true)
    return {candidates:0, dispatched:0};
  const due = await store.collection('radiusDecayQueue')
    .where('dueAt','<=',Timestamp.fromMillis(now)).orderBy('dueAt')
    .limit(DECAY_DISPATCH_CANDIDATE_LIMIT).select('shard').get();
  const shards = [...new Set(due.docs.map(d=>d.data().shard))]
    .filter((shard): shard is number => Number.isInteger(shard) && shard >= 0 && shard < 256);
  const slot = Math.floor(now / DECAY_DISPATCH_INTERVAL_MS);
  await Promise.all(shards.map(shard => enqueue(shard,
    createHash('sha256').update(`due-decay:${slot}:${shard}`).digest('hex'))
    .catch(error=>{if(error.code!=='functions/task-already-exists')throw error;})));
  return {candidates:due.size, dispatched:shards.length};
}
export const radiusDecayDispatch=onSchedule({schedule:'every 5 minutes',region,timeoutSeconds:60,cpu:'gcf_gen1',maxInstances:1},async()=>{
  console.log('[radiusDecayDispatch]', await dispatchDueDecay());
});
export const radiusDecayWorker=onTaskDispatched({region,timeoutSeconds:300,memory:'256MiB',cpu:1,concurrency:8,maxInstances:2,retryConfig:{maxAttempts:8,minBackoffSeconds:10,maxBackoffSeconds:300},rateLimits:{maxConcurrentDispatches:16,maxDispatchesPerSecond:16}},async request=>{
  const shard=request.data?.shard;
  if(!Number.isInteger(shard)||shard<0||shard>255)return;
  if((await db.doc('mapDiscovery/config').get()).data()?.dueDecayEnabled!==true)return;
  await runDecayShard(shard);
});
