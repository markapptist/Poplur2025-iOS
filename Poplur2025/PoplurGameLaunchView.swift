import SwiftUI
import SpriteKit

// MARK: - Poplur Games Launch View

struct PoplurGameLaunchView: View {
    /// When provided, launches this exact game instead of generating a random one.
    var presetConfig: PoplurGameConfig? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var volumeObserver: DeviceVolumeObserver
    @State private var phase: LoadPhase = .loading
    @State private var config: PoplurGameConfig?
    @State private var spinAngle: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var dotCount = 1

    enum LoadPhase { case loading, ready, playing }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch phase {
            case .loading:
                loadingView
            case .ready:
                if let cfg = config {
                    readyView(cfg: cfg)
                }
            case .playing:
                if let cfg = config {
                    GameSceneContainer(config: cfg)
                        .ignoresSafeArea()
                }
            }

            // Exit button lives here, outside GameSceneContainer, so SwiftUI gets the tap
            // before SpriteKit's touchesBegan sees it.
            if phase == .playing {
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.55), radius: 4, x: 0, y: 2)
                                .frame(width: 56, height: 56)
                        }
                        .padding(.trailing, 18)
                        .padding(.top, 60)
                        .contentShape(Rectangle())
                    }
                    Spacer()
                }
                .allowsHitTesting(true)
                .zIndex(1001)
            }
        }
        .volumeBarsOverlay()
        .task { await loadConfig() }
        .onDisappear {
            config = nil
            phase = .loading
        }
    }

    // MARK: Loading screen

    private var loadingView: some View {
        VStack(spacing: 32) {
            Spacer()

            // Spinning Poplur logo wordmark
            Text("POPLUR")
                .font(.system(size: 42, weight: .black, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [.pink, .purple, .cyan], startPoint: .leading, endPoint: .trailing)
                )
                .rotationEffect(.degrees(spinAngle))
                .scaleEffect(pulseScale)
                .onAppear {
                    withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) {
                        spinAngle = 360
                    }
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulseScale = 1.12
                    }
                }

            // Animated character silhouettes row
            HStack(spacing: 20) {
                ForEach(Array(PoplurCharacterID.allCases.enumerated()), id: \.offset) { idx, char in
                    SpriteKitCharacterView(character: char, scale: 0.7)
                        .frame(width: 44, height: 64)
                        .offset(y: idx % 2 == 0 ? -6 : 6)
                        .animation(.easeInOut(duration: 0.5 + Double(idx) * 0.07).repeatForever(autoreverses: true).delay(Double(idx) * 0.12), value: idx)
                }
            }

            VStack(spacing: 8) {
                Text("AI is generating your game\(String(repeating: ".", count: dotCount))")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .onAppear {
                        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
                            dotCount = (dotCount % 3) + 1
                        }
                    }
                Text("Every session is unique")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Spacer()

            Button { dismiss() } label: {
                Text("Cancel")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: Ready screen (brief game card before launch)

    private func readyView(cfg: PoplurGameConfig) -> some View {
        VStack(spacing: 0) {
            // Color swatch header
            LinearGradient(colors: [cfg.skyUIColor.swiftUIColor, cfg.accentUIColor.swiftUIColor],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 220)
                .overlay {
                    VStack(spacing: 12) {
                        SpriteKitCharacterView(character: cfg.character, scale: 1.6)
                            .frame(width: 88, height: 130)
                        Text(cfg.character.displayName.uppercased())
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                            .tracking(3)
                    }
                }

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(cfg.gameName)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    HStack(spacing: 8) {
                        tagPill(cfg.theme, color: cfg.accentUIColor.swiftUIColor)
                        tagPill(cfg.game.displayName, color: .white.opacity(0.15))
                        tagPill(cfg.difficulty.capitalized, color: difficultyColor(cfg.difficulty))
                    }
                }

                Divider().background(.white.opacity(0.15))

                VStack(alignment: .leading, spacing: 12) {
                    infoRow(icon: "bolt.fill", label: "Special", value: cfg.specialMechanic)
                    infoRow(icon: "flame.fill", label: "Enemy", value: cfg.enemyType)
                    infoRow(icon: "star.fill", label: "Power-Ups", value: cfg.powerUps.joined(separator: ", "))
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { phase = .playing }
                } label: {
                    HStack {
                        Image(systemName: "gamecontroller.fill")
                            .poplurIconShader()
                        Text("Play Now")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(cfg.accentUIColor.swiftUIColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button { dismiss() } label: {
                    Text("Not this time")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }
                .padding(.bottom, 8)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 0.08, green: 0.08, blue: 0.12))
        }
        .ignoresSafeArea(edges: .top)
    }

    // MARK: Helpers

    private func tagPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .poplurIconShader()
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }

    private func difficultyColor(_ d: String) -> Color {
        switch d.lowercased() {
        case "easy": return .green.opacity(0.7)
        case "hard": return .red.opacity(0.7)
        default: return .orange.opacity(0.7)
        }
    }

    private func loadConfig() async {
        // A preset (user-created) game skips AI generation and goes straight to the card.
        if let preset = presetConfig {
            await MainActor.run {
                config = preset
                withAnimation(.spring(duration: 0.4)) { phase = .ready }
            }
            return
        }
        let cfg = await PoplurGameService.shared.generateConfig()
        await MainActor.run {
            config = cfg
            withAnimation(.spring(duration: 0.4)) { phase = .ready }
        }
    }
}

// MARK: - Game Scene Container

private struct GameSceneContainer: View {
    let config: PoplurGameConfig

    @State private var scene: SKScene?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                if let scene {
                    SpriteView(scene: scene)
                        .ignoresSafeArea()
                }
            }
            .onAppear {
                guard scene == nil else { return }
                // Include safe-area insets so scene coordinates match what SpriteView renders
                let size = CGSize(
                    width: geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing,
                    height: geo.size.height + geo.safeAreaInsets.top + geo.safeAreaInsets.bottom
                )
                let s: SKScene
                switch config.game {
                case .sideScroller:    s = PopRunnerScene(config: config, size: size)
                case .arcadeShooter:   s = StellaBlastScene(config: config, size: size)
                case .actionAdventure: s = ZylaQuestScene(config: config, size: size)
                case .sports:          s = RexHoopsScene(config: config, size: size)
                }
                scene = s
            }
            .onChange(of: scenePhase) { _, phase in
                scene?.isPaused = (phase != .active)
            }
        }
    }
}

// MARK: - SpriteKit Character Preview (SwiftUI wrapper)

struct SpriteKitCharacterView: UIViewRepresentable {
    let character: PoplurCharacterID
    let scale: CGFloat

    func makeUIView(context: Context) -> SKView {
        let v = SKView(); v.backgroundColor = .clear; v.allowsTransparency = true
        return v
    }
    func updateUIView(_ v: SKView, context: Context) {
        guard v.scene == nil else { return }
        let scene = SKScene(size: CGSize(width: 80, height: 120))
        scene.backgroundColor = .clear; scene.scaleMode = .aspectFit
        let node = character.makeSpriteNode(scale: scale)
        node.position = CGPoint(x: 40, y: 55)
        scene.addChild(node)
        v.presentScene(scene)
    }
}

// MARK: - UIColor → SwiftUI Color

private extension UIColor {
    var swiftUIColor: Color { Color(uiColor: self) }
}
