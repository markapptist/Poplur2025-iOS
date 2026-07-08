import SwiftUI
import SpriteKit

// MARK: - Poplur Pet — SwiftUI device shell + game host

struct PoplurPetGameView: View {
    var onClose: (() -> Void)? = nil

    @State private var scene: PoplurPetScene?
    @Environment(\.scenePhase) private var scenePhase

    private let shellPink   = Color(red: 0.98, green: 0.22, blue: 0.62)
    private let shellDark   = Color(red: 0.05, green: 0.03, blue: 0.10)
    private let screenBorder = Color(red: 0.96, green: 0.30, blue: 0.68)
    private let screenSize: CGFloat = 200

    var body: some View {
        ZStack {
            // Fullscreen dark background
            shellDark.ignoresSafeArea()

            // Glitter oval device shell
            deviceShell
                .frame(maxWidth: 360, maxHeight: .infinity)

            // Close button (top-right)
            VStack {
                HStack {
                    Spacer()
                    Button { onClose?() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                    }
                    .padding(.trailing, 18)
                    .padding(.top, 58)
                }
                Spacer()
            }
        }
        .onAppear { buildScene() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { scene.map { PetSaveManager.save($0.petState) } }
            scene?.isPaused = (phase != .active)
        }
        .onDisappear { scene.map { PetSaveManager.save($0.petState) } }
    }

    // MARK: Device shell

    private var deviceShell: some View {
        GeometryReader { geo in
            ZStack {
                // ── Shell body ──────────────────────────────────────────────
                EggShape()
                    .fill(
                        LinearGradient(colors: [
                            Color(red: 0.06, green: 0.03, blue: 0.14),
                            Color(red: 0.14, green: 0.04, blue: 0.22)
                        ], startPoint: .top, endPoint: .bottom)
                    )
                    .overlay(
                        // Glitter sparkle overlay
                        EggShape()
                            .fill(
                                RadialGradient(colors: [
                                    shellPink.opacity(0.45),
                                    shellPink.opacity(0.08),
                                    .clear
                                ], center: .topTrailing, startRadius: 10, endRadius: 200)
                            )
                    )
                    .shadow(color: shellPink.opacity(0.5), radius: 24, x: 0, y: 8)

                // Shell content
                VStack(spacing: 0) {
                    Spacer(minLength: geo.size.height * 0.06)

                    // "Poplur" logo
                    Text("Poplür")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [shellPink, Color(red: 1.0, green: 0.4, blue: 0.8)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .shadow(color: shellPink.opacity(0.9), radius: 6, x: 0, y: 0)
                        .padding(.bottom, 8)

                    // ── Game screen ───────────────────────────────────────
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 1.0, green: 0.95, blue: 0.75))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(
                                        LinearGradient(colors: [shellPink, Color(red: 0.55, green: 0.20, blue: 1.0), shellPink],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        lineWidth: 4
                                    )
                            )

                        if let scene {
                            SpriteView(scene: scene)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .frame(width: screenSize, height: screenSize)
                    .shadow(color: shellPink.opacity(0.55), radius: 8, x: 0, y: 2)

                    Spacer(minLength: geo.size.height * 0.03)

                    // ── Shell buttons ──────────────────────────────────────
                    HStack(spacing: 24) {
                        shellButton(label: "◀") { scene?.selectPrevious() }
                        shellButton(label: "●", large: true) { scene?.confirmAction() }
                        shellButton(label: "▶") { scene?.selectNext() }
                    }
                    .padding(.bottom, 8)

                    Spacer(minLength: geo.size.height * 0.06)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Decorative elements
                decorations(geo: geo)
            }
        }
        .padding(.horizontal, 22)
    }

    // MARK: Shell button

    private func shellButton(label: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(colors: [
                            shellPink,
                            Color(red: 0.85, green: 0.08, blue: 0.45)
                        ], center: .topLeading, startRadius: 2, endRadius: large ? 34 : 26)
                    )
                    .shadow(color: shellPink.opacity(0.7), radius: large ? 10 : 6, x: 0, y: 3)

                Text(label)
                    .font(.system(size: large ? 18 : 14, weight: .black))
                    .foregroundStyle(.white)
            }
            .frame(width: large ? 56 : 44, height: large ? 56 : 44)
        }
    }

    // MARK: Decorative overlaid elements on the shell

    private func decorations(geo: GeometryProxy) -> some View {
        ZStack {
            // Stars
            Text("✦").font(.system(size: 14)).foregroundStyle(shellPink)
                .position(x: geo.size.width * 0.14, y: geo.size.height * 0.18)
            Text("✦").font(.system(size: 9)).foregroundStyle(.yellow.opacity(0.8))
                .position(x: geo.size.width * 0.82, y: geo.size.height * 0.22)
            Text("★").font(.system(size: 11)).foregroundStyle(.yellow.opacity(0.7))
                .position(x: geo.size.width * 0.12, y: geo.size.height * 0.45)
            Text("✦").font(.system(size: 8)).foregroundStyle(Color(red: 0.55, green: 0.4, blue: 1.0))
                .position(x: geo.size.width * 0.88, y: geo.size.height * 0.50)
            // Lightning bolts
            Text("⚡").font(.system(size: 16)).foregroundStyle(Color(red: 0.3, green: 0.85, blue: 1.0).opacity(0.85))
                .position(x: geo.size.width * 0.10, y: geo.size.height * 0.65)
            Text("⚡").font(.system(size: 12)).foregroundStyle(Color(red: 0.3, green: 0.85, blue: 1.0).opacity(0.6))
                .position(x: geo.size.width * 0.88, y: geo.size.height * 0.68)
            // Hearts
            Text("♥").font(.system(size: 14)).foregroundStyle(shellPink.opacity(0.9))
                .position(x: geo.size.width * 0.16, y: geo.size.height * 0.30)
        }
    }

    // MARK: Scene builder

    private func buildScene() {
        guard scene == nil else { return }
        var state = PetSaveManager.load()
        PetSimulation.applyOfflineDecay(to: &state)
        PetSaveManager.save(state)
        let s = PoplurPetScene(petState: state, size: CGSize(width: screenSize, height: screenSize))
        scene = s
    }
}

// MARK: - Egg outline shape

private struct EggShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let cx = rect.midX, w = rect.width, h = rect.height
        let top    = CGPoint(x: cx, y: h * 0.02)
        let bottom = CGPoint(x: cx, y: h)
        p.move(to: top)
        // top → bottom, left side
        p.addCurve(
            to:       bottom,
            control1: CGPoint(x: cx - w * 0.48, y: h * 0.35),
            control2: CGPoint(x: cx - w * 0.48, y: h * 0.72)
        )
        // bottom → top, right side
        p.addCurve(
            to:       top,
            control1: CGPoint(x: cx + w * 0.48, y: h * 0.72),
            control2: CGPoint(x: cx + w * 0.48, y: h * 0.35)
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - Preview

#Preview {
    PoplurPetGameView()
}
