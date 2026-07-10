import SwiftUI
import WebKit

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
}

struct PoplurClayMapView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "poplur")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 5/255, green: 4/255, blue: 7/255, alpha: 1)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.webView = webView

        if let indexURL = Self.bundledIndexURL() {
            webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
        } else {
            print("[PoplurClayMapView] ClayMapWeb bundle missing — run poplur-clay-map/scripts/sync-mobile.sh")
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    /// Synchronized groups may keep the ClayMapWeb folder or flatten it into
    /// the bundle root — accept either layout.
    static func bundledIndexURL() -> URL? {
        Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "ClayMapWeb")
            ?? Bundle.main.url(forResource: "index", withExtension: "html")
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
