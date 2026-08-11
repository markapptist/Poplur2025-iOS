import SwiftUI
import WebKit

struct PoplurFPSGameSheet: View {
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    /// Prefer the caller's handler; otherwise dismiss the presenting cover.
    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Native SpriteKit game (replaces the old WKWebView build).
            FPSSpriteKitView(onQuit: { close() })
                .ignoresSafeArea()

            Button {
                close()
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
        .onAppear { AppDelegate.fpsGameActive = true }
        .onDisappear {
            AppDelegate.fpsGameActive = false
            // Snap the app back to portrait when leaving the game.
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
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

        let webView = PoplurManagedWebView(
            performanceName: "FPSGameWeb",
            priority: 240,
            configuration: config
        )
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

    static func dismantleUIView(_ uiView: WKWebView, coordinator: ()) {
        (uiView as? PoplurManagedWebView)?.poplurTearDown()
    }

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
