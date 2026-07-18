import SwiftUI
import WebKit
import UniformTypeIdentifiers

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
            let response = URLResponse(
                url: url,
                mimeType: mime,
                expectedContentLength: data.count,
                textEncodingName: mime.hasPrefix("text/") || mime == "application/json" ? "utf-8" : nil
            )
            urlSchemeTask.didReceive(response)
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

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private let auth: AuthViewModel
        private let onComplete: () -> Void
        private let popHaptic = UIImpactFeedbackGenerator(style: .medium)

        init(auth: AuthViewModel, onComplete: @escaping () -> Void) {
            self.auth = auth
            self.onComplete = onComplete
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
                // TODO Phase 3: route to Firebase auth via AuthViewModel. The
                // approved web forms do not post credentials yet, so do NOT fake
                // success — a returning session still resolves through the
                // existing AuthViewModel state listener.
                let email = body?["email"] as? String ?? "<none>"
                let method = body?["method"] as? String ?? "password"
                print("[PreloginWebView] signIn bridge received (email: \(email), method: \(method)) — Phase 3 stub, not wired to auth yet")
            case "signUp":
                // TODO Phase 3: route to AuthViewModel sign-up.
                let email = body?["email"] as? String ?? "<none>"
                let accountType = body?["accountType"] as? String ?? "<none>"
                print("[PreloginWebView] signUp bridge received (email: \(email), accountType: \(accountType)) — Phase 3 stub, not wired to auth yet")
            case "requestPermission":
                // TODO Phase 3: trigger the real OS prompt (AVCaptureDevice /
                // CLLocationManager). For now log only — do NOT fake a grant.
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
    }
}
