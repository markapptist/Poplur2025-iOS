"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.betaScorecard = exports.THRESHOLDS = exports.RETENTION_DAYS = exports.REPOST_WINDOW_MS = exports.ACTIVATION_WINDOW_MS = exports.DEFAULT_WINDOW_START_MILLIS = exports.SCORECARD_TIME_ZONE = exports.SCORECARD_VERSION = exports.SCORECARD_CONFIG_DOC = exports.SCORECARD_DOC = void 0;
exports.dayKey = dayKey;
exports.dayKeyOffset = dayKeyOffset;
exports.foldScorecard = foldScorecard;
exports.computeBetaScorecard = computeBetaScorecard;
exports.publishBetaScorecard = publishBetaScorecard;
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const syntheticIdentity_1 = require("./syntheticIdentity");
const accountRadius_1 = require("./accountRadius");
/**
 * The beta scorecard — what "validated" means for the student beta, computed
 * on a schedule and published to ONE world-readable document so the landing
 * page and the Test Center show the same numbers (runbook § Beta scorecard).
 *
 * Humans only: the desk's `real` class (never owner, review or synthetic).
 * Counts with their denominators, never a bare percentage; a signal with no
 * denominator yet is `pending`, not zero. Nothing personal leaves this
 * function — no uids, no emails, no coordinates — only counts and dates.
 */
exports.SCORECARD_DOC = "public/betaScorecard";
exports.SCORECARD_CONFIG_DOC = "testControl/betaScorecard";
exports.SCORECARD_VERSION = 1;
exports.SCORECARD_TIME_ZONE = "America/Toronto";
/** Until Mark sets the invite day in the config doc, the window opens the
 *  day the fixed build shipped. */
exports.DEFAULT_WINDOW_START_MILLIS = Date.UTC(2026, 8, 16, 4, 0, 0);
exports.ACTIVATION_WINDOW_MS = 24 * 3_600_000;
exports.REPOST_WINDOW_MS = 72 * 3_600_000;
exports.RETENTION_DAYS = [7, 14];
exports.THRESHOLDS = Object.freeze({
    activation: { good: 0.6, weak: 0.3 },
    d7: { good: 0.3, weak: 0.15 },
    d14: { good: 0.2, weak: 0.1 },
    repostRatio: { good: 1.5, weak: 1.0 },
    interception: { good: 0.7, weak: 0.4 },
    offPrompt: { good: 0.4, weak: 0.15 },
});
const dayFormat = new Intl.DateTimeFormat("en-CA", {
    timeZone: exports.SCORECARD_TIME_ZONE, year: "numeric", month: "2-digit", day: "2-digit",
});
/** "YYYY-MM-DD" in Toronto. */
function dayKey(ms) { return dayFormat.format(new Date(ms)); }
/** Calendar arithmetic on the label — labels are calendar days, so UTC is exact. */
function dayKeyOffset(key, days) {
    const [y, m, d] = key.split("-").map(Number);
    return new Date(Date.UTC(y, m - 1, d + days)).toISOString().slice(0, 10);
}
function verdictFor(share, t, higherIsBetter = true) {
    if (share === null)
        return "pending";
    if (higherIsBetter)
        return share >= t.good ? "good" : share < t.weak ? "weak" : "mid";
    return share <= t.good ? "good" : share > t.weak ? "weak" : "mid";
}
function signal(key, label, count, of, t, note) {
    const share = of > 0 ? count / of : null;
    return { key, label, count, of, share, verdict: verdictFor(share, t), note };
}
/** Pure: the scorecard from already-classified rows. */
function foldScorecard(input) {
    const { nowMillis, startMillis, endMillis } = input;
    const windowEnd = endMillis ?? nowMillis;
    const humans = input.humans.filter(h => h.createdAtMillis >= startMillis && h.createdAtMillis <= windowEnd);
    const humanUids = new Set(humans.map(h => h.uid));
    const humanPops = input.posts.filter(p => p.human && humanUids.has(p.uid) && p.createdAtMillis >= startMillis);
    const popsByUid = new Map();
    for (const p of humanPops)
        popsByUid.set(p.uid, [...(popsByUid.get(p.uid) ?? []), p]);
    for (const list of popsByUid.values())
        list.sort((a, b) => a.createdAtMillis - b.createdAtMillis);
    // Activity days: a pop created, or an engagement made, on a Toronto day.
    const activeDays = new Map();
    const touch = (uid, ms) => {
        if (!humanUids.has(uid))
            return;
        const days = activeDays.get(uid) ?? new Set();
        days.add(dayKey(ms));
        activeDays.set(uid, days);
    };
    for (const p of humanPops)
        touch(p.uid, p.createdAtMillis);
    const humanEngagements = input.engagements.filter(e => e.actorHuman && humanUids.has(e.actorUid) && e.createdAtMillis >= startMillis);
    for (const e of humanEngagements)
        touch(e.actorUid, e.createdAtMillis);
    // 1. Activation — a pop within 24 h of the account.
    const activated = humans.filter(h => (popsByUid.get(h.uid) ?? []).some(p => p.createdAtMillis - h.createdAtMillis <= exports.ACTIVATION_WINDOW_MS)).length;
    // 2. Retention — active on Toronto day N after sign-up; eligible once that day has ended.
    const today = dayKey(nowMillis);
    const retention = exports.RETENTION_DAYS.map(n => {
        const eligible = humans.filter(h => dayKeyOffset(dayKey(h.createdAtMillis), n) < today);
        const retained = eligible.filter(h => activeDays.get(h.uid)?.has(dayKeyOffset(dayKey(h.createdAtMillis), n))).length;
        return { n, retained, eligible: eligible.length };
    });
    // 3. The loop — engaged pops grew; did their owners post again within 72 h?
    const firstHumanTouch = new Map();
    for (const e of input.engagements) {
        if (!e.actorHuman || e.actorUid === e.postOwnerUid)
            continue;
        const at = firstHumanTouch.get(e.postId);
        if (at === undefined || e.createdAtMillis < at)
            firstHumanTouch.set(e.postId, e.createdAtMillis);
    }
    const engagedPops = humanPops.filter(p => firstHumanTouch.has(p.id));
    const grewPops = engagedPops.filter(p => p.organicMeters > 0 || p.radiusMeters > p.seedMeters);
    const repostRate = (people, anchorFor) => {
        let eligible = 0;
        let reposted = 0;
        for (const uid of people) {
            const anchor = anchorFor(uid);
            if (anchor === null || nowMillis - anchor < exports.REPOST_WINDOW_MS)
                continue;
            eligible += 1;
            if ((popsByUid.get(uid) ?? []).some(p => p.createdAtMillis > anchor && p.createdAtMillis - anchor <= exports.REPOST_WINDOW_MS))
                reposted += 1;
        }
        return eligible > 0 ? reposted / eligible : null;
    };
    const grewOwners = [...new Set(grewPops.map(p => p.uid))];
    const notGrewOwners = humans.map(h => h.uid).filter(uid => (popsByUid.get(uid) ?? []).length > 0 && !grewOwners.includes(uid));
    const repostRateGrew = repostRate(grewOwners, uid => {
        const touches = grewPops.filter(p => p.uid === uid).map(p => firstHumanTouch.get(p.id) ?? Infinity);
        return touches.length ? Math.min(...touches) : null;
    });
    const repostRateNotGrew = repostRate(notGrewOwners, uid => popsByUid.get(uid)?.[0]?.createdAtMillis ?? null);
    const ratio = repostRateGrew !== null && repostRateNotGrew !== null && repostRateNotGrew > 0 ? repostRateGrew / repostRateNotGrew : null;
    // 4. Discovery — how humans reached the pops they engaged (not their own).
    const discovery = { interception: 0, profile: 0, other: 0 };
    for (const e of humanEngagements) {
        if (e.actorUid === e.postOwnerUid)
            continue;
        if (e.surface === "feed" || e.surface === "map")
            discovery.interception += 1;
        else if (e.surface === "profile")
            discovery.profile += 1;
        else
            discovery.other += 1;
    }
    // 5. Organic pull — referrals (config) and pops on days with no prompt.
    const promptDays = new Set(input.promptDays);
    const offPromptPops = humanPops.filter(p => !promptDays.has(dayKey(p.createdAtMillis))).length;
    // Integrity — no live pop seeded above its owner's current allowance, no ladder.
    let overClaimedPops = 0;
    let ladderPops = 0;
    for (const p of input.posts) {
        if (!p.live)
            continue;
        const earned = input.earnedByUid.get(p.uid) ?? 0;
        if (p.seedMeters > accountRadius_1.POST_DISCOVERY_SEED_METERS + earned)
            overClaimedPops += 1;
        if (p.seedMeters > accountRadius_1.POST_DISCOVERY_SEED_METERS && earned === 0)
            ladderPops += 1;
    }
    const last7 = nowMillis - 7 * 86_400_000;
    const activeLast7d = humans.filter(h => [...(activeDays.get(h.uid) ?? [])].some(day => day >= dayKey(last7))).length;
    const d7 = retention[0];
    const d14 = retention[1];
    return {
        version: exports.SCORECARD_VERSION,
        updatedAtMillis: nowMillis,
        window: { startMillis, endMillis, days: Math.max(0, Math.floor((windowEnd - startMillis) / 86_400_000)) },
        installs: humans.length,
        signals: [
            signal("activation", "Posted within 24 h", activated, humans.length, exports.THRESHOLDS.activation, "a pop within a day of the account"),
            signal("d7", "Active on day 7", d7.retained, d7.eligible, exports.THRESHOLDS.d7, "of accounts whose day 7 has passed"),
            signal("d14", "Active on day 14", d14.retained, d14.eligible, exports.THRESHOLDS.d14, "of accounts whose day 14 has passed"),
            signal("loop", "Engaged pops that grew", grewPops.length, engagedPops.length, { good: 0.9, weak: 0.5 }, "reach rose after a classmate's like"),
            signal("discovery", "Found by radius", discovery.interception, discovery.interception + discovery.profile, exports.THRESHOLDS.interception, "feed or map, not a profile visit"),
            signal("offPrompt", "Pops on days with no prompt", offPromptPops, humanPops.length, exports.THRESHOLDS.offPrompt, "posted without being asked"),
        ],
        loop: { engagedPops: engagedPops.length, grewPops: grewPops.length, repostRateGrew, repostRateNotGrew, ratio },
        discovery,
        organic: { referralInstalls: input.referralInstalls, offPromptPops, humanPops: humanPops.length, promptDays: promptDays.size },
        activity: { activeLast7d, humanPops: humanPops.length, humanEngagements: humanEngagements.length },
        integrity: { overClaimedPops, ladderPops, replacedPops: input.replacedPops },
        timeZone: exports.SCORECARD_TIME_ZONE,
    };
}
// ── Firestore + Auth reads ─────────────────────────────────────────────────
function finite(value) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
}
function millisOf(value) {
    const declared = finite(value);
    if (declared !== null && declared > 0)
        return declared;
    const stamp = value;
    const ms = typeof stamp?.toMillis === "function" ? Number(stamp.toMillis()) : NaN;
    return Number.isFinite(ms) && ms > 0 ? ms : 0;
}
function chunk(items, size) {
    const out = [];
    for (let i = 0; i < items.length; i += size)
        out.push(items.slice(i, i + size));
    return out;
}
async function computeBetaScorecard(db, nowMillis = Date.now()) {
    const config = (await db.doc(exports.SCORECARD_CONFIG_DOC).get()).data() ?? {};
    const startMillis = millisOf(config.startAtMillis ?? config.startAt) || exports.DEFAULT_WINDOW_START_MILLIS;
    const endMillis = millisOf(config.endAtMillis ?? config.endAt) || null;
    const promptDays = Array.isArray(config.promptDays) ? config.promptDays.filter((d) => typeof d === "string") : [];
    const referralInstalls = Math.max(0, Math.round(finite(config.referralInstalls) ?? 0));
    // Every account, classified the desk's way.
    const accounts = [];
    let pageToken;
    do {
        const page = await admin.auth().listUsers(1000, pageToken);
        for (const u of page.users)
            accounts.push({ uid: u.uid, email: u.email ?? "", createdAtMillis: Date.parse(u.metadata.creationTime ?? "") || 0 });
        pageToken = page.pageToken;
    } while (pageToken);
    const profiles = new Map();
    for (const part of chunk(accounts, 100)) {
        const snaps = await db.getAll(...part.map(a => db.collection("users").doc(a.uid)));
        for (const s of snaps)
            profiles.set(s.id, s.data() ?? {});
    }
    const classOf = (uid, email = "") => (0, syntheticIdentity_1.actorClass)(uid, profiles.get(uid) ?? {}, email || profiles.get(uid)?.email || "", profiles.has(uid));
    const humans = accounts
        .filter(a => classOf(a.uid, a.email) === "real")
        .map(a => ({ uid: a.uid, createdAtMillis: a.createdAtMillis }));
    const humanUids = humans.map(h => h.uid);
    const earnedByUid = new Map();
    for (const [uid, profile] of profiles)
        earnedByUid.set(uid, Math.max(0, finite(profile.earnedClaimMeters) ?? 0));
    // Their pops, and the engagements on them and by them.
    const posts = [];
    const engagements = [];
    for (const part of chunk(humanUids, 30)) {
        if (!part.length)
            continue;
        const rows = await db.collection("posts").where("userID", "in", part).get();
        for (const doc of rows.docs) {
            const p = doc.data();
            const uid = String(p.userID ?? "");
            posts.push({
                id: doc.id, uid, createdAtMillis: millisOf(p.createdAtMillis ?? p.createdAt), human: (0, syntheticIdentity_1.postClass)(doc.id, p, false) === "real",
                seedMeters: Math.max(0, finite(p.seedRadiusMeters) ?? 0), organicMeters: Math.max(0, finite(p.organicRadiusMeters) ?? 0),
                radiusMeters: Math.max(0, finite(p.radiusMeters ?? p.radius) ?? 0),
                live: p.visibilityStatus !== "expired" && p.status !== "deleted" && (finite(p.radiusMeters ?? p.radius) ?? 0) > 0,
            });
        }
        const made = await db.collectionGroup("engagements").where("actorUid", "in", part).get();
        for (const doc of made.docs) {
            const e = doc.data();
            const postRef = doc.ref.parent.parent;
            engagements.push({
                postId: postRef?.id ?? "", postOwnerUid: "", actorUid: String(e.actorUid ?? ""), actorHuman: true,
                kind: String(e.kind ?? ""), surface: String(e.surface ?? "unknown"), createdAtMillis: millisOf(e.createdAtMillis ?? e.createdAt),
            });
        }
    }
    const ownerOf = new Map(posts.map(p => [p.id, p.uid]));
    for (const e of engagements)
        e.postOwnerUid = ownerOf.get(e.postId) ?? "";
    const seen = new Set(engagements.map(e => `${e.postId}/${e.actorUid}/${e.createdAtMillis}`));
    for (const p of posts.filter(p => p.human)) {
        const onPop = await db.collection("posts").doc(p.id).collection("engagements").limit(500).get();
        for (const doc of onPop.docs) {
            const e = doc.data();
            const actorUid = String(e.actorUid ?? "");
            const createdAtMillis = millisOf(e.createdAtMillis ?? e.createdAt);
            if (seen.has(`${p.id}/${actorUid}/${createdAtMillis}`))
                continue;
            engagements.push({
                postId: p.id, postOwnerUid: p.uid, actorUid, actorHuman: classOf(actorUid) === "real",
                kind: String(e.kind ?? ""), surface: String(e.surface ?? "unknown"), createdAtMillis,
            });
        }
    }
    const replaced = await db.collection("posts").where("expiryReason", "==", "replaced-by-nearby-pop").count().get();
    return foldScorecard({
        nowMillis, startMillis, endMillis, promptDays, referralInstalls, humans, posts, engagements, earnedByUid,
        replacedPops: replaced.data().count,
    });
}
async function publishBetaScorecard(db, nowMillis = Date.now()) {
    const scorecard = await computeBetaScorecard(db, nowMillis);
    await db.doc(exports.SCORECARD_DOC).set({ ...scorecard, updatedAt: firestore_1.Timestamp.fromMillis(nowMillis), publishedAt: firestore_1.FieldValue.serverTimestamp() });
    return scorecard;
}
if (admin.apps.length === 0)
    admin.initializeApp();
// 512 MiB: a new function at the 256 MiB default is OOM-killed on cold start (11 Sep 2026).
exports.betaScorecard = (0, scheduler_1.onSchedule)({ schedule: "*/15 * * * *", timeZone: exports.SCORECARD_TIME_ZONE, region: "us-central1", memory: "512MiB", cpu: 1, timeoutSeconds: 120 }, async () => { await publishBetaScorecard(admin.firestore()); });
