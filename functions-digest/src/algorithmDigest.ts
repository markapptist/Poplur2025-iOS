import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { FieldPath, FieldValue, Timestamp } from "firebase-admin/firestore";
import { randomUUID } from "node:crypto";
import {
  DIGEST_SCHEMA_VERSION, DigestReader, DigestState, FoldOutcome, LEASE_MS, ObservedVersion, compactPayload, cursorsEqual, digestConfig,
  hydratePayload, initialState, readSwitches, runDigestFold, startCursorsOf,
} from "./algorithmDigestPolicy";
import { hydrateReportState } from "./algorithmReportPolicy";

/**
 * The algorithm desk digest — the I/O half. Runs inside the hourly
 * nearbyPopsDigest handler after the push digest, in its own try/catch, and
 * folds the radiusHistory ledgers of the registered real and official posts
 * into testControl/algorithmDigestState (private fold state) and
 * testControl/algorithmDigest (the published document the desk's proxy
 * watches), and — once per Toronto day — the daily algorithm report into
 * testControl/algorithmReports/daily/{day} with its index on the parent
 * document, inside the same commit transaction (design §2.7). Every rule
 * lives in algorithmDigestPolicy.ts / algorithmReportPolicy.ts; this file
 * only reads Firestore and Auth, takes the lease and commits.
 *
 * Config (optional doc, all fields optional): testControl/algorithmDigestConfig
 *   enabled, maxReadsPerRun (6000), horizonMs (30 min), daysPublished (30),
 *   channelLimit (12), postLimit (50), registeredPostLimit (500),
 *   pollExpiredEveryRuns (24), refreshEveryRuns (24), resetRequestedAtMillis.
 */

if (admin.apps.length === 0) admin.initializeApp();
const db = admin.firestore();

const STATE_DOC = "testControl/algorithmDigestState";
const PUBLISHED_DOC = "testControl/algorithmDigest";
const CONFIG_DOC = "testControl/algorithmDigestConfig";
export const REPORT_INDEX_DOC = "testControl/algorithmReports";
export const REPORT_DAYS = "testControl/algorithmReports/daily";
/** The switches radiusDecay.ts:36-39 and radiusDecayQueue.ts:74 read, sampled once per run. */
const SWITCH_DOCS = ["testControl/simulation", "testControl/syntheticBrowserRunner", "testControl/syntheticDailySimulation",
  "testControl/radiusDecayTrial", "mapDiscovery/config"];
const AUTH_PAGE_SIZE = 1000;

type Fields = Record<string, unknown>;

function timestampTuple(value: unknown): { seconds: number; nanoseconds: number } | null {
  return value instanceof Timestamp ? { seconds: value.seconds, nanoseconds: value.nanoseconds } : null;
}

/** State document → the engine's plain state. The sweep cursor is the exact
 *  Timestamp the last swept document carried (never millis: a re-encoded
 *  cursor sorts before a microsecond commit time and re-reads the row). */
export function decodeState(data: Fields | undefined): DigestState {
  const state = initialState();
  if (!data) return state;
  const number = (value: unknown, fallback: number) => (typeof value === "number" && Number.isFinite(value) ? value : fallback);
  state.digestVersion = number(data.digestVersion, 0);
  state.runId = typeof data.runId === "string" ? data.runId : null;
  state.leaseUntilMillis = number(data.leaseUntilMillis, 0);
  state.readsDay = typeof data.readsDay === "string" ? data.readsDay : null;
  state.readsToday = number(data.readsToday, 0);
  state.runsToday = number(data.runsToday, 0);
  const prev = data.readsPrev as Fields | null | undefined;
  state.readsPrev = prev && typeof prev === "object" ? { day: typeof prev.day === "string" ? prev.day : null, reads: number(prev.reads, 0), runs: number(prev.runs, 0) } : null;
  const sweep = (data.sweep ?? {}) as Fields;
  const cursor = timestampTuple(sweep.cursorCreatedAt);
  state.sweep = {
    cursor: cursor && typeof sweep.cursorPath === "string" ? { ...cursor, path: sweep.cursorPath } : null,
    coldStartDone: sweep.coldStartDone === true,
  };
  const refresh = (data.refresh ?? {}) as Fields;
  state.refresh = { lastRefreshDay: typeof refresh.lastRefreshDay === "string" ? refresh.lastRefreshDay : null };
  state.observedPolicyVersions = Array.isArray(data.observedPolicyVersions) ? data.observedPolicyVersions as ObservedVersion[] : [];
  state.authPageFailedRuns = number(data.authPageFailedRuns, 0);
  state.lastResetAtMillis = number(data.lastResetAtMillis, 0);
  if (typeof data.payload === "string" && data.payload) {
    try { state.payload = hydratePayload(JSON.parse(data.payload)); }
    catch (error) { logger.warn("algorithm digest payload unreadable; starting empty", { message: (error as Error).message }); }
  }
  // The report's memory rides beside the payload as one JSON string (the IO:80 precedent, decision 5).
  if (typeof data.report === "string" && data.report) {
    try { state.report = hydrateReportState(JSON.parse(data.report)); }
    catch (error) { logger.warn("algorithm report state unreadable; starting empty", { message: (error as Error).message }); }
  }
  return state;
}

export function encodeState(state: DigestState): Fields {
  const cursor = state.sweep.cursor;
  return {
    version: DIGEST_SCHEMA_VERSION, digestVersion: state.digestVersion, runId: state.runId, leaseUntilMillis: 0,
    readsDay: state.readsDay, readsToday: state.readsToday, runsToday: state.runsToday, readsPrev: state.readsPrev,
    sweep: { cursorCreatedAt: cursor ? new Timestamp(cursor.seconds, cursor.nanoseconds) : null, cursorPath: cursor?.path ?? null,
      coldStartDone: state.sweep.coldStartDone },
    refresh: state.refresh, observedPolicyVersions: state.observedPolicyVersions, authPageFailedRuns: state.authPageFailedRuns,
    lastResetAtMillis: state.lastResetAtMillis, payload: JSON.stringify(compactPayload(state.payload)), report: JSON.stringify(state.report),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

/** The commit transaction's writes, path-addressed so the retry path can be exercised without Firestore. */
export interface CommitTx { get(path: string): Promise<Fields | undefined>; set(path: string, data: Fields): void }
export type RunCommit = <T>(body: (tx: CommitTx) => Promise<T>) => Promise<T>;
export type OkOutcome = Extract<FoldOutcome, { status: "ok" }>;

/**
 * Commit (1 read, 2 writes + the reports): abort without writing if another run took the lease or moved any
 * cursor while this one folded. The report documents ride the same transaction, so the lease, runId and
 * cursor-abort cover them — but isolated (§2.7): if the transaction throws with reports present it is retried
 * ONCE without them, committing the state whose report memory is restored to its pre-report values, so the
 * hourly digest never loses an hour to its own report and `lastReportedDay` stays unadvanced.
 */
export async function commitDigest(runCommit: RunCommit, outcome: OkOutcome, published: Fields, runId: string, encode: (state: DigestState) => Fields = encodeState,
  log: { error: (message: string, fields: Fields) => void } = logger): Promise<{ committed: boolean; reportsWritten: string[]; reportWriteFailed: string | null }> {
  const attempt = (withReports: boolean) => runCommit(async (tx) => {
    const data = (await tx.get(STATE_DOC)) ?? {};
    if (data.runId !== runId) return false;
    if (!cursorsEqual(startCursorsOf(decodeState(data)), outcome.startCursors)) return false;
    const state = withReports ? outcome.state : { ...outcome.state, report: outcome.reportStateBefore };
    tx.set(STATE_DOC, encode(state));
    tx.set(PUBLISHED_DOC, published);
    if (withReports) {
      for (const report of outcome.reports) tx.set(`${REPORT_DAYS}/${report.day}`, report.document);
      if (outcome.reportIndex) tx.set(REPORT_INDEX_DOC, outcome.reportIndex);
    }
    return true;
  });
  const hasReports = outcome.reports.length > 0;
  try {
    const committed = await attempt(hasReports);
    return { committed, reportsWritten: committed && hasReports ? outcome.reports.map((report) => report.day) : [], reportWriteFailed: null };
  } catch (error) {
    if (!hasReports) throw error;
    const message = (error as Error).message;
    log.error("algorithm digest report write failed; retrying the commit without reports", { runId, message, days: outcome.reports.map((report) => report.day) });
    const committed = await attempt(false);
    return { committed, reportsWritten: [], reportWriteFailed: message };
  }
}

/** The exact queries §3.2 names: the sweep on server createdAt with an exact
 *  Timestamp cursor, and the drill-down's own per-post ledger query
 *  (testActivity.ts:695) plus a cursor — no collection group, no partition. */
function firestoreReader(): DigestReader {
  return {
    async authPage() {
      const page = await admin.auth().listUsers(AUTH_PAGE_SIZE);
      const emailByUid: Record<string, string> = {};
      for (const user of page.users) emailByUid[user.uid] = user.email ?? "";
      return emailByUid;
    },
    async sweepPage({ after, fromMillis, toMillis, limit }) {
      let query = db.collection("posts").orderBy("createdAt").orderBy(FieldPath.documentId());
      if (fromMillis != null) query = query.where("createdAt", ">=", Timestamp.fromMillis(fromMillis));
      query = query.where("createdAt", "<=", Timestamp.fromMillis(toMillis));
      // Never startAfter on the first page: a never-swept registry has no tuple to start from.
      if (after) query = query.startAfter(new Timestamp(after.seconds, after.nanoseconds), db.doc(after.path));
      const snapshot = await query.limit(limit).get();
      const rows = [];
      for (const doc of snapshot.docs) {
        const createdAt = timestampTuple(doc.get("createdAt"));
        if (createdAt) rows.push({ id: doc.id, path: doc.ref.path, data: doc.data(), createdAt });
      }
      return rows;
    },
    async ledgerPage({ postId, after, horizonMillis, limit }) {
      let query = db.collection("posts").doc(postId).collection("radiusHistory")
        .orderBy("atMillis").orderBy(FieldPath.documentId()).where("atMillis", "<=", horizonMillis);
      // A bare id is what a COLLECTION-scope cursor takes; a never-paged post omits the clause.
      if (after) query = query.startAfter(after.atMillis, after.id);
      const snapshot = await query.limit(limit).get();
      return snapshot.docs.map((doc) => ({ id: doc.id, data: doc.data() }));
    },
    async createEntry(postId) {
      const snapshot = await db.doc(`posts/${postId}/radiusHistory/create`).get();
      return snapshot.exists ? { id: snapshot.id, data: snapshot.data() ?? {} } : null;
    },
    async engagement(postId, engagementId) {
      const snapshot = await db.doc(`posts/${postId}/engagements/${engagementId}`).get();
      return snapshot.exists ? snapshot.data() ?? {} : null;
    },
    async user(uid) {
      const snapshot = await db.collection("users").doc(uid).get();
      return snapshot.exists ? snapshot.data() ?? {} : null;
    },
    async post(postId) {
      const snapshot = await db.collection("posts").doc(postId).get();
      return snapshot.exists ? snapshot.data() ?? {} : null;
    },
  };
}

export async function runAlgorithmDigest(nowMillis = Date.now()) {
  const startedAt = Date.now();
  const runId = `${new Date(nowMillis).toISOString().slice(0, 16)}:${randomUUID().slice(0, 8)}`;
  const stateRef = db.doc(STATE_DOC);

  // 1. Lease (1 read, 1 write): the only write before the commit.
  const leased = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(stateRef);
    const data = snapshot.data();
    if (Number(data?.leaseUntilMillis) > nowMillis) return null;
    tx.set(stateRef, { leaseUntilMillis: nowMillis + LEASE_MS, runId }, { merge: true });
    return data ?? {};
  });
  if (!leased) { logger.info("algorithm digest leased elsewhere", { runId }); return { status: "leased" }; }
  const release = () => stateRef.set({ leaseUntilMillis: 0 }, { merge: true });

  try {
    const state = decodeState(leased);
    // 2. Config + switches (6 reads).
    const [configSnapshot, simulation, runner, daily, trial, mapConfig] = await db.getAll(
      db.doc(CONFIG_DOC), ...SWITCH_DOCS.map((path) => db.doc(path)),
    );
    const config = digestConfig(configSnapshot.data());
    if (!config.enabled) { await release(); return { status: "paused" }; }
    const switches = readSwitches({
      simulation: simulation.data() ?? null, runner: runner.data() ?? null, daily: daily.data() ?? null,
      trial: trial.data() ?? null, mapConfig: mapConfig.data() ?? null,
    }, nowMillis);

    // 3–8. Auth page, sweep, per-post pages, refresh, derive, render — in memory.
    const outcome = await runDigestFold({ state, config, switches, reader: firestoreReader(), runStartMillis: nowMillis, runId });
    if (outcome.status === "auth-failed") {
      // No fold, no cursor moves: an hour's staleness beats a wrong REAL number.
      await db.runTransaction(async (tx) => {
        tx.set(stateRef, { leaseUntilMillis: 0, authPageFailedRuns: FieldValue.increment(1) }, { merge: true });
        tx.set(db.doc(PUBLISHED_DOC), { coverage: { authPageFailedRuns: FieldValue.increment(1) } }, { merge: true });
      });
      logger.error("algorithm digest auth page failed; run aborted", { runId });
      return { status: "auth-failed" };
    }

    // 9. Commit (1 read, 2 writes): abort without writing if another run took
    // the lease or moved any cursor while this one folded.
    outcome.cost.runMs = Date.now() - startedAt;
    const published = { ...outcome.published, runMs: outcome.cost.runMs, cost: { ...(outcome.published.cost as Fields), runMs: outcome.cost.runMs } };
    const runCommit: RunCommit = (body) => db.runTransaction((tx) => body({
      get: async (path) => (await tx.get(db.doc(path))).data(),
      set: (path, data) => { tx.set(db.doc(path), data); },
    }));
    const { committed, reportsWritten, reportWriteFailed } = await commitDigest(runCommit, outcome, published, runId);
    if (!committed) {
      logger.warn("algorithm digest commit aborted: another run moved the cursors", { runId });
      return { status: "aborted" };
    }
    // 10. Every read counter in Cloud Logging, so the bill per run is there and not only on the desk — and the
    //     report's always-on operational signal (decision 21): reportsWritten / reportDeferredReason.
    logger.info("algorithm digest run", {
      runId, digestVersion: outcome.state.digestVersion, ...outcome.cost, ...outcome.runCoverage,
      payloadBytes: outcome.payloadBytes, publishedBytes: outcome.publishedBytes,
      reportsWritten, reportBytes: outcome.reportBytes, reportDeferredReason: outcome.reportDeferredReason,
      amendDeferredReason: outcome.amendDeferredReason, amendSkipped: outcome.amendSkipped, reportWriteFailed,
    });
    return { status: "complete", digestVersion: outcome.state.digestVersion, ...outcome.cost, reportsWritten, reportDeferredReason: outcome.reportDeferredReason };
  } catch (error) {
    await release().catch((releaseError) => logger.warn("algorithm digest lease release failed", { message: (releaseError as Error).message }));
    throw error;
  }
}
