"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CLAIM_RADIUS_RECEIPTS = exports.CLAIM_RADIUS_CONFIG_PATH = exports.LEGACY_DROP_CEILING_METERS = exports.POST_DISCOVERY_SEED_METERS = exports.ACCOUNT_CLAIM_RADIUS_FIELD = void 0;
exports.postEarnedRadiusMeters = postEarnedRadiusMeters;
exports.postOwnerUid = postOwnerUid;
exports.accountClaimRadiusSum = accountClaimRadiusSum;
exports.claimRadiusDeltaMeters = claimRadiusDeltaMeters;
exports.addAccountClaimRadius = addAccountClaimRadius;
exports.maxSeedRadiusMeters = maxSeedRadiusMeters;
const firestore_1 = require("firebase-admin/firestore");
const postEngagementPolicy_1 = require("./postEngagementPolicy");
/**
 * The account's earned total, kept on the account itself.
 *
 * Entitlement — the ground an account may claim on its next drop — is the sum
 * of `organicRadiusMeters` over everything it has published. Firestore rules
 * cannot sum a collection, so until 6 Sep 2026 the create rule could not check
 * a claim at all: its bound was the planet and only the client enforced the
 * entitlement, which a modified client simply skips. This field is that sum,
 * maintained by the server so a RULE can read it in one get().
 *
 * It is an aggregate, so it is only as honest as its maintenance: every writer
 * that moves a post's `organicRadiusMeters` adds the same delta here IN THE
 * SAME transaction or batch, and `scripts/backfillAccountClaimRadius.js`
 * recomputes it from the posts themselves. Never write it from a client: it is
 * on `users/{uid}`, which its owner may write, so it is listed among the
 * server-owned account fields in firestore.rules.
 */
exports.ACCOUNT_CLAIM_RADIUS_FIELD = "claimRadiusMeters";
/**
 * The discovery seed every drop is born with, on top of whatever it claims.
 * A post nobody can find is not a post, so a brand-new account with nothing
 * earned still publishes into 5 km. It is spent reach, never earned — it goes
 * to `seedRadiusMeters` and never to `organicRadiusMeters` — so publishing
 * cannot mint entitlement.
 */
exports.POST_DISCOVERY_SEED_METERS = 5_000;
/** The flat per-drop ceiling before 6 Sep 2026. Retired: the rule no longer
 *  has a migration fallback (config/claimRadius is backfilled). */
exports.LEGACY_DROP_CEILING_METERS = 25_000;
/** Marker the backfill flips when every account has an authoritative total.
 *  Read by firestore.rules; unreadable and unwritable by any client. */
exports.CLAIM_RADIUS_CONFIG_PATH = { collection: "config", document: "claimRadius" };
function finite(value) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
}
/**
 * What ONE post contributes to its owner's entitlement.
 *
 * Deliberately the same reading the web client already applies in
 * `poplur-clay-map/src/accountRadiusPosts.ts`: the declared earned pool when
 * the post has one, and otherwise its total minus the seed, so a post from
 * before seeds existed contributes exactly what it always did. If the two ever
 * disagree the picker and the rule disagree, and a legitimate claim is refused
 * on upload with nothing to explain it.
 */
function postEarnedRadiusMeters(post) {
    const declared = finite(post.organicRadiusMeters);
    if (declared !== null) {
        return Math.max(0, Math.min(postEngagementPolicy_1.MAX_POST_RADIUS_METERS, Math.round(declared)));
    }
    const parts = (0, postEngagementPolicy_1.postRadiusParts)(post, Date.now());
    return Math.max(0, Math.min(postEngagementPolicy_1.MAX_POST_RADIUS_METERS, Math.round(parts.organic)));
}
/** The owner uid a post document declares, in every spelling the rules and the
 *  engagement path already tolerate. */
function postOwnerUid(post) {
    const value = post.userID ?? post.userId ?? post.ownerId;
    return typeof value === "string" ? value.trim().slice(0, 128) : "";
}
/** The authoritative total for one owner, summed from their own posts. Used by
 *  the backfill and by the tests that check maintenance has not drifted. */
function accountClaimRadiusSum(posts) {
    let total = 0;
    for (const post of posts)
        total += postEarnedRadiusMeters(post);
    return Math.max(0, Math.round(total));
}
/**
 * The step this event moves the aggregate by: exactly the step it moves the
 * post's earned pool by, so the two can never diverge. Whole metres, because
 * a rule comparing a claim against a fraction of a metre reads as a mystery.
 */
function claimRadiusDeltaMeters(previousOrganicMeters, nextOrganicMeters) {
    const previous = finite(previousOrganicMeters) ?? 0;
    const next = finite(nextOrganicMeters) ?? 0;
    return Math.round(next) - Math.round(previous);
}
/**
 * Stage the aggregate step for `userRef` on `writer`.
 *
 * `FieldValue.increment` rather than a read-modify-write on purpose: the
 * account document then never joins the transaction's read set, so two people
 * engaging with two of the same owner's posts at the same instant do not
 * contend on one row. The cost is that the increment cannot clamp, so the
 * READERS clamp instead — the rule floors a negative or missing total at zero,
 * and the backfill is re-runnable to correct any drift.
 *
 * A merge write, so an account document that does not exist yet is created
 * rather than the whole engagement failing on a missing row.
 */
function addAccountClaimRadius(writer, userRef, deltaMeters) {
    if (!Number.isFinite(deltaMeters) || Math.round(deltaMeters) === 0)
        return false;
    writer.set(userRef, {
        [exports.ACCOUNT_CLAIM_RADIUS_FIELD]: firestore_1.FieldValue.increment(Math.round(deltaMeters)),
        claimRadiusUpdatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    return true;
}
/**
 * The ceiling the create rule enforces, expressed once here so the rule, the
 * tests and the client picker can be checked against one definition rather
 * than three readings of the same sentence.
 *
 * Earned once, spent once: a drop may seed the free discovery grant plus
 * whatever the account has earned (`earnedClaimMeters`, Σ organic over live
 * posts) that is not already sitting on another live pop
 * (`committedClaimMeters`, Σ seed − 5 km). Seeds never count toward what may
 * be claimed — from 7 to 17 Sep 2026 they did, via the full-radius sum, and
 * thirteen posts with no engagement reached the world radius.
 */
function maxSeedRadiusMeters(earnedClaimMeters, committedClaimMeters) {
    const earned = Math.max(0, finite(earnedClaimMeters) ?? 0);
    const committed = Math.max(0, finite(committedClaimMeters) ?? 0);
    return Math.min(postEngagementPolicy_1.MAX_POST_RADIUS_METERS, Math.max(0, earned - committed) + exports.POST_DISCOVERY_SEED_METERS);
}
/**
 * The receipt collection that makes a deleted post's decrement exactly-once.
 *
 * A deleted post's entitlement goes with it: every other writer moves the
 * aggregate by the same step it moves a post's earned pool, and deletion is a
 * step to zero like any other. Without it the aggregate keeps metres whose
 * posts are gone — and because radiusDecay only shrinks living posts, "earn a
 * kilometre, delete the post, keep the kilometre" would be the cheapest way to
 * hold entitlement that never decays.
 *
 * Cloud Functions may deliver the same delete twice, and a second decrement
 * would take back radius that was granted once. The receipt is created inside
 * the transaction, so the second delivery finds it and does nothing.
 */
exports.CLAIM_RADIUS_RECEIPTS = "accountRadiusDeletions";
