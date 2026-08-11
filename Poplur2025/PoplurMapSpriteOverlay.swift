import SwiftUI
import SpriteKit

// MARK: - SpriteKit map overlay (radar, pulse, scan effects)

struct PoplurMapSpriteOverlay: UIViewRepresentable {
    let skin: CubeSkin
    @Binding var isActive: Bool

    func makeUIView(context: Context) -> SKView {
        let view = PoplurManagedSKView(performanceName: "MapSpriteOverlay2D")
        view.backgroundColor = .clear
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 30
        view.isUserInteractionEnabled = false

        let scene = PoplurMapSpriteScene(size: UIScreen.main.bounds.size, skin: skin)
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        context.coordinator.scene = scene
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if let scene = context.coordinator.scene {
            if uiView.bounds.size != .zero, scene.size != uiView.bounds.size {
                scene.size = uiView.bounds.size
                scene.updateLayout()
            }
            scene.setActive(isActive, skin: skin)
        }
    }

    static func dismantleUIView(_ uiView: SKView, coordinator: Coordinator) {
        coordinator.scene?.removeAllChildren()
        uiView.presentScene(nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var scene: PoplurMapSpriteScene?
    }
}

// MARK: - SpriteKit scene

final class PoplurMapSpriteScene: SKScene {
    private var radarNode: SKNode?
    private var scanNode: SKNode?
    private var pulseRings: [SKShapeNode] = []
    private var isActive: Bool = false
    private var currentSkin: CubeSkin

    init(size: CGSize, skin: CubeSkin) {
        self.currentSkin = skin
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        buildScene()
    }

    func updateLayout() {
        radarNode?.removeFromParent()
        scanNode?.removeFromParent()
        pulseRings.forEach { $0.removeFromParent() }
        pulseRings = []
        buildScene()
    }

    func setActive(_ active: Bool, skin: CubeSkin) {
        if skin.rawValue != currentSkin.rawValue {
            currentSkin = skin
            updateLayout()
        }
        isActive = active
        radarNode?.isHidden = !active
        scanNode?.isHidden = !active
        pulseRings.forEach { $0.isHidden = !active }
        if active {
            startPulse()
        } else {
            stopPulse()
        }
    }

    private var accentUIColor: UIColor {
        let c = currentSkin.poplurTheme.mapThemeData.radiusColors.first ?? currentSkin.appTheme.accent
        return UIColor(c)
    }

    private func buildScene() {
        let cx = size.width / 2
        let cy = size.height / 2

        // Radar sweep
        let radarContainer = SKNode()
        radarContainer.position = CGPoint(x: cx, y: cy)
        radarContainer.isHidden = !isActive

        let sweepRadius: CGFloat = min(size.width, size.height) * 0.45
        let sweepArc = CGMutablePath()
        sweepArc.addArc(center: .zero, radius: sweepRadius, startAngle: 0, endAngle: .pi * 0.4, clockwise: false)
        sweepArc.addLine(to: .zero)
        sweepArc.closeSubpath()

        let sweep = SKShapeNode(path: sweepArc)
        sweep.fillColor = accentUIColor.withAlphaComponent(0.06)
        sweep.strokeColor = accentUIColor.withAlphaComponent(0.22)
        sweep.lineWidth = 1.5
        radarContainer.addChild(sweep)

        // Leading edge line
        let edge = SKShapeNode(path: { () -> CGPath in
            let p = CGMutablePath()
            p.move(to: .zero)
            p.addLine(to: CGPoint(x: sweepRadius, y: 0))
            return p
        }())
        edge.strokeColor = accentUIColor.withAlphaComponent(0.55)
        edge.lineWidth = 1.5
        radarContainer.addChild(edge)

        // Rotate the radar
        let rotate = SKAction.repeatForever(SKAction.rotate(byAngle: -.pi * 2, duration: 5.0))
        radarContainer.run(rotate)

        // Radar rings
        for i in 1...3 {
            let r = sweepRadius * CGFloat(i) / 3.0
            let ring = SKShapeNode(circleOfRadius: r)
            ring.strokeColor = accentUIColor.withAlphaComponent(0.12)
            ring.fillColor = .clear
            ring.lineWidth = 0.8
            radarContainer.addChild(ring)
        }

        addChild(radarContainer)
        radarNode = radarContainer

        // Scan line
        let scanContainer = SKNode()
        scanContainer.isHidden = !isActive
        let scanLine = SKShapeNode(rectOf: CGSize(width: size.width + 40, height: 2))
        scanLine.fillColor = accentUIColor.withAlphaComponent(0.10)
        scanLine.strokeColor = accentUIColor.withAlphaComponent(0.28)
        scanContainer.addChild(scanLine)
        scanContainer.position = CGPoint(x: cx, y: -10)
        let scanMove = SKAction.sequence([
            SKAction.moveTo(y: size.height + 10, duration: 6.0),
            SKAction.moveTo(y: -10, duration: 0)
        ])
        scanContainer.run(.repeatForever(scanMove))
        addChild(scanContainer)
        scanNode = scanContainer

        // Pulse rings at center
        for i in 0..<3 {
            let ring = SKShapeNode(circleOfRadius: sweepRadius * 0.45)
            ring.fillColor = .clear
            ring.strokeColor = accentUIColor.withAlphaComponent(0.18)
            ring.lineWidth = 1.5
            ring.position = CGPoint(x: cx, y: cy)
            ring.isHidden = !isActive
            addChild(ring)
            pulseRings.append(ring)

            let delay = SKAction.wait(forDuration: Double(i) * 0.9)
            let expand = SKAction.scale(to: 2.8, duration: 2.5)
            let fade = SKAction.fadeAlpha(to: 0, duration: 2.5)
            let reset = SKAction.group([SKAction.scale(to: 1.0, duration: 0), SKAction.fadeAlpha(to: 1, duration: 0)])
            let pulse = SKAction.sequence([delay, SKAction.group([expand, fade]), reset])
            ring.run(.repeatForever(pulse))
        }
    }

    private func startPulse() {
        isPaused = false
    }

    private func stopPulse() {
        isPaused = false
    }
}

// MARK: - Achievement burst animation

struct PoplurAchievementBurst: View {
    let skin: CubeSkin
    var onComplete: (() -> Void)? = nil

    @State private var rings: [(scale: CGFloat, opacity: Double)] = (0..<5).map { _ in (0.1, 1.0) }
    @State private var started = false

    private var accent: Color { skin.poplurTheme.mapThemeData.controlAccent }

    var body: some View {
        ZStack {
            ForEach(rings.indices, id: \.self) { i in
                Circle()
                    .stroke(accent.opacity(rings[i].opacity), lineWidth: 3)
                    .scaleEffect(rings[i].scale)
                    .frame(width: 80, height: 80)
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            for i in rings.indices {
                let delay = Double(i) * 0.12
                withAnimation(.easeOut(duration: 0.9).delay(delay)) {
                    rings[i].scale = 3.5
                    rings[i].opacity = 0
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                onComplete?()
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Notification burst

struct PoplurNotificationBurst: View {
    let skin: CubeSkin
    let count: Int

    @State private var particles: [BurstParticle] = []

    private struct BurstParticle: Identifiable {
        let id = UUID()
        var angle: Double
        var distance: CGFloat
        var opacity: Double
    }

    private var accent: Color { skin.poplurTheme.mapThemeData.controlAccent }

    var body: some View {
        ZStack {
            ForEach(particles) { p in
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .offset(
                        x: cos(p.angle) * p.distance,
                        y: sin(p.angle) * p.distance
                    )
                    .opacity(p.opacity)
            }
        }
        .onAppear {
            particles = (0..<count).map { i in
                BurstParticle(
                    angle: Double(i) / Double(count) * .pi * 2,
                    distance: 0,
                    opacity: 1.0
                )
            }
            withAnimation(.easeOut(duration: 0.7)) {
                for i in particles.indices {
                    particles[i].distance = CGFloat.random(in: 20...60)
                    particles[i].opacity = 0
                }
            }
        }
        .allowsHitTesting(false)
    }
}
