#!/usr/bin/env node
"use strict";

/**
 * Give every existing pop its history — from the record, never from a guess.
 *
 * Posts made before radiusHistory existed have no entries, but they have a
 * record: every engagement that moved their reach wrote posts/{id}/engagements
 * with `radiusDeltaMeters` (the exact metres it paid) and `result.counters`
 * (the exact totals AFTER it), stamped by the server. This script turns that
 * into history, and labels what it cannot know:
 *
 *   create      ONLY where the first value is a stored fact: a post carrying
 *               seedRadiusMeters (the rules force a new post's reach to equal
 *               its seed, earned 0), or a post nothing has ever moved (no
 *               engagement, never decayed, not rewritten by the runner) whose
 *               document still holds its birth value.
 *   backfill    an opening point for every other post, at the time of the
 *               earliest exact record (the first engagement, valued at the
 *               reach it stepped FROM); a checkpoint wherever the record shows
 *               a change nothing recorded (the world→Earth ceiling, a boost
 *               script), so that change is never blamed on a view; and one
 *               closing point where the document's STORED reach today differs
 *               from the last point (decay ran between — only its sum
 *               survives, and that is what the entry says).
 *   engagement  one entry per applied engagement that moved the total: from
 *               counters − radiusDeltaMeters to counters, at its server time,
 *               delta = radiusDeltaMeters itself.
 *
 * A pop at the Earth-radius ceiling cannot show a per-engagement step (its
 * total is pinned); those entries carry the true total with delta 0.
 *
 * Idempotent: an entry that exists is left alone. `--rewrite` first deletes the
 * entries THIS script wrote (writer === 'backfillRadiusHistory' only; never a
 * server-written point) so a corrected run replaces an earlier one. Dry run by
 * default.
 *
 *   node scripts/backfillRadiusHistory.js                      # report only
 *   node scripts/backfillRadiusHistory.js --execute            # write missing
 *   node scripts/backfillRadiusHistory.js --rewrite --execute  # replace own
 */

const admin = require("firebase-admin");
const policy = require("../lib/postEngagementPolicy.js");

const PROJECT_ID = "poplur2025";
const WRITER = "backfillRadiusHistory";
const execute = process.argv.includes("--execute");
const rewrite = process.argv.includes("--rewrite");
admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();
const RUN_MILLIS = Date.now();

function millisOf(value) {
  if (value == null) return null;
  if (typeof value === "number" && Number.isFinite(value) && value > 0) return value;
  if (typeof value.toMillis === "function") {
    const m = Number(value.toMillis());
    return Number.isFinite(m) && m > 0 ? m : null;
  }
  return null;
}

function finite(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function document(entry) {
  return { ...entry, at: admin.firestore.Timestamp.fromMillis(entry.atMillis) };
}

/** The parts under a total at one moment: seed is constant for a post's life
 *  (written at creation, never changed), boost is whatever the total does
 *  not explain — guarded at the ceiling, where nothing is recoverable. */
function partsAt(total, organic, seed) {
  const boost = total >= policy.MAX_POST_RADIUS_METERS ? 0 : Math.max(0, total - organic - seed);
  return { seed, boost };
}

function entry(atMillis, cause, previous, next, seed, extra = {}) {
  const parts = partsAt(next.radiusMeters, next.organicRadiusMeters, seed);
  return policy.buildRadiusHistoryEntry({
    atMillis, cause, writer: WRITER, previous, next,
    seedRadiusMeters: parts.seed, boostedRadiusMeters: parts.boost, ...extra,
  });
}

async function planFor(postSnapshot) {
  const post = postSnapshot.data() ?? {};
  const historyRef = postSnapshot.ref.collection(policy.RADIUS_HISTORY_COLLECTION);
  const [existing, engagements] = await Promise.all([
    historyRef.get(),
    postSnapshot.ref.collection("engagements").orderBy("createdAt", "asc").get(),
  ]);
  const own = existing.docs.filter(doc => (doc.data() ?? {}).writer === WRITER);
  const keep = new Set(existing.docs.filter(doc => !rewrite || (doc.data() ?? {}).writer !== WRITER).map(doc => doc.id));
  const deletes = rewrite ? own.map(doc => doc.ref) : [];

  const seed = Math.max(0, finite(post.seedRadiusMeters) ?? 0);
  const parts = policy.postRadiusParts(post, RUN_MILLIS);
  const storedNow = parts.stored;
  const createdAtMillis = millisOf(post.createdAtMillis) ?? millisOf(post.createdAt) ?? RUN_MILLIS;

  // The exact record: applied engagements that paid something, in server order.
  const steps = [];
  for (const doc of engagements.docs) {
    const data = doc.data() ?? {};
    const counters = data.result?.counters;
    const at = millisOf(data.createdAt);
    const paid = finite(data.radiusDeltaMeters) ?? 0;
    if (data.applied !== true || !counters || at == null) continue;
    const total = finite(counters.radiusMeters);
    const organic = finite(counters.organicRadiusMeters);
    if (total == null || organic == null) continue;
    steps.push({ id: doc.id, at, total, organic, kind: data.kind, paid });
  }

  const writes = [];
  const add = (id, e) => { if (!keep.has(id)) writes.push({ id, entry: e }); };
  let previous = null;

  // Where the curve starts, and whether that is a fact or a reconstruction.
  const rewrittenByRunner = post.source === "synthetic-browser" && post.syntheticGeneration != null;
  const untouched = steps.length === 0 && post.decayedAt == null && !rewrittenByRunner && storedNow != null;
  if (seed > 0) {
    previous = { radiusMeters: seed, organicRadiusMeters: 0 };
    add(policy.radiusHistoryEntryId.create(), entry(createdAtMillis, "create", null, previous, seed));
  } else if (untouched) {
    previous = { radiusMeters: storedNow, organicRadiusMeters: parts.organic };
    add(policy.radiusHistoryEntryId.create(), entry(createdAtMillis, "create", null, previous, 0));
  } else if (steps.length) {
    // The earliest exact record is the first engagement; the reach it stepped
    // from is a fact at that moment, and nothing earlier is known.
    const first = steps[0];
    const from = { radiusMeters: Math.max(0, first.total - first.paid), organicRadiusMeters: Math.max(0, first.organic - first.paid) };
    previous = from;
    add(policy.radiusHistoryEntryId.backfill(first.at, "open"), entry(first.at, "backfill", null, from, seed));
  }

  for (const step of steps) {
    const from = { radiusMeters: Math.max(0, step.total - step.paid), organicRadiusMeters: Math.max(0, step.organic - step.paid) };
    // Something moved the reach between the last point and this engagement
    // and nothing recorded it: say so, rather than let a view carry it.
    if (previous && from.radiusMeters !== previous.radiusMeters) {
      add(policy.radiusHistoryEntryId.backfill(step.at, "gap"), entry(step.at, "backfill", previous, from, seed));
      previous = from;
    }
    const next = { radiusMeters: step.total, organicRadiusMeters: step.organic };
    if (next.radiusMeters === (previous ? previous.radiusMeters : -1)) { previous = next; continue; }
    add(policy.radiusHistoryEntryId.engagement(step.id), entry(step.at, "engagement", previous, next, seed, { kind: step.kind, engagementId: step.id }));
    previous = next;
  }

  // Today's STORED reach — the number the pin shows — closes the curve when
  // the record stops short of it.
  if (storedNow != null && (!previous || storedNow !== previous.radiusMeters)) {
    const at = Math.max(previous?.atMillis ?? 0, millisOf(post.decayedAt) ?? millisOf(post.updatedAt) ?? RUN_MILLIS);
    const next = { radiusMeters: storedNow, organicRadiusMeters: parts.organic };
    add(policy.radiusHistoryEntryId.backfill(at, "now"), entry(at, "backfill", previous, next, seed));
  }
  return { postId: postSnapshot.id, existing: existing.size, own: own.length, engagements: steps.length, writes, deletes };
}

async function main() {
  const posts = await db.collection("posts").get();
  let planned = 0;
  let removed = 0;
  let touched = 0;
  for (const snapshot of posts.docs) {
    const plan = await planFor(snapshot);
    if (!plan.writes.length && !plan.deletes.length) continue;
    touched += 1;
    planned += plan.writes.length;
    removed += plan.deletes.length;
    const causes = plan.writes.map(w => w.entry.cause).reduce((acc, c) => { acc[c] = (acc[c] || 0) + 1; return acc; }, {});
    console.log(`${plan.postId}: -${plan.deletes.length} +${plan.writes.length} ${JSON.stringify(causes)}; ${plan.engagements} engagements`);
    if (!execute) continue;
    let batch = db.batch();
    let inBatch = 0;
    const flush = async () => { if (inBatch) { await batch.commit(); batch = db.batch(); inBatch = 0; } };
    for (const ref of plan.deletes) { batch.delete(ref); inBatch += 1; if (inBatch === 400) await flush(); }
    for (const write of plan.writes) {
      batch.set(snapshot.ref.collection(policy.RADIUS_HISTORY_COLLECTION).doc(write.id), document(write.entry));
      inBatch += 1;
      if (inBatch === 400) await flush();
    }
    await flush();
  }
  console.log(`\n${posts.size} posts scanned, ${touched} touched, ${removed} own entries ${execute ? "removed" : "to remove"}, ${planned} entries ${execute ? "written" : "planned (dry run — add --execute)"}.`);
}

main().then(() => process.exit(0)).catch(error => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
