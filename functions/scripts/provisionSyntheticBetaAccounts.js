#!/usr/bin/env node

// Provision the fixed beta-browser-v1 cohort: eight isolated Auth accounts
// (five people, three businesses) with UID === actorId, the runner allowlist,
// and — for the businesses only — the profile documents that make them
// businesses: users/{uid} with accountType "business" (the role every native
// client and the Meshy gate read) and a world-readable businesses/{uid}
// listing (the one profile-shaped document the rules let a peer read, and the
// spelling the rules and the Cloud Functions agree on). A person tester owns
// no profile document; the shell writes its first-run profile itself.
//
// Idempotent: existing accounts are updated in place, profile documents are
// merged, and the runner must be paused (testControl) before anything moves.

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
// Mirrors functions/src/syntheticBetaCohort.ts SYNTHETIC_BETA_PROFILES and the
// runner rosters in PoplurLandingPage-HTML/PoplurApp/scripts. The Auth
// displayName is what the RN shell stamps on a post as its username, so a
// business's displayName is its HANDLE (the byline reads "@nightmarket"); its
// trading name lives on the profile documents.
const ACTORS = Object.freeze([
  { actorId: "sim-food-001", email: "beta-sim-food-001@poplur.test", displayName: "Beta Runner · Food scout", kind: "person" },
  { actorId: "sim-sports-002", email: "beta-sim-sports-002@poplur.test", displayName: "Beta Runner · Live sports fan", kind: "person" },
  { actorId: "sim-music-003", email: "beta-sim-music-003@poplur.test", displayName: "Beta Runner · Music curator", kind: "person" },
  { actorId: "sim-tech-004", email: "beta-sim-tech-004@poplur.test", displayName: "Beta Runner · Performance tester", kind: "person" },
  { actorId: "sim-news-005", email: "beta-sim-news-005@poplur.test", displayName: "Beta Runner · News explorer", kind: "person" },
  {
    actorId: "sim-biz-food-006",
    email: "beta-sim-biz-food-006@poplur.test",
    displayName: "nightmarket",
    kind: "business",
    handle: "nightmarket",
    pinColor: "orange",
    business: {
      name: "Night Market Eats",
      category: "Restaurant",
      description: "Late-night street food stall. Synthetic beta tester — not a real business.",
      address: "Kensington Market, Toronto, ON",
      place: "Toronto",
      latitude: 43.6545,
      longitude: -79.4005,
    },
  },
  {
    actorId: "sim-biz-shop-007",
    email: "beta-sim-biz-shop-007@poplur.test",
    displayName: "hauls.to",
    kind: "business",
    handle: "hauls.to",
    pinColor: "purple",
    business: {
      name: "Hauls Outlet",
      category: "Retail",
      description: "Discount fashion and homeware outlet. Synthetic beta tester — not a real business.",
      address: "Eaton Centre, Toronto, ON",
      place: "Toronto",
      latitude: 43.6544,
      longitude: -79.3807,
    },
  },
  {
    actorId: "sim-biz-fashion-008",
    email: "beta-sim-biz-fashion-008@poplur.test",
    displayName: "fitcheck.nyc",
    kind: "business",
    handle: "fitcheck.nyc",
    pinColor: "blue",
    business: {
      name: "Fit Check Daily",
      category: "Boutique",
      description: "SoHo boutique posting daily fits. Synthetic beta tester — not a real business.",
      address: "SoHo, New York, NY",
      place: "New York",
      latitude: 40.7233,
      longitude: -74.003,
    },
  },
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

/** The iOS BusinessProfile.toDictionary() shape, so a native client that
 *  reads the nested profile finds every key it expects. */
function businessProfileDictionary(actor) {
  const business = actor.business;
  return {
    businessName: business.name,
    businessCategory: business.category,
    businessDescription: business.description,
    businessAddress: business.address,
    latitude: business.latitude,
    longitude: business.longitude,
    location: new admin.firestore.GeoPoint(business.latitude, business.longitude),
    contactEmail: actor.email,
    contactPhone: "",
    website: "",
    logoPhotoNotes: "",
    verificationStatus: "verified",
    verificationStatusLabel: "Verified",
    verificationMethods: [],
    verificationMethodLabels: [],
    proofSummary: "Provisioned synthetic beta business — not a real business.",
    requiresReverification: false,
    mapVisibility: true,
    markerType: "verified_business_profile",
  };
}

/** Writes the two documents that make a business tester a business. Merged,
 *  so a rerun refreshes without clobbering anything the app added since. */
async function writeBusinessProfiles(firestore) {
  const now = admin.firestore.FieldValue.serverTimestamp();
  let written = 0;
  for (const actor of ACTORS) {
    if (actor.kind !== "business") continue;
    const profile = businessProfileDictionary(actor);
    const cohortTags = {
      syntheticBeta: true,
      syntheticActorId: actor.actorId,
      cohortId: COHORT_ID,
      source: SOURCE,
      updatedAt: now,
    };
    const userRef = firestore.collection("users").doc(actor.actorId);
    const businessRef = firestore.collection("businesses").doc(actor.actorId);
    const [userSnapshot, businessSnapshot] = await Promise.all([userRef.get(), businessRef.get()]);
    await userRef.set({
      uid: actor.actorId,
      email: actor.email,
      username: actor.handle,
      usernameNormalized: actor.handle.toLowerCase(),
      displayName: actor.business.name,
      accountType: "business",
      isBusinessAccount: true,
      isVerifiedBusiness: true,
      businessName: actor.business.name,
      businessCategory: actor.business.category,
      businessAddress: actor.business.address,
      businessLocation: profile.location,
      businessProfile: profile,
      pinColor: actor.pinColor,
      ...cohortTags,
      ...(userSnapshot.exists ? {} : { createdAt: now }),
    }, { merge: true });
    await businessRef.set({
      ownerUserId: actor.actorId,
      ownerUserID: actor.actorId,
      email: actor.email,
      accountType: "business",
      handle: actor.handle,
      place: actor.business.place,
      ...profile,
      ...cohortTags,
      ...(businessSnapshot.exists ? {} : { submittedAt: now, createdAt: now }),
    }, { merge: true });
    written += 1;
  }
  return written;
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

  const businessCount = await writeBusinessProfiles(firestore);

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
  console.log(`Wrote ${businessCount} business profiles (users/{uid} + businesses/{uid}).`);
  console.log("Runner configuration remains paused. No password or token was printed.");
  if (createdCount > 0) console.log(`New credentials were written with mode 0600 to ${CREDENTIAL_PATH}.`);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error instanceof Error ? error.message : "Synthetic beta provisioning failed safely.");
    process.exit(1);
  });
