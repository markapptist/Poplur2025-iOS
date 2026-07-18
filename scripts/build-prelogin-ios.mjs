#!/usr/bin/env node
// Build the offline pre-login web bundle for iOS (Phase 1 web-embed migration).
//
// Reads the APPROVED, read-only Good Copy sources and emits self-contained,
// OFFLINE HTML into PreloginWeb/ (mirrors ClayMapWeb/). The cleaning step is the
// single most important non-obvious piece of work: the good-copy-welcome.html is
// a claude.ai artifact export whose wrapper has network dependencies (frame
// runtime, .screenlinks catalog, Mapbox/Clearbit fetches). Those are stripped so
// the bundled screen can never re-introduce the Mapbox offline-hang.
//
// The screen's own DOM/CSS/JS is preserved EXACTLY — only the artifact frame,
// the screen-catalog nav, and off-device network calls are removed/neutralized.
//
// Usage: node scripts/build-prelogin-ios.mjs
//   (run from the iOS worktree root; source paths are absolute to the workspace)

import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const WORKSPACE = "/Users/matrix/Developer";
const HERE = dirname(fileURLToPath(import.meta.url));
const APP_ROOT = join(HERE, "..");                 // iOS worktree root
const OUT = join(APP_ROOT, "PreloginWeb");

// ---- protected, read-only Good Copy sources ---------------------------------
const SPLASH_SRC = join(WORKSPACE, "good-copy-splash.html");
const WELCOME_SRC = join(WORKSPACE, "good-copy-welcome.html");

// ---- local assets the screens reference by absolute path --------------------
// dest is the referenced URL path (minus leading slash) so a request served by
// the custom scheme handler resolves 1:1 inside the bundle.
const ASSETS = [
  // welcome hero cube renderer (three.js) + model
  ["poplur-clay-map/node_modules/three/build/three.module.js",
   "poplur-clay-map/node_modules/three/build/three.module.js"],
  ["poplur-clay-map/node_modules/three/examples/jsm/loaders/GLTFLoader.js",
   "poplur-clay-map/node_modules/three/examples/jsm/loaders/GLTFLoader.js"],
  ["poplur-clay-map/node_modules/three/examples/jsm/utils/BufferGeometryUtils.js",
   "poplur-clay-map/node_modules/three/examples/jsm/utils/BufferGeometryUtils.js"],
  ["poplur-clay-map/public/poplur_icon_cube.glb",
   "poplur-clay-map/public/poplur_icon_cube.glb"],
  // shared ambient radio bed (splash + welcome hand the play position off)
  ["poplur-clay-map/public/radio_bed.wav",
   "poplur-clay-map/public/radio_bed.wav"],
  // splash media
  ["Poplur2025-iOS/Poplur2025/poplur_splash.mp4",
   "Poplur2025-iOS/Poplur2025/poplur_splash.mp4"],
  ["Poplur2025-iOS/Poplur2025/pop.mp3",
   "Poplur2025-iOS/Poplur2025/pop.mp3"],
  ["Poplur2025-iOS/Poplur2025/Assets.xcassets/logo.imageset/logo1.png",
   "Poplur2025-iOS/Poplur2025/Assets.xcassets/logo.imageset/logo1.png"],
];
// NOTE: MarkHead_TalkingRig.glb (106MB) and zoom_buildings.glb (8MB) are the
// Sign-up · Choose-Account 3D icons — a Phase-2 screen. They are intentionally
// NOT bundled here; offline they fail fast via the scheme handler (no hang) and
// those icons simply do not render on that not-yet-shipped screen.

function ensureDir(p) { mkdirSync(dirname(p), { recursive: true }); }

// ---- clean the welcome artifact ---------------------------------------------
function cleanWelcome(html) {
  let out = html;

  // 1. Strip the claude.ai artifact frame runtime (FRAME_PREAMBLE + capability
  //    scripts). Removes the https://claude.ai origin strings too.
  out = out.replace(/<!-- frame-runtime -->[\s\S]*?<!-- \/frame-runtime -->/, "");

  // 2. Strip the .screenlinks catalog nav (href="https://claude.ai/code/artifact/…").
  out = out.replace(/<nav class="screens">[\s\S]*?<\/nav>/, "");

  // 3. Neutralize the Mapbox business search (the offline-hang risk) — keep the
  //    graceful "couldn't reach the map" path by rejecting instead of fetching.
  out = out.replace(
    /fetch\('https:\/\/api\.mapbox\.com\/search[\s\S]*?limit=5'\)/,
    "Promise.reject(new Error('offline: map search disabled in bundled build'))"
  );

  // 4. Neutralize the Mapbox static map image (business preview) — no src.
  out = out.replace(
    /'https:\/\/api\.mapbox\.com\/styles[\s\S]*?access_token=' \+ MAPBOX_TOKEN/,
    "''"
  );

  // 5. Neutralize the Clearbit logo probe — empty src triggers the upload
  //    fallback path already in the screen.
  out = out.replace(
    /'https:\/\/logo\.clearbit\.com\/' \+ slug \+ '\.com'/,
    "''"
  );

  // 6. iphone platform skin: the welcome's dark "pill" buttons live behind
  //    `@media (prefers-color-scheme: dark)`. WebKit can pin prefers-color-scheme
  //    to light when a page declares itself light-only, so flip the artifact
  //    wrapper reset (not the screen's own style) to declare dark support. The
  //    host also sets overrideUserInterfaceStyle = .dark; both align to dark.
  out = out.replace(/:root\{color-scheme:light\}/, ":root{color-scheme:dark}");

  return out;
}

// splash.html is already a clean, self-contained page — copy verbatim.
function cleanSplash(html) { return html; }

// ---- run --------------------------------------------------------------------
if (existsSync(OUT)) rmSync(OUT, { recursive: true, force: true });
mkdirSync(OUT, { recursive: true });

const splash = cleanSplash(readFileSync(SPLASH_SRC, "utf8"));
writeFileSync(join(OUT, "splash.html"), splash);

const welcome = cleanWelcome(readFileSync(WELCOME_SRC, "utf8"));
writeFileSync(join(OUT, "welcome.html"), welcome);

for (const [src, dest] of ASSETS) {
  const from = join(WORKSPACE, src);
  const to = join(OUT, dest);
  if (!existsSync(from)) { console.warn(`[skip missing] ${src}`); continue; }
  ensureDir(to);
  copyFileSync(from, to);
}

// ---- verify: zero network refs in the cleaned welcome -----------------------
const httpHits = (welcome.match(/https?:\/\//g) || []).length;
if (httpHits > 0) {
  const lines = welcome.split("\n")
    .map((l, i) => [i + 1, l])
    .filter(([, l]) => /https?:\/\//.test(l))
    .map(([n, l]) => `  line ${n}: ${l.slice(0, 120)}`);
  console.error(`FAIL: welcome.html still has ${httpHits} http ref(s):\n${lines.join("\n")}`);
  process.exit(1);
}

console.log("PreloginWeb built:");
console.log(`  splash.html   ${splash.length} bytes`);
console.log(`  welcome.html  ${welcome.length} bytes  (http refs: ${httpHits})`);
console.log(`  assets:       ${ASSETS.length} mirrored`);
