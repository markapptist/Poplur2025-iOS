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
exports.testActivityControl = void 0;
const admin = __importStar(require("firebase-admin"));
const node_crypto_1 = require("node:crypto");
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const syntheticBetaCohort_1 = require("./syntheticBetaCohort");
/**
 * Privacy-safe, opt-in operations telemetry for the September test cohort.
 *
 * This is intentionally a closed-beta operations feed, not general product
 * analytics. It never accepts message text, media, raw coordinates, contacts,
 * camera or microphone data. Map reporting is deliberately limited to a
 * coarse, user-visible city/region label. Each row carries a 14-day
 * `expiresAt` field so production can apply a Firestore TTL policy without
 * changing this endpoint; the dashboard is further restricted to the two
 * retained production-test administrators.
 */
const REGION = "us-central1";
const RETENTION_MS = 14 * 24 * 60 * 60 * 1000;
const BETA_DESK_ACCESS_TOKEN = (0, params_1.defineSecret)("BETA_DESK_ACCESS_TOKEN");
const BETA_DESK_OPERATOR_UID = "LiEG6SNtKEZN6eEGeybf0afZnHm1";
const TEST_ADMIN_UIDS = new Set([
    "LiEG6SNtKEZN6eEGeybf0afZnHm1", // testcall@poplur.com
    "eoP2Z0ElxIa0Eua7xpFxNlr6tur1", // mark@apptist.ca
]);
const SCREENS = new Set([
    "home", "map", "feed", "camera", "camera-roll", "profile", "hold-menu",
    "upload-flows", "arcade", "games", "battle",
]);
const STATUSES = new Set(["foreground", "background"]);
const PLATFORMS = new Set(["native", "browser"]);
const EVENT_KINDS = new Set(["posted", "like", "view", "comment", "radius-up", "radius-down"]);
const FEEDBACK_LIMIT = 1_200;
const ACTIVITY_LIMIT = 100;
const POST_LIMIT = 120;
const EVENT_LIMIT = 160;
const FEEDBACK_LIST_LIMIT = 80;
const SIMULATION_FEED_LIMIT = 24;
function db() {
    if (!admin.apps.length)
        admin.initializeApp();
    return admin.firestore();
}
function requireSignedIn(uid) {
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in to use the Test Control Center.");
    return uid;
}
function requireAdmin(uid) {
    if (!TEST_ADMIN_UIDS.has(uid)) {
        throw new https_1.HttpsError("permission-denied", "This private tester dashboard is restricted.");
    }
}
/** A local owner-only proxy presents this value; it never reaches browser JS. */
function hasValidDeskCredential(value) {
    const supplied = typeof value === "string" ? value.trim() : "";
    const expected = BETA_DESK_ACCESS_TOKEN.value();
    if (!supplied || !expected || supplied.length !== expected.length)
        return false;
    return (0, node_crypto_1.timingSafeEqual)(Buffer.from(supplied), Buffer.from(expected));
}
function enumValue(value, allowed, fallback) {
    return typeof value === "string" && allowed.has(value) ? value : fallback;
}
function appVersion(value) {
    return typeof value === "string" && /^\d+\.\d+(?:\.\d+)?$/.test(value)
        ? value.slice(0, 24)
        : "0.1.0";
}
function text(value, maxLength) {
    return typeof value === "string" ? value.trim().replace(/\s+/g, " ").slice(0, maxLength) : "";
}
function safeMetric(value, minimum, maximum, fallback = 0) {
    const metric = typeof value === "number" ? value : Number(value);
    return Number.isFinite(metric) ? Math.max(minimum, Math.min(maximum, metric)) : fallback;
}
function safeKey(value) {
    return text(value, 80).replace(/[^a-zA-Z0-9_-]/g, "_") || "untitled";
}
function timestampMs(value) {
    return value && typeof value.toMillis === "function"
        ? value.toMillis()
        : 0;
}
function activeConsent(profile) {
    return profile?.testActivityConsent === true;
}
async function clearTelemetryForUser(uid) {
    const posts = await db().collection("testBetaPosts").where("uid", "==", uid).limit(POST_LIMIT).get();
    const batch = db().batch();
    posts.docs.forEach(doc => batch.delete(doc.ref));
    batch.delete(db().collection("testActivity").doc(uid));
    await batch.commit();
}
function labelFor(uid, profile, authName) {
    const username = typeof profile?.username === "string" ? profile.username.trim().replace(/^@/, "") : "";
    if (username)
        return `@${username.slice(0, 40)}`;
    const name = typeof authName === "string" ? authName.trim() : "";
    if (name)
        return name.slice(0, 50);
    return `Tester ${uid.slice(-4)}`;
}
function mappedSyntheticEvent(doc) {
    const event = doc.data();
    if (event.source !== "synthetic" || event.cohortId !== syntheticBetaCohort_1.SYNTHETIC_BETA_COHORT_ID)
        return null;
    const eventAtMs = timestampMs(event.eventAt);
    if (!eventAtMs)
        return null;
    return {
        eventId: text(event.eventId, 120) || doc.id,
        actorId: text(event.actorId, 80) || "sim-unknown",
        actor: text(event.actor, 64) || "SIM · @tester",
        kind: EVENT_KINDS.has(text(event.kind, 24))
            ? text(event.kind, 24)
            : "view",
        place: text(event.place, 64) || "Private beta region",
        radiusKm: safeMetric(event.radiusKm, 0, 20_000),
        screen: enumValue(event.screen, SCREENS, "map"),
        eventAtMs,
        source: "synthetic",
        cohortId: syntheticBetaCohort_1.SYNTHETIC_BETA_COHORT_ID,
    };
}
exports.testActivityControl = (0, https_1.onCall)({ region: REGION, secrets: [BETA_DESK_ACCESS_TOKEN] }, async (request) => {
    const action = request.data?.action;
    const operatorAction = action === "dashboard" || action === "simulation" || action === "simulationStep";
    const hasDeskAccess = hasValidDeskCredential(request.data?.accessCode)
        || (typeof request.auth?.uid === "string" && TEST_ADMIN_UIDS.has(request.auth.uid));
    const uid = request.auth?.uid
        ?? (operatorAction && hasDeskAccess ? BETA_DESK_OPERATOR_UID : requireSignedIn(request.auth?.uid));
    if (action === "setConsent") {
        const enabled = request.data?.enabled === true;
        const user = db().collection("users").doc(uid);
        await user.set({
            testActivityConsent: enabled,
            testActivityConsentUpdatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        if (!enabled)
            await clearTelemetryForUser(uid);
        return { enabled };
    }
    if (action === "getConsent") {
        const profile = await db().collection("users").doc(uid).get();
        return { enabled: profile.data()?.testActivityConsent === true };
    }
    if (action === "heartbeat") {
        const user = db().collection("users").doc(uid);
        const profile = await user.get();
        if (!activeConsent(profile.data())) {
            throw new https_1.HttpsError("failed-precondition", "Test activity sharing is turned off.");
        }
        const now = Date.now();
        await db().collection("testActivity").doc(uid).set({
            label: labelFor(uid, profile.data(), request.auth?.token.name),
            screen: enumValue(request.data?.screen, SCREENS, "home"),
            status: enumValue(request.data?.status, STATUSES, "foreground"),
            platform: enumValue(request.data?.platform, PLATFORMS, "browser"),
            appVersion: appVersion(request.data?.appVersion),
            lastActivityAt: firestore_1.FieldValue.serverTimestamp(),
            expiresAt: admin.firestore.Timestamp.fromMillis(now + RETENTION_MS),
        }, { merge: true });
        return { accepted: true };
    }
    if (action === "post") {
        const profile = await db().collection("users").doc(uid).get();
        if (!activeConsent(profile.data())) {
            throw new https_1.HttpsError("failed-precondition", "Closed-beta analytics sharing is turned off.");
        }
        const now = Date.now();
        const postKey = safeKey(request.data?.postKey);
        const place = text(request.data?.place, 64) || "Private beta region";
        const radiusKm = safeMetric(request.data?.radiusKm, 0, 20_000);
        const id = `${uid}_${postKey}`;
        await db().collection("testBetaPosts").doc(id).set({
            uid,
            label: labelFor(uid, profile.data(), request.auth?.token.name),
            place,
            postKey,
            initialRadiusKm: radiusKm,
            radiusKm,
            radiusDeltaKm: 0,
            viralScore: 0,
            postedAt: firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
            expiresAt: admin.firestore.Timestamp.fromMillis(now + RETENTION_MS),
        }, { merge: true });
        return { accepted: true };
    }
    if (action === "radius") {
        const profile = await db().collection("users").doc(uid).get();
        if (!activeConsent(profile.data())) {
            throw new https_1.HttpsError("failed-precondition", "Closed-beta analytics sharing is turned off.");
        }
        const now = Date.now();
        const postKey = safeKey(request.data?.postKey);
        const radiusKm = safeMetric(request.data?.radiusKm, 0, 20_000);
        const deltaKm = safeMetric(request.data?.deltaKm, -2_000, 2_000);
        const signal = text(request.data?.signal, 24);
        const ref = db().collection("testBetaPosts").doc(`${uid}_${postKey}`);
        const current = await ref.get();
        const previous = current.data();
        const previousScore = safeMetric(previous?.viralScore, 0, 1_000_000);
        const scoreDelta = signal === "comment" ? 3 : signal === "like" ? 2 : signal === "view" ? 1 : Math.abs(deltaKm) >= 2 ? 2 : 1;
        await ref.set({
            uid,
            label: labelFor(uid, profile.data(), request.auth?.token.name),
            place: text(previous?.place, 64) || "Private beta region",
            postKey,
            initialRadiusKm: safeMetric(previous?.initialRadiusKm, 0, 20_000, radiusKm),
            radiusKm,
            radiusDeltaKm: safeMetric(previous?.radiusDeltaKm, -20_000, 20_000) + deltaKm,
            viralScore: previousScore + scoreDelta,
            postedAt: previous?.postedAt ?? firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
            expiresAt: admin.firestore.Timestamp.fromMillis(now + RETENTION_MS),
        }, { merge: true });
        return { accepted: true };
    }
    if (action === "feedback") {
        const finding = text(request.data?.finding, FEEDBACK_LIMIT);
        const liked = text(request.data?.liked, FEEDBACK_LIMIT);
        const improve = text(request.data?.improve, FEEDBACK_LIMIT);
        if (!finding && !liked && !improve) {
            throw new https_1.HttpsError("invalid-argument", "Add a finding, a positive, or an improvement idea.");
        }
        const profile = await db().collection("users").doc(uid).get();
        const now = Date.now();
        await db().collection("testFeedback").add({
            uid,
            label: labelFor(uid, profile.data(), request.auth?.token.name),
            finding,
            liked,
            improve,
            createdAt: firestore_1.FieldValue.serverTimestamp(),
            expiresAt: admin.firestore.Timestamp.fromMillis(now + RETENTION_MS),
        });
        return { accepted: true };
    }
    if (action === "simulation") {
        const config = db().collection("testControl").doc("simulation");
        if (typeof request.data?.enabled === "boolean") {
            requireAdmin(uid);
            await config.set({
                enabled: request.data.enabled,
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
                updatedBy: uid,
            }, { merge: true });
        }
        const snapshot = await config.get();
        return { enabled: snapshot.data()?.enabled === true };
    }
    if (action === "simulationStep") {
        requireAdmin(uid);
        const config = await db().collection("testControl").doc("simulation").get();
        if (config.data()?.enabled !== true) {
            return { accepted: false, enabled: false, event: null };
        }
        const event = (0, syntheticBetaCohort_1.syntheticEventForTime)(Date.now());
        const { eventAtMs, ...storedEvent } = event;
        await db().collection("testSimulationEvents").doc(event.eventId).set({
            ...storedEvent,
            eventAt: admin.firestore.Timestamp.fromMillis(eventAtMs),
            expiresAt: admin.firestore.Timestamp.fromMillis(eventAtMs + RETENTION_MS),
        });
        return { accepted: true, enabled: true, event };
    }
    if (action === "simulationFeed") {
        const config = await db().collection("testControl").doc("simulation").get();
        if (config.data()?.enabled !== true)
            return { enabled: false, events: [] };
        const afterEventAtMs = safeMetric(request.data?.afterEventAtMs, 0, Date.now());
        const events = db().collection("testSimulationEvents");
        const query = afterEventAtMs > 0
            ? events.where("eventAt", ">", admin.firestore.Timestamp.fromMillis(afterEventAtMs)).orderBy("eventAt", "asc")
            : events.orderBy("eventAt", "desc");
        const snapshot = await query.limit(SIMULATION_FEED_LIMIT).get();
        const mapped = snapshot.docs
            .map(mappedSyntheticEvent)
            .filter((event) => event !== null);
        return {
            enabled: true,
            events: mapped,
            latestEventAtMs: mapped.reduce((latest, event) => Math.max(latest, event.eventAtMs), afterEventAtMs),
        };
    }
    if (action === "simulationPulse") {
        requireAdmin(uid);
        const config = await db().collection("testControl").doc("simulation").get();
        if (config.data()?.enabled !== true)
            return { accepted: false };
        const kind = text(request.data?.kind, 24);
        if (!EVENT_KINDS.has(kind))
            throw new https_1.HttpsError("invalid-argument", "Unsupported simulation event.");
        const now = Date.now();
        const ref = db().collection("testSimulationEvents").doc();
        await ref.set({
            eventId: ref.id,
            actorId: "legacy-local-demo",
            actor: text(request.data?.actor, 64) || "@simulator",
            kind,
            place: text(request.data?.place, 64) || "Private beta region",
            radiusKm: safeMetric(request.data?.radiusKm, 0, 20_000),
            screen: "map",
            source: "synthetic",
            cohortId: "legacy-local-demo",
            eventAt: firestore_1.FieldValue.serverTimestamp(),
            expiresAt: admin.firestore.Timestamp.fromMillis(now + RETENTION_MS),
        });
        return { accepted: true };
    }
    if (action === "dashboard") {
        requireAdmin(uid);
        const now = Date.now();
        const [activitySnapshot, postSnapshot, feedbackSnapshot, simulationSnapshot, configSnapshot] = await Promise.all([
            db().collection("testActivity").orderBy("lastActivityAt", "desc").limit(ACTIVITY_LIMIT).get(),
            db().collection("testBetaPosts").orderBy("updatedAt", "desc").limit(POST_LIMIT).get(),
            db().collection("testFeedback").orderBy("createdAt", "desc").limit(FEEDBACK_LIST_LIMIT).get(),
            db().collection("testSimulationEvents").orderBy("eventAt", "desc").limit(EVENT_LIMIT).get(),
            db().collection("testControl").doc("simulation").get(),
        ]);
        const posts = postSnapshot.docs.map(doc => {
            const post = doc.data();
            const postedAtMs = timestampMs(post.postedAt);
            const updatedAtMs = timestampMs(post.updatedAt);
            const elapsedHours = Math.max((now - (postedAtMs || now)) / 3_600_000, 0.1);
            const viralScore = safeMetric(post.viralScore, 0, 1_000_000);
            return {
                id: doc.id,
                label: text(post.label, 50) || "Tester",
                place: text(post.place, 64) || "Private beta region",
                postedAtMs,
                updatedAtMs,
                initialRadiusKm: safeMetric(post.initialRadiusKm, 0, 20_000),
                radiusKm: safeMetric(post.radiusKm, 0, 20_000),
                radiusDeltaKm: safeMetric(post.radiusDeltaKm, -20_000, 20_000),
                viralScore,
                viralPerHour: Math.round((viralScore / elapsedHours) * 10) / 10,
            };
        });
        const simulation = simulationSnapshot.docs.map(doc => {
            const event = doc.data();
            return {
                id: doc.id,
                eventId: text(event.eventId, 120) || doc.id,
                actorId: text(event.actorId, 80) || "sim-unknown",
                actor: text(event.actor, 64) || "@simulator",
                kind: EVENT_KINDS.has(text(event.kind, 24)) ? text(event.kind, 24) : "view",
                place: text(event.place, 64) || "Private beta region",
                radiusKm: safeMetric(event.radiusKm, 0, 20_000),
                screen: enumValue(event.screen, SCREENS, "map"),
                source: "synthetic",
                cohortId: text(event.cohortId, 80) || "legacy-local-demo",
                eventAtMs: timestampMs(event.eventAt),
            };
        });
        const map = new Map();
        [
            ...posts.map(post => ({ place: post.place, at: post.updatedAtMs, radiusKm: post.radiusKm, velocity: post.viralPerHour, source: "real" })),
            ...simulation.map(event => ({ place: event.place, at: event.eventAtMs, radiusKm: event.radiusKm, velocity: event.kind === "comment" ? 3 : event.kind === "like" ? 2 : 1, source: "synthetic" })),
        ]
            .forEach(event => {
            const previous = map.get(event.place) ?? {
                place: event.place,
                events: 0,
                realEvents: 0,
                syntheticEvents: 0,
                latestAtMs: 0,
                peakRadiusKm: 0,
                velocity: 0,
            };
            map.set(event.place, {
                place: event.place,
                events: previous.events + 1,
                realEvents: previous.realEvents + (event.source === "real" ? 1 : 0),
                syntheticEvents: previous.syntheticEvents + (event.source === "synthetic" ? 1 : 0),
                latestAtMs: Math.max(previous.latestAtMs, event.at),
                peakRadiusKm: Math.max(previous.peakRadiusKm, event.radiusKm),
                velocity: Math.max(previous.velocity, event.velocity),
            });
        });
        return {
            generatedAtMs: now,
            rows: activitySnapshot.docs.map(doc => {
                const row = doc.data();
                const lastActivityAtMs = row.lastActivityAt?.toMillis?.() ?? 0;
                return {
                    id: doc.id,
                    label: typeof row.label === "string" ? row.label : `Tester ${doc.id.slice(-4)}`,
                    screen: typeof row.screen === "string" ? row.screen : "home",
                    platform: row.platform === "native" ? "native" : "browser",
                    appVersion: typeof row.appVersion === "string" ? row.appVersion : "0.1.0",
                    status: row.status === "background" ? "background" : "foreground",
                    lastActivityAtMs,
                    state: now - lastActivityAtMs <= 90_000 ? "active" : "away",
                };
            }),
            posts,
            map: [...map.values()].sort((a, b) => b.events - a.events || b.latestAtMs - a.latestAtMs).slice(0, 32),
            simulation,
            simulationEnabled: configSnapshot.data()?.enabled === true,
            syntheticProfiles: syntheticBetaCohort_1.SYNTHETIC_BETA_PROFILES.map(profile => ({
                id: profile.id,
                label: profile.label,
                handle: profile.handle,
                persona: profile.persona,
                place: profile.place,
                screen: profile.screen,
                status: configSnapshot.data()?.enabled === true ? "live" : "paused",
                finding: profile.finding,
                liked: profile.liked,
                improve: profile.improve,
                avatarTile: profile.avatarTile,
                source: profile.source,
                cohortId: profile.cohortId,
            })),
            counts: {
                realTesters: activitySnapshot.size,
                realPosts: posts.length,
                syntheticPersonas: syntheticBetaCohort_1.SYNTHETIC_BETA_PROFILES.length,
                syntheticEvents: simulation.length,
            },
            feedback: feedbackSnapshot.docs.map(doc => {
                const feedback = doc.data();
                return {
                    id: doc.id,
                    label: text(feedback.label, 50) || "Tester",
                    finding: text(feedback.finding, FEEDBACK_LIMIT),
                    liked: text(feedback.liked, FEEDBACK_LIMIT),
                    improve: text(feedback.improve, FEEDBACK_LIMIT),
                    createdAtMs: timestampMs(feedback.createdAt),
                };
            }),
        };
    }
    throw new https_1.HttpsError("invalid-argument", "Unsupported Test Control Center action.");
});
