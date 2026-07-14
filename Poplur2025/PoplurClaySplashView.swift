import SwiftUI
import AVFoundation

// MARK: - Launch splash

/// Cold-launch splash: plays the clay intro clip full-bleed (1:1 device) with the
/// app's pop sound, then raises a centered loading bar whose lines are drawn with a
/// Metal shader. Stays up until auth has resolved, then routes underneath (Feed/Welcome).
struct PoplurClaySplashView: View {
    @EnvironmentObject private var auth: AuthViewModel
    var onFinished: () -> Void

    @State private var lines: [String] = SplashLoadingLines.sessionLines()
    @State private var currentMessage = ""
    @State private var showLoader = false
    @State private var progress: CGFloat = 0
    @State private var authResolved = false
    @State private var stopMessages = false
    @State private var didStartLoader = false
    @State private var didFinish = false

    private let introDuration: Double = 2.83
    private let fillDuration: Double = 3.2   // cosmetic slow creep — does NOT gate routing
    private let minVisible: Double = 1.1     // brief floor so the slow fill is actually seen

    var body: some View {
        ZStack {
            Color(red: 0.039, green: 0.027, blue: 0.035).ignoresSafeArea()

            SplashVideoPlayer(resourceName: "poplur_splash", onEnded: startLoader)
                .ignoresSafeArea()

            if showLoader {
                // soft radial scrim so the shader lines read over the busy clay scene
                RadialGradient(
                    colors: [Color.black.opacity(0.72), Color.black.opacity(0.30), .clear],
                    center: .center, startRadius: 8, endRadius: 260
                )
                .ignoresSafeArea()
                .transition(.opacity)

                loader
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .onAppear(perform: setup)
        .onChange(of: auth.isResolvingAuthState) { _, resolving in
            if !resolving { authResolved = true }
        }
    }

    private var loader: some View {
        VStack(spacing: 15) {
            Text(currentMessage)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .modifier(SplashShaderText())
                .shadow(color: Color(red: 0.96, green: 0.23, blue: 0.60).opacity(0.5), radius: 12)
                .id(currentMessage)
                .transition(.opacity)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color(red: 1, green: 0.54, blue: 0.78),
                                     Color(red: 0.96, green: 0.23, blue: 0.60),
                                     Color(red: 0.79, green: 0.18, blue: 0.49)],
                            startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geo.size.width * progress))
                }
            }
            .frame(width: min(340, UIScreen.main.bounds.width * 0.82), height: 14)
            .overlay(Capsule().strokeBorder(Color(red: 0.96, green: 0.23, blue: 0.60).opacity(0.35), lineWidth: 1))
        }
        .padding(.horizontal, 30)
    }

    // MARK: sequence

    private func setup() {
        currentMessage = lines.first ?? "Loading Poplur"
        if !auth.isResolvingAuthState { authResolved = true }

        // audible pops even on the ring/silent switch; mix with anything already playing
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)

        // refresh the funny lines for next launch (background, best-effort)
        SplashLoadingLines.refreshFromClaudeInBackground()

        // safety net: if the clip fails to signal its end, start the loader anyway
        DispatchQueue.main.asyncAfter(deadline: .now() + introDuration + 0.6) {
            startLoader()
        }
    }

    private func startLoader() {
        guard !didStartLoader else { return }
        didStartLoader = true
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { showLoader = true }
        Task { await runLoader() }
    }

    private func runLoader() async {
        let shownAt = Date()
        rotateMessages()

        // Cosmetic: let the bar creep up slowly toward near-full. This animation never
        // gates completion — routing fires as soon as auth resolves, so the real load
        // is not slowed by the slower fill.
        await MainActor.run {
            withAnimation(.easeOut(duration: fillDuration)) { progress = 0.9 }
        }

        // Finish the moment real load (auth) is known, after a short visible floor.
        while !authResolved { try? await Task.sleep(nanoseconds: 60_000_000) }
        let elapsed = Date().timeIntervalSince(shownAt)
        if elapsed < minVisible {
            try? await Task.sleep(nanoseconds: UInt64((minVisible - elapsed) * 1_000_000_000))
        }
        stopMessages = true

        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.25)) {
                currentMessage = SplashLoadingLines.destinationLine(loggedIn: auth.isAuthenticated)
            }
            withAnimation(.easeOut(duration: 0.5)) { progress = 1.0 }
        }
        try? await Task.sleep(nanoseconds: 700_000_000)
        finish()
    }

    private func rotateMessages() {
        Task {
            var i = 1
            while !stopMessages {
                try? await Task.sleep(nanoseconds: 850_000_000)
                if stopMessages { break }
                let next = lines[i % lines.count]
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.25)) { currentMessage = next }
                }
                i += 1
            }
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }
}

// MARK: - Shader-driven loading text

@available(iOS 17.0, *)
private struct SplashShaderTextRenderer: TextRenderer {
    var time: Double
    var animatableData: Double {
        get { time }
        set { time = newValue }
    }
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        context.addFilter(
            .colorShader(ShaderLibrary.poplurSplashText(.float(Float(time)), .float(1.0)))
        )
        for line in layout { context.draw(line) }
    }
}

/// Paints text with the animated `poplurSplashText` Metal shader (glossy pink sweep).
struct SplashShaderText: ViewModifier {
    @State private var epoch = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            if reduceMotion {
                content.textRenderer(SplashShaderTextRenderer(time: 0))
            } else {
                TimelineView(.periodic(from: epoch, by: 1.0 / 20.0)) { timeline in
                    let t = timeline.date.timeIntervalSince(epoch)
                    content.textRenderer(SplashShaderTextRenderer(time: t))
                }
            }
        } else {
            content.foregroundStyle(Color(red: 0.96, green: 0.23, blue: 0.60))
        }
    }
}

// MARK: - Full-bleed video (resizeAspectFill = 1:1 device, with sound)

private struct SplashVideoPlayer: UIViewRepresentable {
    let resourceName: String
    var onEnded: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEnded: onEnded) }

    final class Coordinator {
        let onEnded: () -> Void
        var player: AVPlayer?
        var endObserver: NSObjectProtocol?
        init(onEnded: @escaping () -> Void) { self.onEnded = onEnded }
        deinit { if let o = endObserver { NotificationCenter.default.removeObserver(o) } }
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") else {
            // no clip → let the loader start immediately
            DispatchQueue.main.async { context.coordinator.onEnded() }
            return view
        }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = false
        player.actionAtItemEnd = .pause
        context.coordinator.player = player
        context.coordinator.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { _ in context.coordinator.onEnded() }
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill   // fill the whole device
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {}

    final class PlayerView: UIView {
        let playerLayer = AVPlayerLayer()
        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = UIColor(red: 0.039, green: 0.027, blue: 0.035, alpha: 1)
            layer.addSublayer(playerLayer)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}
