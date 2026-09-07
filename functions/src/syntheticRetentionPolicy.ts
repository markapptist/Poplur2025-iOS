import { MAX_POST_RADIUS_METERS, postRadiusParts } from "./postEngagementPolicy";
import { DAILY_SOURCE } from "./syntheticDailyPolicy";

export const SYNTHETIC_RADIUS_HALF_LIFE_HOURS = 4;

/** Opt-in, server-authored stress posts only. Real users keep normal decay. */
export function calculateSyntheticRetentionDecay(post: Record<string, unknown>, now: number) {
  if (post.syntheticSource !== DAILY_SOURCE || post.syntheticBeta !== true
    || post.simulationRetentionVersion !== 1 || typeof post.userID !== "string"
    || !post.userID.startsWith("sim-")) return null;
  const stamp = post.decayedAt as { toMillis?: () => number } | undefined;
  const previous = stamp?.toMillis?.();
  if (previous == null || now - previous < 60_000) return null;
  const before = postRadiusParts(post, now);
  const factor = 2 ** (-(now - previous) / (SYNTHETIC_RADIUS_HALF_LIFE_HOURS * 3_600_000));
  const decay = (meters: number) => { const next = Math.floor(meters * factor); return next < 10 ? 0 : next; };
  const organicRadiusMeters = decay(before.organic);
  // In this stress scenario even the test discovery grant expires. Otherwise
  // 24 posts/day permanently add 120 km/day and decline cannot be tested.
  const seedRadiusMeters = decay(before.seed);
  const radiusMeters = Math.min(MAX_POST_RADIUS_METERS, organicRadiusMeters + seedRadiusMeters + before.boost);
  if (radiusMeters >= before.total) return null;
  return { organicRadiusMeters, seedRadiusMeters, radiusMeters };
}
