import SwiftUI
import WebKit
import UniformTypeIdentifiers

// MARK: - Clay Web Map (Phase 1 embed)
//
// The Poplur clay map (Mapbox GL JS, built from the poplur-clay-map repo)
// running as the map tab's surface inside a WKWebView. The bundle lives in
// ClayMapWeb/ (synced by poplur-clay-map/scripts/sync-mobile.sh).
//
// Native ⇄ web bridge:
//   JS → Swift: window.webkit.messageHandlers.poplur.postMessage({type, ...})
//     "pop"    → haptic tap
//     "poiTap" → route to channel/post (Phase 1.5)
//   Swift → JS: window.__poplurNative.{setCenter,flyTo,setSky,setWeather}

enum PoplurClayWebMap {
    /// Feature flag: flip off to fall back to the native MapKit map tab.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "poplur_clay_web_map") as? Bool ?? true
    }

    /// The web bundle is served over a custom scheme rather than `file://`.
    /// A `file://` page has an opaque origin, so WebKit blocks the Vite bundle's
    /// `<script type="module">`, its Web Workers and its dynamic `import()` calls —
    /// the script never runs and the map renders as the page's #050407 background
    /// (a black screen). A custom scheme gives a real origin where all three work.
    static let scheme = "poplur-clay"
    static let host = "app"

    static var indexURL: URL? { URL(string: "\(scheme)://\(host)/index.html") }
}

struct PoplurClayMapView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "poplur")

        let webRoot = Self.bundledRootURL()
        if let webRoot {
            config.setURLSchemeHandler(ClayMapSchemeHandler(rootDirectory: webRoot),
                                       forURLScheme: PoplurClayWebMap.scheme)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 5/255, green: 4/255, blue: 7/255, alpha: 1)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.webView = webView
        // Required for the delegate above to ever be consulted.
        webView.uiDelegate = context.coordinator

        if webRoot != nil, let indexURL = PoplurClayWebMap.indexURL {
            var components = URLComponents(url: indexURL, resolvingAgainstBaseURL: false)
            let use3D = SettingsStore.shared.use3DMap
            components?.queryItems = [
                URLQueryItem(name: "mapMode", value: use3D ? "3d" : "2d"),
                URLQueryItem(
                    name: "fallback2d",
                    value: !use3D && SettingsStore.prefers2DMapForThisDevice ? "1" : "0"
                )
            ]
            webView.load(URLRequest(url: components?.url ?? indexURL))
        } else {
            print("[PoplurClayMapView] ClayMapWeb bundle missing — run poplur-clay-map/scripts/sync-mobile.sh")
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    /// Directory holding the synced web bundle (`ClayMapWeb/index.html` + assets).
    /// Deliberately does *not* fall back to a bare `index.html` lookup: other
    /// bundled web content (PoplurFPS) also ships an `index.html`, and loading
    /// that here would silently render the wrong page.
    static func bundledRootURL() -> URL? {
        Bundle.main
            .url(forResource: "index", withExtension: "html", subdirectory: "ClayMapWeb")?
            .deletingLastPathComponent()
    }

    /// Serves the bundled ClayMapWeb files over `PoplurClayWebMap.scheme` so the page
    /// gets a real origin (see the note on `PoplurClayWebMap`). Reads are confined to
    /// `rootDirectory`.
    final class ClayMapSchemeHandler: NSObject, WKURLSchemeHandler {
        private let root: URL

        init(rootDirectory: URL) {
            self.root = rootDirectory.standardizedFileURL
        }

        // WKWebView does NOT apply HTTP caching to a custom scheme: the
        // Cache-Control header on these responses is inert, so every asset was
        // re-resolved, re-opened and re-wrapped in a response on every single
        // use. This handler was the hottest app symbol in two separate device
        // CPU profiles because of it. Hold the mapped bytes here instead —
        // bundle assets cannot change without a new build, and the data is
        // memory-mapped, so this costs virtual address space rather than RAM.
        private final class CachedAsset: NSObject {
            let data: Data
            let mime: String

            init(data: Data, mime: String) {
                self.data = data
                self.mime = mime
            }
        }

        private static func cachedAsset(_ key: String) -> (data: Data, mime: String)? {
            guard let cached: CachedAsset = PoplurAssetCache.shared.asset(
                forKey: "ClayMapWeb:\(key)",
                category: .webAsset
            ) else { return nil }
            return (cached.data, cached.mime)
        }

        private static func cacheAsset(_ key: String, data: Data, mime: String) {
            _ = PoplurAssetCache.shared.insert(
                CachedAsset(data: data, mime: mime),
                forKey: "ClayMapWeb:\(key)",
                category: .webAsset,
                estimatedByteCost: max(1, data.count)
            )
        }

        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            guard let url = urlSchemeTask.request.url else {
                urlSchemeTask.didFailWithError(URLError(.badURL))
                return
            }

            var relativePath = url.path
            if relativePath.isEmpty || relativePath == "/" { relativePath = "/index.html" }

            let data: Data
            let mime: String
            // Captures are the user's own media and can change under the same
            // key, so they must never be cached. Everything else ships inside
            // the app bundle and cannot change without a new build.
            let cacheControl = relativePath.hasPrefix("/captures/")
                ? "no-store"
                : "public, max-age=31536000, immutable"
            if relativePath.hasPrefix("/captures/") {
                let key = String(relativePath.dropFirst("/captures/".count))
                guard !key.contains("/"),
                      let item = PoplurWebCaptureStore.item(for: key),
                      let captureData = item.data ?? (item.fileURL.flatMap { try? Data(contentsOf: $0) }) else {
                    urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                    return
                }
                data = captureData
                mime = item.mimeType
            } else {
                // Cache hit: reuse the mapped bytes but still fall through to
                // the range/response logic below, so byte-range requests (video
                // seeking) keep working exactly as they did.
                if let hit = Self.cachedAsset(relativePath) {
                    data = hit.data
                    mime = hit.mime
                } else {
                let fileURL = root.appendingPathComponent(String(relativePath.dropFirst())).standardizedFileURL

                // Confine reads to the bundle directory (no `../` traversal).
                guard fileURL.path.hasPrefix(root.path + "/") || fileURL.path == root.path,
                      // .mappedIfSafe: the file is paged in as it is read rather
                      // than copied whole into memory. A byte-range request for a
                      // video used to load the entire clip just to slice it.
                      let fileData = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
                    urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                    return
                }
                data = fileData
                mime = Self.mimeType(forExtension: fileURL.pathExtension)
                Self.cacheAsset(relativePath, data: data, mime: mime)
                }
            }

            // BYTE-RANGE support — required for <video> over a custom scheme in
            // WKWebView (feed ad clips, splash); without a 206 + Content-Range the
            // media element fails silently and renders black.
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
                    "Accept-Ranges": "bytes",
                    "Cache-Control": cacheControl
                ]
                if let response = HTTPURLResponse(url: url, statusCode: 206,
                                                  httpVersion: "HTTP/1.1", headerFields: headers) {
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(slice)
                    urlSchemeTask.didFinish()
                    return
                }
            }

            let headers = [
                "Content-Type": mime,
                "Content-Length": "\(data.count)",
                "Accept-Ranges": "bytes",
                "Cache-Control": cacheControl
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
            case "mp4":          return "video/mp4"
            case "wav":          return "audio/wav"
            case "webp":         return "image/webp"
            case "png":          return "image/png"
            default:
                return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
            }
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKUIDelegate {
        weak var webView: WKWebView?
        private let popHaptic = UIImpactFeedbackGenerator(style: .medium)

        // WKWebView refuses getUserMedia unless the host answers this. Without
        // it the studio's RECORD button did nothing whatsoever: the promise
        // never resolved, so no recording started and no error surfaced either.
        // The app already holds the real system permission; this only forwards
        // that decision to the web layer rather than granting anything new.
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        // Same story for geolocation. WKWebView treats the embedded page as a
        // WEBSITE and asks its own question — the sheet reads
        // «"app" would like to use your current location», naming the custom
        // scheme's host rather than Poplur, on top of the OS permission the app
        // already holds. Two prompts for one decision, and the second one does
        // not even look like it belongs to this app.
        //
        // Answering here forwards the decision the user already made to the OS.
        // It grants nothing new: if the app lacks location permission, CoreLocation
        // still returns nothing and the page gets nothing.
        func webView(_ webView: WKWebView,
                     requestGeolocationPermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "poplur",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String else { return }
            switch type {
            case "pop":
                popHaptic.impactOccurred()
            case "poiTap":
                // Phase 1.5: route body["id"] to the channel/post flow
                break
            case "profile":
                // The web heat probe's report line. Same contract as the home
                // webview: a WKWebView's console.log never reaches this
                // process's stdout, so native prints it where
                // `devicectl device process launch --console` can read it.
                // Without this case the probe is mute on the map tab — the one
                // surface the thermal work needs it on.
                if let line = body["line"] as? String { print(line) }
            case "publishPost":
                // The web composer finished a post (capture → filter → channel).
                // The account, Firebase Storage and the posts write all live on
                // this side, so decode the media and hand it to the SAME upload
                // path the native capture flow uses.
                handlePublishPost(body)
            default:
                break
            }
        }

        /// Decode a post finished in the web composer and hand it to the native
        /// upload path. Extracted to WebPostPublisher so the web HOME's bridge
        /// (where the camera composer actually lives) uses the same path — this
        /// coordinator was the only place that could publish, which left the
        /// home composer waiting on an upload that never started.
        private func handlePublishPost(_ body: [String: Any]) {
            WebPostPublisher.handle(body)
        }


        // MARK: Swift → JS

        func setCenter(latitude: Double, longitude: Double, zoom: Double? = nil) {
            let zoomArg = zoom.map { String($0) } ?? "undefined"
            webView?.evaluateJavaScript(
                "window.__poplurNative?.setCenter?.(\(longitude), \(latitude), \(zoomArg))")
        }

        func flyTo(latitude: Double, longitude: Double, zoom: Double) {
            webView?.evaluateJavaScript(
                "window.__poplurNative?.flyTo?.(\(longitude), \(latitude), \(zoom))")
        }

        func setSky(day: Bool) {
            webView?.evaluateJavaScript("window.__poplurNative?.setSky?.(\(day))")
        }

        func setWeather(_ mode: String?) {
            let arg = mode.map { "'\($0)'" } ?? "null"
            webView?.evaluateJavaScript("window.__poplurNative?.setWeather?.(\(arg))")
        }
    }
}
