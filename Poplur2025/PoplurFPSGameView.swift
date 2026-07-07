import SwiftUI
import WebKit

struct PoplurFPSGameSheet: View {
    var onClose: (() -> Void)? = nil

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Native SpriteKit game (replaces the old WKWebView build).
            FPSSpriteKitView()
                .ignoresSafeArea()

            Button {
                onClose?()
            } label: {
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
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")

        // Inject CSS to make the arcade cabinet fill the whole screen on mobile
        let mobileCSSScript = WKUserScript(
            source: mobileCSSInjection,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(mobileCSSScript)

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
            let bundleURL = Bundle.main.bundleURL
            webView.loadFileURL(indexURL, allowingReadAccessTo: bundleURL)
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    private var mobileCSSInjection: String {
        """
        (function() {
          var style = document.createElement('style');
          // The game now renders its whole arcade cabinet + FPS on the canvas
          // itself (see PoplurFPS/src). The page's own styles.css already
          // centers and aspect-fits #game-canvas, so we must NOT force the
          // canvas to fill the viewport (that stretches/distorts it). Keep this
          // injection minimal: fullscreen black backdrop + no tap callouts.
          style.textContent = `
            html, body, #app {
              height: 100vh !important;
              width: 100vw !important;
              overflow: hidden !important;
              margin: 0 !important;
              padding: 0 !important;
              background: #000 !important;
            }
            * {
              -webkit-tap-highlight-color: transparent !important;
              -webkit-touch-callout: none !important;
              -webkit-user-select: none !important;
              user-select: none !important;
            }
          `;
          document.head.appendChild(style);
        })();
        """
    }
}
