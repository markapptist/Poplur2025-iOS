#!/usr/bin/env node

const admin = require("firebase-admin");
const { randomBytes } = require("node:crypto");
const { chmod, lstat, mkdir, readFile, rename, writeFile } = require("node:fs/promises");
const os = require("node:os");
const path = require("node:path");

const CONFIRMATION_FLAG = "--confirm-provision-synthetic-beta";
const PROJECT_ID = "poplur2025";
const COHORT_ID = "beta-browser-v1";
const SOURCE = "synthetic-browser";
const PROJECT_ROOT = path.resolve(__dirname, "../..");
const CREDENTIAL_PATH = path.resolve(
  process.env.BETA_RUNNER_CREDENTIALS_PATH
    || process.env.POPLUR_SYNTHETIC_CREDENTIALS_FILE
    || path.join(os.homedir(), ".poplur", "synthetic-beta-credentials.json"),
);
const ACTORS = Object.freeze([
  { actorId: "sim-food-001", email: "beta-sim-food-001@poplur.test", displayName: "Beta Runner · Food scout" },
  { actorId: "sim-sports-002", email: "beta-sim-sports-002@poplur.test", displayName: "Beta Runner · Live sports fan" },
  { actorId: "sim-music-003", email: "beta-sim-music-003@poplur.test", displayName: "Beta Runner · Music curator" },
  { actorId: "sim-tech-004", email: "beta-sim-tech-004@poplur.test", displayName: "Beta Runner · Performance tester" },
  { actorId: "sim-news-005", email: "beta-sim-news-005@poplur.test", displayName: "Beta Runner · News explorer" },
]);

function fail(message) {
  console.error(message);
  process.exit(1);
}

if (!process.argv.includes(CONFIRMATION_FLAG)) {
  fail(`Refusing to provision without ${CONFIRMATION_FLAG}.`);
}

const credentialRelative = path.relative(PROJECT_ROOT, CREDENTIAL_PATH);
if (!credentialRelative.startsWith("..") || path.isAbsolute(credentialRelative)) {
  fail("BETA_RUNNER_CREDENTIALS_PATH must resolve outside the Poplur2025-iOS repository.");
}

admin.initializeApp({ projectId: PROJECT_ID });

async function credentialDocument() {
  try {
    const info = await lstat(CREDENTIAL_PATH);
    if (!info.isFile() || info.isSymbolicLink()) {
      throw new Error("Credential path must be a regular, non-symlink file.");
    }
    if ((info.mode & 0o777) !== 0o600) {
      throw new Error("Existing synthetic beta credentials must have mode 0600.");
    }
    const parsed = JSON.parse(await readFile(CREDENTIAL_PATH, "utf8"));
    const actors = Array.isArray(parsed?.actors) ? parsed.actors : [];
    const seen = new Set();
    for (const row of actors) {
      const actor = ACTORS.find(candidate => candidate.actorId === row?.actorId);
      if (!actor || seen.has(actor.actorId)
        || row.uid !== actor.actorId
        || String(row.email || "").toLowerCase() !== actor.email
        || typeof row.password !== "string"
        || row.password.length < 20) {
        throw new Error("Existing synthetic beta credentials do not match the fixed cohort.");
      }
      seen.add(actor.actorId);
    }
    return { version: 1, actors };
  } catch (error) {
    if (error?.code === "ENOENT") return { version: 1, actors: [] };
    throw error;
  }
}

async function persistCredential(actor, password) {
  const document = await credentialDocument();
  const existing = document.actors.find(row => row?.actorId === actor.actorId);
  if (existing) {
    if (existing.uid !== actor.actorId || String(existing.email || "").toLowerCase() !== actor.email) {
      throw new Error(`Credential file has conflicting metadata for ${actor.actorId}.`);
    }
    return;
  }
  document.actors.push({
    actorId: actor.actorId,
    uid: actor.actorId,
    email: actor.email,
    password,
  });
  document.actors.sort((left, right) => ACTORS.findIndex(actorRow => actorRow.actorId === left.actorId)
    - ACTORS.findIndex(actorRow => actorRow.actorId === right.actorId));
  await mkdir(path.dirname(CREDENTIAL_PATH), { recursive: true, mode: 0o700 });
  const temporaryPath = `${CREDENTIAL_PATH}.${process.pid}.${randomBytes(8).toString("hex")}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(document, null, 2)}\n`, { mode: 0o600, flag: "wx" });
  await chmod(temporaryPath, 0o600);
  await rename(temporaryPath, CREDENTIAL_PATH);
  await chmod(CREDENTIAL_PATH, 0o600);
}

async function authUser(actor) {
  let user;
  let created = false;
  try {
    user = await admin.auth().getUser(actor.actorId);
    user = await admin.auth().updateUser(actor.actorId, {
      email: actor.email,
      emailVerified: true,
      displayName: actor.displayName,
      disabled: false,
    });
  } catch (error) {
    if (error?.code !== "auth/user-not-found") throw error;
    const password = randomBytes(32).toString("base64url");
    user = await admin.auth().createUser({
      uid: actor.actorId,
      email: actor.email,
      emailVerified: true,
      displayName: actor.displayName,
      disabled: false,
      password,
    });
    await persistCredential(actor, password);
    created = true;
  }
  await admin.auth().setCustomUserClaims(user.uid, {
    ...(user.customClaims || {}),
    syntheticBeta: true,
    syntheticActorId: actor.actorId,
  });
  return created;
}

async function main() {
  const firestore = admin.firestore();
  const configRef = firestore.collection("testControl").doc("syntheticBrowserRunner");
  const initialConfig = await configRef.get();
  if (initialConfig.data()?.enabled === true) {
    throw new Error("Pause the synthetic browser runner before provisioning accounts.");
  }

  const existingCredentials = await credentialDocument();
  const existingUsers = await Promise.all(ACTORS.map(async actor => {
    try {
      return await admin.auth().getUser(actor.actorId);
    } catch (error) {
      if (error?.code === "auth/user-not-found") return null;
      throw error;
    }
  }));
  existingUsers.forEach((user, index) => {
    if (user && !existingCredentials.actors.some(row => row.actorId === ACTORS[index].actorId)) {
      throw new Error(`Credential file is missing the existing ${ACTORS[index].actorId} account; no accounts were changed.`);
    }
  });

  let createdCount = 0;
  for (const actor of ACTORS) {
    if (await authUser(actor)) createdCount += 1;
  }

  await firestore.runTransaction(async transaction => {
    const config = await transaction.get(configRef);
    if (config.data()?.enabled === true) {
      throw new Error("Runner became enabled during provisioning; no allowlist change was made.");
    }
    for (const actor of ACTORS) {
      transaction.set(firestore.collection("testSyntheticRunnerActors").doc(actor.actorId), {
        actorId: actor.actorId,
        uid: actor.actorId,
        active: true,
        source: SOURCE,
        cohortId: COHORT_ID,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedBy: "provisionSyntheticBetaAccounts",
      });
    }
    transaction.set(configRef, {
      ...(config.exists ? {} : { enabled: false, generation: 0 }),
      cohortId: COHORT_ID,
      actors: ACTORS.map(actor => ({ actorId: actor.actorId, active: true })),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: "provisionSyntheticBetaAccounts",
    }, { merge: true });
  });

  console.log(`Provisioned ${ACTORS.length} isolated beta runner accounts; ${createdCount} were newly created.`);
  console.log("Runner configuration remains paused. No password or token was printed.");
  if (createdCount > 0) console.log(`New credentials were written with mode 0600 to ${CREDENTIAL_PATH}.`);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error instanceof Error ? error.message : "Synthetic beta provisioning failed safely.");
    process.exit(1);
  });
