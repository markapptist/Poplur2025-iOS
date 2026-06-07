import SwiftUI
import SpriteKit
import UIKit

public struct WeatherVisualizationState {
    public enum Kind {
        case rain, thunderstorms, cloudy, snow
    }

    public var kind: Kind
    public var intensity: Double
    public var lightningFrequency: Double
}

#if DEBUG

public struct WeatherParticleOverlay: UIViewRepresentable {
    @Binding public var weatherState: WeatherVisualizationState

    public init(weatherState: Binding<WeatherVisualizationState>) {
        self._weatherState = weatherState
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> SKView {
        let skView = SKView(frame: .zero)
        skView.allowsTransparency = true
        skView.backgroundColor = .clear

        let scene = SKScene(size: UIScreen.main.bounds.size)
        scene.backgroundColor = .clear
        scene.scaleMode = .resizeFill

        skView.presentScene(scene)

        context.coordinator.scene = scene
        context.coordinator.updateEmitters(for: weatherState)

        return skView
    }

    public func updateUIView(_ uiView: SKView, context: Context) {
        context.coordinator.updateEmitters(for: weatherState)
    }

    public class Coordinator: NSObject {
        var parent: WeatherParticleOverlay
        weak var scene: SKScene?

        private var rainEmitter: SKEmitterNode?
        private var thunderEmitter: SKEmitterNode?
        private var cloudEmitter: SKEmitterNode?
        private var snowEmitter: SKEmitterNode?

        init(_ parent: WeatherParticleOverlay) {
            self.parent = parent
            super.init()
        }

        func updateEmitters(for state: WeatherVisualizationState) {
            guard let scene = scene else { return }

            switch state.kind {
            case .rain:
                removeAllEmitters(except: &rainEmitter)
                if rainEmitter == nil {
                    rainEmitter = makeRainEmitter()
                    rainEmitter!.position = CGPoint(x: scene.size.width / 2, y: scene.size.height)
                    rainEmitter!.particlePositionRange = CGVector(dx: scene.size.width, dy: 0)
                    scene.addChild(rainEmitter!)
                }
                rainEmitter?.particleBirthRate = CGFloat(200 * state.intensity)
                updateThunderlightningFrequency(0)
            case .thunderstorms:
                removeAllEmitters(except: &thunderEmitter)
                if thunderEmitter == nil {
                    thunderEmitter = makeRainEmitter()
                    thunderEmitter!.position = CGPoint(x: scene.size.width / 2, y: scene.size.height)
                    thunderEmitter!.particlePositionRange = CGVector(dx: scene.size.width, dy: 0)
                    scene.addChild(thunderEmitter!)
                }
                thunderEmitter?.particleBirthRate = CGFloat(200 * state.intensity)
                updateThunderlightningFrequency(state.lightningFrequency)
            case .cloudy:
                removeAllEmitters(except: &cloudEmitter)
                if cloudEmitter == nil {
                    cloudEmitter = makeCloudEmitter()
                    cloudEmitter!.position = CGPoint(x: scene.size.width / 2, y: scene.size.height * 0.8)
                    cloudEmitter!.particlePositionRange = CGVector(dx: scene.size.width, dy: 0)
                    scene.addChild(cloudEmitter!)
                }
                cloudEmitter?.particleBirthRate = CGFloat(20 * state.intensity)
                updateThunderlightningFrequency(0)
            case .snow:
                removeAllEmitters(except: &snowEmitter)
                if snowEmitter == nil {
                    snowEmitter = makeSnowEmitter()
                    snowEmitter!.position = CGPoint(x: scene.size.width / 2, y: scene.size.height)
                    snowEmitter!.particlePositionRange = CGVector(dx: scene.size.width, dy: 0)
                    scene.addChild(snowEmitter!)
                }
                snowEmitter?.particleBirthRate = CGFloat(100 * state.intensity)
                updateThunderlightningFrequency(0)
            }
        }

        private func removeAllEmitters(except emitterToKeep: inout SKEmitterNode?) {
            if rainEmitter != emitterToKeep {
                rainEmitter?.removeFromParent()
                rainEmitter = nil
            }
            if thunderEmitter != emitterToKeep {
                thunderEmitter?.removeFromParent()
                thunderEmitter = nil
            }
            if cloudEmitter != emitterToKeep {
                cloudEmitter?.removeFromParent()
                cloudEmitter = nil
            }
            if snowEmitter != emitterToKeep {
                snowEmitter?.removeFromParent()
                snowEmitter = nil
            }
        }

        private func updateThunderlightningFrequency(_ frequency: Double) {
            // Lightning effects could be implemented here if needed.
            // For simplicity, this sample uses only rain particles.
        }

        private func makeRainEmitter() -> SKEmitterNode {
            let emitter = SKEmitterNode()
            emitter.particleTexture = makeRainDropTexture()
            emitter.particleBirthRate = 200
            emitter.particleLifetime = 4
            emitter.particleSpeed = -500
            emitter.particleSpeedRange = 100
            emitter.emissionAngle = CGFloat(-Double.pi / 2)
            emitter.emissionAngleRange = CGFloat(Double.pi / 8)
            emitter.particleAlpha = 0.5
            emitter.particleAlphaRange = 0.1
            emitter.particleScale = 0.2
            emitter.particleScaleRange = 0.1
            emitter.particleColor = UIColor.white
            emitter.particleColorBlendFactor = 1.0
            emitter.particlePositionRange = CGVector(dx: UIScreen.main.bounds.width, dy: 0)
            emitter.particleZPosition = 10
            return emitter
        }

        private func makeCloudEmitter() -> SKEmitterNode {
            let emitter = SKEmitterNode()
            emitter.particleTexture = makeCloudTexture()
            emitter.particleBirthRate = 20
            emitter.particleLifetime = 10
            emitter.particleSpeed = 50
            emitter.particleSpeedRange = 20
            emitter.emissionAngle = 0
            emitter.emissionAngleRange = CGFloat(Double.pi / 4)
            emitter.particleAlpha = 0.3
            emitter.particleAlphaRange = 0.2
            emitter.particleScale = 0.6
            emitter.particleScaleRange = 0.3
            emitter.particleColor = UIColor.gray.withAlphaComponent(0.5)
            emitter.particleColorBlendFactor = 1.0
            emitter.particlePositionRange = CGVector(dx: UIScreen.main.bounds.width, dy: 0)
            emitter.particleZPosition = 5
            return emitter
        }

        private func makeSnowEmitter() -> SKEmitterNode {
            let emitter = SKEmitterNode()
            emitter.particleTexture = makeSnowflakeTexture()
            emitter.particleBirthRate = 100
            emitter.particleLifetime = 8
            emitter.particleSpeed = -100
            emitter.particleSpeedRange = 50
            emitter.emissionAngle = CGFloat(-Double.pi / 2)
            emitter.emissionAngleRange = CGFloat(Double.pi / 4)
            emitter.particleAlpha = 0.8
            emitter.particleAlphaRange = 0.2
            emitter.particleScale = 0.3
            emitter.particleScaleRange = 0.2
            emitter.particleColor = UIColor.white
            emitter.particleColorBlendFactor = 1.0
            emitter.particlePositionRange = CGVector(dx: UIScreen.main.bounds.width, dy: 0)
            emitter.particleZPosition = 10
            return emitter
        }

        private func makeRainDropTexture() -> SKTexture {
            let size = CGSize(width: 2, height: 10)
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            let context = UIGraphicsGetCurrentContext()!

            context.setFillColor(UIColor.white.cgColor)
            let path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 1)
            path.fill()

            let image = UIGraphicsGetImageFromCurrentImageContext()!
            UIGraphicsEndImageContext()
            return SKTexture(image: image)
        }

        private func makeCloudTexture() -> SKTexture {
            let size = CGSize(width: 40, height: 25)
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            let context = UIGraphicsGetCurrentContext()!

            context.setFillColor(UIColor.gray.withAlphaComponent(0.5).cgColor)
            let path = UIBezierPath(ovalIn: CGRect(x: 0, y: 5, width: 25, height: 20))
            path.append(UIBezierPath(ovalIn: CGRect(x: 15, y: 0, width: 25, height: 25)))
            path.fill()

            let image = UIGraphicsGetImageFromCurrentImageContext()!
            UIGraphicsEndImageContext()
            return SKTexture(image: image)
        }

        private func makeSnowflakeTexture() -> SKTexture {
            let size = CGSize(width: 10, height: 10)
            UIGraphicsBeginImageContextWithOptions(size, false, 0)
            let context = UIGraphicsGetCurrentContext()!

            context.setStrokeColor(UIColor.white.cgColor)
            context.setLineWidth(1)

            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width / 2 - 1

            func drawLine(angle: CGFloat) {
                let start = CGPoint(x: center.x + cos(angle) * radius * 0.5,
                                    y: center.y + sin(angle) * radius * 0.5)
                let end = CGPoint(x: center.x + cos(angle) * radius,
                                  y: center.y + sin(angle) * radius)
                context.move(to: start)
                context.addLine(to: end)
            }

            for i in 0..<6 {
                let angle = CGFloat(i) * CGFloat.pi / 3
                drawLine(angle: angle)
                drawLine(angle: angle + CGFloat.pi / 6)
            }

            context.strokePath()

            let image = UIGraphicsGetImageFromCurrentImageContext()!
            UIGraphicsEndImageContext()
            return SKTexture(image: image)
        }
    }
}

#endif
