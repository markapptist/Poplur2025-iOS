import SwiftUI
import SpriteKit

// MARK: - Theme Particle Overlay

/// Theme-specific ambient particle effects rendered above the map.
/// Separate from WeatherParticleOverlay — these are decorative theme particles.
struct PoplurThemeParticleOverlay: UIViewRepresentable {
    let skin: CubeSkin

    private var config: PoplurMapParticleConfig { skin.poplurTheme.mapThemeData.particles }

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.backgroundColor = .clear
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 20
        view.shouldCullNonVisibleNodes = true

        let scene = SKScene(size: UIScreen.main.bounds.size)
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        context.coordinator.configure(scene: scene, config: config)
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        guard let scene = uiView.scene else { return }
        if scene.size != uiView.bounds.size, uiView.bounds.size != .zero {
            scene.size = uiView.bounds.size
            context.coordinator.updateLayout(scene: scene)
        }
        context.coordinator.configure(scene: scene, config: config)
    }

    static func dismantleUIView(_ uiView: SKView, coordinator: Coordinator) {
        uiView.scene?.removeAllChildren()
        uiView.presentScene(nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator

    final class Coordinator {
        private var currentKind: PoplurMapParticleKind?
        private var emitter: SKEmitterNode?

        func configure(scene: SKScene, config: PoplurMapParticleConfig) {
            guard config.kind != currentKind else { return }
            currentKind = config.kind
            emitter?.removeFromParent()
            emitter = nil

            guard config.kind != .none else { return }

            let node = makeEmitter(config: config, sceneSize: scene.size)
            scene.addChild(node)
            emitter = node
        }

        func updateLayout(scene: SKScene) {
            guard let e = emitter else { return }
            positionEmitter(e, in: scene.size, kind: currentKind ?? .none)
        }

        private func makeEmitter(config: PoplurMapParticleConfig, sceneSize: CGSize) -> SKEmitterNode {
            let e = SKEmitterNode()

            switch config.kind {
            case .snow:
                setupSnow(e, config: config, sceneSize: sceneSize)
            case .sparkles:
                setupSparkles(e, config: config, sceneSize: sceneSize)
            case .stars:
                setupStars(e, config: config, sceneSize: sceneSize)
            case .confetti:
                setupConfetti(e, config: config, sceneSize: sceneSize)
            case .dust:
                setupDust(e, config: config, sceneSize: sceneSize)
            case .floatingOrbs:
                setupFloatingOrbs(e, config: config, sceneSize: sceneSize)
            case .rain, .none:
                break
            }

            positionEmitter(e, in: sceneSize, kind: config.kind)
            return e
        }

        private func positionEmitter(_ e: SKEmitterNode, in size: CGSize, kind: PoplurMapParticleKind) {
            switch kind {
            case .snow, .sparkles, .stars, .confetti, .dust:
                e.position = CGPoint(x: size.width / 2, y: size.height + 10)
                e.particlePositionRange = CGVector(dx: size.width * 1.1, dy: 0)
            case .floatingOrbs:
                e.position = CGPoint(x: size.width / 2, y: -10)
                e.particlePositionRange = CGVector(dx: size.width * 1.2, dy: 0)
            case .rain, .none:
                break
            }
        }

        // MARK: Particle type builders

        private func setupSnow(_ e: SKEmitterNode, config: PoplurMapParticleConfig, sceneSize: CGSize) {
            e.particleTexture = snowflakeTexture()
            e.particleBirthRate = config.birthRate
            e.particleLifetime = config.lifetime
            e.particleLifetimeRange = 3
            e.particleSpeed = 30
            e.particleSpeedRange = 12
            e.emissionAngle = -.pi / 2
            e.emissionAngleRange = 0.4
            e.particleScale = 0.18
            e.particleScaleRange = 0.10
            e.particleAlpha = 0.75
            e.particleAlphaRange = 0.25
            e.particleAlphaSpeed = -0.06
            e.particleRotation = 0
            e.particleRotationRange = .pi * 2
            e.particleRotationSpeed = 0.3
            e.particleColor = config.color
            e.particleColorBlendFactor = 0.6
            e.particleBlendMode = .add
            e.xAcceleration = 6
            e.yAcceleration = -20
        }

        private func setupSparkles(_ e: SKEmitterNode, config: PoplurMapParticleConfig, sceneSize: CGSize) {
            e.particleTexture = sparkleTexture()
            e.particleBirthRate = config.birthRate
            e.particleLifetime = config.lifetime
            e.particleLifetimeRange = 2
            e.particleSpeed = 60
            e.particleSpeedRange = 30
            e.emissionAngle = -.pi / 2
            e.emissionAngleRange = .pi / 4
            e.particleScale = 0.12
            e.particleScaleRange = 0.08
            e.particleScaleSpeed = -0.02
            e.particleAlpha = 0.9
            e.particleAlphaRange = 0.1
            e.particleAlphaSpeed = -0.15
            e.particleColor = config.color
            e.particleColorBlendFactor = 1.0
            e.particleBlendMode = .add
            e.xAcceleration = 0
            e.yAcceleration = -10
        }

        private func setupStars(_ e: SKEmitterNode, config: PoplurMapParticleConfig, sceneSize: CGSize) {
            e.particleTexture = starTexture()
            e.particleBirthRate = config.birthRate
            e.particleLifetime = config.lifetime
            e.particleLifetimeRange = 3
            e.particleSpeed = 50
            e.particleSpeedRange = 20
            e.emissionAngle = -.pi / 2
            e.emissionAngleRange = .pi / 6
            e.particleScale = 0.16
            e.particleScaleRange = 0.08
            e.particleScaleSpeed = -0.025
            e.particleAlpha = 1.0
            e.particleAlphaRange = 0.0
            e.particleAlphaSpeed = -0.18
            e.particleRotationSpeed = 1.2
            e.particleColor = config.color
            e.particleColorBlendFactor = 1.0
            e.particleBlendMode = .add
        }

        private func setupConfetti(_ e: SKEmitterNode, config: PoplurMapParticleConfig, sceneSize: CGSize) {
            e.particleTexture = squareTexture()
            e.particleBirthRate = config.birthRate
            e.particleLifetime = config.lifetime
            e.particleLifetimeRange = 1.5
            e.particleSpeed = 80
            e.particleSpeedRange = 40
            e.emissionAngle = -.pi / 2
            e.emissionAngleRange = .pi / 3
            e.particleScale = 0.15
            e.particleScaleRange = 0.10
            e.particleAlpha = 0.95
            e.particleAlphaRange = 0.05
            e.particleAlphaSpeed = -0.20
            e.particleRotationSpeed = 3.0
            e.particleRotationRange = .pi * 2
            e.particleColor = config.color
            e.particleColorBlendFactor = 1.0
            e.particleColorSequence = confettiColorSequence(color1: config.color, color2: config.color2)
            e.particleBlendMode = .alpha
            e.xAcceleration = 15
            e.yAcceleration = -25
        }

        private func setupDust(_ e: SKEmitterNode, config: PoplurMapParticleConfig, sceneSize: CGSize) {
            e.particleTexture = dustTexture()
            e.particleBirthRate = config.birthRate
            e.particleLifetime = config.lifetime
            e.particleLifetimeRange = 4
            e.particleSpeed = 15
            e.particleSpeedRange = 8
            e.emissionAngle = -.pi / 2
            e.emissionAngleRange = .pi * 0.7
            e.particleScale = 0.22
            e.particleScaleRange = 0.12
            e.particleAlpha = 0.30
            e.particleAlphaRange = 0.10
            e.particleAlphaSpeed = -0.03
            e.particleColor = config.color
            e.particleColorBlendFactor = 0.8
            e.particleBlendMode = .alpha
            e.xAcceleration = 8
        }

        private func setupFloatingOrbs(_ e: SKEmitterNode, config: PoplurMapParticleConfig, sceneSize: CGSize) {
            e.particleTexture = orbTexture()
            e.particleBirthRate = config.birthRate
            e.particleLifetime = config.lifetime
            e.particleLifetimeRange = 2
            e.particleSpeed = 25
            e.particleSpeedRange = 10
            e.emissionAngle = .pi / 2
            e.emissionAngleRange = .pi / 3
            e.particleScale = 0.30
            e.particleScaleRange = 0.20
            e.particleScaleSpeed = -0.02
            e.particleAlpha = 0.50
            e.particleAlphaRange = 0.20
            e.particleAlphaSpeed = -0.06
            e.particleColor = config.color
            e.particleColorBlendFactor = 0.9
            e.particleColorSequence = orbColorSequence(color1: config.color, color2: config.color2)
            e.particleBlendMode = .add
            e.xAcceleration = 5
        }

        // MARK: Texture builders (programmatic)

        private func snowflakeTexture() -> SKTexture {
            let size = CGSize(width: 32, height: 32)
            return SKTexture(image: UIGraphicsImageRenderer(size: size).image { ctx in
                let c = ctx.cgContext
                c.setStrokeColor(UIColor.white.cgColor)
                c.setLineWidth(2.0)
                let cx = size.width / 2, cy = size.height / 2, r: CGFloat = 13
                for i in 0..<6 {
                    let angle = CGFloat(i) / 6 * .pi * 2
                    c.move(to: CGPoint(x: cx, y: cy))
                    c.addLine(to: CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle)))
                    c.strokePath()
                    let mx = cx + r * 0.6 * cos(angle), my = cy + r * 0.6 * sin(angle)
                    let bangle1 = angle + .pi / 4, bangle2 = angle - .pi / 4
                    let br: CGFloat = 5
                    c.move(to: CGPoint(x: mx, y: my))
                    c.addLine(to: CGPoint(x: mx + br * cos(bangle1), y: my + br * sin(bangle1)))
                    c.strokePath()
                    c.move(to: CGPoint(x: mx, y: my))
                    c.addLine(to: CGPoint(x: mx + br * cos(bangle2), y: my + br * sin(bangle2)))
                    c.strokePath()
                }
            })
        }

        private func sparkleTexture() -> SKTexture {
            let size = CGSize(width: 24, height: 24)
            return SKTexture(image: UIGraphicsImageRenderer(size: size).image { ctx in
                let c = ctx.cgContext
                let cx = size.width / 2, cy = size.height / 2
                c.setFillColor(UIColor.white.cgColor)
                for i in 0..<4 {
                    let angle = CGFloat(i) / 4 * .pi * 2
                    let path = CGMutablePath()
                    path.move(to: CGPoint(x: cx, y: cy))
                    let tip = CGPoint(x: cx + 11 * cos(angle), y: cy + 11 * sin(angle))
                    let side1 = CGPoint(x: cx + 2.5 * cos(angle + .pi/2), y: cy + 2.5 * sin(angle + .pi/2))
                    let side2 = CGPoint(x: cx + 2.5 * cos(angle - .pi/2), y: cy + 2.5 * sin(angle - .pi/2))
                    path.addLine(to: side1)
                    path.addLine(to: tip)
                    path.addLine(to: side2)
                    path.closeSubpath()
                    c.addPath(path)
                    c.fillPath()
                }
            })
        }

        private func starTexture() -> SKTexture {
            let size = CGSize(width: 28, height: 28)
            return SKTexture(image: UIGraphicsImageRenderer(size: size).image { ctx in
                let c = ctx.cgContext
                let cx = size.width / 2, cy = size.height / 2
                c.setFillColor(UIColor.white.cgColor)
                let path = CGMutablePath()
                for i in 0..<10 {
                    let angle = CGFloat(i) / 10 * .pi * 2 - .pi / 2
                    let r: CGFloat = i.isMultiple(of: 2) ? 12 : 5
                    let pt = CGPoint(x: cx + r * cos(angle), y: cy + r * sin(angle))
                    i == 0 ? path.move(to: pt) : path.addLine(to: pt)
                }
                path.closeSubpath()
                c.addPath(path)
                c.fillPath()
            })
        }

        private func squareTexture() -> SKTexture {
            let size = CGSize(width: 14, height: 8)
            return SKTexture(image: UIGraphicsImageRenderer(size: size).image { ctx in
                ctx.cgContext.setFillColor(UIColor.white.cgColor)
                ctx.cgContext.fill(CGRect(origin: .zero, size: size))
            })
        }

        private func dustTexture() -> SKTexture {
            let size = CGSize(width: 16, height: 16)
            return SKTexture(image: UIGraphicsImageRenderer(size: size).image { ctx in
                let c = ctx.cgContext
                let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray,
                    locations: [0, 1]
                )!
                c.drawRadialGradient(gradient, startCenter: CGPoint(x: 8, y: 8), startRadius: 0, endCenter: CGPoint(x: 8, y: 8), endRadius: 8, options: [])
            })
        }

        private func orbTexture() -> SKTexture {
            let size = CGSize(width: 32, height: 32)
            return SKTexture(image: UIGraphicsImageRenderer(size: size).image { ctx in
                let c = ctx.cgContext
                let gradient = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray,
                    locations: [0, 1]
                )!
                c.drawRadialGradient(gradient, startCenter: CGPoint(x: 16, y: 16), startRadius: 0, endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
            })
        }

        private func confettiColorSequence(color1: UIColor, color2: UIColor) -> SKKeyframeSequence {
            let seq = SKKeyframeSequence(keyframeValues: [color1, color2, color1], times: [0, 0.5, 1.0])
            seq.interpolationMode = .spline
            return seq
        }

        private func orbColorSequence(color1: UIColor, color2: UIColor) -> SKKeyframeSequence {
            let seq = SKKeyframeSequence(keyframeValues: [color1, color2, color1], times: [0, 0.5, 1.0])
            seq.interpolationMode = .spline
            return seq
        }
    }
}
