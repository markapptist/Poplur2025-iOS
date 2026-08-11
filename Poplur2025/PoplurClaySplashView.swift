import SwiftUI
import UIKit
import WebKit

/// Displays the approved Good Copy Splash without recreating its design in SwiftUI.
/// The bundled HTML is a byte-for-byte copy of `good-copy-splash.html`; only its
/// workspace asset URLs are resolved to the equivalent bundled app resources.
struct PoplurClaySplashView: View {
    @EnvironmentObject private var auth: AuthViewModel

    let onFinished: () -> Void

    var body: some View {
        GoodCopySplashWebView()
            .background(Color(red: 10 / 255, green: 7 / 255, blue: 9 / 255))
            .task {
                try? await Task.sleep(for: .milliseconds(3200))
                while auth.isResolvingAuthState && !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard !Task.isCancelled else { return }
                onFinished()
            }
    }
}

private struct GoodCopySplashWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        let webView = PoplurManagedWebView(
            performanceName: "GoodCopySplashWeb",
            priority: 220,
            configuration: configuration
        )
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 10 / 255, green: 7 / 255, blue: 9 / 255, alpha: 1)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isUserInteractionEnabled = false

        guard
            let htmlURL = Bundle.main.url(forResource: "good-copy-splash", withExtension: "html"),
            let approvedSource = try? String(contentsOf: htmlURL, encoding: .utf8)
        else {
            assertionFailure("Approved Good Copy Splash resource is missing")
            return webView
        }

        // The clay-world video is INLINED, not referenced by filename.
        //
        // `loadHTMLString(_:baseURL:)` with a file:// baseURL does not grant the
        // loaded document read access to other files in that directory — WebKit
        // sandboxes it — so a relative "poplur_splash.mp4" could never load on
        // device. The splash therefore sat on the black backdrop showing only
        // the logo fallback, which is precisely what the fallback exists to
        // avoid being seen for long. The approved Good Copy markup is correct
        // and untouched; only the way the bytes reach it changes here, and it
        // is the same base64 substitution this function already does for the
        // logo below. ~350KB, read once while the splash is on screen.
        var runtimeSource = approvedSource
        if let videoURL = Bundle.main.url(forResource: "poplur_splash", withExtension: "mp4"),
           let videoData = try? Data(contentsOf: videoURL) {
            runtimeSource = runtimeSource.replacingOccurrences(
                of: "/Poplur2025-iOS/Poplur2025/poplur_splash.mp4",
                with: "data:video/mp4;base64,\(videoData.base64EncodedString())"
            )
        } else {
            // Video missing from the bundle: leave a relative path so the
            // markup stays valid, and let the logo fallback carry the screen.
            assertionFailure("Approved Good Copy Splash video is missing")
            runtimeSource = runtimeSource.replacingOccurrences(
                of: "/Poplur2025-iOS/Poplur2025/poplur_splash.mp4",
                with: "poplur_splash.mp4"
            )
        }
        if let fallback = UIImage(named: "logo")?.pngData()?.base64EncodedString() {
            runtimeSource = runtimeSource.replacingOccurrences(
                of: "/Poplur2025-iOS/Poplur2025/Assets.xcassets/logo.imageset/logo1.png",
                with: "data:image/png;base64,\(fallback)"
            )
        }

        webView.loadHTMLString(runtimeSource, baseURL: Bundle.main.bundleURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: ()) {
        (webView as? PoplurManagedWebView)?.poplurTearDown()
    }
}
