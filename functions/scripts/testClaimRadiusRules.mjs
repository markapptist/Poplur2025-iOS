/**
 * The create rule, against the real rules engine.
 *
 * Earned once, spent once: a drop may seed the 5 km discovery grant plus what
 * its account has EARNED (Σ organic over live posts) that is not already
 * COMMITTED on another live pop (Σ seed − 5 km) — and no more. Both sums are
 * maintained by accountTotalRadiusOnPostWritten (rules cannot sum a
 * collection), so these tests drive the boundary from the rules' side: at the
 * allowance, below it, above it, with claims out, and through the throttle.
 *
 *   firebase emulators:exec --only firestore \
 *     "node scripts/testClaimRadiusRules.mjs"
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import { doc, setDoc, deleteDoc } from "firebase/firestore";
import { publishWithAdmission } from './postAdmissionTestHelpers.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const SEED = 5_000;
const LEGACY = 25_000;
const WORLD = 6_371_000;
const MINUTE = 60_000;
const DAY = 86_400_000;

const testEnv = await initializeTestEnvironment({
  projectId: "poplur-claim-radius-rules",
  firestore: {
    rules: readFileSync(join(here, "..", "..", "firestore.rules"), "utf8"),
    host: "127.0.0.1",
    port: Number(process.env.FIRESTORE_EMULATOR_HOST?.split(":").pop() ?? 8080),
  },
});

const OWNER = "owner-uid";

/** A post exactly as PostUploadService.swift writes one: the whole creation
 *  radius declared as a seed, the earned pool at zero, origin hidden. */
function drop(radiusMeters, extra = {}, uid = OWNER) {
  return {
    userID: uid,
    mediaURL: "https://example.test/a.jpg",
    mediaType: "image",
    audience: "public",
    status: "published",
    locationVisibility: "hidden",
    radius: radiusMeters,
    radiusMeters,
    seedRadiusMeters: radiusMeters,
    organicRadiusMeters: 0,
    viewCount: 0,
    ...extra,
  };
}

/** Put the account where the rule will read it, written with rules off,
 *  exactly as the trigger writes it. `account` is spread verbatim so a test
 *  can plant the retired profile-sum field or a throttle state. */
async function given(account = {}, uid = OWNER) {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), "users", uid), { username: uid, ...account });
  });
  return testEnv.authenticatedContext(uid).firestore();
}

let created = 0;
const create = async (db, id, data) => {
  const uid = data.userID === 'somebody-else' ? OWNER : data.userID;
  // Each claim assertion starts at the given legacy rate state. Sequential
  // and concurrent slot transitions are covered by testAtomicPostAdmission.
  await testEnv.withSecurityRulesDisabled(ctx => deleteDoc(doc(ctx.firestore(), 'postAdmissions', uid)));
  return publishWithAdmission(db, uid, id, data);
};

// ── An account that has earned ground and has none of it out ─────────────
// 72.8 km earned is the real holding that motivated the 6 Sep change: the
// picker offered 25 km and the owner had nearly three times that.
{
  const db = await given({ earnedClaimMeters: 72_800, committedClaimMeters: 0 });

  await assertSucceeds(create(db, `p${created++}`, drop(72_800)));
  await assertSucceeds(create(db, `p${created++}`, drop(72_800 + SEED)),
    "the discovery seed sits on top of the earned total");
  await assertSucceeds(create(db, `p${created++}`, drop(SEED)),
    "claiming less than the entitlement is always fine");
  await assertSucceeds(create(db, `p${created++}`, drop(0)),
    "and claiming nothing at all is fine");

  await assertFails(create(db, `p${created++}`, drop(72_800 + SEED + 1)),
    "one metre past the entitlement is refused");
  await assertFails(create(db, `p${created++}`, drop(WORLD)),
    "a modified client cannot mint a post at world radius");
  await assertFails(create(db, `p${created++}`, drop(250_000)),
    "nor at ten times what it earned");

  // The invariants that were already there, still there.
  await assertFails(create(db, `p${created++}`, drop(10_000, { organicRadiusMeters: 10_000 })),
    "a post may not be born already holding earned radius");
  await assertFails(create(db, `p${created++}`, drop(10_000, { seedRadiusMeters: 20_000 })),
    "the seed may not exceed the radius it is a seed for");
  await assertFails(create(db, `p${created++}`, drop(10_000, { viewCount: 99 })),
    "counters start at zero");
  await assertFails(create(db, `p${created++}`, drop(10_000, { boostedRadiusMeters: 50_000 })),
    "a boost is bought, not declared");
  await assertFails(create(db, `p${created++}`, drop(10_000, { decayedAt: new Date() })),
    "the decay clock belongs to the server");
  await assertFails(create(db, `p${created++}`, { ...drop(10_000), userID: "somebody-else" }),
    "and a drop is still published as yourself");
}

// Projection policy belongs to the same authoritative decay service as radius.
{
  const db = await given({ earnedClaimMeters: 72_800 });
  await assertSucceeds(create(db, 'projection-existing', drop(5000)));
  for (const field of ['radiusDecayAnchorMillis', 'radiusDecayOrganicPerDay', 'radiusDecaySeedPerDay', 'radiusDecayBoostPerDay']) {
    await assertFails(create(db, `forged-${field}`, drop(5000, { [field]: 0.05 })));
    await assertFails(setDoc(doc(db, 'posts', 'projection-existing'), { [field]: 0.05 }, { merge: true }));
  }
}

// The ceiling, and not some other clause, is what refuses the claim above:
// the SAME document is accepted once the account has earned the ground.
{
  const over = drop(250_000);
  const poor = await given({ earnedClaimMeters: 72_800 });
  await assertFails(create(poor, "attribution", over));
  const rich = await given({ earnedClaimMeters: 250_000 });
  await assertSucceeds(create(rich, "attribution", over),
    "the only thing that changed is what the account had earned");
}

// ── Spent once: claims already out on live pops come off the allowance ───
{
  let db = await given({ earnedClaimMeters: 250_000, committedClaimMeters: 250_000 });
  await assertSucceeds(create(db, `p${created++}`, drop(SEED)),
    "with the whole holding out on a pop, the next drop is the seed");
  await assertFails(create(db, `p${created++}`, drop(SEED + 1)),
    "250 km earned is ONE 250 km claim at a time, not 250 km forever");

  db = await given({ earnedClaimMeters: 250_000, committedClaimMeters: 200_000 });
  await assertSucceeds(create(db, `p${created++}`, drop(50_000 + SEED)),
    "what is not out may still be claimed");
  await assertFails(create(db, `p${created++}`, drop(50_000 + SEED + 1)));

  db = await given({ earnedClaimMeters: 10_000, committedClaimMeters: 60_000 });
  await assertSucceeds(create(db, `p${created++}`, drop(SEED)),
    "earnings that decayed under an outstanding claim leave the seed, never a negative allowance");
  await assertFails(create(db, `p${created++}`, drop(SEED + 1)));
}

// ── The ladder is closed ─────────────────────────────────────────────────
// From 7 to 17 Sep 2026 the profile's full-radius sum was the ceiling, so
// thirteen unengaged posts reached the world radius. That field grants nothing.
{
  const db = await given({ totalPostRadiusMeters: 5_120_000, claimRadiusMeters: 5_120_000 });
  await assertSucceeds(create(db, `p${created++}`, drop(SEED)));
  await assertFails(create(db, `p${created++}`, drop(SEED + 1)),
    "neither the profile sum nor the legacy earned field is a claim");
  await assertFails(create(db, `p${created++}`, drop(5_120_000)),
    "the thirteenth tap is refused");
}

// ── An account that has earned nothing ───────────────────────────────────
{
  const db = await given({ earnedClaimMeters: 0 });
  await assertSucceeds(create(db, `p${created++}`, drop(SEED)),
    "a first post is still discoverable at 5 km");
  await assertFails(create(db, `p${created++}`, drop(SEED + 1)),
    "but nothing beyond the seed has been earned");
}

// An account with no aggregate field at all: absent means zero, and there is
// no migration fallback any more.
{
  const db = await given({});
  await assertSucceeds(create(db, `p${created++}`, drop(SEED)));
  await assertFails(create(db, `p${created++}`, drop(LEGACY)),
    "a new account does not inherit the retired flat ceiling");
}

// A drifted negative aggregate reads as zero rather than as a negative
// ceiling that would refuse even the discovery seed.
{
  const db = await given({ earnedClaimMeters: -50_000, committedClaimMeters: -1 });
  await assertSucceeds(create(db, `p${created++}`, drop(SEED)),
    "drift fails safe: the account can still publish, just not claim");
  await assertFails(create(db, `p${created++}`, drop(SEED + 1)));
}

// ── The throttle: one a minute, thirty a rolling day ─────────────────────
{
  const now = Date.now();
  let db = await given({ lastPostAtMillis: now - 10_000 });
  await assertFails(create(db, `p${created++}`, drop(SEED)),
    "ten seconds after the last post is too soon");
  db = await given({ lastPostAtMillis: now - 2 * MINUTE });
  await assertSucceeds(create(db, `p${created++}`, drop(SEED)),
    "two minutes after is fine");

  db = await given({ postWindowStartMillis: now - 3_600_000, postsInWindow: 30 });
  await assertFails(create(db, `p${created++}`, drop(SEED)),
    "the thirty-first post of the day is refused");
  db = await given({ postWindowStartMillis: now - 3_600_000, postsInWindow: 29 });
  await assertSucceeds(create(db, `p${created++}`, drop(SEED)),
    "the thirtieth is the last one allowed");
  db = await given({ postWindowStartMillis: now - DAY - 1, postsInWindow: 30 });
  await assertSucceeds(create(db, `p${created++}`, drop(SEED)),
    "a window older than a day has rolled over");

  const sim = "sim-actor-01";
  db = await given({ lastPostAtMillis: now, postWindowStartMillis: now, postsInWindow: 500 }, sim);
  await assertSucceeds(create(db, `p${created++}`, drop(SEED, {}, sim)),
    "the synthetic cohort posts at its own cadence");
  await assertFails(create(db, `p${created++}`, drop(SEED + 1, {}, sim)),
    "but claims like anybody else");
}

// ── The aggregates are the server's ──────────────────────────────────────
// They live on users/{uid}, a document its own owner may write. If the owner
// could write these fields the whole check would be decorative.
{
  const db = await given({ earnedClaimMeters: 1_000 });
  const me = doc(db, "users", OWNER);

  await assertSucceeds(setDoc(me, { username: "owner-renamed" }, { merge: true }),
    "an owner still edits their own account");
  for (const [field, value] of [
    ["earnedClaimMeters", WORLD], ["committedClaimMeters", 0], ["claimRadiusMeters", WORLD],
    ["totalPostRadiusMeters", WORLD], ["claimRadiusUpdatedAt", new Date()],
    ["lastPostAtMillis", 0], ["postWindowStartMillis", 0], ["postsInWindow", 0],
  ]) {
    await assertFails(setDoc(me, { [field]: value }, { merge: true }),
      `the owner cannot write ${field}`);
  }
  await assertFails(deleteDoc(me), "nor delete the document to shed the aggregates");
  await assertFails(setDoc(doc(db, "config", "claimRadius"), { backfilled: false }),
    "nothing may touch config/");
}

// A brand-new account creating its own document may not seed the aggregates.
{
  await testEnv.clearFirestore();
  const fresh = testEnv.authenticatedContext("fresh-uid").firestore();
  for (const field of ["earnedClaimMeters", "claimRadiusMeters", "postsInWindow"]) {
    await assertFails(
      setDoc(doc(fresh, "users", "fresh-uid"), { username: "fresh", [field]: 500_000 }),
      `an account cannot be born holding ${field}`,
    );
  }
  await assertSucceeds(setDoc(doc(fresh, "users", "fresh-uid"), { username: "fresh" }));
  await assertSucceeds(create(fresh, "first", drop(SEED, {}, "fresh-uid")),
    "and its first post is the seed");
}

await testEnv.cleanup();
console.log("claim radius rules: PASS");
