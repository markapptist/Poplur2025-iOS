#!/usr/bin/env node
"use strict";

/**
 * Give every existing pop its history.
 *
 * Posts made before radiusHistory existed have no entries, but they are not
 * without a record: every engagement that moved their reach wrote a
 * posts/{id}/engagements document whose `result.counters` are the exact totals
 * AFTER that event, stamped by the server. This script turns that record into
 * history — nothing is guessed:
 *
 *   create      the post's own createdAtMillis and its initial reach — the seed
 *               when the post carries one; otherwise the earliest engagement's
 *               total minus its delta (the reach that engagement stepped FROM);
 *               otherwise the reach the document holds now (a post nobody has
 *               touched has not moved)
 *   engagement  one entry per applied engagement that changed the total, at the
 *               engagement's server createdAt, from its stored counters
 *   backfill    one closing entry when the document's reach today differs from
 *               the last engagement's total (decay ran between — the exact
 *               ticks are gone, only their sum survives, and that is what this
 *               entry says)
 *
 * Idempotent: an entry that exists is left alone (deterministic ids), so the
 * script can be rerun after new engagements land. Dry run by default.
 *
 *   node scripts/backfillRadiusHistory.js            # report only
 *   node scripts/backfillRadiusHistory.js --execute  # write
 */

const admin = require("firebase-admin");
const policy = require("../lib/postEngagementPolicy.js");

const PROJECT_ID = "poplur2025";
const execute = process.argv.includes("--execute");
admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

function millisOf(value) {
  if (value == null) return null;
  if (typeof value === "number" && Number.isFinite(value) && value > 0) return value;
  if (typeof value.toMillis === "function") {
    const m = Number(value.toMillis());
    return Number.isFinite(m) && m > 0 ? m : null;
  }
  return null;
}

function document(entry) {
  return { ...entry, at: admin.firestore.Timestamp.fromMillis(entry.atMillis) };
}

async function planFor(postSnapshot) {
  const post = postSnapshot.data() ?? {};
  const historyRef = postSnapshot.ref.collection(policy.RADIUS_HISTORY_COLLECTION);
  const [existing, engagements] = await Promise.all([
    historyRef.get(),
    postSnapshot.ref.collection("engagements").orderBy("createdAt", "asc").get(),
  ]);
  const have = new Set(existing.docs.map(doc => doc.id));
  const now = Date.now();
  const nowParts = policy.postRadiusParts(post, now);
  const createdAtMillis = millisOf(post.createdAtMillis) ?? millisOf(post.createdAt) ?? now;

  // Applied engagements that actually moved the total, in server order.
  const steps = [];
  for (const doc of engagements.docs) {
    const data = doc.data() ?? {};
    const counters = data.result?.counters;
    const at = millisOf(data.createdAt);
    if (data.applied !== true || !counters || at == null) continue;
    const total = Number(counters.radiusMeters);
    const organic = Number(counters.organicRadiusMeters);
    if (!Number.isFinite(total) || !Number.isFinite(organic)) continue;
    steps.push({ id: doc.id, at, total, organic, kind: data.kind, delta: Number(data.radiusDeltaMeters) || 0 });
  }

  // Where the curve starts.
  let initial;
  if (Number.isFinite(Number(post.seedRadiusMeters)) && Number(post.seedRadiusMeters) > 0) {
    initial = { radiusMeters: nowParts.seed, organicRadiusMeters: 0 };
  } else if (steps.length) {
    initial = { radiusMeters: Math.max(0, steps[0].total - steps[0].delta), organicRadiusMeters: Math.max(0, steps[0].organic - steps[0].delta) };
  } else {
    initial = { radiusMeters: nowParts.total, organicRadiusMeters: nowParts.organic };
  }

  const writes = [];
  if (!have.has("create")) {
    writes.push({
      id: policy.radiusHistoryEntryId.create(),
      entry: policy.buildRadiusHistoryEntry({
        atMillis: createdAtMillis, cause: "create", writer: "backfillRadiusHistory",
        previous: null, next: initial, seedRadiusMeters: nowParts.seed, boostedRadiusMeters: 0,
      }),
    });
  }
  let previous = initial;
  for (const step of steps) {
    const next = { radiusMeters: step.total, organicRadiusMeters: step.organic };
    if (next.radiusMeters === previous.radiusMeters) { previous = next; continue; }
    const id = policy.radiusHistoryEntryId.engagement(step.id);
    if (!have.has(id)) {
      writes.push({
        id,
        entry: policy.buildRadiusHistoryEntry({
          atMillis: step.at, cause: "engagement", writer: "backfillRadiusHistory",
          previous, next, seedRadiusMeters: nowParts.seed, boostedRadiusMeters: nowParts.boost,
          kind: step.kind, engagementId: step.id,
        }),
      });
    }
    previous = next;
  }
  // Decay between then and now: only its sum survives, and it says so.
  if (nowParts.total !== previous.radiusMeters) {
    const at = millisOf(post.decayedAt) ?? millisOf(post.updatedAt) ?? now;
    const id = policy.radiusHistoryEntryId.backfill(at, "decay");
    if (!have.has(id)) {
      writes.push({
        id,
        entry: policy.buildRadiusHistoryEntry({
          atMillis: at, cause: "backfill", writer: "backfillRadiusHistory",
          previous, next: { radiusMeters: nowParts.total, organicRadiusMeters: nowParts.organic },
          seedRadiusMeters: nowParts.seed, boostedRadiusMeters: nowParts.boost,
        }),
      });
    }
  }
  return { postId: postSnapshot.id, existing: have.size, engagements: steps.length, writes };
}

async function main() {
  const posts = await db.collection("posts").get();
  let planned = 0;
  let touched = 0;
  for (const snapshot of posts.docs) {
    const plan = await planFor(snapshot);
    if (!plan.writes.length) continue;
    touched += 1;
    planned += plan.writes.length;
    const causes = plan.writes.map(w => w.entry.cause).join(",");
    console.log(`${plan.postId}: +${plan.writes.length} (${causes}); had ${plan.existing}, ${plan.engagements} engagements`);
    if (!execute) continue;
    let batch = db.batch();
    let inBatch = 0;
    for (const write of plan.writes) {
      batch.set(snapshot.ref.collection(policy.RADIUS_HISTORY_COLLECTION).doc(write.id), document(write.entry));
      inBatch += 1;
      if (inBatch === 400) { await batch.commit(); batch = db.batch(); inBatch = 0; }
    }
    if (inBatch) await batch.commit();
  }
  console.log(`\n${posts.size} posts scanned, ${touched} need history, ${planned} entries ${execute ? "written" : "planned (dry run — add --execute)"}.`);
}

main().then(() => process.exit(0)).catch(error => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
