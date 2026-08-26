import * as admin from "firebase-admin";
import { randomUUID } from "crypto";
import { logger } from "firebase-functions";
import { onRequest } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";
import {
  GdeltQueryBatch,
  LiveNewsEvent,
  buildLiveNewsEvents,
  liveNewsContentHash,
  preserveLiveNewsIds,
} from "./liveNewsCore";

const REGION = "us-central1";
const GDELT_GEO_ENDPOINT = "https://api.gdeltproject.org/api/v2/geo/geo";
const GDELT_DOC_ENDPOINT = "https://api.gdeltproject.org/api/v2/doc/doc";
const GDELT_GEO_DOCUMENTATION = "https://blog.gdeltproject.org/gdelt-geo-2-0-api-debuts/";
const GDELT_DOC_DOCUMENTATION = "https://blog.gdeltproject.org/gdelt-doc-2-0-api-debuts/";

const SNAPSHOT_COLLECTION = "liveNewsPublic";
const SNAPSHOT_DOCUMENT = "current";
const SYSTEM_COLLECTION = "liveNewsSystem";
const LEASE_DOCUMENT = "ingest";
const LEASE_MS = 3 * 60_000;
const PROVIDER_TIMEOUT_MS = 14_000;
const GEO_RESPONSE_LIMIT = 8 * 1024 * 1024;
const DOC_RESPONSE_LIMIT = 5 * 1024 * 1024;
const MAX_PUBLIC_EVENTS = 40;

type QueryDefinition = {
  category: string;
  liveKind: GdeltQueryBatch["liveKind"];
  query: string;
};

/**
 * These deliberately describe observable public-interest events. Each query is
 * joined across GEO and DOC by article URL; a DOC headline without provider
 * coordinates is useful news, but is not allowed to move Poplur's map.
 */
const QUERY_DEFINITIONS: QueryDefinition[] = [
  {
    category: "public safety",
    liveKind: "safety",
    query: "(earthquake OR wildfire OR flood OR hurricane OR tornado OR eruption OR explosion OR evacuation OR \"state of emergency\")",
  },
  {
    category: "live events",
    liveKind: "event",
    query: "(parade OR festival OR protest OR demonstration OR rally OR march OR marathon OR election OR ceremony OR concert)",
  },
  {
    category: "transport",
    liveKind: "transport",
    query: "(derailment OR \"service suspended\" OR \"airport closed\" OR \"road closure\" OR \"transit disruption\")",
  },
  {
    category: "world",
    liveKind: "top",
    query: "(government OR economy OR health OR science OR climate)",
  },
];

type PublicSnapshot = {
  schemaVersion: 1;
  provider: "gdelt-geo-2.0";
  generatedAt: string;
  checkedAt: string;
  contentHash: string;
  events: LiveNewsEvent[];
  policy: {
    coordinates: "gdelt-geo-point-only";
    summaries: "deterministic-source-derived";
    media: "omit-without-explicit-reuse-rights";
    geoDocumentation: string;
    docDocumentation: string;
  };
};

function database(): admin.firestore.Firestore {
  if (admin.apps.length === 0) admin.initializeApp();
  return admin.firestore();
}

function snapshotRef(): admin.firestore.DocumentReference {
  return database().collection(SNAPSHOT_COLLECTION).doc(SNAPSHOT_DOCUMENT);
}

function leaseRef(): admin.firestore.DocumentReference {
  return database().collection(SYSTEM_COLLECTION).doc(LEASE_DOCUMENT);
}

function providerUrl(endpoint: string, definition: QueryDefinition, kind: "geo" | "doc"): URL {
  const url = new URL(endpoint);
  url.searchParams.set("query", definition.query);
  url.searchParams.set("timespan", "24h");
  if (kind === "geo") {
    url.searchParams.set("mode", "pointdata");
    url.searchParams.set("format", "geojson");
    url.searchParams.set("maxpoints", "125");
    // Excludes country and ADM1-only mentions so their centroids are not
    // presented as the site of a local event. City/landmark points remain.
    url.searchParams.set("geores", "2");
    url.searchParams.set("sort", "date");
  } else {
    url.searchParams.set("mode", "artlist");
    url.searchParams.set("format", "json");
    url.searchParams.set("maxrecords", "250");
    url.searchParams.set("sort", "datedesc");
  }
  return url;
}

async function fetchProviderJson(url: URL, byteLimit: number): Promise<unknown> {
  if (url.protocol !== "https:" || url.hostname !== "api.gdeltproject.org") {
    throw new Error("live_news_provider_host_rejected");
  }
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), PROVIDER_TIMEOUT_MS);
  try {
    const response = await fetch(url, {
      method: "GET",
      redirect: "error",
      signal: controller.signal,
      headers: {
        Accept: "application/json, application/geo+json",
        "User-Agent": "Poplur-News/1.0 (+https://poplur.com)",
      },
    });
    if (!response.ok) throw new Error(`live_news_provider_http_${response.status}`);
    if (response.url && new URL(response.url).hostname !== "api.gdeltproject.org") {
      throw new Error("live_news_provider_redirect_rejected");
    }
    const declaredSize = Number(response.headers.get("content-length"));
    if (Number.isFinite(declaredSize) && declaredSize > byteLimit) {
      throw new Error("live_news_provider_response_too_large");
    }
    const buffer = Buffer.from(await response.arrayBuffer());
    if (buffer.byteLength === 0 || buffer.byteLength > byteLimit) {
      throw new Error("live_news_provider_response_size_invalid");
    }
    try {
      return JSON.parse(buffer.toString("utf8")) as unknown;
    } catch {
      throw new Error("live_news_provider_json_invalid");
    }
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchQueryBatch(definition: QueryDefinition): Promise<GdeltQueryBatch> {
  const [geo, documents] = await Promise.all([
    fetchProviderJson(providerUrl(GDELT_GEO_ENDPOINT, definition, "geo"), GEO_RESPONSE_LIMIT),
    fetchProviderJson(providerUrl(GDELT_DOC_ENDPOINT, definition, "doc"), DOC_RESPONSE_LIMIT),
  ]);
  return { category: definition.category, liveKind: definition.liveKind, geo, documents };
}

async function fetchProviderBatches(): Promise<GdeltQueryBatch[]> {
  const batches: GdeltQueryBatch[] = [];
  // Two categories at a time bounds both upstream load and function memory.
  for (let index = 0; index < QUERY_DEFINITIONS.length; index += 2) {
    const definitions = QUERY_DEFINITIONS.slice(index, index + 2);
    const settled = await Promise.allSettled(definitions.map(fetchQueryBatch));
    settled.forEach((result, resultIndex) => {
      const definition = definitions[resultIndex];
      if (result.status === "fulfilled") batches.push(result.value);
      else logger.warn("live_news_provider_query_failed", {
        category: definition?.category ?? "unknown",
        reason: errorCode(result.reason),
      });
    });
  }
  if (batches.length === 0) throw new Error("live_news_all_provider_queries_failed");
  return batches;
}

function storedEvents(value: unknown): LiveNewsEvent[] {
  if (!Array.isArray(value)) return [];
  return value.filter((entry): entry is LiveNewsEvent => {
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) return false;
    const event = entry as Partial<LiveNewsEvent>;
    return typeof event.id === "string"
      && typeof event.title === "string"
      && typeof event.summary === "string"
      && typeof event.category === "string"
      && typeof event.place === "string"
      && typeof event.updatedAt === "string"
      && Array.isArray(event.coords)
      && event.coords.length === 2
      && event.coords.every(Number.isFinite)
      && Array.isArray(event.sources)
      && event.sources.every(source => source && typeof source.url === "string" && typeof source.publisher === "string")
      && Array.isArray(event.media);
  }).slice(0, MAX_PUBLIC_EVENTS);
}

async function acquireLease(token: string, nowMs: number): Promise<boolean> {
  const ref = leaseRef();
  return database().runTransaction(async transaction => {
    const snapshot = await transaction.get(ref);
    const leaseUntil = snapshot.data()?.leaseUntil;
    if (leaseUntil instanceof admin.firestore.Timestamp && leaseUntil.toMillis() > nowMs) return false;
    transaction.set(ref, {
      leaseToken: token,
      leaseUntil: admin.firestore.Timestamp.fromMillis(nowMs + LEASE_MS),
      lastStartedAt: admin.firestore.FieldValue.serverTimestamp(),
      state: "running",
    }, { merge: true });
    return true;
  });
}

async function releaseFailedLease(token: string, error: unknown): Promise<void> {
  const ref = leaseRef();
  await database().runTransaction(async transaction => {
    const snapshot = await transaction.get(ref);
    if (snapshot.data()?.leaseToken !== token) return;
    transaction.set(ref, {
      leaseToken: admin.firestore.FieldValue.delete(),
      leaseUntil: admin.firestore.Timestamp.fromMillis(0),
      lastFailedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastError: errorCode(error).slice(0, 160),
      state: "failed",
    }, { merge: true });
  });
}

function makePublicSnapshot(events: LiveNewsEvent[], generatedAt: string, checkedAt: string): PublicSnapshot {
  return {
    schemaVersion: 1,
    provider: "gdelt-geo-2.0",
    generatedAt,
    checkedAt,
    contentHash: liveNewsContentHash(events),
    events,
    policy: {
      coordinates: "gdelt-geo-point-only",
      summaries: "deterministic-source-derived",
      media: "omit-without-explicit-reuse-rights",
      geoDocumentation: GDELT_GEO_DOCUMENTATION,
      docDocumentation: GDELT_DOC_DOCUMENTATION,
    },
  };
}

async function publishSnapshot(token: string, rawEvents: LiveNewsEvent[], nowMs: number): Promise<{ changed: boolean; count: number }> {
  const currentRef = snapshotRef();
  const stateRef = leaseRef();
  const checkedAt = new Date(nowMs).toISOString();

  return database().runTransaction(async transaction => {
    const [state, current] = await Promise.all([
      transaction.get(stateRef),
      transaction.get(currentRef),
    ]);
    if (state.data()?.leaseToken !== token) throw new Error("live_news_lease_lost");

    const previousEvents = storedEvents(current.data()?.events);
    const events = preserveLiveNewsIds(rawEvents, previousEvents).slice(0, MAX_PUBLIC_EVENTS);
    if (events.length === 0) throw new Error("live_news_no_publishable_events");
    const contentHash = liveNewsContentHash(events);
    const existingHash = typeof current.data()?.contentHash === "string" ? current.data()?.contentHash : "";
    const existingGeneratedAt = typeof current.data()?.generatedAt === "string" ? current.data()?.generatedAt : null;
    const changed = contentHash !== existingHash;
    const generatedAt = changed || !existingGeneratedAt ? checkedAt : existingGeneratedAt;
    const next = makePublicSnapshot(events, generatedAt, checkedAt);

    if (changed || !current.exists) transaction.set(currentRef, next);
    else transaction.set(currentRef, { checkedAt, events, contentHash }, { merge: true });
    transaction.set(stateRef, {
      leaseToken: admin.firestore.FieldValue.delete(),
      leaseUntil: admin.firestore.Timestamp.fromMillis(0),
      lastCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
      lastError: admin.firestore.FieldValue.delete(),
      lastEventCount: events.length,
      lastContentHash: contentHash,
      state: "idle",
    }, { merge: true });
    return { changed, count: events.length };
  });
}

async function runLiveNewsRefresh(): Promise<void> {
  const token = randomUUID();
  const startedAt = Date.now();
  if (!await acquireLease(token, startedAt)) {
    logger.info("live_news_refresh_skipped_lease_active");
    return;
  }
  try {
    const batches = await fetchProviderBatches();
    const events = buildLiveNewsEvents(batches, Date.now());
    const published = await publishSnapshot(token, events, Date.now());
    logger.info("live_news_refresh_completed", {
      changed: published.changed,
      count: published.count,
      providerBatchCount: batches.length,
      elapsedMs: Date.now() - startedAt,
    });
  } catch (error) {
    await releaseFailedLease(token, error).catch(releaseError => {
      logger.error("live_news_lease_release_failed", { reason: errorCode(releaseError) });
    });
    logger.error("live_news_refresh_failed", {
      reason: errorCode(error),
      elapsedMs: Date.now() - startedAt,
    });
    throw error;
  }
}

/** Provider ingest is server-owned and idempotent; clients cannot trigger it. */
export const refreshLiveNews = onSchedule(
  {
    region: REGION,
    schedule: "every 15 minutes",
    timeZone: "Etc/UTC",
    retryCount: 2,
    minBackoffSeconds: 30,
    maxBackoffSeconds: 180,
    timeoutSeconds: 120,
    memory: "512MiB",
    maxInstances: 1,
  },
  async () => runLiveNewsRefresh()
);

function publicLimit(value: unknown): number {
  const raw = Array.isArray(value) ? value[0] : value;
  const parsed = typeof raw === "string" ? Number.parseInt(raw, 10) : NaN;
  return Number.isFinite(parsed) ? Math.max(1, Math.min(MAX_PUBLIC_EVENTS, parsed)) : MAX_PUBLIC_EVENTS;
}

function errorCode(error: unknown): string {
  if (error instanceof Error && error.name === "AbortError") return "provider_timeout";
  if (error instanceof Error && error.message) return error.message.replace(/[^a-zA-Z0-9_.-]/g, "_").slice(0, 160);
  return "unknown_error";
}

/** Public, cacheable, read-only endpoint consumed by both Map and Poplur News. */
export const liveNewsApi = onRequest(
  {
    region: REGION,
    cors: true,
    timeoutSeconds: 15,
    memory: "256MiB",
    maxInstances: 20,
  },
  async (request, response) => {
    response.set("Access-Control-Allow-Origin", "*");
    response.set("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS");
    response.set("Access-Control-Allow-Headers", "Accept, If-None-Match");
    response.set("X-Content-Type-Options", "nosniff");
    if (request.method === "OPTIONS") {
      response.status(204).send("");
      return;
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      response.set("Allow", "GET, HEAD, OPTIONS");
      response.status(405).json({ error: "method_not_allowed" });
      return;
    }

    const snapshot = await snapshotRef().get();
    const data = snapshot.data();
    const events = storedEvents(data?.events);
    if (!snapshot.exists || events.length === 0) {
      response.set("Cache-Control", "public, max-age=30");
      response.status(503).json({ events: [], generatedAt: null, stale: true, error: "live_news_initializing" });
      return;
    }

    const generatedAt = typeof data?.generatedAt === "string" ? data.generatedAt : null;
    const checkedAt = typeof data?.checkedAt === "string" ? data.checkedAt : generatedAt;
    const ageMs = checkedAt ? Date.now() - Date.parse(checkedAt) : Number.POSITIVE_INFINITY;
    const stale = !Number.isFinite(ageMs) || ageMs > 90 * 60_000;
    const fullHash = typeof data?.contentHash === "string" ? data.contentHash : liveNewsContentHash(events);
    const etag = `\"${fullHash}\"`;
    response.set("ETag", etag);
    response.set("Cache-Control", stale
      ? "public, max-age=30, stale-if-error=3600"
      : "public, max-age=60, stale-while-revalidate=900, stale-if-error=3600");
    if (request.get("if-none-match") === etag) {
      response.status(304).send("");
      return;
    }

    const payload = {
      events: events.slice(0, publicLimit(request.query.limit)),
      generatedAt,
      checkedAt,
      stale,
      provider: "GDELT GEO 2.0 + DOC 2.0",
      policy: data?.policy ?? makePublicSnapshot([], new Date(0).toISOString(), new Date(0).toISOString()).policy,
    };
    if (request.method === "HEAD") response.status(200).send("");
    else response.status(200).json(payload);
  }
);
