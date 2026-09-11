import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import {
  Coordinates, NearbyCandidate, NEARBY_DIGEST_LOOKBACK_MS, coordinatePair, digestDue, digestSinceMillis,
  digestWindowOpen, eligibleNearbyPost, nearbyDigestId, nearbyPopsNotification, orderNewestFirst,
  postCreatedAtMillis, postInViewerRadius, solarLocalHour,
} from "./nearbyPopsPolicy";

/**
 * The proactive push: hourly, for every account with a registered device,
 * "N new pops in your radius" — at most once per 20 h, only between 09:00 and
 * 20:59 solar time, and only when something actually landed.
 *
 * Accounts store no location, so "where you are" is anchored on the newest
 * post the person made (their public approximate pair, or the protected
 * postLocations copy for private/ghost accounts). A client may later write
 * users/{uid}.nearbyAnchor {latitude, longitude} and it takes precedence.
 *
 * Config (optional doc, all fields optional): testControl/nearbyPopsDigest
 *   enabled: boolean (default true)
 *   includeTestCohort: boolean (default false — synthetic posts are invisible
 *     to a real user outside test mode, so a digest must not point at them)
 *   maxUsersPerRun: number (default 500)
 */

if (admin.apps.length === 0) admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();
// Cold-start breadcrumb: index.ts requires this module about halfway through
// the codebase, so its presence in a revision's logs brackets a startup stall.
logger.info("nearbyPopsDigest module loaded", { pid: process.pid, uptimeMs: Math.round(process.uptime() * 1000) });

const CONFIG = "testControl/nearbyPopsDigest";
const RECENT_POST_LIMIT = 600;
const ANCHOR_POST_LIMIT = 10;
const WATERMARK = "nearbyDigestAtMillis";

interface TokenEntry { platform?: string; }
type PostRow = { id: string; data: Record<string, unknown> };

async function anchorFor(uid: string, user: Record<string, unknown>): Promise<Coordinates | null> {
  const declared = user.nearbyAnchor as Record<string, unknown> | undefined;
  const override = declared ? coordinatePair(declared.latitude, declared.longitude) : null;
  if (override) return override;
  const recent = await db.collection("posts").where("userID", "==", uid)
    .orderBy("createdAt", "desc").limit(ANCHOR_POST_LIMIT).get();
  const hiddenIds: string[] = [];
  for (const doc of recent.docs) {
    const data = doc.data();
    if (data.status === "deleted") continue;
    const pair = coordinatePair(data.latitude, data.longitude);
    if (pair) return pair;
    hiddenIds.push(doc.id);
  }
  for (const postId of hiddenIds) {
    const protectedCopy = await db.doc(`users/${uid}/postLocations/${postId}`).get();
    const data = protectedCopy.data();
    const pair = data ? coordinatePair(data.latitude, data.longitude) : null;
    if (pair) return pair;
  }
  return null;
}

async function sendDigest(uid: string, tokens: string[], notification: { title: string; body: string },
  data: Record<string, string>) {
  const dead: string[] = [];
  let delivered = 0;
  for (let offset = 0; offset < tokens.length; offset += 500) {
    const batch = tokens.slice(offset, offset + 500);
    const response = await messaging.sendEachForMulticast({
      tokens: batch,
      notification,
      data,
      apns: { payload: { aps: { "thread-id": "nearby-pops", sound: "default" } } },
      android: { priority: "high", notification: { channelId: "poplur_alerts", tag: "nearby-pops" } },
    });
    response.responses.forEach((result, index) => {
      if (result.success) { delivered++; return; }
      const code = result.error?.code;
      if (code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token") {
        dead.push(batch[index]);
      } else {
        logger.warn("nearby digest send failed", { uid, code, message: result.error?.message });
      }
    });
  }
  if (dead.length > 0) {
    // Delete by key so a device registering right now is never clobbered.
    await db.collection("users").doc(uid).update(
      Object.fromEntries(dead.map((token) => [`fcmTokens.${token}`, FieldValue.delete()])),
    ).catch((error) => logger.warn("dead token prune failed", { uid, message: (error as Error).message }));
  }
  return { delivered, pruned: dead.length };
}

export async function runNearbyPopsDigest(nowMillis = Date.now()) {
  const config = (await db.doc(CONFIG).get()).data() ?? {};
  if (config.enabled === false) return { status: "paused" };
  const includeTestCohort = config.includeTestCohort === true;
  const maxUsers = typeof config.maxUsersPerRun === "number" && config.maxUsersPerRun > 0
    ? Math.floor(config.maxUsersPerRun) : 500;

  const recentSnapshot = await db.collection("posts")
    .where("createdAt", ">=", Timestamp.fromMillis(nowMillis - NEARBY_DIGEST_LOOKBACK_MS))
    .orderBy("createdAt", "desc").limit(RECENT_POST_LIMIT).get();
  const recent: PostRow[] = recentSnapshot.docs.map((doc) => ({ id: doc.id, data: doc.data() }));

  const usersSnapshot = await db.collection("users").where("fcmTokens", "!=", null).limit(maxUsers).get();
  const summary = { status: "complete", users: usersSnapshot.size, recentPosts: recent.length,
    due: 0, inWindow: 0, anchored: 0, withPops: 0, sent: 0, delivered: 0, pruned: 0 };

  for (const userDoc of usersSnapshot.docs) {
    const uid = userDoc.id;
    const user = userDoc.data();
    const tokens = Object.keys((user.fcmTokens ?? {}) as Record<string, TokenEntry>);
    if (tokens.length === 0 || !digestDue(user[WATERMARK], nowMillis)) continue;
    summary.due++;
    const anchor = await anchorFor(uid, user);
    if (!anchor) continue;
    summary.anchored++;
    if (!digestWindowOpen(solarLocalHour(nowMillis, anchor.longitude))) continue;
    summary.inWindow++;

    const since = digestSinceMillis(user[WATERMARK], nowMillis);
    const viewerRadius = Number(user.claimRadiusMeters) || 0;
    const candidates: NearbyCandidate[] = [];
    for (const post of recent) {
      const createdAtMillis = postCreatedAtMillis(post.data);
      if (createdAtMillis <= since) continue;
      if (!eligibleNearbyPost(post.data, { viewerUid: uid, includeTestCohort })) continue;
      if (!postInViewerRadius(post.data, anchor, viewerRadius)) continue;
      const handle = typeof post.data.username === "string" ? post.data.username : "";
      candidates.push({ postId: post.id, handle: handle ? `@${handle.replace(/^@/, "")}` : "", createdAtMillis });
    }
    if (candidates.length === 0) continue;
    summary.withPops++;

    const ordered = orderNewestFirst(candidates);
    const notification = nearbyPopsNotification(ordered);
    if (!notification) continue;
    const notificationId = nearbyDigestId(nowMillis);
    const newest = ordered[0];
    const userRef = db.collection("users").doc(uid);
    const rowRef = userRef.collection("notifications").doc(notificationId);

    // One atomic reservation: a second overlapping run sees the watermark and stops.
    const reserved = await db.runTransaction(async (tx) => {
      const [row, fresh] = await tx.getAll(rowRef, userRef);
      if (row.exists || !digestDue(fresh.data()?.[WATERMARK], nowMillis)) return false;
      tx.create(rowRef, {
        id: notificationId, kind: "radiusEntry", title: notification.title, detail: notification.detail,
        actorUid: "", actorHandle: newest.handle, radiusDeltaMeters: 0,
        createdAt: FieldValue.serverTimestamp(), isUnread: true, isDismissed: false,
        postId: newest.postId, popCount: ordered.length, popIds: ordered.slice(0, 20).map((c) => c.postId),
      });
      tx.set(userRef, { [WATERMARK]: nowMillis }, { merge: true });
      return true;
    });
    if (!reserved) continue;

    const result = await sendDigest(uid, tokens, { title: notification.title, body: notification.body }, {
      postId: newest.postId, notificationId, kind: "radiusEntry", actorHandle: newest.handle,
      popCount: String(ordered.length),
    });
    summary.sent++;
    summary.delivered += result.delivered;
    summary.pruned += result.pruned;
    logger.info("nearby digest sent", { uid, pops: ordered.length, ...result });
  }
  logger.info("nearby digest run", summary);
  return summary;
}

export const nearbyPopsDigest = onSchedule(
  { schedule: "every 60 minutes", region: "us-central1", timeoutSeconds: 300, memory: "512MiB", cpu: 1, maxInstances: 1 },
  async () => { await runNearbyPopsDigest(); },
);
