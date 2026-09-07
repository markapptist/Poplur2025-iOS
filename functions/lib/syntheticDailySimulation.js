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
exports.syntheticDailySimulation = void 0;
exports.runSyntheticDailySimulation = runSyntheticDailySimulation;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const postEngagement_1 = require("./postEngagement");
const syntheticBetaCohort_1 = require("./syntheticBetaCohort");
const accountRadius_1 = require("./accountRadius");
const radiusHistory_1 = require("./radiusHistory");
const postEngagementPolicy_1 = require("./postEngagementPolicy");
const syntheticDailyPolicy_1 = require("./syntheticDailyPolicy");
if (!admin.apps.length)
    admin.initializeApp();
const db = admin.firestore();
const CONFIG = "testControl/syntheticDailySimulation";
const ACTORS = "testDailySimulationActors";
/** Persistent daily quotas; retries/restarts reuse account, post and engagement IDs. */
async function runSyntheticDailySimulation(nowMillis = Date.now()) {
    const config = (await db.doc(CONFIG).get()).data();
    const master = (await db.doc("testControl/syntheticBrowserRunner").get()).data();
    if (config?.enabled !== true || master?.enabled !== true)
        return { status: "paused" };
    const day = (0, syntheticDailyPolicy_1.simulationDay)(nowMillis);
    const runRef = db.collection("testDailySimulationRuns").doc(day);
    const acquired = await db.runTransaction(async (tx) => {
        const row = (await tx.get(runRef)).data();
        if (row?.status === "complete" || Number(row?.leaseUntilMillis) > nowMillis)
            return false;
        tx.set(runRef, { day, status: "running", source: syntheticDailyPolicy_1.DAILY_SOURCE, leaseUntilMillis: nowMillis + 9 * 60_000, startedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        return true;
    });
    if (!acquired)
        return { status: "already-running-or-complete", day };
    try {
        const media = await db.collection("posts").where("officialContent", "==", true).get();
        const pool = media.docs.filter(doc => /^https:\/\//.test(String(doc.data().mediaURL || "")));
        if (!pool.length)
            throw new Error("No approved official media available for synthetic posts");
        for (const uid of (0, syntheticDailyPolicy_1.dailyTesterIds)(day)) {
            try {
                await admin.auth().getUser(uid);
            }
            catch (error) {
                if (error.code !== "auth/user-not-found")
                    throw error;
                await admin.auth().createUser({ uid, email: `${uid}@poplur.test`, displayName: `Simulation Tester ${uid.slice(10)}` });
            }
            const userRef = db.collection("users").doc(uid);
            await db.runTransaction(async (tx) => {
                const existing = await tx.get(userRef);
                if (!existing.exists)
                    tx.create(userRef, { uid, username: uid, email: `${uid}@poplur.test`, accountType: "personal", bio: "Labelled Poplur simulation account", syntheticBeta: true, syntheticSource: syntheticDailyPolicy_1.DAILY_SOURCE, claimRadiusMeters: 0, createdAt: firestore_1.FieldValue.serverTimestamp() });
                tx.set(db.collection(ACTORS).doc(uid), { uid, joinedDay: day, syntheticSource: syntheticDailyPolicy_1.DAILY_SOURCE }, { merge: true });
            });
        }
        const growing = await db.collection(ACTORS).get();
        const ids = [...new Set([...syntheticBetaCohort_1.SYNTHETIC_BETA_PROFILES.map(p => p.id), ...growing.docs.map(d => d.id)])].sort();
        let created = 0;
        for (const [actorIndex, uid] of ids.entries()) {
            // Fixed cohort accounts must actually exist; never impersonate a UID missing from Auth.
            await admin.auth().getUser(uid);
            for (let slot = 0; slot < syntheticDailyPolicy_1.DAILY_POSTS_PER_TESTER; slot++) {
                const postId = (0, syntheticDailyPolicy_1.dailyPostId)(day, uid, slot);
                const ref = db.collection("posts").doc(postId);
                const source = pool[(0, syntheticDailyPolicy_1.simulationHash)(postId) % pool.length];
                const creative = source.data();
                const location = (0, syntheticDailyPolicy_1.dailyPostLocation)(day, actorIndex, slot);
                const post = {
                    userID: uid, username: uid, mediaURL: creative.mediaURL, playbackURL: creative.mediaURL,
                    mediaType: creative.mediaType === "video" ? "video" : "photo",
                    ...(creative.posterURL ? { posterURL: creative.posterURL } : {}),
                    channelId: creative.channelId || "live", caption: `Simulation post · ${location.place} · ${day}`,
                    photoViewSeconds: 15, ...location, radius: accountRadius_1.POST_DISCOVERY_SEED_METERS, radiusMeters: accountRadius_1.POST_DISCOVERY_SEED_METERS,
                    seedRadiusMeters: accountRadius_1.POST_DISCOVERY_SEED_METERS, organicRadiusMeters: 0,
                    viewCount: 0, likeCount: 0, downvoteCount: 0, commentCount: 0,
                    audience: "public", status: "published", processingStatus: "ready", locationVisibility: "approximate",
                    syntheticBeta: true, syntheticCohort: true, syntheticActorId: uid, syntheticSource: syntheticDailyPolicy_1.DAILY_SOURCE,
                    approvedMediaPostId: source.id, simulationDay: day, schemaVersion: 2,
                    createdAt: firestore_1.Timestamp.fromMillis(nowMillis), createdAtMillis: nowMillis, decayedAt: firestore_1.Timestamp.fromMillis(nowMillis),
                };
                const didCreate = await db.runTransaction(async (tx) => {
                    if ((await tx.get(ref)).exists)
                        return false;
                    tx.create(ref, post);
                    tx.create((0, radiusHistory_1.radiusHistoryRef)(ref, postEngagementPolicy_1.radiusHistoryEntryId.create()), (0, radiusHistory_1.radiusHistoryDocument)((0, radiusHistory_1.creationHistoryEntry)(post, nowMillis, syntheticDailyPolicy_1.DAILY_SOURCE)));
                    return true;
                });
                if (didCreate)
                    created++;
            }
        }
        const posts = await db.collection("posts").orderBy("createdAtMillis", "desc").limit(400).get();
        const ownerUid = typeof config.ownerUid === "string" ? config.ownerUid : "";
        const ownerPosts = ownerUid ? await db.collection("posts").where("userID", "==", ownerUid).limit(40).get() : null;
        let engagements = 0;
        for (const uid of ids) {
            const available = posts.docs.filter(d => (0, accountRadius_1.postOwnerUid)(d.data()) !== uid && d.data().status !== "deleted"
                && d.data().audience !== "private" && d.data().officialContent !== true);
            const owner = (ownerPosts?.docs ?? []).filter(d => d.data().officialContent !== true && d.data().audience !== "private" && d.data().status !== "deleted");
            const others = available.filter(d => (0, accountRadius_1.postOwnerUid)(d.data()) !== ownerUid);
            const offset = (0, syntheticDailyPolicy_1.simulationHash)(`${day}:${uid}`);
            const targets = [...(owner.length ? [owner[offset % owner.length]] : []), ...[0, 1, 2].flatMap(n => others.length ? [others[(offset + n) % others.length]] : [])];
            for (const target of new Map(targets.map(d => [d.id, d])).values()) {
                const row = target.data();
                const reaction = (0, syntheticDailyPolicy_1.simulationReaction)(uid, target.id, row.syntheticBeta === true || row.syntheticCohort === true);
                // Declared test traffic uses the production transaction, including blocks,
                // duplicate grants, account totals, comments and per-post radius history.
                const kinds = ["view", reaction, ...(reaction === "like" ? ["comment"] : [])];
                for (const kind of kinds) {
                    try {
                        const result = await (0, postEngagement_1.applyPostEngagement)(uid, {
                            postId: target.id, eventId: `sim-${day}-${kind}-${(0, syntheticDailyPolicy_1.simulationHash)(target.id).toString(16)}`, kind,
                            ...(kind === "comment" ? { text: "Simulation tester: checking this post's comments and feed playback." } : {}),
                        });
                        if (!result.duplicate)
                            engagements++;
                    }
                    catch (error) {
                        const code = error.code;
                        if (code !== "permission-denied" && code !== "not-found" && code !== "failed-precondition")
                            throw error;
                        // An unavailable/blocked post is skipped, never bypassed through an admin write.
                        break;
                    }
                }
            }
        }
        const result = { status: "complete", day, testers: ids.length, newTesterIds: (0, syntheticDailyPolicy_1.dailyTesterIds)(day), postsCreatedThisAttempt: created, dailyPostTarget: ids.length * syntheticDailyPolicy_1.DAILY_POSTS_PER_TESTER, engagementsThisAttempt: engagements };
        await runRef.set({ ...result, leaseUntilMillis: 0, completedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        return result;
    }
    catch (error) {
        await runRef.set({ status: "error", leaseUntilMillis: 0, error: error instanceof Error ? error.message : String(error), updatedAt: firestore_1.FieldValue.serverTimestamp() }, { merge: true });
        throw error;
    }
}
exports.syntheticDailySimulation = (0, scheduler_1.onSchedule)({ schedule: "every 60 minutes", timeZone: "America/Toronto", region: "us-central1", timeoutSeconds: 540, memory: "512MiB" }, async () => {
    console.log("[syntheticDailySimulation]", await runSyntheticDailySimulation());
});
