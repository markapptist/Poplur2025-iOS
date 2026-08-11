import SwiftUI
import AVFoundation
import SceneKit

// MARK: – Post-login loading screen (loops auth_transition.mp4)

struct LoadingTransitionVideoView: UIViewRepresentable {
    @MainActor
    final class Coordinator {
        var player: AVQueuePlayer?
        var looper: AVPlayerLooper?
        var performanceRegistration: PoplurPerformanceRegistration?

        func tearDown(playerLayer: AVPlayerLayer? = nil) {
            performanceRegistration?.setVisible(false)
            performanceRegistration?.invalidate()
            performanceRegistration = nil
            player?.pause()
            looper = nil
            player?.removeAllItems()
            player = nil
            playerLayer?.player = nil
        }

        deinit {
            let registration = performanceRegistration
            let retainedPlayer = player
            Task { @MainActor in
                registration?.setVisible(false)
                registration?.invalidate()
                retainedPlayer?.pause()
                retainedPlayer?.removeAllItems()
            }
        }
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
        let registration = PoplurPerformanceManager.shared.registerRenderer(
            name: "AuthTransitionVideo",
            classification: .decorative,
            onPolicy: { [weak queuePlayer] _, granted in
                granted ? queuePlayer?.play() : queuePlayer?.pause()
            },
            onPurgeInactiveResources: { [weak queuePlayer] in
                queuePlayer?.pause()
            }
        )
        context.coordinator.performanceRegistration = registration
        view.visibilityChanged = { [weak registration] visible in
            registration?.setVisible(visible)
        }
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {}

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        uiView.visibilityChanged = nil
        coordinator.tearDown(playerLayer: uiView.playerLayer)
    }

    private static func videoURL() -> URL? {
        Bundle.main.url(forResource: "auth_transition", withExtension: "mp4")
            ?? Bundle.main.url(forResource: "auth_transition", withExtension: "mov")
    }

    final class PlayerContainerView: UIView {
        let playerLayer = AVPlayerLayer()
        var visibilityChanged: ((Bool) -> Void)?

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

        override func didMoveToWindow() {
            super.didMoveToWindow()
            visibilityChanged?(window != nil && !isHidden && alpha > 0.01)
        }
    }
}

// MARK: – Pre-login loading screen (spinning cube on white)

struct LoginCubeLoadingView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let scnView = PoplurManagedSCNView(performanceName: "LoginCubeLoading3D")
        scnView.backgroundColor = .white
        scnView.autoenablesDefaultLighting = true
        scnView.allowsCameraControl = false
        scnView.preferredFramesPerSecond = PoplurPerformanceManager.shared.targetFPS
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

    static func dismantleUIView(_ uiView: SCNView, coordinator: ()) {
        (uiView as? PoplurManagedSCNView)?.poplurTearDown()
    }

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
