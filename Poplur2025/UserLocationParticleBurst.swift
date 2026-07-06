import SwiftUI
import SpriteKit

/// Renders a looping SpriteKit particle burst at the user's current map location.
/// Uses the project's Spark.sks particle — no AI-generated assets.
///
/// Place this in the map's overlay ZStack, *above* the Map but *below* the UI chrome.
/// Pass the screen-space CGPoint of the user pin; update it as the map pans.
struct UserLocationParticleBurst: UIViewRepresentable {

    /// Screen-space position of the user pin. Nil hides the effect entirely.
    var screenPosition: CGPoint?
    /// Tint pulled from the active CubeSkin so the particles match the theme.
    var tintColor: UIColor

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SKView {
        let v = SKView()
        v.backgroundColor = .clear
        v.allowsTransparency = true
        v.isUserInteractionEnabled = false
        v.preferredFramesPerSecond = 30
        v.shouldCullNonVisibleNodes = true

        let scene = SKScene()
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill
        context.coordinator.scene = scene
        v.presentScene(scene)

        return v
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        let scene = context.coordinator.scene
        // Resize scene when view bounds change
        if scene.size != uiView.bounds.size, uiView.bounds.size != .zero {
            scene.size = uiView.bounds.size
        }
        context.coordinator.update(screenPosition: screenPosition, tint: tintColor, sceneSize: scene.size)
    }

    static func dismantleUIView(_ uiView: SKView, coordinator: Coordinator) {
        uiView.scene?.removeAllChildren()
        uiView.presentScene(nil)
    }

    // MARK: – Coordinator

    final class Coordinator {
        var scene = SKScene()
        private var emitter: SKEmitterNode?
        private var glowEmitter: SKEmitterNode?
        private var currentTint: UIColor = .clear

        func update(screenPosition: CGPoint?, tint: UIColor, sceneSize: CGSize) {
            guard let pos = screenPosition, sceneSize != .zero else {
                emitter?.isPaused = true
                glowEmitter?.isPaused = true
                return
            }
            // Convert UIKit coordinates (origin top-left) → SpriteKit (origin bottom-left)
            let skPos = CGPoint(x: pos.x, y: sceneSize.height - pos.y)

            if emitter == nil { build(tint: tint, sceneSize: sceneSize) }
            if tint != currentTint { recolor(tint: tint) }

            emitter?.position = skPos
            emitter?.isPaused = false
            glowEmitter?.position = skPos
            glowEmitter?.isPaused = false
        }

        private func build(tint: UIColor, sceneSize: CGSize) {
            currentTint = tint

            // Primary spark burst — load Spark.sks if available, else procedural fallback
            let spark: SKEmitterNode
            if let loaded = SKEmitterNode(fileNamed: "Spark") {
                spark = loaded
            } else {
                spark = proceduralSpark(tint: tint)
            }
            spark.particleColor = tint
            spark.particleColorBlendFactor = 0.9
            spark.particleBlendMode = .add
            spark.particleBirthRate = 6
            spark.particleLifetime = 1.8
            spark.zPosition = 10
            scene.addChild(spark)
            emitter = spark

            // Soft ambient glow underneath — uses Bokeh.sks if available
            let glow: SKEmitterNode
            if let loaded = SKEmitterNode(fileNamed: "Bokeh") {
                glow = loaded
            } else {
                glow = proceduralGlow(tint: tint)
            }
            glow.particleColor = tint
            glow.particleColorBlendFactor = 0.7
            glow.particleBlendMode = .add
            glow.particleBirthRate = 3
            glow.particleLifetime = 2.2
            glow.particleScale = 0.6
            glow.zPosition = 9
            scene.addChild(glow)
            glowEmitter = glow
        }

        private func recolor(tint: UIColor) {
            currentTint = tint
            emitter?.particleColor = tint
            glowEmitter?.particleColor = tint
        }

        // Procedural fallback if .sks file isn't found at runtime
        private func proceduralSpark(tint: UIColor) -> SKEmitterNode {
            let e = SKEmitterNode()
            e.particleTexture = sparkTexture()
            e.particleBirthRate = 6
            e.particleLifetime = 1.8
            e.particleLifetimeRange = 0.6
            e.particleSpeed = 70
            e.particleSpeedRange = 40
            e.emissionAngle = .pi / 2
            e.emissionAngleRange = .pi * 2
            e.particleScale = 0.10
            e.particleScaleRange = 0.06
            e.particleScaleSpeed = -0.04
            e.particleAlpha = 0.95
            e.particleAlphaSpeed = -0.5
            e.particleColor = tint
            e.particleColorBlendFactor = 1.0
            e.particleBlendMode = .add
            e.yAcceleration = -60
            return e
        }

        private func proceduralGlow(tint: UIColor) -> SKEmitterNode {
            let e = SKEmitterNode()
            e.particleTexture = orbTexture()
            e.particleBirthRate = 3
            e.particleLifetime = 2.2
            e.particleLifetimeRange = 0.8
            e.particleSpeed = 12
            e.particleSpeedRange = 6
            e.emissionAngle = .pi / 2
            e.emissionAngleRange = .pi * 2
            e.particleScale = 0.30
            e.particleScaleRange = 0.12
            e.particleScaleSpeed = -0.05
            e.particleAlpha = 0.55
            e.particleAlphaSpeed = -0.2
            e.particleColor = tint
            e.particleColorBlendFactor = 0.8
            e.particleBlendMode = .add
            return e
        }

        private func sparkTexture() -> SKTexture {
            let size = CGSize(width: 24, height: 24)
            return SKTexture(image: UIGraphicsImageRenderer(size: size).image { ctx in
                let c = ctx.cgContext
                c.setFillColor(UIColor.white.cgColor)
                let cx = size.width / 2, cy = size.height / 2
                for i in 0..<4 {
                    let a = CGFloat(i) / 4 * .pi * 2
                    let path = CGMutablePath()
                    path.move(to: CGPoint(x: cx, y: cy))
                    path.addLine(to: CGPoint(x: cx + 2.5 * cos(a + .pi/2), y: cy + 2.5 * sin(a + .pi/2)))
                    path.addLine(to: CGPoint(x: cx + 11 * cos(a), y: cy + 11 * sin(a)))
                    path.addLine(to: CGPoint(x: cx + 2.5 * cos(a - .pi/2), y: cy + 2.5 * sin(a - .pi/2)))
                    path.closeSubpath()
                    c.addPath(path)
                    c.fillPath()
                }
            })
        }

        private func orbTexture() -> SKTexture {
            let size = CGSize(width: 32, height: 32)
            return SKTexture(image: UIGraphicsImageRenderer(size: size).image { ctx in
                let c = ctx.cgContext
                guard let g = CGGradient(
                    colorsSpace: CGColorSpaceCreateDeviceRGB(),
                    colors: [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray,
                    locations: [0, 1]
                ) else { return }
                c.drawRadialGradient(g, startCenter: CGPoint(x: 16, y: 16), startRadius: 0,
                                     endCenter: CGPoint(x: 16, y: 16), endRadius: 16, options: [])
            })
        }
    }
}
