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
exports.queryMapDiscovery = exports.repairMapDiscovery = exports.mapDiscoveryWorker = exports.mapDiscoveryEnqueue = exports.mapDiscoveryOwnerChanged = exports.mapDiscoveryEngagement = exports.mapDiscoveryPostChanged = void 0;
exports.dirtyMapSummary = dirtyMapSummary;
exports.reconcileMapPost = reconcileMapPost;
exports.rankMapEngagement = rankMapEngagement;
exports.rebuildMapSummary = rebuildMapSummary;
exports.processMapJob = processMapJob;
exports.hydrateMapCandidates = hydrateMapCandidates;
exports.runMapDiscoveryQuery = runMapDiscoveryQuery;
exports.backfillMapDiscovery = backfillMapDiscovery;
exports.backfillMapEngagements = backfillMapEngagements;
const admin = __importStar(require("firebase-admin"));
const crypto_1 = require("crypto");
const firestore_1 = require("firebase-admin/firestore");
const functions_1 = require("firebase-admin/functions");
const firestore_2 = require("firebase-functions/v2/firestore");
const tasks_1 = require("firebase-functions/v2/tasks");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const https_1 = require("firebase-functions/v2/https");
const radiusDecayQueue_1 = require("./radiusDecayQueue");
const mapDiscoveryPolicy_1 = require("./mapDiscoveryPolicy");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
const region = 'us-central1';
const sha = (s) => (0, crypto_1.createHash)('sha256').update(s).digest('hex');
const ownerId = (p) => String(p.userID || p.userId || '');
const safeId = (s) => typeof s === 'string' && /^[\w.-]{1,180}$/.test(s);
/** Durable, sharded invalidation outbox. Repeated events coalesce for 30s;
 * different posts do not contend on one worldwide/cell counter. */
async function dirtyMapSummary(kind, key, cohort, source, delay = 30) {
    const bucket = parseInt(sha(source).slice(0, 4), 16) % 64;
    const id = sha(`${kind}:${cohort}:${key}:${bucket}`);
    const ref = db.doc(`mapDiscoveryJobs/${id}`);
    await db.runTransaction(async (tx) => {
        const existing = await tx.get(ref);
        if (existing.exists) {
            tx.update(ref, { version: firestore_1.FieldValue.increment(1) });
            return;
        }
        tx.create(ref, { kind, key, cohort, version: 1, generation: Date.now(), shard: bucket % 16,
            dueAt: firestore_1.Timestamp.fromMillis(Date.now() + delay * 1000) });
    });
}
async function reconcileMapPost(postId) {
    const ref = db.doc(`mapPostIndex/${postId}`);
    await db.runTransaction(async (tx) => {
        const [postSnap, previous, rankSnap] = await tx.getAll(db.doc(`posts/${postId}`), ref, db.doc(`mapPostRanks/${postId}`));
        const post = postSnap.data() || {}, uid = ownerId(post);
        const user = safeId(uid) ? await tx.get(db.doc(`users/${uid}`)) : null;
        const old = previous.data();
        let next = null;
        if (postSnap.exists && user?.exists && (0, mapDiscoveryPolicy_1.eligibleMapPost)(post, user.data() || {})) {
            const rank = rankSnap.data();
            const created = (0, mapDiscoveryPolicy_1.millis)(post.createdAt) || (0, mapDiscoveryPolicy_1.millis)(post.createdAtMillis) || Date.now();
            const cell = (0, mapDiscoveryPolicy_1.competitionCell)(post.latitude, post.longitude);
            next = { postId, ownerId: uid, cellId: cell.id, cohort: (0, mapDiscoveryPolicy_1.postCohort)(post, user.data() || {}),
                latitude: post.latitude, longitude: post.longitude, createdAtMillis: created,
                rankKey: (0, mapDiscoveryPolicy_1.rankKey)(rank || {}, created), exposure: rank?.views || 0, rankAt: rank?.at || created,
                rankBucket: Math.floor((rank?.at || created) / mapDiscoveryPolicy_1.RANK_WINDOW_MS), rankEligible: (rank?.views || 0) >= 5,
                expiresAtMillis: Math.max(created, rank?.at || 0) + mapDiscoveryPolicy_1.RANK_MAX_AGE_MS };
        }
        const same = !old && !next || old && next && Object.keys(old).length === Object.keys(next).length
            && Object.entries(next).every(([key, value]) => old[key] === value);
        if (same && (postSnap.exists || !rankSnap.exists))
            return;
        const bucket = parseInt(sha(postId).slice(0, 4), 16) % 64;
        const cells = [...new Map([old, next].filter(Boolean).map(c => [`${c.cohort}:${c.cellId}`, c])).values()];
        const jobs = cells.map(c => db.doc(`mapDiscoveryJobs/${sha(`cell:${c.cohort}:${c.cellId}:${bucket}`)}`));
        const pending = jobs.length ? await tx.getAll(...jobs) : [];
        if (!postSnap.exists && rankSnap.exists)
            tx.delete(rankSnap.ref);
        if (next)
            tx.set(ref, next);
        else if (previous.exists)
            tx.delete(ref);
        cells.forEach((c, i) => {
            if (pending[i].exists)
                tx.update(jobs[i], { version: firestore_1.FieldValue.increment(1) });
            else
                tx.create(jobs[i], { kind: 'cell', key: c.cellId, cohort: c.cohort, version: 1,
                    generation: Date.now(), shard: bucket % 16, dueAt: firestore_1.Timestamp.fromMillis(Date.now() + 30_000) });
        });
    });
}
/** Rank only accepted server engagement receipts. One actor/kind per six-hour
 * window; owner reactions and synthetic actors cannot elect real winners. */
async function rankMapEngagement(postId, eventId, event) {
    const uid = event.actorUid, kind = event.kind;
    if (!safeId(uid) || !['view', 'like', 'comment', 'dislike'].includes(kind) || event.applied === false)
        return;
    const now = (0, mapDiscoveryPolicy_1.millis)(event.createdAt) || Date.now();
    const receipt = db.doc(`mapRankReceipts/${sha(`${postId}:${eventId}`)}`);
    const unique = db.doc(`mapRankActors/${sha(`${postId}:${uid}:${kind}:${Math.floor(now / mapDiscoveryPolicy_1.RANK_WINDOW_MS)}`)}`);
    await db.runTransaction(async (tx) => {
        const [seen, actorSeen, postSnap, actor, rank] = await tx.getAll(receipt, unique, db.doc(`posts/${postId}`), db.doc(`users/${uid}`), db.doc(`mapPostRanks/${postId}`));
        if (seen.exists)
            return;
        const post = postSnap.data() || {}, owner = ownerId(post);
        if (!postSnap.exists || !safeId(owner) || owner === uid)
            return;
        const [user, blocked, reverse] = await tx.getAll(db.doc(`users/${owner}`), db.doc(`users/${owner}/blocked/${uid}`), db.doc(`users/${uid}/blocked/${owner}`));
        if (!user.exists || !actor.exists || blocked.exists || reverse.exists || !(0, mapDiscoveryPolicy_1.eligibleMapPost)(post, user.data() || {}))
            return;
        if ((0, mapDiscoveryPolicy_1.postCohort)(post, user.data() || {}) === 'real' && actor.data()?.syntheticBeta === true)
            return;
        const expiry = firestore_1.Timestamp.fromMillis(Date.now() + 7 * 86400_000);
        tx.create(receipt, { expiresAt: expiry });
        if (actorSeen.exists)
            return;
        tx.create(unique, { expiresAt: expiry });
        // Out-of-order event delivery cannot move the score clock backwards.
        const at = Math.max(now, Number(rank.data()?.at || 0));
        const gain = Number(event.radiusDeltaMeters || 0);
        const next = (0, mapDiscoveryPolicy_1.advanceRank)(rank.data() || {}, at, kind, gain);
        tx.set(rank.ref, next);
    });
    // Retry-safe even if the process died between committing rank and projection.
    await reconcileMapPost(postId);
}
async function rebuildMapSummary(kind, key, cohort) {
    const target = db.doc(`${kind === 'cell' ? 'mapCellSummaries' : 'mapRegionSummaries'}/${cohort}_${key}`);
    const now = Date.now();
    const cell = kind === 'cell' ? (0, mapDiscoveryPolicy_1.parseCell)(key) : null;
    const tile = cell ? (0, mapDiscoveryPolicy_1.regionAt)(cell.center[1], cell.center[0]) : (0, mapDiscoveryPolicy_1.parseRegion)(key);
    const parent = cell ? tile : (0, mapDiscoveryPolicy_1.parentRegion)(tile);
    const result = await db.runTransaction(async (tx) => {
        const previous = await tx.get(target);
        let candidates;
        if (cell) {
            const base = db.collection('mapPostIndex').where('cohort', '==', cohort).where('cellId', '==', key);
            const bucket = Math.floor(now / mapDiscoveryPolicy_1.RANK_WINDOW_MS);
            // Thirteen six-hour buckets bound both document reads and index scans,
            // even when a hot cell contains millions of old posts. Each contributes
            // its strongest sixteen qualified candidates; new posts get 32 slots.
            const pages = await Promise.all([
                ...Array.from({ length: 13 }, (_, i) => tx.get(base.where('rankBucket', '==', bucket - i)
                    .where('rankEligible', '==', true).orderBy('rankKey', 'desc').limit(16))),
                tx.get(base.orderBy('createdAtMillis', 'desc').limit(32)),
            ]);
            candidates = [...new Map(pages.flatMap(page => page.docs).map(d => [d.id, d.data()])).values()];
        }
        else if (tile.z === mapDiscoveryPolicy_1.REGION_DEPTH) {
            const children = await tx.get(db.collection('mapCellSummaries').where('cohort', '==', cohort).where('leaf', '==', key).limit(192));
            candidates = children.docs.flatMap(d => summaryCandidates(d.data()));
        }
        else {
            const children = await tx.getAll(...(0, mapDiscoveryPolicy_1.regionChildren)(tile).map(r => db.doc(`mapRegionSummaries/${cohort}_${(0, mapDiscoveryPolicy_1.regionId)(r)}`)));
            candidates = children.flatMap(d => summaryCandidates(d.data()));
        }
        const old = previous.data();
        const choice = (0, mapDiscoveryPolicy_1.chooseChampion)(candidates, old || {}, now, Boolean(cell));
        const alternates = candidates.filter(c => c.expiresAtMillis > now && c.postId !== choice.winner?.postId)
            .sort((a, b) => b.rankKey - a.rankKey).slice(0, 4);
        const next = { ...choice, alternates, updatedAtMillis: now, cohort, ...(cell ? { leaf: (0, mapDiscoveryPolicy_1.regionId)(tile) } : {}) };
        tx.set(target, next);
        const winner = choice.winner;
        const qualificationEnds = winner && (0, mapDiscoveryPolicy_1.qualifiedWinner)(winner, now)
            ? winner.rankAt + Math.log(winner.exposure / 5) * (6 * 3600_000 / Math.LN2) + 1000 : Infinity;
        const nextDue = winner ? Math.min(winner.expiresAtMillis + 1000, qualificationEnds) : 0;
        return { changed: JSON.stringify(summaryCandidates(old)) !== JSON.stringify(summaryCandidates(next)), challenger: Boolean(choice.challengerId), nextDue };
    });
    if (result.changed && parent)
        await dirtyMapSummary('region', (0, mapDiscoveryPolicy_1.regionId)(parent), cohort, key, 5);
    return result;
}
async function processMapJob(id, generation) {
    const ref = db.doc(`mapDiscoveryJobs/${id}`), snap = await ref.get(), job = snap.data();
    if (!job || (generation != null && generation !== job.generation))
        return;
    let repeat = false, nextDue = 0;
    if (job.kind === 'owner') {
        // Privacy is enforced at read time immediately. This paged repair removes
        // stale index candidates and reintroduces newly public posts asynchronously.
        const field = job.field || 'userID';
        let q = db.collection('posts').where(field, '==', job.key).orderBy(firestore_1.FieldPath.documentId()).limit(100);
        if (job.cursor)
            q = q.startAfter(job.cursor);
        const posts = await q.get();
        await Promise.all(posts.docs.map(p => reconcileMapPost(p.id)));
        if (posts.size === 100) {
            await ref.update({ cursor: posts.docs[99].id });
            repeat = true;
        }
        else if (field === 'userID') {
            await ref.update({ field: 'userId', cursor: firestore_1.FieldValue.delete() });
            repeat = true;
        }
    }
    else {
        const rebuilt = await rebuildMapSummary(job.kind, job.key, job.cohort);
        repeat = rebuilt.challenger;
        // One durable timer per summary, not one timer per invalidation shard.
        const clockId = sha(`clock:${job.cohort}:${job.kind}:${job.key}`);
        if (id === clockId)
            nextDue = rebuilt.nextDue;
        else if (rebuilt.nextDue > 0) {
            const clock = db.doc(`mapDiscoveryJobs/${clockId}`);
            await db.runTransaction(async (tx) => {
                const old = await tx.get(clock);
                if (!old.exists)
                    tx.create(clock, { kind: job.kind, key: job.key, cohort: job.cohort,
                        version: 1, generation: Date.now(), shard: parseInt(clockId.slice(0, 2), 16) % 16,
                        dueAt: firestore_1.Timestamp.fromMillis(rebuilt.nextDue) });
                else if (old.data().dueAt.toMillis() > rebuilt.nextDue)
                    tx.update(clock, {
                        generation: firestore_1.FieldValue.increment(1), dueAt: firestore_1.Timestamp.fromMillis(rebuilt.nextDue), version: firestore_1.FieldValue.increment(1),
                    });
            });
        }
    }
    await db.runTransaction(async (tx) => {
        const current = await tx.get(ref);
        if (!current.exists || current.data()?.generation !== job.generation)
            return;
        if (repeat || current.data()?.version !== job.version || nextDue > 0)
            tx.update(ref, {
                generation: job.generation + 1, dueAt: firestore_1.Timestamp.fromMillis(repeat || current.data()?.version !== job.version ? Date.now() + (repeat && job.kind === 'cell' ? 120 : 30) * 1000 : Math.max(Date.now() + 1000, nextDue)),
            });
        else
            tx.delete(ref);
    });
}
exports.mapDiscoveryPostChanged = (0, firestore_2.onDocumentWritten)({ document: 'posts/{postId}', region, retry: true, memory: '256MiB', cpu: 'gcf_gen1', concurrency: 1, maxInstances: 4 }, e => reconcileMapPost(e.params.postId));
exports.mapDiscoveryEngagement = (0, firestore_2.onDocumentCreated)({ document: 'posts/{postId}/engagements/{engagementId}', region, retry: true, memory: '256MiB', cpu: 'gcf_gen1', concurrency: 1, maxInstances: 4 }, e => rankMapEngagement(e.params.postId, e.params.engagementId, e.data?.data() || {}));
exports.mapDiscoveryOwnerChanged = (0, firestore_2.onDocumentWritten)({ document: 'users/{uid}', region, retry: true, memory: '256MiB', cpu: 'gcf_gen1', concurrency: 1, maxInstances: 4 }, async (e) => {
    const before = e.data?.before.data(), after = e.data?.after.data();
    if (['privateAccount', 'ghostMode', 'disabled', 'syntheticBeta'].every(k => before?.[k] === after?.[k]) && Boolean(before) === Boolean(after))
        return;
    await dirtyMapSummary('owner', e.params.uid, 'real', e.params.uid, 0);
});
exports.mapDiscoveryEnqueue = (0, firestore_2.onDocumentWritten)({ document: 'mapDiscoveryJobs/{jobId}', region, retry: true, memory: '256MiB', cpu: 'gcf_gen1', concurrency: 1, maxInstances: 4 }, async (e) => {
    const job = e.data?.after.data();
    if (!job || e.data?.before.data()?.generation === job.generation)
        return;
    try {
        await (0, functions_1.getFunctions)().taskQueue(`locations/${region}/functions/mapDiscoveryWorker`).enqueue({ id: e.params.jobId, generation: job.generation }, {
            id: sha(`${e.params.jobId}:${job.generation}`), scheduleTime: new Date(Math.max(Date.now(), job.dueAt.toMillis())), dispatchDeadlineSeconds: 180,
        });
    }
    catch (error) {
        if (error.code !== 'functions/task-already-exists')
            throw error;
    }
});
exports.mapDiscoveryWorker = (0, tasks_1.onTaskDispatched)({ region, timeoutSeconds: 180, memory: '512MiB', cpu: 1, maxInstances: 2, concurrency: 8, retryConfig: { maxAttempts: 8, minBackoffSeconds: 10, maxBackoffSeconds: 300 }, rateLimits: { maxConcurrentDispatches: 16, maxDispatchesPerSecond: 16 } }, async (request) => {
    if (typeof request.data.id !== 'string' || !/^[a-f0-9]{64}$/.test(request.data.id))
        return;
    await processMapJob(request.data.id, request.data.generation);
});
exports.repairMapDiscovery = (0, scheduler_1.onSchedule)({ schedule: 'every 10 minutes', region, timeoutSeconds: 300, cpu: 'gcf_gen1', maxInstances: 1 }, async () => {
    for (let shard = 0; shard < 16; shard++) {
        const overdue = await db.collection('mapDiscoveryJobs').where('shard', '==', shard).where('dueAt', '<', firestore_1.Timestamp.fromMillis(Date.now() - 10 * 60_000)).limit(100).get();
        const batch = db.batch();
        for (const job of overdue.docs)
            batch.update(job.ref, { generation: firestore_1.FieldValue.increment(1), dueAt: firestore_1.Timestamp.now() });
        if (!overdue.empty)
            await batch.commit();
    }
});
function queryFingerprint(input, uid) { return sha(JSON.stringify({ bounds: input.bounds, zoom: input.zoom, includeTest: input.includeTest, uid })).slice(0, 24); }
function decodeCursor(cursor, fingerprint) {
    if (!cursor)
        return null;
    try {
        const c = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
        if (c.f !== fingerprint || !safeId(c.id) || !Number.isFinite(c.at) || c.at < 0)
            throw new Error();
        return c;
    }
    catch {
        throw new https_1.HttpsError('invalid-argument', 'This map page has expired. Refresh the area.');
    }
}
/** Only a whitelist leaves the server; documents/ranking identities never do. */
const PUBLIC_FIELDS = ['userID', 'userId', 'username', 'handle', 'displayName', 'latitude', 'longitude', 'radiusMeters', 'radius', 'organicRadiusMeters', 'mediaURL', 'playbackURL', 'posterURL', 'mediaType', 'caption', 'profilePictureURL', 'avatarURL', 'avatarUrl', 'photoURL', 'place', 'locationName', 'channel', 'channelId', 'channelID', 'viewCount', 'repeatViewCount', 'likeCount', 'upvoteCount', 'dislikeCount', 'downvoteCount', 'profileVisitCount', 'pinColor', 'commentCount', 'viewDurationSeconds', 'maxViewSeconds', 'isVerified', 'verified', 'trophyColor'];
async function hydrateMapCandidates(candidates, uid, includeTest, now = Date.now()) {
    const unique = [...new Map(candidates.slice(0, mapDiscoveryPolicy_1.MAX_MAP_FEATURES).map(c => [c.postId, c])).values()];
    if (!unique.length)
        return [];
    const posts = await db.getAll(...unique.map(c => db.doc(`posts/${c.postId}`)));
    const owners = [...new Set(posts.map(p => ownerId(p.data() || {})).filter(safeId))];
    const security = owners.length ? await db.getAll(...owners.flatMap(id => [db.doc(`users/${id}`), db.doc(`users/${uid}/blocked/${id}`), db.doc(`users/${id}/blocked/${uid}`)])) : [];
    const access = new Map(owners.map((id, i) => [id, { exists: security[i * 3].exists, user: security[i * 3].data() || {}, blocked: security[i * 3 + 1].exists || security[i * 3 + 2].exists }]));
    return posts.flatMap((snap, i) => {
        const p = snap.data(), c = unique[i], owner = access.get(ownerId(p || {}));
        if (!p || !owner?.exists || owner.blocked || !(0, mapDiscoveryPolicy_1.eligibleMapPost)(p, owner.user))
            return [];
        const cohort = (0, mapDiscoveryPolicy_1.postCohort)(p, owner.user);
        if (cohort === 'test' && !includeTest)
            return [];
        // An edited origin must not leak into the old tile while its event is queued.
        if ((0, mapDiscoveryPolicy_1.competitionCell)(p.latitude, p.longitude).id !== c.cellId)
            return [];
        const row = { locationVisibility: 'approximate', audience: 'public', visibilityStatus: 'published', createdAtMillis: (0, mapDiscoveryPolicy_1.millis)(p.createdAt) || (0, mapDiscoveryPolicy_1.millis)(p.createdAtMillis) };
        for (const key of PUBLIC_FIELDS) {
            const value = p[key];
            if (typeof value === 'string')
                row[key] = value.slice(0, /URL$|Url$|caption/.test(key) ? 2048 : 180);
            else if (typeof value === 'number' && Number.isFinite(value) || typeof value === 'boolean')
                row[key] = value;
        }
        row.username = String(owner.user.username || p.username || p.handle || '').slice(0, 80);
        if (cohort === 'test')
            row.syntheticBeta = true;
        return [{ id: snap.id, row, competition: { cellId: c.cellId, cohort, status: c.summaryLeader === false ? 'local' : (0, mapDiscoveryPolicy_1.qualifiedWinner)(c, now) ? 'winner' : 'new', score: c.rankKey } }];
    });
}
// Bounded warm-instance tile cache. Personalized payloads are never shared;
// every response still rechecks live post/owner privacy and mutual blocks.
function summaryCandidates(summary) {
    return [...(summary?.winner ? [{ ...summary.winner, summaryLeader: true }] : []),
        ...(summary?.alternates || []).map(c => ({ ...c, summaryLeader: false }))];
}
const summaryCache = new Map();
async function readSummaryTiles(refs) {
    const now = Date.now(), missing = refs.filter(ref => (summaryCache.get(ref.path)?.until || 0) <= now);
    if (missing.length)
        for (const doc of await db.getAll(...missing)) {
            summaryCache.delete(doc.ref.path);
            summaryCache.set(doc.ref.path, { until: now + 30_000, candidates: summaryCandidates(doc.data()) });
            while (summaryCache.size > 512)
                summaryCache.delete(summaryCache.keys().next().value);
        }
    return refs.flatMap(ref => summaryCache.get(ref.path)?.candidates || []);
}
async function runMapDiscoveryQuery(uid, raw) {
    let input;
    try {
        input = (0, mapDiscoveryPolicy_1.parseMapQuery)(raw);
    }
    catch {
        throw new https_1.HttpsError('invalid-argument', 'Invalid map viewport.');
    }
    const config = (await db.doc('mapDiscovery/config').get()).data() || {};
    if (config.enabled !== true && !(Array.isArray(config.canaryUids) && config.canaryUids.includes(uid)))
        return { schema: mapDiscoveryPolicy_1.MAP_SCHEMA, enabled: false, posts: [], cells: [], nextCursor: null };
    // Production and simulation never share a competition. Test visibility is a
    // server switch, not something an untrusted request may enable itself.
    input.includeTest = input.includeTest && config.includeTest === true;
    const f = queryFingerprint(input, uid), cursor = decodeCursor(input.cursor, f);
    const cells = (0, mapDiscoveryPolicy_1.visibleCells)(input.bounds);
    const local = input.zoom >= 12 && cells && cells.length <= mapDiscoveryPolicy_1.MAX_LOCAL_CELLS;
    let candidates = [], nextCursor = null;
    let mode = local ? 'posts' : cells ? 'cells' : 'regions';
    let cellShapes = [];
    if (local) {
        let q = db.collection('mapPostIndex').where('cellId', 'in', cells.map(c => c.id));
        if (!input.includeTest)
            q = q.where('cohort', '==', 'real');
        q = q.orderBy('createdAtMillis', 'desc').orderBy(firestore_1.FieldPath.documentId(), 'desc');
        if (cursor)
            q = q.startAfter(cursor.at, cursor.id);
        const page = await q.limit(mapDiscoveryPolicy_1.MAP_PAGE_SIZE + 1).get();
        candidates = page.docs.slice(0, mapDiscoveryPolicy_1.MAP_PAGE_SIZE).map(d => d.data());
        if (page.size > mapDiscoveryPolicy_1.MAP_PAGE_SIZE) {
            const last = candidates[candidates.length - 1];
            nextCursor = Buffer.from(JSON.stringify({ f, at: last.createdAtMillis, id: last.postId })).toString('base64url');
        }
        cellShapes = cells;
    }
    else {
        const ids = cells ? cells.map(c => c.id) : (0, mapDiscoveryPolicy_1.visibleRegions)(input.bounds, input.zoom).map(mapDiscoveryPolicy_1.regionId);
        if (cells)
            cellShapes = cells;
        const collection = cells ? 'mapCellSummaries' : 'mapRegionSummaries';
        const cohorts = input.includeTest ? ['real', 'test'] : ['real'];
        const refs = ids.flatMap(id => cohorts.map(c => db.doc(`${collection}/${c}_${id}`)));
        const summaries = refs.length ? await readSummaryTiles(refs) : [];
        // Include nearby alternatives as regular pins; only the elected leader gets
        // winner styling. Every candidate still passes live privacy checks.
        candidates = summaries.filter(c => c.expiresAtMillis > Date.now()).slice(0, mapDiscoveryPolicy_1.MAX_MAP_FEATURES);
    }
    if (input.selectedPostId && candidates.length < mapDiscoveryPolicy_1.MAX_MAP_FEATURES) {
        const selected = await db.doc(`mapPostIndex/${input.selectedPostId}`).get();
        if (selected.exists)
            candidates.push(selected.data());
    }
    const posts = await hydrateMapCandidates(candidates, uid, input.includeTest);
    if (mode === 'posts')
        for (const post of posts)
            post.competition.status = 'local';
    return { schema: mapDiscoveryPolicy_1.MAP_SCHEMA, enabled: true, mode, posts, cells: cellShapes, nextCursor,
        refreshAfterSeconds: 60, generatedAtMillis: Date.now(), limits: { features: mapDiscoveryPolicy_1.MAX_MAP_FEATURES, page: mapDiscoveryPolicy_1.MAP_PAGE_SIZE, richPins: 36 } };
}
exports.queryMapDiscovery = (0, https_1.onCall)({ region, timeoutSeconds: 30, memory: '512MiB', cpu: 1, concurrency: 40, maxInstances: 4 }, async (request) => {
    if (!request.auth?.uid)
        throw new https_1.HttpsError('unauthenticated', 'Sign in to explore the map.');
    const uid = request.auth.uid, now = Date.now();
    await db.runTransaction(async (tx) => {
        const ref = db.doc(`mapDiscoveryRate/${uid}`), previous = await tx.get(ref), state = previous.data();
        const tokens = Math.min(30, Number(state?.tokens ?? 30) + Math.max(0, now - Number(state?.at ?? now)) / 1000);
        if (tokens < 1)
            throw new https_1.HttpsError('resource-exhausted', 'Please pause briefly before loading another area.');
        tx.set(ref, { tokens: tokens - 1, at: now, expiresAt: firestore_1.Timestamp.fromMillis(now + 3600_000) });
    });
    return runMapDiscoveryQuery(uid, request.data);
});
/** Resumable migration, deliberately not a public callable. Run from an admin
 * script, then verify summaries before enabling the server feature switch. */
async function backfillMapDiscovery(limit = 500) {
    const stateRef = db.doc('mapDiscovery/migration'), saved = (await stateRef.get()).data() || {};
    const state = saved.version === 2 ? saved : {};
    if (state.complete)
        return state;
    let q = db.collection('posts').orderBy(firestore_1.FieldPath.documentId()).limit(Math.min(500, Math.max(1, limit)));
    if (state.cursor)
        q = q.startAfter(state.cursor);
    const page = await q.get();
    for (let i = 0; i < page.size; i += 20)
        await Promise.all(page.docs.slice(i, i + 20).map(async (p) => { await reconcileMapPost(p.id); await (0, radiusDecayQueue_1.reconcileDecayPost)(p.id); }));
    const next = { version: 2, cursor: page.docs.at(-1)?.id || state.cursor || '', complete: page.size < limit, processed: Number(state.processed || 0) + page.size, updatedAt: firestore_1.Timestamp.now() };
    await stateRef.set(next);
    return next;
}
async function backfillMapEngagements(limit = 500) {
    const ref = db.doc('mapDiscovery/engagementMigration'), state = (await ref.get()).data() || {};
    if (state.complete)
        return state;
    const since = state.since || Date.now() - mapDiscoveryPolicy_1.RANK_WINDOW_MS;
    let query = db.collectionGroup('engagements').where('createdAt', '>=', firestore_1.Timestamp.fromMillis(since))
        .orderBy('createdAt').orderBy(firestore_1.FieldPath.documentId()).limit(Math.min(500, limit));
    if (state.path)
        query = query.startAfter(firestore_1.Timestamp.fromMillis(state.at), state.path);
    const page = await query.get();
    // Sequential per post ordering is naturally enforced by score transactions.
    for (let i = 0; i < page.size; i += 10)
        await Promise.all(page.docs.slice(i, i + 10).map(event => {
            const post = event.ref.parent.parent;
            return post?.parent.id === 'posts' ? rankMapEngagement(post.id, event.id, event.data()) : Promise.resolve();
        }));
    const last = page.docs.at(-1);
    const next = { since, path: last?.ref.path || state.path || '', at: (0, mapDiscoveryPolicy_1.millis)(last?.data().createdAt) || state.at || since,
        complete: page.size < limit, processed: Number(state.processed || 0) + page.size, updatedAt: firestore_1.Timestamp.now() };
    await ref.set(next);
    return next;
}
