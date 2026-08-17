import SwiftUI
import WebKit

// MARK: - Post-login approved splash embed
//
// This host deliberately loads PoplurPreloginWeb.splashURL: the identical
// bundled splash.html used while signed out. There is no alternate post-login
// loading design and no native visual recreation.

struct PostLoginLoadingWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = false
        config.allowsAirPlayForMediaPlayback = false

        if let webRoot = PreloginWebView.bundledRootURL() {
            config.setURLSchemeHandler(
                PreloginWebView.PreloginSchemeHandler(rootDirectory: webRoot),
                forURLScheme: PoplurPreloginWeb.scheme
            )
        }

        let webView = PoplurManagedWebView(
            performanceName: "PostLoginLoadingWeb",
            // Home owns the only foreground work lease while this visual cover
            // is present. Giving the cover the higher priority deadlocked the
            // handoff: Home's rAF-based ready signal could never run, so the
            // cover's short splash video looped forever. At a lower priority the
            // approved cover remains painted but inert while Home reaches its
            // first frame, then SwiftUI dismantles this WebView normally.
            priority: 100,
            configuration: config
        )
        // This is a non-interactive cover. Never let WebKit expose transport
        // controls or promote its splash clip into a remote media session.
        webView.isUserInteractionEnabled = false
        webView.isOpaque = false
        // The Loading screen paints its own clay-globe backdrop (#0a0709); match it
        // so there is no flash between the sign-in transition and the web loading.
        webView.backgroundColor = UIColor(red: 10/255, green: 7/255, blue: 9/255, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // The loading screen's dark styling lives behind prefers-color-scheme: dark
        // (same as welcome) — pin to dark regardless of device appearance.
        webView.overrideUserInterfaceStyle = .dark

        // The APPROVED clay splash is the SHORT VIDEO CLIP in splash.html — the
        // same one signed-out launch shows, so both paths agree. The globe Loading
        // screen is a different approved screen (kept for watch/wear); putting it
        // here was wrong and is reverted.
        //
        // Autoplay is already permitted above (mediaTypesRequiringUserActionForPlayback
        // is empty, inline playback on), and the clip is bundled at
        // PreloginWeb/Poplur2025-iOS/Poplur2025/poplur_splash.mp4 — both verified.
        // So when a launch shows the logo on black instead of the clip, that is the
        // WKWebView still starting up, not a missing or blocked video.
        if PreloginWebView.bundledRootURL() != nil, let url = PoplurPreloginWeb.splashURL {
            webView.load(URLRequest(url: url))
        } else {
            print("[PostLoginLoadingWebView] PreloginWeb/splash.html missing — run scripts/build-prelogin-ios.mjs")
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        (uiView as? PoplurManagedWebView)?.poplurTearDown()
    }
}
