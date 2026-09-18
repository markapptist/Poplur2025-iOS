import SwiftUI
import AVFoundation

struct PoplurClaySplashView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @State private var playbackFinished = false
    @State private var didFinish = false
    let onFinished: () -> Void

    var body: some View {
        NativePreloginSplash { playbackFinished = true; finishIfReady() }
            .onChange(of: auth.isResolvingAuthState) { _, _ in
                // Let the app observe initial auth resolution while its cold
                // cover is still present, so it does not start a second intro.
                DispatchQueue.main.async { finishIfReady() }
            }
    }

    private func finishIfReady() {
        guard playbackFinished, !auth.isResolvingAuthState, !didFinish else { return }
        didFinish = true
        onFinished()
    }
}

struct NativePreloginSplash: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var playback = SplashPlayback()
    @State private var didFinish = false
    var onFinished: () -> Void = {}
    // Same rotation as the approved Good Copy splash (good-copy-splash.html).
    private let messages = ["Warming up the pinetrees", "Rolling out the clay roads", "Teaching the pin to drop", "Sprinkling pink stars", "Kneading the little mountains", "Waking up the tugboat", "Polishing the big P", "Fluffing the clouds"]

    var body: some View {
        GeometryReader { proxy in
            // Good Copy paints the clip edge to edge (`object-fit: cover`) and
            // floats the loader over it at 68% height behind a soft radial
            // scrim. There is no letterbox and no separate footer: a black band
            // under the clay world reads as a defect on the phone.
            ZStack {
                Color(red: 10 / 255, green: 7 / 255, blue: 9 / 255)
                // A frame from this exact clip avoids flashing a separate legacy logo.
                Image("SplashPoster").resizable().scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                NativeSplashVideo(player: playback.player)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                RadialGradient(
                    stops: [
                        .init(color: .black.opacity(0.55), location: 0),
                        .init(color: .black.opacity(0.2), location: 0.52),
                        .init(color: .clear, location: 0.74),
                    ],
                    center: UnitPoint(x: 0.5, y: 0.56),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.5
                )
                .allowsHitTesting(false)
                VStack(spacing: 16) {
                    Text(messages[Int(playback.elapsed / 0.85) % messages.count])
                        .font(.system(size: 20, weight: .heavy, design: .rounded))
                        .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.54, blue: 0.77), .pink, Color(red: 1, green: 0.94, blue: 0.98)], startPoint: .leading, endPoint: .trailing))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .shadow(color: Color(red: 0.96, green: 0.23, blue: 0.6).opacity(0.5), radius: 12)
                    ClaySplashProgress(progress: playback.progress, stripeOffset: reduceMotion ? 0 : playback.elapsed * 30)
                }
                .frame(width: min(215, proxy.size.width * 0.58))
                .position(x: proxy.size.width / 2, y: proxy.size.height * 0.68)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading Poplur")
        .accessibilityValue("\(Int(playback.progress * 100)) percent")
        .accessibilityIdentifier("nativePreloginSplash")
        .onAppear { playback.setActive(phase == .active); finishIfReady() }
        .onChange(of: phase) { _, phase in playback.setActive(phase == .active); finishIfReady() }
        .onChange(of: playback.hasFinished) { _, _ in finishIfReady() }
        .onDisappear { playback.stop() }
    }

    private func finishIfReady() {
        guard playback.hasFinished, phase == .active, !didFinish else { return }
        didFinish = true
        onFinished()
    }
}

private struct ClaySplashProgress: View {
    let progress: Double
    let stripeOffset: Double
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(red: 0.19, green: 0.03, blue: 0.1).gradient)
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 1, green: 0.52, blue: 0.77)))
                    for x in stride(from: -40 + stripeOffset.truncatingRemainder(dividingBy: 40), to: size.width + 40, by: 40) {
                        let path = Path { p in
                            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x + 20, y: 0))
                            p.addLine(to: CGPoint(x: x + 34, y: size.height)); p.addLine(to: CGPoint(x: x + 14, y: size.height)); p.closeSubpath()
                        }
                        context.fill(path, with: .color(Color(red: 1, green: 0.88, blue: 0.94)))
                    }
                }
                .overlay(LinearGradient(stops: [.init(color: .white.opacity(0.65), location: 0), .init(color: .clear, location: 0.35), .init(color: .pink.opacity(0.3), location: 0.6), .init(color: Color(red: 0.55, green: 0.07, blue: 0.29).opacity(0.8), location: 1)], startPoint: .top, endPoint: .bottom))
                .clipShape(Capsule())
                .frame(width: max(14, proxy.size.width * progress))
                .overlay(alignment: .top) {
                    Capsule().fill(.white.opacity(0.55)).frame(height: 2).padding(.horizontal, 6).padding(.top, 2)
                }
            }
            .overlay(Capsule().strokeBorder(.pink.opacity(0.6), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 2, y: 3)
            .shadow(color: .pink.opacity(0.25), radius: 8)
        }.frame(height: 14)
    }
}

private struct NativeSplashVideo: UIViewRepresentable {
    let player: AVPlayer
    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        // Edge to edge, matching Good Copy's `object-fit: cover`; the layer
        // is clipped to the screen so nothing letterboxes.
        view.playerLayer.videoGravity = .resizeAspectFill
        view.clipsToBounds = true
        view.playerLayer.player = player
        return view
    }
    func updateUIView(_ view: PlayerView, context: Context) {}
    static func dismantleUIView(_ view: PlayerView, coordinator: ()) { view.playerLayer.player = nil }
}
