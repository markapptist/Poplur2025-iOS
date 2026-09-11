import * as admin from "firebase-admin";
import { timingSafeEqual } from "node:crypto";
import { FieldValue } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { RADIUS_HISTORY_COLLECTION } from "./postEngagementPolicy";
import { PRESENCE_COLLECTION, PRESENCE_LEASE_MS } from "./appPresence";
import { defineSecret } from "firebase-functions/params";
import {
  emptySyntheticBrowserRuntime,
  SYNTHETIC_BETA_COHORT_ID,
  SYNTHETIC_BETA_PROFILES,
  SyntheticBrowserRuntime,
  syntheticProfile,
} from "./syntheticBetaCohort";
import {
  SYNTHETIC_RUNNER_ACTOR_COLLECTION,
  SYNTHETIC_RUNNER_CONFIG_DOC,
  SYNTHETIC_RUNNER_RUNTIME_DOC,
} from "./syntheticBrowserRunner";

/**
 * Privacy-safe, opt-in operations telemetry for the September test cohort.
 *
 * This is intentionally a closed-beta operations feed, not general product
 * analytics. It never accepts message text, media, raw coordinates, contacts,
 * camera or microphone data. Map reporting is deliberately limited to a
 * coarse, user-visible city/region label. Each row carries a 14-day
 * `expiresAt` field enforced by the production Firestore TTL policy; the
 * dashboard is further restricted to the two retained production-test
 * administrators.
 */

const REGION = "us-central1";
const RETENTION_MS = 14 * 24 * 60 * 60 * 1000;
const BETA_DESK_ACCESS_TOKEN = defineSecret("BETA_DESK_ACCESS_TOKEN");
const BETA_DESK_OPERATOR_UID = "LiEG6SNtKEZN6eEGeybf0afZnHm1";
const TEST_ADMIN_UIDS = new Set([
  "LiEG6SNtKEZN6eEGeybf0afZnHm1", // testcall@poplur.com
  "eoP2Z0ElxIa0Eua7xpFxNlr6tur1", // mark@apptist.ca
]);
export const TEST_ACTIVITY_SCREEN_IDS = Object.freeze([
  "home", "map", "feed", "camera", "camera-roll", "profile", "hold-menu",
  "upload-flows", "arcade", "games", "battle", "map-radio", "feed-news",
  "map-conquer", "map-directions", "map-ipod", "map-show-me",
  "feed-apps", "feed-browser", "feed-casino", "feed-games", "feed-tvguide",
  "camera-ai-chat", "camera-studio",
  "profile-avatar", "profile-house", "profile-messages", "profile-notifications",
  "profile-phone", "profile-settings", "profile-stats", "profile-store",
  "profile-trophies", "profile-wallet", "profile-wardrobe",
] as const);
const SCREENS = new Set<string>(TEST_ACTIVITY_SCREEN_IDS);
const STATUSES = new Set(["foreground", "background"]);
const PLATFORMS = new Set(["native", "browser"]);
const EVENT_KINDS = new Set(["posted", "like", "view", "comment", "radius-up", "radius-down"]);
const FEEDBACK_LIMIT = 1_200;
const ACTIVITY_LIMIT = 100;
const POST_LIMIT = 120;
/** The tester table reads every account and the newest slice of the real
 *  posts ledger. Beta-sized on purpose; both are one read. */
const TESTER_TABLE_USER_LIMIT = 1000;
const TESTER_TABLE_POST_LIMIT = 2000;
const TESTER_RECENT_POSTS = 24;
/** A heartbeat this fresh is "online". Same window the activity rows use. */
const ONLINE_WINDOW_MS = 90_000;

function finiteCoordinate(latitude: unknown, longitude: unknown): { latitude: number; longitude: number } | null {
  const lat = Number(latitude);
  const lng = Number(longitude);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  return { latitude: lat, longitude: lng };
}

export interface TesterTableInput {
  now: number;
  users: Array<{ uid: string; profile: FirebaseFirestore.DocumentData }>;
  accounts: Array<{ uid: string; displayName: string | null; email: string | null; createdAtMs: number; lastSignInAtMs: number }>;
  heartbeats: Array<{ uid: string } & FirebaseFirestore.DocumentData>;
  ledger: Array<{ id: string } & FirebaseFirestore.DocumentData>;
  /** Live foreground leases from appPresenceSessions, already filtered to
   *  activeUntil > now by the query. Optional so older callers keep working. */
  leases?: Array<{ uid: string; synthetic: boolean; activeUntilMs: number }>;
}

export interface TesterPostSummary {
  id: string;
  createdAtMs: number;
  radiusMeters: number;
  mediaType: "photo" | "video";
  mediaCount: number;
  caption: string;
  channelId: string;
  coarse: { latitude: number; longitude: number } | null;
}

export interface TesterTableRow {
  uid: string;
  label: string;
  username: string;
  accountType: string;
  signedUpAtMs: number;
  lastSignInAtMs: number;
  /** online = a live foreground lease (every signed-in account writes one), or
   *  failing that a heartbeat inside ONLINE_WINDOW_MS; away = we have seen them
   *  but not now; unknown = never seen by either signal. */
  presence: "online" | "away" | "unknown";
  /** Which signal decided `presence`, so the desk can say "no signal" honestly. */
  presenceSource: "lease" | "heartbeat" | "none";
  lastActivityAtMs: number;
  screen: string;
  platform: string;
  postCount: number;
  lastPostedAtMs: number;
  posts: TesterPostSummary[];
  /** A cohort actor, sim-daily account or other labelled simulation account.
   *  The desk counts these apart so "new testers" means people. */
  synthetic: boolean;
}

/**
 * Pure. One row per account, joined across three sources that each know one
 * thing: Auth knows when they signed up, testActivity knows whether they are
 * here right now, and the posts ledger knows what they have made. A tester who
 * appears in none but Auth still gets a row - a signup with zero posts and no
 * heartbeat is exactly the person the owner most wants to see.
 */
export function buildTesterTable(input: TesterTableInput): TesterTableRow[] {
  const profiles = new Map(input.users.map(user => [user.uid, user.profile]));
  const heartbeats = new Map(input.heartbeats.map(beat => [beat.uid, beat]));
  // One uid can hold several session leases; the freshest wins. Synthetic
  // actors are counted elsewhere and must not read as human presence.
  const leases = new Map<string, number>();
  for (const lease of input.leases ?? []) {
    if (!lease.uid || lease.synthetic) continue;
    if (lease.activeUntilMs > input.now && lease.activeUntilMs <= input.now + PRESENCE_LEASE_MS) {
      leases.set(lease.uid, Math.max(leases.get(lease.uid) ?? 0, lease.activeUntilMs));
    }
  }
  const byOwner = new Map<string, TesterPostSummary[]>();
  for (const post of input.ledger) {
    const owner = typeof post.userID === "string" ? post.userID : "";
    if (!owner) continue;
    const list = byOwner.get(owner) ?? [];
    list.push({
      id: post.id,
      createdAtMs: safeMetric(post.createdAtMillis, 0, Number.MAX_SAFE_INTEGER) || timestampMs(post.createdAt),
      radiusMeters: safeMetric(post.radius, 0, 40_075_000),
      mediaType: post.mediaType === "video" ? "video" : "photo",
      mediaCount: safeMetric(post.mediaCount, 1, 10, 1),
      caption: text(post.caption, 120),
      channelId: text(post.channelId, 64),
      coarse: finiteCoordinate(post.latitude, post.longitude),
    });
    byOwner.set(owner, list);
  }
  // Every uid any source has seen. Auth first, so the signup date leads.
  const uids = new Set<string>([
    ...input.accounts.map(account => account.uid),
    ...input.users.map(user => user.uid),
    ...byOwner.keys(),
  ]);
  const accounts = new Map(input.accounts.map(account => [account.uid, account]));
  return [...uids].map((uid): TesterTableRow => {
    const account = accounts.get(uid);
    const profile = profiles.get(uid);
    const beat = heartbeats.get(uid);
    const heartbeatAtMs = beat ? timestampMs(beat.lastActivityAt) : 0;
    const leaseUntilMs = leases.get(uid) ?? 0;
    const heartbeatLive = input.now - heartbeatAtMs <= ONLINE_WINDOW_MS && heartbeatAtMs > 0;
    const presence: TesterTableRow["presence"] = leaseUntilMs || heartbeatLive ? "online"
      : beat || account?.lastSignInAtMs ? "away" : "unknown";
    const presenceSource: TesterTableRow["presenceSource"] = leaseUntilMs ? "lease" : beat ? "heartbeat" : "none";
    // The freshest thing we know about them, whichever signal it came from.
    const lastActivityAtMs = Math.max(heartbeatAtMs, leaseUntilMs ? input.now : 0, account?.lastSignInAtMs ?? 0);
    const posts = (byOwner.get(uid) ?? []).sort((a, b) => b.createdAtMs - a.createdAtMs);
    return {
      uid,
      label: labelFor(uid, profile, account?.displayName ?? null),
      username: text(profile?.username, 40),
      accountType: text(profile?.accountType, 16) || "user",
      signedUpAtMs: account?.createdAtMs ?? 0,
      lastSignInAtMs: account?.lastSignInAtMs ?? 0,
      presence,
      presenceSource,
      lastActivityAtMs,
      screen: text(beat?.screen, 40),
      platform: beat?.platform === "native" ? "native" : beat ? "browser" : "",
      postCount: posts.length,
      lastPostedAtMs: posts[0]?.createdAtMs ?? 0,
      posts: posts.slice(0, TESTER_RECENT_POSTS),
      synthetic: isSyntheticAccount(uid, profile, account?.email ?? null),
    };
  }).sort((a, b) => {
    const rank = (row: TesterTableRow) => row.presence === "online" ? 0 : row.presence === "away" ? 1 : 2;
    return rank(a) - rank(b)
      || b.lastActivityAtMs - a.lastActivityAtMs
      || b.lastPostedAtMs - a.lastPostedAtMs
      || b.signedUpAtMs - a.signedUpAtMs;
  });
}

/** Every way a simulation account announces itself: the cohort actor ids
 *  (syntheticBetaCohort), the sim-daily flags on users/{uid}
 *  (syntheticDailySimulation writes syntheticBeta + syntheticSource), the
 *  labelled accountType, and the @poplur.test mailbox every provisioner uses. */
export function isSyntheticAccount(uid: string, profile: FirebaseFirestore.DocumentData | undefined, email: string | null): boolean {
  if (syntheticProfile(uid)) return true;
  // Lab posters (synthetic-conquer-*) and sim-daily accounts carry it in the
  // uid itself; Auth uids are random, so a prefix cannot collide with a person.
  if (/^(synthetic-|sim-)/.test(uid)) return true;
  if (profile?.syntheticBeta === true || profile?.syntheticCohort === true) return true;
  if (typeof profile?.syntheticSource === "string" && profile.syntheticSource) return true;
  if (typeof profile?.accountType === "string" && profile.accountType.toLowerCase().startsWith("synthetic")) return true;
  return typeof email === "string" && email.toLowerCase().endsWith("@poplur.test");
}

/** A post is synthetic when its writer stamped it so, or when its owner is. */
export function isSyntheticPost(post: FirebaseFirestore.DocumentData, ownerSynthetic: boolean): boolean {
  return ownerSynthetic
    || post.syntheticBeta === true
    || post.syntheticCohort === true
    || (typeof post.syntheticActorId === "string" && post.syntheticActorId !== "");
}

const DAILY_SERIES_DAYS = 14;
/** The owner reads the desk from Toronto; days roll at that midnight. */
const DAILY_SERIES_TIME_ZONE = "America/Toronto";

export interface DailyCount {
  /** Calendar day in the series time zone, YYYY-MM-DD. */
  day: string;
  signups: number;
  syntheticSignups: number;
  posts: number;
  syntheticPosts: number;
}

export interface DailySeries {
  timeZone: string;
  /** Oldest first, ending today; every day present, zero-filled. */
  days: DailyCount[];
  /** False when the posts ledger slice was capped before the window's oldest
   *  day, so early columns may under-count pops. Signups come from Auth and
   *  are always complete. */
  postsComplete: boolean;
}

export interface DailySeriesInput {
  now: number;
  accounts: TesterTableInput["accounts"];
  users: TesterTableInput["users"];
  ledger: TesterTableInput["ledger"];
  days?: number;
  timeZone?: string;
  ledgerLimit?: number;
}

/**
 * Pure. How many people joined and how many pops were dropped on each of the
 * last N calendar days, real and synthetic counted apart. Built from the same
 * Auth page, users slice and posts slice the tester table already holds, so
 * it costs the dashboard no extra reads.
 */
export function buildDailySeries(input: DailySeriesInput): DailySeries {
  const timeZone = input.timeZone || DAILY_SERIES_TIME_ZONE;
  const count = Math.max(1, Math.min(input.days ?? DAILY_SERIES_DAYS, 90));
  const format = new Intl.DateTimeFormat("en-CA", { timeZone, year: "numeric", month: "2-digit", day: "2-digit" });
  const dayKey = (ms: number) => format.format(new Date(ms));
  // Walk back in half-day steps so a DST change can neither skip nor double a day.
  const keys: string[] = [];
  for (let step = 0; keys.length < count && step < count * 4; step++) {
    const key = dayKey(input.now - step * 43_200_000);
    if (!keys.includes(key)) keys.push(key);
  }
  keys.reverse();
  const byDay = new Map(keys.map(key => [key, { day: key, signups: 0, syntheticSignups: 0, posts: 0, syntheticPosts: 0 }]));
  const profiles = new Map(input.users.map(user => [user.uid, user.profile]));
  const syntheticOwners = new Set<string>();
  const seen = new Set<string>();
  const consider = (uid: string, email: string | null) => {
    if (isSyntheticAccount(uid, profiles.get(uid), email)) syntheticOwners.add(uid);
  };
  for (const account of input.accounts) { seen.add(account.uid); consider(account.uid, account.email); }
  for (const user of input.users) if (!seen.has(user.uid)) consider(user.uid, null);
  for (const account of input.accounts) {
    if (!account.createdAtMs) continue;
    const bucket = byDay.get(dayKey(account.createdAtMs));
    if (!bucket) continue;
    bucket.signups += 1;
    if (syntheticOwners.has(account.uid)) bucket.syntheticSignups += 1;
  }
  let oldestPostMs = Number.POSITIVE_INFINITY;
  for (const post of input.ledger) {
    const createdAtMs = safeMetric(post.createdAtMillis, 0, Number.MAX_SAFE_INTEGER) || timestampMs(post.createdAt);
    if (!createdAtMs) continue;
    oldestPostMs = Math.min(oldestPostMs, createdAtMs);
    const bucket = byDay.get(dayKey(createdAtMs));
    if (!bucket) continue;
    const owner = typeof post.userID === "string" ? post.userID : "";
    const ownerSynthetic = owner ? (syntheticOwners.has(owner) || isSyntheticAccount(owner, profiles.get(owner), null)) : false;
    bucket.posts += 1;
    if (isSyntheticPost(post, ownerSynthetic)) bucket.syntheticPosts += 1;
  }
  const limit = input.ledgerLimit ?? TESTER_TABLE_POST_LIMIT;
  const postsComplete = input.ledger.length < limit
    || (Number.isFinite(oldestPostMs) && dayKey(oldestPostMs) < keys[0]);
  return { timeZone, days: keys.map(key => byDay.get(key)!), postsComplete };
}

const FEEDBACK_LIST_LIMIT = 80;

function db(): admin.firestore.Firestore {
  if (!admin.apps.length) admin.initializeApp();
  return admin.firestore();
}

function requireSignedIn(uid: string | undefined): string {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in to use the Test Control Center.");
  return uid;
}

function requireAdmin(uid: string): void {
  if (!TEST_ADMIN_UIDS.has(uid)) {
    throw new HttpsError("permission-denied", "This private tester dashboard is restricted.");
  }
}

/** A local owner-only proxy presents this value; it never reaches browser JS. */
function hasValidDeskCredential(value: unknown): boolean {
  const supplied = typeof value === "string" ? value.trim() : "";
  const expected = BETA_DESK_ACCESS_TOKEN.value();
  if (!supplied || !expected || supplied.length !== expected.length) return false;
  return timingSafeEqual(Buffer.from(supplied), Buffer.from(expected));
}

function enumValue(value: unknown, allowed: Set<string>, fallback: string): string {
  return typeof value === "string" && allowed.has(value) ? value : fallback;
}

function appVersion(value: unknown): string {
  return typeof value === "string" && /^\d+\.\d+(?:\.\d+)?$/.test(value)
    ? value.slice(0, 24)
    : "0.1.0";
}

/**
 * Copy only the bounded presence fields accepted by a heartbeat. Keeping this
 * as a positive projection means extra request fields (including content,
 * coordinates, media/input, and mic/camera state) can never reach Firestore.
 */
export function privacySafeTestActivityHeartbeat(data: Record<string, unknown>): {
  screen: string;
  status: string;
  platform: string;
  appVersion: string;
} {
  return {
    screen: enumValue(data.screen, SCREENS, "home"),
    status: enumValue(data.status, STATUSES, "foreground"),
    platform: enumValue(data.platform, PLATFORMS, "browser"),
    appVersion: appVersion(data.appVersion),
  };
}

function text(value: unknown, maxLength: number): string {
  return typeof value === "string" ? value.trim().replace(/\s+/g, " ").slice(0, maxLength) : "";
}

function safeMetric(value: unknown, minimum: number, maximum: number, fallback = 0): number {
  const metric = typeof value === "number" ? value : Number(value);
  return Number.isFinite(metric) ? Math.max(minimum, Math.min(maximum, metric)) : fallback;
}

function safeKey(value: unknown): string {
  return text(value, 80).replace(/[^a-zA-Z0-9_-]/g, "_") || "untitled";
}

function timestampMs(value: unknown): number {
  return value && typeof (value as { toMillis?: unknown }).toMillis === "function"
    ? (value as { toMillis: () => number }).toMillis()
    : 0;
}

function activeConsent(profile: FirebaseFirestore.DocumentData | undefined): boolean {
  return profile?.testActivityConsent === true;
}

async function clearTelemetryForUser(uid: string): Promise<void> {
  const posts = await db().collection("testBetaPosts").where("uid", "==", uid).limit(POST_LIMIT).get();
  const batch = db().batch();
  posts.docs.forEach(doc => batch.delete(doc.ref));
  batch.delete(db().collection("testActivity").doc(uid));
  await batch.commit();
}

function labelFor(uid: string, profile: FirebaseFirestore.DocumentData | undefined, authName: unknown): string {
  const username = typeof profile?.username === "string" ? profile.username.trim().replace(/^@/, "") : "";
  if (username) return `@${username.slice(0, 40)}`;
  const name = typeof authName === "string" ? authName.trim() : "";
  if (name) return name.slice(0, 50);
  return `Tester ${uid.slice(-4)}`;
}

function currentRunnerRuntime(
  data: FirebaseFirestore.DocumentData | undefined,
  generation: number,
): SyntheticBrowserRuntime | undefined {
  if (data?.source !== "synthetic-browser"
    || data?.cohortId !== SYNTHETIC_BETA_COHORT_ID
    || data.generation !== generation
    || !Array.isArray(data.recentEvents)
    || !Array.isArray(data.sessions)
    || !data.analytics) return undefined;
  return data as SyntheticBrowserRuntime;
}

function runnerGeneration(data: FirebaseFirestore.DocumentData | undefined): number {
  return Number.isSafeInteger(data?.generation) && data!.generation > 0 ? data!.generation : 0;
}

function publicRunnerActors(data: FirebaseFirestore.DocumentData | undefined): Array<{
  actorId: string;
  active: boolean;
}> {
  if (!Array.isArray(data?.actors)) return [];
  return data!.actors
    .map((actor: unknown) => {
      if (!actor || typeof actor !== "object") return null;
      const value = actor as Record<string, unknown>;
      const actorId = text(value.actorId, 80);
      if (!syntheticProfile(actorId)) return null;
      return {
        actorId,
        active: value.active === true,
      };
    })
    .filter((actor): actor is { actorId: string; active: boolean } => actor !== null);
}

async function setRunnerEnabled(enabled: boolean, updatedBy: string): Promise<{ enabled: boolean; generation: number }> {
  const configRef = db().collection("testControl").doc(SYNTHETIC_RUNNER_CONFIG_DOC);
  return db().runTransaction(async transaction => {
    const snapshot = await transaction.get(configRef);
    const previousEnabled = snapshot.data()?.enabled === true;
    const previousGeneration = runnerGeneration(snapshot.data());
    const generation = enabled && !previousEnabled ? previousGeneration + 1 : previousGeneration;
    transaction.set(configRef, {
      enabled,
      generation,
      cohortId: SYNTHETIC_BETA_COHORT_ID,
      actors: publicRunnerActors(snapshot.data()),
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy,
    }, { merge: true });
    return { enabled, generation };
  });
}

async function setRunnerActor(
  actorId: string,
  runnerUid: string,
  active: boolean,
  updatedBy: string,
): Promise<{ actorId: string; active: boolean; generation: number }> {
  const profile = syntheticProfile(actorId);
  if (!profile) throw new HttpsError("invalid-argument", "Runner actor is outside the fixed cohort.");
  if (!/^[A-Za-z0-9_-]{6,128}$/.test(runnerUid)) {
    throw new HttpsError("invalid-argument", "Runner Firebase UID is invalid.");
  }
  const configRef = db().collection("testControl").doc(SYNTHETIC_RUNNER_CONFIG_DOC);
  const user = await admin.auth().getUser(runnerUid);
  const claims = { ...(user.customClaims ?? {}) } as Record<string, unknown>;
  if (active) {
    claims.syntheticBeta = true;
    claims.syntheticActorId = actorId;
  } else {
    delete claims.syntheticBeta;
    delete claims.syntheticActorId;
  }
  await admin.auth().setCustomUserClaims(runnerUid, claims);

  const actorRef = db().collection(SYNTHETIC_RUNNER_ACTOR_COLLECTION).doc(actorId);
  return db().runTransaction(async transaction => {
    const configSnapshot = await transaction.get(configRef);
    const generation = runnerGeneration(configSnapshot.data());
    const actors = publicRunnerActors(configSnapshot.data()).filter(actor => actor.actorId !== actorId);
    actors.push({ actorId, active });
    transaction.set(actorRef, {
      actorId,
      uid: runnerUid,
      active,
      source: "synthetic-browser",
      cohortId: SYNTHETIC_BETA_COHORT_ID,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy,
    });
    transaction.set(configRef, {
      ...(configSnapshot.exists ? {} : {
        enabled: false,
        generation: 0,
        cohortId: SYNTHETIC_BETA_COHORT_ID,
      }),
      actors,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy,
    }, { merge: true });
    return { actorId, active, generation };
  });
}

export const testActivityControl = onCall({ region: REGION, secrets: [BETA_DESK_ACCESS_TOKEN] }, async request => {
  const action = request.data?.action;
  const operatorAction = action === "dashboard"
    || action === "postHistory"
    || action === "simulation"
    || action === "simulationStep"
    || action === "simulationPulse"
    || action === "runner"
    || action === "runnerActor";
  const hasDeskAccess = hasValidDeskCredential(request.data?.accessCode)
    || (typeof request.auth?.uid === "string" && TEST_ADMIN_UIDS.has(request.auth.uid));
  const uid = request.auth?.uid
    ?? (operatorAction && hasDeskAccess ? BETA_DESK_OPERATOR_UID : requireSignedIn(request.auth?.uid));

  if (action === "setConsent") {
    const enabled = request.data?.enabled === true;
    const user = db().collection("users").doc(uid);
    await user.set({
      testActivityConsent: enabled,
      testActivityConsentUpdatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
    if (!enabled) await clearTelemetryForUser(uid);
    return { enabled };
  }

  if (action === "getConsent") {
    const profile = await db().collection("users").doc(uid).get();
    return { enabled: profile.data()?.testActivityConsent === true };
  }

  if (action === "heartbeat") {
    const user = db().collection("users").doc(uid);
    const profile = await user.get();
    if (!activeConsent(profile.data())) {
      throw new HttpsError("failed-precondition", "Test activity sharing is turned off.");
    }
    const now = Date.now();
    const heartbeat = privacySafeTestActivityHeartbeat(request.data ?? {});
    await db().collection("testActivity").doc(uid).set({
      label: labelFor(uid, profile.data(), request.auth?.token.name),
      ...heartbeat,
      lastActivityAt: FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(now + RETENTION_MS),
    }, { merge: true });
    return { accepted: true };
  }

  if (action === "post") {
    const profile = await db().collection("users").doc(uid).get();
    if (!activeConsent(profile.data())) {
      throw new HttpsError("failed-precondition", "Closed-beta analytics sharing is turned off.");
    }
    const now = Date.now();
    const postKey = safeKey(request.data?.postKey);
    const place = text(request.data?.place, 64) || "Private beta region";
    const radiusKm = safeMetric(request.data?.radiusKm, 0, 20_000);
    const id = `${uid}_${postKey}`;
    await db().collection("testBetaPosts").doc(id).set({
      uid,
      label: labelFor(uid, profile.data(), request.auth?.token.name),
      place,
      postKey,
      initialRadiusKm: radiusKm,
      radiusKm,
      radiusDeltaKm: 0,
      viralScore: 0,
      postedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(now + RETENTION_MS),
    }, { merge: true });
    return { accepted: true };
  }

  if (action === "radius") {
    const profile = await db().collection("users").doc(uid).get();
    if (!activeConsent(profile.data())) {
      throw new HttpsError("failed-precondition", "Closed-beta analytics sharing is turned off.");
    }
    const now = Date.now();
    const postKey = safeKey(request.data?.postKey);
    const radiusKm = safeMetric(request.data?.radiusKm, 0, 20_000);
    const deltaKm = safeMetric(request.data?.deltaKm, -2_000, 2_000);
    const signal = text(request.data?.signal, 24);
    const ref = db().collection("testBetaPosts").doc(`${uid}_${postKey}`);
    const current = await ref.get();
    const previous = current.data();
    const previousScore = safeMetric(previous?.viralScore, 0, 1_000_000);
    const scoreDelta = signal === "comment" ? 3 : signal === "like" ? 2 : signal === "view" ? 1 : Math.abs(deltaKm) >= 2 ? 2 : 1;
    await ref.set({
      uid,
      label: labelFor(uid, profile.data(), request.auth?.token.name),
      place: text(previous?.place, 64) || "Private beta region",
      postKey,
      initialRadiusKm: safeMetric(previous?.initialRadiusKm, 0, 20_000, radiusKm),
      radiusKm,
      radiusDeltaKm: safeMetric(previous?.radiusDeltaKm, -20_000, 20_000) + deltaKm,
      viralScore: previousScore + scoreDelta,
      postedAt: previous?.postedAt ?? FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(now + RETENTION_MS),
    }, { merge: true });
    return { accepted: true };
  }

  if (action === "feedback") {
    const finding = text(request.data?.finding, FEEDBACK_LIMIT);
    const liked = text(request.data?.liked, FEEDBACK_LIMIT);
    const improve = text(request.data?.improve, FEEDBACK_LIMIT);
    if (!finding && !liked && !improve) {
      throw new HttpsError("invalid-argument", "Add a finding, a positive, or an improvement idea.");
    }
    const profile = await db().collection("users").doc(uid).get();
    const now = Date.now();
    await db().collection("testFeedback").add({
      uid,
      label: labelFor(uid, profile.data(), request.auth?.token.name),
      finding,
      liked,
      improve,
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(now + RETENTION_MS),
    });
    return { accepted: true };
  }

  if (action === "simulation") {
    const config = db().collection("testControl").doc("simulation");
    if (typeof request.data?.enabled === "boolean") {
      requireAdmin(uid);
      await config.set({
        enabled: request.data.enabled,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: uid,
      }, { merge: true });
    }
    const snapshot = await config.get();
    return { enabled: snapshot.data()?.enabled === true };
  }

  if (action === "simulationStep") {
    requireAdmin(uid);
    return { accepted: false, enabled: false, event: null, reason: "browser-runner-required" };
  }

  if (action === "simulationFeed") {
    return { enabled: false, events: [], reason: "runner-events-are-private" };
  }

  if (action === "simulationPulse") {
    requireAdmin(uid);
    return { accepted: false, enabled: false, event: null, reason: "browser-runner-required" };
  }

  if (action === "runner") {
    requireAdmin(uid);
    if (typeof request.data?.enabled === "boolean") {
      await setRunnerEnabled(request.data.enabled, uid);
    }
    const snapshot = await db().collection("testControl").doc(SYNTHETIC_RUNNER_CONFIG_DOC).get();
    return {
      enabled: snapshot.data()?.enabled === true,
      generation: runnerGeneration(snapshot.data()),
      actors: publicRunnerActors(snapshot.data()),
    };
  }

  if (action === "runnerActor") {
    requireAdmin(uid);
    const actorId = text(request.data?.actorId, 80);
    const runnerUid = text(request.data?.uid, 128);
    if (typeof request.data?.active !== "boolean") {
      throw new HttpsError("invalid-argument", "Runner actor active state is required.");
    }
    return setRunnerActor(actorId, runnerUid, request.data.active, uid);
  }

  if (action === "postHistory") {
    requireAdmin(uid);
    const postId = typeof request.data?.postId === "string" ? request.data.postId : "";
    if (!/^post-[A-Za-z0-9_-]{16,96}$/.test(postId)) {
      throw new HttpsError("invalid-argument", "That post id is not one this desk can open.");
    }
    const postRef = db().collection("posts").doc(postId);
    const [postSnapshot, historySnapshot] = await Promise.all([
      postRef.get(),
      postRef.collection(RADIUS_HISTORY_COLLECTION).orderBy("atMillis", "asc").limit(500).get(),
    ]);
    if (!postSnapshot.exists) throw new HttpsError("not-found", "That post no longer exists.");
    const post = postSnapshot.data() ?? {};
    const ownerId = typeof post.userID === "string" ? post.userID : "";
    // The exact drop point lives under the owner, never on the public post.
    // This desk is owner-only, so it may read it; the public document keeps
    // only the coarse cell, which is what everyone else gets.
    const exact = ownerId
      ? await db().collection("users").doc(ownerId).collection("postLocations").doc(postId).get().catch(() => null)
      : null;
    return {
      postId,
      ownerId,
      createdAtMs: timestampMs(post.createdAt) || safeMetric(post.createdAtMillis, 0, Number.MAX_SAFE_INTEGER),
      caption: text(post.caption, 280),
      channelId: text(post.channelId, 64),
      mediaType: post.mediaType === "video" ? "video" : "photo",
      mediaCount: safeMetric(post.mediaCount, 1, 10, 1),
      radiusMeters: safeMetric(post.radius, 0, 40_075_000),
      seedRadiusMeters: safeMetric(post.seedRadiusMeters, 0, 40_075_000),
      organicRadiusMeters: safeMetric(post.organicRadiusMeters, 0, 40_075_000),
      locationVisibility: text(post.locationVisibility, 16),
      coarse: finiteCoordinate(post.latitude, post.longitude),
      exact: exact?.exists ? finiteCoordinate(exact.data()?.latitude, exact.data()?.longitude) : null,
      history: historySnapshot.docs.map(doc => {
        const entry = doc.data();
        return {
          id: doc.id,
          atMs: safeMetric(entry.atMillis, 0, Number.MAX_SAFE_INTEGER),
          cause: text(entry.cause, 24) || "unknown",
          kind: text(entry.kind, 24) || null,
          radiusMeters: safeMetric(entry.radiusMeters, 0, 40_075_000),
          organicRadiusMeters: safeMetric(entry.organicRadiusMeters, 0, 40_075_000),
          seedRadiusMeters: safeMetric(entry.seedRadiusMeters, 0, 40_075_000),
          delta: safeMetric(entry.delta, -40_075_000, 40_075_000),
          writer: text(entry.writer, 40),
        };
      }),
    };
  }

  if (action === "dashboard") {
    requireAdmin(uid);
    const now = Date.now();
    const [activitySnapshot, postSnapshot, feedbackSnapshot, runtimeSnapshot, runnerConfigSnapshot, simulationConfigSnapshot, usersSnapshot, ledgerSnapshot, authPage, leaseSnapshot] = await Promise.all([
      db().collection("testActivity").orderBy("lastActivityAt", "desc").limit(ACTIVITY_LIMIT).get(),
      db().collection("testBetaPosts").orderBy("updatedAt", "desc").limit(POST_LIMIT).get(),
      db().collection("testFeedback").orderBy("createdAt", "desc").limit(FEEDBACK_LIST_LIMIT).get(),
      db().collection("testControl").doc(SYNTHETIC_RUNNER_RUNTIME_DOC).get(),
      db().collection("testControl").doc(SYNTHETIC_RUNNER_CONFIG_DOC).get(),
      db().collection("testControl").doc("simulation").get(),
      // The tester table below. Beta scale: every account and the newest slice
      // of the real posts ledger fit in one read each.
      db().collection("users").limit(TESTER_TABLE_USER_LIMIT).get(),
      db().collection("posts").orderBy("createdAtMillis", "desc").limit(TESTER_TABLE_POST_LIMIT).get(),
      admin.auth().listUsers(TESTER_TABLE_USER_LIMIT).catch(() => null),
      // Foreground leases are the online source: every account writes one,
      // opted into activity sharing or not. Heartbeats only say which screen.
      db().collection(PRESENCE_COLLECTION)
        .where("activeUntil", ">", admin.firestore.Timestamp.fromMillis(now))
        .select("uid", "synthetic", "activeUntil").get(),
    ]);
    const testers = buildTesterTable({
      now,
      users: usersSnapshot.docs.map(doc => ({ uid: doc.id, profile: doc.data() })),
      accounts: (authPage?.users ?? []).map(user => ({
        uid: user.uid,
        displayName: user.displayName ?? null,
        email: user.email ?? null,
        createdAtMs: Date.parse(user.metadata.creationTime ?? "") || 0,
        lastSignInAtMs: Date.parse(user.metadata.lastSignInTime ?? "") || 0,
      })),
      heartbeats: activitySnapshot.docs.map(doc => ({ uid: doc.id, ...doc.data() })),
      ledger: ledgerSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })),
      leases: leaseSnapshot.docs.map(doc => ({
        uid: typeof doc.data().uid === "string" ? doc.data().uid : "",
        synthetic: doc.data().synthetic === true,
        activeUntilMs: doc.data().activeUntil?.toMillis?.() ?? 0,
      })),
    });
    const daily = buildDailySeries({
      now,
      accounts: (authPage?.users ?? []).map(user => ({
        uid: user.uid,
        displayName: user.displayName ?? null,
        email: user.email ?? null,
        createdAtMs: Date.parse(user.metadata.creationTime ?? "") || 0,
        lastSignInAtMs: Date.parse(user.metadata.lastSignInTime ?? "") || 0,
      })),
      users: usersSnapshot.docs.map(doc => ({ uid: doc.id, profile: doc.data() })),
      ledger: ledgerSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })),
    });
    const posts = postSnapshot.docs.map(doc => {
      const post = doc.data();
      const postedAtMs = timestampMs(post.postedAt);
      const updatedAtMs = timestampMs(post.updatedAt);
      const elapsedHours = Math.max((now - (postedAtMs || now)) / 3_600_000, 0.1);
      const viralScore = safeMetric(post.viralScore, 0, 1_000_000);
      return {
        id: doc.id,
        label: text(post.label, 50) || "Tester",
        place: text(post.place, 64) || "Private beta region",
        postedAtMs,
        updatedAtMs,
        initialRadiusKm: safeMetric(post.initialRadiusKm, 0, 20_000),
        radiusKm: safeMetric(post.radiusKm, 0, 20_000),
        radiusDeltaKm: safeMetric(post.radiusDeltaKm, -20_000, 20_000),
        viralScore,
        viralPerHour: Math.round((viralScore / elapsedHours) * 10) / 10,
      };
    });
    const simulationEnabled = simulationConfigSnapshot.data()?.enabled === true;
    const runnerEnabled = runnerConfigSnapshot.data()?.enabled === true;
    const runnerGenerationValue = runnerGeneration(runnerConfigSnapshot.data());
    const runtime = currentRunnerRuntime(runtimeSnapshot.data(), runnerGenerationValue)
      ?? emptySyntheticBrowserRuntime(runnerGenerationValue, now);
    const runnerEvents = [...runtime.recentEvents]
      .sort((a, b) => b.eventAtMs - a.eventAtMs)
      .map(event => ({ id: event.eventId, ...event }));
    const actorStates = new Map(publicRunnerActors(runnerConfigSnapshot.data()).map(actor => [actor.actorId, actor]));
    const sessionStates = new Map(runtime.sessions.map(session => [session.actorId, session]));
    const runnerActors = SYNTHETIC_BETA_PROFILES.map(profile => {
      const allowlist = actorStates.get(profile.id);
      const session = sessionStates.get(profile.id);
      const active = allowlist?.active === true;
      return {
        id: profile.id,
        actorId: profile.id,
        label: profile.label,
        handle: profile.handle,
        persona: profile.persona,
        place: profile.place,
        avatarTile: profile.avatarTile,
        active,
        state: !runnerEnabled ? "paused" : session?.status === "live" ? "live" : active ? "ready" : "not-allowlisted",
        generation: runnerGenerationValue,
        source: profile.source,
        cohortId: profile.cohortId,
      };
    });
    const map = new Map<string, { place: string; events: number; realEvents: number; syntheticEvents: number; latestAtMs: number; peakRadiusKm: number; velocity: number }>();
    [
      ...posts.map(post => ({ place: post.place, at: post.updatedAtMs, radiusKm: post.radiusKm, velocity: post.viralPerHour, source: "real" as const })),
      ...runnerEvents.map(event => ({ place: event.place, at: event.eventAtMs, radiusKm: 0, velocity: 1, source: "synthetic" as const })),
    ]
      .forEach(event => {
        const previous = map.get(event.place) ?? {
          place: event.place,
          events: 0,
          realEvents: 0,
          syntheticEvents: 0,
          latestAtMs: 0,
          peakRadiusKm: 0,
          velocity: 0,
        };
        map.set(event.place, {
          place: event.place,
          events: previous.events + 1,
          realEvents: previous.realEvents + (event.source === "real" ? 1 : 0),
          syntheticEvents: previous.syntheticEvents + (event.source === "synthetic" ? 1 : 0),
          latestAtMs: Math.max(previous.latestAtMs, event.at),
          peakRadiusKm: Math.max(previous.peakRadiusKm, event.radiusKm),
          velocity: Math.max(previous.velocity, event.velocity),
        });
      });
    return {
      generatedAtMs: now,
      testers,
      daily,
      rows: activitySnapshot.docs.map(doc => {
        const row = doc.data();
        const lastActivityAtMs = row.lastActivityAt?.toMillis?.() ?? 0;
        return {
          id: doc.id,
          label: typeof row.label === "string" ? row.label : `Tester ${doc.id.slice(-4)}`,
          screen: typeof row.screen === "string" ? row.screen : "home",
          platform: row.platform === "native" ? "native" : "browser",
          appVersion: typeof row.appVersion === "string" ? row.appVersion : "0.1.0",
          status: row.status === "background" ? "background" : "foreground",
          lastActivityAtMs,
          state: now - lastActivityAtMs <= 90_000 ? "active" : "away",
        };
      }),
      posts,
      map: [...map.values()].sort((a, b) => b.events - a.events || b.latestAtMs - a.latestAtMs).slice(0, 32),
      simulation: [],
      simulationEnabled,
      syntheticProfiles: runnerActors,
      syntheticSessions: [],
      syntheticAnalytics: null,
      runnerEnabled,
      runnerGeneration: runnerGenerationValue,
      runnerActors,
      runnerEvents,
      runnerSessions: runtime.sessions
        .map(session => ({ ...session, status: runnerEnabled ? session.status : "paused" }))
        .sort((a, b) => SYNTHETIC_BETA_PROFILES.findIndex(profile => profile.id === a.actorId)
          - SYNTHETIC_BETA_PROFILES.findIndex(profile => profile.id === b.actorId)),
      runnerAnalytics: runtime.analytics,
      counts: {
        realTesters: activitySnapshot.size,
        realPosts: posts.length,
        syntheticPersonas: SYNTHETIC_BETA_PROFILES.length,
        syntheticEvents: runtime.analytics.eventCount,
        syntheticRecentEvents: runnerEvents.length,
        runnerActiveActors: runnerActors.filter(actor => actor.state === "live").length,
      },
      feedback: feedbackSnapshot.docs.map(doc => {
        const feedback = doc.data();
        return {
          id: doc.id,
          label: text(feedback.label, 50) || "Tester",
          finding: text(feedback.finding, FEEDBACK_LIMIT),
          liked: text(feedback.liked, FEEDBACK_LIMIT),
          improve: text(feedback.improve, FEEDBACK_LIMIT),
          createdAtMs: timestampMs(feedback.createdAt),
        };
      }),
    };
  }

  throw new HttpsError("invalid-argument", "Unsupported Test Control Center action.");
});
