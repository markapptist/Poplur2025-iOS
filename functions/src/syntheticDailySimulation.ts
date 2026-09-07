import * as admin from "firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { applyPostEngagement } from "./postEngagement";
import { SYNTHETIC_BETA_PROFILES } from "./syntheticBetaCohort";
import { POST_DISCOVERY_SEED_METERS, postOwnerUid } from "./accountRadius";
import { creationHistoryEntry, radiusHistoryDocument, radiusHistoryRef } from "./radiusHistory";
import { radiusHistoryEntryId } from "./postEngagementPolicy";
import { DAILY_SOURCE, DAILY_POSTS_PER_TESTER, dailyPostLocation, dailyTesterIds, simulationDay, simulationHash,
  simulationSlot, simulationSlotPostId, simulationEngagementKinds, SIMULATION_ACTIVE_ACTOR_LIMIT, SIMULATION_POSTS_PER_SLOT } from "./syntheticDailyPolicy";

if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();
const CONFIG = "testControl/syntheticDailySimulation";
const ACTORS = "testDailySimulationActors";

/** Hourly quotas: retries reuse IDs, while new hours add content all day. */
export async function runSyntheticDailySimulation(nowMillis = Date.now()) {
  const config = (await db.doc(CONFIG).get()).data();
  const master = (await db.doc("testControl/syntheticBrowserRunner").get()).data();
  if (config?.enabled !== true || master?.enabled !== true) return { status: "paused" };
  const day = simulationDay(nowMillis);
  const slotKey = simulationSlot(nowMillis);
  const runRef = db.collection("testDailySimulationRuns").doc(slotKey);
  const acquired = await db.runTransaction(async tx => {
    const row = (await tx.get(runRef)).data();
    if (row?.status === "complete" || Number(row?.leaseUntilMillis) > nowMillis) return false;
    tx.set(runRef, { day, status: "running", source: DAILY_SOURCE, leaseUntilMillis: nowMillis + 9 * 60_000, startedAt: FieldValue.serverTimestamp() }, { merge: true });
    return true;
  });
  if (!acquired) return { status: "already-running-or-complete", day };
  try {
    const media = await db.collection("posts").where("officialContent", "==", true).get();
    const pool = media.docs.filter(doc => /^https:\/\//.test(String(doc.data().mediaURL || "")));
    if (!pool.length) throw new Error("No approved official media available for synthetic posts");
    for (const uid of dailyTesterIds(day)) {
      try { await admin.auth().getUser(uid); }
      catch (error) {
        if ((error as { code?: string }).code !== "auth/user-not-found") throw error;
        await admin.auth().createUser({ uid, email: `${uid}@poplur.test`, displayName: `Simulation Tester ${uid.slice(10)}` });
      }
      const userRef = db.collection("users").doc(uid);
      await db.runTransaction(async tx => {
        const existing = await tx.get(userRef);
        if (!existing.exists) tx.create(userRef, { uid, username: uid, email: `${uid}@poplur.test`, accountType: "personal", bio: "Labelled Poplur simulation account", syntheticBeta: true, syntheticSource: DAILY_SOURCE, claimRadiusMeters: 0, createdAt: FieldValue.serverTimestamp() });
        tx.set(db.collection(ACTORS).doc(uid), { uid, joinedDay: day, syntheticSource: DAILY_SOURCE }, { merge: true });
      });
    }
    const growing = await db.collection(ACTORS).orderBy("joinedDay", "desc")
      .limit(SIMULATION_ACTIVE_ACTOR_LIMIT - SYNTHETIC_BETA_PROFILES.length).get();
    const ids = [...new Set([...SYNTHETIC_BETA_PROFILES.map(p => p.id), ...growing.docs.map(d => d.id)])].sort();
    let created = 0;
    for (const [actorIndex, uid] of ids.entries()) {
      // Fixed cohort accounts must actually exist; never impersonate a UID missing from Auth.
      await admin.auth().getUser(uid);
      for (let slot = 0; slot < SIMULATION_POSTS_PER_SLOT; slot++) {
        const postId = simulationSlotPostId(nowMillis, uid, slot);
        const ref = db.collection("posts").doc(postId);
        const source = pool[simulationHash(postId) % pool.length];
        const creative = source.data();
        const location = dailyPostLocation(day, actorIndex, new Date(nowMillis).getUTCHours() + slot);
        const post = {
          userID: uid, username: uid, mediaURL: creative.mediaURL, playbackURL: creative.mediaURL,
          mediaType: creative.mediaType === "video" ? "video" : "photo",
          ...(creative.posterURL ? { posterURL: creative.posterURL } : {}),
          channelId: creative.channelId || "live", caption: `Simulation post · ${location.place} · ${day}`,
          photoViewSeconds: 15, ...location, radius: POST_DISCOVERY_SEED_METERS, radiusMeters: POST_DISCOVERY_SEED_METERS,
          seedRadiusMeters: POST_DISCOVERY_SEED_METERS, organicRadiusMeters: 0,
          viewCount: 0, likeCount: 0, downvoteCount: 0, commentCount: 0,
          audience: "public", status: "published", processingStatus: "ready", locationVisibility: "approximate",
          syntheticBeta: true, syntheticCohort: true, syntheticActorId: uid, syntheticSource: DAILY_SOURCE,
          simulationRetentionVersion: 1, simulationSlot: slotKey,
          approvedMediaPostId: source.id, simulationDay: day, schemaVersion: 2,
          createdAt: Timestamp.fromMillis(nowMillis), createdAtMillis: nowMillis, decayedAt: Timestamp.fromMillis(nowMillis),
        };
        const didCreate = await db.runTransaction(async tx => {
          if ((await tx.get(ref)).exists) return false;
          tx.create(ref, post);
          tx.create(radiusHistoryRef(ref, radiusHistoryEntryId.create()), radiusHistoryDocument(creationHistoryEntry(post, nowMillis, DAILY_SOURCE)));
          return true;
        });
        if (didCreate) created++;
      }
    }
    const posts = await db.collection("posts").orderBy("createdAtMillis", "desc").limit(400).get();
    const ownerUid = typeof config.ownerUid === "string" ? config.ownerUid : "";
    const ownerPosts = ownerUid ? await db.collection("posts").where("userID", "==", ownerUid).limit(40).get() : null;
    let engagements = 0;
    let gainedMeters = created * POST_DISCOVERY_SEED_METERS;
    let lostMeters = 0;
    for (const uid of ids) {
      const available = posts.docs.filter(d => postOwnerUid(d.data()) !== uid && d.data().status !== "deleted"
        && d.data().audience !== "private" && d.data().officialContent !== true);
      const owner = (ownerPosts?.docs ?? []).filter(d => d.data().officialContent !== true && d.data().audience !== "private" && d.data().status !== "deleted");
      const others = available.filter(d => postOwnerUid(d.data()) !== ownerUid
        && (d.data().syntheticBeta === true || d.data().syntheticCohort === true));
      const offset = simulationHash(`${slotKey}:${uid}`);
      const targets = [...(owner.length ? [owner[offset % owner.length]] : []), ...[0, 1, 2].flatMap(n => others.length ? [others[(offset + n) % others.length]] : [])];
      for (const target of new Map(targets.map(d => [d.id, d])).values()) {
        const row = target.data();
        // Declared test traffic uses the production transaction, including blocks,
        // duplicate grants, account totals, comments and per-post radius history.
        const kinds = simulationEngagementKinds(uid, target.id, row.syntheticBeta === true || row.syntheticCohort === true);
        for (const kind of kinds) {
          try {
            const result = await applyPostEngagement(uid, {
              postId: target.id, eventId: `sim-${slotKey}-${kind}-${simulationHash(target.id).toString(16)}`, kind,
              ...(kind === "comment" ? { text: "Simulation tester: checking this post's comments and feed playback." } : {}),
            });
            if (!result.duplicate) {
              engagements++;
              gainedMeters += Math.max(0, result.radiusDeltaMeters);
              lostMeters += Math.max(0, -result.radiusDeltaMeters);
            }
          } catch (error) {
            const code = (error as { code?: string }).code;
            if (code !== "permission-denied" && code !== "not-found" && code !== "failed-precondition") throw error;
            // An unavailable/blocked post is skipped, never bypassed through an admin write.
            break;
          }
        }
      }
    }
    const result = { status: "complete", day, slot: slotKey, testers: ids.length, newTesterIds: dailyTesterIds(day), postsCreatedThisAttempt: created, dailyPostTarget: ids.length * DAILY_POSTS_PER_TESTER, hourlyPostTarget: ids.length * SIMULATION_POSTS_PER_SLOT, engagementsThisAttempt: engagements, gainedMetersThisAttempt: gainedMeters, lostMetersThisAttempt: lostMeters };
    await runRef.set({ ...result, leaseUntilMillis: 0, completedAt: FieldValue.serverTimestamp() }, { merge: true });
    return result;
  } catch (error) {
    await runRef.set({ status: "error", leaseUntilMillis: 0, error: error instanceof Error ? error.message : String(error), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    throw error;
  }
}

export const syntheticDailySimulation = onSchedule({ schedule: "every 60 minutes", timeZone: "America/Toronto", region: "us-central1", timeoutSeconds: 540, memory: "512MiB" }, async () => {
  console.log("[syntheticDailySimulation]", await runSyntheticDailySimulation());
});
