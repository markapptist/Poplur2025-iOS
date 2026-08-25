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
// Each entry is [absoluteSource, destRelativeToBundle]. dest is the referenced
// URL path (minus leading slash) so a request served by the custom scheme
// handler resolves 1:1 inside the bundle. Because PreloginWeb is a *folder*
// reference in project.pbxproj (lastKnownFileType = folder, like ClayMapWeb),
// every file mirrored here ships in the app bundle automatically — no per-file
// pbxproj build-file entry is needed.
const COMPRESSED_DIR = join(WORKSPACE, ".codex/prelogin-assets-compressed");
const CLAYMAP_PUBLIC = join(WORKSPACE, "poplur-clay-map/public");

const ASSETS = [
  // welcome hero cube renderer (three.js).
  [join(WORKSPACE, "poplur-clay-map/node_modules/three/build/three.module.js"),
   "poplur-clay-map/node_modules/three/build/three.module.js"],
  [join(WORKSPACE, "poplur-clay-map/node_modules/three/examples/jsm/loaders/GLTFLoader.js"),
   "poplur-clay-map/node_modules/three/examples/jsm/loaders/GLTFLoader.js"],
  [join(WORKSPACE, "poplur-clay-map/node_modules/three/examples/jsm/utils/BufferGeometryUtils.js"),
   "poplur-clay-map/node_modules/three/examples/jsm/utils/BufferGeometryUtils.js"],

  // Phase-2: Draco decoder. The compressed models use KHR_draco_mesh_compression,
  // so the GLTFLoader needs a DRACOLoader + the wasm decoder. Bundle all three
  // from the SAME vendored three.js version, offline, so the hero cube and the
  // Choose-Account models decode when WebGL is available. The decoder dir matches
  // the welcome's DRACOLoader.setDecoderPath (libs/draco/). Without these the
  // meshes cannot decode and the 3D silently falls back to 2D even on real HW.
  [join(WORKSPACE, "poplur-clay-map/node_modules/three/examples/jsm/loaders/DRACOLoader.js"),
   "poplur-clay-map/node_modules/three/examples/jsm/loaders/DRACOLoader.js"],
  [join(WORKSPACE, "poplur-clay-map/node_modules/three/examples/jsm/libs/draco/draco_wasm_wrapper.js"),
   "poplur-clay-map/node_modules/three/examples/jsm/libs/draco/draco_wasm_wrapper.js"],
  [join(WORKSPACE, "poplur-clay-map/node_modules/three/examples/jsm/libs/draco/draco_decoder.wasm"),
   "poplur-clay-map/node_modules/three/examples/jsm/libs/draco/draco_decoder.wasm"],

  // Phase-2: COMPRESSED 3D models (user-approved compress + bundle all).
  // gltf-transform webp@1024 + Draco, staged in .codex/prelogin-assets-compressed/.
  // welcome hero cube — REPLACES the 33MB uncompressed model with the 859KB one.
  [join(COMPRESSED_DIR, "poplur_icon_cube.glb"),
   "poplur-clay-map/public/poplur_icon_cube.glb"],
  // Sign-up · Choose-Account 3D icons — now under the 100MB cap, so they ship
  // and render offline (MarkHead heads + Poplur building). welcome.html
  // references these two by the paths on the right.
  [join(COMPRESSED_DIR, "MarkHead_TalkingRig.glb"),
   "Poplur2025-iOS/Poplur2025/MarkHead_TalkingRig.glb"],
  [join(COMPRESSED_DIR, "zoom_buildings.glb"),
   "poplur-clay-map/public/zoom_buildings.glb"],

  // Phase-2: static 2D cube image — shown in place of the GL cube canvas when
  // WebGL is unavailable (see cleanWelcome 2D-fallback injection).
  [join(CLAYMAP_PUBLIC, "clay_cube.png"),
   "poplur-clay-map/public/clay_cube.png"],

  // Post-sign-up gender pane (paneGender): the same already-shipping post-login
  // navigator heads, already small enough to bundle directly — no separate
  // compression pass needed, unlike zoom_buildings.glb above.
  [join(CLAYMAP_PUBLIC, "poplur_mark_head_navigator.glb"),
   "poplur-clay-map/public/poplur_mark_head_navigator.glb"],
  [join(CLAYMAP_PUBLIC, "poplur_female_head_navigator.glb"),
   "poplur-clay-map/public/poplur_female_head_navigator.glb"],

  // shared ambient radio bed (splash + welcome hand the play position off)
  [join(CLAYMAP_PUBLIC, "radio_bed.wav"),
   "poplur-clay-map/public/radio_bed.wav"],
  // splash media
  [join(WORKSPACE, "Poplur2025-iOS/Poplur2025/poplur_splash.mp4"),
   "Poplur2025-iOS/Poplur2025/poplur_splash.mp4"],
  [join(WORKSPACE, "Poplur2025-iOS/Poplur2025/pop.mp3"),
   "Poplur2025-iOS/Poplur2025/pop.mp3"],
  [join(WORKSPACE, "Poplur2025-iOS/Poplur2025/Assets.xcassets/logo.imageset/logo1.png"),
   "Poplur2025-iOS/Poplur2025/Assets.xcassets/logo.imageset/logo1.png"],
  // Keep the loading globe bundled for the post-login Loading screen. The
  // splash no longer preloads it; the destination screen requests it on demand.
  [join(WORKSPACE, ".claude/artifacts/models/poplur-globe-lite.glb"),
   ".claude/artifacts/models/poplur-globe-lite.glb"],
];

function ensureDir(p) { mkdirSync(dirname(p), { recursive: true }); }

// ---- clean the welcome artifact ---------------------------------------------
// iOS WKWebView can ignore `object-fit: cover` on <video>, letterboxing it
// (black bars top/bottom) while Android honours it — hence "fine on Android".
// Size the element to overflow and centre it instead, so cover behaviour never
// depends on object-fit support.
const coverVideoCss = html => html.replace(
  'video { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; display: block; z-index: 1; }',
  'video { position: absolute; inset: 0; margin: auto; width: 100vw; height: 177.78vw; min-width: 56.25vh; min-height: 100vh; object-fit: cover; display: block; z-index: 1; }'
)

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

  // 6a. Keyboard hardening (BUG-1). The pre-login is a fixed full-screen layout;
  //     when a field is focused iOS both (a) auto-zooms into sub-16px inputs and
  //     (b) scrolls the layout up to clear the keyboard — both displace the UI.
  //     `interactive-widget=overlays-content` leaves the approved layout viewport
  //     at its pre-keyboard height instead of squeezing the form. The canonical
  //     screen also freezes height-only focused-input resizes; maximum-scale=1 /
  //     user-scalable=no disable focus auto-zoom. Native additionally clamps the
  //     scrollView offset to zero, so the header/logo never flies off-screen.
  out = out.replace(
    'content="width=device-width,initial-scale=1"',
    'content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,interactive-widget=overlays-content"'
  );
  out = out.replace(
    'interactive-widget=resizes-content',
    'interactive-widget=overlays-content',
  );

  // 7. WebGL hardening. Account previews may be skipped on a GPU-less device,
  //    but the approved login cube must never be replaced by the old generic
  //    clay_cube.png fallback. The canonical source owns a recovery watchdog
  //    that remounts the exact login GLB on constructor, load, or context-loss
  //    failure until the device can provide a context.
  // 6b. Draco decoder wiring — IDEMPOTENT. The bundled models are Draco-compressed
  //     (KHR_draco_mesh_compression), so the GLTFLoader needs a DRACOLoader + the
  //     wasm decoder (bundled offline by ASSETS at libs/draco/). The approved Good
  //     Copy source now wires this itself; only inject when it does NOT, so we
  //     never emit a duplicate `import {DRACOLoader}` (a module SyntaxError). Both
  //     paths point at the SAME decoder dir we bundle.
  const DRACO_PATH = "/poplur-clay-map/node_modules/three/examples/jsm/libs/draco/";
  if (!/import\s*\{\s*DRACOLoader\s*\}/.test(out)) {
    out = out.replace(
      'import {GLTFLoader} from "three/addons/loaders/GLTFLoader.js";',
      'import {GLTFLoader} from "three/addons/loaders/GLTFLoader.js";\nimport {DRACOLoader} from "three/addons/loaders/DRACOLoader.js";'
    );
  }
  if (!/setDRACOLoader/.test(out)) {
    out = out.replace(
      "const loader = new GLTFLoader();",
      `const loader = new GLTFLoader();

// Phase-2 fallback wiring (only when the source did not already wire it): the
// bundled models are Draco-compressed, so give the GLTFLoader a DRACOLoader whose
// wasm decoder is bundled offline. Covers both the hero cube and Choose-Account.
const __poplurDraco = new DRACOLoader();
__poplurDraco.setDecoderPath("${DRACO_PATH}");
loader.setDRACOLoader(__poplurDraco);`
    );
  }

  out = out.replace(
    "const loader = new GLTFLoader();",
    `const loader = new GLTFLoader();

// Bundled-build hardening for one-shot account previews. The hero login cube
// deliberately does not use this one-time decision: its canonical recovery
// watchdog replaces the canvas and retries the real GLB when WebGL returns.
const POPLUR_WEBGL_OK = (function () {
  try {
    var c = document.createElement('canvas');
    return !!(window.WebGLRenderingContext &&
      (c.getContext('webgl2') || c.getContext('webgl') || c.getContext('experimental-webgl')));
  } catch (e) { return false; }
})();`
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

  // 9. Native bridge (Phase-2 web-embed). Define window.poplurBridge before any
  //    handler wiring so permission dialogs + flow completion can post a defined
  //    action set to the host. iOS: window.webkit.messageHandlers.poplur; Android
  //    parity: PoplurNative.onAction(action, payloadJson). No network ref.
  out = out.replace(
    "<script>\n  let stableViewportWidth = innerWidth",
    `<script>
  // ── Native bridge (Phase-2 web-embed) ──────────────────────────────────────
  // Defined action set (identical on iOS + Android):
  //   signIn | signUp | requestPermission(permission: camera|location) | complete | pop
  //   radioStations({callbackId}) -> window.__poplurStationsResult(callbackId, list)
  // iOS delivery:     window.webkit.messageHandlers.poplur.postMessage({action, ...})
  // Android delivery: window.PoplurNative.onAction(action, JSON.stringify(rest))
  // Auth + OS permission prompts stay Phase-3 stubs on the native side (log, no
  // faked success); only the flow-completion 'complete' action drives the
  // native handoff to the existing post-login path.
  window.poplurBridge = (function () {
    function post(msg) {
      try {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.poplur) {
          window.webkit.messageHandlers.poplur.postMessage(msg);
          return true;
        }
      } catch (e) {}
      try {
        if (window.PoplurNative && typeof window.PoplurNative.onAction === 'function') {
          var rest = {}; for (var k in msg) { if (k !== 'action') rest[k] = msg[k]; }
          window.PoplurNative.onAction(msg.action, JSON.stringify(rest));
          return true;
        }
      } catch (e) {}
      return false;
    }
    function assign(base, extra) { if (extra) { for (var k in extra) base[k] = extra[k]; } return base; }
    return {
      signIn: function (d) { return post(assign({ action: 'signIn' }, d)); },
      signUp: function (d) { return post(assign({ action: 'signUp' }, d)); },
      requestPermission: function (permission, d) { return post(assign({ action: 'requestPermission', permission: permission }, d)); },
      complete: function (d) { return post(assign({ action: 'complete' }, d)); },
      pop: function () { return post({ action: 'pop' }); },
      stations: function (d) { return post(assign({ action: 'radioStations' }, d)); }
    };
  })();

  // ── Live radio lookup, through the bridge ──────────────────────────────────
  // The page's own station lookup is a raw fetch that cannot run inside an
  // offline bundle, so native makes the call and hands the list back. The
  // resolved object is shaped like a fetch Response purely so the page's
  // existing .then(function (r) { return r.json() }) chain is left untouched.
  window.__poplurStationsPending = {};
  window.__poplurStationsResult = function (id, list) {
    var fn = window.__poplurStationsPending[id];
    if (fn) fn(list);
  };
  window.__poplurTuneStations = function () {
    return new Promise(function (resolve) {
      var id = 'st' + Date.now() + Math.random().toString(36).slice(2, 8);
      var settled = false;
      function finish(list) {
        if (settled) return;
        settled = true;
        delete window.__poplurStationsPending[id];
        resolve({ json: function () { return Promise.resolve(list || []); } });
      }
      window.__poplurStationsPending[id] = finish;
      // An empty list is the graceful outcome: tryNext() simply never tunes and
      // pre-login stays silent, exactly as it did before this existed. The
      // promise must never be left hanging — an unresolved lookup is what
      // stranded the clay map offline, and this flow gates a launch screen.
      setTimeout(function () { finish([]); }, 6000);
      if (!window.poplurBridge || !window.poplurBridge.stations({ callbackId: id })) finish([]);
    });
  };
  let stableViewportWidth = innerWidth`
  );

  // 9a. Sign-in (password) → post {email, password} to REAL native Firebase auth.
  //     Do NOT fake success: on a native host the auth-state listener transitions
  //     the app on success and window.poplurAuthResult surfaces errors. Only in a
  //     plain-browser preview (no native host, post() returns falsy) do we keep
  //     the prototype success gesture.
  out = out.replace(
    "      if (/.+@.+\\..+/.test(email) && pass.length >= 4) cubeSuccess()",
    "      if (/.+@.+\\..+/.test(email) && pass.length >= 4) { var __p = window.poplurBridge && poplurBridge.signIn({ email: email, password: pass, method: 'password' }); if (!__p) cubeSuccess() }"
  );

  // 9b. Face ID sign-in → post {method:'faceid'} (native replies via
  //     poplurAuthResult that it isn't wired yet — no faked success). Browser
  //     preview keeps the prototype gesture.
  out = out.replace(
    "    document.getElementById('faceIdBtn').addEventListener('click', cubeSuccess)",
    "    document.getElementById('faceIdBtn').addEventListener('click', function () { var __p = window.poplurBridge && poplurBridge.signIn({ method: 'faceid' }); if (!__p) cubeSuccess() })"
  );

  // 9c. Sign-up completion → post {email, password, accountType} to REAL native
  //     Firebase createUser (email/password captured from the Create-login pane,
  //     which stays in the DOM). No faked success on a native host: success
  //     transitions via the auth-state listener, errors arrive via
  //     window.poplurAuthResult. Browser preview (no native host) keeps the
  //     approved prototype choreography. Also defines poplurAuthResult in-scope.
  out = out.replace(
    "    function finishSignup(message) {\n      cubeSuccess()\n      if (window.__poplurShowAlert) window.__poplurShowAlert(message, 'Nice!')\n      setTimeout(function () { setPane(0) }, 1400)\n    }",
    "    function finishSignup(message) {\n" +
    "      var acctType = isBusiness() ? 'business' : 'personal'\n" +
    "      var suEmail = '', suPass = ''\n" +
    "      try {\n" +
    "        var __em = document.querySelector('#paneCreateLogin input[type=\"email\"]')\n" +
    "        var __pw = document.querySelectorAll('#paneCreateLogin input[type=\"password\"]')\n" +
    "        suEmail = __em ? __em.value.trim() : ''\n" +
    "        suPass = (__pw && __pw[0]) ? __pw[0].value : ''\n" +
    "      } catch (e) {}\n" +
    "      var __posted = window.poplurBridge && poplurBridge.signUp({ email: suEmail, password: suPass, accountType: acctType, profilePhotoDataURI: acctType === 'personal' ? pendingProfilePhotoDataURI : '' })\n" +
    "      if (!__posted) {\n" +
    "        cubeSuccess()\n" +
    "        if (window.__poplurShowAlert) window.__poplurShowAlert(message, 'Nice!')\n" +
    "        setTimeout(function () { setPane(0) }, 1400)\n" +
    "      }\n" +
    "    }\n" +
    "    // Native -> web auth result: real Firebase sign-in/up outcome.\n" +
    "    // Success -> brief gesture (the native app is already transitioning);\n" +
    "    // failure -> the approved error banner + cube shake. In-scope so it can\n" +
    "    // reach cubeSuccess()/signupError().\n" +
    "    window.poplurAuthResult = function (res) {\n" +
    "      if (res && res.ok) { cubeSuccess() }\n" +
    "      else { signupError((res && res.error) || 'Something went wrong. Please try again.') }\n" +
    "    }"
  );

  // 9c-1. The approved personal sign-up screen only previews its selected
  //       photo. Preserve that choice for the native signUp bridge, but never
  //       send the original full-resolution camera image through WKScriptMessage:
  //       canvas-normalize it to JPEG, cap its longest edge, and keep reducing
  //       quality/size until the decoded payload is below the native limit.
  const personalPhotoSource = `    // ── Personal: a profile photo is required before finishing ──
    var photoSet = false
    document.getElementById('photoInput').addEventListener('change', function (e) {
      var file = e.target.files && e.target.files[0]
      if (!file) return
      var reader = new FileReader()
      reader.onload = function () {
        var img = new Image(); img.src = reader.result
        var circle = document.getElementById('photoCircle')
        circle.textContent = ''; circle.appendChild(img)
        photoSet = true
      }
      reader.readAsDataURL(file)
    })`;
  const personalPhotoBundle = `    // ── Personal: a profile photo is required before finishing ──
    var photoSet = false
    var pendingProfilePhotoDataURI = ''
    var PROFILE_PHOTO_MAX_EDGE = 1024
    var PROFILE_PHOTO_MAX_BYTES = 900000

    function profilePhotoByteLength(dataURI) {
      var comma = dataURI.indexOf(',')
      if (comma < 0) return Infinity
      var encoded = dataURI.length - comma - 1
      var padding = dataURI.endsWith('==') ? 2 : (dataURI.endsWith('=') ? 1 : 0)
      return Math.floor(encoded * 3 / 4) - padding
    }

    function encodeProfilePhotoJPEG(image) {
      var sourceWidth = image.naturalWidth || image.width || 0
      var sourceHeight = image.naturalHeight || image.height || 0
      if (!sourceWidth || !sourceHeight) return ''
      var scale = Math.min(1, PROFILE_PHOTO_MAX_EDGE / Math.max(sourceWidth, sourceHeight))
      var width = Math.max(1, Math.round(sourceWidth * scale))
      var height = Math.max(1, Math.round(sourceHeight * scale))
      var quality = 0.84
      var canvas = document.createElement('canvas')

      for (var attempt = 0; attempt < 14; attempt++) {
        canvas.width = width
        canvas.height = height
        var context = canvas.getContext('2d')
        if (!context) return ''
        context.imageSmoothingEnabled = true
        context.imageSmoothingQuality = 'high'
        context.fillStyle = '#ffffff'
        context.fillRect(0, 0, width, height)
        context.drawImage(image, 0, 0, width, height)
        var encoded = canvas.toDataURL('image/jpeg', quality)
        if (encoded.indexOf('data:image/jpeg;base64,') === 0 &&
            profilePhotoByteLength(encoded) <= PROFILE_PHOTO_MAX_BYTES) return encoded

        if (quality > 0.58) {
          quality = Math.max(0.58, quality - 0.08)
        } else {
          width = Math.max(1, Math.round(width * 0.82))
          height = Math.max(1, Math.round(height * 0.82))
          quality = 0.76
        }
      }
      return ''
    }

    document.getElementById('photoInput').addEventListener('change', function (e) {
      var file = e.target.files && e.target.files[0]
      if (!file) return
      photoSet = false
      pendingProfilePhotoDataURI = ''
      var reader = new FileReader()
      reader.onerror = function () { signupError('That photo could not be read. Choose another photo.') }
      reader.onload = function () {
        var source = new Image()
        source.onerror = function () { signupError('That photo could not be opened. Choose another photo.') }
        source.onload = function () {
          var encoded = ''
          try { encoded = encodeProfilePhotoJPEG(source) } catch (error) {}
          if (!encoded) {
            signupError('That photo could not be prepared. Choose another photo.')
            return
          }
          pendingProfilePhotoDataURI = encoded
          var preview = new Image(); preview.src = encoded
          var circle = document.getElementById('photoCircle')
          circle.textContent = ''; circle.appendChild(preview)
          photoSet = true
        }
        source.src = reader.result
      }
      reader.readAsDataURL(file)
    })`;
  if (!out.includes(personalPhotoSource)) {
    throw new Error("Personal profile-photo source block changed; update the bounded iOS bridge transform.");
  }
  out = out.replace(personalPhotoSource, personalPhotoBundle);

  // 9d. Button pop → mirror the tap to the native haptic bridge.
  out = out.replace(
    "    function playPop() {\n      popSfx.muted = false",
    "    function playPop() {\n      if (window.poplurBridge) poplurBridge.pop()\n      popSfx.muted = false"
  );

  // 9e. Location permission choice → post requestPermission/location (Phase-3
  //     stub: native logs, real OS prompt lands later). Fires for every allow
  //     variant; deny is still reported with its choice.
  out = out.replace(
    "          if (btn.dataset.permission !== 'location-deny') allowedAny = true\n          showPermission(permCamera)",
    "          if (btn.dataset.permission !== 'location-deny') allowedAny = true\n          if (window.poplurBridge) poplurBridge.requestPermission('location', { choice: btn.dataset.permission })\n          showPermission(permCamera)"
  );

  // 9f. Camera-roll permission choice → post requestPermission/camera.
  out = out.replace(
    "          if (btn.dataset.permission === 'allow') allowedAny = true\n          sessionStorage.setItem('poplurWelcomePerms', '1')",
    "          if (btn.dataset.permission === 'allow') allowedAny = true\n          if (window.poplurBridge) poplurBridge.requestPermission('camera', { choice: btn.dataset.permission })\n          sessionStorage.setItem('poplurWelcomePerms', '1')"
  );

  // 9g. Live radio: the welcome's station lookup is a raw fetch to
  //     radio-browser, which cannot run inside an offline bundle — and an
  //     unreachable host is precisely the hang the clay map's Mapbox call used
  //     to cause. It used to be rejected outright, which is why pre-login never
  //     tuned anything while the map tuned a real local station. Route it
  //     through the bridge instead: no http ref remains in the bundle, the URL
  //     lives on the native side, and native can use the device's real location
  //     rather than the coordinates hardcoded in the approved source.
  out = out.replace(
    /fetch\('https:\/\/de1\.api\.radio-browser\.info\/[^']*'\)/,
    "window.__poplurTuneStations()"
  );

  return out;
}

// splash.html is already a clean, self-contained page with zero network refs.
// 3D models remain bundled for the destination screens, but the approved splash
// intentionally does not preload them so launch avoids unnecessary decode/I/O.
function cleanSplash(html) {
  // The canonical splash owns first-painted-frame gating and explicitly disables
  // native/PiP/remote controls. Keep this transform idempotent so generated
  // targets never reintroduce the old canplay-only placeholder race.
  return html;
}

// ---- run --------------------------------------------------------------------
// Files that live in PreloginWeb but are NOT built here. loading.html is placed
// by hand and is loaded by PreloginWebView.loadingURL; the globe it renders is
// its only asset. The wipe below is recursive, so without this it took both with
// it on every rebuild and silently removed a screen the app still asks for.
// Carry them across rather than making the wipe surgical: a rebuild should still
// be able to guarantee nothing stale survives in the parts it DOES own.
const PRESERVE = [
  "loading.html",
  "poplur-clay-map/public/poplur-globe-lite.glb",
];
const carried = [];
for (const rel of PRESERVE) {
  const from = join(OUT, rel);
  if (existsSync(from)) carried.push([rel, readFileSync(from)]);
}

if (existsSync(OUT)) rmSync(OUT, { recursive: true, force: true });
mkdirSync(OUT, { recursive: true });

for (const [rel, buf] of carried) {
  const to = join(OUT, rel);
  mkdirSync(dirname(to), { recursive: true });
  writeFileSync(to, buf);
}

const splash = cleanSplash(readFileSync(SPLASH_SRC, "utf8"));
writeFileSync(join(OUT, "splash.html"), splash);

const welcome = cleanWelcome(readFileSync(WELCOME_SRC, "utf8"));
writeFileSync(join(OUT, "welcome.html"), welcome);

for (const [from, dest] of ASSETS) {
  const to = join(OUT, dest);
  if (!existsSync(from)) { console.warn(`[skip missing] ${from}`); continue; }
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
