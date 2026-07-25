// Build the offline post-login LOADING web bundle for iOS (Phase 3 web-embed).
//
// The prototype's approved post-login load screen is the web "Loading" screen of
// poplur-prelogin-flow.html (clay globe + wordmark + rotating clay messages,
// three.js). We render that EXACT screen inside a WKWebView after sign-in —
// replacing the old auth_transition.mp4 — the same way pre-login embeds the
// approved splash/welcome. See scripts/build-prelogin-ios.mjs for the sibling.
//
// This reuses the pre-login bundle's already-shipped three.js + DRACOLoader +
// draco decoder (PreloginWeb/poplur-clay-map/node_modules/three/...), so the only
// new payload is the two Draco-compressed models. The cleaning step:
//   1. strips the model <link rel=preload> (uncompressed source paths),
//   2. rewrites the two model URLs to the bundled compressed copies,
//   3. injects DRACOLoader on the loading GLTFLoader (models are now Draco),
//   4. defaults ?embed to "Loading" so it renders only that screen offline,
//   5. guards the WebGLRenderer so a GPU-less context can't blank the screen
//      (the 2D worldmap + progress + messages still show — matches the
//      welcome cube's POPLUR_WEBGL_OK fallback).
// The screen's own DOM/CSS/JS is otherwise preserved EXACTLY.

import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const WORKSPACE = "/Users/matrix/Developer";
const HERE = dirname(fileURLToPath(import.meta.url));
const APP_ROOT = join(HERE, "..");                 // iOS worktree root
const OUT = join(APP_ROOT, "PreloginWeb");         // shares the pre-login bundle root

const FLOW_SRC = join(WORKSPACE, ".claude/artifacts/poplur-prelogin-flow.html");
// The UNCOMPRESSED 2MB lite globe is the known-good asset (memory: it "renders
// smoothly"; the Draco variant is unverified and computeVertexNormals must NOT be
// called on it). The 22MB wordmark is DROPPED — it was the load bottleneck and
// "poplur" is already baked into the globe's clay texture.
const MODELS_SRC_DIR = join(WORKSPACE, ".claude/artifacts/models");
const COMPRESSED_DIR = join(WORKSPACE, ".codex/prelogin-assets-compressed/loading");
const PUBLIC_DIR = join(OUT, "poplur-clay-map/public");

const MODELS = [
  ["poplur-globe-lite.glb", "/poplur-clay-map/public/poplur-globe-lite.glb"],
  // The "poplur" wordmark, Draco-compressed to 184KB (the 22MB original was the
  // old bottleneck; the real offender was the 111MB MarkHead rig — see below).
  ["poplur-wordmark.glb", "/poplur-clay-map/public/poplur-wordmark.glb"],
];

const DRACO_DECODER_PATH = "/poplur-clay-map/node_modules/three/examples/jsm/libs/draco/";

function ensureDir(p) { mkdirSync(p, { recursive: true }); }

function clean(html) {
  let out = html;

  // 1. Drop the model preload links — they point at the uncompressed source
  //    paths (/.claude/artifacts/models/…) which are not in the bundle.
  out = out.replace(/\s*<link rel="preload" as="fetch" href="\/\.claude\/artifacts\/models\/[^"]*">/g, "");

  // 2. Rewrite the globe URL to the bundled copy, and DROP the wordmark load
  //    entirely (removed from the approved loading screen — bottleneck; "poplur"
  //    is baked into the globe texture).
  out = out.replace(/\/\.claude\/artifacts\/models\/poplur-globe-lite\.glb/g, MODELS[0][1]);
  out = out.replace(/\/\.claude\/artifacts\/models\/poplur-wordmark\.glb/g, MODELS[1][1]);

  // 3. Inject DRACOLoader on the loading GLTFLoader (the second module script —
  //    uniquely identified by `const loadingCanvas=`). The compressed models are
  //    Draco, so the plain GLTFLoader would fail to decode without this.
  const loadingImport =
    `import {GLTFLoader} from "three/addons/loaders/GLTFLoader.js";\nconst loadingCanvas=document.querySelector`;
  if (!out.includes(loadingImport)) throw new Error("loading module import anchor not found — flow changed");
  out = out.replace(
    loadingImport,
    `import {GLTFLoader} from "three/addons/loaders/GLTFLoader.js";\nimport {DRACOLoader} from "three/addons/loaders/DRACOLoader.js";\nconst loadingCanvas=document.querySelector`
  );
  const loaderDecl = `const loader=new GLTFLoader();`;
  if (!out.includes(loaderDecl)) throw new Error("loading GLTFLoader decl not found — flow changed");
  out = out.replace(
    loaderDecl,
    `const loader=new GLTFLoader();\n  const __loadingDraco=new DRACOLoader();__loadingDraco.setDecoderPath("${DRACO_DECODER_PATH}");loader.setDRACOLoader(__loadingDraco);`
  );

  // 4. Default ?embed to "Loading" so the bundle renders that screen with no query
  //    (the app also loads it as loading.html?embed=Loading — belt and suspenders).
  out = out.replace(
    /new URLSearchParams\(location\.search\)\.get\("embed"\)/g,
    `(new URLSearchParams(location.search).get("embed")||"Loading")`
  );

  // 5. Guard the loading WebGLRenderer so a GPU-less context (e.g. the software
  //    simulator) can't throw and blank the screen — the 2D worldmap, progress
  //    bar and rotating messages still render.
  const rendererLine = `  const renderer=new THREE.WebGLRenderer({canvas:loadingCanvas,alpha:true,antialias:true,preserveDrawingBuffer:true});`;
  if (!out.includes(rendererLine)) throw new Error("loading renderer line not found — flow changed");
  out = out.replace(rendererLine, `  try{\n${rendererLine}`);
  const tickClose = `  tick();\n  // The Loading screen holds`;
  if (!out.includes(tickClose)) throw new Error("loading tick() anchor not found — flow changed");
  out = out.replace(
    tickClose,
    `  tick();\n  }catch(__glErr){console.warn("[loading] globe unavailable — 2D fallback",__glErr);}\n  // The Loading screen holds`
  );

  // 5b. Strip the OTHER screens' 3D assets. ?embed=Loading renders one screen,
  //     but the flow's account-model loader still fetched every canvas it found:
  //     MarkHead_TalkingRig.glb (111MB!) + zoom_buildings.glb (8.6MB). On device
  //     that starved the WebView — the globe/wordmark never appeared and the
  //     clay progress bar stalled. Renaming the attribute leaves the markup
  //     untouched while the loader's querySelectorAll finds nothing.
  out = out.replace(/data-account-model=/g, "data-account-model-off=");

  // 6. Neutralize the live radio-station lookup (radio-browser.info) — a network
  //    call that fires on load and would hang/fail offline. Resolve to an empty
  //    station list so the ambient radio simply stays quiet on the loading screen.
  out = out.replace(
    /fetch\('https:\/\/[a-z0-9]+\.api\.radio-browser\.info\/[^']*'\)/g,
    "Promise.resolve({ json: function () { return Promise.resolve([]) } })"
  );

  return out;
}

// ---- run ---------------------------------------------------------------------
const raw = readFileSync(FLOW_SRC, "utf8");
const cleaned = clean(raw);

// Offline assertion: no residual off-device network references.
const http = (cleaned.match(/https?:\/\//g) || []).length;
if (http > 0) {
  const hits = [...cleaned.matchAll(/https?:\/\/[^"'\s)]*/g)].slice(0, 8).map(m => m[0]);
  throw new Error(`loading.html still has ${http} http refs (offline hardening failed): ${hits.join(", ")}`);
}

ensureDir(OUT);
ensureDir(PUBLIC_DIR);
writeFileSync(join(OUT, "loading.html"), cleaned);

for (const [name] of MODELS) {
  const compressed = join(COMPRESSED_DIR, name);
  const src = existsSync(compressed) ? compressed : join(MODELS_SRC_DIR, name);
  if (!existsSync(src)) throw new Error(`model missing: ${src}`);
  copyFileSync(src, join(PUBLIC_DIR, name));
}
// The Draco-compressed wordmark from an earlier pass must not linger in the bundle.
try { rmSync(join(PUBLIC_DIR, "poplur-wordmark.glb")); } catch {}

// Sanity: the reused three.js + draco decoder must already be in the bundle.
for (const rel of [
  "poplur-clay-map/node_modules/three/build/three.module.js",
  "poplur-clay-map/node_modules/three/examples/jsm/loaders/DRACOLoader.js",
  "poplur-clay-map/node_modules/three/examples/jsm/libs/draco/draco_decoder.wasm",
]) {
  if (!existsSync(join(OUT, rel))) {
    console.warn(`[build-loading-ios] WARNING: expected reused asset missing: ${rel} — run build-prelogin-ios.mjs first`);
  }
}

console.log(`[build-loading-ios] wrote loading.html (${(cleaned.length / 1024).toFixed(0)} KB), 0 http refs`);
console.log(`[build-loading-ios] bundled models: ${MODELS.map(m => m[0]).join(", ")} → ${PUBLIC_DIR}`);
