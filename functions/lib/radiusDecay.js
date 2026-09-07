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
exports.radiusDecay = void 0;
exports.runRadiusDecay = runRadiusDecay;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const postEngagementPolicy_1 = require("./postEngagementPolicy");
const radiusHistory_1 = require("./radiusHistory");
const accountRadius_1 = require("./accountRadius");
const syntheticRetentionPolicy_1 = require("./syntheticRetentionPolicy");
const syntheticDailyPolicy_1 = require("./syntheticDailyPolicy");
if (admin.apps.length === 0)
    admin.initializeApp();
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
async function runRadiusDecay(nowMillis = Date.now()) {
    const [simulation, master] = await Promise.all([
        db.doc("testControl/syntheticDailySimulation").get(), db.doc("testControl/syntheticBrowserRunner").get(),
    ]);
    const stressEnabled = simulation.data()?.enabled === true && master.data()?.enabled === true;
    const nowTimestamp = firestore_1.Timestamp.fromMillis(nowMillis);
    let decayed = 0;
    let stamped = 0;
    // Paged range queries because legacy posts may carry only radius/radiusMeters
    // with no organicRadiusMeters field; the per-post transaction re-reads, so
    // overlap between the result sets is harmless.
    const references = new Map();
    for (const field of ["organicRadiusMeters", "radiusMeters", "radius"]) {
        let cursor;
        for (;;) {
            const query = db.collection("posts").where(field, ">", 0).orderBy(field).limit(500);
            const page = await (cursor ? query.startAfter(cursor) : query).get();
            for (const doc of page.docs)
                references.set(doc.ref.path, doc.ref);
            if (page.size < 500)
                break;
            cursor = page.docs[page.docs.length - 1];
        }
    }
    for (const ref of references.values()) {
        await db.runTransaction(async (transaction) => {
            const snapshot = await transaction.get(ref);
            if (!snapshot.exists)
                return;
            const post = snapshot.data() ?? {};
            if (post.decayedAt == null) {
                transaction.update(ref, { decayedAt: nowTimestamp });
                stamped += 1;
                return;
            }
            const stressDecay = stressEnabled ? (0, syntheticRetentionPolicy_1.calculateSyntheticRetentionDecay)(post, nowMillis) : null;
            const next = stressDecay ?? (0, postEngagementPolicy_1.calculateRadiusDecay)(post, nowMillis);
            if (!next)
                return;
            const before = (0, postEngagementPolicy_1.postRadiusParts)(post, nowMillis);
            transaction.update(ref, {
                organicRadiusMeters: next.organicRadiusMeters,
                ...(stressDecay ? { seedRadiusMeters: stressDecay.seedRadiusMeters } : {}),
                radiusMeters: next.radiusMeters,
                radius: next.radiusMeters,
                decayedAt: nowTimestamp,
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
            // Entitlement is the sum of what an account's posts have earned, so
            // decay takes it back on the same principle it was granted: the same
            // delta, in the same transaction as the post it belongs to. An
            // aggregate that only ever grew would let an account keep claiming
            // ground its posts no longer hold.
            const ownerUid = (0, accountRadius_1.postOwnerUid)(post);
            if (ownerUid) {
                (0, accountRadius_1.addAccountClaimRadius)(transaction, db.collection("users").doc(ownerUid), (0, accountRadius_1.claimRadiusDeltaMeters)(before.organic, next.organicRadiusMeters));
            }
            // The pop's history: decay is a change like any other and is recorded
            // with it, in the same transaction.
            transaction.create((0, radiusHistory_1.radiusHistoryRef)(ref, postEngagementPolicy_1.radiusHistoryEntryId.decay(nowMillis)), (0, radiusHistory_1.radiusHistoryDocument)((0, postEngagementPolicy_1.buildRadiusHistoryEntry)({
                atMillis: nowMillis,
                cause: "decay",
                writer: "radiusDecay",
                previous: { radiusMeters: before.stored ?? before.total, organicRadiusMeters: before.organic },
                next,
                seedRadiusMeters: stressDecay?.seedRadiusMeters ?? before.seed,
                boostedRadiusMeters: before.boost,
            })));
            if (stressDecay) {
                transaction.set(db.collection("testRetentionDecaySlots").doc((0, syntheticDailyPolicy_1.simulationSlot)(nowMillis)), {
                    lostMeters: firestore_1.FieldValue.increment(Math.max(0, before.total - next.radiusMeters)),
                    postsDecayed: firestore_1.FieldValue.increment(1), updatedAt: nowTimestamp,
                }, { merge: true });
            }
            decayed += 1;
        });
    }
    console.log(`[radiusDecay] ${decayed} decayed, ${stamped} baseline-stamped, ${references.size} candidates`);
    return { decayed, stamped, candidates: references.size };
}
exports.radiusDecay = (0, scheduler_1.onSchedule)({ schedule: "every 60 minutes", region: "us-central1", timeoutSeconds: 300, memory: "256MiB" }, async () => { await runRadiusDecay(); });
