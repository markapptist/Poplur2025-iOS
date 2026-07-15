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

        let webView = WKWebView(frame: .zero, configuration: configuration)
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

        var runtimeSource = approvedSource.replacingOccurrences(
            of: "/Poplur2025-iOS/Poplur2025/poplur_splash.mp4",
            with: "poplur_splash.mp4"
        )
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
}
