import * as admin from "firebase-admin";
import { createHash, timingSafeEqual } from "node:crypto";
import { defineSecret } from "firebase-functions/params";
import { onRequest } from "firebase-functions/v2/https";
import {
  advanceSyntheticBrowserRuntime,
  emptySyntheticBrowserRuntime,
  SYNTHETIC_BETA_COHORT_ID,
  SYNTHETIC_RUNNER_ACTIONS,
  SYNTHETIC_RUNNER_EVENT_TYPES,
  SYNTHETIC_RUNNER_SCREENS,
  SyntheticBrowserEvent,
  SyntheticBrowserRuntime,
  syntheticProfile,
} from "./syntheticBetaCohort";
import { buildRadiusHistoryEntry, postRadiusParts, radiusHistoryEntryId } from "./postEngagementPolicy";
import { creationHistoryEntry, radiusHistoryDocument, radiusHistoryRef } from "./radiusHistory";

const REGION = "us-central1";
const RETENTION_MS = 14 * 24 * 60 * 60 * 1000;
const MAX_EVENT_AGE_MS = 10 * 60 * 1000;
const MAX_EVENT_FUTURE_MS = 60 * 1000;
const BETA_RUNNER_INGEST_TOKEN = defineSecret("BETA_RUNNER_INGEST_TOKEN");
const RUNNER_SECRET_HEADER = "X-Poplur-Runner-Token";

export const SYNTHETIC_RUNNER_CONFIG_DOC = "syntheticBrowserRunner";
export const SYNTHETIC_RUNNER_RUNTIME_DOC = "syntheticBrowserRuntime";
export const SYNTHETIC_RUNNER_ACTOR_COLLECTION = "testSyntheticRunnerActors";
export const SYNTHETIC_RUNNER_EVENT_COLLECTION = "testSyntheticBrowserEvents";
export const SYNTHETIC_RUNNER_SESSION_COLLECTION = "testSyntheticBrowserSessions";

type SyntheticMapPostSeed = {
  latitude: number;
  longitude: number;
  baseRadiusMeters: number;
};

/** Server-owned public test cells. Coordinates are never accepted from the
 * runner request or copied into analytics; they exist only in the ordinary
 * `posts` document that the real Map already consumes. */
const SYNTHETIC_MAP_POST_SEEDS: Readonly<Record<string, SyntheticMapPostSeed>> = {
  "sim-food-001": { latitude: 43.653, longitude: -79.383, baseRadiusMeters: 2_400 },
  "sim-sports-002": { latitude: 51.507, longitude: -0.128, baseRadiusMeters: 2_900 },
  "sim-music-003": { latitude: 43.646, longitude: -79.395, baseRadiusMeters: 2_100 },
  "sim-tech-004": { latitude: 37.775, longitude: -122.419, baseRadiusMeters: 3_100 },
  "sim-news-005": { latitude: 40.713, longitude: -74.006, baseRadiusMeters: 2_700 },
  // Business testers stand where they trade.
  "sim-biz-food-006": { latitude: 43.6545, longitude: -79.4005, baseRadiusMeters: 2_600 },
  "sim-biz-shop-007": { latitude: 43.6544, longitude: -79.3807, baseRadiusMeters: 2_300 },
  "sim-biz-fashion-008": { latitude: 40.7233, longitude: -74.003, baseRadiusMeters: 2_800 },
};

const SYNTHETIC_RADIUS_STEPS = [0, 600, 1_400, 900, -300] as const;

const EVENT_STATUSES = new Set(["foreground", "background", "idle", "blocked", "complete"]);
const END_STATUSES = new Set(["paused", "complete", "blocked"]);
const END_REASONS = new Set([
  "completed", "owner-paused", "cloud-paused", "runner-stopped", "browser-closed",
  "startup-error", "runner-error", "error",
]);
const METRIC_LIMITS: Record<string, [number, number]> = {
  loadMs: [0, 120_000],
  interactionMs: [0, 120_000],
  frameRate: [0, 240],
  heapMb: [0, 8_192],
  longTaskCount: [0, 10_000],
};

type RunnerIdentity = { uid: string; actorId: string };
type RunnerStatusRequest = { type: "status"; actorId: string };
type RunnerStartRequest = {
  type: "start";
  actorId: string;
  occurredAtMs: number;
};
type RunnerEventRequest = {
  type: "event";
  actorId: string;
  sessionId: string;
  sequence: number;
  occurredAtMs: number;
  screen: string;
  action: string;
  status: string;
  localFrameSequence: number;
  frameSuppressed: boolean;
  dwellMs: number;
  stepIndex: number;
  journeyLength: number;
  eventType: string;
  metrics: Record<string, number>;
};
type RunnerEndRequest = {
  type: "end";
  actorId: string;
  sessionId: string;
  sequence: number;
  occurredAtMs: number;
  status: string;
  reason: string;
};
export type SyntheticRunnerRequest = RunnerStatusRequest | RunnerStartRequest | RunnerEventRequest | RunnerEndRequest;

class RunnerRequestError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

function ensureAdmin(): void {
  if (!admin.apps.length) admin.initializeApp();
}

function db(): admin.firestore.Firestore {
  ensureAdmin();
  return admin.firestore();
}

function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new RunnerRequestError(400, "Send one JSON metadata object.");
  }
  return value as Record<string, unknown>;
}

function exactKeys(value: Record<string, unknown>, allowed: readonly string[]): void {
  const allowedKeys = new Set(allowed);
  const extra = Object.keys(value).find(key => !allowedKeys.has(key));
  if (extra) throw new RunnerRequestError(400, "Unsupported runner metadata field.");
}

function identifier(value: unknown, name: string, maxLength = 120): string {
  if (typeof value !== "string" || !new RegExp(`^[A-Za-z0-9_-]{1,${maxLength}}$`).test(value)) {
    throw new RunnerRequestError(400, `Invalid ${name}.`);
  }
  return value;
}

function integer(value: unknown, name: string, minimum: number, maximum: number): number {
  if (!Number.isSafeInteger(value) || (value as number) < minimum || (value as number) > maximum) {
    throw new RunnerRequestError(400, `Invalid ${name}.`);
  }
  return value as number;
}

function enumString(value: unknown, name: string, allowed: Set<string>): string {
  if (typeof value !== "string" || !allowed.has(value)) {
    throw new RunnerRequestError(400, `Invalid ${name}.`);
  }
  return value;
}

function eventTime(value: unknown, nowMs: number): number {
  const occurredAtMs = integer(value, "occurredAtMs", 0, Number.MAX_SAFE_INTEGER);
  if (occurredAtMs < nowMs - MAX_EVENT_AGE_MS || occurredAtMs > nowMs + MAX_EVENT_FUTURE_MS) {
    throw new RunnerRequestError(400, "Runner event timestamp is outside the live-session window.");
  }
  return occurredAtMs;
}

function numericMetrics(value: unknown): Record<string, number> {
  if (value === undefined) return {};
  const metrics = record(value);
  exactKeys(metrics, Object.keys(METRIC_LIMITS));
  return Object.fromEntries(Object.entries(metrics).map(([key, metric]) => {
    const [minimum, maximum] = METRIC_LIMITS[key];
    if (typeof metric !== "number" || !Number.isFinite(metric) || metric < minimum || metric > maximum) {
      throw new RunnerRequestError(400, "Runner metric is outside its allowed numeric range.");
    }
    return [key, metric];
  }));
}

export function parseSyntheticRunnerRequest(value: unknown, nowMs: number): SyntheticRunnerRequest {
  const body = record(value);
  const type = enumString(body.type, "type", new Set(["status", "start", "event", "end"])) as SyntheticRunnerRequest["type"];
  const actorId = identifier(body.actorId, "actorId", 80);
  if (!syntheticProfile(actorId)) throw new RunnerRequestError(400, "Runner actor is not in the fixed cohort.");

  if (type === "status") {
    exactKeys(body, ["type", "actorId"]);
    return { type, actorId };
  }

  const occurredAtMs = eventTime(body.occurredAtMs, nowMs);
  if (type === "start") {
    exactKeys(body, ["type", "actorId", "occurredAtMs"]);
    return { type, actorId, occurredAtMs };
  }

  const sessionId = identifier(body.sessionId, "sessionId");
  const sequence = integer(body.sequence, "sequence", 1, 1_000_000);
  if (type === "end") {
    exactKeys(body, ["type", "actorId", "sessionId", "sequence", "occurredAtMs", "status", "reason"]);
    return {
      type,
      actorId,
      sessionId,
      sequence,
      occurredAtMs,
      status: enumString(body.status, "status", END_STATUSES),
      reason: enumString(body.reason, "reason", END_REASONS),
    };
  }

  exactKeys(body, [
    "type", "actorId", "sessionId", "sequence", "occurredAtMs",
    "screen", "action", "status", "localFrameSequence", "frameSuppressed",
    "dwellMs", "stepIndex", "journeyLength", "eventType", "metrics",
  ]);
  const journeyLength = integer(body.journeyLength, "journeyLength", 1, 512);
  const stepIndex = integer(body.stepIndex, "stepIndex", 0, journeyLength - 1);
  if (typeof body.frameSuppressed !== "boolean") {
    throw new RunnerRequestError(400, "frameSuppressed must be a boolean.");
  }
  return {
    type,
    actorId,
    sessionId,
    sequence,
    occurredAtMs,
    screen: enumString(body.screen, "screen", SYNTHETIC_RUNNER_SCREENS),
    action: enumString(body.action, "action", SYNTHETIC_RUNNER_ACTIONS),
    status: enumString(body.status, "status", EVENT_STATUSES),
    localFrameSequence: integer(body.localFrameSequence, "localFrameSequence", 0, 10_000_000),
    frameSuppressed: body.frameSuppressed,
    dwellMs: integer(body.dwellMs, "dwellMs", 0, 600_000),
    stepIndex,
    journeyLength,
    eventType: enumString(body.eventType, "eventType", SYNTHETIC_RUNNER_EVENT_TYPES),
    metrics: numericMetrics(body.metrics),
  };
}

function validRunnerSecret(value: unknown): boolean {
  const supplied = typeof value === "string" ? value.trim() : "";
  const expected = BETA_RUNNER_INGEST_TOKEN.value();
  if (!supplied || !expected || supplied.length !== expected.length) return false;
  return timingSafeEqual(Buffer.from(supplied), Buffer.from(expected));
}

async function verifiedRunnerIdentity(authorization: string | undefined): Promise<RunnerIdentity> {
  const match = /^Bearer ([A-Za-z0-9._-]+)$/.exec(authorization ?? "");
  if (!match) throw new RunnerRequestError(401, "Runner Firebase ID token is required.");
  ensureAdmin();
  let token: admin.auth.DecodedIdToken;
  try {
    token = await admin.auth().verifyIdToken(match[1], true);
  } catch {
    throw new RunnerRequestError(401, "Runner Firebase ID token is invalid.");
  }
  const actorId = typeof token.syntheticActorId === "string" ? token.syntheticActorId : "";
  if (token.syntheticBeta !== true || !syntheticProfile(actorId)) {
    throw new RunnerRequestError(403, "Firebase runner claims are not authorized.");
  }
  return { uid: token.uid, actorId };
}

function runnerGeneration(data: FirebaseFirestore.DocumentData | undefined): number {
  return Number.isSafeInteger(data?.generation) && data!.generation > 0 ? data!.generation : 0;
}

export function validateSyntheticRunnerAccess(
  identity: RunnerIdentity,
  actorId: string,
  config: FirebaseFirestore.DocumentData | undefined,
  actor: FirebaseFirestore.DocumentData | undefined,
  expectedGeneration?: number,
): { enabled: boolean; generation: number } {
  const generation = runnerGeneration(config);
  const enabled = config?.enabled === true && generation > 0;
  if (config?.cohortId !== SYNTHETIC_BETA_COHORT_ID
    || actor?.active !== true
    || actor.actorId !== actorId
    || actor.uid !== identity.uid
    || actor.cohortId !== SYNTHETIC_BETA_COHORT_ID
    || actor.source !== "synthetic-browser"
    || identity.actorId !== actorId) {
    throw new RunnerRequestError(403, "Runner is not on the active allowlist.");
  }
  if (expectedGeneration !== undefined && expectedGeneration !== generation) {
    throw new RunnerRequestError(409, "Runner generation is stale.");
  }
  return { enabled, generation };
}

function stableHash(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

export function syntheticRunnerSessionId(actorId: string, generation: number, occurredAtMs: number): string {
  return `${actorId}_${generation}_${stableHash(`${actorId}:${generation}:${occurredAtMs}`).slice(0, 24)}`;
}

export function syntheticRunnerEventId(type: string, actorId: string, generation: number, sessionId: string, sequence: number): string {
  return stableHash(`${SYNTHETIC_BETA_COHORT_ID}:${type}:${actorId}:${generation}:${sessionId}:${sequence}`);
}

export function syntheticMapPostId(actorId: string, generation: number): string {
  if (!syntheticProfile(actorId) || !Number.isSafeInteger(generation) || generation <= 0) {
    throw new Error("Synthetic Map post identity is invalid.");
  }
  return `synthetic-${actorId}-${generation}`;
}

/** Media copied onto a synthetic Map post from that actor's OWN real post. */
export interface SyntheticActorMedia {
  mediaURL: string;
  mediaType: string;
  posterURL?: string;
  channelId?: string;
}

/**
 * The newest creative this actor actually published through the app.
 *
 * A pop is not a pop without media: the app's own delivery path drops a post
 * with no media URL before it ever reaches the Map, so every synthetic Map
 * post written here used to exist in Firestore and be invisible on device —
 * present enough to be wrong, absent enough to look like the Map was broken.
 *
 * It is deliberately the ACTOR'S OWN media and nothing else. Borrowing "any
 * recent post that has media" is how unapproved creative ends up on a post
 * that is not its author's; these actors publish real photos through the
 * ordinary Camera → Composer → Post flow, so their own most recent one is
 * both approved and honestly attributed. No media, no post.
 */
export async function syntheticActorMedia(actorId: string): Promise<SyntheticActorMedia | null> {
  const snapshot = await db().collection("posts")
    .where("userID", "==", actorId)
    .limit(30)
    .get();
  let newest: { media: SyntheticActorMedia; at: number } | null = null;
  for (const doc of snapshot.docs) {
    const row = doc.data();
    // Never source from another synthetic Map post: that is how a medialess
    // document would propagate itself forward once one existed.
    if (row.source === "synthetic-browser") continue;
    const playback = typeof row.playbackURL === "string" ? row.playbackURL.trim() : "";
    const direct = typeof row.mediaURL === "string" ? row.mediaURL.trim() : "";
    // By CONTENT, not presence: seeded rows carry playbackURL as "".
    const mediaURL = playback || direct;
    if (!mediaURL.startsWith("https://")) continue;
    const mediaType = typeof row.mediaType === "string" && row.mediaType.trim()
      ? row.mediaType.trim()
      : /\.(?:mp4|mov|m4v|webm)(?:[?#]|$)/i.test(mediaURL) ? "video" : "photo";
    const createdAt = row.createdAtMillis ?? row.createdAt?.toMillis?.() ?? 0;
    const at = Number.isFinite(Number(createdAt)) ? Number(createdAt) : 0;
    if (newest && at <= newest.at) continue;
    const poster = typeof row.posterURL === "string" ? row.posterURL.trim() : "";
    const channel = typeof row.channelId === "string" ? row.channelId.trim() : "";
    newest = {
      at,
      media: {
        mediaURL,
        mediaType,
        ...(poster.startsWith("https://") ? { posterURL: poster } : {}),
        ...(channel ? { channelId: channel } : {}),
      },
    };
  }
  return newest?.media ?? null;
}

/** The radius this actor's Nth Map post claims. Shared with the beta-desk row
 *  so the two can never disagree, and so deriving a radius does not require
 *  building a whole post (which now needs media the desk row has no use for). */
export function syntheticMapPostRadiusMeters(actorId: string, sequence: number): number {
  const seed = SYNTHETIC_MAP_POST_SEEDS[actorId];
  if (!seed || !Number.isSafeInteger(sequence) || sequence < 1) {
    throw new Error("Synthetic Map post event is invalid.");
  }
  return Math.max(1_000,
    seed.baseRadiusMeters + SYNTHETIC_RADIUS_STEPS[(sequence - 1) % SYNTHETIC_RADIUS_STEPS.length]);
}

export function syntheticMapPostData(
  actorId: string,
  generation: number,
  sessionId: string,
  sequence: number,
  media: SyntheticActorMedia,
): FirebaseFirestore.DocumentData {
  const profile = syntheticProfile(actorId);
  const seed = SYNTHETIC_MAP_POST_SEEDS[actorId];
  if (!profile || !seed || !Number.isSafeInteger(sequence) || sequence < 1) {
    throw new Error("Synthetic Map post event is invalid.");
  }
  const radiusMeters = syntheticMapPostRadiusMeters(actorId, sequence);
  return {
    userID: actorId,
    userId: actorId,
    username: profile.handle.replace(/^@/, ""),
    displayName: profile.persona,
    place: profile.place,
    locationName: profile.place,
    latitude: seed.latitude,
    longitude: seed.longitude,
    locationVisibility: "approximate",
    audience: "public",
    status: "published",
    visibilityStatus: "published",
    radiusMeters,
    radius: radiusMeters,
    organicRadiusMeters: radiusMeters,
    viewCount: sequence * 3,
    likeCount: Math.floor(sequence / 2),
    commentCount: Math.floor(sequence / 5),
    caption: `${profile.persona} closed-beta Map check`,
    // Carried from the actor's own published post; without it the app's
    // delivery path drops this document and the Map looks empty.
    mediaURL: media.mediaURL,
    mediaType: media.mediaType,
    ...(media.posterURL ? { posterURL: media.posterURL } : {}),
    channelId: media.channelId ?? "live",
    source: "synthetic-browser",
    syntheticBeta: true,
    testOnly: true,
    cohortId: SYNTHETIC_BETA_COHORT_ID,
    syntheticGeneration: generation,
    syntheticSessionId: sessionId,
  };
}

export function syntheticBetaPostData(
  actorId: string,
  generation: number,
  sessionId: string,
  sequence: number,
): FirebaseFirestore.DocumentData {
  const profile = syntheticProfile(actorId);
  if (!profile) throw new Error("Synthetic beta post identity is invalid.");
  const radiusKm = syntheticMapPostRadiusMeters(actorId, sequence) / 1_000;
  const initialRadiusKm = SYNTHETIC_MAP_POST_SEEDS[actorId].baseRadiusMeters / 1_000;
  return {
    uid: actorId,
    label: profile.label,
    place: profile.place,
    postKey: syntheticMapPostId(actorId, generation),
    initialRadiusKm,
    radiusKm,
    radiusDeltaKm: radiusKm - initialRadiusKm,
    viralScore: sequence * 3,
    source: "synthetic-browser",
    syntheticBeta: true,
    testOnly: true,
    cohortId: SYNTHETIC_BETA_COHORT_ID,
    syntheticGeneration: generation,
    syntheticSessionId: sessionId,
  };
}

function runtimeFrom(data: FirebaseFirestore.DocumentData | undefined, generation: number): SyntheticBrowserRuntime | undefined {
  if (data?.source !== "synthetic-browser"
    || data?.cohortId !== SYNTHETIC_BETA_COHORT_ID
    || data.generation !== generation
    || !Array.isArray(data.recentEvents)
    || !Array.isArray(data.sessions)
    || !data.analytics) return undefined;
  return data as SyntheticBrowserRuntime;
}

function storedEvent(event: SyntheticBrowserEvent, receivedAtMs: number): FirebaseFirestore.DocumentData {
  return {
    ...event,
    eventAt: admin.firestore.Timestamp.fromMillis(event.eventAtMs),
    receivedAt: admin.firestore.Timestamp.fromMillis(receivedAtMs),
    expiresAt: admin.firestore.Timestamp.fromMillis(receivedAtMs + RETENTION_MS),
  };
}

async function runnerStatus(identity: RunnerIdentity, request: RunnerStatusRequest): Promise<Record<string, unknown>> {
  const [configSnapshot, actorSnapshot] = await Promise.all([
    db().collection("testControl").doc(SYNTHETIC_RUNNER_CONFIG_DOC).get(),
    db().collection(SYNTHETIC_RUNNER_ACTOR_COLLECTION).doc(request.actorId).get(),
  ]);
  const status = validateSyntheticRunnerAccess(identity, request.actorId, configSnapshot.data(), actorSnapshot.data());
  return { ok: true, ...status, actorId: request.actorId };
}

async function ingestRunnerEvent(
  identity: RunnerIdentity,
  request: RunnerStartRequest | RunnerEventRequest | RunnerEndRequest,
  receivedAtMs: number,
): Promise<Record<string, unknown>> {
  const configRef = db().collection("testControl").doc(SYNTHETIC_RUNNER_CONFIG_DOC);
  const actorRef = db().collection(SYNTHETIC_RUNNER_ACTOR_COLLECTION).doc(request.actorId);
  const runtimeRef = db().collection("testControl").doc(SYNTHETIC_RUNNER_RUNTIME_DOC);
  // Resolved BEFORE the transaction on purpose: Firestore forbids a plain
  // query inside one, and this needs no atomicity — it reads the actor's
  // already-published creative, not state this write owns.
  const wantsMapPost = request.type === "event"
    && request.screen === "map"
    && request.action === "open-map";
  const actorMedia = wantsMapPost ? await syntheticActorMedia(request.actorId) : null;
  const sessionRef = db().collection(SYNTHETIC_RUNNER_SESSION_COLLECTION).doc(request.actorId);

  return db().runTransaction(async transaction => {
    const [configSnapshot, actorSnapshot, runtimeSnapshot, sessionSnapshot] = await Promise.all([
      transaction.get(configRef),
      transaction.get(actorRef),
      transaction.get(runtimeRef),
      transaction.get(sessionRef),
    ]);
    const access = validateSyntheticRunnerAccess(
      identity,
      request.actorId,
      configSnapshot.data(),
      actorSnapshot.data(),
    );
    if (!access.enabled || access.generation <= 0) {
      throw new RunnerRequestError(409, "Synthetic browser runner is paused.");
    }
    const generation = access.generation;
    const sessionId = request.type === "start"
      ? syntheticRunnerSessionId(request.actorId, generation, request.occurredAtMs)
      : request.sessionId;
    const sequence = request.type === "start" ? 0 : request.sequence;
    const eventId = syntheticRunnerEventId(request.type, request.actorId, generation, sessionId, sequence);
    const eventRef = db().collection(SYNTHETIC_RUNNER_EVENT_COLLECTION).doc(eventId);
    const eventSnapshot = await transaction.get(eventRef);
    if (eventSnapshot.exists) {
      return { ok: true, enabled: true, generation: access.generation, actorId: request.actorId, sessionId, eventId, duplicate: true };
    }

    const profile = syntheticProfile(request.actorId)!;
    const previousSession = sessionSnapshot.data();
    if (request.type !== "start") {
      if (previousSession?.source !== "synthetic-browser"
        || previousSession.cohortId !== SYNTHETIC_BETA_COHORT_ID
        || previousSession.generation !== generation
        || previousSession.sessionId !== sessionId
        || previousSession.actorId !== request.actorId
        || previousSession.status !== "live") {
        throw new RunnerRequestError(409, "Runner session is not active for this generation.");
      }
      if (!Number.isSafeInteger(previousSession.sequence) || request.sequence <= previousSession.sequence) {
        throw new RunnerRequestError(409, "Runner event sequence is stale.");
      }
      if (!Number.isSafeInteger(previousSession.lastEventAtMs)
        || request.occurredAtMs < previousSession.lastEventAtMs) {
        throw new RunnerRequestError(409, "Runner event time is stale.");
      }
    }

    const priorScreen = request.type === "start"
      ? null
      : (typeof previousSession?.currentScreen === "string" && SYNTHETIC_RUNNER_SCREENS.has(previousSession.currentScreen)
        ? previousSession.currentScreen
        : "home");
    const endScreen = priorScreen ?? "home";
    const event: SyntheticBrowserEvent = request.type === "start" ? {
      eventId,
      actorId: request.actorId,
      actor: profile.label,
      sessionId,
      generation,
      sequence,
      priorScreen,
      screen: "home",
      currentScreen: "home",
      action: "app-open",
      eventType: "session",
      stepIndex: 0,
      journeyLength: 1,
      dwellMs: 0,
      status: "foreground",
      localFrameSequence: 0,
      frameSuppressed: true,
      metrics: {},
      eventAtMs: request.occurredAtMs,
      place: profile.place,
      source: "synthetic-browser",
      cohortId: SYNTHETIC_BETA_COHORT_ID,
    } : request.type === "event" ? {
      eventId,
      actorId: request.actorId,
      actor: profile.label,
      sessionId,
      generation,
      sequence,
      priorScreen,
      screen: request.screen,
      currentScreen: request.screen,
      action: request.action,
      eventType: request.eventType,
      stepIndex: request.stepIndex,
      journeyLength: request.journeyLength,
      dwellMs: request.dwellMs,
      status: request.status,
      localFrameSequence: request.localFrameSequence,
      frameSuppressed: request.frameSuppressed,
      metrics: request.metrics,
      eventAtMs: request.occurredAtMs,
      place: profile.place,
      source: "synthetic-browser",
      cohortId: SYNTHETIC_BETA_COHORT_ID,
    } : {
      eventId,
      actorId: request.actorId,
      actor: profile.label,
      sessionId,
      generation,
      sequence,
      priorScreen,
      screen: endScreen,
      currentScreen: endScreen,
      action: "session-end",
      eventType: "lifecycle",
      stepIndex: request.sequence,
      journeyLength: Math.max(request.sequence + 1, Number(previousSession?.journeyLength) || 1),
      dwellMs: 0,
      status: request.status,
      localFrameSequence: Number(previousSession?.localFrameSequence) || 0,
      frameSuppressed: true,
      metrics: {},
      reason: request.reason,
      eventAtMs: request.occurredAtMs,
      place: profile.place,
      source: "synthetic-browser",
      cohortId: SYNTHETIC_BETA_COHORT_ID,
    };

    const shouldPublishMapPost = request.type === "event"
      && request.screen === "map"
      && request.action === "open-map";
    const mapPostRef = shouldPublishMapPost
      ? db().collection("posts").doc(syntheticMapPostId(request.actorId, generation))
      : null;
    const betaPostRef = shouldPublishMapPost
      ? db().collection("testBetaPosts").doc(syntheticMapPostId(request.actorId, generation))
      : null;
    const [mapPostSnapshot, betaPostSnapshot] = await Promise.all([
      mapPostRef ? transaction.get(mapPostRef) : Promise.resolve(null),
      betaPostRef ? transaction.get(betaPostRef) : Promise.resolve(null),
    ]);

    const currentRuntime = runtimeFrom(runtimeSnapshot.data(), generation)
      ?? emptySyntheticBrowserRuntime(generation, request.occurredAtMs);
    let runtime = advanceSyntheticBrowserRuntime(currentRuntime, event);
    if (request.type === "end") {
      runtime = {
        ...runtime,
        sessions: runtime.sessions.map(session => session.actorId === request.actorId
          ? { ...session, status: "paused" as const }
          : session),
      };
    }
    const session = runtime.sessions.find(candidate => candidate.actorId === request.actorId);
    if (!session) throw new RunnerRequestError(500, "Runner session state is unavailable.");
    const expiresAt = admin.firestore.Timestamp.fromMillis(receivedAtMs + RETENTION_MS);
    transaction.set(eventRef, storedEvent(event, receivedAtMs));
    transaction.set(sessionRef, {
      ...session,
      localFrameSequence: event.localFrameSequence,
      sessionStartedAt: admin.firestore.Timestamp.fromMillis(session.startedAtMs),
      lastEventAt: admin.firestore.Timestamp.fromMillis(session.lastEventAtMs),
      expiresAt,
    });
    transaction.set(runtimeRef, {
      ...runtime,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    // No media, no post. A Map document the delivery path will drop is worse
    // than no document: it sits in `posts` looking published while the Map
    // shows nothing, which reads as the Map being broken.
    if (mapPostRef && request.type === "event" && actorMedia) {
      const existingCreatedAt = mapPostSnapshot?.data()?.createdAt;
      const mapPost = syntheticMapPostData(request.actorId, generation, sessionId, request.sequence, actorMedia);
      transaction.set(mapPostRef, {
        ...mapPost,
        createdAt: existingCreatedAt ?? admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      // The synthetic pop's history, like any other pop's: a first point when
      // the document is born, then one per step that moves its reach.
      const previousPost = mapPostSnapshot?.exists ? (mapPostSnapshot.data() ?? {}) : null;
      const nowMillis = receivedAtMs;
      if (!previousPost) {
        transaction.set(
          radiusHistoryRef(mapPostRef, radiusHistoryEntryId.create()),
          radiusHistoryDocument(creationHistoryEntry({ ...mapPost, createdAtMillis: nowMillis }, nowMillis, "testSessionIngest")),
        );
      } else {
        const before = postRadiusParts(previousPost, nowMillis);
        const nextTotal = Number(mapPost.radiusMeters);
        if (Number.isFinite(nextTotal) && nextTotal !== before.total) {
          transaction.set(
            radiusHistoryRef(mapPostRef, radiusHistoryEntryId.synthetic(request.sequence)),
            radiusHistoryDocument(buildRadiusHistoryEntry({
              atMillis: nowMillis,
              cause: "synthetic",
              writer: "testSessionIngest",
              previous: { radiusMeters: before.total, organicRadiusMeters: before.organic },
              next: { radiusMeters: nextTotal, organicRadiusMeters: Number(mapPost.organicRadiusMeters) },
              seedRadiusMeters: 0,
              boostedRadiusMeters: 0,
            })),
          );
        }
      }
    }
    if (betaPostRef && request.type === "event") {
      const existingPostedAt = betaPostSnapshot?.data()?.postedAt;
      transaction.set(betaPostRef, {
        ...syntheticBetaPostData(request.actorId, generation, sessionId, request.sequence),
        postedAt: existingPostedAt ?? admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromMillis(receivedAtMs + RETENTION_MS),
      }, { merge: true });
    }
    return { ok: true, enabled: true, generation: access.generation, actorId: request.actorId, sessionId, eventId, duplicate: false };
  });
}

export const testSessionIngest = onRequest({
  region: REGION,
  secrets: [BETA_RUNNER_INGEST_TOKEN],
  cors: false,
  timeoutSeconds: 30,
}, async (request, response) => {
  response.set("Cache-Control", "no-store");
  try {
    if (request.method !== "POST") throw new RunnerRequestError(405, "POST is required.");
    if (!validRunnerSecret(request.get(RUNNER_SECRET_HEADER))) {
      throw new RunnerRequestError(401, "Runner ingest credential is invalid.");
    }
    const identity = await verifiedRunnerIdentity(request.get("Authorization"));
    const parsed = parseSyntheticRunnerRequest(request.body, Date.now());
    if (identity.actorId !== parsed.actorId) {
      throw new RunnerRequestError(403, "Runner actor claim does not match the request.");
    }
    const result = parsed.type === "status"
      ? await runnerStatus(identity, parsed)
      : await ingestRunnerEvent(identity, parsed, Date.now());
    response.status(200).json(result);
  } catch (error) {
    if (error instanceof RunnerRequestError) {
      response.status(error.status).json({ ok: false, error: error.message });
      return;
    }
    response.status(500).json({ ok: false, error: "Runner ingest failed safely." });
  }
});
