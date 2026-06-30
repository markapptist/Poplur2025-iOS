import SwiftUI
import SceneKit
import UIKit

struct HeadPreviewView: View {
    let modelURL: URL

    private var isSupportedModel: Bool {
        HeadScenePreview.supportedExtensions.contains(modelURL.pathExtension.lowercased())
    }

    var body: some View {
        Group {
            if isSupportedModel {
                HeadScenePreview(modelURL: modelURL)
            } else {
                HeadPreviewUnavailableView()
            }
        }
        .clipShape(Circle())
    }
}

private struct HeadPreviewUnavailableView: View {
    var body: some View {
        Color.clear
    }
}

private struct HeadScenePreview: UIViewRepresentable {
    static let supportedExtensions: Set<String> = ["usdz", "scn", "dae"]

    let modelURL: URL

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.scene = SCNScene()
        context.coordinator.load(modelURL, into: view)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private weak var view: SCNView?

        func load(_ url: URL, into view: SCNView) {
            self.view = view
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let scene = try? SCNScene(url: url, options: [
                    SCNSceneSource.LoadingOption.convertUnitsToMeters: true,
                    SCNSceneSource.LoadingOption.convertToYUp: true
                ]) else {
                    print("[HeadPreviewView] Unsupported or unreadable model: \(url.lastPathComponent)")
                    return
                }
                DispatchQueue.main.async {
                    self?.configure(scene, in: view)
                }
            }
        }

        private func configure(_ scene: SCNScene, in view: SCNView) {
            let modelRoot = SCNNode()
            scene.rootNode.childNodes.forEach { node in
                node.removeFromParentNode()
                modelRoot.addChildNode(node)
            }

            let (minBB, maxBB) = modelRoot.boundingBox
            let extent = SCNVector3(maxBB.x - minBB.x, maxBB.y - minBB.y, maxBB.z - minBB.z)
            let maxExtent = Swift.max(extent.x, Swift.max(extent.y, extent.z))
            let scale = maxExtent > 0 ? Float(1.25 / maxExtent) : Float(1)
            let centerX = Float((minBB.x + maxBB.x) / 2)
            let centerY = Float((minBB.y + maxBB.y) / 2)
            let centerZ = Float((minBB.z + maxBB.z) / 2)
            modelRoot.scale = SCNVector3(scale, scale, scale)
            modelRoot.position = SCNVector3(
                -centerX * scale,
                -centerY * scale,
                -centerZ * scale
            )

            let previewScene = SCNScene()
            previewScene.rootNode.addChildNode(modelRoot)
            addLighting(to: previewScene)

            let camera = SCNNode()
            camera.camera = SCNCamera()
            camera.camera?.fieldOfView = 32
            camera.position = SCNVector3(0, 0.02, 2.45)
            previewScene.rootNode.addChildNode(camera)

            view.scene = previewScene
            view.pointOfView = camera

            let turnLeft = SCNAction.rotateBy(x: 0, y: 0.16, z: 0, duration: 2.4)
            let turnRight = SCNAction.rotateBy(x: 0, y: -0.16, z: 0, duration: 2.4)
            turnLeft.timingMode = .easeInEaseOut
            turnRight.timingMode = .easeInEaseOut
            modelRoot.runAction(.repeatForever(.sequence([turnLeft, turnRight])))
        }

        private func addLighting(to scene: SCNScene) {
            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 420
            scene.rootNode.addChildNode(ambient)

            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .directional
            key.light?.intensity = 950
            key.eulerAngles = SCNVector3(-0.45, 0.35, 0)
            scene.rootNode.addChildNode(key)

            let fill = SCNNode()
            fill.light = SCNLight()
            fill.light?.type = .directional
            fill.light?.intensity = 280
            fill.light?.color = UIColor(red: 0.55, green: 0.68, blue: 1, alpha: 1)
            fill.eulerAngles = SCNVector3(0.2, Float.pi - 0.4, 0)
            scene.rootNode.addChildNode(fill)
        }
    }
}
