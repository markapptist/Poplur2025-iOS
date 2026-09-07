"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.SYNTHETIC_RADIUS_HALF_LIFE_HOURS = void 0;
exports.calculateSyntheticRetentionDecay = calculateSyntheticRetentionDecay;
const postEngagementPolicy_1 = require("./postEngagementPolicy");
const syntheticDailyPolicy_1 = require("./syntheticDailyPolicy");
exports.SYNTHETIC_RADIUS_HALF_LIFE_HOURS = 4;
/** Opt-in, server-authored stress posts only. Real users keep normal decay. */
function calculateSyntheticRetentionDecay(post, now) {
    if (post.syntheticSource !== syntheticDailyPolicy_1.DAILY_SOURCE || post.syntheticBeta !== true
        || post.simulationRetentionVersion !== 1 || typeof post.userID !== "string"
        || !post.userID.startsWith("sim-"))
        return null;
    const stamp = post.decayedAt;
    const previous = stamp?.toMillis?.();
    if (previous == null || now - previous < 60_000)
        return null;
    const before = (0, postEngagementPolicy_1.postRadiusParts)(post, now);
    const factor = 2 ** (-(now - previous) / (exports.SYNTHETIC_RADIUS_HALF_LIFE_HOURS * 3_600_000));
    const decay = (meters) => { const next = Math.floor(meters * factor); return next < 10 ? 0 : next; };
    const organicRadiusMeters = decay(before.organic);
    // In this stress scenario even the test discovery grant expires. Otherwise
    // 24 posts/day permanently add 120 km/day and decline cannot be tested.
    const seedRadiusMeters = decay(before.seed);
    const radiusMeters = Math.min(postEngagementPolicy_1.MAX_POST_RADIUS_METERS, organicRadiusMeters + seedRadiusMeters + before.boost);
    if (radiusMeters >= before.total)
        return null;
    return { organicRadiusMeters, seedRadiusMeters, radiusMeters };
}
