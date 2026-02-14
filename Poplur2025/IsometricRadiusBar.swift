import SwiftUI
import SceneKit

public struct IsometricRadiusBar: View {
    @Binding public var radius: Double
    public var body: some View {
        ZStack {
            SceneView(
                scene: makeScene(),
                pointOfView: makeCameraNode(), options: [.allowsCameraControl],
                preferredFramesPerSecond: 60,
                antialiasingMode: .multisampling4X
            )
            .frame(width: 60, height: 200)
            .background(Color.clear)
            .allowsHitTesting(false)
        }
        // Optional overlay area for tap/drag gestures
        .overlay(
            Rectangle()
                .foregroundColor(Color.clear)
                .contentShape(Rectangle())
        )
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        let boxNode = SCNNode(geometry: makeBoxGeometry())
        boxNode.position = SCNVector3(0, Float(clampedHeight()/2), 0)
        scene.rootNode.addChildNode(boxNode)
        scene.background.contents = UIColor.clear
        return scene
    }

    private func makeBoxGeometry() -> SCNBox {
        let height = clampedHeight()
        let box = SCNBox(width: 20, height: CGFloat(height), length: 20, chamferRadius: 0)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.blue
        box.materials = [material]
        return box
    }

    private func clampedHeight() -> Double {
        let clamped = max(100, min(radius, 10_000))
        return clamped
    }

    private func makeCameraNode() -> SCNNode {
        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 70
        camera.zNear = 1
        camera.zFar = 1000

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        // Position camera back a bit on z axis
        cameraNode.position = SCNVector3(0, 50, 100)
        // Rotate to isometric-like: 45° around Y and ~30° around X
        cameraNode.eulerAngles = SCNVector3(-Float(30.0 * Double.pi / 180), Float(45.0 * Double.pi / 180), 0)
        return cameraNode
    }
}
