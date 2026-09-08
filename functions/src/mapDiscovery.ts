import * as admin from 'firebase-admin';
import { createHash } from 'crypto';
import { FieldPath, FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getFunctions } from 'firebase-admin/functions';
import { onDocumentWritten, onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onTaskDispatched } from 'firebase-functions/v2/tasks';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { reconcileDecayPost } from './radiusDecayQueue';
import { advanceRank, Candidate, chooseChampion, competitionCell, eligibleMapPost, MAP_PAGE_SIZE, MAP_SCHEMA,
  MAX_LOCAL_CELLS, MAX_MAP_FEATURES, millis, parentRegion, parseCell, parseMapQuery, parseRegion,
  postCohort, qualifiedWinner, Rank, rankKey, RANK_MAX_AGE_MS, RANK_WINDOW_MS, regionAt, regionChildren,
  regionId, REGION_DEPTH, visibleCells, visibleRegions } from './mapDiscoveryPolicy';

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const region = 'us-central1';
const sha = (s: string) => createHash('sha256').update(s).digest('hex');
const ownerId = (p: admin.firestore.DocumentData) => String(p.userID || p.userId || '');
const safeId = (s: unknown): s is string => typeof s === 'string' && /^[\w.-]{1,180}$/.test(s);
type Job = { kind: 'cell' | 'region' | 'owner'; key: string; cohort: 'real' | 'test'; version: number; generation: number; shard: number; dueAt: Timestamp; cursor?: string; field?: string };
type Summary = { winner: Candidate | null; alternates: Candidate[]; challengerId: string | null; challengerSince: number; updatedAtMillis: number; cohort: string; leaf?: string };

/** Durable, sharded invalidation outbox. Repeated events coalesce for 30s;
 * different posts do not contend on one worldwide/cell counter. */
export async function dirtyMapSummary(kind: Job['kind'], key: string, cohort: Job['cohort'], source: string, delay = 30) {
  const bucket = parseInt(sha(source).slice(0, 4), 16) % 64;
  const id = sha(`${kind}:${cohort}:${key}:${bucket}`);
  const ref = db.doc(`mapDiscoveryJobs/${id}`);
  await db.runTransaction(async tx => {
    const existing = await tx.get(ref);
    if (existing.exists) { tx.update(ref, { version: FieldValue.increment(1) }); return; }
    tx.create(ref, { kind, key, cohort, version: 1, generation: Date.now(), shard: bucket % 16,
      dueAt: Timestamp.fromMillis(Date.now() + delay * 1000) });
  });
}

export async function reconcileMapPost(postId: string) {
  const ref = db.doc(`mapPostIndex/${postId}`);
  await db.runTransaction(async tx => {
    const [postSnap, previous, rankSnap] = await tx.getAll(db.doc(`posts/${postId}`), ref, db.doc(`mapPostRanks/${postId}`));
    const post = postSnap.data() || {}, uid = ownerId(post);
    const user = safeId(uid) ? await tx.get(db.doc(`users/${uid}`)) : null;
    const old = previous.data() as Candidate | undefined;
    let next: Candidate | null = null;
    if (postSnap.exists && user?.exists && eligibleMapPost(post, user.data() || {})) {
      const rank = rankSnap.data() as Partial<Rank> | undefined;
      const created = millis(post.createdAt) || millis(post.createdAtMillis) || Date.now();
      const cell = competitionCell(post.latitude, post.longitude);
      next = { postId, ownerId: uid, cellId: cell.id, cohort: postCohort(post, user.data() || {}),
        latitude: post.latitude, longitude: post.longitude, createdAtMillis: created,
        rankKey: rankKey(rank || {}, created), exposure: rank?.views || 0, rankAt: rank?.at || created,
        rankBucket: Math.floor((rank?.at || created) / RANK_WINDOW_MS), rankEligible: (rank?.views || 0) >= 5,
        expiresAtMillis: Math.max(created, rank?.at || 0) + RANK_MAX_AGE_MS };
    }
    const same = !old && !next || old && next && Object.keys(old).length === Object.keys(next).length
      && Object.entries(next).every(([key, value]) => (old as unknown as Record<string, unknown>)[key] === value);
    if (same && (postSnap.exists || !rankSnap.exists)) return;
    const bucket = parseInt(sha(postId).slice(0, 4), 16) % 64;
    const cells = [...new Map(([old, next].filter(Boolean) as Candidate[]).map(c => [`${c.cohort}:${c.cellId}`, c])).values()];
    const jobs = cells.map(c => db.doc(`mapDiscoveryJobs/${sha(`cell:${c.cohort}:${c.cellId}:${bucket}`)}`));
    const pending = jobs.length ? await tx.getAll(...jobs) : [];
    if (!postSnap.exists && rankSnap.exists) tx.delete(rankSnap.ref);
    if (next) tx.set(ref, next); else if (previous.exists) tx.delete(ref);
    cells.forEach((c, i) => {
      if (pending[i].exists) tx.update(jobs[i], { version: FieldValue.increment(1) });
      else tx.create(jobs[i], { kind: 'cell', key: c.cellId, cohort: c.cohort, version: 1,
        generation: Date.now(), shard: bucket % 16, dueAt: Timestamp.fromMillis(Date.now() + 30_000) });
    });
  });
}

/** Rank only accepted server engagement receipts. One actor/kind per six-hour
 * window; owner reactions and synthetic actors cannot elect real winners. */
export async function rankMapEngagement(postId: string, eventId: string, event: admin.firestore.DocumentData) {
  const uid = event.actorUid, kind = event.kind;
  if (!safeId(uid) || !['view', 'like', 'comment', 'dislike'].includes(kind) || event.applied === false) return;
  const now = millis(event.createdAt) || Date.now();
  const receipt = db.doc(`mapRankReceipts/${sha(`${postId}:${eventId}`)}`);
  const unique = db.doc(`mapRankActors/${sha(`${postId}:${uid}:${kind}:${Math.floor(now / RANK_WINDOW_MS)}`)}`);
  await db.runTransaction(async tx => {
    const [seen, actorSeen, postSnap, actor, rank] = await tx.getAll(receipt, unique, db.doc(`posts/${postId}`), db.doc(`users/${uid}`), db.doc(`mapPostRanks/${postId}`));
    if (seen.exists) return;
    const post = postSnap.data() || {}, owner = ownerId(post);
    if (!postSnap.exists || !safeId(owner) || owner === uid) return;
    const [user, blocked, reverse] = await tx.getAll(db.doc(`users/${owner}`), db.doc(`users/${owner}/blocked/${uid}`), db.doc(`users/${uid}/blocked/${owner}`));
    if (!user.exists || !actor.exists || blocked.exists || reverse.exists || !eligibleMapPost(post, user.data() || {})) return;
    if (postCohort(post, user.data() || {}) === 'real' && actor.data()?.syntheticBeta === true) return;
    const expiry = Timestamp.fromMillis(Date.now() + 7 * 86400_000);
    tx.create(receipt, { expiresAt: expiry });
    if (actorSeen.exists) return;
    tx.create(unique, { expiresAt: expiry });
    // Out-of-order event delivery cannot move the score clock backwards.
    const at = Math.max(now, Number(rank.data()?.at || 0));
    const gain = Number(event.radiusDeltaMeters || 0);
    const next = advanceRank(rank.data() || {}, at, kind, gain);
    tx.set(rank.ref, next);
  });
  // Retry-safe even if the process died between committing rank and projection.
  await reconcileMapPost(postId);
}

export async function rebuildMapSummary(kind: 'cell' | 'region', key: string, cohort: Job['cohort']) {
  const target = db.doc(`${kind === 'cell' ? 'mapCellSummaries' : 'mapRegionSummaries'}/${cohort}_${key}`);
  const now = Date.now();
  const cell = kind === 'cell' ? parseCell(key) : null;
  const tile = cell ? regionAt(cell.center[1], cell.center[0]) : parseRegion(key);
  const parent = cell ? tile : parentRegion(tile);
  const result = await db.runTransaction(async tx => {
    const previous = await tx.get(target);
    let candidates: Candidate[];
    if (cell) {
      const base = db.collection('mapPostIndex').where('cohort', '==', cohort).where('cellId', '==', key);
      const bucket = Math.floor(now / RANK_WINDOW_MS);
      // Thirteen six-hour buckets bound both document reads and index scans,
      // even when a hot cell contains millions of old posts. Each contributes
      // its strongest sixteen qualified candidates; new posts get 32 slots.
      const pages = await Promise.all([
        ...Array.from({ length: 13 }, (_, i) => tx.get(base.where('rankBucket', '==', bucket - i)
          .where('rankEligible', '==', true).orderBy('rankKey', 'desc').limit(16))),
        tx.get(base.orderBy('createdAtMillis', 'desc').limit(32)),
      ]);
      candidates = [...new Map(pages.flatMap(page => page.docs).map(d => [d.id, d.data() as Candidate])).values()];
    } else if (tile.z === REGION_DEPTH) {
      const children = await tx.get(db.collection('mapCellSummaries').where('cohort', '==', cohort).where('leaf', '==', key).limit(192));
      candidates = children.docs.flatMap(d => summaryCandidates(d.data() as Summary));
    } else {
      const children = await tx.getAll(...regionChildren(tile).map(r => db.doc(`mapRegionSummaries/${cohort}_${regionId(r)}`)));
      candidates = children.flatMap(d => summaryCandidates(d.data() as Summary | undefined));
    }
    const old = previous.data() as Summary | undefined;
    const choice = chooseChampion(candidates, old || {}, now, Boolean(cell));
    const alternates = candidates.filter(c => c.expiresAtMillis > now && c.postId !== choice.winner?.postId)
      .sort((a, b) => b.rankKey - a.rankKey).slice(0, 4);
    const next: Summary = { ...choice, alternates, updatedAtMillis: now, cohort, ...(cell ? { leaf: regionId(tile) } : {}) };
    tx.set(target, next);
    const winner = choice.winner;
    const qualificationEnds = winner && qualifiedWinner(winner, now)
      ? winner.rankAt + Math.log(winner.exposure / 5) * (6 * 3600_000 / Math.LN2) + 1000 : Infinity;
    const nextDue = winner ? Math.min(winner.expiresAtMillis + 1000, qualificationEnds) : 0;
    return { changed: JSON.stringify(summaryCandidates(old)) !== JSON.stringify(summaryCandidates(next)), challenger: Boolean(choice.challengerId), nextDue };
  });
  if (result.changed && parent) await dirtyMapSummary('region', regionId(parent), cohort, key, 5);
  return result;
}

export async function processMapJob(id: string, generation?: number) {
  const ref = db.doc(`mapDiscoveryJobs/${id}`), snap = await ref.get(), job = snap.data() as Job | undefined;
  if (!job || (generation != null && generation !== job.generation)) return;
  let repeat = false, nextDue = 0;
  if (job.kind === 'owner') {
    // Privacy is enforced at read time immediately. This paged repair removes
    // stale index candidates and reintroduces newly public posts asynchronously.
    const field = job.field || 'userID';
    let q = db.collection('posts').where(field, '==', job.key).orderBy(FieldPath.documentId()).limit(100);
    if (job.cursor) q = q.startAfter(job.cursor);
    const posts = await q.get();
    await Promise.all(posts.docs.map(p => reconcileMapPost(p.id)));
    if (posts.size === 100) { await ref.update({ cursor: posts.docs[99].id }); repeat = true; }
    else if (field === 'userID') { await ref.update({ field: 'userId', cursor: FieldValue.delete() }); repeat = true; }
  } else {
    const rebuilt = await rebuildMapSummary(job.kind, job.key, job.cohort);
    repeat = rebuilt.challenger;
    // One durable timer per summary, not one timer per invalidation shard.
    const clockId = sha(`clock:${job.cohort}:${job.kind}:${job.key}`);
    if (id === clockId) nextDue = rebuilt.nextDue;
    else if (rebuilt.nextDue > 0) {
      const clock = db.doc(`mapDiscoveryJobs/${clockId}`);
      await db.runTransaction(async tx => {
        const old = await tx.get(clock);
        if (!old.exists) tx.create(clock, { kind: job.kind, key: job.key, cohort: job.cohort,
          version: 1, generation: Date.now(), shard: parseInt(clockId.slice(0, 2), 16) % 16,
          dueAt: Timestamp.fromMillis(rebuilt.nextDue) });
        else if (old.data()!.dueAt.toMillis() > rebuilt.nextDue) tx.update(clock, {
          generation: FieldValue.increment(1), dueAt: Timestamp.fromMillis(rebuilt.nextDue), version: FieldValue.increment(1),
        });
      });
    }
  }
  await db.runTransaction(async tx => {
    const current = await tx.get(ref);
    if (!current.exists || current.data()?.generation !== job.generation) return;
    if (repeat || current.data()?.version !== job.version || nextDue > 0) tx.update(ref, {
      generation: job.generation + 1, dueAt: Timestamp.fromMillis(repeat || current.data()?.version !== job.version ? Date.now() + (repeat && job.kind === 'cell' ? 120 : 30) * 1000 : Math.max(Date.now() + 1000, nextDue)),
    }); else tx.delete(ref);
  });
}

export const mapDiscoveryPostChanged = onDocumentWritten({ document: 'posts/{postId}', region, retry: true, memory: '256MiB', cpu: 'gcf_gen1', concurrency: 1, maxInstances: 4 }, e => reconcileMapPost(e.params.postId));
export const mapDiscoveryEngagement = onDocumentCreated({ document: 'posts/{postId}/engagements/{engagementId}', region, retry: true, memory: '256MiB', cpu: 'gcf_gen1', concurrency: 1, maxInstances: 4 }, e => rankMapEngagement(e.params.postId, e.params.engagementId, e.data?.data() || {}));
export const mapDiscoveryOwnerChanged = onDocumentWritten({ document: 'users/{uid}', region, retry: true, memory: '256MiB', cpu: 'gcf_gen1', concurrency: 1, maxInstances: 4 }, async e => {
  const before = e.data?.before.data(), after = e.data?.after.data();
  if (['privateAccount', 'ghostMode', 'disabled', 'syntheticBeta'].every(k => before?.[k] === after?.[k]) && Boolean(before) === Boolean(after)) return;
  await dirtyMapSummary('owner', e.params.uid, 'real', e.params.uid, 0);
});
export const mapDiscoveryEnqueue = onDocumentWritten({ document: 'mapDiscoveryJobs/{jobId}', region, retry: true, memory: '256MiB', cpu: 'gcf_gen1', concurrency: 1, maxInstances: 4 }, async e => {
  const job = e.data?.after.data() as Job | undefined;
  if (!job || e.data?.before.data()?.generation === job.generation) return;
  try {
    await getFunctions().taskQueue(`locations/${region}/functions/mapDiscoveryWorker`).enqueue({ id: e.params.jobId, generation: job.generation }, {
      id: sha(`${e.params.jobId}:${job.generation}`), scheduleTime: new Date(Math.max(Date.now(), job.dueAt.toMillis())), dispatchDeadlineSeconds: 180,
    });
  } catch (error) { if ((error as { code?: string }).code !== 'functions/task-already-exists') throw error; }
});
export const mapDiscoveryWorker = onTaskDispatched({ region, timeoutSeconds: 180, memory: '512MiB', cpu: 1, maxInstances: 2, concurrency: 8, retryConfig: { maxAttempts: 8, minBackoffSeconds: 10, maxBackoffSeconds: 300 }, rateLimits: { maxConcurrentDispatches: 16, maxDispatchesPerSecond: 16 } }, async request => {
  if (typeof request.data.id !== 'string' || !/^[a-f0-9]{64}$/.test(request.data.id)) return;
  await processMapJob(request.data.id, request.data.generation);
});
export const repairMapDiscovery = onSchedule({ schedule: 'every 10 minutes', region, timeoutSeconds: 300, cpu: 'gcf_gen1', maxInstances: 1 }, async () => {
  for (let shard = 0; shard < 16; shard++) {
    const overdue = await db.collection('mapDiscoveryJobs').where('shard', '==', shard).where('dueAt', '<', Timestamp.fromMillis(Date.now() - 10 * 60_000)).limit(100).get();
    const batch = db.batch();
    for (const job of overdue.docs) batch.update(job.ref, { generation: FieldValue.increment(1), dueAt: Timestamp.now() });
    if (!overdue.empty) await batch.commit();
  }
});

type QueryInput = ReturnType<typeof parseMapQuery>;
function queryFingerprint(input: QueryInput, uid: string) { return sha(JSON.stringify({ bounds: input.bounds, zoom: input.zoom, includeTest: input.includeTest, uid })).slice(0, 24); }
function decodeCursor(cursor: string | null, fingerprint: string) {
  if (!cursor) return null;
  try {
    const c = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
    if (c.f !== fingerprint || !safeId(c.id) || !Number.isFinite(c.at) || c.at < 0) throw new Error();
    return c as { f: string; id: string; at: number };
  } catch { throw new HttpsError('invalid-argument', 'This map page has expired. Refresh the area.'); }
}

/** Only a whitelist leaves the server; documents/ranking identities never do. */
const PUBLIC_FIELDS = ['userID', 'userId', 'username', 'handle', 'displayName', 'latitude', 'longitude', 'radiusMeters', 'radius', 'organicRadiusMeters', 'mediaURL', 'playbackURL', 'posterURL', 'mediaType', 'caption', 'profilePictureURL', 'avatarURL', 'avatarUrl', 'photoURL', 'place', 'locationName', 'channel', 'channelId', 'channelID', 'viewCount', 'repeatViewCount', 'likeCount', 'upvoteCount', 'dislikeCount', 'downvoteCount', 'profileVisitCount', 'pinColor', 'commentCount', 'viewDurationSeconds', 'maxViewSeconds', 'isVerified', 'verified', 'trophyColor'] as const;
export async function hydrateMapCandidates(candidates: Candidate[], uid: string, includeTest: boolean, now = Date.now()) {
  const unique = [...new Map(candidates.slice(0, MAX_MAP_FEATURES).map(c => [c.postId, c])).values()];
  if (!unique.length) return [];
  const posts = await db.getAll(...unique.map(c => db.doc(`posts/${c.postId}`)));
  const owners = [...new Set(posts.map(p => ownerId(p.data() || {})).filter(safeId))];
  const security = owners.length ? await db.getAll(...owners.flatMap(id => [db.doc(`users/${id}`), db.doc(`users/${uid}/blocked/${id}`), db.doc(`users/${id}/blocked/${uid}`)])) : [];
  const access = new Map(owners.map((id, i) => [id, { exists: security[i * 3].exists, user: security[i * 3].data() || {}, blocked: security[i * 3 + 1].exists || security[i * 3 + 2].exists }]));
  return posts.flatMap((snap, i) => {
    const p = snap.data(), c = unique[i], owner = access.get(ownerId(p || {}));
    if (!p || !owner?.exists || owner.blocked || !eligibleMapPost(p, owner.user)) return [];
    const cohort = postCohort(p, owner.user);
    if (cohort === 'test' && !includeTest) return [];
    // An edited origin must not leak into the old tile while its event is queued.
    if (competitionCell(p.latitude, p.longitude).id !== c.cellId) return [];
    const row: admin.firestore.DocumentData = { locationVisibility: 'approximate', audience: 'public', visibilityStatus: 'published', createdAtMillis: millis(p.createdAt) || millis(p.createdAtMillis) };
    for (const key of PUBLIC_FIELDS) {
      const value = p[key];
      if (typeof value === 'string') row[key] = value.slice(0, /URL$|Url$|caption/.test(key) ? 2048 : 180);
      else if (typeof value === 'number' && Number.isFinite(value) || typeof value === 'boolean') row[key] = value;
    }
    row.username = String(owner.user.username || p.username || p.handle || '').slice(0, 80);
    if (cohort === 'test') row.syntheticBeta = true;
    return [{ id: snap.id, row, competition: { cellId: c.cellId, cohort, status: c.summaryLeader === false ? 'local' : qualifiedWinner(c, now) ? 'winner' : 'new', score: c.rankKey } }];
  });
}

// Bounded warm-instance tile cache. Personalized payloads are never shared;
// every response still rechecks live post/owner privacy and mutual blocks.
function summaryCandidates(summary?: Partial<Summary>): Candidate[] {
  return [...(summary?.winner ? [{ ...summary.winner, summaryLeader: true }] : []),
    ...(summary?.alternates || []).map(c => ({ ...c, summaryLeader: false }))];
}
const summaryCache = new Map<string, { until: number; candidates: Candidate[] }>();
async function readSummaryTiles(refs: admin.firestore.DocumentReference[]) {
  const now = Date.now(), missing = refs.filter(ref => (summaryCache.get(ref.path)?.until || 0) <= now);
  if (missing.length) for (const doc of await db.getAll(...missing)) {
    summaryCache.delete(doc.ref.path);
    summaryCache.set(doc.ref.path, { until: now + 30_000, candidates: summaryCandidates(doc.data()) });
    while (summaryCache.size > 512) summaryCache.delete(summaryCache.keys().next().value!);
  }
  return refs.flatMap(ref => summaryCache.get(ref.path)?.candidates || []);
}

/** Only the recipient may replay an expired post from their own inbox. */
async function notificationFocusFor(uid: string, raw: unknown) {
  const id = (raw as { notificationId?: unknown })?.notificationId;
  if (typeof id !== 'string' || id.length > 500 || id.includes('/')) return undefined;
  const notice = (await db.doc(`users/${uid}/notifications/${id}`).get()).data();
  if (!notice || !safeId(notice.postId)) return undefined;
  const post = (await db.doc(`posts/${notice.postId}`).get()).data();
  if (!post || ownerId(post) !== uid || !Number.isFinite(post.latitude) || !Number.isFinite(post.longitude)) return undefined;
  const historyId = notice.historyId;
  if (!safeId(historyId)) return undefined;
  const history = (await db.doc(`posts/${notice.postId}/radiusHistory/${historyId}`).get()).data();
  if (!history || !Number.isFinite(history.delta) || !Number.isFinite(history.radiusMeters)) return undefined;
  const colors: Record<string, string> = { red: '#fb7185', purple: '#c084fc', blue: '#7dd3fc', green: '#4ade80', orange: '#ffbd66' };
  const color = typeof post.pinColor === 'string' ? colors[post.pinColor] ?? post.pinColor : '';
  const boundedKm = (meters: number) => Math.min(6371000, Math.max(0, meters)) / 1000;
  return { notificationId: id, id: `firestore:${notice.postId}`, coords: [post.longitude, post.latitude],
    name: String(post.username || post.handle || post.displayName || 'Your post').slice(0, 180),
    beforeKm: boundedKm(history.radiusMeters - history.delta),
    afterKm: boundedKm(history.radiusMeters),
    currentKm: boundedKm(Number(post.radiusMeters ?? post.radius) || 0),
    color: /^#[\da-f]{6}$/i.test(color) ? color : '#f53c99' };
}

export async function runMapDiscoveryQuery(uid: string, raw: unknown) {
  let input: QueryInput;
  try { input = parseMapQuery(raw); } catch { throw new HttpsError('invalid-argument', 'Invalid map viewport.'); }
  const config = (await db.doc('mapDiscovery/config').get()).data() || {};
  if (config.enabled !== true && !(Array.isArray(config.canaryUids) && config.canaryUids.includes(uid))) return { schema: MAP_SCHEMA, enabled: false, posts: [], cells: [], nextCursor: null };
  // Production and simulation never share a competition. Test visibility is a
  // server switch, not something an untrusted request may enable itself.
  input.includeTest = input.includeTest && config.includeTest === true;
  const f = queryFingerprint(input, uid), cursor = decodeCursor(input.cursor, f);
  const cells = visibleCells(input.bounds);
  const local = input.zoom >= 12 && cells && cells.length <= MAX_LOCAL_CELLS;
  let candidates: Candidate[] = [], nextCursor: string | null = null;
  let mode: 'posts' | 'cells' | 'regions' = local ? 'posts' : cells ? 'cells' : 'regions';
  let cellShapes: ReturnType<typeof parseCell>[] = [];
  if (local) {
    let q = db.collection('mapPostIndex').where('cellId', 'in', cells.map(c => c.id));
    if (!input.includeTest) q = q.where('cohort', '==', 'real');
    q = q.orderBy('createdAtMillis', 'desc').orderBy(FieldPath.documentId(), 'desc');
    if (cursor) q = q.startAfter(cursor.at, cursor.id);
    const page = await q.limit(MAP_PAGE_SIZE + 1).get();
    candidates = page.docs.slice(0, MAP_PAGE_SIZE).map(d => d.data() as Candidate);
    if (page.size > MAP_PAGE_SIZE) {
      const last = candidates[candidates.length - 1];
      nextCursor = Buffer.from(JSON.stringify({ f, at: last.createdAtMillis, id: last.postId })).toString('base64url');
    }
    cellShapes = cells;
  } else {
    const ids = cells ? cells.map(c => c.id) : visibleRegions(input.bounds, input.zoom).map(regionId);
    if (cells) cellShapes = cells;
    const collection = cells ? 'mapCellSummaries' : 'mapRegionSummaries';
    const cohorts = input.includeTest ? ['real', 'test'] : ['real'];
    const refs = ids.flatMap(id => cohorts.map(c => db.doc(`${collection}/${c}_${id}`)));
    const summaries = refs.length ? await readSummaryTiles(refs) : [];
    // Include nearby alternatives as regular pins; only the elected leader gets
    // winner styling. Every candidate still passes live privacy checks.
    candidates = summaries.filter(c => c.expiresAtMillis > Date.now()).slice(0, MAX_MAP_FEATURES);
  }
  if (input.selectedPostId && candidates.length < MAX_MAP_FEATURES) {
    const selected = await db.doc(`mapPostIndex/${input.selectedPostId}`).get();
    if (selected.exists) candidates.push(selected.data() as Candidate);
  }
  const posts = await hydrateMapCandidates(candidates, uid, input.includeTest);
  if (mode === 'posts') for (const post of posts) post.competition.status = 'local';
  const notificationFocus = await notificationFocusFor(uid, raw);
  return { ...(notificationFocus ? { notificationFocus } : {}), schema: MAP_SCHEMA, enabled: true, mode, posts, cells: cellShapes, nextCursor,
    refreshAfterSeconds: 60, generatedAtMillis: Date.now(), limits: { features: MAX_MAP_FEATURES, page: MAP_PAGE_SIZE, richPins: 36 } };
}
export const queryMapDiscovery = onCall({ region, timeoutSeconds: 30, memory: '512MiB', cpu: 1, concurrency: 40, maxInstances: 4 }, async request => {
  if (!request.auth?.uid) throw new HttpsError('unauthenticated', 'Sign in to explore the map.');
  const uid = request.auth.uid, now = Date.now();
  await db.runTransaction(async tx => {
    const ref = db.doc(`mapDiscoveryRate/${uid}`), previous = await tx.get(ref), state = previous.data();
    const tokens = Math.min(30, Number(state?.tokens ?? 30) + Math.max(0, now - Number(state?.at ?? now)) / 1000);
    if (tokens < 1) throw new HttpsError('resource-exhausted', 'Please pause briefly before loading another area.');
    tx.set(ref, { tokens: tokens - 1, at: now, expiresAt: Timestamp.fromMillis(now + 3600_000) });
  });
  return runMapDiscoveryQuery(uid, request.data);
});

/** Resumable migration, deliberately not a public callable. Run from an admin
 * script, then verify summaries before enabling the server feature switch. */
export async function backfillMapDiscovery(limit = 500) {
  const stateRef = db.doc('mapDiscovery/migration'), saved = (await stateRef.get()).data() || {};
  const state = saved.version === 2 ? saved : {};
  if (state.complete) return state;
  let q = db.collection('posts').orderBy(FieldPath.documentId()).limit(Math.min(500, Math.max(1, limit)));
  if (state.cursor) q = q.startAfter(state.cursor);
  const page = await q.get();
  for (let i = 0; i < page.size; i += 20) await Promise.all(page.docs.slice(i, i + 20).map(async p => { await reconcileMapPost(p.id); await reconcileDecayPost(p.id); }));
  const next = { version: 2, cursor: page.docs.at(-1)?.id || state.cursor || '', complete: page.size < limit, processed: Number(state.processed || 0) + page.size, updatedAt: Timestamp.now() };
  await stateRef.set(next); return next;
}

export async function backfillMapEngagements(limit = 500) {
  const ref = db.doc('mapDiscovery/engagementMigration'), state = (await ref.get()).data() || {};
  if (state.complete) return state;
  const since = state.since || Date.now() - RANK_WINDOW_MS;
  let query = db.collectionGroup('engagements').where('createdAt', '>=', Timestamp.fromMillis(since))
    .orderBy('createdAt').orderBy(FieldPath.documentId()).limit(Math.min(500, limit));
  if (state.path) query = query.startAfter(Timestamp.fromMillis(state.at), state.path);
  const page = await query.get();
  // Sequential per post ordering is naturally enforced by score transactions.
  for (let i = 0; i < page.size; i += 10) await Promise.all(page.docs.slice(i, i + 10).map(event => {
    const post = event.ref.parent.parent;
    return post?.parent.id === 'posts' ? rankMapEngagement(post.id, event.id, event.data()) : Promise.resolve();
  }));
  const last = page.docs.at(-1);
  const next = { since, path: last?.ref.path || state.path || '', at: millis(last?.data().createdAt) || state.at || since,
    complete: page.size < limit, processed: Number(state.processed || 0) + page.size, updatedAt: Timestamp.now() };
  await ref.set(next); return next;
}
