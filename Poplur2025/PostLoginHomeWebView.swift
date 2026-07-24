import SwiftUI
import WebKit

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
        URL(string: "\(PoplurClayWebMap.scheme)://\(PoplurClayWebMap.host)/index.html?view=home&tabs=1")
    }
}

struct PostLoginHomeWebView: UIViewRepresentable {
    let onReady: () -> Void

    init(onReady: @escaping () -> Void = {}) {
        self.onReady = onReady
    }

    func makeCoordinator() -> Coordinator { Coordinator(onReady: onReady) }

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
        webView.isOpaque = false
        // Match the home twin's dark backdrop so there is no flash on the reveal.
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

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let bridge = PoplurClayMapView.Coordinator()
        var onReady: () -> Void
        private var didSignalReady = false

        init(onReady: @escaping () -> Void) {
            self.onReady = onReady
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
            bridge.userContentController(userContentController, didReceive: message)
        }
    }
}
