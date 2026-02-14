import SwiftUI
import SceneKit

public struct BarberPole3DView: UIViewRepresentable {
    public var radius: Int
    public var maxRadius: Int
    public var maxHeight: CGFloat

    public init(radius: Int, maxRadius: Int, maxHeight: CGFloat) {
        self.radius = radius
        self.maxRadius = maxRadius
        self.maxHeight = maxHeight
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView(frame: .zero)
        scnView.backgroundColor = .clear
        scnView.autoenablesDefaultLighting = false
        scnView.allowsCameraControl = false
        scnView.scene = SCNScene()

        // Camera
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, maxHeight / 4, 6)
        scnView.scene?.rootNode.addChildNode(cameraNode)

        // Lights
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light?.type = .ambient
        ambientLightNode.light?.color = UIColor(white: 0.4, alpha: 1)
        scnView.scene?.rootNode.addChildNode(ambientLightNode)

        let directionalLightNode = SCNNode()
        directionalLightNode.light = SCNLight()
        directionalLightNode.light?.type = .directional
        directionalLightNode.light?.color = UIColor(white: 0.8, alpha: 1)
        directionalLightNode.eulerAngles = SCNVector3(-Float.pi / 3, 0, 0)
        scnView.scene?.rootNode.addChildNode(directionalLightNode)

        // Root container node for the pole and parts
        let poleRootNode = SCNNode()
        scnView.scene?.rootNode.addChildNode(poleRootNode)

        // Backing plate (optional)
        let backingWidth: CGFloat = 1.0
        let backingHeight: CGFloat = maxHeight
        let backingLength: CGFloat = 0.1
        let backingGeometry = SCNBox(width: backingWidth, height: backingHeight, length: backingLength, chamferRadius: 0)
        let backingMaterial = SCNMaterial()
        backingMaterial.diffuse.contents = UIColor(white: 0.15, alpha: 0.8)
        backingMaterial.isDoubleSided = true
        backingGeometry.materials = [backingMaterial]
        let backingNode = SCNNode(geometry: backingGeometry)
        backingNode.position = SCNVector3(0, backingHeight / 2, -0.3)
        poleRootNode.addChildNode(backingNode)

        // Pole cylinder
        let poleRadius: CGFloat = 0.35
        let poleHeight: CGFloat = 0.01 // start near zero
        let cylinderGeometry = SCNCylinder(radius: poleRadius, height: poleHeight)
        cylinderGeometry.radialSegmentCount = 60

        // Create spiral striped texture for the pole
        let textureSize = CGSize(width: 256, height: 256)
        let spiralImage = BarberPole3DView.createSpiralStripedImage(size: textureSize)

        let poleMaterial = SCNMaterial()
        poleMaterial.diffuse.contents = spiralImage
        poleMaterial.isDoubleSided = true
        poleMaterial.diffuse.wrapS = .repeat
        poleMaterial.diffuse.wrapT = .repeat

        // Scale to repeat stripes around the cylinder many times
        poleMaterial.diffuse.contentsTransform = SCNMatrix4MakeScale(8, 12, 1)

        cylinderGeometry.materials = [poleMaterial]

        let poleNode = SCNNode(geometry: cylinderGeometry)
        poleNode.position = SCNVector3(0, poleHeight / 2, 0)
        poleRootNode.addChildNode(poleNode)

        // Base cap sphere - chrome-like
        let baseCapRadius = poleRadius * 1.1
        let baseCapGeometry = SCNSphere(radius: baseCapRadius)
        let baseCapMaterial = SCNMaterial()
        baseCapMaterial.diffuse.contents = UIColor.white
        baseCapMaterial.metalness.contents = 1.0
        baseCapMaterial.roughness.contents = 0.1
        baseCapGeometry.materials = [baseCapMaterial]
        let baseCapNode = SCNNode(geometry: baseCapGeometry)
        baseCapNode.position = SCNVector3(0, 0, 0)
        poleRootNode.addChildNode(baseCapNode)

        // Top cap sphere - chrome-like
        let topCapGeometry = SCNSphere(radius: baseCapRadius)
        topCapGeometry.materials = [baseCapMaterial]
        let topCapNode = SCNNode(geometry: topCapGeometry)
        topCapNode.position = SCNVector3(0, poleHeight, 0)
        poleRootNode.addChildNode(topCapNode)

        // Store nodes in coordinator for later updates
        context.coordinator.poleNode = poleNode
        context.coordinator.poleMaterial = poleMaterial
        context.coordinator.topCapNode = topCapNode
        context.coordinator.baseCapNode = baseCapNode

        // Animate spiral rotation on the texture indefinitely
        context.coordinator.startSpiralAnimation()

        // Animate initial height
        context.coordinator.animateHeight(from: poleHeight, to: targetHeight(for: radius))

        return scnView
    }

    public func updateUIView(_ uiView: SCNView, context: Context) {
        let target = targetHeight(for: radius)
        context.coordinator.animateHeight(from: currentHeight(), to: target)
    }

    private func targetHeight(for radiusValue: Int) -> CGFloat {
        guard maxRadius > 0 else { return 0 }
        let clampedRadius = max(0, min(radiusValue, maxRadius))
        return CGFloat(clampedRadius) / CGFloat(maxRadius) * maxHeight
    }

    private func currentHeight() -> CGFloat {
        0 // this is overridden in coordinator; here just a placeholder
    }

    public class Coordinator {
        var parent: BarberPole3DView

        weak var poleNode: SCNNode?
        weak var topCapNode: SCNNode?
        weak var baseCapNode: SCNNode?
        weak var poleMaterial: SCNMaterial?

        private var animationDuration: CFTimeInterval = 0.6

        init(_ parent: BarberPole3DView) {
            self.parent = parent
        }

        func animateHeight(from oldHeight: CGFloat, to newHeight: CGFloat) {
            guard let poleNode = poleNode,
                  let cylinder = poleNode.geometry as? SCNCylinder,
                  let topCapNode = topCapNode,
                  let baseCapNode = baseCapNode else { return }

            if abs(oldHeight - newHeight) < 0.001 {
                return
            }

            SCNTransaction.begin()
            SCNTransaction.animationDuration = animationDuration
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            cylinder.height = newHeight
            // Adjust pole position so bottom stays at y=0
            poleNode.position = SCNVector3(0, newHeight / 2, 0)

            // Move top cap to new top
            topCapNode.position = SCNVector3(0, newHeight, 0)

            SCNTransaction.commit()
        }

        func startSpiralAnimation() {
            guard let material = poleMaterial else { return }

            let rotateAction = SCNAction.repeatForever(
                SCNAction.customAction(duration: 10.0) { (node, elapsedTime) in
                    let progress = elapsedTime / 10.0
                    let angle = Float(progress * 2 * .pi)
                    // rotate contentsTransform about y axis for spiral effect
                    var transform = SCNMatrix4MakeScale(8, 12, 1)
                    // rotation around z axis (texture space)
                    let rotation = SCNMatrix4MakeRotation(angle, 0, 0, 1)
                    transform = SCNMatrix4Mult(rotation, transform)
                    material.diffuse.contentsTransform = transform
                }
            )

            poleNode?.runAction(rotateAction, forKey: "spiralRotation")
        }
    }

    private static func createSpiralStripedImage(size: CGSize) -> UIImage {
        let stripeWidth: CGFloat = size.width / 12 // total 12 stripes
        let diagonalLength = sqrt(size.width * size.width + size.height * size.height)

        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let context = UIGraphicsGetCurrentContext() else { return UIImage() }

        // Fill background white
        context.setFillColor(UIColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        // The stripes run diagonally from bottom-left to top-right

        // We'll draw wide diagonal stripes in red, white, blue repeating

        // Colors sequence:
        let colors: [UIColor] = [
            UIColor.red,
            UIColor.white,
            UIColor.blue,
            UIColor.white
        ]

        // Number of stripes to cover diagonal + some extra for repeat
        let stripesCount = 20

        context.saveGState()
        // Rotate context so stripes run diagonally
        context.translateBy(x: 0, y: size.height)
        context.rotate(by: -.pi / 4)

        for i in 0..<stripesCount {
            let color = colors[i % colors.count]
            context.setFillColor(color.cgColor)
            let rect = CGRect(x: CGFloat(i) * stripeWidth, y: 0, width: stripeWidth, height: diagonalLength)
            context.fill(rect)
        }
        context.restoreGState()

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIImage()
    }
}

#Preview {
    BarberPole3DView(radius: 7, maxRadius: 10, maxHeight: 5)
        .frame(width: 200, height: 400)
        .background(Color.black.opacity(0.85))
}
