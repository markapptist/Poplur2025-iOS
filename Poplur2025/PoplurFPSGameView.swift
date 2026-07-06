import SwiftUI
import WebKit

struct PoplurFPSGameSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            _FPSWebView()
                .ignoresSafeArea()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                    .frame(width: 56, height: 56)
            }
            .padding(.top, 60)
            .padding(.trailing, 18)
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

private struct _FPSWebView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        // Allow ES module scripts to load from file:// origin (required for type="module")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.bouncesZoom = false

        if let indexURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "PoplurFPS"
        ) {
            // Allow access to bundle root so the assets/ subfolder is reachable
            let bundleURL = Bundle.main.bundleURL
            webView.loadFileURL(indexURL, allowingReadAccessTo: bundleURL)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
