import AVFoundation
import SwiftUI

/// Cold-launch splash matching the canonical Good Copy: a looping clay scene with
/// an always-visible shader-text loader and independently animated barber-pole fill.
struct PoplurClaySplashView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinished: () -> Void

    @State private var progress: CGFloat = 0.04
    @State private var messageIndex = 0
    @State private var messageOpacity = 1.0
    @State private var didFinish = false

    private let minimumVisibleDuration: TimeInterval = 2.8
    private let maximumAuthWait: TimeInterval = 8.0

    private let messages = [
        "Warming up the pinetrees",
        "Rolling out the clay roads",
        "Teaching the pin to drop",
        "Sprinkling pink stars",
        "Kneading the little mountains",
        "Waking up the tugboat",
        "Polishing the big P",
        "Fluffing the clouds",
    ]

    var body: some View {
        GeometryReader { geometry in
            let loaderWidth = min(geometry.size.width * 0.58, 215)

            ZStack {
                Color(red: 0.039, green: 0.027, blue: 0.035)

                SplashLoopingVideoPlayer(resourceName: "poplur_splash")
                    .ignoresSafeArea()

                RadialGradient(
                    colors: [Color.black.opacity(0.55), Color.black.opacity(0.20), .clear],
                    center: UnitPoint(x: 0.5, y: 0.56),
                    startRadius: 8,
                    endRadius: max(geometry.size.width, geometry.size.height) * 0.45
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                loader(width: loaderWidth)
                    .position(
                        x: geometry.size.width / 2,
                        y: geometry.size.height * 0.68
                    )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(Color(red: 0.039, green: 0.027, blue: 0.035))
        .ignoresSafeArea()
        .task {
            await runProgressSequence()
        }
        .task {
            await rotateMessages()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading Poplur")
        .accessibilityValue(messages[messageIndex])
    }

    private func loader(width: CGFloat) -> some View {
        VStack(spacing: 16) {
            Text(messages[messageIndex])
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: width, height: 26)
                .modifier(SplashShaderText())
                .shadow(
                    color: Color(red: 0.957, green: 0.231, blue: 0.600).opacity(0.5),
                    radius: 12
                )
                .opacity(messageOpacity)

            GeometryReader { track in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(red: 0.110, green: 0.031, blue: 0.071).opacity(0.55))

                    SplashBarberPoleFill(reduceMotion: reduceMotion)
                        .frame(width: max(0, track.size.width * progress))
                        .clipShape(Capsule())
                        .shadow(
                            color: Color(red: 0.957, green: 0.231, blue: 0.600).opacity(0.32),
                            radius: 8
                        )
                }
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(
                            Color(red: 0.957, green: 0.231, blue: 0.600).opacity(0.35),
                            lineWidth: 1
                        )
                }
            }
            .frame(width: width, height: 9)
        }
        .frame(width: width)
        .allowsHitTesting(false)
    }

    @MainActor
    private func runProgressSequence() async {
        let startedAt = Date()

        if reduceMotion {
            progress = 0.70
        } else {
            withAnimation(.easeOut(duration: 4.0)) {
                progress = 0.90
            }
        }

        while auth.isResolvingAuthState,
              Date().timeIntervalSince(startedAt) < maximumAuthWait,
              !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60_000_000)
        }

        guard !Task.isCancelled else { return }

        let elapsed = Date().timeIntervalSince(startedAt)
        if elapsed < minimumVisibleDuration {
            try? await Task.sleep(
                nanoseconds: UInt64((minimumVisibleDuration - elapsed) * 1_000_000_000)
            )
        }

        guard !Task.isCancelled else { return }

        withAnimation(.easeOut(duration: reduceMotion ? 0 : 0.5)) {
            progress = 1.0
        }
        try? await Task.sleep(nanoseconds: reduceMotion ? 150_000_000 : 700_000_000)

        guard !Task.isCancelled, !didFinish else { return }
        didFinish = true
        onFinished()
    }

    @MainActor
    private func rotateMessages() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard !Task.isCancelled else { return }

            if reduceMotion {
                messageIndex = (messageIndex + 1) % messages.count
                continue
            }

            withAnimation(.easeInOut(duration: 0.22)) {
                messageOpacity = 0.18
            }
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }

            messageIndex = (messageIndex + 1) % messages.count
            withAnimation(.easeInOut(duration: 0.22)) {
                messageOpacity = 1.0
            }
        }
    }
}

private struct SplashBarberPoleFill: View {
    let reduceMotion: Bool

    private let cycleDuration: TimeInterval = 0.7
    private let patternWidth: CGFloat = 44

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let fraction = reduceMotion
                ? 0
                : timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
            let offset = CGFloat(fraction) * patternWidth

            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                let bands: [(width: CGFloat, color: Color)] = [
                    (15, Color(red: 1.000, green: 0.882, blue: 0.945)),
                    (14, Color(red: 1.000, green: 0.525, blue: 0.769)),
                    (15, Color(red: 0.961, green: 0.235, blue: 0.600)),
                ]

                var groupStart = -size.height - patternWidth - offset
                while groupStart < size.width + size.height + patternWidth {
                    var bandStart = groupStart
                    for band in bands {
                        var stripe = Path()
                        stripe.move(to: CGPoint(x: bandStart, y: 0))
                        stripe.addLine(to: CGPoint(x: bandStart + band.width, y: 0))
                        stripe.addLine(
                            to: CGPoint(x: bandStart + band.width - size.height, y: size.height)
                        )
                        stripe.addLine(to: CGPoint(x: bandStart - size.height, y: size.height))
                        stripe.closeSubpath()
                        context.fill(stripe, with: .color(band.color))
                        bandStart += band.width
                    }
                    groupStart += patternWidth
                }

                let topHighlight = Path(
                    CGRect(x: 0, y: 0, width: size.width, height: min(2, size.height * 0.3))
                )
                context.fill(topHighlight, with: .color(.white.opacity(0.45)))
            }
        }
    }
}

@available(iOS 18.0, *)
private struct SplashShaderTextRenderer: TextRenderer {
    var time: Double

    var animatableData: Double {
        get { time }
        set { time = newValue }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        context.addFilter(
            .colorShader(
                ShaderLibrary.poplurSplashText(.float(Float(time)), .float(1.0))
            )
        )
        for line in layout {
            context.draw(line)
        }
    }
}

private struct SplashShaderText: ViewModifier {
    @State private var epoch = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: reduceMotion)) { timeline in
                content.textRenderer(
                    SplashShaderTextRenderer(
                        time: reduceMotion ? 0 : timeline.date.timeIntervalSince(epoch)
                    )
                )
            }
        } else {
            content.foregroundStyle(Color(red: 0.957, green: 0.231, blue: 0.600))
        }
    }
}

private struct SplashLoopingVideoPlayer: UIViewRepresentable {
    let resourceName: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") else {
            return view
        }

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        player.actionAtItemEnd = .none

        context.coordinator.player = player
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspectFill
        player.play()
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if context.coordinator.player?.timeControlStatus != .playing {
            context.coordinator.player?.play()
        }
    }

    static func dismantleUIView(_ uiView: PlayerView, coordinator: Coordinator) {
        coordinator.player?.pause()
        uiView.playerLayer.player = nil
    }

    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }

    final class PlayerView: UIView {
        let playerLayer = AVPlayerLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = UIColor(red: 0.039, green: 0.027, blue: 0.035, alpha: 1)
            layer.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}
