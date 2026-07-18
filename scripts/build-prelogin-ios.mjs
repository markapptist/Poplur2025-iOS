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

  // 7. WebGL/GPU-less hardening. The hero cube (and the account-icon icons) build
  //    a THREE.WebGLRenderer. On a software-GPU simulator or a context-starved
  //    device, WebGL is unavailable and the constructor THROWS — and on WKWebView
  //    an uncaught error blanks the ENTIRE web view (the reported black screen).
  //    Detect WebGL once up front; if it is missing, skip every three.js renderer
  //    and fire the intro-ready hook so the choreography still reveals the copy on
  //    schedule (there is no CSS cube — the source says so — the stage just stays
  //    empty, which is the approved GPU-less render). Also wrap each renderer
  //    construction in try/catch as a belt-and-suspenders guard.
  out = out.replace(
    "const loader = new GLTFLoader();",
    `const loader = new GLTFLoader();

// Bundled-build hardening: WebGL may be unavailable (software-GPU simulator or a
// context-starved device). Constructing THREE.WebGLRenderer would throw, and an
// uncaught error blanks the whole WKWebView. Detect once; if missing, skip the
// three.js cube entirely and reveal the intro on schedule (no CSS cube exists —
// the stage stays empty, the approved GPU-less render).
const POPLUR_WEBGL_OK = (function () {
  try {
    var c = document.createElement('canvas');
    return !!(window.WebGLRenderingContext &&
      (c.getContext('webgl2') || c.getContext('webgl') || c.getContext('experimental-webgl')));
  } catch (e) { return false; }
})();
if (!POPLUR_WEBGL_OK && window.__poplurCubeGLReady) {
  try { window.__poplurCubeGLReady(); } catch (e) {}
}`
  );

  // 7a. Only run the account-icon renderers when WebGL is present.
  out = out.replace(
    'document.querySelectorAll("canvas[data-account-model]").forEach(canvas => {',
    'if (POPLUR_WEBGL_OK) document.querySelectorAll("canvas[data-account-model]").forEach(canvas => {'
  );

  // 7b. Non-fatal account-icon renderer construction.
  out = out.replace(
    '  const renderer = new THREE.WebGLRenderer({canvas, alpha:true, antialias:true, powerPreference:"low-power", preserveDrawingBuffer:true});',
    '  let renderer; try { renderer = new THREE.WebGLRenderer({canvas, alpha:true, antialias:true, powerPreference:"low-power", preserveDrawingBuffer:true}); } catch (e) { canvas.closest(".account-3d-icon")?.classList.add("model-error"); return; }'
  );

  // 7c. Skip the hero-cube renderer when WebGL is absent.
  out = out.replace(
    "  if (!stage || !canvas) return;",
    "  if (!stage || !canvas || !POPLUR_WEBGL_OK) return;"
  );

  // 7d. Non-fatal hero-cube renderer construction — fall back to the (empty)
  //     stage and still fire the intro-ready hook instead of throwing.
  out = out.replace(
    "  const renderer = new THREE.WebGLRenderer({canvas, alpha:true, antialias:true});",
    "  let renderer; try { renderer = new THREE.WebGLRenderer({canvas, alpha:true, antialias:true}); } catch (e) { if (window.__poplurCubeGLReady) { try { window.__poplurCubeGLReady(); } catch (e2) {} } return; }"
  );

  return out;
}

// splash.html is already a clean, self-contained page. Only drop the two
// `<link rel=preload>` hints for GLBs that are NOT bundled (MarkHead 106MB,
// zoom_buildings 8MB — Phase-2 account-icon assets), so they don't emit 404
// preload warnings. Everything else is verbatim; still zero network refs.
function cleanSplash(html) {
  let out = html;
  out = out.replace(
    /\n\s*<link rel="preload" as="fetch" href="\/Poplur2025-iOS\/Poplur2025\/MarkHead_TalkingRig\.glb">/,
    ""
  );
  out = out.replace(
    /\n\s*<link rel="preload" as="fetch" href="\/poplur-clay-map\/public\/zoom_buildings\.glb">/,
    ""
  );
  return out;
}

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
