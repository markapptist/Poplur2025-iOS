"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.radiusDecayWorker = exports.radiusDecayDispatch = exports.DECAY_DISPATCH_CANDIDATE_LIMIT = exports.DECAY_DISPATCH_INTERVAL_MS = exports.radiusDecayIndexChanged = exports.decayShard = void 0;
exports.needsDecay = needsDecay;
exports.reconcileDecayPost = reconcileDecayPost;
exports.runDecayShard = runDecayShard;
exports.dispatchDueDecay = dispatchDueDecay;
const admin = __importStar(require("firebase-admin"));
const crypto_1 = require("crypto");
const functions_1 = require("firebase-admin/functions");
const firestore_1 = require("firebase-admin/firestore");
const firestore_2 = require("firebase-functions/v2/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const tasks_1 = require("firebase-functions/v2/tasks");
const postEngagementPolicy_1 = require("./postEngagementPolicy");
const mapDiscoveryPolicy_1 = require("./mapDiscoveryPolicy");
const radiusDecay_1 = require("./radiusDecay");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore(), region = 'us-central1';
const decayShard = (id) => parseInt((0, crypto_1.createHash)('sha256').update(id).digest('hex').slice(0, 4), 16) % 256;
exports.decayShard = decayShard;
function needsDecay(post, now = Date.now()) {
    const parts = (0, postEngagementPolicy_1.postRadiusParts)(post, now);
    return post.visibilityStatus !== 'expired' && (parts.organic > 0 || parts.seed > 0 || parts.boost > 0);
}
async function reconcileDecayPost(postId) {
    await db.runTransaction(async (tx) => {
        const ref = db.doc(`radiusDecayQueue/${postId}`);
        const [post, queue] = await tx.getAll(db.doc(`posts/${postId}`), ref);
        const data = post.data() || {};
        if (!post.exists || !needsDecay(data)) {
            if (queue.exists)
                tx.delete(ref);
            return;
        }
        const due = (0, mapDiscoveryPolicy_1.millis)(data.decayedAt) ? (0, mapDiscoveryPolicy_1.millis)(data.decayedAt) + 3600_000 : 0;
        const existingDue = (0, mapDiscoveryPolicy_1.millis)(queue.data()?.dueAt);
        // The worker can schedule the inactivity deadline before the next hourly
        // tick. A post-change trigger must not push that deadline back an hour.
        if (queue.exists && (existingDue === due || (existingDue > (0, mapDiscoveryPolicy_1.millis)(data.decayedAt) && existingDue < due)))
            return;
        tx.set(ref, { shard: (0, exports.decayShard)(postId), dueAt: firestore_1.Timestamp.fromMillis(due) });
    });
}
exports.radiusDecayIndexChanged = (0, firestore_2.onDocumentWritten)({ document: 'posts/{postId}', region, retry: true, cpu: 'gcf_gen1', concurrency: 1, maxInstances: 4 }, e => reconcileDecayPost(e.params.postId));
async function runDecayShard(shard, now = Date.now(), pages = 5) {
    let processed = 0;
    for (let page = 0; page < Math.min(5, pages); page++) {
        const due = await db.collection('radiusDecayQueue').where('shard', '==', shard).where('dueAt', '<=', firestore_1.Timestamp.fromMillis(now)).orderBy('dueAt').limit(200).get();
        if (due.empty)
            break;
        await (0, radiusDecay_1.runRadiusDecay)(now, due.docs.map(d => db.doc(`posts/${d.id}`)));
        processed += due.size;
        if (due.size < 200)
            break;
    }
    return processed;
}
exports.DECAY_DISPATCH_INTERVAL_MS = 5 * 60_000;
exports.DECAY_DISPATCH_CANDIDATE_LIMIT = 256;
/** Find actual due work before launching workers. An idle beta used to
 * launch 46,080 workers/day, each reading configuration and an empty shard.
 * Oldest-first selection drains a backlog across ticks without a full scan;
 * each selected worker can drain up to 1,000 posts in its shard. */
async function dispatchDueDecay(store = db, enqueue = (shard, id) => (0, functions_1.getFunctions)().taskQueue(`locations/${region}/functions/radiusDecayWorker`)
    .enqueue({ shard }, { id, dispatchDeadlineSeconds: 300 }), now = Date.now()) {
    if ((await store.doc('mapDiscovery/config').get()).data()?.dueDecayEnabled !== true)
        return { candidates: 0, dispatched: 0 };
    const due = await store.collection('radiusDecayQueue')
        .where('dueAt', '<=', firestore_1.Timestamp.fromMillis(now)).orderBy('dueAt')
        .limit(exports.DECAY_DISPATCH_CANDIDATE_LIMIT).select('shard').get();
    const shards = [...new Set(due.docs.map(d => d.data().shard))]
        .filter((shard) => Number.isInteger(shard) && shard >= 0 && shard < 256);
    const slot = Math.floor(now / exports.DECAY_DISPATCH_INTERVAL_MS);
    await Promise.all(shards.map(shard => enqueue(shard, (0, crypto_1.createHash)('sha256').update(`due-decay:${slot}:${shard}`).digest('hex'))
        .catch(error => { if (error.code !== 'functions/task-already-exists')
        throw error; })));
    return { candidates: due.size, dispatched: shards.length };
}
exports.radiusDecayDispatch = (0, scheduler_1.onSchedule)({ schedule: 'every 5 minutes', region, timeoutSeconds: 60, cpu: 'gcf_gen1', maxInstances: 1 }, async () => {
    console.log('[radiusDecayDispatch]', await dispatchDueDecay());
});
exports.radiusDecayWorker = (0, tasks_1.onTaskDispatched)({ region, timeoutSeconds: 300, memory: '256MiB', cpu: 1, concurrency: 8, maxInstances: 2, retryConfig: { maxAttempts: 8, minBackoffSeconds: 10, maxBackoffSeconds: 300 }, rateLimits: { maxConcurrentDispatches: 16, maxDispatchesPerSecond: 16 } }, async (request) => {
    const shard = request.data?.shard;
    if (!Number.isInteger(shard) || shard < 0 || shard > 255)
        return;
    if ((await db.doc('mapDiscovery/config').get()).data()?.dueDecayEnabled !== true)
        return;
    await runDecayShard(shard);
});
