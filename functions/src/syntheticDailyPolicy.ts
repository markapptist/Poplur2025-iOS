import { createHash } from "node:crypto";

export const DAILY_NEW_TESTERS = 2;
export const DAILY_POSTS_PER_TESTER = 2;
export const DAILY_SOURCE = "scheduled-test-simulation";
export const SIMULATION_CITIES = [
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
] as const;

export function simulationDay(now: number): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/Toronto", year: "numeric", month: "2-digit", day: "2-digit" }).format(now);
}
export function simulationHash(value: string): number {
  return createHash("sha256").update(value).digest().readUInt32BE(0);
}
export function dailyTesterIds(day: string): string[] {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) throw new Error("Invalid simulation day");
  return Array.from({ length: DAILY_NEW_TESTERS }, (_, i) => `sim-daily-${day}-${i + 1}`);
}
export function dailyPostId(day: string, uid: string, slot: number): string {
  return `post-sim-daily-${day}-${simulationHash(uid).toString(16)}-${slot}`;
}
export function dailyPostLocation(day: string, actorIndex: number, slot: number) {
  // Adjacent actors/slots visit different cities; daily rotation prevents a fixed cluster.
  const index = (simulationHash(day) + actorIndex * DAILY_POSTS_PER_TESTER + slot) % SIMULATION_CITIES.length;
  const [place, lat, lng] = SIMULATION_CITIES[index];
  const jitter = (simulationHash(`${day}:${actorIndex}:${slot}`) % 101 - 50) / 1000;
  const latitudeCell = Math.round((lat + jitter) * 1000);
  const longitudeCell = Math.round((lng - jitter) * 1000);
  return { place, latitudeCell, longitudeCell, latitude: latitudeCell / 1000, longitude: longitudeCell / 1000 };
}

export function simulationReaction(uid: string, postId: string, synthetic: boolean): "like" | "dislike" {
  // Stable per actor/post: repeated days do not pay a like and later a dislike on the same pair.
  return synthetic && simulationHash(`${uid}:${postId}`) % 3 === 0 ? "dislike" : "like";
}
