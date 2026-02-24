import SwiftUI
import SceneKit
import CoreMotion

private let isRunningInPreviews: Bool = {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}()

private enum CubeFaceImageCache {
    private static var cache: [String: UIImage] = [:]
    static func image(for key: String, builder: () -> UIImage) -> UIImage {
        if let img = cache[key] { return img }
        let img = builder()
        cache[key] = img
        return img
    }
}

struct CubeTabView: View {
    @Binding var selectedTab: AppTab
    @Environment(\.renderingConfig) private var renderingConfig
    var tintColor: Color = .indigo
    @State private var rotationIndex: Int = 0
    var onSwipeUp: (() -> Void)? = nil
    var onCubeTap: (() -> Void)? = nil

    var body: some View {
        FloatingCube(selectedTab: $selectedTab, rotationIndex: $rotationIndex, tintColor: tintColor, onSwipeUp: onSwipeUp, onCubeTap: onCubeTap)
            .frame(height: 200)
            .background(.clear)
            .accessibilityHidden(true)
            .onAppear { print("[CubeTabView] Appeared (forced 3D)") }
    }
}

private struct FloatingCube: View {
    @Binding var selectedTab: AppTab
    @Binding var rotationIndex: Int
    var tintColor: Color
    var onSwipeUp: (() -> Void)?
    var onCubeTap: (() -> Void)?

    @State private var bob: CGFloat = 0
    @State private var tilt: Double = 0

    var body: some View {
        CubeSceneView(selectedTab: $selectedTab, rotationIndex: $rotationIndex, tintColor: tintColor, parentSwipeUpHandler: onSwipeUp, parentCubeTapHandler: onCubeTap)
    }
}

private struct CubeSceneView: UIViewRepresentable {
    @Binding var selectedTab: AppTab
    @Binding var rotationIndex: Int
    var tintColor: Color
    var parentSwipeUpHandler: (() -> Void)? = nil
    var parentCubeTapHandler: (() -> Void)? = nil

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = false
        // Fast first frame: empty scene, no AA, lower FPS
        scnView.scene = SCNScene()
        scnView.isPlaying = true
        scnView.preferredFramesPerSecond = 30
        scnView.antialiasingMode = .multisampling4X
        // Defer full scene build and higher quality to next runloop
        DispatchQueue.main.async { [weak scnView] in
            guard let v = scnView else { return }
            v.scene = makeScene()
            v.preferredFramesPerSecond = 60
            // Removed: v.antialiasingMode = .multisampling4X
        }

        // Remove border to reduce compositing cost on launch
        scnView.layer.borderWidth = 0

        // Gestures: pan for left/right (more sensitive), swipe up for action
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let swipeUp = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        swipeUp.direction = .up
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.25

        // Set delegates
        pan.delegate = context.coordinator
        swipeUp.delegate = context.coordinator
        tap.delegate = context.coordinator
        longPress.delegate = context.coordinator

        // Prefer long-press for stationary holds: tap should wait for long-press to fail
        tap.require(toFail: longPress)
        // Pan should wait for long-press unless movement triggers pan first
        pan.require(toFail: longPress)

        scnView.addGestureRecognizer(pan)
        scnView.addGestureRecognizer(swipeUp)
        scnView.addGestureRecognizer(tap)
        scnView.addGestureRecognizer(longPress)

        context.coordinator.view = scnView
        context.coordinator.syncToSelectedTab(selectedTab)

        if selectedTab != .feed {
            NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
        }
        if selectedTab == .record {
            NotificationCenter.default.post(name: Notification.Name("RecordTabBecameActive"), object: nil)
        }

        // Observe motion updates to rotate cube based on device attitude
        if !isRunningInPreviews {
            context.coordinator.startObservingMotion()
        }

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.syncToSelectedTab(selectedTab)
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(self)
        coordinator.onSwipeUp = parentSwipeUpHandler
        coordinator.onCubeTap = parentCubeTapHandler
        return coordinator
    }

    // MARK: - Scene
    private func makeScene() -> SCNScene {
        let scene = SCNScene()

        // Enable environment lighting for reflections if an environment image is present
        if let env = UIImage(named: "CubeEnv") {
            scene.lightingEnvironment.contents = env
            scene.lightingEnvironment.intensity = 0.0
        } else {
            scene.lightingEnvironment.intensity = 0.0
        }

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 3.7) // move even closer to enlarge cube further
        cameraNode.camera?.fieldOfView = 50
        cameraNode.camera?.zFar = 100
        scene.rootNode.addChildNode(cameraNode)

        // Removed key directional light and fill omni light as per instructions

        // Lean cube geometry with small chamfer (lower tessellation)
        let box = SCNBox(width: 1.3, height: 1.3, length: 1.3, chamferRadius: 0.25)
        box.chamferSegmentCount = 8
        let node = SCNNode(geometry: box)
        node.name = "cube"
        scene.rootNode.addChildNode(node)

        box.materials = makeMaterials()

        return scene
    }

    private func uiColor(_ c: Color) -> UIColor { UIColor(c) }

    private func makeMaterials() -> [SCNMaterial] {
        // Map faces to tabs in order: +X, -X, +Y, -Y, +Z, -Z
        let tabs: [AppTab] = [.map, .record, .feed, .profile]
        var faces: [AppTab] = tabs
        faces.append(tabs.first!)

        return faces.map { tab in
            let mat = SCNMaterial()
            // Face content
            mat.diffuse.contents = faceImage(for: tab)
            mat.multiply.contents = uiColor(tintColor)
            mat.diffuse.intensity = 0.95
            mat.multiply.intensity = 1.0
            // Normal map if available
            if let normal = UIImage(named: "CubeNormalMap") {
                mat.normal.contents = normal
                mat.normal.intensity = 0.7
            }
            // Simplify lighting model and neutralize PBR params
            mat.lightingModel = .constant
            mat.metalness.contents = 0.0
            mat.roughness.contents = 1.0
            mat.emission.contents = UIColor.clear
            mat.emission.intensity = 0.0
            mat.isDoubleSided = true
            mat.locksAmbientWithDiffuse = true
            return mat
        }
    }

    private func faceImage(for tab: AppTab) -> UIImage {
        let key = "face_v2_\(tab.title)"
        return CubeFaceImageCache.image(for: key) {
            let size = CGSize(width: 300, height: 300)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                let rect = CGRect(origin: .zero, size: size)
                UIColor(white: 0.95, alpha: 1).setFill()
                UIBezierPath(roundedRect: rect.insetBy(dx: 8, dy: 8), cornerRadius: 24).fill()

                // Icon
                let symbolName = tab.systemImage
                let pointSize: CGFloat = 80
                let iconWidth: CGFloat = 90
                let iconHeight: CGFloat = 90
                let iconY: CGFloat = 70
                let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
                let image = UIImage(systemName: symbolName, withConfiguration: config) ?? UIImage()
                let imgRect = CGRect(x: (size.width - iconWidth) / 2, y: iconY, width: iconWidth, height: iconHeight)
                image.withTintColor(.black, renderingMode: .alwaysOriginal).draw(in: imgRect)

                // Title
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .heavy),
                    .foregroundColor: UIColor.black,
                    .paragraphStyle: paragraph
                ]
                let title = tab.title as NSString
                let titleRect = CGRect(x: 0, y: 180, width: size.width, height: 40)
                title.draw(in: titleRect, withAttributes: attrs)
            }
        }
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CubeSceneView
        weak var view: SCNView?
        private var currentIndex: Int = 0
        private let tabs: [AppTab] = [.map, .record, .feed, .profile]
        var onSwipeUp: (() -> Void)?
        var onCubeTap: (() -> Void)?
        var parentSwipeUpHandler: (() -> Void)?

        private var panStartPoint: CGPoint = .zero
        private var panAccumulated: CGFloat = 0
        private let panThreshold: CGFloat = 10 // lower threshold for sensitivity
        private let haptic = UIImpactFeedbackGenerator(style: .light)

        private var motionObserver: NSObjectProtocol?
        private var liveRotation: SCNVector3 = SCNVector3Zero

        private var holdObservers: [NSObjectProtocol] = []
        private var isBlinking: Bool = false

        // Added helper functions as per instructions
        private func deg2rad(_ degrees: Float) -> Float { degrees * .pi / 180 }
        private func clamp(_ value: Float, min minVal: Float, max maxVal: Float) -> Float { max(minVal, min(maxVal, value)) }

        init(_ parent: CubeSceneView) {
            self.parent = parent
            super.init()
            startObservingHold()
        }

        deinit {
            stopObservingMotion()
            stopObservingHold()
        }

        @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
            guard let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }

            if gesture.direction == .up {
                let flip = SCNAction.rotateBy(x: CGFloat.pi, y: 0, z: 0, duration: 0.28)
                flip.timingMode = .easeInEaseOut
                cube.runAction(flip)
                if parent.selectedTab == .record {
                    onSwipeUp?()
                }
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            onCubeTap?()
            if parent.selectedTab == .record {
                print("[CubeTabView] Tap -> post cubeTabViewTapped (record tab)")
                NotificationCenter.default.post(name: .cameraCubeTabViewTapped, object: nil)
            } else {
                print("[CubeTabView] Tap ignored for tab: \(parent.selectedTab)")
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                print("[CubeTabView] Long press began -> .cubeHoldBegan")
                NotificationCenter.default.post(name: .cameraCubeHoldBegan, object: nil)
            case .ended, .cancelled, .failed:
                print("[CubeTabView] Long press ended -> .cubeHoldEnded")
                NotificationCenter.default.post(name: .cameraCubeHoldEnded, object: nil)
            default:
                break
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            let translation = gesture.translation(in: scnView)

            switch gesture.state {
            case .began:
                panStartPoint = translation
                panAccumulated = 0
            case .changed:
                // Accumulate horizontal movement
                let deltaX = translation.x - panStartPoint.x
                panAccumulated += deltaX
                panStartPoint = translation

                // Clear liveRotation to avoid fighting motion tilt during pan
                self.liveRotation = SCNVector3Zero

                // Keep face flat during drag; do not expose adjacent faces
                let baseY = Float(currentIndex) * (-Float.pi / 2)
                cube.eulerAngles = SCNVector3(0, baseY, 0)

            case .ended, .cancelled, .failed:
                // Decide if we switch faces
                if panAccumulated <= -panThreshold {
                    currentIndex = (currentIndex + 1) % tabs.count
                    rotateCube(cube, to: currentIndex, animated: true, bouncy: true)
                    parent.selectedTab = tabs[currentIndex]
                    haptic.impactOccurred(intensity: 0.8)

                    let newTab = tabs[currentIndex]
                    if newTab != .feed {
                        NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                    }
                    if newTab == .record {
                        NotificationCenter.default.post(name: Notification.Name("RecordTabBecameActive"), object: nil)
                    }
                } else if panAccumulated >= panThreshold {
                    currentIndex = (currentIndex - 1 + tabs.count) % tabs.count
                    rotateCube(cube, to: currentIndex, animated: true, bouncy: true)
                    parent.selectedTab = tabs[currentIndex]
                    haptic.impactOccurred(intensity: 0.8)

                    let newTab = tabs[currentIndex]
                    if newTab != .feed {
                        NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                    }
                    if newTab == .record {
                        NotificationCenter.default.post(name: Notification.Name("RecordTabBecameActive"), object: nil)
                    }
                } else {
                    // Snap back to current face if below threshold
                    rotateCube(cube, to: currentIndex, animated: true, bouncy: true)

                    let newTab = tabs[currentIndex]
                    if newTab != .feed {
                        NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                    }
                    if newTab == .record {
                        NotificationCenter.default.post(name: Notification.Name("RecordTabBecameActive"), object: nil)
                    }
                }
                // Reset live tilt and reapply combined rotation
                cube.eulerAngles.y = Float(currentIndex) * (-Float.pi / 2)
                self.liveRotation = SCNVector3Zero
                self.applyCombinedRotation(to: cube)
            default:
                break
            }
        }

        func syncToSelectedTab(_ tab: AppTab) {
            guard let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            if let idx = tabs.firstIndex(of: tab), idx != currentIndex {
                currentIndex = idx
                rotateCube(cube, to: currentIndex, animated: true)
                applyCombinedRotation(to: cube)

                if tab != .feed {
                    NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                }
                if tab == .record {
                    NotificationCenter.default.post(name: Notification.Name("RecordTabBecameActive"), object: nil)
                }
            }
        }

        private func rotateCube(_ node: SCNNode, to index: Int, animated: Bool = true, bouncy: Bool = false) {
            let baseAngle = Float(index) * (-Float.pi / 2)
            if !animated {
                node.eulerAngles.y = baseAngle
                return
            }
            if bouncy {
                // Overshoot then settle
                let overshoot: Float = 0.12
                let target1 = SCNAction.rotateTo(x: 0, y: CGFloat(baseAngle + overshoot), z: 0, duration: 0.18, usesShortestUnitArc: true)
                target1.timingMode = .easeInEaseOut
                let target2 = SCNAction.rotateTo(x: 0, y: CGFloat(baseAngle), z: 0, duration: 0.22, usesShortestUnitArc: true)
                target2.timingMode = .easeInEaseOut
                let seq = SCNAction.sequence([target1, target2])
                node.runAction(seq) { [weak self] in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.applyCombinedRotation(to: node)
                    }
                }
            } else {
                let action = SCNAction.rotateTo(x: 0, y: CGFloat(baseAngle), z: 0, duration: 0.28, usesShortestUnitArc: true)
                action.timingMode = .easeInEaseOut
                node.runAction(action) { [weak self] in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.applyCombinedRotation(to: node)
                    }
                }
            }
        }

        func startObservingMotion() {
            stopObservingMotion()
            motionObserver = NotificationCenter.default.addObserver(forName: Notification.Name("CubeMotionUpdate"), object: nil, queue: .main) { [weak self] notif in
                guard let self,
                      let scnView = self.view,
                      let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }

                // Map to a single horizontal component for side-to-side sway only
                // Use device roll (left-right tilt) to drive horizontal sway; adjust sign if needed
                let horizontal = Float((notif.userInfo?["roll"] as? Double) ?? 0)
                let horizontalScaled = horizontal * 0.5

                // Optional: map pitch to a tiny vertical bobbing influence
                let pitch = Float((notif.userInfo?["pitch"] as? Double) ?? 0)
                let pitchScaled = max(-0.5, min(0.5, pitch))
                let bobInfluence = sin(pitchScaled) * 0.02

                // Clamp raw horizontal to keep within reasonable bounds
                let maxTiltRad: Float = deg2rad(60)
                let clampedH = clamp(horizontalScaled, min: -maxTiltRad, max: maxTiltRad)

                // Only store Y component and tiny Z for bob; zero X to prevent up/down tilt
                self.liveRotation = SCNVector3(0, clampedH, bobInfluence)

                self.applyCombinedRotation(to: cube)
            }
        }

        func stopObservingMotion() {
            if let token = motionObserver {
                NotificationCenter.default.removeObserver(token)
                motionObserver = nil
            }
        }

        private func startObservingHold() {
            stopObservingHold()
            let began = NotificationCenter.default.addObserver(forName: .cameraCubeHoldBegan, object: nil, queue: .main) { [weak self] _ in
                self?.beginBlink()
            }
            let ended = NotificationCenter.default.addObserver(forName: .cameraCubeHoldEnded, object: nil, queue: .main) { [weak self] _ in
                self?.endBlink()
            }
            holdObservers = [began, ended]
        }

        private func stopObservingHold() {
            holdObservers.forEach { NotificationCenter.default.removeObserver($0) }
            holdObservers.removeAll()
        }

        private func beginBlink() {
            guard !isBlinking, let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            isBlinking = true
            let fadeDown = SCNAction.fadeOpacity(to: 0.4, duration: 0.35)
            let fadeUp = SCNAction.fadeOpacity(to: 1.0, duration: 0.35)
            let pulse = SCNAction.repeatForever(SCNAction.sequence([fadeDown, fadeUp]))
            cube.runAction(pulse, forKey: "recordBlink")
        }

        private func endBlink() {
            guard isBlinking, let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            isBlinking = false
            cube.removeAction(forKey: "recordBlink")
            cube.opacity = 1.0
        }

        private func applyCombinedRotation(to node: SCNNode) {
            // Base rotation from current index (y-axis steps of 90 degrees)
            let baseY = Float(currentIndex) * (-Float.pi / 2)

            // We only sway side-to-side: ignore X and Z for rotation, but use Z for slight tilt
            let yAdditiveScale: Float = 0.2
            let maxYAddDeg: Float = 6
            let maxYAdd = deg2rad(maxYAddDeg)

            var yAdd = liveRotation.y * yAdditiveScale
            yAdd = clamp(yAdd, min: -maxYAdd, max: maxYAdd)

            let zAdditiveScale: Float = 0.15
            let maxZAdd: Float = deg2rad(3)
            var zAdd = liveRotation.z * zAdditiveScale
            zAdd = clamp(zAdd, min: -maxZAdd, max: maxZAdd)

            let y = baseY + yAdd
            node.eulerAngles = SCNVector3(0 + zAdd, y, 0)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Allow swipeUp simultaneously; others are controlled via failure requirements
            if gestureRecognizer is UISwipeGestureRecognizer || otherGestureRecognizer is UISwipeGestureRecognizer {
                return true
            }
            return false
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            // If long-press already began, prevent pan/tap from starting
            if let lp = gestureRecognizer.view?.gestureRecognizers?.first(where: { $0 is UILongPressGestureRecognizer }) as? UILongPressGestureRecognizer {
                if lp.state == .began || lp.state == .changed { return false }
            }
            return true
        }
    }
}

#Preview("Cube Properties") {
    CubeOnlyPreview()
}

private struct CubeOnlyPreview: View {
    @State private var tab: AppTab = .map
    @State private var cubeHeight: CGFloat = 200
    @State private var tint: Color = .indigo

    var body: some View {
        VStack(spacing: 12) {
            // Controls
            VStack(alignment: .leading, spacing: 10) {
                Text("Cube Controls").font(.headline)
                HStack {
                    Text("Height \(Int(cubeHeight))")
                    Slider(value: $cubeHeight, in: 140...280)
                }
                HStack {
                    ColorPicker("Tint", selection: $tint)
                }
                Picker("Selected Tab", selection: $tab) {
                    Text("Map").tag(AppTab.map)
                    Text("Record").tag(AppTab.record)
                    Text("Feed").tag(AppTab.feed)
                    Text("Profile").tag(AppTab.profile)
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Cube under test
            ZStack {
                Color(UIColor.systemBackground)
                CubeTabView(selectedTab: $tab, tintColor: tint)
                    .frame(height: cubeHeight)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 6)
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
    }
}
