/**
 * Fixed, explicitly synthetic closed-beta personas.
 *
 * These are simulation actors, not Firebase Auth users. They never write to
 * `users`, create social content, or impersonate a human tester. Keeping the
 * cohort in code lets the operator dashboard and the app consume the same
 * deterministic identities without another mutable production collection.
 */

export const SYNTHETIC_BETA_COHORT_ID = "beta-sim-v1";
export const SYNTHETIC_EVENT_INTERVAL_MS = 15_000;

export type SyntheticBetaProfile = {
  id: string;
  label: string;
  handle: string;
  persona: string;
  place: string;
  screen: string;
  finding: string;
  liked: string;
  improve: string;
  avatarTile: string;
  source: "synthetic";
  cohortId: typeof SYNTHETIC_BETA_COHORT_ID;
  radiusBaseKm: number;
};

export type SyntheticBetaEvent = {
  eventId: string;
  actorId: string;
  actor: string;
  kind: "posted" | "like" | "view" | "comment" | "radius-up" | "radius-down";
  place: string;
  radiusKm: number;
  screen: string;
  eventAtMs: number;
  source: "synthetic";
  cohortId: typeof SYNTHETIC_BETA_COHORT_ID;
};

export const SYNTHETIC_BETA_PROFILES: readonly SyntheticBetaProfile[] = [
  {
    id: "sim-food-001",
    label: "SIM · @sauceboss",
    handle: "@sauceboss",
    persona: "Food scout",
    place: "Toronto",
    screen: "camera",
    finding: "Fast visual posts are easy to understand, but the composer needs clearer progress feedback.",
    liked: "The camera-to-map flow feels immediate and local.",
    improve: "Show upload and radius changes without obscuring the post.",
    avatarTile: "food",
    source: "synthetic",
    cohortId: SYNTHETIC_BETA_COHORT_ID,
    radiusBaseKm: 4.2,
  },
  {
    id: "sim-sports-002",
    label: "SIM · @pitchside",
    handle: "@pitchside",
    persona: "Live sports fan",
    place: "London",
    screen: "feed",
    finding: "Short event bursts can make a post grow much faster than ordinary activity.",
    liked: "Live reactions feel energetic when the map and feed update together.",
    improve: "Make burst virality readable without rapidly shifting the entire layout.",
    avatarTile: "sports",
    source: "synthetic",
    cohortId: SYNTHETIC_BETA_COHORT_ID,
    radiusBaseKm: 7.6,
  },
  {
    id: "sim-music-003",
    label: "SIM · @basement.set",
    handle: "@basement.set",
    persona: "Music curator",
    place: "Toronto",
    screen: "feed",
    finding: "Audio posts spread slowly at first and then hold attention for longer sessions.",
    liked: "The radio and music identity is distinctive.",
    improve: "Keep playback state obvious while moving between Feed, Map, and Radio.",
    avatarTile: "music",
    source: "synthetic",
    cohortId: SYNTHETIC_BETA_COHORT_ID,
    radiusBaseKm: 3.4,
  },
  {
    id: "sim-tech-004",
    label: "SIM · @shipit",
    handle: "@shipit",
    persona: "Performance tester",
    place: "World beta region",
    screen: "map",
    finding: "Rapid screen changes reveal loading and lifecycle issues before single-screen use does.",
    liked: "The side-control language stays recognizable across features.",
    improve: "Park expensive scenes sooner and preserve the exact return position.",
    avatarTile: "tech",
    source: "synthetic",
    cohortId: SYNTHETIC_BETA_COHORT_ID,
    radiusBaseKm: 12.5,
  },
  {
    id: "sim-news-005",
    label: "SIM · @citydesk",
    handle: "@citydesk",
    persona: "News explorer",
    place: "New York",
    screen: "map",
    finding: "Worldwide stories are most useful when the map clearly explains why it moved.",
    liked: "The news tour turns headlines into a spatial experience.",
    improve: "Keep story source, age, and next destination visible during the tour.",
    avatarTile: "news",
    source: "synthetic",
    cohortId: SYNTHETIC_BETA_COHORT_ID,
    radiusBaseKm: 9.8,
  },
] as const;

const EVENT_SEQUENCE: readonly SyntheticBetaEvent["kind"][] = [
  "view",
  "like",
  "view",
  "comment",
  "radius-up",
  "view",
  "like",
  "radius-down",
];

/** Returns one stable event for a wall-clock slot. Repeating the same slot is idempotent. */
export function syntheticEventForTime(nowMs: number): SyntheticBetaEvent {
  const safeNow = Number.isFinite(nowMs) && nowMs >= 0 ? Math.floor(nowMs) : 0;
  const slot = Math.floor(safeNow / SYNTHETIC_EVENT_INTERVAL_MS);
  const eventAtMs = slot * SYNTHETIC_EVENT_INTERVAL_MS;
  const profile = SYNTHETIC_BETA_PROFILES[slot % SYNTHETIC_BETA_PROFILES.length];
  const kind = EVENT_SEQUENCE[slot % EVENT_SEQUENCE.length];
  const wave = (slot % 9) - 4;
  const radiusKm = Math.max(0.5, Math.round((profile.radiusBaseKm + wave * 0.35) * 10) / 10);
  return {
    eventId: `${SYNTHETIC_BETA_COHORT_ID}_${profile.id}_${slot}`,
    actorId: profile.id,
    actor: profile.label,
    kind,
    place: profile.place,
    radiusKm,
    screen: profile.screen,
    eventAtMs,
    source: "synthetic",
    cohortId: SYNTHETIC_BETA_COHORT_ID,
  };
}
