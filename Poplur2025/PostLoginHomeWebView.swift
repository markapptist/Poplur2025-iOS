import SwiftUI
import WebKit
import FirebaseAuth
import FirebaseFirestore

// MARK: - Post-login HOME Web Embed (Phase 3)
//
// The approved post-login home is the poplur-clay-map ViewHarness home twin,
// served at ?view=home. It ships in the SAME bundle the clay map already embeds
// (ClayMapWeb/, synced by poplur-clay-map/scripts/sync-mobile.sh) — App.tsx routes
// to <ViewHarness> whenever a ?view= / #view is present, else the map. So the home
// reuses the exact custom-scheme + bridge infrastructure PoplurClayMapView ships:
// the same origin, scheme handler, and `poplur` message channel.
//
// This intentionally REPLACES the native HomeView with the approved web home. The
// home's tabs (map/feed/camera/profile) are the web twin today; real device power
// (native camera + ML, live feed, notifications) is bridged in over later phases
// through the same JS⇄native `poplur` channel that already drives the map's
// haptics/flyTo and the pre-login screens' Firebase auth — the shell lands first,
// functionality is wired in tab by tab.
//
// Reversible: PoplurWebHome.isEnabled (UserDefaults "poplur_web_home", default on)
// flips back to the native HomeView without a rebuild if the web home regresses.

enum PoplurWebHome {
    /// Feature flag: flip off to fall back to the native HomeView.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "poplur_web_home") as? Bool ?? true
    }

    /// The approved home twin: the shared clay bundle opened on its home tab.
    /// `tabs=1` shows the bottom tab pills; the scheme handler ignores the query
    /// and serves index.html, while App.tsx reads ?view / #view to pick the view.
    static var homeURL: URL? {
        URL(string: "\(PoplurClayWebMap.scheme)://\(PoplurClayWebMap.host)/index.html?view=home&tabs=1&v=\(PoplurPreloginWeb.buildStamp)")
    }
}

struct PostLoginHomeWebView: UIViewRepresentable {
    let onReady: () -> Void
    /// Tap on bridge events the host cares about (tabChanged / cameraShutter /
    /// cameraControl → the native web-home camera layer). Every message still
    /// flows to the shared clay bridge afterwards.
    let onWebEvent: ((String, [String: Any]) -> Void)?

    init(onReady: @escaping () -> Void = {}, onWebEvent: ((String, [String: Any]) -> Void)? = nil) {
        self.onReady = onReady
        self.onWebEvent = onWebEvent
    }

    func makeCoordinator() -> Coordinator { Coordinator(onReady: onReady, onWebEvent: onWebEvent) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.userContentController.add(context.coordinator, name: "poplur")
        config.userContentController.add(context.coordinator, name: "homeReady")
        config.userContentController.addUserScript(
            WKUserScript(
                source: Self.readinessScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        if let webRoot = PoplurClayMapView.bundledRootURL() {
            config.setURLSchemeHandler(
                PoplurClayMapView.ClayMapSchemeHandler(rootDirectory: webRoot),
                forURLScheme: PoplurClayWebMap.scheme
            )
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        // OPAQUE by default. A transparent WKWebView made WebKit fail to
        // composite media layers: the map iframe ran (audio playing) without
        // ever being visible, and feed clips never started. Transparency is now
        // switched on ONLY while the camera tab is front (see setCameraHole),
        // which is the only surface that needs the punch-through.
        webView.isOpaque = true
        webView.backgroundColor = UIColor(red: 5/255, green: 4/255, blue: 7/255, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.overrideUserInterfaceStyle = .dark
        context.coordinator.bridge.webView = webView

        if PoplurClayMapView.bundledRootURL() != nil, let url = PoplurWebHome.homeURL {
            webView.load(URLRequest(url: url))
        } else {
            print("[PostLoginHomeWebView] ClayMapWeb bundle missing — run poplur-clay-map/scripts/sync-mobile.sh")
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onReady = onReady
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "poplur")
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "homeReady")
    }

    private static let readinessScript = #"""
        (() => {
          let sent = false;
          const signalReady = () => {
            if (sent) return;
            sent = true;
            window.webkit.messageHandlers.homeReady.postMessage({ type: "ready" });
          };
          const afterLoad = () => {
            const fontsReady = document.fonts?.ready ?? Promise.resolve();
            Promise.resolve(fontsReady).then(() => {
              requestAnimationFrame(() => requestAnimationFrame(() => {
                setTimeout(signalReady, 250);
              }));
            });
          };
          if (document.readyState === "complete") afterLoad();
          else window.addEventListener("load", afterLoad, { once: true });
        })();
        """#

    /// Punch-through only for the camera tab (see the opacity note above).
    static func setCameraHole(_ on: Bool, on webView: WKWebView) {
        webView.isOpaque = !on
        let opaqueBg = UIColor(red: 5/255, green: 4/255, blue: 7/255, alpha: 1)
        webView.backgroundColor = on ? .clear : opaqueBg
        webView.scrollView.backgroundColor = webView.backgroundColor
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let bridge = PoplurClayMapView.Coordinator()
        var onReady: () -> Void
        let onWebEvent: ((String, [String: Any]) -> Void)?
        private var didSignalReady = false

        init(onReady: @escaping () -> Void, onWebEvent: ((String, [String: Any]) -> Void)? = nil) {
            self.onReady = onReady
            self.onWebEvent = onWebEvent
        }

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            if message.name == "homeReady" {
                guard !didSignalReady else { return }
                didSignalReady = true
                DispatchQueue.main.async { [onReady] in onReady() }
                return
            }
            if let body = message.body as? [String: Any],
               let type = body["type"] as? String {
                if type == "requestCameraRoll", let webView = bridge.webView {
                    // The web roll's Allow → real OS photo permission → recent
                    // photo thumbnails pushed back as data URIs.
                    DispatchQueue.main.async { WebCameraRollProvider.push(into: webView) }
                }
                if type == "requestProfile", let webView = bridge.webView {
                    DispatchQueue.main.async { Self.pushProfile(into: webView) }
                }
                if type == "tabChanged", let webView = bridge.webView {
                    let isCamera = (body["tab"] as? String) == "post"
                    DispatchQueue.main.async {
                        PostLoginHomeWebView.setCameraHole(isCamera, on: webView)
                    }
                }
                if let onWebEvent {
                    DispatchQueue.main.async { onWebEvent(type, body) }
                }
            }
            bridge.userContentController(userContentController, didReceive: message)
        }

        private static func pushProfile(into webView: WKWebView) {
            guard let user = Auth.auth().currentUser else { return }
            let fallback = user.displayName
                ?? user.email?.split(separator: "@").first.map(String.init)
                ?? "Poplur user"

            func deliver(username: String, business: Bool) {
                let payload: [String: Any] = ["username": username, "business": business]
                guard let data = try? JSONSerialization.data(withJSONObject: payload),
                      let json = String(data: data, encoding: .utf8) else { return }
                webView.evaluateJavaScript("window.poplurProfile?.(\(json));")
            }

            Firestore.firestore().collection("users").document(user.uid).getDocument { snapshot, _ in
                let data = snapshot?.data()
                let username = (data?["username"] as? String)
                    ?? (data?["displayName"] as? String)
                    ?? fallback
                let accountType = (data?["accountType"] as? String)?.lowercased()
                let business = accountType == "business"
                    || data?["isBusinessAccount"] as? Bool == true
                    || data?["businessProfile"] != nil
                DispatchQueue.main.async { deliver(username: username, business: business) }
            }
        }
    }
}
