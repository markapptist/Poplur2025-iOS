import * as admin from "firebase-admin";
import { createHash } from "node:crypto";
import { HttpsError, onCall } from "firebase-functions/v2/https";

// A foreground lease, not analytics: no screen, location, device, or content.
// Clients renew once a minute. Crashes/disconnects expire after two minutes.
export const PRESENCE_LEASE_MS = 120_000;
export const PRESENCE_COLLECTION = "appPresenceSessions";

export function presenceInput(data: Record<string, unknown>): {
  session: string; sequence: number; active: boolean;
} {
  if (typeof data.session !== "string" || !/^[a-zA-Z0-9-]{16,80}$/.test(data.session)
    || !Number.isSafeInteger(data.sequence) || Number(data.sequence) < 1
    || typeof data.active !== "boolean") {
    throw new HttpsError("invalid-argument", "Invalid presence lease.");
  }
  return { session: data.session, sequence: Number(data.sequence), active: data.active };
}

/** BETA PHASE: there are no human testers yet, so the synthetic cohort is the
 *  audience the algorithm is being built against, and ONLINE NOW counts them
 *  (owner decision, 11 Sep 2026). Flip to `false` when humans arrive in the
 *  next testing phase and the number goes back to people only. The Test Center
 *  desk (testActivity.ts) has always counted actors apart and is unaffected. */
export const COUNT_SYNTHETIC_TESTERS = true;

export function countPresentPeople(
  rows: readonly { uid?: unknown; synthetic?: unknown; activeUntilMs?: unknown }[],
  now: number,
  countSynthetic = COUNT_SYNTHETIC_TESTERS,
): number {
  return new Set(rows.filter(row => typeof row.uid === "string" && row.uid.length > 0
    && (countSynthetic || row.synthetic !== true) && typeof row.activeUntilMs === "number"
    && row.activeUntilMs > now && row.activeUntilMs <= now + PRESENCE_LEASE_MS)
    .map(row => row.uid)).size;
}

/** Exported seam also used by the emulator test; identity comes from auth only. */
export async function updateAppPresence(
  db: admin.firestore.Firestore, uid: string, synthetic: boolean,
  data: Record<string, unknown>, now = Date.now(),
): Promise<{ peopleOnline: number; asOfMs: number; validForMs: number }> {
  const input = presenceInput(data);
  const key = createHash("sha256").update(`${uid}:${input.session}`).digest("hex");
  const ref = db.collection(PRESENCE_COLLECTION).doc(key);
  await db.runTransaction(async transaction => {
    const existing = await transaction.get(ref);
    // An old foreground request arriving after background must not revive it.
    if (Number(existing.data()?.sequence ?? 0) >= input.sequence) return;
    transaction.set(ref, {
      uid, synthetic, sequence: input.sequence,
      activeUntil: admin.firestore.Timestamp.fromMillis(input.active ? now + PRESENCE_LEASE_MS : now),
      // Retain the sequence briefly to reject delayed requests. TTL is cleanup
      // only; the query below expires leases even before Firestore removes them.
      expiresAt: admin.firestore.Timestamp.fromMillis(now + 24 * 60 * 60 * 1000),
    });
  });
  const asOfMs = Date.now();
  const snapshot = await db.collection(PRESENCE_COLLECTION)
    .where("activeUntil", ">", admin.firestore.Timestamp.fromMillis(asOfMs))
    .select("uid", "synthetic", "activeUntil").get();
  const peopleOnline = countPresentPeople(snapshot.docs.map(doc => ({
    uid: doc.data().uid, synthetic: doc.data().synthetic,
    activeUntilMs: doc.data().activeUntil?.toMillis?.(),
  })), asOfMs);
  // Never expose the private identities or individual online states.
  return { peopleOnline, asOfMs, validForMs: PRESENCE_LEASE_MS };
}

export const appPresence = onCall({ region: "us-central1", timeoutSeconds: 15 }, async request => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in to Poplur.");
  // Look for the DEFAULT app by name, never by `apps.length`. Verifying this
  // request's bearer token made firebase-functions create its own private app
  // ("__FIREBASE_FUNCTIONS_SDK__") when no default existed — so by the time
  // this line ran, `apps.length` was already 1, the guard skipped
  // initializeApp(), and admin.firestore() threw "default app does not
  // exist" on every authenticated call. index.ts normally initialises the
  // default first, but this function has shipped as an isolated stub without
  // it, which is exactly the case the count-based guard cannot survive.
  if (!admin.apps.some(app => app?.name === "[DEFAULT]")) admin.initializeApp();
  return updateAppPresence(admin.firestore(), request.auth.uid,
    request.auth.token.syntheticBeta === true, request.data ?? {});
});
