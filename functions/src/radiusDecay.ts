import * as admin from "firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import {
  buildRadiusHistoryEntry,
  calculateRadiusDecay,
  postRadiusParts,
  radiusHistoryEntryId,
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
 * runs catch up). Boost never decays here — it is paid product with its own
 * boostExpiresAt. Feed reach labels snapshot at delivery and are unaffected;
 * only the live delivery gate shrinks.
 *
 * The decay clock is `decayedAt`, written ONLY here: a post without one gets
 * a baseline stamp and no decay, so decay accrues purely between server
 * stamps and a pre-decay-era post is never punished retroactively. Clients
 * are locked out of decayedAt in firestore.rules — a client-written clock
 * would let an owner freeze their own decay.
 *
 * Scale note: this pages the whole radius-bearing post set hourly, which is
 * fine at beta scale (hundreds). Past ~50k such posts, shard by decayedAt
 * cursor instead of re-reading everything.
 */
export async function runRadiusDecay(nowMillis = Date.now()) {
    const [simulation, master] = await Promise.all([
      db.doc("testControl/syntheticDailySimulation").get(), db.doc("testControl/syntheticBrowserRunner").get(),
    ]);
    const stressEnabled = simulation.data()?.enabled === true && master.data()?.enabled === true;
    const nowTimestamp = Timestamp.fromMillis(nowMillis);
    let decayed = 0;
    let stamped = 0;
    // Paged range queries because legacy posts may carry only radius/radiusMeters
    // with no organicRadiusMeters field; the per-post transaction re-reads, so
    // overlap between the result sets is harmless.
    const references = new Map<string, admin.firestore.DocumentReference>();
    for (const field of ["organicRadiusMeters", "radiusMeters", "radius"]) {
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
        if (!snapshot.exists) return;
        const post = snapshot.data() ?? {};
        if (post.decayedAt == null) {
          transaction.update(ref, { decayedAt: nowTimestamp });
          stamped += 1;
          return;
        }
        const stressDecay = stressEnabled ? calculateSyntheticRetentionDecay(post, nowMillis) : null;
        const next = stressDecay ?? calculateRadiusDecay(post, nowMillis);
        if (!next) return;
        const before = postRadiusParts(post, nowMillis);
        transaction.update(ref, {
          organicRadiusMeters: next.organicRadiusMeters,
          ...(stressDecay ? { seedRadiusMeters: stressDecay.seedRadiusMeters } : {}),
          radiusMeters: next.radiusMeters,
          radius: next.radiusMeters,
          decayedAt: nowTimestamp,
          updatedAt: FieldValue.serverTimestamp(),
        });
        // Entitlement is the sum of what an account's posts have earned, so
        // decay takes it back on the same principle it was granted: the same
        // delta, in the same transaction as the post it belongs to. An
        // aggregate that only ever grew would let an account keep claiming
        // ground its posts no longer hold.
        const ownerUid = postOwnerUid(post);
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
            seedRadiusMeters: stressDecay?.seedRadiusMeters ?? before.seed,
            boostedRadiusMeters: before.boost,
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
  async () => { await runRadiusDecay(); },
);
