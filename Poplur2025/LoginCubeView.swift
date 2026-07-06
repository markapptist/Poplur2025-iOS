import SwiftUI
import SceneKit

/// The dedicated cube shown on pre-login screens (Welcome/Login/SignUp) — a fixed branding
/// model, distinct from the per-skin navigation cube used after sign-in.
///
/// Loads the .dae (Collada) source of the login cube via Apple's native SCNScene(url:) loader,
/// NOT the GLB via GLTFSceneKit's GLTFSceneSource — that path is confirmed to segfault
/// (EXC_BAD_ACCESS inside -[SCNSceneSource sceneWithClass:options:statusHandler:]) on this
/// asset and on the main cube's GLB assets alike. The .dae + its 6 texture PNGs sit together
/// in LoginCube/ and are loaded through the mature, native DAE import path instead.
struct LoginCubeView: UIViewRepresentable {
    private static let assetName = "poplr_login_cube_equal_faces"
    private static let candidateSubdirectories = ["LoginCube"]

    var onTap: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.scene = Self.makeScene()
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = onTap != nil
        if onTap != nil {
            let recognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
            view.addGestureRecognizer(recognizer)
        }
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.onTap = onTap
    }

    final class Coordinator: NSObject {
        var onTap: (() -> Void)?
        init(onTap: (() -> Void)?) { self.onTap = onTap }
        @objc func handleTap() { onTap?() }
    }

    private static func makeScene() -> SCNScene {
        let scene = SCNScene()

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(cameraNode)

        let environment = SCNNode()
        environment.light = {
            let light = SCNLight()
            light.type = .ambient
            light.intensity = 400
            return light
        }()
        scene.rootNode.addChildNode(environment)

        guard let url = daeURL(),
              let loadedScene = try? SCNScene(url: url, options: nil) else {
            print("[LoginCubeView] Could not load login cube .dae")
            return scene
        }

        let container = SCNNode()
        for child in loadedScene.rootNode.childNodes {
            child.removeFromParentNode()
            container.addChildNode(child)
        }
        guard !container.childNodes.isEmpty else { return scene }

        RuntimeGLBLoader.normalize(container)
        scene.rootNode.addChildNode(container)

        // Gentle hover
        let up = SCNAction.moveBy(x: 0, y: 0.06, z: 0, duration: 1.4)
        up.timingMode = .easeInEaseOut
        let down = SCNAction.moveBy(x: 0, y: -0.06, z: 0, duration: 1.4)
        down.timingMode = .easeInEaseOut
        container.runAction(SCNAction.repeatForever(SCNAction.sequence([up, down])), forKey: "hover")

        // Periodic spring pop (~every 3.5s)
        let popUp = SCNAction.scale(to: 1.14, duration: 0.20)
        popUp.timingMode = .easeOut
        let popDown = SCNAction.scale(to: 1.0, duration: 0.36)
        popDown.timingMode = .easeInEaseOut
        let wait = SCNAction.wait(duration: 3.5, withRange: 1.5)
        container.runAction(SCNAction.repeatForever(SCNAction.sequence([wait, popUp, popDown])), forKey: "pop")

        return scene
    }

    private static func daeURL() -> URL? {
        for subdirectory in candidateSubdirectories {
            if let url = Bundle.main.url(forResource: assetName, withExtension: "dae", subdirectory: subdirectory) {
                return url
            }
        }
        return Bundle.main.url(forResource: assetName, withExtension: "dae")
    }
}
