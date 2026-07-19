import SwiftUI
import WebKit

// MARK: - Post-login LOADING Web Embed (Phase 3)
//
// The approved post-login load screen is the prototype's web "Loading" screen
// (clay globe + wordmark + rotating clay messages, three.js) — NOT the old
// auth_transition.mp4. It is rendered inside a WKWebView exactly like the
// pre-login splash/welcome, reusing the same offline bundle root and custom
// URL-scheme handler (PoplurPreloginWeb.scheme / PreloginWebView.PreloginSchemeHandler).
//
// Built by scripts/build-loading-ios.mjs into PreloginWeb/loading.html (the flow's
// `?embed=Loading` screen, Draco models rewired to the bundled compressed copies).
// There is no bridge here — the screen only animates; the app controls how long it
// shows before revealing the post-login home.

extension PoplurPreloginWeb {
    /// The approved post-login loading screen (isolated via ?embed=Loading; the
    /// bundle also defaults to "Loading" if the query is dropped).
    static var loadingURL: URL? { URL(string: "\(scheme)://\(host)/loading.html?embed=Loading") }
}

struct PostLoginLoadingWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []

        if let webRoot = PreloginWebView.bundledRootURL() {
            config.setURLSchemeHandler(
                PreloginWebView.PreloginSchemeHandler(rootDirectory: webRoot),
                forURLScheme: PoplurPreloginWeb.scheme
            )
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = true
        // The Loading screen paints its own clay-globe backdrop (#0a0709); match it
        // so there is no flash between the sign-in transition and the web loading.
        webView.backgroundColor = UIColor(red: 10/255, green: 7/255, blue: 9/255, alpha: 1)
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // The loading screen's dark styling lives behind prefers-color-scheme: dark
        // (same as welcome) — pin to dark regardless of device appearance.
        webView.overrideUserInterfaceStyle = .dark

        if PreloginWebView.bundledRootURL() != nil, let url = PoplurPreloginWeb.loadingURL {
            webView.load(URLRequest(url: url))
        } else {
            print("[PostLoginLoadingWebView] PreloginWeb/loading.html missing — run scripts/build-loading-ios.mjs")
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
