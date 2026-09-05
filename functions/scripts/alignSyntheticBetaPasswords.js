#!/usr/bin/env node

/**
 * Align the eight fixed beta-browser-v1 accounts with the local credential file.
 *
 * provisionSyntheticBetaAccounts.js deliberately never touches an existing
 * account's password, so a cohort whose credential file has drifted can no
 * longer sign in: production Auth answers INVALID_LOGIN_CREDENTIALS for every
 * actor and the synthetic runner cannot start. resetSyntheticBetaCohort.js
 * would fix that by DELETING the identities and their data, which is far more
 * than the situation calls for and refuses to run at all while any synthetic
 * post is ambiguous.
 *
 * This sets the password of exactly those eight uids to the value already
 * stored in the mode-0600 credential file. Nothing is deleted, no other
 * account is read or written, and no password or token is printed.
 *
 *   node scripts/alignSyntheticBetaPasswords.js --confirm-align-synthetic-passwords
 *
 * Guards, all of which must hold per actor before a write:
 *   - the credential row's uid equals its actorId and is one of the eight
 *   - the credential row's email equals the pinned address for that actor
 *   - the live Auth account exists at that uid with that exact email
 *   - the account already carries the syntheticBeta custom claim
 *
 * It finishes by signing in as each actor exactly as the app does, and exits
 * non-zero unless all eight succeed.
 */

const admin = require("firebase-admin");
const { readFile } = require("node:fs/promises");
const { lstat } = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");

const CONFIRMATION_FLAG = "--confirm-align-synthetic-passwords";
const PROJECT_ID = "poplur2025";
// Public web API key, the same one the shipping web client sends.
const IDENTITY_TOOLKIT_KEY = "AIzaSyC_b3-zHngzP-MKa1Cx5yclbV_6DlvGe_w";
const CREDENTIAL_PATH = path.resolve(
  process.env.BETA_RUNNER_CREDENTIALS_PATH
    || process.env.POPLUR_SYNTHETIC_CREDENTIALS_FILE
    || path.join(os.homedir(), ".poplur", "synthetic-beta-credentials.json"),
);
const PINNED = Object.freeze({
  "sim-food-001": "beta-sim-food-001@poplur.test",
  "sim-sports-002": "beta-sim-sports-002@poplur.test",
  "sim-music-003": "beta-sim-music-003@poplur.test",
  "sim-tech-004": "beta-sim-tech-004@poplur.test",
  "sim-news-005": "beta-sim-news-005@poplur.test",
  "sim-biz-food-006": "beta-sim-biz-food-006@poplur.test",
  "sim-biz-shop-007": "beta-sim-biz-shop-007@poplur.test",
  "sim-biz-fashion-008": "beta-sim-biz-fashion-008@poplur.test",
});

function fail(message) {
  console.error(message);
  process.exit(1);
}

if (!process.argv.includes(CONFIRMATION_FLAG)) {
  fail(`Refusing to change any password without ${CONFIRMATION_FLAG}.`);
}

async function credentialRows() {
  const info = await lstat(CREDENTIAL_PATH).catch(() => null);
  if (!info || !info.isFile() || info.isSymbolicLink()) {
    throw new Error("Credential path must be an existing regular, non-symlink file.");
  }
  if ((info.mode & 0o777) !== 0o600) {
    throw new Error("Synthetic beta credentials must have mode 0600.");
  }
  const parsed = JSON.parse(await readFile(CREDENTIAL_PATH, "utf8"));
  const rows = Array.isArray(parsed?.actors) ? parsed.actors : [];
  if (rows.length !== Object.keys(PINNED).length) {
    throw new Error(`Credential file must hold exactly ${Object.keys(PINNED).length} actors.`);
  }
  return rows;
}

async function signInAs(email, password) {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${IDENTITY_TOOLKIT_KEY}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const body = await response.json().catch(() => ({}));
  return { ok: response.ok, status: response.status, uid: body.localId, message: body.error?.message };
}

async function main() {
  admin.initializeApp({ projectId: PROJECT_ID });
  const rows = await credentialRows();

  let aligned = 0;
  for (const row of rows) {
    const actorId = String(row?.actorId || "");
    const email = String(row?.email || "").toLowerCase();
    const password = typeof row?.password === "string" ? row.password : "";
    if (PINNED[actorId] !== email || row?.uid !== actorId || password.length < 20) {
      console.error(`${actorId || "(missing)"}: not a pinned cohort row; skipped.`);
      continue;
    }
    const user = await admin.auth().getUser(actorId).catch(() => null);
    if (!user) {
      console.log(`${actorId.padEnd(16)} no Auth account — run provisionSyntheticBetaAccounts.js first.`);
      continue;
    }
    if (String(user.email || "").toLowerCase() !== email) {
      console.error(`${actorId.padEnd(16)} Auth email does not match the pinned address; skipped.`);
      continue;
    }
    if (user.customClaims?.syntheticBeta !== true) {
      console.error(`${actorId.padEnd(16)} account is not marked syntheticBeta; skipped.`);
      continue;
    }
    await admin.auth().updateUser(actorId, { password });
    aligned += 1;
    console.log(`${actorId.padEnd(16)} password aligned with the local credential file.`);
  }

  console.log("--- sign-in verification ---");
  let signedIn = 0;
  for (const row of rows) {
    const result = await signInAs(row.email, row.password);
    if (result.ok && result.uid === row.actorId) signedIn += 1;
    console.log(`${String(row.actorId).padEnd(16)} ${result.status} ${result.ok ? `OK uid=${result.uid}` : (result.message ?? "failed")}`);
  }
  console.log(`aligned=${aligned} signedIn=${signedIn}/${rows.length}`);
  if (signedIn !== rows.length) throw new Error("Not every cohort account can sign in yet.");
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error instanceof Error ? error.message : "Synthetic password alignment failed safely.");
    process.exit(1);
  });
