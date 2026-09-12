"use strict";

/**
 * functions-digest cannot import functions/src (tsconfig rootDir is "src" and
 * `gcloud run deploy --source .` uploads only this directory), so the two pure
 * modules the algorithm digest depends on are byte-copied into src/shared/ and
 * pinned by scripts/testSharedSync.js. Three knobs live in modules that cannot
 * be copied (they import firebase-admin); those are lifted from the source
 * text by anchored patterns into sync-stamp.json — never typed by hand, so a
 * refactor that moves one breaks the deploy, not the desk's numbers.
 *
 *   node scripts/syncShared.js
 */
const fs = require("node:fs");
const path = require("node:path");
const { createHash } = require("node:crypto");

const DIGEST_ROOT = path.resolve(__dirname, "..");
const FUNCTIONS_SRC = path.resolve(DIGEST_ROOT, "..", "functions", "src");
const SHARED_DIR = path.join(DIGEST_ROOT, "src", "shared");
const STAMP_PATH = path.join(SHARED_DIR, "sync-stamp.json");

/** Copied byte for byte; both import nothing but node:crypto. */
const COPIES = ["postEngagementPolicy.ts", "syntheticIdentity.ts"];

/** Anchored patterns (algorithm-desk-design.md §1.1). The stress half-life is
 *  lifted the same way: syntheticRetentionPolicy.ts imports the daily policy
 *  and cannot be copied either. */
const EXTRACTIONS = {
  seedMeters: { file: "accountRadius.ts", pattern: /^export const POST_DISCOVERY_SEED_METERS = ([\d_]+);/m },
  boostDefaultMeters: { file: "index.ts", pattern: /positiveInt\(body\.radiusMetersAdded, (\d+)\)/ },
  boostDefaultHours: { file: "index.ts", pattern: /positiveInt\(body\.durationHours, (\d+)\)/ },
  stressHalfLifeHours: { file: "syntheticRetentionPolicy.ts", pattern: /^export const SYNTHETIC_RADIUS_HALF_LIFE_HOURS = (\d+);/m },
};

function sha256(text) {
  return createHash("sha256").update(text).digest("hex");
}

function readSource(file) {
  return fs.readFileSync(path.join(FUNCTIONS_SRC, file), "utf8");
}

function lineOf(text, index) {
  return text.slice(0, index).split("\n").length;
}

/** Runs every pattern; throws on the first miss so a deploy cannot ship a
 *  digest that reads a knob from nowhere. */
function extractKnobs(read = readSource) {
  const extracted = { sourceLines: {} };
  for (const [name, { file, pattern }] of Object.entries(EXTRACTIONS)) {
    const text = read(file);
    const match = pattern.exec(text);
    if (!match) throw new Error(`syncShared: pattern for ${name} missed in functions/src/${file}`);
    extracted[name] = Number(match[1].replace(/_/g, ""));
    extracted.sourceLines[name] = `functions/src/${file}:${lineOf(text, match.index)}`;
  }
  return extracted;
}

function sync() {
  fs.mkdirSync(SHARED_DIR, { recursive: true });
  const shas = {};
  for (const file of COPIES) {
    const source = readSource(file);
    fs.writeFileSync(path.join(SHARED_DIR, file), source);
    shas[file] = sha256(source);
  }
  const stamp = {
    syncedAtMillis: Date.now(),
    policySha256: shas["postEngagementPolicy.ts"],
    identitySha256: shas["syntheticIdentity.ts"],
    extracted: extractKnobs(),
  };
  fs.writeFileSync(STAMP_PATH, `${JSON.stringify(stamp, null, 2)}\n`);
  return stamp;
}

module.exports = { COPIES, EXTRACTIONS, FUNCTIONS_SRC, SHARED_DIR, STAMP_PATH, extractKnobs, readSource, sha256, sync };

if (require.main === module) {
  const stamp = sync();
  console.log(`synced ${COPIES.join(", ")} → src/shared; extracted ${JSON.stringify(stamp.extracted)}`);
}
