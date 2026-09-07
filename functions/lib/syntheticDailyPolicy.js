"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SIMULATION_CITIES = exports.DAILY_SOURCE = exports.SIMULATION_ACTIVE_ACTOR_LIMIT = exports.SIMULATION_POSTS_PER_SLOT = exports.SIMULATION_SLOT_MS = exports.DAILY_POSTS_PER_TESTER = exports.DAILY_NEW_TESTERS = void 0;
exports.simulationSlot = simulationSlot;
exports.simulationSlotPostId = simulationSlotPostId;
exports.simulationEngagementKinds = simulationEngagementKinds;
exports.simulationDay = simulationDay;
exports.simulationHash = simulationHash;
exports.dailyTesterIds = dailyTesterIds;
exports.dailyPostId = dailyPostId;
exports.dailyPostLocation = dailyPostLocation;
exports.simulationReaction = simulationReaction;
const node_crypto_1 = require("node:crypto");
exports.DAILY_NEW_TESTERS = 2;
exports.DAILY_POSTS_PER_TESTER = 24;
exports.SIMULATION_SLOT_MS = 60 * 60_000;
exports.SIMULATION_POSTS_PER_SLOT = 1;
exports.SIMULATION_ACTIVE_ACTOR_LIMIT = 64;
exports.DAILY_SOURCE = "scheduled-test-simulation";
function simulationSlot(now) {
    return new Date(Math.floor(now / exports.SIMULATION_SLOT_MS) * exports.SIMULATION_SLOT_MS).toISOString().slice(0, 13);
}
function simulationSlotPostId(now, uid, slot = 0) {
    return `post-sim-hourly-${simulationSlot(now)}-${simulationHash(uid).toString(16)}-${slot}`;
}
function simulationEngagementKinds(uid, postId, synthetic) {
    if (!synthetic)
        return ["view", "like", "comment"];
    // Mixed reactions plus an accelerated decay clock exercise actual losses.
    // A dislike is independent of the optional paid-view event, otherwise its
    // -1 km was always cancelled by the immediately preceding +1 km view.
    const bucket = simulationHash(`${uid}:${postId}`) % 8;
    return bucket < 4 ? ["dislike"] : bucket === 4 ? ["view", "comment"] : ["view", "like"];
}
exports.SIMULATION_CITIES = [
    ["Toronto", 43.653, -79.383], ["Vancouver", 49.283, -123.121],
    ["New York", 40.713, -74.006], ["Los Angeles", 34.052, -118.244],
    ["Mexico City", 19.433, -99.133], ["Lima", -12.046, -77.043],
    ["São Paulo", -23.551, -46.633], ["Buenos Aires", -34.604, -58.382],
    ["London", 51.507, -0.128], ["Paris", 48.857, 2.352],
    ["Berlin", 52.520, 13.405], ["Rome", 41.903, 12.496],
    ["Lagos", 6.524, 3.379], ["Nairobi", -1.292, 36.822],
    ["Cape Town", -33.925, 18.424], ["Cairo", 30.044, 31.236],
    ["Mumbai", 19.076, 72.878], ["Bangkok", 13.756, 100.502],
    ["Tokyo", 35.676, 139.650], ["Seoul", 37.567, 126.978],
    ["Singapore", 1.352, 103.820], ["Sydney", -33.869, 151.209],
    ["Auckland", -36.851, 174.764], ["Honolulu", 21.307, -157.858],
];
function simulationDay(now) {
    return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Toronto", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
}
function simulationHash(value) {
    return (0, node_crypto_1.createHash)("sha256").update(value).digest().readUInt32BE(0);
}
function dailyTesterIds(day) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(day))
        throw new Error("Invalid simulation day");
    return Array.from({ length: exports.DAILY_NEW_TESTERS }, (_, i) => `sim-daily-${day}-${i + 1}`);
}
function dailyPostId(day, uid, slot) {
    return `post-sim-daily-${day}-${simulationHash(uid).toString(16)}-${slot}`;
}
function dailyPostLocation(day, actorIndex, slot) {
    // Adjacent actors/slots visit different cities; daily rotation prevents a fixed cluster.
    const index = (simulationHash(day) + actorIndex * 7 + slot) % exports.SIMULATION_CITIES.length;
    const [place, lat, lng] = exports.SIMULATION_CITIES[index];
    const jitter = (simulationHash(`${day}:${actorIndex}:${slot}`) % 101 - 50) / 1000;
    const latitudeCell = Math.round((lat + jitter) * 1000);
    const longitudeCell = Math.round((lng - jitter) * 1000);
    return { place, latitudeCell, longitudeCell, latitude: latitudeCell / 1000, longitude: longitudeCell / 1000 };
}
function simulationReaction(uid, postId, synthetic) {
    // Stable per actor/post: repeated days do not pay a like and later a dislike on the same pair.
    return synthetic && simulationHash(`${uid}:${postId}`) % 3 === 0 ? "dislike" : "like";
}
