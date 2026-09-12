"use strict";
/**
 * Who is a person, and which pops are theirs — one predicate, one module.
 *
 * Pure on purpose: no imports, nothing from firebase-admin. The algorithm
 * digest (functions-digest) cannot import functions/src, so its build step
 * byte-copies this file and a test pins the copy to the source. Any dependency
 * added here breaks that copy, which is why the cohort table is not consulted:
 * every id in SYNTHETIC_BETA_PROFILES starts with `sim-`, and the uid-prefix
 * rule below already covers it (testSyntheticIdentity.js asserts that).
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.DESK_REVIEW_UIDS = exports.DESK_OWNER_UIDS = void 0;
exports.isSyntheticAccount = isSyntheticAccount;
exports.isSyntheticPost = isSyntheticPost;
exports.postClass = postClass;
exports.actorClass = actorClass;
/** The two retained production-test administrators (TEST_ADMIN_UIDS in
 *  testActivity.ts). Their taps on other people's posts are the owner
 *  rehearsing, never a tester's attention, so they never enter a REAL figure. */
exports.DESK_OWNER_UIDS = Object.freeze([
    "LiEG6SNtKEZN6eEGeybf0afZnHm1", // testcall@poplur.com
    "eoP2Z0ElxIa0Eua7xpFxNlr6tur1", // mark@apptist.ca
]);
/** The App Review demo account (@appreview). Its taps are Apple's reviewers
 *  or the owner rehearsing the review, never a tester's. Pinned like the owner
 *  set: a constant, not a knob. */
exports.DESK_REVIEW_UIDS = Object.freeze([
    "92eygyJsD3VEXzHXdBLch44AMRl1", // @appreview
]);
/** Every way a simulation account announces itself: the cohort actor ids
 *  (syntheticBetaCohort, all `sim-`), the sim-daily flags on users/{uid}
 *  (syntheticDailySimulation writes syntheticBeta + syntheticSource), the
 *  labelled accountType, and the poplur.test mailboxes every provisioner
 *  uses — `<uid>@poplur.test` for sim-daily accounts and
 *  `<name>@synthetic.poplur.test` for the permanent QA cohorts that exist in
 *  Auth only, with no users document to carry a flag. */
function isSyntheticAccount(uid, profile, email) {
    // Lab posters (synthetic-conquer-*) and sim-daily accounts carry it in the
    // uid itself; Auth uids are random, so a prefix cannot collide with a person.
    if (/^(synthetic-|sim-)/.test(uid))
        return true;
    if (profile?.syntheticBeta === true || profile?.syntheticCohort === true)
        return true;
    if (typeof profile?.syntheticSource === "string" && profile.syntheticSource)
        return true;
    if (typeof profile?.accountType === "string" && profile.accountType.toLowerCase().startsWith("synthetic"))
        return true;
    if (typeof email !== "string")
        return false;
    const mailbox = email.toLowerCase();
    return mailbox.endsWith("@poplur.test") || mailbox.endsWith(".poplur.test");
}
/** A post is synthetic when its writer stamped it so, or when its owner is. */
function isSyntheticPost(post, ownerSynthetic) {
    return ownerSynthetic
        || post.syntheticBeta === true
        || post.syntheticCohort === true
        || (typeof post.syntheticActorId === "string" && post.syntheticActorId !== "");
}
/**
 * Which population a pop belongs to. Order matters and mirrors the Test
 * Center report (.codex/test-center-report/gather.mjs): the 29 App Review
 * posts are owned by a @poplur.com mailbox and would read as real without the
 * officialContent rule; the Radius Lab pins carry syntheticBeta too, so the
 * lab id/source is tested before the synthetic rule or every lab pin becomes
 * cohort output.
 */
function postClass(postId, post, ownerSynthetic) {
    if (post.officialContent === true)
        return "official";
    if (postId.startsWith("post-radius-lab-")
        || (typeof post.syntheticSource === "string" && post.syntheticSource.startsWith("radius-lab")))
        return "lab";
    if (isSyntheticPost(post, ownerSynthetic)
        || typeof post.syntheticSource === "string"
        || post.source === "synthetic-browser"
        || postId.startsWith("post-sim-")
        || postId.startsWith("synthetic-"))
        return "synthetic";
    return "real";
}
/**
 * Whose attention an engagement was. `known` is the caller's answer to "does
 * this uid exist at all" (in the Auth page or as a users document): a uid
 * absent from both is `unknown`, never assumed to be a person. The email must
 * be the Auth email — the permanent QA cohorts have no users document, so
 * without it they would classify as real.
 */
function actorClass(uid, profile, email, known) {
    if (exports.DESK_OWNER_UIDS.includes(uid))
        return "owner";
    if (exports.DESK_REVIEW_UIDS.includes(uid))
        return "review";
    if (isSyntheticAccount(uid, profile, email))
        return "synthetic";
    if (known === false)
        return "unknown";
    return "real";
}
