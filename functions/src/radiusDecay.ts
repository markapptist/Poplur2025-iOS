import * as admin from "firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { calculateRadiusDecay } from "./postEngagementPolicy";

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
export const radiusDecay = onSchedule(
  { schedule: "every 60 minutes", region: "us-central1", timeoutSeconds: 300, memory: "256MiB" },
  async () => {
    const nowMillis = Date.now();
    const nowTimestamp = Timestamp.fromMillis(nowMillis);
    let decayed = 0;
    let stamped = 0;
    // Two range queries because legacy posts may carry only radius/radiusMeters
    // with no organicRadiusMeters field; the per-post transaction re-reads, so
    // overlap between the two result sets is harmless.
    const [organicSnapshot, legacySnapshot] = await Promise.all([
      db.collection("posts").where("organicRadiusMeters", ">", 0).limit(2_000).get(),
      db.collection("posts").where("radiusMeters", ">", 0).limit(2_000).get(),
    ]);
    const references = new Map<string, admin.firestore.DocumentReference>();
    for (const doc of [...organicSnapshot.docs, ...legacySnapshot.docs]) {
      references.set(doc.ref.path, doc.ref);
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
        const next = calculateRadiusDecay(post, nowMillis);
        if (!next) return;
        transaction.update(ref, {
          organicRadiusMeters: next.organicRadiusMeters,
          radiusMeters: next.radiusMeters,
          radius: next.radiusMeters,
          decayedAt: nowTimestamp,
          updatedAt: FieldValue.serverTimestamp(),
        });
        decayed += 1;
      });
    }
    console.log(`[radiusDecay] ${decayed} decayed, ${stamped} baseline-stamped, ${references.size} candidates`);
  },
);
