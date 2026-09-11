/**
 * Nearby pops digest — the pure policy behind the scheduled push.
 *
 * Retention primitive: the three existing senders (engagement, DM, radius
 * loss) are all reactions to someone else's action, so a person whose posts
 * nobody touched hears nothing. This digest is the proactive layer: once a day,
 * at a sane local hour, "N new pops in your radius".
 *
 * Everything here is deterministic and unit-tested by
 * scripts/testNearbyPopsPolicy.js; nearbyPopsDigest.ts owns Firestore and FCM.
 */

export const NEARBY_DIGEST_COOLDOWN_MS = 20 * 3_600_000;
/** How far back a digest may look when a user has never had one. */
export const NEARBY_DIGEST_LOOKBACK_MS = 24 * 3_600_000;
/** Local-hour window (inclusive) in which a digest may be delivered. */
export const NEARBY_DIGEST_FIRST_HOUR = 9;
export const NEARBY_DIGEST_LAST_HOUR = 20;
/** Handles named in the body before "and N more". */
export const NEARBY_DIGEST_NAMED_HANDLES = 2;

export interface Coordinates { latitude: number; longitude: number; }

const EARTH_RADIUS_METERS = 6_371_000;

function finiteCoordinate(value: unknown, limit: number): number | null {
  return typeof value === "number" && Number.isFinite(value) && Math.abs(value) <= limit ? value : null;
}

/** A complete, validated pair or nothing — never one coordinate from each spelling. */
export function coordinatePair(latitude: unknown, longitude: unknown): Coordinates | null {
  const lat = finiteCoordinate(latitude, 90);
  const lng = finiteCoordinate(longitude, 180);
  return lat != null && lng != null ? { latitude: lat, longitude: lng } : null;
}

/** Great-circle metres; the same haversine the web's reach.ts uses, in metres. */
export function haversineMeters(a: Coordinates, b: Coordinates): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(b.latitude - a.latitude);
  const dLng = toRad(b.longitude - a.longitude);
  const h = Math.sin(dLat / 2) ** 2
    + Math.cos(toRad(a.latitude)) * Math.cos(toRad(b.latitude)) * Math.sin(dLng / 2) ** 2;
  return EARTH_RADIUS_METERS * 2 * Math.asin(Math.min(1, Math.sqrt(h)));
}

export function millisOf(value: unknown): number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  const stamp = value as { toMillis?: () => number } | undefined;
  const millis = stamp?.toMillis?.();
  return typeof millis === "number" && Number.isFinite(millis) ? millis : 0;
}

export function postCreatedAtMillis(post: Record<string, unknown>): number {
  return millisOf(post.createdAt) || millisOf(post.createdAtMillis);
}

export function postRadiusMeters(post: Record<string, unknown>): number {
  const value = Number(post.radiusMeters ?? post.radius);
  return Number.isFinite(value) && value > 0 ? value : 0;
}

export function postIsTestCohort(post: Record<string, unknown>): boolean {
  return post.syntheticBeta === true || post.syntheticCohort === true
    || typeof post.syntheticSource === "string";
}

export interface NearbyEligibility { viewerUid: string; includeTestCohort: boolean; }

/**
 * The post-level half of mapDiscoveryPolicy.eligibleMapPost. Owner privacy is
 * already reflected on the post: setAccountLocationPrivacy strips coordinates
 * and marks locationVisibility "hidden" for private/ghost accounts, so a post
 * that still carries an approximate public pair is one its owner shows on the
 * map. Official (world-radius) content reaches everyone and would make every
 * digest say the same thing, so it never counts as "near you".
 */
export function eligibleNearbyPost(post: Record<string, unknown>, options: NearbyEligibility): boolean {
  const owner = post.userID ?? post.userId ?? post.ownerUid ?? post.uid;
  if (!owner || owner === options.viewerUid) return false;
  if (post.officialContent === true) return false;
  if (post.audience && post.audience !== "public") return false;
  const status = post.visibilityStatus ?? post.status;
  if (status && status !== "published" && status !== "live") return false;
  if (post.locationVisibility !== "approximate") return false;
  if (post.privateAccount === true || post.ghostMode === true) return false;
  if (["removed", "blocked", "rejected"].includes(String(post.moderationStatus))) return false;
  if (!coordinatePair(post.latitude, post.longitude)) return false;
  if (postRadiusMeters(post) <= 0) return false;
  if (!(post.mediaURL || post.playbackURL || post.caption)) return false;
  if (!options.includeTestCohort && postIsTestCohort(post)) return false;
  return true;
}

/**
 * "In your radius" is the union of the two reach questions from reach.ts:
 * the pop's own radius reaches the viewer (it would intercept their feed), or
 * the pop sits inside the viewer's claim radius (they can reach it on the map).
 */
export function postInViewerRadius(
  post: Record<string, unknown>,
  anchor: Coordinates,
  viewerRadiusMeters: number,
): boolean {
  const coords = coordinatePair(post.latitude, post.longitude);
  if (!coords) return false;
  const distance = haversineMeters(anchor, coords);
  return distance <= postRadiusMeters(post) || distance <= Math.max(0, viewerRadiusMeters);
}

/** Solar local hour from longitude: no timezone is stored for accounts, and
 * ±1 h of solar noon is plenty to keep a digest out of the night. */
export function solarLocalHour(nowMillis: number, longitude: number): number {
  const shifted = nowMillis + (longitude / 15) * 3_600_000;
  return new Date(shifted).getUTCHours();
}

export function digestWindowOpen(localHour: number): boolean {
  return localHour >= NEARBY_DIGEST_FIRST_HOUR && localHour <= NEARBY_DIGEST_LAST_HOUR;
}

export function digestDue(lastDigestAtMillis: unknown, nowMillis: number): boolean {
  return typeof lastDigestAtMillis !== "number" || !Number.isFinite(lastDigestAtMillis)
    || nowMillis - lastDigestAtMillis >= NEARBY_DIGEST_COOLDOWN_MS;
}

/** Posts count as "new" after the last digest, never further back than the lookback. */
export function digestSinceMillis(lastDigestAtMillis: unknown, nowMillis: number): number {
  const floor = nowMillis - NEARBY_DIGEST_LOOKBACK_MS;
  return typeof lastDigestAtMillis === "number" && Number.isFinite(lastDigestAtMillis)
    ? Math.max(floor, lastDigestAtMillis) : floor;
}

/** One inbox row per delivery; hour granularity can never collide under a 20 h cooldown. */
export function nearbyDigestId(nowMillis: number): string {
  return `nearby:${new Date(nowMillis).toISOString().slice(0, 13)}`;
}

export interface NearbyCandidate { postId: string; handle: string; createdAtMillis: number; }

export function nearbyPopsNotification(candidates: NearbyCandidate[]): { title: string; body: string; detail: string } | null {
  if (candidates.length === 0) return null;
  const count = candidates.length;
  const title = count === 1 ? "1 new pop in your radius" : `${count} new pops in your radius`;
  const handles: string[] = [];
  for (const candidate of candidates) {
    const handle = candidate.handle.trim();
    if (!handle || handles.includes(handle)) continue;
    handles.push(handle);
    if (handles.length === NEARBY_DIGEST_NAMED_HANDLES) break;
  }
  const rest = count - handles.length;
  const who = handles.length === 0 ? (count === 1 ? "A pop" : "Pops")
    : handles.length === 1 ? handles[0]
    : `${handles[0]} and ${handles[1]}`;
  const more = rest > 0 && handles.length > 0 ? ` and ${rest} more` : "";
  const verb = count === 1 ? "just landed" : "just landed";
  const body = `${who}${more} ${verb} near you. Tap to see ${count === 1 ? "it" : "them"} on the map.`;
  return { title, body, detail: `${title} · ${who}${more}` };
}

/** Newest first, so the row's postId (what a tap opens) is the freshest pop. */
export function orderNewestFirst<T extends { createdAtMillis: number }>(candidates: T[]): T[] {
  return [...candidates].sort((a, b) => b.createdAtMillis - a.createdAtMillis);
}
