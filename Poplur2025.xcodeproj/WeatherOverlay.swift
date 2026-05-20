import SwiftUI
import SceneKit

struct WeatherVisualizationState {
    enum Kind { case clear, rain, thunderstorms, cloudy }
    var kind: Kind
    var intensity: Double // 0..1
    var lightningFrequency: Double // 0..1
}

struct WeatherParticleOverlay: UIViewRepresentable {
    @Binding var weatherState: WeatherVisualizationState

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = true
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        let scene = SCNScene()
        view.scene = scene

        // Top-down camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 6, 0)
        cameraNode.eulerAngles = SCNVector3(-Float.pi/2, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        context.coordinator.view = view
        context.coordinator.configureScene(for: weatherState)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.configureScene(for: weatherState)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        weak var view: SCNView?

        func configureScene(for state: WeatherVisualizationState) {
            guard let scene = view?.scene else { return }
            // Remove previous emitters
            scene.rootNode.childNodes.forEach { node in
                if node.name == "WeatherEmitter" || node.name == "Lightning" { node.removeFromParentNode() }
            }

            switch state.kind {
            case .clear:
                addSunnyMotes(to: scene, intensity: state.intensity)
            case .rain:
                addRain(to: scene, intensity: state.intensity)
            case .thunderstorms:
                addRain(to: scene, intensity: state.intensity)
                addLightning(to: scene, frequency: state.lightningFrequency)
            case .cloudy:
                addCloudHaze(to: scene, density: state.intensity)
            }
        }

        private func addRain(to scene: SCNScene, intensity: Double) {
            let emitter = SCNParticleSystem()
            emitter.birthRate = CGFloat(600 * max(0.05, intensity))
            emitter.particleLifeSpan = 1.3
            emitter.particleVelocity = 6
            emitter.particleVelocityVariation = 1
            emitter.particleSize = 0.01
            emitter.particleColor = UIColor.white.withAlphaComponent(0.5)
            emitter.emitterShape = SCNBox(width: 8, height: 0.1, length: 8, chamferRadius: 0)
            emitter.acceleration = SCNVector3(0, -9.8, 0)
            emitter.loops = true

            let node = SCNNode()
            node.name = "WeatherEmitter"
            node.position = SCNVector3(0, 3.8, 0)
            node.addParticleSystem(emitter)
            scene.rootNode.addChildNode(node)
        }

        private func addLightning(to scene: SCNScene, frequency: Double) {
            let lightNode = SCNNode()
            lightNode.name = "Lightning"
            let light = SCNLight()
            light.type = .omni
            light.color = UIColor.white
            light.intensity = 0
            lightNode.light = light
            lightNode.position = SCNVector3(0, 5, 2)
            scene.rootNode.addChildNode(lightNode)

            let flash = CABasicAnimation(keyPath: "light.intensity")
            flash.fromValue = 0
            flash.toValue = 2200
            flash.duration = 0.08
            flash.autoreverses = true
            flash.repeatCount = .infinity
            flash.timeOffset = Double.random(in: 0...1)
            flash.repeatDuration = CFTimeInterval(max(0.2, 3.0 - frequency * 2.5))
            lightNode.addAnimation(flash, forKey: "lightningFlash")
        }

        private func addSunnyMotes(to scene: SCNScene, intensity: Double) {
            let motes = SCNParticleSystem()
            motes.birthRate = CGFloat(60 * max(0.05, intensity))
            motes.particleLifeSpan = 3.0
            motes.particleVelocity = 0.3
            motes.particleSize = 0.02
            motes.particleColor = UIColor.yellow.withAlphaComponent(0.4)
            motes.emitterShape = SCNSphere(radius: 2.5)
            motes.acceleration = SCNVector3(0, 0.1, 0)

            let node = SCNNode()
            node.name = "WeatherEmitter"
            node.position = SCNVector3(0, 1.2, 0)
            node.addParticleSystem(motes)
            scene.rootNode.addChildNode(node)
        }

        private func addCloudHaze(to scene: SCNScene, density: Double) {
            let haze = SCNParticleSystem()
            haze.birthRate = CGFloat(24 * max(0.05, density))
            haze.particleLifeSpan = 6.0
            haze.particleVelocity = 0.2
            haze.particleSize = 0.4
            haze.particleColor = UIColor.white.withAlphaComponent(0.12)
            haze.emitterShape = SCNSphere(radius: 3.0)

            let node = SCNNode()
            node.name = "WeatherEmitter"
            node.position = SCNVector3(0, 1.6, 0)
            node.addParticleSystem(haze)
            scene.rootNode.addChildNode(node)
        }
    }
}
