import * as admin from "firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import {
  buildRadiusHistoryEntry,
  calculateRadiusDecay,
  postRadiusParts,
  radiusHistoryEntryId,
  RADIUS_DECAY_PER_DAY,
} from "./postEngagementPolicy";
import { radiusHistoryDocument, radiusHistoryRef } from "./radiusHistory";
import { addAccountClaimRadius, claimRadiusDeltaMeters, postOwnerUid } from "./accountRadius";
import { calculateSyntheticRetentionDecay } from "./syntheticRetentionPolicy";
import { simulationSlot } from "./syntheticDailyPolicy";

if (admin.apps.length === 0) admin.initializeApp();

const db = admin.firestore();

/**
 * Radius is a score you defend, not a stat you keep: organic radius halves in
 * ~13.5 days untouched (RADIUS_DECAY_PER_DAY, elapsed-time based so missed
 * runs catch up). The 5x all-user trial includes legacy demo reach stored
 * in the boost component, starting at its explicit activation time.
 *
 * The decay clock is `decayedAt`, written ONLY here: a post without one gets
 * a baseline stamp and no decay, so decay accrues purely between server
 * stamps and a pre-decay-era post is never punished retroactively. Clients
 * are locked out of decayedAt in firestore.rules — a client-written clock
 * would let an owner freeze their own decay.
 *
 * Production uses the sharded due-work queue. The full scan remains available
 * only as a migration/rollback path while dueDecayEnabled is false.
 */
export async function runRadiusDecay(nowMillis = Date.now(), dueReferences?: admin.firestore.DocumentReference[]) {
    const [simulation, master, decayTrial] = await Promise.all([
      db.doc("testControl/syntheticDailySimulation").get(), db.doc("testControl/syntheticBrowserRunner").get(),
      db.doc("testControl/radiusDecayTrial").get(),
    ]);
    const stressEnabled = simulation.data()?.enabled === true && master.data()?.enabled === true;
    const nowTimestamp = Timestamp.fromMillis(nowMillis);
    let decayed = 0;
    let stamped = 0;
    // Paged range queries because legacy posts may carry only radius/radiusMeters
    // with no organicRadiusMeters field; the per-post transaction re-reads, so
    // overlap between the result sets is harmless.
    const references = new Map<string, admin.firestore.DocumentReference>();
    for (const ref of dueReferences || []) references.set(ref.path, ref);
    for (const field of dueReferences ? [] : ["organicRadiusMeters", "radiusMeters", "radius"]) {
      let cursor: admin.firestore.QueryDocumentSnapshot | undefined;
      for (;;) {
        const query = db.collection("posts").where(field, ">", 0).orderBy(field).limit(500);
        const page = await (cursor ? query.startAfter(cursor) : query).get();
        for (const doc of page.docs) references.set(doc.ref.path, doc.ref);
        if (page.size < 500) break;
        cursor = page.docs[page.docs.length - 1];
      }
    }
    for (const ref of references.values()) {
      await db.runTransaction(async transaction => {
        const snapshot = await transaction.get(ref);
        const queueRef = db.doc(`radiusDecayQueue/${ref.id}`);
        const queue = dueReferences ? await transaction.get(queueRef) : null;
        if (dueReferences && (!queue?.exists || (queue.data()?.dueAt?.toMillis?.() ?? 0) > nowMillis)) return;
        if (!snapshot.exists) { if (queue?.exists) transaction.delete(queueRef); return; }
        const post = snapshot.data() ?? {};
        // Queue advancement is atomic with the decay/history/account delta.
        // Retries see a future deadline and cannot debit the same hour twice.
        if (dueReferences) {
          const parts = postRadiusParts(post, nowMillis);
          if (parts.organic <= 0 && parts.seed <= 0 && parts.boost <= 0) {
            transaction.delete(queueRef); return;
          }
          transaction.update(queueRef, { dueAt: Timestamp.fromMillis(nowMillis + 3600_000) });
        }
        if (post.decayedAt == null) {
          transaction.update(ref, { decayedAt: nowTimestamp });
          stamped += 1;
          return;
        }
        const ownerUid = postOwnerUid(post);
        const trial = decayTrial.data()?.enabled === true ? decayTrial.data() as { multiplier: number; effectiveAtMillis: number; boostedEffectiveAtMillis?: number } : undefined;
        const stressDecay = stressEnabled && !trial ? calculateSyntheticRetentionDecay(post, nowMillis) : null;
        const next = stressDecay ?? calculateRadiusDecay(post, nowMillis, undefined, trial);
        if (!next) return;
        const before = postRadiusParts(post, nowMillis);
        const validTrial = trial && Number.isFinite(trial.multiplier) && trial.multiplier >= 1 && trial.multiplier <= 10
          && Number.isFinite(trial.effectiveAtMillis) && nowMillis >= trial.effectiveAtMillis ? trial : undefined;
        transaction.update(ref, {
          organicRadiusMeters: next.organicRadiusMeters,
          ...('boostedRadiusMeters' in next ? { boostedRadiusMeters: next.boostedRadiusMeters } : {}),
          ...(next.seedRadiusMeters != null ? { seedRadiusMeters: next.seedRadiusMeters } : {}),
          ...(next.radiusMeters <= 0 ? { visibilityStatus: "expired", expiredAt: nowTimestamp, expiryReason: "radius-zero" } : {}),
          radiusMeters: next.radiusMeters,
          radius: next.radiusMeters,
          decayedAt: nowTimestamp,
          // Display-only projection contract. Clients can show the continuous
          // curve between durable server updates without writing radius back.
          radiusDecayAnchorMillis: stressDecay ? 0 : nowMillis,
          radiusDecayOrganicPerDay: 1 - Math.pow(1 - RADIUS_DECAY_PER_DAY, validTrial?.multiplier ?? 1),
          radiusDecaySeedPerDay: validTrial ? 1 - Math.pow(1 - RADIUS_DECAY_PER_DAY, validTrial.multiplier) : 0,
          radiusDecayBoostPerDay: validTrial?.boostedEffectiveAtMillis && nowMillis >= validTrial.boostedEffectiveAtMillis
            ? 1 - Math.pow(1 - RADIUS_DECAY_PER_DAY, validTrial.multiplier) : 0,
          updatedAt: FieldValue.serverTimestamp(),
        });
        // Entitlement is the sum of what an account's posts have earned, so
        // decay takes it back on the same principle it was granted: the same
        // delta, in the same transaction as the post it belongs to. An
        // aggregate that only ever grew would let an account keep claiming
        // ground its posts no longer hold.
        if (ownerUid) {
          addAccountClaimRadius(
            transaction,
            db.collection("users").doc(ownerUid),
            claimRadiusDeltaMeters(before.organic, next.organicRadiusMeters),
          );
        }
        // The pop's history: decay is a change like any other and is recorded
        // with it, in the same transaction.
        transaction.create(
          radiusHistoryRef(ref, radiusHistoryEntryId.decay(nowMillis)),
          radiusHistoryDocument(buildRadiusHistoryEntry({
            atMillis: nowMillis,
            cause: "decay",
            writer: "radiusDecay",
            previous: { radiusMeters: before.stored ?? before.total, organicRadiusMeters: before.organic },
            next,
            seedRadiusMeters: next.seedRadiusMeters ?? before.seed,
            boostedRadiusMeters: 'boostedRadiusMeters' in next ? next.boostedRadiusMeters as number : before.boost,
          })),
        );
        if (stressDecay) {
          transaction.set(db.collection("testRetentionDecaySlots").doc(simulationSlot(nowMillis)), {
            lostMeters: FieldValue.increment(Math.max(0, before.total - next.radiusMeters)),
            postsDecayed: FieldValue.increment(1), updatedAt: nowTimestamp,
          }, { merge: true });
        }
        decayed += 1;
      });
    }
    console.log(`[radiusDecay] ${decayed} decayed, ${stamped} baseline-stamped, ${references.size} candidates`);
    return { decayed, stamped, candidates: references.size };
}

export const radiusDecay = onSchedule(
  { schedule: "every 60 minutes", region: "us-central1", timeoutSeconds: 300, memory: "256MiB" },
  async () => {
    // The old hourly sweep is only the rollback path during migration.
    if ((await db.doc('mapDiscovery/config').get()).data()?.dueDecayEnabled === true) return;
    await runRadiusDecay();
  },
);
