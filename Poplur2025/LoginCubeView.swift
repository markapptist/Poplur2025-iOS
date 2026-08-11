import SwiftUI
import SceneKit
import simd

/// The dedicated cube shown on pre-login screens (Welcome/Login/SignUp) — a fixed branding
/// model, distinct from the per-skin navigation cube used after sign-in.
///
/// Loads the .dae (Collada) source of the login cube via Apple's native SCNScene(url:) loader,
/// NOT the GLB via GLTFSceneKit's GLTFSceneSource — that path is confirmed to segfault
/// (EXC_BAD_ACCESS inside -[SCNSceneSource sceneWithClass:options:statusHandler:]) on this
/// asset and on the main cube's GLB assets alike. The .dae + its 6 texture PNGs sit together
/// in LoginCube/ and are loaded through the mature, native DAE import path instead.
///
/// When `onTap` is non-nil the cube acts as a back button and plays a periodic "peek" animation
/// every ~3 s: it rotates 90° to reveal the back-arrow face, holds briefly, then rotates back to
/// the Poplur logo face so the user knows it's interactive.
struct LoginCubeView: UIViewRepresentable {
    enum Face {
        case brand
        case forward
    }

    private static let assetName = "poplr_login_cube_equal_faces"
    private static let candidateSubdirectories = ["LoginCube"]

    var onTap: (() -> Void)? = nil
    var onBack: (() -> Void)? = nil
    var onForward: (() -> Void)? = nil
    var face: Face = .brand

    private var isNavigationCube: Bool { onBack != nil || onForward != nil }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onBack: onBack, onForward: onForward)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = PoplurManagedSCNView(performanceName: "LoginCube3D")
        view.backgroundColor = .clear
        view.scene = Self.makeScene(isBackButton: onTap != nil, isNavigationCube: isNavigationCube, face: face)
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = false
        view.isUserInteractionEnabled = onTap != nil || isNavigationCube
        if view.isUserInteractionEnabled {
            let recognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
            view.addGestureRecognizer(recognizer)
        }
        if isNavigationCube {
            let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
            view.addGestureRecognizer(pan)
            context.coordinator.navigationNode = view.scene?.rootNode.childNode(withName: "navigationCube", recursively: true)
        }
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onBack = onBack
        context.coordinator.onForward = onForward
    }

    final class Coordinator: NSObject {
        var onTap: (() -> Void)?
        var onBack: (() -> Void)?
        var onForward: (() -> Void)?
        weak var navigationNode: SCNNode?
        private var panStartX: CGFloat = 0
        private(set) var isShowingBack = false

        init(onTap: (() -> Void)?, onBack: (() -> Void)?, onForward: (() -> Void)?) {
            self.onTap = onTap
            self.onBack = onBack
            self.onForward = onForward
        }

        @objc func handleTap() {
            if onBack != nil || onForward != nil {
                isShowingBack ? onBack?() : onForward?()
            } else {
                onTap?()
            }
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                panStartX = recognizer.translation(in: recognizer.view).x
            case .ended:
                let delta = recognizer.translation(in: recognizer.view).x - panStartX
                guard abs(delta) > 24 else { return }
                isShowingBack.toggle()
                let targetY: CGFloat = (isShowingBack ? .pi / 2 : .pi) + 0.56
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.42
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                navigationNode?.eulerAngles.y = Float(targetY)
                SCNTransaction.commit()
            default:
                break
            }
        }
    }

    private static func makeScene(isBackButton: Bool = false, isNavigationCube: Bool = false, face: Face = .brand) -> SCNScene {
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
        container.name = isNavigationCube ? "navigationCube" : "loginCube"
        for child in loadedScene.rootNode.childNodes {
            child.removeFromParentNode()
            container.addChildNode(child)
        }
        guard !container.childNodes.isEmpty else { return scene }

        RuntimeGLBLoader.normalize(container)
        let spinPivot = SCNNode()
        spinPivot.addChildNode(container)
        if isNavigationCube {
            // Original DAE faces: OK/check is opposite the logo, while BACK is the adjacent face.
            // Start on the check face; a horizontal swipe rotates exactly one quarter turn to BACK.
            // A deliberate three-quarter pose keeps the active face readable while exposing
            // enough of the top and adjacent side that the control cannot read as a flat tile.
            container.eulerAngles = SCNVector3(-0.42, Float.pi + 0.56, 0)
        } else { switch face {
        case .brand:
            container.eulerAngles = SCNVector3(0, Float.pi, 0)
        case .forward:
            // The approved Welcome pose presents the FORWARD (+X) face to camera and tips the
            // adjacent OK (-Z) face toward the viewer as the cube's top surface.
            let forwardToCamera = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(0, 1, 0))
            let okFaceToTop = simd_quatf(angle: .pi / 2, axis: SIMD3<Float>(0, 0, 1))
            let revealTop = simd_quatf(angle: .pi / 10, axis: SIMD3<Float>(1, 0, 0))
            container.simdOrientation = revealTop * okFaceToTop * forwardToCamera

            // Claude's approved Welcome artifact idles at 12°/s. Keep that motion exclusive
            // to the decorative Welcome cube so the interactive auth cubes retain their peek.
            let idleSpin = SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 30)
            idleSpin.timingMode = .linear
            // Rotate the parent around screen/world vertical. Rotating the already-pitched
            // model itself would tumble the OK face from top to front and bottom.
            spinPivot.runAction(.repeatForever(idleSpin), forKey: "welcomeIdleSpin")
        }}
        scene.rootNode.addChildNode(spinPivot)

        // Periodic spring pop (~every 3.5s)
        let popUp = SCNAction.scale(to: 1.14, duration: 0.20)
        popUp.timingMode = .easeOut
        let popDown = SCNAction.scale(to: 1.0, duration: 0.36)
        popDown.timingMode = .easeInEaseOut
        let wait = SCNAction.wait(duration: 3.5, withRange: 1.5)
        container.runAction(SCNAction.repeatForever(SCNAction.sequence([wait, popUp, popDown])), forKey: "pop")

        // Back-button peek: rotate 90° to reveal back-arrow face, hold, then rotate back.
        // Fires every ~3 s so the user discovers the cube is tappable.
        if isBackButton && !isNavigationCube {
            let peekWait = SCNAction.wait(duration: 3.0, withRange: 0.6)
            // Rotate -90° around Y to show the adjacent (back-arrow) face
            let peekTo = SCNAction.rotateBy(x: 0, y: -.pi / 2, z: 0, duration: 0.42)
            peekTo.timingMode = .easeInEaseOut
            let hold = SCNAction.wait(duration: 0.9)
            // Rotate back +90° to restore the Poplur logo face
            let peekBack = SCNAction.rotateBy(x: 0, y: .pi / 2, z: 0, duration: 0.42)
            peekBack.timingMode = .easeInEaseOut
            let peekCycle = SCNAction.sequence([peekWait, peekTo, hold, peekBack])
            container.runAction(SCNAction.repeatForever(peekCycle), forKey: "peek")
        }

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
