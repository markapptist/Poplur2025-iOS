/**
 * The create rule, against the real rules engine.
 *
 * A drop may claim the ground its account has earned and no more. That check
 * only exists because the server keeps `users/{uid}.claimRadiusMeters` in step
 * with the posts (functions/src/accountRadius.ts) — rules cannot sum a
 * collection — so these tests drive the boundary from the rules' side: at the
 * aggregate, below it, above it, and through the migration window where an
 * account has no aggregate yet.
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

const here = dirname(fileURLToPath(import.meta.url));
const SEED = 5_000;
const LEGACY = 25_000;

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
function drop(radiusMeters, extra = {}) {
  return {
    userID: OWNER,
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

/** Put the account and the migration marker where the rule will read them.
 *  Written with rules off, exactly as the server writes them. */
async function given({ claimRadiusMeters, backfilled }) {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    await setDoc(doc(db, "users", OWNER), {
      username: "owner",
      ...(claimRadiusMeters === undefined ? {} : { claimRadiusMeters }),
    });
    if (backfilled !== undefined) {
      await setDoc(doc(db, "config", "claimRadius"), { backfilled });
    }
  });
  return testEnv.authenticatedContext(OWNER).firestore();
}

let created = 0;
const create = (db, id, data) => setDoc(doc(db, "posts", id), data);

// ── An account that has been summed ──────────────────────────────────────
// 72.8 km earned is the real holding that motivated the 6 Sep change: the
// picker offered 25 km and the owner had nearly three times that.
{
  const db = await given({ claimRadiusMeters: 72_800, backfilled: true });

  await assertSucceeds(create(db, `p${created++}`, drop(72_800)));
  await assertSucceeds(create(db, `p${created++}`, drop(72_800 + SEED)),
    "the discovery seed sits on top of the earned total");
  await assertSucceeds(create(db, `p${created++}`, drop(SEED)),
    "claiming less than the entitlement is always fine");
  await assertSucceeds(create(db, `p${created++}`, drop(0)),
    "and claiming nothing at all is fine");

  await assertFails(create(db, `p${created++}`, drop(72_800 + SEED + 1)),
    "one metre past the entitlement is refused");
  await assertFails(create(db, `p${created++}`, drop(6_371_000)),
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

// The ceiling, and not some other clause, is what refuses the claim above:
// the SAME document is accepted once the account has earned the ground.
{
  const over = drop(250_000);
  const poor = await given({ claimRadiusMeters: 72_800, backfilled: true });
  await assertFails(create(poor, "attribution", over));
  const rich = await given({ claimRadiusMeters: 250_000, backfilled: true });
  await assertSucceeds(create(rich, "attribution", over),
    "the only thing that changed is what the account had earned");
}

// ── An account that has earned nothing ───────────────────────────────────
{
  const db = await given({ claimRadiusMeters: 0, backfilled: true });
  await assertSucceeds(create(db, `p${created++}`, drop(SEED)),
    "a first post is still discoverable at 5 km");
  await assertFails(create(db, `p${created++}`, drop(SEED + 1)),
    "but nothing beyond the seed has been earned");
}

// An account with no aggregate field at all, once the backfill is marked
// complete: absent means zero, which is the honest answer for an account
// created after the migration.
{
  const db = await given({ backfilled: true });
  await assertSucceeds(create(db, `p${created++}`, drop(SEED)));
  await assertFails(create(db, `p${created++}`, drop(LEGACY)),
    "a new account does not inherit the retired flat ceiling");
}

// A drifted negative aggregate reads as zero rather than as a negative
// ceiling that would refuse even the discovery seed.
{
  const db = await given({ claimRadiusMeters: -50_000, backfilled: true });
  await assertSucceeds(create(db, `p${created++}`, drop(SEED)),
    "drift fails safe: the account can still publish, just not claim");
  await assertFails(create(db, `p${created++}`, drop(SEED + 1)));
}

// ── The migration window ─────────────────────────────────────────────────
// Rules deployed, backfill not finished. An existing account has no total
// yet and must keep the ceiling it had yesterday.
{
  const db = await given({});
  await assertSucceeds(create(db, `p${created++}`, drop(LEGACY + SEED)),
    "mid-backfill an unsummed account keeps the pre-6-Sep 25 km drop ceiling");
  await assertFails(create(db, `p${created++}`, drop(LEGACY + SEED + 1)),
    "the fallback is bounded — it is not the planet");
}

// Mid-backfill, an account the engagement path has already incremented past
// the fallback: the larger of the two wins, so nobody is demoted by the
// order the migration happens to reach them in.
{
  const db = await given({ claimRadiusMeters: 100_000 });
  await assertSucceeds(create(db, `p${created++}`, drop(100_000 + SEED)));
  await assertFails(create(db, `p${created++}`, drop(100_000 + SEED + 1)));
}

// And an account whose partial total is BELOW the fallback is not locked
// down before the sum is authoritative.
{
  const db = await given({ claimRadiusMeters: 1_000 });
  await assertSucceeds(create(db, `p${created++}`, drop(LEGACY + SEED)),
    "a partial increment must not lock an account below what it had yesterday");
}

// ── The aggregate is the server's ────────────────────────────────────────
// It lives on users/{uid}, a document its own owner may write. If the owner
// could write this field the whole check would be decorative.
{
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), "users", OWNER), {
      username: "owner", claimRadiusMeters: 1_000,
    });
    await setDoc(doc(context.firestore(), "config", "claimRadius"), { backfilled: true });
  });
  const db = testEnv.authenticatedContext(OWNER).firestore();
  const me = doc(db, "users", OWNER);

  await assertSucceeds(setDoc(me, { username: "owner-renamed" }, { merge: true }),
    "an owner still edits their own account");
  await assertFails(setDoc(me, { claimRadiusMeters: 6_371_000 }, { merge: true }),
    "but cannot write itself the entitlement");
  await assertFails(setDoc(me, { claimRadiusUpdatedAt: new Date() }, { merge: true }),
    "nor the clock that says when it last moved");
  await assertFails(deleteDoc(me), "nor delete the document to shed the aggregate");

  // Nothing may read config/claimRadius either — a rule's own get() is not
  // subject to rules, so the marker stays invisible to every client.
  await assertFails(setDoc(doc(db, "config", "claimRadius"), { backfilled: false }));
}

// A brand-new account creating its own document may not seed the aggregate.
{
  await testEnv.clearFirestore();
  const fresh = testEnv.authenticatedContext("fresh-uid").firestore();
  await assertFails(
    setDoc(doc(fresh, "users", "fresh-uid"), { username: "fresh", claimRadiusMeters: 500_000 }),
    "an account cannot be born holding entitlement",
  );
  await assertSucceeds(setDoc(doc(fresh, "users", "fresh-uid"), { username: "fresh" }));
}

await testEnv.cleanup();
console.log("claim radius rules: PASS");
