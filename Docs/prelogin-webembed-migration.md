# Pre-login Web-Embed Migration Plan

**Goal:** ship the *exact* prototype web screens inside the iOS and Android apps via
WebView, instead of hand-rebuilding them in SwiftUI/Compose. The web screens are the
high-quality source; native remakes look cheap and never quite match. Render the real
HTML/CSS/JS; keep only the native glue.

**Author:** build-runner thread · **Date:** 2026-07-18
**Status:** plan + Phase-0 spike. Not yet an approved architecture change.

---

## Why this is viable — the clay map already does it

Every layer this needs already ships in the app for the clay map:

| Layer | iOS (clay map) | Android (clay map) |
|---|---|---|
| WebView host | `PoplurClayMapView.swift` — `WKWebView` | `ClayMapActivity.kt` — `WebView` |
| Local serving | `WKURLSchemeHandler` (maps html/js/css/glb/mp3 MIME) | `WebViewAssetLoader` over `appassets.androidplatform.net` |
| JS↔native bridge | `WKScriptMessageHandler` named `poplur` | `@JavascriptInterface onEvent(json)` |
| Build → app sync | `poplur-clay-map/scripts/sync-mobile.sh` (`npm run build` → rsync `dist/` into both apps) | same |

The pre-login flow rides the identical rails. This is not new infrastructure — it is a
second consumer of infrastructure that already exists and is proven on device.

---

## CRITICAL: the good-copy files are artifact exports, not production pages

`good-copy-welcome.html` (and siblings) are **claude.ai artifact exports**. As-is they
are NOT safe to bundle, because the wrapper has network dependencies:

- `window.__FRAME_PREAMBLE` + capability scripts (`downloads.*.js`, `mcp.*.js`,
  `self.*.js`, `_transforms.*.js`) — claude.ai artifact runtime.
- `.screenlinks` nav catalog with `href="https://claude.ai/code/artifact/..."` links.
- A `fetch('https://api.mapbox.com/search/searchbox/v1/forward?...')` — a live network
  call. On an offline device this hangs/fails exactly the way the clay map's Mapbox
  fetch did (the original "Samsung glitch").

The **actual screen** is cleanly contained in `.phone > .screens`. So the migration
needs a **build/extraction step** that, per screen:

1. Extracts the `.phone`/`.screens` DOM + its inline `<style>`/`<script>`.
2. Strips the artifact frame runtime, the `.screenlinks` catalog, and any off-device
   `fetch`/`href` (rewire real actions through the bridge instead).
3. Emits a clean, self-contained, **offline** HTML file.

This preserves visual fidelity 1:1 (the screen's own HTML/CSS is untouched) while making
the bundle production-safe. It is the single most important non-obvious piece of work.

---

## The bridge contract (the real engineering)

Rendering is free. The work is the JS↔native calls. Both platforms already expose a
single `poplur` event channel; define one message schema and route it:

```
web → native:  window.poplur.send({ action, payload, callbackId })
native → web:  webView.evaluate("window.poplurResolve(callbackId, result)")
```

| action | payload | native handler (already exists) |
|---|---|---|
| `signIn` | `{email, password}` | Android `AuthViewModel.signIn(...)`; iOS auth |
| `signUp` | `{email, password, accountType, businessProfile}` | Android `AuthViewModel.signUp(...)` |
| `requestPermission` | `{kind: "camera"\|"location"}` | iOS `PoplurPermissionCenter.shared.ask(kind)`; Android runtime request |
| `openSettings` | `{}` | iOS `PoplurPermissionCenter.openSettings()` |
| `complete` | `{}` | `onSignUpSuccess` / `onWelcomePermissionsGranted` → leave pre-login |
| `navigate` | `{screen}` | in-web nav for most; native only at flow boundaries |

Most navigation stays *inside* the web (the prototype already sequences its 12 screens).
Native is called only for: auth, OS permission prompts, Face ID, and exiting pre-login.

---

## Screen inventory

The GCL prototype flow is **12 screens**: Launch, Splash, Welcome, Sign In · Face ID,
Sign up · Choose Account, Sign up · Create Login, Sign up · Profile Setup,
Sign up · Verify Business, Sign up · Review & Submit, Camera Permission,
Location Permission, Login Cube.

Only **3** exist as standalone files today (`good-copy-launch/splash/welcome.html`); the
other 9 render *inside* `gcl-prototype.html`'s player.

**Source decision (recommended): bundle the whole prototype flow as one web app.** It
already sequences all 12 screens with its own navigation and is a single source of
truth, so GCL edits propagate by rebuild. Extracting 9 new standalone files is more work
and multiplies the drift surface.

---

## Phased plan

- **Phase 0 — Spike (this doc's companion).** Bundle the Welcome screen into a WebView
  on Android, load on the A03s, screenshot, compare to the prototype. Wire one bridge
  call (`signIn`). Proves fidelity + interaction cheaply. *(Running now.)*
- **Phase 1 — Welcome, both platforms.** Replace `WelcomeView.swift` /
  `WelcomeAuthScreen.kt` host with a WebView host on iOS + Android. Delete the native
  remakes. Ship the cleaning/extraction step for one screen.
- **Phase 2 — Full flow bundle.** Bundle all 12 screens with the prototype's own
  navigation in one WebView. Finalize the bridge message schema.
- **Phase 3 — Real integrations.** Wire the mock dialogs to real native: OS permission
  prompts, Firebase auth, Face ID, deep-link/navigation on completion. Bulk of effort.
- **Phase 4 — Pipeline + cutover.** Add `sync-prelogin.sh` (mirrors `sync-mobile.sh`),
  remove native pre-login code, add a GCL tracking gate so drift is caught by
  rebuild-not-rewrite.

---

## Open decisions

1. **Bundle the whole flow vs. extract 9 standalone screens.** Recommend: whole flow.
2. **Stub vs. real auth/permissions in early phases.** Recommend: stub through Phase 2,
   wire real in Phase 3.
3. **Native chrome.** The prototype draws a mock `9:41 / 100%` status bar; on device hide
   it and let the real OS status bar show.
4. **Offline hardening.** The cleaning step must remove the Mapbox `fetch` and any
   artifact-runtime network calls, or a bundled screen risks the same offline hang the
   clay map had.

---

## Ownership

- **Build-runner** (this thread): build, bundle, the sync pipeline, and on-device
  verification per phase. Owns the extraction/cleaning build step and the fidelity
  checks.
- **GCL / design + native threads**: the bridge wiring and native host code, and the
  real auth/permission integrations in Phase 3.
