import SwiftUI
import WebKit
import UniformTypeIdentifiers
import FirebaseAuth
import CoreLocation
import Photos

// MARK: - Pre-login Web Embed (Phase 1)
//
// The APPROVED pre-login web screens (splash → welcome) rendered inside a
// WKWebView instead of native SwiftUI remakes. This is the second consumer of
// the exact infrastructure the clay map already ships (PoplurClayMapView):
// a custom URL-scheme handler serving a bundled, OFFLINE web folder, plus a
// `poplur` WKScriptMessageHandler bridge.
//
// The bundle lives in PreloginWeb/ (built by scripts/build-prelogin-ios.mjs from
// the read-only Good Copy sources — the artifact frame runtime, screen catalog,
// and Mapbox/Clearbit network calls are stripped so nothing can hang offline).
//
// Flow: load splash.html, then after the prototype's splash beat (~3.2s)
// navigate to welcome.html. Both pages share the same custom-scheme origin, so
// their sessionStorage handoff (the radio-bed play position) is preserved.
//
// Native ⇄ web bridge (poplur channel):
//   web → Swift: window.webkit.messageHandlers.poplur.postMessage({action, ...})
//
// Phase-2 finalized action set (identical on iOS + Android — Android delivers the
// same shape via PoplurNative.onAction(action, payloadJson)):
//     "signIn"            → AuthViewModel sign-in  (Phase-3 stub: log, no faked success)
//     "signUp"            → AuthViewModel sign-up   (Phase-3 stub: log, no faked success)
//     "requestPermission" → { permission: "camera" | "location", choice }
//                           (`camera` is the legacy web key for camera roll/photos)
//     "complete"          → flow finished → onComplete() handoff to post-login
//     "pop"               → haptic tap (auxiliary)

enum PoplurPreloginWeb {
    // Custom scheme (not file://) so the page gets a real origin: ES modules,
    // the three.js import map, and dynamic import() all require it (see the
    // note on PoplurClayWebMap for why file:// silently fails).
    static let scheme = "poplur-prelogin"
    static let host = "app"

    /// The prototype's splash beat before handing off to Welcome.
    static let splashDurationSeconds: Double = 3.2

    /// Build stamp appended to every page URL. `devicectl install` replaces the
    /// app bundle but KEEPS the data container, so WebKit happily served the
    /// previous build's cached splash — the app looked "old" after a fresh
    /// install. Busting on build version guarantees the new page loads.
    /// Cache key for every web URL the app loads. It MUST change whenever the
    /// web bundle changes, or WKWebView keeps serving the page it already has.
    ///
    /// This used to be CFBundleVersion + CFBundleShortVersionString alone — and
    /// those are `6` and `0.1` on every build, so the stamp was the constant
    /// "6-0.1" forever. The URL never varied, so the web view answered from cache
    /// no matter how many times the app was rebuilt and reinstalled: the native
    /// binary updated while the web layer stayed frozen on an old build. That is
    /// exactly the "it's showing old builds" symptom, and it makes every web
    /// change look like it silently failed to ship.
    ///
    /// The bundle's own modification time changes on every build without anyone
    /// having to remember to bump a version, so the stamp now tracks the build
    /// itself rather than a number nobody edits.
    static var buildStamp: String {
        let version = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0")
            + "-" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0")
        guard let executable = Bundle.main.executableURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: executable.path),
              let built = attributes[.modificationDate] as? Date
        else { return version }
        return version + "-" + String(Int(built.timeIntervalSince1970))
    }

    static var splashURL: URL? { URL(string: "\(scheme)://\(host)/splash.html?v=\(buildStamp)") }
    static var welcomeURL: URL? { URL(string: "\(scheme)://\(host)/welcome.html?v=\(buildStamp)") }
    /// The APPROVED post-login Loading screen — clay globe, wordmark, rotating
    /// clay messages — built offline by scripts/build-loading-ios.mjs.
    static var loadingURL: URL? { URL(string: "\(scheme)://\(host)/loading.html?v=\(buildStamp)") }
}

struct PreloginWebView: UIViewRepresentable {
    let auth: AuthViewModel
    /// Called when the web flow reports `complete` (Phase 3 handoff hook).
    var onComplete: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(auth: auth, onComplete: onComplete) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // Autoplay the splash video + radio bed without a gesture (as the
        // prototype does inside its frame).
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "poplur")

        // Splash video diagnostics, INJECTED rather than written into the page:
        // splash.html is approved Good Copy and must not be edited to debug it.
        // The video sits at opacity 0 until the page adds .ready on a painted
        // frame, so "no video at all" and "video playing invisibly" look
        // identical on screen. This reports which one it is, plus the media
        // element's own error code.
        let splashProbe = #"""
        (function () {
          function report(stage, video) {
            try {
              var e = video && video.error;
              window.webkit.messageHandlers.poplur.postMessage({
                type: 'splashVideoDiag', stage: stage,
                readyState: video ? video.readyState : -1,
                networkState: video ? video.networkState : -1,
                paused: video ? video.paused : null,
                ready: video ? video.classList.contains('ready') : null,
                errorCode: e ? e.code : 0,
                src: (video && video.currentSrc) ? video.currentSrc.slice(-40) : ''
              });
            } catch (err) {}
          }
          function attach() {
            var video = document.querySelector('video');
            if (!video) { report('no-video-element', null); return; }
            ['loadedmetadata','loadeddata','canplay','playing','stalled','error','abort']
              .forEach(function (name) {
                video.addEventListener(name, function () { report(name, video); });
              });
            report('attached', video);
            setTimeout(function () { report('t+1500ms', video); }, 1500);
            setTimeout(function () { report('t+3000ms', video); }, 3000);
          }
          if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', attach);
          } else { attach(); }
        })();
        """#
        config.userContentController.addUserScript(
            WKUserScript(source: splashProbe, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )

        let webRoot = Self.bundledRootURL()
        if let webRoot {
            config.setURLSchemeHandler(PreloginSchemeHandler(rootDirectory: webRoot),
                                       forURLScheme: PoplurPreloginWeb.scheme)
        }

        let webView = PoplurManagedWebView(
            performanceName: "PreloginWeb",
            priority: 120,
            configuration: config
        )
        webView.isOpaque = true
        // Matches the splash background (#0a0709) so there is no flash between
        // the auth-resolving frame and the web splash. This is the SAME colour
        // as LaunchScreen.storyboard's backdrop, so the storyboard, this view
        // and the splash page are one continuous tone rather than three
        // near-blacks stepping into each other. It was `.black` (#000000),
        // which is a visible step against #0a0709.
        webView.backgroundColor = UIColor(red: 10 / 255, green: 7 / 255, blue: 9 / 255, alpha: 1)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // BUG-1 fix: the pre-login layout is fixed/full-screen and must NEVER
        // scroll. WebKit still scrolls its internal scrollView to lift a focused
        // input above the keyboard, which displaces the fixed layout and does not
        // reset on dismiss. Own the scrollView delegate and hard-clamp every
        // contentOffset back to zero (the web side also resizes under the keyboard
        // via interactive-widget=resizes-content, so the field stays reachable
        // without moving the whole UI).
        webView.scrollView.delegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        webView.scrollView.keyboardDismissMode = .interactive
        // Force the iphone platform skin the GCL prototype uses: the welcome's
        // dark "pill" buttons live behind `@media (prefers-color-scheme: dark)`,
        // so pin the web content to dark regardless of the device appearance.
        webView.overrideUserInterfaceStyle = .dark
        context.coordinator.webView = webView

        // Launch shows the SPLASH, always.
        //
        // This used to load Welcome directly. Welcome is ~285KB of HTML plus its
        // hero cube and account-icon models, so "straight to Welcome" meant
        // staring at an empty black WebView for the whole of that parse — the
        // black screen on launch. The splash is ~10KB and self-contained, so it
        // paints almost immediately and then covers the Welcome load with the
        // clay world instead of with nothing.
        //
        // The 3.2s splash beat is anchored to the page FINISHING ITS LOAD
        // (didFinish below), not to this call. It used to start here, at view
        // construction — but WebKit's processes aren't even alive yet at that
        // point, and on a cold phone their spin-up ate the entire beat: the
        // timer swapped in Welcome while the splash was still black-with-logo,
        // so the approved video never got a frame on screen. That was the
        // "black splash with just a logo" report.
        //
        // The original guarantee stands via the failsafe armed here: a splash
        // that never finishes loading still hands off (10s cap), so nobody can
        // be stranded on the intro.
        if webRoot != nil, let splashURL = PoplurPreloginWeb.splashURL {
            webView.load(URLRequest(url: splashURL))
            context.coordinator.armSplashFailsafe()
        } else if webRoot != nil, let welcomeURL = PoplurPreloginWeb.welcomeURL {
            // Splash URL unavailable: Welcome is still better than nothing.
            webView.load(URLRequest(url: welcomeURL))
        } else {
            print("[PreloginWebView] PreloginWeb bundle missing — run scripts/build-prelogin-ios.mjs")
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        (uiView as? PoplurManagedWebView)?.poplurTearDown()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "poplur")
    }

    /// Directory holding the bundled pre-login web files (`PreloginWeb/splash.html`
    /// + `welcome.html` + assets). Scoped by subdirectory so it never resolves a
    /// different bundled `index.html` (e.g. ClayMapWeb / PoplurFPS).
    static func bundledRootURL() -> URL? {
        Bundle.main
            .url(forResource: "welcome", withExtension: "html", subdirectory: "PreloginWeb")?
            .deletingLastPathComponent()
    }

    /// Serves the bundled PreloginWeb files over `PoplurPreloginWeb.scheme` so the
    /// page gets a real origin. Reads are confined to `rootDirectory` — an absent
    /// asset fails fast (no network, no hang), which is exactly the offline
    /// hardening the cleaning step exists to guarantee.
    final class PreloginSchemeHandler: NSObject, WKURLSchemeHandler {
        private let root: URL

        init(rootDirectory: URL) {
            self.root = rootDirectory.standardizedFileURL
        }

        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            guard let url = urlSchemeTask.request.url else {
                urlSchemeTask.didFailWithError(URLError(.badURL))
                return
            }

            var relativePath = url.path
            if relativePath.isEmpty || relativePath == "/" { relativePath = "/splash.html" }
            let fileURL = root.appendingPathComponent(String(relativePath.dropFirst())).standardizedFileURL

            // Confine reads to the bundle directory (no `../` traversal).
            guard fileURL.path.hasPrefix(root.path + "/") || fileURL.path == root.path else {
                PoplurDiagLog.append("[PreloginSplash] BLOCKED path traversal for \(url.path)")
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }

            let mime = Self.mimeType(forExtension: fileURL.pathExtension)

            // The splash video "never appears" and nothing anywhere recorded
            // whether it was even requested. Log media requests (and any miss)
            // so the next device run distinguishes "WebKit never asked for it",
            // "the handler could not find it" and "it was served and still did
            // not paint" -- three different bugs that look identical on screen.
            if ["mp4", "mov", "m4v"].contains(fileURL.pathExtension.lowercased()) {
                let range = urlSchemeTask.request.value(forHTTPHeaderField: "Range") ?? "none"
                let exists = FileManager.default.fileExists(atPath: fileURL.path)
                PoplurDiagLog.append("[PreloginSplash] media request \(url.lastPathComponent) range=\(range) exists=\(exists)")
            }

            // BYTE-RANGE support. WKWebView will not play a <video> served over a
            // custom scheme unless the handler answers Range requests with a 206
            // and Content-Range — without it the media element silently fails and
            // the splash renders as black (Android's WebViewAssetLoader does this
            // for us, which is why only iOS showed it).
            if let rangeHeader = urlSchemeTask.request.value(forHTTPHeaderField: "Range"),
               rangeHeader.hasPrefix("bytes="),
               let spec = rangeHeader.split(separator: "=").last,
               let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
               fileSize > 0 {
                let range = String(spec)
                let bounds = range.split(separator: "-", omittingEmptySubsequences: false)
                let start: Int
                let upper: Int
                if range.contains(",") || bounds.count != 2 {
                    Self.respondRangeNotSatisfiable(to: urlSchemeTask, url: url, fileSize: fileSize)
                    return
                } else if bounds[0].isEmpty {
                    // RFC 7233 suffix range: `bytes=-N` means the final N bytes.
                    guard let suffixLength = Int(bounds[1]), suffixLength > 0 else {
                        Self.respondRangeNotSatisfiable(to: urlSchemeTask, url: url, fileSize: fileSize)
                        return
                    }
                    start = max(0, fileSize - suffixLength)
                    upper = fileSize - 1
                } else {
                    guard let parsedStart = Int(bounds[0]), parsedStart >= 0 else {
                        Self.respondRangeNotSatisfiable(to: urlSchemeTask, url: url, fileSize: fileSize)
                        return
                    }
                    start = parsedStart
                    upper = min(Int(bounds[1]) ?? (fileSize - 1), fileSize - 1)
                }
                guard start < fileSize, start <= upper else {
                    Self.respondRangeNotSatisfiable(to: urlSchemeTask, url: url, fileSize: fileSize)
                    return
                }
                let slice: Data
                do {
                    let handle = try FileHandle(forReadingFrom: fileURL)
                    defer { try? handle.close() }
                    try handle.seek(toOffset: UInt64(start))
                    let length = upper - start + 1
                    guard let bytes = try handle.read(upToCount: length), bytes.count == length else {
                        throw URLError(.cannotDecodeContentData)
                    }
                    slice = bytes
                } catch {
                    urlSchemeTask.didFailWithError(error)
                    return
                }
                let headers = [
                    "Content-Type": mime,
                    "Content-Length": "\(slice.count)",
                    "Content-Range": "bytes \(start)-\(upper)/\(fileSize)",
                    "Accept-Ranges": "bytes",
                    "Cache-Control": "no-store"
                ]
                if let response = HTTPURLResponse(url: url, statusCode: 206,
                                                  httpVersion: "HTTP/1.1", headerFields: headers) {
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(slice)
                    urlSchemeTask.didFinish()
                    return
                }
            }

            // Full-body response, advertising range support so media can seek.
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }
            let headers = [
                "Content-Type": mime,
                "Content-Length": "\(data.count)",
                "Accept-Ranges": "bytes",
                    "Cache-Control": "no-store"
            ]
            if let response = HTTPURLResponse(url: url, statusCode: 200,
                                              httpVersion: "HTTP/1.1", headerFields: headers) {
                urlSchemeTask.didReceive(response)
            } else {
                urlSchemeTask.didReceive(URLResponse(
                    url: url, mimeType: mime, expectedContentLength: data.count,
                    textEncodingName: mime.hasPrefix("text/") ? "utf-8" : nil))
            }
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

        private static func respondRangeNotSatisfiable(
            to task: WKURLSchemeTask,
            url: URL,
            fileSize: Int
        ) {
            let headers = [
                "Content-Range": "bytes */\(fileSize)",
                "Content-Length": "0",
                "Accept-Ranges": "bytes"
            ]
            if let response = HTTPURLResponse(
                url: url,
                statusCode: 416,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            ) {
                task.didReceive(response)
                task.didFinish()
            } else {
                task.didFailWithError(URLError(.badServerResponse))
            }
        }

        private static func mimeType(forExtension ext: String) -> String {
            switch ext.lowercased() {
            case "html":         return "text/html"
            case "js", "mjs":    return "text/javascript"
            case "css":          return "text/css"
            case "json":         return "application/json"
            case "wasm":         return "application/wasm"
            case "glb":          return "model/gltf-binary"
            case "mp3":          return "audio/mpeg"
            case "wav":          return "audio/wav"
            case "mp4":          return "video/mp4"
            case "png":          return "image/png"
            default:
                return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
            }
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, UIScrollViewDelegate, WKNavigationDelegate {
        weak var webView: WKWebView?
        private let auth: AuthViewModel
        private let onComplete: () -> Void
        private let popHaptic = UIImpactFeedbackGenerator(style: .medium)
        private let locationRequester = CLLocationManager()
        private var locationPermissionRequestInFlight = false
        private var photoPermissionRequestInFlight = false
        /// The splash→welcome handoff fires exactly once, whoever asks first:
        /// the post-render beat, the load-failure path, or the failsafe.
        private var welcomeHandoffDone = false
        private var splashFailsafe: DispatchWorkItem?

        init(auth: AuthViewModel, onComplete: @escaping () -> Void) {
            self.auth = auth
            self.onComplete = onComplete
            super.init()
            observeAppLifecycle()
        }

        // MARK: - Background audio

        /// Minimizing the app must silence the pre-login radio, and it did not.
        ///
        /// The radio bed plays from an `<audio>` element INSIDE this WebView, and
        /// nothing native reached it: `Poplur2025App`'s scenePhase handler stops
        /// `PreLoginMusicPlayer` (already inert behind `usePreloginWebEmbed`) and
        /// posts `.StopMapAudio`, whose only observer is native `MapView`. With
        /// `UIBackgroundModes = [audio]` declared in Info.plist, WebKit was free to
        /// keep the bed playing after the app went away.
        ///
        /// Post-login does not have this bug because the clay map pauses itself on
        /// `visibilitychange`/`pagehide`. The pre-login pages carry no such handler
        /// and are GENERATED from the protected Good Copy sources by
        /// `scripts/build-prelogin-ios.mjs`, so the pause is owned here instead of
        /// being patched into the bundle.
        private func observeAppLifecycle() {
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(suspendWebMedia),
                               name: UIApplication.willResignActiveNotification, object: nil)
            center.addObserver(self, selector: #selector(resumeWebMedia),
                               name: UIApplication.didBecomeActiveNotification, object: nil)
        }

        /// `willResignActive` rather than `didEnterBackground` so the app switcher,
        /// Control Center and incoming calls go quiet too — matching what the
        /// native pre-login player did on `.inactive`.
        @objc private func suspendWebMedia() {
            webView?.setAllMediaPlaybackSuspended(true, completionHandler: nil)
            // That call covers HTMLMediaElement and nothing else. The pre-login AI
            // host is NOT an <audio> tag — `speakAI` in welcome.html speaks through
            // the Web Speech API, and at 0.85 volume it is the loudest thing on the
            // screen. Suspending media alone left it talking to a phone that had
            // already been put away, so it is cancelled explicitly.
            webView?.evaluateJavaScript("window.speechSynthesis && window.speechSynthesis.cancel()")
        }

        /// Lifts the suspension only. Elements the person muted or paused through
        /// the web UI stay muted or paused — WebKit resumes just what it silenced.
        /// The AI greeting is deliberately NOT re-spoken: it is a one-time welcome,
        /// and resuming it half a sentence in on every app switch would be worse
        /// than losing the tail of it.
        @objc private func resumeWebMedia() {
            webView?.setAllMediaPlaybackSuspended(false, completionHandler: nil)
        }

        // BUG-1 fix: keep the fixed full-screen pre-login pinned. Any attempt by
        // WebKit to scroll (to lift a focused field over the keyboard) is clamped
        // straight back to the top so the header/logo never fly off-screen and the
        // layout resets cleanly when the keyboard dismisses.
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if scrollView.contentOffset != .zero {
                scrollView.contentOffset = .zero
            }
        }

        /// After the splash beat, navigate the same web view to Welcome. Same
        /// origin, so the splash→welcome sessionStorage handoff survives.
        private func scheduleWelcomeHandoff(after seconds: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                guard let self, !self.welcomeHandoffDone,
                      let welcomeURL = PoplurPreloginWeb.welcomeURL else { return }
                self.welcomeHandoffDone = true
                self.splashFailsafe?.cancel()
                self.splashFailsafe = nil
                self.webView?.load(URLRequest(url: welcomeURL))
            }
        }

        /// Nobody gets stranded on the intro: if the splash page has not
        /// finished loading within this window (didFinish never fired), go to
        /// Welcome anyway. Cancelled by the real beat the moment the splash
        /// renders.
        func armSplashFailsafe() {
            let failsafe = DispatchWorkItem { [weak self] in
                guard let self, !self.welcomeHandoffDone,
                      let welcomeURL = PoplurPreloginWeb.welcomeURL else { return }
                self.welcomeHandoffDone = true
                self.webView?.load(URLRequest(url: welcomeURL))
            }
            splashFailsafe = failsafe
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: failsafe)
        }

        // MARK: - WKNavigationDelegate (the splash beat's real anchor)

        /// The approved 3.2s beat starts when the SPLASH HAS ACTUALLY LOADED —
        /// WebKit paints this 10KB page immediately after didFinish, and its
        /// preloaded video reveals right behind that — so the beat is spent
        /// showing the approved clay video, not absorbing process spin-up.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !welcomeHandoffDone,
                  webView.url?.path.hasSuffix("/splash.html") == true else { return }
            splashFailsafe?.cancel()
            splashFailsafe = nil
            scheduleWelcomeHandoff(after: PoplurPreloginWeb.splashDurationSeconds)
        }

        /// A splash that cannot load should not keep its black curtain up for
        /// the failsafe's full window — Welcome is still better than nothing.
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            guard !welcomeHandoffDone,
                  webView.url == nil || webView.url?.path.hasSuffix("/splash.html") == true else { return }
            scheduleWelcomeHandoff(after: 0)
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "poplur" else { return }
            let body = message.body as? [String: Any]
            // Finalized schema keys on `action`; tolerate legacy `type` too.
            guard let action = (body?["action"] as? String) ?? (body?["type"] as? String) else { return }
            switch action {
            case "splashVideoDiag":
                // Injected probe (see splashProbe above). Written to the device
                // log so a cold launch can be read back afterwards -- the splash
                // is gone in ~3.2s, which is not long enough to attach anything.
                let stage = body?["stage"] as? String ?? "?"
                let ready = body?["ready"] as? Bool
                let errorCode = body?["errorCode"] as? Int ?? 0
                let readyState = body?["readyState"] as? Int ?? -1
                let networkState = body?["networkState"] as? Int ?? -1
                let paused = body?["paused"] as? Bool
                let src = body?["src"] as? String ?? ""
                PoplurDiagLog.append(
                    "[PreloginSplash] video \(stage) readyState=\(readyState) network=\(networkState) "
                    + "paused=\(paused.map(String.init) ?? "?") ready=\(ready.map(String.init) ?? "?") "
                    + "err=\(errorCode) src=\(src)"
                )
            case "pop":
                popHaptic.impactOccurred()
            case "signIn":
                // BUG-2 fix: real Firebase sign-in, mirroring LoginView.loginUser().
                // On success we do NOT fake anything — the AuthViewModel state
                // listener flips isAuthenticated and the app transitions to
                // post-login automatically. On error we post the message back to
                // the web so the form can surface it.
                let method = body?["method"] as? String ?? "password"
                let email = (body?["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let password = body?["password"] as? String ?? ""
                if method == "faceid" {
                    // Face ID isn't wired to the web embed yet (no saved-credential
                    // biometric bridge). Do not fake success — tell the web plainly.
                    print("[PreloginWebView] signIn(faceid) — not wired in web embed yet")
                    postAuthResult(ok: false, error: "Face ID sign-in isn’t available here yet — use your email and password.")
                    return
                }
                guard !email.isEmpty, !password.isEmpty else {
                    print("[PreloginWebView] signIn missing credentials — ignoring (no fake success)")
                    postAuthResult(ok: false, error: "Enter your email and password.")
                    return
                }
                Auth.auth().signIn(withEmail: email, password: password) { [weak self] _, error in
                    if let error {
                        print("[PreloginWebView] signIn failed: \(error.localizedDescription)")
                        self?.postAuthResult(ok: false, error: error.localizedDescription)
                    } else {
                        print("[PreloginWebView] signIn succeeded — auth-state listener will transition")
                        self?.postAuthResult(ok: true, error: nil)
                    }
                }
            case "signUp":
                // BUG-2 fix: real Firebase account creation, mirroring
                // SignUpView.submit(). Business-profile persistence stays Phase 3;
                // success transitions via the same auth-state listener.
                let email = (body?["email"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let password = body?["password"] as? String ?? ""
                let accountType = body?["accountType"] as? String ?? "personal"
                guard !email.isEmpty, !password.isEmpty else {
                    print("[PreloginWebView] signUp missing credentials — ignoring (no fake success)")
                    postAuthResult(ok: false, error: "Enter your email and password to create your account.")
                    return
                }
                Auth.auth().createUser(withEmail: email, password: password) { [weak self] _, error in
                    if let error {
                        print("[PreloginWebView] signUp failed: \(error.localizedDescription)")
                        self?.postAuthResult(ok: false, error: error.localizedDescription)
                    } else {
                        print("[PreloginWebView] signUp succeeded (\(accountType)) — auth-state listener will transition")
                        Task { @MainActor in self?.auth.didSignUp = true }
                        self?.postAuthResult(ok: true, error: nil)
                    }
                }
            case "requestPermission":
                // A permission is asked ONCE, wherever the user first meets it:
                // signed out, that is here; signed in, the post-login home asks
                // in the same clay alert. The answer is recorded here so the
                // primer does not repeat; the system prompt is deferred until
                // the user invokes the feature that needs that capability.
                //
                // The approved clay card is the only startup permission UI. Do
                // not stack Apple's system alert on top of it; a real OS ask is
                // reserved for the feature that actually needs the capability.
                let permission = body?["permission"] as? String ?? ""
                let choice = body?["choice"] as? String ?? ""
                switch permission {
                case "camera":
                    // The approved card says "camera roll". The bundled web still
                    // uses its legacy `camera` bridge key, so map that key to
                    // Photos — never to AVCaptureDevice.
                    guard choice == "allow" || choice == "deny" else {
                        print("[PreloginWebView] ignored unknown camera-roll choice: \(choice)")
                        return
                    }
                    PoplurPermissionRouting.markPreloginHandledThisLaunch(permission: .photos)
                    guard choice == "allow" else {
                        print("[PreloginWebView] camera roll declined in-app — OS prompt not shown")
                        return
                    }
                    print("[PreloginWebView] camera-roll accepted in-app — system prompt deferred until Camera Roll is used")
                case "location":
                    guard choice == "location-once"
                            || choice == "location-allow"
                            || choice == "location-deny" else {
                        print("[PreloginWebView] ignored unknown location choice: \(choice)")
                        return
                    }
                    PoplurPermissionRouting.markPreloginHandledThisLaunch(permission: .location)
                    guard choice != "location-deny" else {
                        print("[PreloginWebView] location declined in-app — OS prompt not shown")
                        return
                    }
                    print("[PreloginWebView] location accepted in-app — system prompt deferred until a location feature is used")
                default:
                    print("[PreloginWebView] unhandled permission: \(permission)")
                }
            case "radioStations":
                // Live radio, the way the map already does it. The page's own
                // lookup is a raw fetch that the offline bundle strips, so the
                // call is made here and the list handed back.
                //
                // No permission is asked for. Pre-login deliberately defers every
                // OS prompt until the feature that needs it is used, and a radio
                // bed is not worth a location dialog on a launch screen — so this
                // uses a location the person has ALREADY granted, and otherwise
                // falls back to the coordinates the approved source hardcodes.
                let callbackId = body?["callbackId"] as? String ?? ""
                let status = locationRequester.authorizationStatus
                let authorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
                let coordinate = authorized ? locationRequester.location?.coordinate : nil
                fetchRadioStations(
                    latitude: coordinate?.latitude ?? Self.fallbackRadioLatitude,
                    longitude: coordinate?.longitude ?? Self.fallbackRadioLongitude,
                    callbackId: callbackId
                )
            case "complete":
                // Flow finished → hand off to the existing post-login path.
                PoplurPermissionRouting.markPreloginHandledThisLaunch()
                onComplete()
            default:
                print("[PreloginWebView] unhandled bridge action: \(action)")
            }
        }

        // MARK: - Live radio

        /// Same coordinates the approved Welcome source hardcodes, used whenever
        /// the person has not already granted location.
        private static let fallbackRadioLatitude = 43.6532
        private static let fallbackRadioLongitude = -79.3832

        private func fetchRadioStations(latitude: Double, longitude: Double, callbackId: String) {
            var components = URLComponents(string: "https://de1.api.radio-browser.info/json/stations/search")
            components?.queryItems = [
                URLQueryItem(name: "geo_lat", value: String(latitude)),
                URLQueryItem(name: "geo_long", value: String(longitude)),
                URLQueryItem(name: "geo_distance", value: "90000"),
                URLQueryItem(name: "hidebroken", value: "true"),
                // Nearest-by-popularity happily returns 32kbps mono streams, and
                // a heavily compressed stream behind the music is indistinguishable
                // from a fault in the app. Ask for something worth listening to.
                URLQueryItem(name: "bitrateMin", value: "96"),
                URLQueryItem(name: "order", value: "clickcount"),
                URLQueryItem(name: "reverse", value: "true"),
                URLQueryItem(name: "limit", value: "16")
            ]
            guard let url = components?.url else {
                postRadioStations("[]", callbackId: callbackId)
                return
            }
            var request = URLRequest(url: url)
            // A launch screen must never wait on a third party. The web side gives
            // up after 6s; this gives up sooner so an empty list is a decision
            // rather than a timeout racing another timeout.
            request.timeoutInterval = 4
            URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
                // Only well-formed JSON is handed to evaluateJavaScript. The
                // response is third-party text being placed in an expression
                // position, so parsing it first is what keeps it a value and not
                // a script.
                guard let data,
                      (try? JSONSerialization.jsonObject(with: data)) != nil,
                      let json = String(data: data, encoding: .utf8) else {
                    self?.postRadioStations("[]", callbackId: callbackId)
                    return
                }
                self?.postRadioStations(json, callbackId: callbackId)
            }.resume()
        }

        private func postRadioStations(_ json: String, callbackId: String) {
            // The id is generated web-side as 'st' + digits + base36, so stripping
            // it to alphanumerics cannot change a legitimate value and cannot let
            // a crafted one close the quote.
            let safeId = callbackId.filter { $0.isLetter || $0.isNumber }
            DispatchQueue.main.async { [weak self] in
                self?.webView?.evaluateJavaScript(
                    "window.__poplurStationsResult && window.__poplurStationsResult('\(safeId)', \(json))"
                )
            }
        }

        /// Native → web auth callback. The web defines `window.poplurAuthResult`
        /// to shake the cube + show the error banner on failure (and play the
        /// success gesture on success, though the app is already transitioning).
        private func postAuthResult(ok: Bool, error: String?) {
            let payload: [String: Any] = ["ok": ok, "error": error ?? ""]
            let json = (try? JSONSerialization.data(withJSONObject: payload))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"ok\":\(ok)}"
            DispatchQueue.main.async { [weak self] in
                self?.webView?.evaluateJavaScript(
                    "window.poplurAuthResult && window.poplurAuthResult(\(json))"
                )
            }
        }
    }
}
