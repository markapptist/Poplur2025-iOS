"use strict";
/**
 * Student demo engagement policy — pure, no Firebase.
 *
 * The test build is for students who must understand Poplur the moment they
 * open it: when one of them posts, the synthetic cohort has to react right
 * away, wherever the pop is, and keep reacting at a steady rate — likes,
 * comments, a message — so radius grows, notifications land and the map
 * plays its growth moment. This module decides WHO reacts, WHEN and with WHAT
 * words; studentDemoResponder.ts carries it out through the same production
 * engagement transaction every real tap uses.
 *
 * Everything is deterministic from the post id, so a retried trigger, a
 * second instance or a replayed tick lands on the same plan and the same
 * idempotent engagement ids.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.DEMO_REPLY_DELAY_MS = exports.DEMO_REPLIES_PER_HOUR = exports.DEMO_DM_REPLIES = exports.DEMO_DM_OPENERS = exports.DEMO_COMMENTS = exports.STUDENT_DEMO_SOURCE = exports.STUDENT_DEMO_EVENT_PREFIX = exports.STUDENT_DEMO_DM_LEDGER = exports.STUDENT_DEMO_PLANS = exports.STUDENT_DEMO_CONFIG = void 0;
exports.parseStudentDemoConfig = parseStudentDemoConfig;
exports.demoHash = demoHash;
exports.pickActors = pickActors;
exports.demoComment = demoComment;
exports.demoOpener = demoOpener;
exports.demoReply = demoReply;
exports.buildDemoPlan = buildDemoPlan;
exports.nextDue = nextDue;
exports.demoEventId = demoEventId;
exports.demoMessageId = demoMessageId;
exports.canonicalThreadId = canonicalThreadId;
exports.demoEligiblePost = demoEligiblePost;
exports.STUDENT_DEMO_CONFIG = "testControl/studentDemo";
exports.STUDENT_DEMO_PLANS = "testDemoEngagementPlans";
exports.STUDENT_DEMO_DM_LEDGER = "testDemoDMLedger";
exports.STUDENT_DEMO_EVENT_PREFIX = "demo-";
exports.STUDENT_DEMO_SOURCE = "student-demo-responder";
const DEFAULTS = {
    enabled: false,
    firstBeatMs: 20_000,
    actorsPerPost: 6,
    dmEnabled: true,
    replyEnabled: true,
    inlineWindowMs: 95_000,
};
function num(value, fallback, min, max) {
    const n = typeof value === "number" ? value : Number(value);
    if (!Number.isFinite(n))
        return fallback;
    return Math.min(max, Math.max(min, n));
}
function parseStudentDemoConfig(raw) {
    const row = (raw && typeof raw === "object" ? raw : {});
    return {
        enabled: row.enabled === true,
        firstBeatMs: num(row.firstBeatMs, DEFAULTS.firstBeatMs, 5_000, 120_000),
        actorsPerPost: Math.round(num(row.actorsPerPost, DEFAULTS.actorsPerPost, 2, 12)),
        dmEnabled: row.dmEnabled !== false,
        replyEnabled: row.replyEnabled !== false,
        inlineWindowMs: num(row.inlineWindowMs, DEFAULTS.inlineWindowMs, 0, 400_000),
    };
}
/** FNV-1a: the same small hash the daily simulation uses, kept local so this
 *  module stays dependency-free. */
function demoHash(value) {
    let hash = 0x811c9dc5;
    for (let i = 0; i < value.length; i++) {
        hash ^= value.charCodeAt(i);
        hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    return hash >>> 0;
}
/** Deterministic pick without replacement: a stable shuffle of `pool` keyed
 *  by `seed`, first `count` entries. */
function pickActors(pool, seed, count) {
    const scored = pool.map((uid, i) => ({ uid, score: demoHash(`${seed}:${uid}:${i}`) }));
    scored.sort((a, b) => a.score - b.score || a.uid.localeCompare(b.uid));
    return scored.slice(0, Math.max(0, count)).map(s => s.uid);
}
/** Short, warm, and generic enough for any pop. None of them claims to know
 *  what is in the picture; the simulation never pretends to be a person, and
 *  the handle on the row already says it is a tester. */
exports.DEMO_COMMENTS = [
    "love this one",
    "ok this is a vibe",
    "just popped up on my map, nice",
    "this is going in my favourites",
    "saw this from across town, the radius is real",
    "more of this please",
    "the light in this is so good",
    "yep, liked and shared",
    "you're taking over the map today",
    "this made my feed better",
    "big pop energy",
    "new favourite creator, no notes",
    "wait where is this?",
    "came for the pin, stayed for the post",
    "this deserves way more reach",
    "watching your radius climb from here",
    "clean. very clean.",
    "the map needed this",
    "okay you win the neighbourhood",
    "post more like this and you own the block",
    "this is what the feed is for",
    "found you through the radius, staying",
    "instant like",
    "your pin just got bigger on my screen",
];
/** Openers a fake tester sends after the first likes have landed. */
exports.DEMO_DM_OPENERS = [
    "hey, your pop just showed up on my map. is that near you?",
    "saw your post in my feed, that spot looks great. what's the story?",
    "your pin is growing on my screen right now, nice work",
    "just liked your pop. are you posting more from around there?",
    "hi! new here too. your post is the first one that reached me",
];
/** Answers to whatever a student writes back. Never a question that needs
 *  a real answer, never a claim about the world. */
exports.DEMO_DM_REPLIES = [
    "ha, nice. keep posting, your radius is climbing",
    "love that. I'll keep an eye on your pin",
    "for sure. every post grows the circle a bit more",
    "same here. this app makes the map feel alive",
    "okay that's cool. post something from there next",
    "yes! that's the whole idea, reach grows with each pop",
    "good to know. I'm around, message any time",
];
function demoComment(seed) {
    return exports.DEMO_COMMENTS[demoHash(`c:${seed}`) % exports.DEMO_COMMENTS.length];
}
function demoOpener(seed) {
    return exports.DEMO_DM_OPENERS[demoHash(`o:${seed}`) % exports.DEMO_DM_OPENERS.length];
}
function demoReply(seed) {
    return exports.DEMO_DM_REPLIES[demoHash(`r:${seed}`) % exports.DEMO_DM_REPLIES.length];
}
/** The beats after a post, in seconds: quick first reactions so the student
 *  sees the radius move before they leave the screen, then a steady tail over
 *  the hour so the app keeps feeling alive. Each beat names a kind mix. */
const BEATS = [
    { afterSec: 0, kinds: ["view", "like"] },
    { afterSec: 25, kinds: ["view", "comment"] },
    { afterSec: 70, kinds: ["view", "like"] },
    { afterSec: 180, kinds: ["view"], dm: true },
    { afterSec: 300, kinds: ["view", "like", "comment"] },
    { afterSec: 720, kinds: ["view", "like"] },
    { afterSec: 1_500, kinds: ["view", "comment"] },
    { afterSec: 2_700, kinds: ["view", "like"] },
    { afterSec: 3_600, kinds: ["view", "like", "comment"] },
];
function buildDemoPlan(postId, ownerUid, actorPool, config, nowMillis) {
    const actors = pickActors(actorPool.filter(uid => uid !== ownerUid), postId, config.actorsPerPost);
    if (!actors.length)
        return null;
    const steps = BEATS.map((beat, index) => {
        const actorUid = actors[index % actors.length];
        const step = {
            index,
            dueAtMillis: nowMillis + config.firstBeatMs + beat.afterSec * 1_000,
            actorUid,
            kinds: [...beat.kinds],
            done: false,
        };
        if (beat.kinds.includes("comment"))
            step.comment = demoComment(`${postId}:${index}:${actorUid}`);
        if (beat.dm && config.dmEnabled)
            step.dm = demoOpener(`${postId}:${actorUid}`);
        return step;
    });
    return { postId, ownerUid, createdAtMillis: nowMillis, steps, nextDueAtMillis: steps[0].dueAtMillis, source: exports.STUDENT_DEMO_SOURCE };
}
function nextDue(steps) {
    let next = null;
    for (const step of steps)
        if (!step.done && (next === null || step.dueAtMillis < next))
            next = step.dueAtMillis;
    return next;
}
/** Idempotent engagement id: same post, step and kind → same id, so a retry
 *  returns the stored result instead of paying radius twice. */
function demoEventId(postId, index, kind) {
    return `${exports.STUDENT_DEMO_EVENT_PREFIX}${demoHash(postId).toString(16)}-${index}-${kind}`;
}
/** A client message id the DM rules accept (`msg-` + 16–96 [A-Za-z0-9-]). */
function demoMessageId(seed) {
    const a = demoHash(`m1:${seed}`).toString(16).padStart(8, "0");
    const b = demoHash(`m2:${seed}`).toString(16).padStart(8, "0");
    return `msg-demo-${a}-${b}`;
}
function canonicalThreadId(a, b) {
    return a < b ? `${a}_${b}` : `${b}_${a}`;
}
/** Same rule the client uses for a real tap: only a published, public,
 *  non-official post is something a fake tester would react to. */
function demoEligiblePost(post) {
    if (post.officialContent === true)
        return false;
    if (post.audience === "private")
        return false;
    if (post.status !== undefined && post.status !== "published")
        return false;
    if (post.processingStatus !== undefined && post.processingStatus !== "ready")
        return false;
    return true;
}
/** How many replies a thread may draw from the cohort per hour: enough for a
 *  conversation, never a loop with a student's auto-responder. */
exports.DEMO_REPLIES_PER_HOUR = 6;
/** The fake tester "reads" before answering. */
exports.DEMO_REPLY_DELAY_MS = 9_000;
