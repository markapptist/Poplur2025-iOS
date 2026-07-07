import SwiftUI
import AVFoundation
import SceneKit

// MARK: – Post-login loading screen (loops auth_transition.mp4)

struct LoadingTransitionVideoView: UIViewRepresentable {
    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        guard let url = Self.videoURL() else { return view }
        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        context.coordinator.player = queuePlayer
        context.coordinator.looper = looper
        view.playerLayer.player = queuePlayer
        view.playerLayer.videoGravity = .resizeAspect
        queuePlayer.play()
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {}

    private static func videoURL() -> URL? {
        Bundle.main.url(forResource: "auth_transition", withExtension: "mp4")
            ?? Bundle.main.url(forResource: "auth_transition", withExtension: "mov")
    }

    final class PlayerContainerView: UIView {
        let playerLayer = AVPlayerLayer()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .white
            layer.addSublayer(playerLayer)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }
    }
}

// MARK: – Pre-login loading screen (spinning cube on white)

struct LoginCubeLoadingView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .white
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = false
        scnView.preferredFramesPerSecond = 60
        scnView.antialiasingMode = .multisampling4X

        let scene = SCNScene()

        // Camera — same settings as CubeTabView so the cube looks the same size
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 40
        cameraNode.position = SCNVector3(0, 0, 5.0)
        scene.rootNode.addChildNode(cameraNode)

        // Ambient light so the cube is visible on white
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light!.type = .ambient
        ambient.light!.intensity = 600
        ambient.light!.color = UIColor.white
        scene.rootNode.addChildNode(ambient)

        // Directional key light
        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 900
        key.light!.color = UIColor.white
        key.eulerAngles = SCNVector3(-Float.pi / 5, Float.pi / 6, 0)
        scene.rootNode.addChildNode(key)

        // Cube node
        let cubeNode = Self.loadLoginCube() ?? Self.fallbackCubeNode()
        scene.rootNode.addChildNode(cubeNode)

        // Idle spin
        let spin = SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0.15, y: 1.0, z: 0.08, duration: 2.8)
        )
        cubeNode.runAction(spin, forKey: "loginSpin")

        scnView.scene = scene
        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    private static func loadLoginCube() -> SCNNode? {
        let url = Bundle.main.url(forResource: "poplr_login_cube_equal_faces", withExtension: "dae", subdirectory: "LoginCube")
               ?? Bundle.main.url(forResource: "poplr_login_cube_equal_faces", withExtension: "dae")
        guard let url, let scene = try? SCNScene(url: url, options: nil) else { return nil }
        let container = SCNNode()
        for child in scene.rootNode.childNodes {
            child.removeFromParentNode()
            container.addChildNode(child)
        }
        guard !container.childNodes.isEmpty else { return nil }
        RuntimeGLBLoader.normalize(container)
        return container
    }

    private static func fallbackCubeNode() -> SCNNode {
        let box = SCNBox(width: 1.2, height: 1.2, length: 1.2, chamferRadius: 0.06)
        let mat = SCNMaterial()
        mat.diffuse.contents = UIColor(white: 0.18, alpha: 1)
        mat.lightingModel = .lambert
        box.materials = [mat]
        return SCNNode(geometry: box)
    }
}
