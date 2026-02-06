import SwiftUI
import SceneKit
import CoreMotion

struct CubeTabView: View {
    @Binding var selectedTab: AppTab
    @State private var rotationIndex: Int = 0
    var onSwipeUp: (() -> Void)? = nil
    var onCubeTap: (() -> Void)? = nil

    var body: some View {
        FloatingCube(selectedTab: $selectedTab, rotationIndex: $rotationIndex, onSwipeUp: onSwipeUp, onCubeTap: onCubeTap)
            .frame(height: 200)
            .background(.clear)
            .accessibilityHidden(true)
    }
}

private struct FloatingCube: View {
    @Binding var selectedTab: AppTab
    @Binding var rotationIndex: Int
    var onSwipeUp: (() -> Void)?
    var onCubeTap: (() -> Void)?

    @State private var bob: CGFloat = 0
    @State private var tilt: Double = 0

    var body: some View {
        CubeSceneView(selectedTab: $selectedTab, rotationIndex: $rotationIndex, parentSwipeUpHandler: onSwipeUp, parentCubeTapHandler: onCubeTap)
            .offset(y: bob)
            .rotationEffect(.degrees(tilt))
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    bob = -12
                }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    tilt = 5
                }
            }
    }
}

private struct CubeSceneView: UIViewRepresentable {
    @Binding var selectedTab: AppTab
    @Binding var rotationIndex: Int
    var parentSwipeUpHandler: (() -> Void)? = nil
    var parentCubeTapHandler: (() -> Void)? = nil

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.allowsCameraControl = false
        scnView.scene = makeScene()
        scnView.isPlaying = true
        scnView.antialiasingMode = .multisampling4X

        // Gestures: pan for left/right (more sensitive), swipe up for action
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let swipeUp = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        swipeUp.direction = .up
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))

        scnView.addGestureRecognizer(pan)
        scnView.addGestureRecognizer(swipeUp)
        scnView.addGestureRecognizer(tap)

        context.coordinator.view = scnView
        context.coordinator.syncToSelectedTab(selectedTab)

        // Observe motion updates to rotate cube based on device attitude
        context.coordinator.startObservingMotion()

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

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 5.0)
        cameraNode.camera?.zFar = 100
        scene.rootNode.addChildNode(cameraNode)

        // Light
        let light = SCNLight()
        light.type = .omni
        light.intensity = 800
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position = SCNVector3(8, 8, 10)
        scene.rootNode.addChildNode(lightNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 300
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Cube with different materials for each face
        let box = SCNBox(width: 2.2, height: 2.2, length: 2.2, chamferRadius: 0.18)
        let node = SCNNode(geometry: box)
        node.name = "cube"
        scene.rootNode.addChildNode(node)

        box.materials = makeMaterials()

        return scene
    }

    private func makeMaterials() -> [SCNMaterial] {
        // Map faces to tabs in order: +X, -X, +Y, -Y, +Z, -Z
        // We'll use 5 faces for the 5 tabs; the extra face repeats the first.
        let tabs: [AppTab] = [.map, .record, .feed, .profile]
        var faces: [AppTab] = tabs
        faces.append(tabs.first!)

        return faces.map { tab in
            let mat = SCNMaterial()
            mat.diffuse.contents = faceImage(for: tab)
            mat.locksAmbientWithDiffuse = true
            mat.isDoubleSided = true
            return mat
        }
    }

    private func faceImage(for tab: AppTab) -> UIImage {
        // Render a small UIKit view with SF Symbol and label to a UIImage
        let size = CGSize(width: 300, height: 300)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            UIColor.white.setFill()
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
            title.draw(in: CGRect(x: 0, y: 180, width: size.width, height: 40), withAttributes: attrs)
        }
    }

    // MARK: - Coordinator
    class Coordinator: NSObject {
        var parent: CubeSceneView
        weak var view: SCNView?
        private var currentIndex: Int = 0
        private let tabs: [AppTab] = [.map, .record, .feed, .profile]
        var onSwipeUp: (() -> Void)?
        var onCubeTap: (() -> Void)?
        var parentSwipeUpHandler: (() -> Void)?

        private var panStartPoint: CGPoint = .zero
        private var panAccumulated: CGFloat = 0
        private let panThreshold: CGFloat = 18 // lower threshold for sensitivity
        private let haptic = UIImpactFeedbackGenerator(style: .light)

        private var motionObserver: NSObjectProtocol?
        private var liveRotation: SCNVector3 = SCNVector3Zero

        // Added helper functions as per instructions
        private func deg2rad(_ degrees: Float) -> Float { degrees * .pi / 180 }
        private func clamp(_ value: Float, min minVal: Float, max maxVal: Float) -> Float { max(minVal, min(maxVal, value)) }

        init(_ parent: CubeSceneView) { self.parent = parent }

        deinit { stopObservingMotion() }

        @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
            guard let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }

            if gesture.direction == .up {
                let flip = SCNAction.rotateBy(x: CGFloat.pi, y: 0, z: 0, duration: 0.28)
                flip.timingMode = .easeInEaseOut
                cube.runAction(flip)
                onSwipeUp?()
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            onCubeTap?()
            NotificationCenter.default.post(name: Notification.Name("CubeTabViewTappedNotification"), object: nil)
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

                // Optionally, apply a tiny live rotation for responsiveness
                let liveAngle = Float(panAccumulated / 380) // small preview tilt
                let baseY = Float(currentIndex) * (-Float.pi / 2)
                cube.eulerAngles = SCNVector3(0, baseY + liveAngle, 0)

            case .ended, .cancelled, .failed:
                // Decide if we switch faces
                if panAccumulated <= -panThreshold {
                    currentIndex = (currentIndex + 1) % tabs.count
                    rotateCube(cube, to: currentIndex, animated: true, bouncy: true)
                    parent.selectedTab = tabs[currentIndex]
                    haptic.impactOccurred(intensity: 0.8)
                } else if panAccumulated >= panThreshold {
                    currentIndex = (currentIndex - 1 + tabs.count) % tabs.count
                    rotateCube(cube, to: currentIndex, animated: true, bouncy: true)
                    parent.selectedTab = tabs[currentIndex]
                    haptic.impactOccurred(intensity: 0.8)
                } else {
                    // Snap back to current face if below threshold
                    rotateCube(cube, to: currentIndex, animated: true, bouncy: true)
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

                // Clamp raw horizontal to keep within reasonable bounds
                let maxTiltRad: Float = deg2rad(60)
                let clampedH = clamp(horizontal, min: -maxTiltRad, max: maxTiltRad)

                // Only store Y component; zero X/Z to prevent up/down tilt
                self.liveRotation = SCNVector3(0, clampedH, 0)

                self.applyCombinedRotation(to: cube)
            }
        }

        func stopObservingMotion() {
            if let token = motionObserver {
                NotificationCenter.default.removeObserver(token)
                motionObserver = nil
            }
        }

        private func applyCombinedRotation(to node: SCNNode) {
            // Base rotation from current index (y-axis steps of 90 degrees)
            let baseY = Float(currentIndex) * (-Float.pi / 2)

            // We only sway side-to-side: ignore X and Z
            let yAdditiveScale: Float = 0.7
            let maxYAddDeg: Float = 38
            let maxYAdd = deg2rad(maxYAddDeg)

            var yAdd = liveRotation.y * yAdditiveScale
            yAdd = clamp(yAdd, min: -maxYAdd, max: maxYAdd)

            let y = baseY + yAdd
            node.eulerAngles = SCNVector3(0, y, 0)
        }
    }
}

#Preview {
    StatefulPreview()
}

private struct StatefulPreview: View {
    @State private var tab: AppTab = .map
    var body: some View {
        VStack {
            Spacer()
            Text("Selected: \(tab.title)")
            CubeTabView(selectedTab: $tab)
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

