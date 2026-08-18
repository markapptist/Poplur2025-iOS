import SwiftUI
import WebKit

// MARK: - Post-login approved splash embed
//
// This host deliberately loads PoplurPreloginWeb.splashURL: the identical
// bundled splash.html used while signed out. There is no alternate post-login
// loading design and no native visual recreation.

struct PostLoginLoadingWebView: UIViewRepresentable {
    /// Receives the injected splash probe. This host had no message handler at
    /// all, which is why instrumenting only PreloginWebView produced media
    /// requests (the scheme handler class is shared by both hosts) and not a
    /// single video report: a signed-in launch never goes through that host.
    final class Coordinator: NSObject, WKScriptMessageHandler {
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == "poplur",
                  let body = message.body as? [String: Any],
                  (body["type"] as? String) == "splashVideoDiag" else { return }
            let stage = body["stage"] as? String ?? "?"
            let readyState = body["readyState"] as? Int ?? -1
            let networkState = body["networkState"] as? Int ?? -1
            let paused = (body["paused"] as? Bool).map(String.init) ?? "?"
            let ready = (body["ready"] as? Bool).map(String.init) ?? "?"
            let errorCode = body["errorCode"] as? Int ?? 0
            PoplurDiagLog.append(
                "[PostLoginLoadingSplash] video \(stage) readyState=\(readyState) "
                + "network=\(networkState) paused=\(paused) ready=\(ready) err=\(errorCode)"
            )
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Same probe the pre-login host injects, so the two paths are comparable.
        config.userContentController.add(context.coordinator, name: "poplur")
        config.userContentController.addUserScript(
            WKUserScript(source: PoplurPreloginWeb.splashVideoProbe,
                         injectionTime: .atDocumentEnd,
                         forMainFrameOnly: true)
        )
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
        // Keep this document's runtime alive WITHOUT taking the heavy-renderer
        // lease. That combination is the whole fix.
        //
        // The cover is deliberately priority 100 so Home wins the single heavy
        // renderer and can reach its first frame -- raising it deadlocked the
        // handoff, which is why it was lowered. But losing that lease SUSPENDS
        // the document, and a suspended document cannot start playback. Measured
        // on device: the clip reached readyState=4 (HAVE_ENOUGH_DATA), network=1
        // (idle), err=0 -- fully buffered and perfectly decodable -- and stayed
        // paused=true forever, with `playing` never firing. splash.html reveals
        // the video only once playback starts (its three paths all require it,
        // and the play() rejection is swallowed), so .ready was never added, the
        // clip sat at opacity 0, and the logo fallback covered a working video.
        // The looping progress bar underneath is CSS on the compositor, which
        // runs regardless -- which is what made this look like a hung loader.
        //
        // poplurIsRuntimeActive treats lightweight-overlay mode as a third way to
        // stay live besides holding the lease, which is exactly what a cover that
        // must animate while yielding to Home needs.
        webView.setLightweightOverlayMode(true)

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
        // A launch showing the logo on black instead of the clip was NOT the
        // WebView still starting up, as this comment used to claim. Device
        // measurement showed the opposite: the clip is fully buffered
        // (readyState=4, err=0) and simply never permitted to play, because the
        // cover had yielded the renderer lease and its document was suspended.
        // setLightweightOverlayMode above is what fixes it. Left recorded here
        // because that guess is why the fallback was read as a slow start for
        // months instead of as a stuck one.
        if PreloginWebView.bundledRootURL() != nil, let url = PoplurPreloginWeb.splashURL {
            webView.load(URLRequest(url: url))
        } else {
            print("[PostLoginLoadingWebView] PreloginWeb/splash.html missing — run scripts/build-prelogin-ios.mjs")
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        (uiView as? PoplurManagedWebView)?.poplurTearDown()
    }
}
