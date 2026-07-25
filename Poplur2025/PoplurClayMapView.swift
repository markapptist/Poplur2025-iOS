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

        if webRoot != nil, let indexURL = PoplurClayWebMap.indexURL {
            webView.load(URLRequest(url: indexURL))
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

        func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
            guard let url = urlSchemeTask.request.url else {
                urlSchemeTask.didFailWithError(URLError(.badURL))
                return
            }

            var relativePath = url.path
            if relativePath.isEmpty || relativePath == "/" { relativePath = "/index.html" }
            let fileURL = root.appendingPathComponent(String(relativePath.dropFirst())).standardizedFileURL

            // Confine reads to the bundle directory (no `../` traversal).
            guard fileURL.path.hasPrefix(root.path + "/") || fileURL.path == root.path,
                  let data = try? Data(contentsOf: fileURL) else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
                return
            }

            let mime = Self.mimeType(forExtension: fileURL.pathExtension)

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

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var webView: WKWebView?
        private let popHaptic = UIImpactFeedbackGenerator(style: .medium)

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
            default:
                break
            }
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
