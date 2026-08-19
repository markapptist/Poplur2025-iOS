/**
 * Parameters for the creature-collector template.
 *
 * This is the genre Pokémon defined — starter choice, overworld encounters,
 * turn-based battles with type advantage, capture, a party, evolution — with
 * every creature, move and zone invented per game. None of Nintendo's species,
 * names, art or type chart appears here or is reachable from here: the type set
 * below is our own, and the effectiveness rules are hand-written in this file
 * rather than generated, so balance is a reviewed decision and not a prompt.
 *
 * Kept separate from GameSpecification on purpose: each template has its own
 * parameter shape, and a shared "one spec for every genre" object would have to
 * be loose enough to describe all of them, which is exactly how a validator
 * stops catching anything.
 */

export const CREATURE_SPEC_VERSION = 1 as const;

/** Our own eight elements. Deliberately not the Nintendo eighteen. */
export const CREATURE_TYPES = [
  "ember", "tide", "bloom", "spark", "stone", "gale", "shade", "beast",
] as const;
export type CreatureType = (typeof CREATURE_TYPES)[number];

/**
 * Hand-written effectiveness. A generated chart makes every game a coin flip
 * whose rules the player cannot learn, so this one is fixed and reviewed:
 * each type beats two and loses to two, in one readable cycle.
 */
export const TYPE_CHART: Record<CreatureType, { strongAgainst: CreatureType[]; weakAgainst: CreatureType[] }> = {
  ember: { strongAgainst: ["bloom", "gale"], weakAgainst: ["tide", "stone"] },
  tide:  { strongAgainst: ["ember", "stone"], weakAgainst: ["bloom", "spark"] },
  bloom: { strongAgainst: ["tide", "stone"], weakAgainst: ["ember", "gale"] },
  spark: { strongAgainst: ["tide", "gale"], weakAgainst: ["stone", "bloom"] },
  stone: { strongAgainst: ["ember", "spark"], weakAgainst: ["tide", "bloom"] },
  gale:  { strongAgainst: ["bloom", "beast"], weakAgainst: ["ember", "spark"] },
  shade: { strongAgainst: ["beast", "spark"], weakAgainst: ["gale", "ember"] },
  beast: { strongAgainst: ["shade", "stone"], weakAgainst: ["gale", "shade"] },
};

export const MOVE_EFFECTS = [
  "none", "lower_attack", "lower_defense", "raise_attack", "raise_defense", "heal", "poison", "stun",
] as const;
export type MoveEffect = (typeof MOVE_EFFECTS)[number];

export const RARITIES = ["common", "uncommon", "rare", "legendary"] as const;
export type Rarity = (typeof RARITIES)[number];

/**
 * Ceilings. A GBA cartridge has room for far more than this, but every creature
 * is a sprite sheet plus a battle portrait, and the template loads a zone's
 * encounter table into IWRAM. These numbers keep a generated game inside a
 * budget the template is known to fit, so failure is a sentence rather than a
 * link-time section overflow.
 */
export const CREATURE_LIMITS = {
  titleMaxLength: 48,
  descriptionMaxLength: 280,
  nameMaxLength: 24,
  creatures: { min: 6, max: 24 },
  moves: { min: 4, max: 32 },
  movesPerCreature: { min: 1, max: 4 },
  zones: { min: 2, max: 8 },
  encountersPerZone: { min: 1, max: 6 },
  starters: 3,
  partySize: { min: 1, max: 6 },
  baseStat: { min: 10, max: 120 },
  movePower: { min: 0, max: 120 },
  moveAccuracy: { min: 50, max: 100 },
  catchRate: { min: 1, max: 100 },
  level: { min: 2, max: 60 },
  evolveLevel: { min: 5, max: 55 },
} as const;

export interface MoveSpec {
  id: string;
  displayName: string;
  type: CreatureType;
  /** 0 means a status move that deals no damage. */
  power: number;
  accuracy: number;
  effect: MoveEffect;
}

export interface CreatureSpec {
  species: string;
  displayName: string;
  type: CreatureType;
  baseHp: number;
  baseAttack: number;
  baseDefense: number;
  baseSpeed: number;
  /** Move ids; every one must exist in the game's move list. */
  moves: string[];
  rarity: Rarity;
  catchRate: number;
  /** Species id, or "" for a creature that does not evolve. */
  evolvesInto: string;
  evolveLevel: number;
}

export interface ZoneSpec {
  id: string;
  displayName: string;
  encounters: string[];
  levelMin: number;
  levelMax: number;
}

export interface CreatureCollectorSpec {
  version: typeof CREATURE_SPEC_VERSION;
  title: string;
  description: string;
  rivalName: string;
  championName: string;
  partySize: number;
  starters: string[];
  creatures: CreatureSpec[];
  moves: MoveSpec[];
  zones: ZoneSpec[];
}

export interface SpecViolation { field: string; problem: string }
export interface CreatureValidationResult {
  ok: boolean;
  spec?: CreatureCollectorSpec;
  violations: SpecViolation[];
}

const SLUG_RE = /^[a-z][a-z0-9_]{0,31}$/;
/** Display names are shown, not used as identifiers, so the charset is about
 *  what the GBA font can actually draw rather than about safety. */
const NAME_RE = /^[A-Za-z0-9 '\-!?.]{1,24}$/;

const isInt = (v: unknown): v is number =>
  typeof v === "number" && Number.isInteger(v) && Number.isFinite(v);

/**
 * Validate an untrusted object into a CreatureCollectorSpec.
 *
 * Never throws. The cross-reference pass is the important half: a creature that
 * knows a move which does not exist, or a zone that spawns a species nobody
 * defined, compiles into a template that indexes past the end of an array. The
 * generator is far more likely to get a reference wrong than a number.
 */
export function validateCreatureCollectorSpec(input: unknown): CreatureValidationResult {
  const violations: SpecViolation[] = [];
  const fail = (field: string, problem: string) => violations.push({ field, problem });

  if (typeof input !== "object" || input === null) {
    return { ok: false, violations: [{ field: "spec", problem: "must be an object" }] };
  }
  const raw = input as Record<string, unknown>;
  const L = CREATURE_LIMITS;

  if (raw.version !== CREATURE_SPEC_VERSION) {
    fail("version", `must be ${CREATURE_SPEC_VERSION}`);
  }
  const str = (v: unknown, field: string, max: number) => {
    if (typeof v !== "string" || !v.trim() || v.length > max) {
      fail(field, `non-empty string, max ${max} characters`);
      return false;
    }
    return true;
  };
  str(raw.title, "title", L.titleMaxLength);
  str(raw.description, "description", L.descriptionMaxLength);
  if (typeof raw.rivalName !== "string" || !NAME_RE.test(raw.rivalName)) {
    fail("rivalName", `letters, digits and simple punctuation, max ${L.nameMaxLength}`);
  }
  if (typeof raw.championName !== "string" || !NAME_RE.test(raw.championName)) {
    fail("championName", `letters, digits and simple punctuation, max ${L.nameMaxLength}`);
  }
  if (!isInt(raw.partySize) || raw.partySize < L.partySize.min || raw.partySize > L.partySize.max) {
    fail("partySize", `integer ${L.partySize.min}..${L.partySize.max}`);
  }

  // ---- moves -------------------------------------------------------------
  const moves: MoveSpec[] = [];
  const moveIds = new Set<string>();
  if (!Array.isArray(raw.moves) || raw.moves.length < L.moves.min || raw.moves.length > L.moves.max) {
    fail("moves", `array of ${L.moves.min}..${L.moves.max} moves`);
  } else {
    raw.moves.forEach((entry, i) => {
      const m = entry as Record<string, unknown>;
      const at = `moves[${i}]`;
      if (typeof m !== "object" || m === null) return fail(at, "must be an object");
      if (typeof m.id !== "string" || !SLUG_RE.test(m.id)) fail(`${at}.id`, "lowercase slug");
      else if (moveIds.has(m.id)) fail(`${at}.id`, `duplicate move id "${m.id}"`);
      else moveIds.add(m.id);
      if (typeof m.displayName !== "string" || !NAME_RE.test(m.displayName)) {
        fail(`${at}.displayName`, `max ${L.nameMaxLength} printable characters`);
      }
      if (!CREATURE_TYPES.includes(m.type as CreatureType)) fail(`${at}.type`, "one of the eight types");
      if (!isInt(m.power) || m.power < L.movePower.min || m.power > L.movePower.max) {
        fail(`${at}.power`, `integer ${L.movePower.min}..${L.movePower.max}`);
      }
      if (!isInt(m.accuracy) || m.accuracy < L.moveAccuracy.min || m.accuracy > L.moveAccuracy.max) {
        fail(`${at}.accuracy`, `integer ${L.moveAccuracy.min}..${L.moveAccuracy.max}`);
      }
      if (!MOVE_EFFECTS.includes(m.effect as MoveEffect)) fail(`${at}.effect`, "one of the listed effects");
      // A move that neither damages nor does anything is a dead menu entry.
      if (m.power === 0 && m.effect === "none") {
        fail(`${at}`, "a move with no power must have an effect");
      }
      if (violations.length === 0 || !violations.some((v) => v.field.startsWith(at))) {
        moves.push(m as unknown as MoveSpec);
      }
    });
  }

  // ---- creatures ---------------------------------------------------------
  const creatures: CreatureSpec[] = [];
  const speciesIds = new Set<string>();
  if (!Array.isArray(raw.creatures) || raw.creatures.length < L.creatures.min || raw.creatures.length > L.creatures.max) {
    fail("creatures", `array of ${L.creatures.min}..${L.creatures.max} creatures`);
  } else {
    raw.creatures.forEach((entry, i) => {
      const c = entry as Record<string, unknown>;
      const at = `creatures[${i}]`;
      if (typeof c !== "object" || c === null) return fail(at, "must be an object");
      if (typeof c.species !== "string" || !SLUG_RE.test(c.species)) fail(`${at}.species`, "lowercase slug");
      else if (speciesIds.has(c.species)) fail(`${at}.species`, `duplicate species "${c.species}"`);
      else speciesIds.add(c.species);
      if (typeof c.displayName !== "string" || !NAME_RE.test(c.displayName)) {
        fail(`${at}.displayName`, `max ${L.nameMaxLength} printable characters`);
      }
      if (!CREATURE_TYPES.includes(c.type as CreatureType)) fail(`${at}.type`, "one of the eight types");
      for (const stat of ["baseHp", "baseAttack", "baseDefense", "baseSpeed"] as const) {
        const v = c[stat];
        if (!isInt(v) || v < L.baseStat.min || v > L.baseStat.max) {
          fail(`${at}.${stat}`, `integer ${L.baseStat.min}..${L.baseStat.max}`);
        }
      }
      if (!Array.isArray(c.moves) || c.moves.length < L.movesPerCreature.min || c.moves.length > L.movesPerCreature.max) {
        fail(`${at}.moves`, `${L.movesPerCreature.min}..${L.movesPerCreature.max} move ids`);
      }
      if (!RARITIES.includes(c.rarity as Rarity)) fail(`${at}.rarity`, "one of the rarities");
      if (!isInt(c.catchRate) || c.catchRate < L.catchRate.min || c.catchRate > L.catchRate.max) {
        fail(`${at}.catchRate`, `integer ${L.catchRate.min}..${L.catchRate.max}`);
      }
      if (typeof c.evolvesInto !== "string" || (c.evolvesInto !== "" && !SLUG_RE.test(c.evolvesInto))) {
        fail(`${at}.evolvesInto`, 'species slug, or "" for no evolution');
      }
      if (c.evolvesInto !== "" &&
          (!isInt(c.evolveLevel) || c.evolveLevel < L.evolveLevel.min || c.evolveLevel > L.evolveLevel.max)) {
        fail(`${at}.evolveLevel`, `integer ${L.evolveLevel.min}..${L.evolveLevel.max} when it evolves`);
      }
      creatures.push(c as unknown as CreatureSpec);
    });
  }

  // ---- zones -------------------------------------------------------------
  const zones: ZoneSpec[] = [];
  const zoneIds = new Set<string>();
  if (!Array.isArray(raw.zones) || raw.zones.length < L.zones.min || raw.zones.length > L.zones.max) {
    fail("zones", `array of ${L.zones.min}..${L.zones.max} zones`);
  } else {
    raw.zones.forEach((entry, i) => {
      const z = entry as Record<string, unknown>;
      const at = `zones[${i}]`;
      if (typeof z !== "object" || z === null) return fail(at, "must be an object");
      if (typeof z.id !== "string" || !SLUG_RE.test(z.id)) fail(`${at}.id`, "lowercase slug");
      else if (zoneIds.has(z.id)) fail(`${at}.id`, `duplicate zone id "${z.id}"`);
      else zoneIds.add(z.id);
      if (typeof z.displayName !== "string" || !NAME_RE.test(z.displayName)) {
        fail(`${at}.displayName`, `max ${L.nameMaxLength} printable characters`);
      }
      if (!Array.isArray(z.encounters) ||
          z.encounters.length < L.encountersPerZone.min || z.encounters.length > L.encountersPerZone.max) {
        fail(`${at}.encounters`, `${L.encountersPerZone.min}..${L.encountersPerZone.max} species`);
      }
      const lo = z.levelMin, hi = z.levelMax;
      if (!isInt(lo) || lo < L.level.min || lo > L.level.max) fail(`${at}.levelMin`, `integer ${L.level.min}..${L.level.max}`);
      if (!isInt(hi) || hi < L.level.min || hi > L.level.max) fail(`${at}.levelMax`, `integer ${L.level.min}..${L.level.max}`);
      if (isInt(lo) && isInt(hi) && lo > hi) fail(`${at}.levelMin`, "cannot be above levelMax");
      zones.push(z as unknown as ZoneSpec);
    });
  }

  // ---- cross-references --------------------------------------------------
  // Everything above validated shapes in isolation. These are the errors that
  // would otherwise reach the C++ as an out-of-range index.
  for (const c of creatures) {
    for (const id of Array.isArray(c.moves) ? c.moves : []) {
      if (typeof id !== "string" || !moveIds.has(id)) {
        fail(`creatures.${c.species}.moves`, `unknown move "${String(id)}"`);
      }
    }
    if (c.evolvesInto && !speciesIds.has(c.evolvesInto)) {
      fail(`creatures.${c.species}.evolvesInto`, `unknown species "${c.evolvesInto}"`);
    }
    if (c.evolvesInto && c.evolvesInto === c.species) {
      fail(`creatures.${c.species}.evolvesInto`, "cannot evolve into itself");
    }
  }
  for (const z of zones) {
    for (const id of Array.isArray(z.encounters) ? z.encounters : []) {
      if (typeof id !== "string" || !speciesIds.has(id)) {
        fail(`zones.${z.id}.encounters`, `unknown species "${String(id)}"`);
      }
    }
  }

  const starters = Array.isArray(raw.starters) ? raw.starters : [];
  if (starters.length !== L.starters) {
    fail("starters", `exactly ${L.starters} species`);
  } else {
    starters.forEach((id, i) => {
      if (typeof id !== "string" || !speciesIds.has(id)) fail(`starters[${i}]`, `unknown species "${String(id)}"`);
    });
    if (new Set(starters).size !== starters.length) fail("starters", "must be three different species");
  }

  // An evolution cycle makes the template loop forever the first time a
  // creature levels up inside it.
  for (const c of creatures) {
    const seen = new Set<string>([c.species]);
    let cursor = c.evolvesInto;
    while (cursor) {
      if (seen.has(cursor)) {
        fail(`creatures.${c.species}.evolvesInto`, "evolution chain loops back on itself");
        break;
      }
      seen.add(cursor);
      cursor = creatures.find((x) => x.species === cursor)?.evolvesInto ?? "";
    }
  }

  // Every zone should be reachable content: a species nothing spawns and no
  // starter grants can never be obtained, which reads to a player as a bug.
  const obtainable = new Set<string>(starters.filter((s): s is string => typeof s === "string"));
  for (const z of zones) for (const id of z.encounters ?? []) obtainable.add(id);
  for (const c of creatures) if (obtainable.has(c.species) && c.evolvesInto) obtainable.add(c.evolvesInto);
  for (const c of creatures) {
    if (!obtainable.has(c.species)) {
      fail(`creatures.${c.species}`, "cannot be obtained: no zone spawns it and nothing evolves into it");
    }
  }

  if (violations.length > 0) return { ok: false, violations };

  return {
    ok: true,
    violations: [],
    spec: {
      version: CREATURE_SPEC_VERSION,
      title: (raw.title as string).trim(),
      description: (raw.description as string).trim(),
      rivalName: raw.rivalName as string,
      championName: raw.championName as string,
      partySize: raw.partySize as number,
      starters: starters as string[],
      creatures,
      moves,
      zones,
    },
  };
}
