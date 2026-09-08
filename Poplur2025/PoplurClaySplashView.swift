import SwiftUI
import AVFoundation

/// Approved clay-world video and loading treatment, decoded by AVFoundation.
/// This surface owns no browser process, JavaScript clock, or WebGL context.
struct PoplurClaySplashView: View {
    @EnvironmentObject private var auth: AuthViewModel
    let onFinished: () -> Void
    var body: some View {
        NativePreloginSplash()
            .task {
                try? await Task.sleep(for: .milliseconds(3200))
                while auth.isResolvingAuthState && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(50)) }
                guard !Task.isCancelled else { return }
                onFinished()
            }
    }
}

struct NativePreloginSplash: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color(red: 10 / 255, green: 7 / 255, blue: 9 / 255)
                Image("logo").resizable().scaledToFit().frame(width: min(170, proxy.size.width * 0.45))
                NativeSplashVideo(active: phase == .active)
                RadialGradient(colors: [.black.opacity(0.55), .black.opacity(0.2), .clear], center: UnitPoint(x: 0.5, y: 0.56), startRadius: 0, endRadius: proxy.size.height * 0.5)
                VStack(spacing: 16) {
                    Text("Loading…").font(.custom("AvenirNext-Heavy", size: 20)).foregroundStyle(LinearGradient(colors: [.pink, .white, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                    TimelineView(.animation(minimumInterval: 1 / 24, paused: phase != .active || reduceMotion)) { timeline in
                        Canvas { context, size in
                            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5), with: .color(.pink.opacity(0.25)))
                            let offset = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 24
                            for x in stride(from: -24 + offset, to: size.width + 24, by: 24) {
                                let path = Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x + 12, y: 0)); p.addLine(to: CGPoint(x: x + 3, y: size.height)); p.addLine(to: CGPoint(x: x - 9, y: size.height)); p.closeSubpath() }
                                context.fill(path, with: .color(.pink))
                            }
                        }
                    }.frame(height: 9).clipShape(Capsule()).overlay(Capsule().stroke(.pink.opacity(0.35), lineWidth: 1))
                }.frame(width: min(215, proxy.size.width * 0.58)).position(x: proxy.size.width / 2, y: proxy.size.height * 0.68)
            }
        }.ignoresSafeArea().accessibilityElement(children: .ignore).accessibilityLabel("Loading Poplur").accessibilityIdentifier("nativePreloginSplash")
    }
}

private struct NativeSplashVideo: UIViewRepresentable {
    var active: Bool
    class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        override init(frame: CGRect) {
            super.init(frame: frame)
            playerLayer.videoGravity = .resizeAspectFill
            if let url = Bundle.main.url(forResource: "poplur_splash", withExtension: "mp4") {
                let player = AVQueuePlayer(); player.isMuted = true
                self.player = player; playerLayer.player = player
                looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        func stop() { player?.pause(); looper?.disableLooping(); looper = nil; player?.removeAllItems(); playerLayer.player = nil; player = nil }
    }
    func makeUIView(context: Context) -> PlayerView { PlayerView() }
    func updateUIView(_ view: PlayerView, context: Context) { active ? view.player?.play() : view.player?.pause() }
    static func dismantleUIView(_ view: PlayerView, coordinator: ()) { view.stop() }
}
