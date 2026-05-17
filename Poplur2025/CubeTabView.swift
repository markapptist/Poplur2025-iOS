import SwiftUI
import SceneKit
import CoreMotion
import AVFoundation

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
    @Binding var previewHover: Bool
    @Binding var previewPopTrigger: Int
    @Binding var previewPopSoundEnabled: Bool
    @Binding var previewYawRightStep: Int
    @Binding var previewYawLeftStep: Int
    @Binding var previewHoldActive: Bool
    @Environment(\.renderingConfig) private var renderingConfig
    var tintColor: Color = .indigo
    var baseColor: Color = Color(white: 0.2)
    var glowColor: Color = .orange
    var glowOpacity: CGFloat = 0.8
    var useNormalMap: Bool = true
    var lightingModel: SCNMaterial.LightingModel = .constant
    var rotationSpeedMultiplier: Double = 1.0 // >1.0 = slower, <1.0 = faster
    var enablePreviewSpin: Bool = true
    var enableGlow: Bool = true
    @State private var rotationIndex: Int = 0
    var onSwipeUp: (() -> Void)? = nil
    var onCubeTap: (() -> Void)? = nil

    init(selectedTab: Binding<AppTab>,
         previewHover: Binding<Bool> = .constant(false),
         previewPopTrigger: Binding<Int> = .constant(0),
         previewPopSoundEnabled: Binding<Bool> = .constant(false),
         previewYawRightStep: Binding<Int> = .constant(0),
         previewYawLeftStep: Binding<Int> = .constant(0),
         previewHoldActive: Binding<Bool> = .constant(false),
         tintColor: Color = .indigo,
         baseColor: Color = Color(white: 0.2),
         glowColor: Color = .orange,
         glowOpacity: CGFloat = 0.8,
         useNormalMap: Bool = true,
         lightingModel: SCNMaterial.LightingModel = .constant,
         rotationSpeedMultiplier: Double = 1.0,
         enablePreviewSpin: Bool = true,
         enableGlow: Bool = true,
         onSwipeUp: (() -> Void)? = nil,
         onCubeTap: (() -> Void)? = nil) {
        self._selectedTab = selectedTab
        self._previewHover = previewHover
        self._previewPopTrigger = previewPopTrigger
        self._previewPopSoundEnabled = previewPopSoundEnabled
        self._previewYawRightStep = previewYawRightStep
        self._previewYawLeftStep = previewYawLeftStep
        self._previewHoldActive = previewHoldActive
        self.tintColor = tintColor
        self.baseColor = baseColor
        self.glowColor = glowColor
        self.glowOpacity = glowOpacity
        self.useNormalMap = useNormalMap
        self.lightingModel = lightingModel
        self.rotationSpeedMultiplier = rotationSpeedMultiplier
        self.enablePreviewSpin = enablePreviewSpin
        self.enableGlow = enableGlow
        self.onSwipeUp = onSwipeUp
        self.onCubeTap = onCubeTap
    }

    var body: some View {
        FloatingCube(
            selectedTab: $selectedTab,
            rotationIndex: $rotationIndex,
            previewHover: $previewHover,
            previewPopTrigger: $previewPopTrigger,
            previewPopSoundEnabled: $previewPopSoundEnabled,
            previewYawRightStep: $previewYawRightStep,
            previewYawLeftStep: $previewYawLeftStep,
            previewHoldActive: $previewHoldActive,
            tintColor: tintColor,
            glowColor: glowColor,
            glowOpacity: glowOpacity,
            useNormalMap: useNormalMap,
            lightingModel: lightingModel,
            rotationSpeedMultiplier: rotationSpeedMultiplier,
            onSwipeUp: onSwipeUp,
            onCubeTap: onCubeTap,
            baseColor: baseColor,
            enablePreviewSpin: enablePreviewSpin,
            enableGlow: enableGlow
        )
        .frame(height: 200)
        .aspectRatio(1, contentMode: .fit)
        .background(.clear)
        .accessibilityHidden(true)
        .onAppear {
            print("[CubeTabView] Appeared (forced 3D)")
            #if DEBUG
            if !isRunningInPreviews {
                do {
                    try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
                    try AVAudioSession.sharedInstance().setActive(true)
                    print("[CubeTabView] AVAudioSession activated")
                } catch {
                    print("[CubeTabView] AVAudioSession activation failed: \(error)")
                }
            } else {
                print("[CubeTabView] Skipping AVAudioSession setup in previews")
            }
            #endif
        }
    }
}

private struct FloatingCube: View {
    @Binding var selectedTab: AppTab
    @Binding var rotationIndex: Int
    @Binding var previewHover: Bool
    @Binding var previewPopTrigger: Int
    @Binding var previewPopSoundEnabled: Bool
    @Binding var previewYawRightStep: Int
    @Binding var previewYawLeftStep: Int
    @Binding var previewHoldActive: Bool
    var tintColor: Color
    var glowColor: Color
    var glowOpacity: CGFloat
    var useNormalMap: Bool
    var lightingModel: SCNMaterial.LightingModel
    var rotationSpeedMultiplier: Double
    var onSwipeUp: (() -> Void)?
    var onCubeTap: (() -> Void)?
    var baseColor: Color
    var enablePreviewSpin: Bool
    var enableGlow: Bool

    @State private var bob: CGFloat = 0
    @State private var tilt: Double = 0

    var body: some View {
        CubeSceneView(
            selectedTab: $selectedTab,
            rotationIndex: $rotationIndex,
            previewHover: $previewHover,
            previewPopTrigger: $previewPopTrigger,
            previewPopSoundEnabled: $previewPopSoundEnabled,
            previewYawRightStep: $previewYawRightStep,
            previewYawLeftStep: $previewYawLeftStep,
            previewHoldActive: $previewHoldActive,
            tintColor: tintColor,
            glowColor: glowColor,
            glowOpacity: glowOpacity,
            baseColor: baseColor,
            useNormalMap: useNormalMap,
            lightingModel: lightingModel,
            rotationSpeedMultiplier: rotationSpeedMultiplier,
            parentSwipeUpHandler: onSwipeUp,
            parentCubeTapHandler: onCubeTap,
            enablePreviewSpin: enablePreviewSpin,
            enableGlow: enableGlow
        )
    }
}

private struct CubeSceneView: UIViewRepresentable {
    @Binding var selectedTab: AppTab
    @Binding var rotationIndex: Int
    @Binding var previewHover: Bool
    @Binding var previewPopTrigger: Int
    @Binding var previewPopSoundEnabled: Bool
    @Binding var previewYawRightStep: Int
    @Binding var previewYawLeftStep: Int
    @Binding var previewHoldActive: Bool
    var tintColor: Color
    var glowColor: Color
    var glowOpacity: CGFloat
    var baseColor: Color
    var useNormalMap: Bool
    var lightingModel: SCNMaterial.LightingModel
    var rotationSpeedMultiplier: Double
    var parentSwipeUpHandler: (() -> Void)? = nil
    var parentCubeTapHandler: (() -> Void)? = nil
    var enablePreviewSpin: Bool
    var enableGlow: Bool

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        // Removed: scnView.autoenablesDefaultLighting = false
        // Removed: scnView.rendersContinuously = true
        scnView.allowsCameraControl = false
        // Fast first frame: empty scene, no AA, lower FPS
        scnView.scene = SCNScene()
        scnView.isPlaying = true
        scnView.preferredFramesPerSecond = 60
        scnView.antialiasingMode = .multisampling4X
        // Defer full scene build and higher quality to next runloop
        DispatchQueue.main.async { [weak scnView] in
            guard let v = scnView else { return }
            v.scene = makeScene()
            v.preferredFramesPerSecond = 120
            // Removed: v.antialiasingMode = .multisampling4X

            if let cube = v.scene?.rootNode.childNode(withName: "cube", recursively: true), let box = cube.geometry as? SCNBox {
                context.coordinator.cubeMaterials = box.materials
            }
            // Defer normal map and glow attachment one more pass in previews
            if isRunningInPreviews {
                DispatchQueue.main.async {
                    if let cube = v.scene?.rootNode.childNode(withName: "cube", recursively: true), let box = cube.geometry as? SCNBox {
                        // Apply normal maps now if enabled
                        if self.useNormalMap, let normal = UIImage(named: "CubeNormalMap") {
                            for m in context.coordinator.cubeMaterials {
                                m.normal.contents = normal
                                m.normal.intensity = 2.0
                            }
                        }
                        // Attach or update glow now
                        if self.enableGlow {
                            self.attachOrUpdateGlow(to: cube)
                        }
                    }
                }
            }
        }

        // Remove border to reduce compositing cost on launch
        scnView.layer.borderWidth = 0

        // Gestures: pan for left/right (more sensitive), swipe up for action
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let swipeUp = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        swipeUp.direction = .up
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5 // 0.5 seconds for timeline/general interactions (recording countdown handles the 2s delay)

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
        
        if isRunningInPreviews {
            let lp = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePreviewLongPress(_:)))
            lp.minimumPressDuration = 0.25
            scnView.addGestureRecognizer(lp)
        }

        context.coordinator.view = scnView
        context.coordinator.syncToSelectedTab(selectedTab)
        context.coordinator.setInitialYaw(for: selectedTab)

        // Apply initial preview hover state and pop/yaw triggers
        context.coordinator.applyPreviewHover(previewHover)
        context.coordinator.lastPopTrigger = previewPopTrigger
        context.coordinator.lastYawRightStep = previewYawRightStep
        context.coordinator.lastYawLeftStep = previewYawLeftStep
        
        if isRunningInPreviews {
            context.coordinator.startAccelerometerSimulation()
        }

        if selectedTab != .feed {
            NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
        }
        if selectedTab == .record {
            NotificationCenter.default.post(name: Notification.Name("RecordTabBecameActive"), object: nil)
        }

        // Observe motion updates to rotate cube based on device attitude
        context.coordinator.startObservingMotion()

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        // Keep tab state in sync
        context.coordinator.syncToSelectedTab(selectedTab)

        // Propagate live tint updates to materials so previews reflect changes immediately
        if let cube = uiView.scene?.rootNode.childNode(withName: "cube", recursively: true),
           let box = cube.geometry as? SCNBox {
            let uiTint = UIColor(tintColor)
            let tabFaces: [AppTab] = [
                .map, .record, .feed, .profile, .map, .record
            ]
            let mats = context.coordinator.cubeMaterials.isEmpty ? box.materials : context.coordinator.cubeMaterials
            for (i, mat) in mats.enumerated() where i < tabFaces.count {
                let tab = tabFaces[i]
                mat.diffuse.contents = faceBackgroundOnly(for: tab, baseColor: baseColor)
                mat.multiply.contents = uiTint
                if useNormalMap, let normal = UIImage(named: "CubeNormalMap") {
                    mat.normal.contents = normal
                    mat.normal.intensity = isRunningInPreviews ? 2.0 : 0.6
                } else {
                    mat.normal.contents = nil
                }
            }
            // If we used cached materials, ensure the box still points to them (only once). Avoid resetting each frame.
            if context.coordinator.cubeMaterials.isEmpty == false {
                box.materials = context.coordinator.cubeMaterials
            }
            // Nudge SceneKit to redraw this frame
            uiView.sceneTime = uiView.sceneTime
        }

        if isRunningInPreviews {
            context.coordinator.startAccelerometerSimulation()
        }

        // Manage preview hover animation state
        context.coordinator.applyPreviewHover(previewHover)

        // Manage preview pop trigger
        if context.coordinator.lastPopTrigger != previewPopTrigger {
            context.coordinator.lastPopTrigger = previewPopTrigger
            context.coordinator.triggerPreviewPop()
        }

        // Manage preview yaw right step
        if context.coordinator.lastYawRightStep != previewYawRightStep {
            let diff = previewYawRightStep - context.coordinator.lastYawRightStep
            context.coordinator.lastYawRightStep = previewYawRightStep
            context.coordinator.applyYaw(steps: diff, direction: .right)
        }
        // Manage preview yaw left step
        if context.coordinator.lastYawLeftStep != previewYawLeftStep {
            let diff = previewYawLeftStep - context.coordinator.lastYawLeftStep
            context.coordinator.lastYawLeftStep = previewYawLeftStep
            context.coordinator.applyYaw(steps: diff, direction: .left)
        }

        // Manage preview spin action when toggle changes
        if isRunningInPreviews,
           let cube = uiView.scene?.rootNode.childNode(withName: "cube", recursively: true) {
            let isSpinning = cube.action(forKey: "previewSpin") != nil
            if enablePreviewSpin && !isSpinning && !context.coordinator.isSpinSuspended {
                let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 8.0))
                spin.timingMode = .linear
                cube.runAction(spin, forKey: "previewSpin")
            } else if !enablePreviewSpin && isSpinning {
                cube.removeAction(forKey: "previewSpin")
            }
        }

        // Update glow particle appearance each frame so color/opacity changes apply live
        if let cube = uiView.scene?.rootNode.childNode(withName: "cube", recursively: true) {
            if enableGlow {
                attachOrUpdateGlow(to: cube)
            } else if let glowNode = cube.childNode(withName: "cubeGlow", recursively: false) {
                glowNode.removeFromParentNode()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(self)
        coordinator.onSwipeUp = parentSwipeUpHandler
        coordinator.onCubeTap = parentCubeTapHandler
        coordinator.applyPreviewHover(previewHover)
        coordinator.lastPopTrigger = previewPopTrigger
        coordinator.lastYawRightStep = previewYawRightStep
        coordinator.lastYawLeftStep = previewYawLeftStep
        return coordinator
    }

    // MARK: - Scene
    private func makeScene() -> SCNScene {
        let scene = SCNScene()

        // Removed fog for atmospheric depth cue
        // Removed background.contents assignment

        // Enable environment lighting for reflections if an environment image is present
        if let env = UIImage(named: "CubeEnv") {
            scene.lightingEnvironment.contents = env
        }
        // Use non-zero IBL intensity when using a shaded model so rotation shows depth
        if isRunningInPreviews {
            scene.lightingEnvironment.intensity = 0.35
        } else {
            switch lightingModel {
            case .physicallyBased:
                scene.lightingEnvironment.intensity = 0.30
            case .blinn, .lambert:
                scene.lightingEnvironment.intensity = 0.15
            default:
                scene.lightingEnvironment.intensity = 0.0
            }
        }

        // Slightly darker background helps depth; enable default lighting if needed
        // Removed: scene.background.contents = UIColor.clear

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.eulerAngles = SCNVector3Zero
        // Removed HDR/exposure/motion blur lines
        /*
        cameraNode.camera?.wantsHDR = true
        cameraNode.camera?.wantsExposureAdaptation = true
        cameraNode.camera?.motionBlurIntensity = 0.0
        */
        cameraNode.position = SCNVector3(0, 0, 5.0) // pull back to reduce perspective distortion
        cameraNode.camera?.fieldOfView = 40
        cameraNode.camera?.zFar = 100
        scene.rootNode.addChildNode(cameraNode)

        // Removed ground plane for contact shadow
        /*
        let ground = SCNFloor()
        ground.reflectivity = 0.0
        ground.reflectionFalloffEnd = 0.0
        ground.firstMaterial = {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor.black.withAlphaComponent(0.0)
            m.roughness.contents = 1.0
            m.metalness.contents = 0.0
            m.lightingModel = .lambert
            m.isDoubleSided = true
            m.writesToDepthBuffer = false
            return m
        }()
        let groundNode = SCNNode(geometry: ground)
        groundNode.position = SCNVector3(0, -1.1, 0)
        scene.rootNode.addChildNode(groundNode)
        */

        // Add subtle lights only when using shaded models, WITHOUT shadows (reverted to original)
        if true {
            let intensityDirectional: CGFloat = 80
            let intensityOmni: CGFloat = 40
            // Directional light
            let dir = SCNLight()
            dir.type = .directional
            dir.intensity = intensityDirectional
            let dirNode = SCNNode()
            dirNode.light = dir
            dirNode.eulerAngles = SCNVector3(Float(30.0 * .pi / 180), Float(-45.0 * .pi / 180), 0)
            scene.rootNode.addChildNode(dirNode)

            // Omni light
            let omni = SCNLight()
            omni.type = .omni
            omni.intensity = intensityOmni
            let omniNode = SCNNode()
            omniNode.light = omni
            omniNode.position = SCNVector3(-2, 1.5, 3)
            scene.rootNode.addChildNode(omniNode)
        }

        // Lean cube geometry with small chamfer (lower tessellation)
        let box = SCNBox(width: 1.3, height: 1.3, length: 1.3, chamferRadius: 0.25)
        box.chamferSegmentCount = 8
        let node = SCNNode(geometry: box)
        node.name = "cube"
        // Removed shadow casting on cube
        // node.castsShadow = true
        scene.rootNode.addChildNode(node)

        node.eulerAngles = SCNVector3(0.0, 0.0, 0.0)

        // Attach or update glow particle system for previews (only if enableGlow true)
        if enableGlow && !isRunningInPreviews {
            attachOrUpdateGlow(to: node)
        }

        // In previews, continuously rotate the cube to preview all sides
        if isRunningInPreviews && enablePreviewSpin {
            let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 8.0))
            spin.timingMode = .linear
            node.runAction(spin, forKey: "previewSpin")
        }

        let mats = makeMaterials(baseColor: baseColor)
        box.materials = mats
        // Cache materials for in-place mutation during updates
        // Not here because coordinator is unavailable - handled in makeUIView

        return scene
    }

    private func uiColor(_ c: Color) -> UIColor { UIColor(c) }

    private func makeMaterials(baseColor: Color) -> [SCNMaterial] {
        // Build exactly six faces in +X, -X, +Y, -Y, +Z, -Z order
        // Repeat app tabs to fill all six faces so each side renders content
        let tabFaces: [AppTab] = [
            .map,     // +X
            .record,  // -X
            .feed,    // +Y
            .profile, // -Y
            .map,     // +Z
            .record   // -Z
        ]

        return tabFaces.map { tab in
            let mat = SCNMaterial()
            // Face content
            let bgMask = faceBackgroundOnly(for: tab, baseColor: baseColor)
            let emissionMask = faceEmissionMask(for: tab)
            // Use white background mask in diffuse so geometry shows the shape
            mat.diffuse.contents = bgMask
            mat.diffuse.intensity = 1.0
            // Apply live tint via multiply color
            mat.multiply.contents = uiColor(tintColor)
            mat.multiply.intensity = 0.75
            // Removed preview override for multiply intensity:
            /*
            if isRunningInPreviews {
                mat.multiply.intensity = 0.9
            }
            */
            // Boost emission for better icon readability
            mat.emission.intensity = 0.5
            if isRunningInPreviews {
                mat.emission.intensity = 0.4
            }
            mat.emission.contents = emissionMask
            // Normal map if available - only if NOT in previews
            if useNormalMap && !isRunningInPreviews, let normal = UIImage(named: "CubeNormalMap") {
                mat.normal.contents = normal
                mat.normal.intensity = 0.6
            } else if !useNormalMap {
                mat.normal.contents = nil
            }
            // Apply chosen lighting model
            mat.lightingModel = lightingModel

            if lightingModel != .constant {
                mat.metalness.contents = 0.15
                mat.roughness.contents = 0.8
                // Removed mat.fresnelExponent = 0.7 completely
                if useNormalMap {
                    mat.normal.intensity = 1.3
                }
                mat.selfIllumination.contents = UIColor.black
            } else {
                mat.metalness.contents = 0.0
                mat.roughness.contents = 1.0
            }

            mat.isDoubleSided = false
            mat.locksAmbientWithDiffuse = false

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

                let imgRect = CGRect(x: (size.width - iconWidth) / 2, y: iconY, width: iconWidth, height: iconHeight)

                // Soft glow behind icon
                let glowConfig = UIImage.SymbolConfiguration(pointSize: pointSize + 10, weight: .bold)
                let glowImage = UIImage(systemName: symbolName, withConfiguration: glowConfig) ?? UIImage()
                let glowRect = imgRect.insetBy(dx: -6, dy: -6)
                UIColor.white.withAlphaComponent(0.25).setFill()
                glowImage.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: glowRect, blendMode: .normal, alpha: 0.25)

                let image = UIImage(systemName: symbolName, withConfiguration: config) ?? UIImage()
                image.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: imgRect)

                // Title
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .heavy),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph
                ]
                let title = tab.title as NSString
                let titleRect = CGRect(x: 0, y: 180, width: size.width, height: 40)
                // Outline attributes
                let outlineAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .heavy),
                    .foregroundColor: UIColor.white.withAlphaComponent(0.35),
                    .strokeColor: UIColor.white.withAlphaComponent(0.35),
                    .strokeWidth: -3,
                    .paragraphStyle: paragraph
                ]
                title.draw(in: titleRect.offsetBy(dx: 0.5, dy: 0.5), withAttributes: outlineAttrs)
                // Main fill
                title.draw(in: titleRect, withAttributes: attrs)
            }
        }
    }

    private func faceEmissionMask(for tab: AppTab) -> UIImage {
        let key = "face_emission_\(tab.title)"
        return CubeFaceImageCache.image(for: key) {
            let size = CGSize(width: 300, height: 300)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                // Transparent background
                UIColor.clear.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))

                // Icon (white)
                let symbolName = tab.systemImage
                let pointSize: CGFloat = 80
                let iconWidth: CGFloat = 90
                let iconHeight: CGFloat = 90
                let iconY: CGFloat = 70
                let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
                let imgRect = CGRect(x: (size.width - iconWidth) / 2, y: iconY, width: iconWidth, height: iconHeight)

                // Stronger glow for emission
                let glowConfig = UIImage.SymbolConfiguration(pointSize: pointSize + 10, weight: .bold)
                let glowImage = UIImage(systemName: symbolName, withConfiguration: glowConfig) ?? UIImage()
                let glowRect = imgRect.insetBy(dx: -6, dy: -6)
                glowImage.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: glowRect, blendMode: .normal, alpha: 0.55)

                let image = UIImage(systemName: symbolName, withConfiguration: config) ?? UIImage()
                image.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: imgRect)

                // Title (white)
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let title = tab.title as NSString
                let titleRect = CGRect(x: 0, y: 180, width: size.width, height: 40)
                // Bold pass to thicken emission mask
                let boldAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 26, weight: .black),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph
                ]
                title.draw(in: titleRect, withAttributes: boldAttrs)
                // Regular pass for crisp edges
                let regularAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 24, weight: .heavy),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: paragraph
                ]
                title.draw(in: titleRect, withAttributes: regularAttrs)
            }
        }
    }

    private func faceBackgroundOnly(for tab: AppTab, baseColor: Color) -> UIImage {
        // Include baseColor components in cache key so live changes are reflected
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(baseColor).getRed(&r, green: &g, blue: &b, alpha: &a)
        let key = String(format: "face_bg_only_%@_r%.3f_g%.3f_b%.3f_a%.3f", tab.title, r, g, b, a)
        return CubeFaceImageCache.image(for: key) {
            let size = CGSize(width: 300, height: 300)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                // White background shape (to be tinted via material multiply)
                UIColor(baseColor).setFill()
                let rect = CGRect(origin: .zero, size: size)
                UIBezierPath(roundedRect: rect.insetBy(dx: 8, dy: 8), cornerRadius: 24).fill()
            }
        }
    }

    // MARK: - Glow Particle System Helper
    private func attachOrUpdateGlow(to cube: SCNNode) {
        let glowName = "cubeGlow"
        
        // PARTICLE EFFECTS DISABLED - Remove existing particles if present
        if let existing = cube.childNode(withName: glowName, recursively: false) {
            existing.removeFromParentNode()
            print("🔥 [CubeTabView] Particle effects disabled - glow node removed")
        }
        
        // Early return - don't create new particles
        return
        
        /* ORIGINAL PARTICLE CODE - DISABLED
        let glowNode: SCNNode
        if let existing = cube.childNode(withName: glowName, recursively: false) {
            glowNode = existing
        } else {
            glowNode = SCNNode()
            glowNode.name = glowName
            cube.addChildNode(glowNode)
            // Create a particle system approximating a soft flame-like glow
            let ps = SCNParticleSystem()
            ps.birthRate = 90
            ps.particleLifeSpan = 1.2
            ps.particleLifeSpanVariation = 0.4
            ps.emissionDuration = 0
            ps.loops = true
            ps.spreadingAngle = 10
            ps.emitterShape = SCNSphere(radius: 0.65)
            ps.particleSize = 0.06
            ps.particleSizeVariation = 0.03
            ps.blendMode = .additive
            ps.isBlackPassEnabled = false
            ps.particleVelocity = 0.2
            ps.particleVelocityVariation = 0.15
            ps.acceleration = SCNVector3(0, 0.15, 0)
            ps.particleImage = UIImage(systemName: "circle.fill")
            glowNode.addParticleSystem(ps)
        }
        // Update color each frame from glowColor
        let ui = UIColor(glowColor)
        if let ps = glowNode.particleSystems?.first {
            ps.particleColor = ui.withAlphaComponent(glowOpacity)
            ps.particleColorVariation = SCNVector4(0.03, 0.03, 0.03, 0.1)
        }
        */
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
        var cubeMaterials: [SCNMaterial] = []

        var lastPopTrigger: Int = 0
        var lastYawRightStep: Int = 0
        var lastYawLeftStep: Int = 0

        // Added stored properties for accelerometer simulation
        private var accelSimLink: CADisplayLink?
        private var accelTarget: SCNVector3 = SCNVector3Zero
        private var accelCurrent: SCNVector3 = SCNVector3Zero
        private var accelTime: CFTimeInterval = 0
        private var isAccelSimulating: Bool = false

        // New stored property for preview sim observer
        private var previewSimObserver: NSObjectProtocol?

        // New stored property for continuous yaw state (radians)
        private var currentYaw: Float = 0

        // New stored property for pan starting yaw
        private var panStartYaw: Float = 0

        // Sensitivity: radians per point of horizontal pan
        private let radiansPerPoint: Float = Float.pi / 360

        // New stored property to track if user is interacting (pan gesture active)
        private var isInteracting: Bool = false

        // New stored property to suspend spin temporarily
        private var suspendSpin: Bool = false
        var isSpinSuspended: Bool { suspendSpin }

        // Added helper functions as per instructions
        private func deg2rad(_ degrees: Float) -> Float { degrees * .pi / 180 }
        private func clamp(_ value: Float, min minVal: Float, max maxVal: Float) -> Float { max(minVal, min(maxVal, value)) }

        private func snappedIndex(from yaw: Float) -> Int {
            let rawIndex = Int(round(yaw / (-Float.pi / 2)))
            let modIndex = ((rawIndex % tabs.count) + tabs.count) % tabs.count
            return modIndex
        }

        private var rotationSpeedMultiplier: Double { parent.rotationSpeedMultiplier }

        private var popAudioSource: SCNAudioSource? = {
            let candidates: [(name: String, ext: String?)] = [
                ("pop", "mp3"),
                ("pop", "caf"),
                ("pop", "wav")
            ]
            for cand in candidates {
                if let url = Bundle.main.url(forResource: cand.name, withExtension: cand.ext) {
                    if let src = SCNAudioSource(url: url) {
                        src.volume = 0.9
                        src.isPositional = false
                        src.shouldStream = false
                        src.loops = false
                        src.load()
                        print("[CubeTabView] Loaded pop audio from bundle: \(url.lastPathComponent)")
                        return src
                    }
                }
            }
            print("[CubeTabView] Failed to load 'pop' audio (mp3/caf/wav) from bundle")
            return nil
        }()
        
        #if DEBUG
        private var popAVPlayer: AVAudioPlayer? = {
            let candidates: [(name: String, ext: String?)] = [
                ("pop", "mp3"),
                ("pop", "caf"),
                ("pop", "wav")
            ]
            for cand in candidates {
                if let url = Bundle.main.url(forResource: cand.name, withExtension: cand.ext) {
                    do {
                        let player = try AVAudioPlayer(contentsOf: url)
                        player.volume = 0.9
                        player.numberOfLoops = 0
                        player.prepareToPlay()
                        print("[CubeTabView] AVAudioPlayer prepared: \(url.lastPathComponent)")
                        return player
                    } catch {
                        print("[CubeTabView] AVAudioPlayer init failed for \(url.lastPathComponent): \(error)")
                    }
                }
            }
            print("[CubeTabView] AVAudioPlayer fallback not available for 'pop'")
            return nil
        }()
        #endif

        init(_ parent: CubeSceneView) {
            self.parent = parent
            super.init()
            startObservingHold()
            startAccelerometerSimulation()
            previewSimObserver = NotificationCenter.default.addObserver(forName: Notification.Name("CubePreviewSimulateMotionEnabled"), object: nil, queue: .main) { [weak self] notif in
                guard let self = self else { return }
                let enabled = (notif.userInfo?["enabled"] as? Bool) ?? false
                if enabled {
                    // Pause internal simulation so external posts (sliders) control the cube
                    self.stopAccelerometerSimulation()
                } else {
                    // Resume internal simulation in previews only
                    if isRunningInPreviews {
                        self.startAccelerometerSimulation()
                    }
                }
            }
            NotificationCenter.default.addObserver(forName: Notification.Name("CubePreviewSetFPS"), object: nil, queue: .main) { [weak self] notif in
                guard let self = self, let scnView = self.view else { return }
                let fps = (notif.userInfo?["fps"] as? Int) ?? 120
                scnView.preferredFramesPerSecond = fps
            }
        }

        deinit {
            if let token = previewSimObserver {
                NotificationCenter.default.removeObserver(token)
                previewSimObserver = nil
            }
            stopObservingMotion()
            stopObservingHold()
            stopAccelerometerSimulation()
        }

        func setInitialYaw(for tab: AppTab) {
            let idx = tabs.firstIndex(of: tab) ?? 0
            currentIndex = idx
            currentYaw = Float(idx) * (-Float.pi / 2)
            guard let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            cube.eulerAngles = SCNVector3(0, currentYaw, 0)
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
            } else if parent.selectedTab == .map {
                print("[CubeTabView] Tap -> handled by onCubeTap callback (map tab)")
                // Map centering is handled by onCubeTap callback in HomeView
            } else if parent.selectedTab == .profile {
                print("[CubeTabView] Tap -> posting CubeTapped for profile")
                NotificationCenter.default.post(name: Notification.Name("CubeTapped"), object: nil)
            } else {
                print("[CubeTabView] Tap ignored for tab: \(parent.selectedTab)")
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                print("[CubeTabView] Long press began -> .cubeHoldBegan + .cameraCubeHoldBegan")
                // Post general cube hold notification for all tabs
                NotificationCenter.default.post(name: .cubeHoldBegan, object: nil)
                // Also post camera-specific notification for record tab
                NotificationCenter.default.post(name: .cameraCubeHoldBegan, object: nil)
                // Also send profile-specific notification if on profile tab
                if parent.selectedTab == .profile {
                    print("[CubeTabView] Long press on profile -> posting CubeLongPressed")
                    NotificationCenter.default.post(name: Notification.Name("CubeLongPressed"), object: nil)
                }
            case .ended, .cancelled, .failed:
                print("[CubeTabView] Long press ended -> .cubeHoldEnded + .cameraCubeHoldEnded")
                // Post general cube hold ended notification
                NotificationCenter.default.post(name: .cubeHoldEnded, object: nil)
                // Also post camera-specific notification
                NotificationCenter.default.post(name: .cameraCubeHoldEnded, object: nil)
            default:
                break
            }
        }

        // Updated handlePreviewLongPress per instructions
        @objc func handlePreviewLongPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                parent.previewHoldActive = true
                // Mirror real hold notifications so blink loop runs in previews
                NotificationCenter.default.post(name: .cameraCubeHoldBegan, object: nil)
                // Immediate pop feedback at hold begin
                self.triggerPreviewPop()
            case .ended, .cancelled, .failed:
                parent.previewHoldActive = false
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
                isInteracting = true
                if isRunningInPreviews,
                   let scnView = view,
                   let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true),
                   cube.action(forKey: "previewSpin") != nil {
                    cube.removeAction(forKey: "previewSpin")
                }
                panStartPoint = translation
                panAccumulated = 0
                panStartYaw = currentYaw

            case .changed:
                // Accumulate horizontal movement
                let deltaX = translation.x - panStartPoint.x
                panAccumulated += deltaX
                panStartPoint = translation

                // Update currentYaw by pan offset scaled by radiansPerPoint
                currentYaw = panStartYaw + Float(panAccumulated) * radiansPerPoint

                // Apply rotation immediately
                cube.eulerAngles = SCNVector3(0, currentYaw, 0)

                // Clear liveRotation to avoid fighting motion tilt during pan
                self.liveRotation = SCNVector3Zero

            case .ended, .cancelled, .failed:
                // Snap to nearest face based on currentYaw
                let targetIndex = snappedIndex(from: currentYaw)
                let targetYaw = Float(targetIndex) * (-Float.pi / 2)

                currentIndex = targetIndex
                currentYaw = targetYaw
                animateToYaw(targetYaw, bouncy: true)
                parent.selectedTab = tabs[currentIndex]
                haptic.impactOccurred(intensity: 0.8)

                let newTab = tabs[currentIndex]
                if newTab != .feed {
                    NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                }
                if newTab == .record {
                    NotificationCenter.default.post(name: Notification.Name("RecordTabBecameActive"), object: nil)
                }

                // Reset live tilt and reapply combined rotation in animate completion
                self.liveRotation = SCNVector3Zero

            default:
                break
            }
        }

        func syncToSelectedTab(_ tab: AppTab) {
            guard let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            if let idx = tabs.firstIndex(of: tab), idx != currentIndex {
                currentIndex = idx
                currentYaw = Float(idx) * (-Float.pi / 2)
                animateToYaw(currentYaw)

                if tab != .feed {
                    NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                }
                if tab == .record {
                    NotificationCenter.default.post(name: Notification.Name("RecordTabBecameActive"), object: nil)
                }
            }
        }

        private func animateToYaw(_ yaw: Float, bouncy: Bool = false) {
            guard let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }

            // Suspend spin and remove existing spin if any
            self.suspendSpin = true
            self.isInteracting = true
            if isRunningInPreviews,
               let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true),
               cube.action(forKey: "previewSpin") != nil {
                cube.removeAction(forKey: "previewSpin")
            }

            let cgYaw = CGFloat(yaw)

            let completionBlock: () -> Void = { [weak self] in
                guard let self = self,
                      let scnView = self.view,
                      let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
                self.applyCombinedRotation(to: cube)
                self.isInteracting = false
                self.suspendSpin = false
                if isRunningInPreviews && self.parent.enablePreviewSpin {
                    let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 8.0))
                    spin.timingMode = .linear
                    cube.runAction(spin, forKey: "previewSpin")
                }
            }

            if bouncy {
                let overshoot: CGFloat = 0.12
                let target1 = SCNAction.rotateTo(x: 0, y: cgYaw + overshoot, z: 0, duration: 0.18 * parent.rotationSpeedMultiplier, usesShortestUnitArc: true)
                target1.timingMode = .easeInEaseOut
                let target2 = SCNAction.rotateTo(x: 0, y: cgYaw, z: 0, duration: 0.22 * parent.rotationSpeedMultiplier, usesShortestUnitArc: true)
                target2.timingMode = .easeInEaseOut
                cube.runAction(SCNAction.sequence([target1, target2]), completionHandler: completionBlock)
            } else {
                let action = SCNAction.rotateTo(x: 0, y: cgYaw, z: 0, duration: 0.28 * parent.rotationSpeedMultiplier, usesShortestUnitArc: true)
                action.timingMode = .easeInEaseOut
                cube.runAction(action, completionHandler: completionBlock)
            }
        }

        private func rotateCube(_ node: SCNNode, to index: Int, animated: Bool = true, bouncy: Bool = false) {
            let baseAngle = Float(index) * (-Float.pi / 2)
            if !animated {
                node.eulerAngles.y = baseAngle
                currentYaw = baseAngle
                return
            }
            currentYaw = baseAngle
            animateToYaw(currentYaw, bouncy: bouncy)
        }

        func startObservingMotion() {
            stopObservingMotion()
            motionObserver = NotificationCenter.default.addObserver(forName: Notification.Name("CubeMotionUpdate"), object: nil, queue: .main) { [weak self] notif in
                guard let self,
                      let scnView = self.view,
                      let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }

                // Skip motion updates while user is interacting (panning)
                if self.isInteracting { return }

                // Ignore device pitch/roll; keep faces square
                self.liveRotation = SCNVector3Zero
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

            // Adjusted: slower and more gradual pop cycle
            let up = SCNAction.scale(to: 1.12, duration: 1.2)
            up.timingMode = .easeInEaseOut
            let peakHold = SCNAction.wait(duration: 0.12)
            let down = SCNAction.scale(to: 1.0, duration: 0.9)
            down.timingMode = .easeInEaseOut
            let rest = SCNAction.wait(duration: 0.35)

            // Pop sound exactly at peak
            var peakSound: SCNAction = .wait(duration: 0)
            if let src = popAudioSource {
                #if DEBUG
                if !isRunningInPreviews {
                    do {
                        try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
                        try AVAudioSession.sharedInstance().setActive(true)
                        print("[CubeTabView] AVAudioSession ensured active for long-press slow pop")
                    } catch {
                        print("[CubeTabView] AVAudioSession ensure active failed: \(error)")
                    }
                } else {
                    print("[CubeTabView] Skipping AVAudioSession ensure active in previews")
                }
                #endif
                peakSound = SCNAction.playAudio(src, waitForCompletion: false)
            }

            let peakGroup = SCNAction.group([peakHold, peakSound])
            let cycle = SCNAction.sequence([up, peakGroup, down, rest])
            let loop = SCNAction.repeatForever(cycle)
            cube.runAction(loop, forKey: "recordBlink")
        }

        private func endBlink() {
            guard isBlinking, let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            isBlinking = false
            cube.removeAction(forKey: "recordBlink")
            cube.scale = SCNVector3(1.0, 1.0, 1.0)
        }

        private func applyCombinedRotation(to node: SCNNode) {
            // Lock cube to yaw-only so faces stay square to the screen
            let y = currentYaw
            node.eulerAngles = SCNVector3(0, y, 0)
        }

        func applyPreviewHover(_ enabled: Bool) {
            guard let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            if cube.action(forKey: "previewHover") == nil {
                let up = SCNAction.moveBy(x: 0, y: 0.08, z: 0, duration: 0.9)
                up.timingMode = .easeInEaseOut
                let down = SCNAction.moveBy(x: 0, y: -0.08, z: 0, duration: 0.9)
                down.timingMode = .easeInEaseOut
                let seq = SCNAction.sequence([up, down])
                cube.runAction(.repeatForever(seq), forKey: "previewHover")
            }
        }

        func triggerPreviewPop() {
            guard let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            
            let shouldPlaySound = parent.previewPopSoundEnabled
            
            // Adjusted: slow the one-shot pop
            let up = SCNAction.scale(to: 1.12, duration: 0.35)
            up.timingMode = .easeInEaseOut
            let down = SCNAction.scale(to: 1.0, duration: 0.40)
            down.timingMode = .easeInEaseOut
            cube.runAction(SCNAction.sequence([up, down]), forKey: "previewPop")
            
            if shouldPlaySound {
                print("[CubeTabView] Pop sound requested")
                guard let src = popAudioSource else { print("[CubeTabView] No audio source available"); return }
                #if DEBUG
                if !isRunningInPreviews {
                    do {
                        try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
                        try AVAudioSession.sharedInstance().setActive(true)
                        print("[CubeTabView] AVAudioSession ensured active for pop")
                    } catch {
                        print("[CubeTabView] AVAudioSession ensure active failed: \(error)")
                    }
                } else {
                    print("[CubeTabView] Skipping AVAudioSession ensure active for pop in previews")
                }
                #endif
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if cube.parent == nil { print("[CubeTabView] Cube node missing parent; skipping audio"); return }
                    let player = SCNAudioPlayer(source: src)
                    cube.addAudioPlayer(player)
                    print("[CubeTabView] Added SCNAudioPlayer to cube")
                    // Fallback: also run a playAudio action in case player is ignored in previews
                    let playAction = SCNAction.playAudio(src, waitForCompletion: false)
                    cube.runAction(playAction)
                    print("[CubeTabView] Triggered playAudio action fallback")
                    
                    #if DEBUG
                    if let player = self.popAVPlayer {
                        player.currentTime = 0
                        if !player.isPlaying {
                            player.play()
                            print("[CubeTabView] AVAudioPlayer played pop")
                        } else {
                            // Restart to ensure audible response
                            player.stop()
                            player.currentTime = 0
                            player.play()
                            print("[CubeTabView] AVAudioPlayer restarted pop")
                        }
                    } else {
                        print("[CubeTabView] AVAudioPlayer fallback not available")
                    }
                    #endif
                }
            }
        }

        enum YawDirection { case left, right }
        func applyYaw(steps: Int, direction: YawDirection) {
            guard steps != 0, let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            // Pause any continuous spin during manual yaw so the action isn't overridden
            let wasSpinning = cube.action(forKey: "previewSpin") != nil
            if wasSpinning { cube.removeAction(forKey: "previewSpin") }

            let degreesPerStep: CGFloat = 45
            let totalDegrees = degreesPerStep * CGFloat(steps)
            let radians = (direction == .right ? 1 : -1) * totalDegrees * .pi / 180

            // Update our continuous yaw state so subsequent pans/snaps start from the new angle
            currentYaw += Float(radians)

            let secondsPer45: Double = 0.35
            let action = SCNAction.rotateBy(x: 0, y: radians, z: 0, duration: secondsPer45 * Double(abs(steps)))
            action.timingMode = .easeIn
            cube.runAction(action) { [weak self] in
                guard let self = self else { return }
                // After finishing, reapply combined rotation to include motion tilt
                self.applyCombinedRotation(to: cube)
                // Optionally resume spin in previews if it was active and enabled
                if isRunningInPreviews && self.parent.enablePreviewSpin && wasSpinning == true {
                    let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 8.0))
                    spin.timingMode = .linear
                    cube.runAction(spin, forKey: "previewSpin")
                }
            }
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

        // MARK: - Accelerometer simulation for previews
        func startAccelerometerSimulation() {
            stopAccelerometerSimulation()
            guard isRunningInPreviews else { return }
            isAccelSimulating = true
            accelTime = 0
            accelCurrent = SCNVector3Zero
            accelTarget = SCNVector3Zero
            let link = CADisplayLink(target: self, selector: #selector(accelSimTick(_:)))
            link.add(to: .main, forMode: .common)
            accelSimLink = link
        }

        func stopAccelerometerSimulation() {
            accelSimLink?.invalidate()
            accelSimLink = nil
            isAccelSimulating = false
        }

        @objc private func accelSimTick(_ link: CADisplayLink) {
            guard let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            if isInteracting { return }
            // Ignore simulated tilt; keep yaw-only orientation
            self.liveRotation = SCNVector3Zero
            self.applyCombinedRotation(to: cube)
        }
    }
}

#Preview("Cube Properties") {
    CubeOnlyPreview()
}

private struct CubeOnlyPreview: View {
    @State private var tab: AppTab = .map
    @State private var tint: Color = .indigo
    @State private var glow: Color = .orange
    @State private var glowOpacity: CGFloat = 0.8
    @State private var base: Color = Color(white: 0.2)
    @State private var useNormalMapPreview: Bool = true
    @State private var lightingModelPreview: SCNMaterial.LightingModel = isRunningInPreviews ? .physicallyBased : .lambert

    @State private var uiScale: CGFloat = 1.2
    @State private var scaleMode: ScaleMode = .scaleTo
    @State private var scaleByFactor: CGFloat = 1.0
    @State private var rotationSpeedMultiplier: Double = 1.5
    @State private var enablePreviewSpin: Bool = true

    @State private var hoverEnabled: Bool = false
    @State private var popEnabled: Bool = false
    
    @State private var highFPSPreview: Bool = true

    @State private var previewHover: Bool = false
    @State private var previewPopTrigger: Int = 0
    @State private var previewPopSoundEnabled: Bool = false
    @State private var previewYawRightStep: Int = 0
    @State private var previewYawLeftStep: Int = 0
    @State private var previewHoldActive: Bool = false
    
    @State private var previewGlowEnabled: Bool = true
    
    @State private var directPopPlayer: AVAudioPlayer? = nil
    @State private var lastDirectPopError: String? = nil

    // Preview-only simulated motion controls
    @State private var simulateMotion: Bool = false
    @State private var simRoll: Double = 0.0   // radians
    @State private var simPitch: Double = 0.0  // radians

    enum ScaleMode: String, CaseIterable, Identifiable { case scaleTo, scaleBy; var id: String { rawValue } }

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 12) {
                // Controls
                VStack(alignment: .leading, spacing: 10) {
                    Text("Cube Controls").font(.headline)
                    HStack {
                        ColorPicker("Tint", selection: $tint)
                    }
                    HStack {
                        ColorPicker("Glow", selection: $glow)
                    }
                    HStack {
                        Text("Glow Opacity \(String(format: "%.2f", glowOpacity))")
                        Slider(value: $glowOpacity, in: 0.1...1.0)
                    }
                    HStack {
                        ColorPicker("Base Color", selection: $base)
                    }
                    Picker("Selected Tab", selection: $tab) {
                        Text("Map").tag(AppTab.map)
                        Text("Record").tag(AppTab.record)
                        Text("Feed").tag(AppTab.feed)
                        Text("Profile").tag(AppTab.profile)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text("UI Scale \(String(format: "%.2f", uiScale))")
                        Slider(value: $uiScale, in: 0.8...2.0)
                    }
                    HStack(spacing: 8) {
                        Text("Yaw Right")
                        Button("45°") { previewYawRightStep += 1 }
                        Button("90°") { previewYawRightStep += 2 }
                        Button("180°") { previewYawRightStep += 4 }
                        Button("360°") { previewYawRightStep += 8 }
                    }
                    HStack(spacing: 8) {
                        Text("Yaw Left")
                        Button("45°") { previewYawLeftStep += 1 }
                        Button("90°") { previewYawLeftStep += 2 }
                        Button("180°") { previewYawLeftStep += 4 }
                        Button("360°") { previewYawLeftStep += 8 }
                    }
                    Toggle("Use Normal Map", isOn: $useNormalMapPreview)
                    Picker("Lighting", selection: $lightingModelPreview) {
                        Text("PBR").tag(SCNMaterial.LightingModel.physicallyBased)
                        Text("Blinn").tag(SCNMaterial.LightingModel.blinn)
                        Text("Lambert").tag(SCNMaterial.LightingModel.lambert)
                        Text("Constant").tag(SCNMaterial.LightingModel.constant)
                    }
                    .pickerStyle(.segmented)
                    Toggle("Spin Cube in Preview", isOn: $enablePreviewSpin)
                    Toggle("High FPS (120) in Preview", isOn: $highFPSPreview)
                    Toggle("Glow Enabled", isOn: $previewGlowEnabled)
                    Toggle("Hover", isOn: $hoverEnabled)
                        .onChange(of: hoverEnabled) { _, new in previewHover = new }
                    Toggle("Pop", isOn: $popEnabled)
                        .onChange(of: popEnabled) { _, new in
                            if new {
                                previewPopTrigger += 1
                                popEnabled = false
                            }
                        }
                    Toggle("Pop Sound", isOn: $previewPopSoundEnabled)
                    Toggle("Hold (Preview Only)", isOn: $previewHoldActive)

                    Toggle("Simulate Motion (Preview)", isOn: $simulateMotion)
                        .onChange(of: simulateMotion) { _, new in
                            NotificationCenter.default.post(
                                name: Notification.Name("CubePreviewSimulateMotionEnabled"),
                                object: nil,
                                userInfo: ["enabled": new]
                            )
                        }
                    HStack(spacing: 10) {
                        Button("Play Pop Now") { playPopDirect() }
                            .buttonStyle(.borderedProminent)
                        if let err = lastDirectPopError {
                            Text(err).font(.footnote).foregroundStyle(.secondary)
                        }
                    }

                    Picker("Scale Mode", selection: $scaleMode) {
                        Text("Scale To").tag(ScaleMode.scaleTo)
                        Text("Scale By").tag(ScaleMode.scaleBy)
                    }
                    .pickerStyle(.segmented)
                    if scaleMode == .scaleBy {
                        HStack {
                            Text("Scale By \(String(format: "%.2f", scaleByFactor))x")
                            Slider(value: $scaleByFactor, in: 0.5...2.0)
                        }
                    }
                    HStack {
                        Text("Rotation Speed x\(String(format: "%.2f", rotationSpeedMultiplier))")
                        Slider(value: $rotationSpeedMultiplier, in: 0.5...3.0)
                    }

                    // Simulated accelerometer controls for previews
                    HStack {
                        Text("Roll")
                        Slider(value: $simRoll, in: -0.8...0.8)
                    }
                    .disabled(!simulateMotion)
                    HStack {
                        Text("Pitch")
                        Slider(value: $simPitch, in: -0.8...0.8)
                    }
                    .disabled(!simulateMotion)
                    .onChange(of: simRoll) { _, new in
                        guard simulateMotion else { return }
                        NotificationCenter.default.post(
                            name: Notification.Name("CubeMotionUpdate"),
                            object: nil,
                            userInfo: ["roll": new, "pitch": simPitch]
                        )
                    }
                    .onChange(of: simPitch) { _, new in
                        guard simulateMotion else { return }
                        NotificationCenter.default.post(
                            name: Notification.Name("CubeMotionUpdate"),
                            object: nil,
                            userInfo: ["roll": simRoll, "pitch": new]
                        )
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Cube under test
                ZStack {
                    Color(UIColor.systemBackground)
                    Group {
                        if scaleMode == .scaleTo {
                            CubeTabView(
                                selectedTab: $tab,
                                previewHover: $previewHover,
                                previewPopTrigger: $previewPopTrigger,
                                previewPopSoundEnabled: $previewPopSoundEnabled,
                                previewYawRightStep: $previewYawRightStep,
                                previewYawLeftStep: $previewYawLeftStep,
                                previewHoldActive: $previewHoldActive,
                                tintColor: tint,
                                baseColor: base,
                                glowColor: glow,
                                glowOpacity: glowOpacity,
                                useNormalMap: useNormalMapPreview,
                                lightingModel: (isRunningInPreviews ? SCNMaterial.LightingModel.physicallyBased : lightingModelPreview),
                                rotationSpeedMultiplier: rotationSpeedMultiplier,
                                enablePreviewSpin: enablePreviewSpin,
                                enableGlow: previewGlowEnabled
                            )
                            .frame(height: 200)
                            .aspectRatio(1, contentMode: .fit)
                            .scaleEffect(uiScale)
                            .shadow(radius: 12, y: 8)
                        } else {
                            CubeTabView(
                                selectedTab: $tab,
                                previewHover: $previewHover,
                                previewPopTrigger: $previewPopTrigger,
                                previewPopSoundEnabled: $previewPopSoundEnabled,
                                previewYawRightStep: $previewYawRightStep,
                                previewYawLeftStep: $previewYawLeftStep,
                                previewHoldActive: $previewHoldActive,
                                tintColor: tint,
                                baseColor: base,
                                glowColor: glow,
                                glowOpacity: glowOpacity,
                                useNormalMap: useNormalMapPreview,
                                lightingModel: (isRunningInPreviews ? SCNMaterial.LightingModel.physicallyBased : lightingModelPreview),
                                rotationSpeedMultiplier: rotationSpeedMultiplier,
                                enablePreviewSpin: enablePreviewSpin,
                                enableGlow: previewGlowEnabled
                            )
                            .frame(height: 200)
                            .aspectRatio(1, contentMode: .fit)
                            .scaleEffect(uiScale)
                            .shadow(radius: 12, y: 8)
                            .scaleEffect(scaleByFactor)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(radius: 6)
                .onAppear {
                    NotificationCenter.default.post(name: Notification.Name("CubePreviewSetFPS"), object: nil, userInfo: ["fps": highFPSPreview ? 120 : 60])
                }
                .onChange(of: highFPSPreview) { _, new in
                    NotificationCenter.default.post(name: Notification.Name("CubePreviewSetFPS"), object: nil, userInfo: ["fps": new ? 120 : 60])
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .task {
                // SceneKit handles preview spin now; no SwiftUI rotation needed
            }
        }
    }
    
    private func playPopDirect() {
        lastDirectPopError = nil
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[CubeOnlyPreview] AVAudioSession activation failed: \(error)")
        }
        let candidates: [(String, String?)] = [("pop", "mp3"), ("pop", "caf"), ("pop", "wav")]
        var loaded: URL? = nil
        for (name, ext) in candidates {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                loaded = url
                break
            }
        }
        guard let url = loaded else {
            let msg = "Could not find 'pop' (mp3/caf/wav) in bundle"
            lastDirectPopError = msg
            print("[CubeOnlyPreview] \(msg)")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.95
            player.numberOfLoops = 0
            player.prepareToPlay()
            directPopPlayer = player
            player.currentTime = 0
            player.play()
            print("[CubeOnlyPreview] Played pop directly: \(url.lastPathComponent)")
        } catch {
            lastDirectPopError = "AVAudioPlayer failed: \(error.localizedDescription)"
            print("[CubeOnlyPreview] AVAudioPlayer error: \(error)")
        }
    }
}

