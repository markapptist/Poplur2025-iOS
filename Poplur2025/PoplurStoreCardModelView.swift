import SceneKit
import SwiftUI
import UIKit

/// The native fallback carousel owns exactly one live SceneKit surface. Product
/// tiles use the bundled card posters instead of additional render contexts.
struct PoplurStoreCardModelView: UIViewRepresentable {
    let modelName: String
    let presentationRotationX: Float

    func makeUIView(context: Context) -> SCNView {
        let view = PoplurManagedSCNView(
            performanceName: "StoreCardCarousel3D",
            classification: .heavy,
            rateClass: .decorative
        )
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 30
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.scene = makeScene()
        view.isPlaying = true
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    static func dismantleUIView(_ uiView: SCNView, coordinator: Void) {
        uiView.scene?.rootNode.removeAllActions()
        (uiView as? PoplurManagedSCNView)?.poplurTearDown()
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        guard let url = RuntimeGLBLoader.bundledURL(
            named: modelName,
            candidateSubdirectories: ["StoreModels"]
        ), let imported = RuntimeGLBLoader.loadScene(from: url, label: modelName) else {
            addCameraAndLights(to: scene)
            return scene
        }

        let geometryRoot = SCNNode()
        imported.rootNode.childNodes.forEach { geometryRoot.addChildNode($0.clone()) }
        geometryRoot.eulerAngles.x = presentationRotationX

        let presentationRoot = SCNNode()
        presentationRoot.addChildNode(geometryRoot)
        RuntimeGLBLoader.normalize(presentationRoot, targetExtent: 1.55)
        scene.rootNode.addChildNode(presentationRoot)

        let rotation = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 12)
        rotation.timingMode = .linear
        presentationRoot.runAction(.repeatForever(rotation))
        addCameraAndLights(to: scene)
        return scene
    }

    private func addCameraAndLights(to scene: SCNScene) {
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 34
        camera.position = SCNVector3(0, 0, 2.45)
        scene.rootNode.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 1_050
        key.eulerAngles = SCNVector3(-0.55, 0.55, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .directional
        fill.light?.intensity = 420
        fill.light?.color = UIColor(red: 0.62, green: 0.78, blue: 1, alpha: 1)
        fill.eulerAngles = SCNVector3(0.25, -.pi + 0.4, 0)
        scene.rootNode.addChildNode(fill)
    }
}

struct PoplurStoreCardPosterView: View {
    let assetName: String
    let name: String
    let accent: Color

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, accent.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if let image = UIImage(named: assetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 30, weight: .bold))
                    Text(name)
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(0.92))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipped()
        .accessibilityLabel("\(name) card preview")
    }
}
