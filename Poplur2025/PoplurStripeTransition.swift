import SwiftUI
import SpriteKit

// MARK: - Coordinator

final class StripeTransitionCoordinator: ObservableObject {
    @Published var isVisible: Bool = false
    private var midpointAction: (() -> Void)?

    func trigger(midpoint: @escaping () -> Void) {
        midpointAction = midpoint
        isVisible = true
    }

    fileprivate func fireMidpoint() {
        midpointAction?()
        midpointAction = nil
    }

    fileprivate func fireComplete() {
        isVisible = false
    }
}

// MARK: - Stripe Shape

private struct StripeShape: Shape {
    var leftEdge: CGFloat
    let width: CGFloat

    var animatableData: CGFloat {
        get { leftEdge }
        set { leftEdge = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let H = rect.height
        var p = Path()
        p.move(to: CGPoint(x: leftEdge, y: 0))
        p.addLine(to: CGPoint(x: leftEdge + width, y: 0))
        p.addLine(to: CGPoint(x: leftEdge + width + H, y: H))
        p.addLine(to: CGPoint(x: leftEdge + H, y: H))
        p.closeSubpath()
        return p
    }
}

// MARK: - Gold Confetti

private final class GoldConfettiScene: SKScene {
    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { nil }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        view.backgroundColor = .clear
        spawnBurst()
    }

    func resize(to newSize: CGSize) { size = newSize }

    private func spawnBurst() {
        let side: CGFloat = 8
        let squareTex = SKTexture(image: UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            UIColor(red: 1.0, green: 0.82, blue: 0.18, alpha: 1.0).setFill()
            ctx.cgContext.fill(CGRect(x: 0, y: 0, width: side, height: side))
        })

        let e = SKEmitterNode()
        e.particleTexture = squareTex
        e.particleBirthRate = 320
        e.particleLifetime = 1.3
        e.particleLifetimeRange = 0.6
        e.particleSpeed = 260
        e.particleSpeedRange = 110
        e.emissionAngle = 0
        e.emissionAngleRange = .pi * 2
        e.particleAlpha = 1.0
        e.particleAlphaSpeed = -0.75
        e.particleScale = 1.0
        e.particleScaleRange = 0.7
        e.particleScaleSpeed = -0.25
        e.particleRotation = 0
        e.particleRotationRange = .pi
        e.particleRotationSpeed = 2.5
        e.particleColor = UIColor(red: 1.0, green: 0.82, blue: 0.18, alpha: 1.0)
        e.particleColorBlendFactor = 1.0
        e.position = CGPoint(x: size.width / 2, y: size.height / 2)
        e.zPosition = 10
        addChild(e)

        run(.sequence([
            .wait(forDuration: 0.22),
            .run { e.particleBirthRate = 0 },
            .wait(forDuration: 1.8),
            .run { e.removeFromParent() }
        ]))
    }
}

private struct GoldConfettiView: View {
    @State private var scene: GoldConfettiScene?

    var body: some View {
        GeometryReader { geo in
            let s: GoldConfettiScene = {
                if let existing = scene { return existing }
                return GoldConfettiScene(size: geo.size)
            }()
            SpriteView(scene: s, options: [.allowsTransparency])
                .ignoresSafeArea()
                .onAppear { if scene == nil { scene = s } }
                .onChange(of: geo.size) { _, newSize in s.resize(to: newSize) }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Overlay View

struct StripeTransitionOverlay: View {
    @ObservedObject var coordinator: StripeTransitionCoordinator

    private let stripeCount = 8
    private let colors: [Color] = [
        Color(red: 0.84, green: 0.02, blue: 0.47),   // deep magenta
        Color(red: 0.54, green: 0.10, blue: 0.76),   // purple
        .white,
        Color(red: 1.00, green: 0.18, blue: 0.60),   // hot pink
        Color(red: 0.58, green: 0.08, blue: 0.82),   // violet
        Color(red: 0.97, green: 0.78, blue: 0.89),   // light pink
        Color(red: 0.94, green: 0.10, blue: 0.52),   // deep pink
        .white,
    ]

    @State private var leftEdges: [CGFloat] = Array(repeating: 0, count: 8)
    @State private var ready = false
    @State private var logoScale: CGFloat = 0
    @State private var logoOpacity: Double = 0
    @State private var showConfetti = false

    var body: some View {
        GeometryReader { geo in
            let sw = geo.size.width / CGFloat(stripeCount)
            ZStack {
                // Stripes with cylindrical 3D sheen
                ForEach(0..<stripeCount, id: \.self) { i in
                    ZStack {
                        StripeShape(leftEdge: leftEdges[i], width: sw)
                            .fill(colors[i])
                        StripeShape(leftEdge: leftEdges[i], width: sw)
                            .fill(LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .white.opacity(0.50), location: 0.00),
                                    .init(color: .white.opacity(0.08), location: 0.35),
                                    .init(color: .clear,               location: 0.65),
                                    .init(color: .black.opacity(0.10), location: 1.00),
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                    }
                    .ignoresSafeArea()
                }

                // Gold confetti burst
                if showConfetti {
                    GoldConfettiView()
                        .allowsHitTesting(false)
                }

                // App icon card + wordmark
                VStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.24), radius: 18, x: 0, y: 8)
                        if let img = UIImage(named: "logo") {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFit()
                                .padding(10)
                        }
                    }
                    .frame(width: 96, height: 96)

                    Text("poplur")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0.16, green: 0.08, blue: 0.22))
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
            }
            .ignoresSafeArea()
            .onAppear {
                guard !ready else { return }
                ready = true
                let startX = geo.size.width     // bars start off the right edge
                for i in 0..<stripeCount { leftEdges[i] = startX }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    playEntry(size: geo.size, sw: sw)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(true)
    }

    private func playEntry(size: CGSize, sw: CGFloat) {
        let duration = 0.28
        let stagger = 0.052

        // Stagger right-to-left: bar 7 (rightmost) arrives first
        for i in 0..<stripeCount {
            let delay = Double(stripeCount - 1 - i) * stagger
            withAnimation(.easeOut(duration: duration).delay(delay)) {
                leftEdges[i] = CGFloat(i) * sw
            }
        }

        let midDelay = Double(stripeCount - 1) * stagger + duration + 0.02
        DispatchQueue.main.asyncAfter(deadline: .now() + midDelay) {
            coordinator.fireMidpoint()

            withAnimation(.spring(response: 0.40, dampingFraction: 0.56)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }
            showConfetti = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.52) {
                playExit(size: size, sw: sw)
            }
        }
    }

    private func playExit(size: CGSize, sw: CGFloat) {
        let duration = 0.24
        let stagger = 0.046
        let exitX = -(size.height + sw)     // bars exit off the left edge

        withAnimation(.easeOut(duration: 0.16)) {
            logoOpacity = 0
        }

        // Stagger left-to-right: bar 0 exits first (sweep left)
        for i in 0..<stripeCount {
            withAnimation(.easeIn(duration: duration).delay(Double(i) * stagger)) {
                leftEdges[i] = exitX
            }
        }

        let doneDelay = Double(stripeCount - 1) * stagger + duration + 0.06
        DispatchQueue.main.asyncAfter(deadline: .now() + doneDelay) {
            showConfetti = false
            coordinator.fireComplete()
        }
    }
}
