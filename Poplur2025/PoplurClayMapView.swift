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
        private static var assetCache: [String: (data: Data, mime: String)] = [:]
        private static let assetCacheLock = NSLock()

        private static func cachedAsset(_ key: String) -> (data: Data, mime: String)? {
            assetCacheLock.lock(); defer { assetCacheLock.unlock() }
            return assetCache[key]
        }

        private static func cacheAsset(_ key: String, data: Data, mime: String) {
            assetCacheLock.lock(); defer { assetCacheLock.unlock() }
            // Bounded so a long session cannot accumulate every capture-sized
            // blob the page ever asked for.
            if assetCache.count > 400 { assetCache.removeAll(keepingCapacity: true) }
            assetCache[key] = (data, mime)
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
        /// upload path. The web bundle has no account, so it sends the baked
        /// media as a data: URL; everything authenticated happens here.
        private func handlePublishPost(_ body: [String: Any]) {
            guard let dataUrl = body["data"] as? String,
                  let payload = Self.decodeDataURL(dataUrl) else { return }
            let kind = body["kind"] as? String ?? "photo"

            // Radius and caption cannot ride on the image-only upload
            // notifications, so stage them for the upload that follows.
            if let radiusKm = body["radiusKm"] as? Double {
                PostUploadService.shared.nextRadiusMeters = Int(radiusKm * 1000)
            }
            PostUploadService.shared.nextCaption = body["caption"] as? String
            PostUploadService.shared.nextRequestID = body["requestId"] as? String

            var userInfo: [String: Any] = [:]
            if kind == "video" {
                // A recording has to become a file URL for the uploader.
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("poplur-post-\(UUID().uuidString).mp4")
                guard (try? payload.write(to: url)) != nil else { return }
                userInfo["videoURL"] = url
            } else {
                guard let image = UIImage(data: payload) else { return }
                userInfo["image"] = image
            }

            // A post bound to a map spot carries its coordinate; a plain channel
            // post uploads to wherever the user currently is.
            if let latitude = body["latitude"] as? Double,
               let longitude = body["longitude"] as? Double {
                userInfo["latitude"] = latitude
                userInfo["longitude"] = longitude
                NotificationCenter.default.post(
                    name: Notification.Name("UploadPostToCoordinate"),
                    object: nil,
                    userInfo: userInfo
                )
            } else if let image = userInfo["image"] as? UIImage {
                NotificationCenter.default.post(
                    name: Notification.Name("UploadImageToCurrentCoordinate"), object: image
                )
            } else if let videoURL = userInfo["videoURL"] as? URL {
                NotificationCenter.default.post(
                    name: Notification.Name("UploadVideoToCurrentCoordinate"), object: videoURL
                )
            }
        }

        /// `data:<mime>;base64,<payload>` → raw bytes.
        private static func decodeDataURL(_ value: String) -> Data? {
            guard let comma = value.firstIndex(of: ","), value.hasPrefix("data:") else { return nil }
            let encoded = String(value[value.index(after: comma)...])
            return Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
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
