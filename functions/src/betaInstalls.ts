import * as admin from "firebase-admin";
import { Firestore } from "firebase-admin/firestore";
import { onDocumentCreated, onDocumentDeleted } from "firebase-functions/v2/firestore";
import { DEFAULT_WINDOW_START_MILLIS, SCORECARD_CONFIG_DOC } from "./betaScorecard";
import { actorClass } from "./syntheticIdentity";

/**
 * The live installs count the landing page shows (Mark, 10 Oct 2026: "I want
 * installs, not emails sent — this is for YC to see"). ONE world-readable
 * document, `public/betaInstalls`, rewritten the moment an account's
 * `users/{uid}` profile is created or deleted, so the number on poplur.ca
 * moves in real time and costs nothing while nothing happens — unlike the
 * scorecard, which runs on a (paused) 15-minute schedule.
 *
 * An install is a HUMAN Firebase Auth account — the desk's `real` class,
 * never owner, review or synthetic — created on or after the scorecard's
 * window start (testControl/betaScorecard.startAtMillis, else the default).
 * Counts and dates only; no uid or email leaves this function.
 */
export const INSTALLS_DOC = "public/betaInstalls";
export const INSTALLS_VERSION = 1;

export type BetaInstalls = { version: number; installs: number; startMillis: number; updatedAtMillis: number };

const millisOf = (value: unknown): number => {
  const n = Number(value);
  if (Number.isFinite(n) && n > 0) return n;
  const stamp = value as { toMillis?: () => number } | undefined;
  const ms = typeof stamp?.toMillis === "function" ? Number(stamp.toMillis()) : NaN;
  return Number.isFinite(ms) && ms > 0 ? ms : 0;
};

export async function countBetaInstalls(db: Firestore, nowMillis = Date.now()): Promise<BetaInstalls> {
  const config = (await db.doc(SCORECARD_CONFIG_DOC).get()).data() ?? {};
  const startMillis = millisOf(config.startAtMillis ?? config.startAt) || DEFAULT_WINDOW_START_MILLIS;
  const accounts: { uid: string; email: string; createdAtMillis: number }[] = [];
  let pageToken: string | undefined;
  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    for (const u of page.users) accounts.push({ uid: u.uid, email: u.email ?? "", createdAtMillis: Date.parse(u.metadata.creationTime ?? "") || 0 });
    pageToken = page.pageToken;
  } while (pageToken);
  const inWindow = accounts.filter(a => a.createdAtMillis >= startMillis);
  let installs = 0;
  for (let i = 0; i < inWindow.length; i += 100) {
    const part = inWindow.slice(i, i + 100);
    const snaps = await db.getAll(...part.map(a => db.collection("users").doc(a.uid)));
    snaps.forEach((s, j) => {
      const profile = s.data() ?? {};
      if (actorClass(part[j].uid, profile, part[j].email || (profile.email as string | undefined) || "", s.exists) === "real") installs += 1;
    });
  }
  return { version: INSTALLS_VERSION, installs, startMillis, updatedAtMillis: nowMillis };
}

export async function publishBetaInstalls(db: Firestore): Promise<BetaInstalls> {
  const count = await countBetaInstalls(db);
  await db.doc(INSTALLS_DOC).set(count, { merge: true });
  return count;
}

const trigger = { document: "users/{uid}", region: "us-central1", memory: "256MiB", cpu: "gcf_gen1", concurrency: 1, maxInstances: 2 } as const;
export const betaInstallsOnUserCreated = onDocumentCreated(trigger, async () => { await publishBetaInstalls(admin.firestore()); });
export const betaInstallsOnUserDeleted = onDocumentDeleted(trigger, async () => { await publishBetaInstalls(admin.firestore()); });
