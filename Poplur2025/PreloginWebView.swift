import SwiftUI
import WebKit
import UniformTypeIdentifiers
import FirebaseAuth

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
//                           (Phase-3 stub: log; real OS prompt lands in Phase 3)
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

    static var splashURL: URL? { URL(string: "\(scheme)://\(host)/splash.html") }
    static var welcomeURL: URL? { URL(string: "\(scheme)://\(host)/welcome.html") }
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

        let webRoot = Self.bundledRootURL()
        if let webRoot {
            config.setURLSchemeHandler(PreloginSchemeHandler(rootDirectory: webRoot),
                                       forURLScheme: PoplurPreloginWeb.scheme)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = true
        // Matches the splash background (#0a0709) so there is no flash between
        // the auth-resolving frame and the web splash.
        webView.backgroundColor = UIColor(red: 10/255, green: 7/255, blue: 9/255, alpha: 1)
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
        webView.scrollView.keyboardDismissMode = .interactive
        // Force the iphone platform skin the GCL prototype uses: the welcome's
        // dark "pill" buttons live behind `@media (prefers-color-scheme: dark)`,
        // so pin the web content to dark regardless of the device appearance.
        webView.overrideUserInterfaceStyle = .dark
        context.coordinator.webView = webView

        if webRoot != nil, let splashURL = PoplurPreloginWeb.splashURL {
            webView.load(URLRequest(url: splashURL))
            context.coordinator.scheduleWelcomeHandoff()
        } else {
            print("[PreloginWebView] PreloginWeb bundle missing — run scripts/build-prelogin-ios.mjs")
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

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
            guard fileURL.path.hasPrefix(root.path + "/") || fileURL.path == root.path,
                  let data = try? Data(contentsOf: fileURL) else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }

            let mime = Self.mimeType(forExtension: fileURL.pathExtension)

            // BYTE-RANGE support. WKWebView will not play a <video> served over a
            // custom scheme unless the handler answers Range requests with a 206
            // and Content-Range — without it the media element silently fails and
            // the splash renders as black (Android's WebViewAssetLoader does this
            // for us, which is why only iOS showed it).
            if let rangeHeader = urlSchemeTask.request.value(forHTTPHeaderField: "Range"),
               rangeHeader.hasPrefix("bytes="),
               let spec = rangeHeader.split(separator: "=").last {
                let bounds = spec.split(separator: "-", omittingEmptySubsequences: false)
                let start = Int(bounds.first ?? "") ?? 0
                let end = bounds.count > 1 ? (Int(bounds[1]) ?? data.count - 1) : data.count - 1
                let upper = min(end, data.count - 1)
                guard start <= upper else {
                    urlSchemeTask.didFailWithError(URLError(.badServerResponse))
                    return
                }
                let slice = data.subdata(in: start..<(upper + 1))
                let headers = [
                    "Content-Type": mime,
                    "Content-Length": "\(slice.count)",
                    "Content-Range": "bytes \(start)-\(upper)/\(data.count)",
                    "Accept-Ranges": "bytes"
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
            let headers = [
                "Content-Type": mime,
                "Content-Length": "\(data.count)",
                "Accept-Ranges": "bytes"
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

    final class Coordinator: NSObject, WKScriptMessageHandler, UIScrollViewDelegate {
        weak var webView: WKWebView?
        private let auth: AuthViewModel
        private let onComplete: () -> Void
        private let popHaptic = UIImpactFeedbackGenerator(style: .medium)

        init(auth: AuthViewModel, onComplete: @escaping () -> Void) {
            self.auth = auth
            self.onComplete = onComplete
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
        func scheduleWelcomeHandoff() {
            DispatchQueue.main.asyncAfter(deadline: .now() + PoplurPreloginWeb.splashDurationSeconds) { [weak self] in
                guard let self, let welcomeURL = PoplurPreloginWeb.welcomeURL else { return }
                self.webView?.load(URLRequest(url: welcomeURL))
            }
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "poplur" else { return }
            let body = message.body as? [String: Any]
            // Finalized schema keys on `action`; tolerate legacy `type` too.
            guard let action = (body?["action"] as? String) ?? (body?["type"] as? String) else { return }
            switch action {
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
                // Phase-3 stub (unchanged): log only, do NOT fake a grant. The real
                // OS prompt (AVCaptureDevice / CLLocationManager) lands in Phase 3.
                let permission = body?["permission"] as? String ?? "<none>"
                let choice = body?["choice"] as? String ?? "<none>"
                print("[PreloginWebView] requestPermission bridge received (permission: \(permission), choice: \(choice)) — Phase 3 stub, OS prompt not wired yet")
            case "complete":
                // Flow finished → hand off to the existing post-login path.
                onComplete()
            default:
                print("[PreloginWebView] unhandled bridge action: \(action)")
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
