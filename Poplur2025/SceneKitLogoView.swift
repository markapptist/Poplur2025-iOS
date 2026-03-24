import SwiftUI
import SceneKit

public struct SceneKitLogoView: View {
    public var background: Color = .pink
    public var logoName: String? = "logo"
    public var shouldLoop: Bool = true
    public var shouldRotate: Bool = false
    public var animationSpeedFactor: CGFloat = 1.0

    public init(
        background: Color = .pink,
        logoName: String? = "logo",
        shouldLoop: Bool = true,
        shouldRotate: Bool = false,
        animationSpeedFactor: CGFloat = 1.0
    ) {
        self.background = background
        self.logoName = logoName
        self.shouldLoop = shouldLoop
        self.shouldRotate = shouldRotate
        self.animationSpeedFactor = animationSpeedFactor
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                    .ignoresSafeArea()
                SceneView(
                    scene: makeScene(size: geo.size, logoName: logoName),
                    options: [.allowsCameraControl]
                )
            }
        }
    }

    private func makeScene(size: CGSize, logoName: String?) -> SCNScene {
        let scene = SCNScene()

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.usesOrthographicProjection = false
        cameraNode.camera?.fieldOfView = 50
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 6)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        // Lights
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor(white: 0.3, alpha: 1.0) // low intensity
        let ambientNode = SCNNode()
        ambientNode.light = ambientLight
        scene.rootNode.addChildNode(ambientNode)

        let omniLight = SCNLight()
        omniLight.type = .omni
        omniLight.color = UIColor.white
        let omniNode = SCNNode()
        omniNode.light = omniLight
        omniNode.position = SCNVector3(x: 0, y: 5, z: 5)
        scene.rootNode.addChildNode(omniNode)
        
        let dirLight = SCNLight()
        dirLight.type = .directional
        dirLight.intensity = 800
        dirLight.castsShadow = true
        let dirNode = SCNNode()
        dirNode.light = dirLight
        dirNode.eulerAngles = SCNVector3(-Float.pi/3, Float.pi/6, 0)
        scene.rootNode.addChildNode(dirNode)

        // Logo node
        let logoNode = makeLogoNode(logoName: logoName)
        logoNode.name = "LogoNode"
        logoNode.position = SCNVector3Zero
        scene.rootNode.addChildNode(logoNode)

        // Animation: pulse scale
        let scaleUp = SCNAction.scale(to: 1.15, duration: 0.6)
        scaleUp.timingMode = .easeInEaseOut
        let scaleDown = SCNAction.scale(to: 1.0, duration: 0.6)
        scaleDown.timingMode = .easeInEaseOut
        let sequence = SCNAction.sequence([scaleUp, scaleDown])
        let action: SCNAction
        if shouldLoop {
            action = SCNAction.repeatForever(sequence)
        } else {
            action = sequence
        }
        action.speed = animationSpeedFactor
        logoNode.runAction(action)

        if shouldRotate {
            let rotateAction = SCNAction.repeatForever(
                SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 6.0)
            )
            logoNode.runAction(rotateAction, forKey: "y-rotation")
        }

        return scene
    }

    private func makeLogoNode(logoName: String?) -> SCNNode {
        if
            let logoName = logoName,
            let uiImage = UIImage(named: logoName),
            let _ = uiImage.cgImage
        {
            // Build a vector-extruded shape (best quality 3D outline)
            let path = makeLogoBezierPath()
            path.flatness = 0.2

            let depth: CGFloat = 0.25 // substantial thickness for 3D
            let shape = SCNShape(path: path, extrusionDepth: depth)

            let face = SCNMaterial()
            face.diffuse.contents = UIColor.white
            face.lightingModel = .physicallyBased

            let side = SCNMaterial()
            side.diffuse.contents = UIColor(white: 0.85, alpha: 1.0)
            side.lightingModel = .physicallyBased

            shape.materials = [face, side, face] // front, sides, back

            let node = SCNNode(geometry: shape)

            // Scale the path to roughly fit width 2.0 units like before
            let targetWidth: CGFloat = 2.0
            let bounds = path.bounds
            let scale = targetWidth / max(bounds.width, 0.0001)
            node.scale = SCNVector3(scale, scale, 1)

            // Center pivot for clean rotation
            let (minB, maxB) = node.boundingBox
            let cx = (minB.x + maxB.x) / 2
            let cy = (minB.y + maxB.y) / 2
            let cz = (minB.z + maxB.z) / 2
            node.pivot = SCNMatrix4MakeTranslation(cx, cy, cz)

            return node
        } else {
            // fallback geometry: torus tinted white
            let torus = SCNTorus(ringRadius: 1, pipeRadius: 0.3)
            torus.firstMaterial?.diffuse.contents = UIColor.white
            torus.firstMaterial?.lightingModel = .blinn

            let node = SCNNode(geometry: torus)
            return node
        }
    }
    
    // Placeholder vector outline for the logo. Replace with your exact path for perfect fidelity.
    private func makeLogoBezierPath() -> UIBezierPath {
        let path = UIBezierPath()
        // Draw a stylized capital P inside a unit box [0,1] x [0,1], then we will scale in SceneKit
        // Vertical stem
        path.move(to: CGPoint(x: 0.2, y: 0.1))
        path.addLine(to: CGPoint(x: 0.2, y: 0.9))
        path.addLine(to: CGPoint(x: 0.35, y: 0.9))
        path.addLine(to: CGPoint(x: 0.35, y: 0.55))
        // Top bowl (semi-rounded rectangle)
        let bowlRect = CGRect(x: 0.35, y: 0.6, width: 0.45, height: 0.25)
        let bowl = UIBezierPath(roundedRect: bowlRect, cornerRadius: 0.12)
        path.append(bowl)
        // Close stem bottom
        path.addLine(to: CGPoint(x: 0.35, y: 0.1))
        path.addLine(to: CGPoint(x: 0.2, y: 0.1))

        // Outline mode: use even-odd fill to carve the bowl hole
        path.usesEvenOddFillRule = true

        // Scale up to a more comfortable size (unit to points)
        let scale: CGFloat = 200.0
        path.apply(CGAffineTransform(scaleX: scale, y: scale))
        // Recenter around origin so SceneKit centering works better
        let b = path.bounds
        let translate = CGAffineTransform(translationX: -b.midX, y: -b.midY)
        path.apply(translate)
        return path
    }
}

#Preview("SceneKit Logo") {
    struct PreviewWrapper: View {
        @State private var shouldLoop = true
        @State private var shouldRotate = true
        @State private var animationSpeed: CGFloat = 1.0

        var body: some View {
            VStack(spacing: 20) {
                SceneKitLogoView(
                    background: Color.pink,
                    logoName: "logo",
                    shouldLoop: shouldLoop,
                    shouldRotate: shouldRotate,
                    animationSpeedFactor: animationSpeed
                )
                .frame(width: 250, height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 25))
                .shadow(radius: 10)

                Toggle("Loop Animation", isOn: $shouldLoop)
                    .padding(.horizontal, 40)
                
                Toggle("Rotate Y", isOn: $shouldRotate)
                    .padding(.horizontal, 40)

                HStack {
                    Text("Speed:")
                    Slider(value: $animationSpeed, in: 0.1...4.0, step: 0.1)
                    Text(String(format: "%.1fx", animationSpeed))
                        .frame(width: 50, alignment: .leading)
                }
                .padding(.horizontal, 40)
            }
            .padding()
        }
    }
    return PreviewWrapper()
}
