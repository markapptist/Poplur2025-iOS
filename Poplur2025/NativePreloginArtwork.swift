import SwiftUI
import SceneKit

/// Uses the same bundled clay meshes and textures as the approved welcome.
/// Only the shared cube is live; account/head thumbnails are rendered once.
struct NativePreloginCube: UIViewRepresentable {
    var welcome: Bool
    var awake: Bool
    var back: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear; view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X; view.rendersContinuously = false
        let scene = SCNScene(); view.scene = scene
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(camera)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity = 400
        scene.rootNode.addChildNode(ambient)
        let model = SCNNode()
        let cubeURL = Bundle.main.url(forResource: "poplr_login_cube_equal_faces", withExtension: "dae", subdirectory: "LoginCube")
            ?? Bundle.main.url(forResource: "poplr_login_cube_equal_faces", withExtension: "dae")
        if let url = cubeURL, let loaded = try? SCNScene(url: url) {
            for node in loaded.rootNode.childNodes { node.removeFromParentNode(); model.addChildNode(node) }
            RuntimeGLBLoader.normalize(model)
        }
        scene.rootNode.addChildNode(model)
        let coordinator = context.coordinator
        coordinator.view = view; coordinator.model = model; coordinator.back = back
        view.addGestureRecognizer(UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tap)))
        view.addGestureRecognizer(UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.pan(_:))))
        coordinator.registration = PoplurPerformanceManager.shared.registerRenderer(name: "NativePreloginCube", classification: .decorative) { [weak coordinator] policy, granted in
            guard let coordinator else { return }
            coordinator.granted = granted
            coordinator.view?.preferredFramesPerSecond = min(24, policy.targetFPS)
            coordinator.refresh()
        }
        coordinator.registration?.setVisible(true)
        return view
    }
    func updateUIView(_ view: SCNView, context: Context) {
        let c = context.coordinator; c.back = back; c.awake = awake
        if c.welcome != welcome {
            c.welcome = welcome; c.model?.removeAllActions()
            c.model?.eulerAngles = SCNVector3(-0.32, welcome ? -.pi / 2 : .pi / 2 + 0.38, 0)
            if welcome { c.model?.runAction(.repeatForever(.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 30)), forKey: "welcome") }
        }
        c.refresh()
    }
    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.registration?.invalidate(); coordinator.registration = nil
        view.isPlaying = false; view.scene?.rootNode.enumerateHierarchy { node, _ in node.removeAllActions() }; view.scene = nil
    }
    final class Coordinator: NSObject {
        weak var view: SCNView?
        weak var model: SCNNode?
        var registration: PoplurPerformanceRegistration?
        var welcome: Bool?; var awake = true; var granted = false; var dragging = false
        var back: (() -> Void)?
        private var startingAngle: Float = 0
        func refresh() { let active = granted && (awake || dragging); view?.scene?.isPaused = !active; view?.isPlaying = active && welcome == true; view?.setNeedsDisplay() }
        @objc func tap() { if welcome == false { back?() } }
        @objc func pan(_ gesture: UIPanGestureRecognizer) {
            guard let model else { return }
            if gesture.state == .began { dragging = true; startingAngle = model.presentation.eulerAngles.y; model.removeAllActions(); refresh() }
            model.eulerAngles.y = startingAngle + Float(gesture.translation(in: view).x) * 0.013
            if gesture.state == .ended || gesture.state == .cancelled {
                dragging = false
                if welcome == false { model.eulerAngles = SCNVector3(-0.32, .pi / 2 + 0.38, 0) }
                else { model.runAction(.repeatForever(.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 30)), forKey: "welcome") }
                refresh()
            }
            view?.setNeedsDisplay()
        }
    }
}

@MainActor
enum NativePreloginThumbnails {
    private static var cache: [String: UIImage] = [:]
    static func image(_ name: String) -> UIImage? {
        if let image = cache[name] { return image }
        guard let url = RuntimeGLBLoader.bundledURL(named: name, candidateSubdirectories: ["", "PreloginWeb/media", "ClayMapWeb", "Models", "SignupModels"]), let loaded = RuntimeGLBLoader.loadScene(from: url, label: "NativePreloginThumbnail") else { return nil }
        let scene = SCNScene(); let content = SCNNode()
        for node in loaded.rootNode.childNodes { content.addChildNode(node.clone()) }
        RuntimeGLBLoader.normalize(content, targetExtent: 1.55)
        content.eulerAngles = SCNVector3(-0.12, name == "zoom_buildings" ? -0.55 : 0.2, 0)
        scene.rootNode.addChildNode(content)
        let camera = SCNNode(); camera.camera = SCNCamera(); camera.camera?.fieldOfView = 35; camera.position = SCNVector3(0, 0, 3.2); scene.rootNode.addChildNode(camera)
        let light = SCNNode(); light.light = SCNLight(); light.light?.type = .ambient; light.light?.intensity = 520; scene.rootNode.addChildNode(light)
        let renderer = SCNRenderer(device: nil, options: nil); renderer.scene = scene; renderer.pointOfView = camera; renderer.autoenablesDefaultLighting = true
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 240, height: 240), antialiasingMode: .multisampling4X)
        renderer.scene = nil; cache[name] = image
        return image
    }
}

struct NativePreloginBackdrop: View {
    var color: Color
    var awake: Bool
    @State private var epoch = Date()
    var body: some View {
        ZStack {
            color
            Canvas { context, size in
                for x in stride(from: 5.0, to: size.width, by: 10) {
                    for y in stride(from: 5.0, to: size.height, by: 10) {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 3.2, height: 3.2)), with: .color(Color(red: 0.84, green: 0.06, blue: 0.42).opacity(0.38)))
                    }
                }
            }
            RadialGradient(colors: [.white.opacity(0.15), .clear, .black.opacity(0.23)], center: UnitPoint(x: 0.5, y: 0.4), startRadius: 10, endRadius: 550)
            TimelineView(.animation(minimumInterval: 1 / 24, paused: !awake)) { timeline in
                Canvas { context, size in
                    let seconds = timeline.date.timeIntervalSince(epoch)
                    let colors: [Color] = [.white, .yellow, .cyan, .pink, Color(red: 0.65, green: 1, blue: 0.3)]
                    for i in 0..<32 {
                        let x = (Double((i * 73 + 11) % 101) / 101) * size.width
                        let y = (Double(i * 37) + seconds * (14 + Double(i % 8))).truncatingRemainder(dividingBy: size.height + 25) - 15
                        var particle = context; particle.translateBy(x: x + sin(seconds + Double(i)) * 13, y: y)
                        particle.rotate(by: .radians(seconds * 0.4 + Double(i)))
                        particle.addFilter(.shadow(color: .black.opacity(0.18), radius: 1, x: 1, y: 2))
                        particle.fill(Path(roundedRect: CGRect(x: -4, y: -6, width: 8, height: 13), cornerRadius: 3), with: .color(colors[i % colors.count]))
                    }
                }
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
