import SwiftUI
import SceneKit

// MARK: - Poplur Earth Intro
//
// A stylised "clay Earth" GLB spinning inside a procedural starfield, shown as the
// map-launch curtain. As the curtain fades, MapKit (already parked at a world view)
// is revealed underneath and descends into the user's location — so the stylised
// globe cross-dissolves into the real map zooming in.

struct PoplurEarthIntroView: UIViewRepresentable {
    /// Slowly dollies the camera toward the globe so the hand-off to the map carries momentum.
    var pushIn: Bool = true

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling2X
        view.isUserInteractionEnabled = false
        view.rendersContinuously = true

        let scene = SCNScene()
        scene.background.contents = Self.starfieldImage()
        view.scene = scene

        // Camera
        let camera = SCNCamera()
        camera.fieldOfView = 38
        camera.zNear = 0.01
        camera.zFar = 100
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 4.2)
        scene.rootNode.addChildNode(cameraNode)

        // Lighting — soft ambient + a key light for a clean terminator on the clay.
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 260
        ambient.light?.color = UIColor(red: 0.55, green: 0.60, blue: 0.85, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.light?.color = UIColor(red: 1.0, green: 0.96, blue: 0.9, alpha: 1)
        key.position = SCNVector3(-3, 2.5, 4)
        key.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(key)

        // Pivot holds the globe with a natural axial tilt and spins forever.
        let pivot = SCNNode()
        pivot.eulerAngles = SCNVector3(0.15, 0, 0.41) // ~23.5° tilt
        scene.rootNode.addChildNode(pivot)
        pivot.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 26)))
        context.coordinator.pivot = pivot

        // SCNSceneSource._sceneWithClass crashes with SIGSEGV on ARM64 when processing the
        // 46 MB poplur_clay_earth.glb; PLTryCatch cannot intercept native signals. Use the
        // SCNSphere globe directly — earth_day texture gives it the same visual weight.
        context.coordinator.addFallbackGlobe(to: pivot)

        if pushIn {
            let dolly = SCNAction.move(to: SCNVector3(0, 0, 3.2), duration: 6)
            dolly.timingMode = .easeInEaseOut
            cameraNode.runAction(dolly)
        }

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var pivot: SCNNode?

        func addFallbackGlobe(to pivot: SCNNode) {
            let sphere = SCNSphere(radius: 1.15)
            sphere.segmentCount = 96
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = UIImage(named: "earth_day") ?? UIColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 1)
            m.selfIllumination.contents = UIImage(named: "earth_night") ?? UIColor.clear
            m.selfIllumination.intensity = 0.6
            m.roughness.contents = 0.65
            m.metalness.contents = 0.0
            sphere.materials = [m]
            let node = SCNNode(geometry: sphere)
            node.opacity = 0
            pivot.addChildNode(node)
            node.runAction(.fadeIn(duration: 0.6))
        }
    }

    // MARK: Procedural starfield

    private static var cachedStars: UIImage?

    static func starfieldImage() -> UIImage {
        if let cached = cachedStars { return cached }
        let size = CGSize(width: 2048, height: 1024)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            // Deep-space vertical gradient.
            let colors = [
                UIColor(red: 0.01, green: 0.01, blue: 0.05, alpha: 1).cgColor,
                UIColor(red: 0.04, green: 0.02, blue: 0.10, alpha: 1).cgColor,
                UIColor(red: 0.01, green: 0.01, blue: 0.04, alpha: 1).cgColor,
            ]
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors as CFArray, locations: [0, 0.5, 1]) {
                cg.drawLinearGradient(grad, start: .zero,
                                      end: CGPoint(x: 0, y: size.height), options: [])
            }
            var gen = SystemRandomNumberGenerator()
            // Faint dust
            for _ in 0..<1400 {
                let x = CGFloat.random(in: 0..<size.width, using: &gen)
                let y = CGFloat.random(in: 0..<size.height, using: &gen)
                let r = CGFloat.random(in: 0.3..<0.9, using: &gen)
                let a = CGFloat.random(in: 0.15..<0.5, using: &gen)
                cg.setFillColor(UIColor(white: 1, alpha: a).cgColor)
                cg.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
            // Bright stars with a hint of colour
            for _ in 0..<260 {
                let x = CGFloat.random(in: 0..<size.width, using: &gen)
                let y = CGFloat.random(in: 0..<size.height, using: &gen)
                let r = CGFloat.random(in: 1.0..<2.6, using: &gen)
                let a = CGFloat.random(in: 0.6..<1.0, using: &gen)
                let tint = [UIColor(white: 1, alpha: a),
                            UIColor(red: 0.7, green: 0.8, blue: 1, alpha: a),
                            UIColor(red: 1, green: 0.85, blue: 0.7, alpha: a)].randomElement(using: &gen)!
                cg.setFillColor(tint.cgColor)
                cg.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
        }
        cachedStars = image
        return image
    }
}
