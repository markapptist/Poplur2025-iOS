import SwiftUI
import SceneKit
import CoreMotion
import AVFoundation
import Photos
import GLTFSceneKit

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
    static func clearSkinCache() {
        cache = cache.filter {
            !$0.key.hasPrefix("face_bg_skin_") &&
            !$0.key.hasPrefix("face_emission_neon_") &&
            !$0.key.hasPrefix("face_cubemap_v2_")
        }
    }
}

// MARK: - Cube Face Exporter
struct CubeFaceExporter {
    
    /// Export faces directly to project root - called automatically
    static func exportToProjectRoot() {
        let tabs: [AppTab] = [.map, .record, .feed, .profile]
        let baseColor = Color(white: 0.2)
        
        for tab in tabs {
            let faceImage = generateFaceImage(for: tab, baseColor: baseColor)
            let emissionImage = generateEmissionMask(for: tab)
            let backgroundImage = generateBackgroundOnly(for: tab, baseColor: baseColor)
            
            // Save to /repo directory
            if let faceData = faceImage.pngData() {
                let faceURL = URL(fileURLWithPath: "/repo/cube_face_\(tab.title).png")
                try? faceData.write(to: faceURL)
                print("✅ Exported: \(faceURL.path)")
            }
            
            if let emissionData = emissionImage.pngData() {
                let emissionURL = URL(fileURLWithPath: "/repo/cube_emission_\(tab.title).png")
                try? emissionData.write(to: emissionURL)
                print("✅ Exported: \(emissionURL.path)")
            }
            
            if let bgData = backgroundImage.pngData() {
                let bgURL = URL(fileURLWithPath: "/repo/cube_background_\(tab.title).png")
                try? bgData.write(to: bgURL)
                print("✅ Exported: \(bgURL.path)")
            }
        }
        
        print("🎉 All cube faces exported to /repo/")
    }
    
    /// Export all cube faces to the photo library
    static func exportToPhotos(baseColor: Color = Color(white: 0.2), completion: @escaping (Result<Int, Error>) -> Void) {
        // Request photo library permission
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized else {
                completion(.failure(ExportError.permissionDenied))
                return
            }
            
            let tabs: [AppTab] = [.map, .record, .feed, .profile]
            var savedCount = 0
            
            PHPhotoLibrary.shared().performChanges {
                for tab in tabs {
                    let faceImage = CubeFaceExporter.generateFaceImage(for: tab, baseColor: baseColor)
                    let emissionImage = CubeFaceExporter.generateEmissionMask(for: tab)
                    let backgroundImage = CubeFaceExporter.generateBackgroundOnly(for: tab, baseColor: baseColor)
                    
                    // Save each variant
                    PHAssetChangeRequest.creationRequestForAsset(from: faceImage)
                    PHAssetChangeRequest.creationRequestForAsset(from: emissionImage)
                    PHAssetChangeRequest.creationRequestForAsset(from: backgroundImage)
                    savedCount += 3
                }
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    if success {
                        completion(.success(savedCount))
                    } else {
                        completion(.failure(error ?? ExportError.saveFailed))
                    }
                }
            }
        }
    }
    
    /// Export faces to a temporary directory and return URLs
    static func exportToFiles(baseColor: Color = Color(white: 0.2)) -> [URL] {
        let tabs: [AppTab] = [.map, .record, .feed, .profile]
        var urls: [URL] = []
        
        let tempDir = FileManager.default.temporaryDirectory
        
        for tab in tabs {
            let faceImage = generateFaceImage(for: tab, baseColor: baseColor)
            let emissionImage = generateEmissionMask(for: tab)
            let backgroundImage = generateBackgroundOnly(for: tab, baseColor: baseColor)
            
            // Save face image
            if let faceData = faceImage.pngData() {
                let faceURL = tempDir.appendingPathComponent("cube_face_\(tab.title).png")
                try? faceData.write(to: faceURL)
                urls.append(faceURL)
                print("💾 Exported: \(faceURL.path)")
            }
            
            // Save emission mask
            if let emissionData = emissionImage.pngData() {
                let emissionURL = tempDir.appendingPathComponent("cube_emission_\(tab.title).png")
                try? emissionData.write(to: emissionURL)
                urls.append(emissionURL)
                print("💾 Exported: \(emissionURL.path)")
            }
            
            // Save background only
            if let bgData = backgroundImage.pngData() {
                let bgURL = tempDir.appendingPathComponent("cube_background_\(tab.title).png")
                try? bgData.write(to: bgURL)
                urls.append(bgURL)
                print("💾 Exported: \(bgURL.path)")
            }
        }
        
        return urls
    }
    
    // MARK: - Image Generation
    
    private static func generateFaceImage(for tab: AppTab, baseColor: Color) -> UIImage {
        let size = CGSize(width: 1024, height: 1024) // Higher resolution for export
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(white: 0.95, alpha: 1).setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: 27, dy: 27), cornerRadius: 82).fill()
            
            // Icon — vertically centered: icon(307) + gap(68) + title(137) = 512 → top = (1024−512)/2 = 256
            let symbolName = tab.systemImage
            let pointSize: CGFloat = 273
            let iconWidth: CGFloat = 307
            let iconHeight: CGFloat = 307
            let iconY: CGFloat = 256
            let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)

            let imgRect = CGRect(x: (size.width - iconWidth) / 2, y: iconY, width: iconWidth, height: iconHeight)

            // Soft glow behind icon
            let glowConfig = UIImage.SymbolConfiguration(pointSize: pointSize + 34, weight: .bold)
            let glowImage = UIImage(systemName: symbolName, withConfiguration: glowConfig) ?? UIImage()
            let glowRect = imgRect.insetBy(dx: -20, dy: -20)
            UIColor.white.withAlphaComponent(0.25).setFill()
            glowImage.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: glowRect, blendMode: .normal, alpha: 0.25)

            let image = UIImage(systemName: symbolName, withConfiguration: config) ?? UIImage()
            image.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: imgRect)

            // Title — top = iconY + iconHeight + gap = 256 + 307 + 68 = 631
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 82, weight: .heavy),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let title = tab.title as NSString
            let titleRect = CGRect(x: 0, y: 631, width: size.width, height: 137)
            // Outline
            let outlineAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 82, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.35),
                .strokeColor: UIColor.white.withAlphaComponent(0.35),
                .strokeWidth: -3,
                .paragraphStyle: paragraph
            ]
            title.draw(in: titleRect.offsetBy(dx: 1.7, dy: 1.7), withAttributes: outlineAttrs)
            title.draw(in: titleRect, withAttributes: attrs)
        }
    }
    
    private static func generateEmissionMask(for tab: AppTab) -> UIImage {
        let size = CGSize(width: 1024, height: 1024)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            
            let symbolName = tab.systemImage
            let pointSize: CGFloat = 273
            let iconWidth: CGFloat = 307
            let iconHeight: CGFloat = 307
            let iconY: CGFloat = 256
            let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
            let imgRect = CGRect(x: (size.width - iconWidth) / 2, y: iconY, width: iconWidth, height: iconHeight)

            // Glow
            let glowConfig = UIImage.SymbolConfiguration(pointSize: pointSize + 34, weight: .bold)
            let glowImage = UIImage(systemName: symbolName, withConfiguration: glowConfig) ?? UIImage()
            let glowRect = imgRect.insetBy(dx: -20, dy: -20)
            glowImage.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: glowRect, blendMode: .normal, alpha: 0.55)

            let image = UIImage(systemName: symbolName, withConfiguration: config) ?? UIImage()
            image.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: imgRect)

            // Title
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let title = tab.title as NSString
            let titleRect = CGRect(x: 0, y: 631, width: size.width, height: 137)
            let boldAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 89, weight: .black),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            title.draw(in: titleRect, withAttributes: boldAttrs)
            let regularAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 82, weight: .heavy),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            title.draw(in: titleRect, withAttributes: regularAttrs)
        }
    }
    
    private static func generateBackgroundOnly(for tab: AppTab, baseColor: Color) -> UIImage {
        let size = CGSize(width: 1024, height: 1024)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor(baseColor).setFill()
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: rect.insetBy(dx: 27, dy: 27), cornerRadius: 82).fill()
        }
    }
    
    enum ExportError: LocalizedError {
        case permissionDenied
        case saveFailed
        
        var errorDescription: String? {
            switch self {
            case .permissionDenied: return "Photo library access denied"
            case .saveFailed: return "Failed to save images"
            }
        }
    }
}

struct CubeTabView: View {
    @ObservedObject private var cubeSkinStore = CubeSkinStore.shared
    @Binding var selectedTab: AppTab
    @Binding var previewHover: Bool
    @Binding var previewPopTrigger: Int
    @Binding var previewPopSoundEnabled: Bool
    @Binding var previewYawRightStep: Int
    @Binding var previewYawLeftStep: Int
    @Binding var previewHoldActive: Bool
    @Environment(\.renderingConfig) private var renderingConfig
    var tintColor: Color = .indigo
    var baseColor: Color = Color(red: 0.04, green: 0.03, blue: 0.10)
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
            enableGlow: enableGlow,
            currentSkin: cubeSkinStore.current
        )
        .frame(width: 200, height: 200)
        .background(.clear)
        .accessibilityHidden(true)
        .onAppear {
            print("[CubeTabView] Appeared (forced 3D)")
            #if DEBUG
            if !isRunningInPreviews {
                PoplurEQSync.shared.configureAudioSession(for: .ambientPlayback)
                print("[CubeTabView] AVAudioSession activated")
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
    var currentSkin: CubeSkin = CubeSkinStore.shared.current

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
            enableGlow: enableGlow,
            currentSkin: currentSkin
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
    var currentSkin: CubeSkin = CubeSkinStore.shared.current

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
            v.isPlaying = true
            v.rendersContinuously = self.selectedTab == .record || self.selectedTab == .map
            // Removed: v.antialiasingMode = .multisampling4X

            context.coordinator.bindGeneratedCubeMaterials(from: v.scene)
            context.coordinator.setInitialYaw(for: self.selectedTab)
            // Defer normal map and glow attachment one more pass in previews
            if isRunningInPreviews {
                DispatchQueue.main.async {
                    if let cube = v.scene?.rootNode.childNode(withName: "cube", recursively: true), let _ = cube.geometry as? SCNBox {
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
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1  // single-touch only — prevents multi-finger twists from reaching the gesture
        let swipeUp = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
        swipeUp.direction = .up
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5 // 0.5 seconds for timeline/general interactions (recording countdown handles the 2s delay)
        longPress.allowableMovement = 24

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
        let shouldKeepRendererHot = selectedTab == .record || selectedTab == .map
        if uiView.rendersContinuously != shouldKeepRendererHot {
            uiView.rendersContinuously = shouldKeepRendererHot
        }
        if !uiView.isPlaying {
            uiView.isPlaying = true
        }

        // Keep tab state in sync
        context.coordinator.syncToSelectedTab(selectedTab)

        context.coordinator.setSettingsFaceActive(selectedTab == .settings)

        if selectedTab == .record {
            context.coordinator.resumeForCameraTab()
        }

        // Rebuild the scene when model-backed skins change, and update generated materials for fallback skins.
        if currentSkin != context.coordinator.lastAppliedSkin {
            context.coordinator.lastAppliedSkin = currentSkin
            CubeFaceImageCache.clearSkinCache()
            if currentSkin.runtimeModelAssetName != nil {
                uiView.scene = makeScene()
                context.coordinator.bindGeneratedCubeMaterials(from: uiView.scene)
                context.coordinator.setInitialYaw(for: selectedTab)
            } else if let cube = uiView.scene?.rootNode.childNode(withName: "cube", recursively: true),
                      let box = cube.geometry as? SCNBox {
                var newMats = makeMaterials(baseColor: baseColor)
                let elementCount = box.elementCount
                if elementCount > newMats.count {
                    let edgeMat = makeChamferEdgeMaterial()
                    while newMats.count < elementCount { newMats.append(edgeMat) }
                }
                box.materials = newMats
                context.coordinator.cubeMaterials = newMats
                context.coordinator.applyAllDynamicFaces()
            }
        }

        // Keep multiply white (neon style — emission carries all color)
        if let cube = uiView.scene?.rootNode.childNode(withName: "cube", recursively: true),
           let box = cube.geometry as? SCNBox {
            let mats = context.coordinator.cubeMaterials.isEmpty ? box.materials : context.coordinator.cubeMaterials
            for mat in mats {
                mat.multiply.contents = UIColor.white
                if useNormalMap, let normal = UIImage(named: "CubeNormalMap") {
                    mat.normal.contents = normal
                    mat.normal.intensity = isRunningInPreviews ? 2.0 : 0.6
                } else {
                    mat.normal.contents = nil
                }
            }
            if context.coordinator.cubeMaterials.isEmpty == false {
                box.materials = context.coordinator.cubeMaterials
            }
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
    private func initialYaw(for tab: AppTab) -> Float {
        let tabs: [AppTab] = [.feed, .profile, .map, .record]
        let index = tabs.firstIndex(of: tab) ?? 0
        return Float(index) * (-Float.pi / 2)
    }

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

        let generatedBox: SCNBox?
        let node: SCNNode
        if let runtimeModelNode = makeRuntimeCubeModelNode() {
            generatedBox = nil
            node = runtimeModelNode
        } else {
            // Lean fallback cube geometry with small chamfer (lower tessellation).
            let box = SCNBox(width: 1.3, height: 1.3, length: 1.3, chamferRadius: 0.25)
            box.chamferSegmentCount = 8
            generatedBox = box
            node = SCNNode(geometry: box)
        }
        node.name = "cube"
        // Removed shadow casting on cube
        // node.castsShadow = true
        scene.rootNode.addChildNode(node)

        node.simdOrientation = simd_quatf(angle: initialYaw(for: selectedTab), axis: SIMD3<Float>(0, 1, 0))

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

        if let box = generatedBox {
            var mats = makeMaterials(baseColor: baseColor)
            // SCNBox with chamferRadius generates 26 geometry elements (6 faces + 12 edges + 8 corners).
            // Any element beyond the materials array cycles, but chamfer UVs sample black tile corners.
            // Fill all extra slots with a solid edge material so no chamfer ever shows black.
            let elementCount = box.elementCount
            if elementCount > mats.count {
                let edgeMat = makeChamferEdgeMaterial()
                while mats.count < elementCount { mats.append(edgeMat) }
            }
            box.materials = mats
        }
        // Cache materials for in-place mutation during updates
        // Not here because coordinator is unavailable - handled in makeUIView

        return scene
    }

    private func makeRuntimeCubeModelNode() -> SCNNode? {
        guard let assetName = currentSkin.runtimeModelAssetName else { return nil }

        let loadedScene: SCNScene
        if let glbURL = runtimeCubeModelURL(named: assetName, fileExtensions: ["glb"]),
           let glbScene = loadRuntimeGLBScene(from: glbURL, assetName: assetName) {
            loadedScene = glbScene
        } else if let url = runtimeCubeModelURL(named: assetName, fileExtensions: ["usdz", "dae"]),
            let daeScene = try? SCNScene(url: url, options: nil) {
            loadedScene = daeScene
        } else {
            print("[CubeSceneView] Missing runtime cube model asset: \(assetName)")
            return nil
        }

        let container = SCNNode()
        let modelContent = SCNNode()
        for child in loadedScene.rootNode.childNodes {
            child.removeFromParentNode()
            modelContent.addChildNode(child)
        }
        guard !modelContent.childNodes.isEmpty else { return nil }

        normalizeRuntimeCubeModel(modelContent)
        prepareRuntimeCubeMaterials(modelContent, assetName: assetName, skin: currentSkin)
        container.addChildNode(modelContent)
        return container
    }

    private func runtimeCubeModelURL(named assetName: String, fileExtensions: [String]) -> URL? {
        for fileExtension in fileExtensions {
            if let bundledURL = Bundle.main.url(
                forResource: assetName,
                withExtension: fileExtension,
                subdirectory: "CubeModels"
            ) ?? Bundle.main.url(forResource: assetName, withExtension: fileExtension) {
                return bundledURL
            }
        }

        #if DEBUG
        let projectCubeModelsURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("CubeModels", isDirectory: true)

        for fileExtension in fileExtensions {
            let localURL = projectCubeModelsURL.appendingPathComponent("\(assetName).\(fileExtension)")
            if FileManager.default.fileExists(atPath: localURL.path) {
                return localURL
            }
        }
        #endif

        return nil
    }

    private func loadRuntimeGLBScene(from url: URL, assetName: String) -> SCNScene? {
        let source = GLTFSceneSource(url: url, options: nil)
        guard let scene = source.scene() else {
            print("[CubeSceneView] Could not decode GLB runtime cube model: \(assetName) at \(url.path)")
            return nil
        }
        return scene
    }

    private func normalizeRuntimeCubeModel(_ node: SCNNode) {
        guard let bounds = runtimeBounds(for: node) else { return }
        let minBounds = bounds.min
        let maxBounds = bounds.max

        let width = maxBounds.x - minBounds.x
        let height = maxBounds.y - minBounds.y
        let depth = maxBounds.z - minBounds.z
        let maxExtent = max(width, max(height, depth))
        guard maxExtent > 0 else { return }

        let center = SCNVector3(
            (minBounds.x + maxBounds.x) / 2,
            (minBounds.y + maxBounds.y) / 2,
            (minBounds.z + maxBounds.z) / 2
        )
        let scale = Float(1.3) / maxExtent
        node.pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)
        node.scale = SCNVector3(scale, scale, scale)
    }

    private func runtimeBounds(for root: SCNNode) -> (min: SCNVector3, max: SCNVector3)? {
        var minBounds = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxBounds = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var foundGeometry = false

        root.enumerateChildNodes { child, _ in
            guard child.geometry != nil else { return }
            foundGeometry = true
            let bounds = child.boundingBox
            let corners = [
                SCNVector3(bounds.min.x, bounds.min.y, bounds.min.z),
                SCNVector3(bounds.min.x, bounds.min.y, bounds.max.z),
                SCNVector3(bounds.min.x, bounds.max.y, bounds.min.z),
                SCNVector3(bounds.min.x, bounds.max.y, bounds.max.z),
                SCNVector3(bounds.max.x, bounds.min.y, bounds.min.z),
                SCNVector3(bounds.max.x, bounds.min.y, bounds.max.z),
                SCNVector3(bounds.max.x, bounds.max.y, bounds.min.z),
                SCNVector3(bounds.max.x, bounds.max.y, bounds.max.z)
            ]
            for corner in corners {
                let point = child.convertPosition(corner, to: root)
                minBounds.x = min(minBounds.x, point.x)
                minBounds.y = min(minBounds.y, point.y)
                minBounds.z = min(minBounds.z, point.z)
                maxBounds.x = max(maxBounds.x, point.x)
                maxBounds.y = max(maxBounds.y, point.y)
                maxBounds.z = max(maxBounds.z, point.z)
            }
        }

        return foundGeometry ? (minBounds, maxBounds) : nil
    }

    private func prepareRuntimeCubeMaterials(_ node: SCNNode, assetName: String, skin: CubeSkin) {
        let diffuseTexture = runtimeCubeTexture(assetName: assetName, suffix: "0003")
        let normalTexture = runtimeCubeTexture(assetName: assetName, suffix: "0001")

        node.enumerateChildNodes { child, _ in
            child.geometry?.materials.forEach { material in
                material.lightingModel = .physicallyBased
                material.isDoubleSided = true
                material.diffuse.contents = diffuseTexture ?? material.diffuse.contents
                material.diffuse.intensity = 1.0
                material.emission.contents = nil
                material.emission.intensity = 0.0
                material.normal.contents = useNormalMap ? normalTexture : nil
                material.normal.intensity = useNormalMap ? 0.55 : 0.0
                if skin == .gold {
                    material.metalness.contents = 1.0
                    material.roughness.contents = 0.28
                    material.specular.contents = UIColor(white: 1.0, alpha: 1.0)
                    material.specular.intensity = 0.95
                } else {
                    material.metalness.contents = 0.35
                    material.roughness.contents = 0.38
                    material.specular.contents = UIColor(white: 0.9, alpha: 1.0)
                    material.specular.intensity = 0.55
                }
            }
        }
    }

    private func runtimeCubeTexture(assetName: String, suffix: String) -> UIImage? {
        let resourceName = "\(assetName)_texture_\(suffix)"
        if let image = UIImage(named: "\(resourceName).jpg") ?? UIImage(named: resourceName) {
            return image
        }
        let url = Bundle.main.url(forResource: resourceName, withExtension: "jpg", subdirectory: "CubeModels")
            ?? Bundle.main.url(forResource: resourceName, withExtension: "jpg")
        guard let url else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func uiColor(_ c: Color) -> UIColor { UIColor(c) }

    // Slices one tile from a 4×3 cube-net image and scales the content to fill the full face.
    // AI-generated cross layouts have black padding around the content within each tile; this
    // detects the non-black bounding box and stretches it edge-to-edge so no black bleeds onto the cube.
    // faceIndex matches SCNBox material order: 0=front(Feed) 1=right(Profile) 2=back(Map) 3=left(Camera) 4=top 5=bottom
    private func sliceCubemapTile(from image: UIImage, faceIndex: Int) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let tileW = cg.width / 4
        let tileH = cg.height / 3
        // (col, row) for each material index in the cross layout
        let colRow: [(Int, Int)] = [(2,1), (3,1), (0,1), (1,1), (1,0), (1,2)]
        guard faceIndex < colRow.count else { return image }
        let (col, row) = colRow[faceIndex]
        let cropRect = CGRect(x: col * tileW, y: row * tileH, width: tileW, height: tileH)
        guard let tile = cg.cropping(to: cropRect) else { return image }

        // Find the tight bounding box of non-black content pixels in the tile.
        let contentRect = tileContentBounds(cgImage: tile, threshold: 20)
        let size = CGSize(width: tileW, height: tileH)
        let skin = CubeSkinStore.shared.current

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            // Use the skin's theme color as background so chamfer edge pixels blend.
            skin.themeUIColor.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
            // Crop to content area then stretch to fill the full tile — removes black padding.
            if let contentTile = tile.cropping(to: contentRect) {
                UIImage(cgImage: contentTile, scale: image.scale, orientation: image.imageOrientation)
                    .draw(in: CGRect(origin: .zero, size: size))
            } else {
                UIImage(cgImage: tile, scale: image.scale, orientation: image.imageOrientation)
                    .draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }

    // Returns the tightest CGRect containing all pixels brighter than `threshold` in any channel.
    // If the whole image is dark, returns the full image rect.
    private func tileContentBounds(cgImage: CGImage, threshold: Int) -> CGRect {
        let w = cgImage.width
        let h = cgImage.height
        guard let dataProvider = cgImage.dataProvider,
              let cfData = dataProvider.data,
              let bytes = CFDataGetBytePtr(cfData) else {
            return CGRect(x: 0, y: 0, width: w, height: h)
        }
        let bpp = cgImage.bitsPerPixel / 8  // bytes per pixel (usually 4: RGBA or BGRA)
        let bpr = cgImage.bytesPerRow
        guard bpp >= 3 else { return CGRect(x: 0, y: 0, width: w, height: h) }
        var minX = w, minY = h, maxX = 0, maxY = 0
        for y in 0..<h {
            for x in 0..<w {
                let o = y * bpr + x * bpp
                // First three bytes are R,G,B (RGBA) or B,G,R (BGRA) — order doesn't matter for threshold.
                let c0 = Int(bytes[o]), c1 = Int(bytes[o + 1]), c2 = Int(bytes[o + 2])
                if c0 > threshold || c1 > threshold || c2 > threshold {
                    if x < minX { minX = x }; if x > maxX { maxX = x }
                    if y < minY { minY = y }; if y > maxY { maxY = y }
                }
            }
        }
        if minX > maxX || minY > maxY { return CGRect(x: 0, y: 0, width: w, height: h) }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func makeMaterials(baseColor: Color) -> [SCNMaterial] {
        // SCNBox material order (Apple docs): 0=front(+Z) 1=right(+X) 2=back(-Z) 3=left(-X) 4=top(+Y) 5=bottom(-Y)
        // yaw=0°   → front (+Z) = index 0 = Map
        // yaw=-90° → right (+X) = index 1 = Camera
        // yaw=-180°→ back  (-Z) = index 2 = Feed
        // yaw=-270°→ left  (-X) = index 3 = Profile
        let faceSpecs: [(String, String, AppTab)] = [
            ("Feed",     "tv.fill",        .feed),     // 0: +Z front
            ("Profile",  "person.fill",    .profile),  // 1: +X right
            ("Map",      "map.fill",       .map),      // 2: -Z back
            ("Camera",   "camera.fill",    .record),   // 3: -X left
            ("",         "fork.knife",     .settings), // 4: +Y top
            ("",         "p.circle.fill",  .settings), // 5: -Y bottom
        ]

        let skin = CubeSkinStore.shared.current

        return faceSpecs.map { spec in
            let (title, icon, tab) = spec
            let mat = SCNMaterial()

            // Use the skin only as the face material. Icons and labels are rendered
            // dynamically so new skins never show stale baked cube artwork.
            mat.diffuse.contents = faceBackgroundOnly(for: tab, baseColor: baseColor)
            mat.emission.intensity = 0.88
            mat.emission.contents = faceEmissionMask(title: title, systemImage: icon,
                                                     borderColor: skin.borderAccentColor,
                                                     iconColor: skin.iconFillColor)

            mat.diffuse.intensity = 1.0
            mat.diffuse.wrapS = .clamp
            mat.diffuse.wrapT = .clamp
            mat.multiply.contents = UIColor.white
            mat.multiply.intensity = 1.0
            if useNormalMap && !isRunningInPreviews, let normal = UIImage(named: "CubeNormalMap") {
                mat.normal.contents = normal
                mat.normal.intensity = 0.6
            }
            mat.lightingModel = lightingModel
            mat.metalness.contents = 0.0
            mat.roughness.contents = 1.0
            mat.isDoubleSided = false
            mat.locksAmbientWithDiffuse = false
            return mat
        }
    }

    private func makeChamferEdgeMaterial() -> SCNMaterial {
        let mat = SCNMaterial()
        // Use the skin's theme color for chamfer edges so they blend with the face textures
        mat.diffuse.contents = CubeSkinStore.shared.current.themeUIColor
        mat.diffuse.intensity = 1.0
        mat.lightingModel = lightingModel
        mat.metalness.contents = 0.0
        mat.roughness.contents = 1.0
        mat.isDoubleSided = true
        mat.locksAmbientWithDiffuse = false
        return mat
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
        let skin = CubeSkinStore.shared.current
        let bc = skin.borderAccentColor
        let ic = skin.iconFillColor
        switch tab {
        case .feed:    return faceEmissionMask(title: "Feed",     systemImage: "tv.fill",        borderColor: bc, iconColor: ic)
        case .map:     return faceEmissionMask(title: "Map",      systemImage: "map.fill",       borderColor: bc, iconColor: ic)
        case .record:  return faceEmissionMask(title: "Camera",   systemImage: "camera.fill",    borderColor: bc, iconColor: ic)
        case .profile: return faceEmissionMask(title: "Profile",  systemImage: "person.fill",    borderColor: bc, iconColor: ic)
        case .settings:return faceEmissionMask(title: "Settings", systemImage: "gearshape.fill", borderColor: bc, iconColor: ic)
        }
    }

    private func faceEmissionMask(title: String, systemImage: String,
                                  borderColor: UIColor = UIColor(red: 0.55, green: 0.30, blue: 1.0, alpha: 1.0),
                                  iconColor: UIColor = .white) -> UIImage {
        let skin = CubeSkinStore.shared.current
        let key = "face_emission_neon_\(skin.rawValue)_\(title)_\(systemImage)"
        return CubeFaceImageCache.image(for: key) {
            let size = CGSize(width: 300, height: 300)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { ctx in
                UIColor.clear.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))

                // Skin-matched neon border glow — drawn from outer edge inward
                let borderRect = CGRect(origin: .zero, size: size)
                for i in 1...18 {
                    let lineWidth = CGFloat(19 - i) * 1.3
                    let alpha = CGFloat(i) / 18.0 * 0.62
                    borderColor.withAlphaComponent(alpha).setStroke()
                    let inset = lineWidth / 2.0 + 2.0
                    let path = UIBezierPath(
                        roundedRect: borderRect.insetBy(dx: inset, dy: inset),
                        cornerRadius: max(4.0, 22.0 - lineWidth * 0.4)
                    )
                    path.lineWidth = lineWidth
                    path.stroke()
                }
                // Crisp bright inner border — lighter version of borderColor
                var bh: CGFloat = 0, bs: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
                borderColor.getHue(&bh, saturation: &bs, brightness: &bb, alpha: &ba)
                UIColor(hue: bh, saturation: max(0, bs - 0.18), brightness: min(1, bb + 0.22), alpha: 0.92).setStroke()
                let crispPath = UIBezierPath(roundedRect: borderRect.insetBy(dx: 5, dy: 5), cornerRadius: 20)
                crispPath.lineWidth = 2.5
                crispPath.stroke()

                // Icon
                let isPhoneIcon = title == "Phone" || systemImage.contains("phone")
                let pointSize: CGFloat = isPhoneIcon ? 118 : 80
                let maxW: CGFloat = isPhoneIcon ? 132 : 90
                let maxH: CGFloat = isPhoneIcon ? 132 : 90
                let iconY: CGFloat = isPhoneIcon ? 48 : 68
                let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
                let image = UIImage(systemName: systemImage, withConfiguration: config) ?? UIImage()
                let imgScale = image.size.width > 0 && image.size.height > 0
                    ? min(maxW / image.size.width, maxH / image.size.height) : 1
                let drawW = image.size.width * imgScale
                let drawH = image.size.height * imgScale
                let imgRect = CGRect(
                    x: (size.width - drawW) / 2,
                    y: iconY + (maxH - drawH) / 2,
                    width: drawW,
                    height: drawH
                )

                // Multi-pass glow behind icon
                for i in stride(from: 5, through: 1, by: -1) {
                    let glowSize = pointSize + CGFloat(i) * 7
                    let glowConfig = UIImage.SymbolConfiguration(pointSize: glowSize, weight: .bold)
                    let glowImg = UIImage(systemName: systemImage, withConfiguration: glowConfig) ?? UIImage()
                    let expand = CGFloat(i) * 3.5
                    glowImg.withTintColor(iconColor, renderingMode: .alwaysOriginal)
                        .draw(in: imgRect.insetBy(dx: -expand, dy: -expand), blendMode: .normal, alpha: 0.07 * CGFloat(6 - i))
                }

                image.withTintColor(iconColor, renderingMode: .alwaysOriginal).draw(in: imgRect)

                guard !title.isEmpty else { return }

                // Label text — skin accent color, double-drawn for thickness
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                let titleNS = title as NSString
                let titleRect = CGRect(x: 0, y: 180, width: size.width, height: 40)
                let glowAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 27, weight: .black),
                    .foregroundColor: iconColor.withAlphaComponent(0.38),
                    .paragraphStyle: paragraph
                ]
                titleNS.draw(in: titleRect.insetBy(dx: -1, dy: -1), withAttributes: glowAttrs)
                let mainAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 26, weight: .black),
                    .foregroundColor: iconColor,
                    .paragraphStyle: paragraph
                ]
                titleNS.draw(in: titleRect, withAttributes: mainAttrs)
            }
        }
    }

    private func faceBackgroundOnly(for tab: AppTab, baseColor: Color) -> UIImage {
        let skin = CubeSkinStore.shared.current
        let tabSuffix = (skin == .rubber) ? "_\(tab.title)" : ""
        let cacheKey = "face_bg_skin_\(skin.rawValue)\(tabSuffix)"
        if let skinImage = UIImage(named: skin.diffuseAssetName) {
            return CubeFaceImageCache.image(for: cacheKey) { skinImage }
        }
        return CubeFaceImageCache.image(for: cacheKey) {
            skin.makeTexture(tab: tab)
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
        private let tabs: [AppTab] = [.map, .record, .feed, .profile]
        private var currentIndex: Int = 2
        var onSwipeUp: (() -> Void)?
        var onCubeTap: (() -> Void)?
        var parentSwipeUpHandler: (() -> Void)?

        private var panStartPoint: CGPoint = .zero
        private var panAccumulated: CGFloat = 0
        private let panThreshold: CGFloat = 10 // lower threshold for sensitivity
        private let haptic = UIImpactFeedbackGenerator(style: .light)
        private var cubeHoldLastLocation: CGPoint?

        private var motionObserver: NSObjectProtocol?
        private var liveRotation: SCNVector3 = SCNVector3Zero
        private var liveRollYaw: Float = 0
        private var lastTiltSnapTime: CFTimeInterval = 0
        private var lastSetYaw: Float = 0

        private var holdObservers: [NSObjectProtocol] = []
        private var profileIconOverrideObserver: NSObjectProtocol?
        private var faceOverrideObserver: NSObjectProtocol?
        private var profileIconOverride: (title: String, systemImage: String)?
        private var faceOverrides: [Int: (title: String, systemImage: String)] = [:]
        private var tvGuideObservers: [NSObjectProtocol] = []
        private var isTVGuideOpen: Bool = false
        private var isBlinking: Bool = false
        var cubeMaterials: [SCNMaterial] = []
        var lastAppliedSkin: CubeSkin = CubeSkinStore.shared.current
        var wasOnSettingsTab: Bool = false

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
        private var resignActiveToken: NSObjectProtocol?

        // New stored property for continuous yaw state (radians)
        private var currentYaw: Float = -Float.pi

        // New stored property for pan starting yaw
        private var panStartYaw: Float = 0

        // Sensitivity: radians per point of horizontal pan
        private let radiansPerPoint: Float = Float.pi / 360

        // New stored property to track if user is interacting (pan gesture active)
        private var isInteracting: Bool = false

        // New stored property to suspend spin temporarily
        private var suspendSpin: Bool = false
        var isSpinSuspended: Bool { suspendSpin }

        // P-logo periodic peek
        private var peekPitch: Float = 0
        private var peekActive: Bool = false
        private var peekTimer: Timer?

        // Skin change observer
        private var skinChangeObserver: NSObjectProtocol?

        // Added helper functions as per instructions
        private func deg2rad(_ degrees: Float) -> Float { degrees * .pi / 180 }
        private func clamp(_ value: Float, min minVal: Float, max maxVal: Float) -> Float { max(minVal, min(maxVal, value)) }

        private func snappedIndex(from yaw: Float) -> Int {
            let rawIndex = Int(round(yaw / (-Float.pi / 2)))
            let modIndex = ((rawIndex % tabs.count) + tabs.count) % tabs.count
            return modIndex
        }

        private func canonicalYaw(for index: Int) -> Float {
            Float(index) * (-Float.pi / 2)
        }

        private func nearestEquivalentYaw(for index: Int, from yaw: Float) -> Float {
            let baseYaw = canonicalYaw(for: index)
            let turn = Float.pi * 2
            return baseYaw + round((yaw - baseYaw) / turn) * turn
        }

        private func continuousYaw(to targetIndex: Int) -> Float {
            let target = max(0, min(tabs.count - 1, targetIndex))
            let current = currentIndex
            let forwardSteps = (target - current + tabs.count) % tabs.count
            let backwardSteps = (current - target + tabs.count) % tabs.count
            let signedSteps: Int
            if forwardSteps == 0 {
                signedSteps = 0
            } else if forwardSteps <= backwardSteps {
                signedSteps = forwardSteps
            } else {
                signedSteps = -backwardSteps
            }

            let currentFaceYaw = canonicalYaw(for: current)
            let turn = Float.pi * 2
            let currentRevolution = round((currentYaw - currentFaceYaw) / turn) * turn
            return currentFaceYaw + currentRevolution - (Float(signedSteps) * Float.pi / 2)
        }

        private var rotationSpeedMultiplier: Double { parent.rotationSpeedMultiplier }

        private var selectedTabNeedsContinuousRenderer: Bool {
            parent.selectedTab == .record || parent.selectedTab == .map
        }

        private func setRendererHot(_ hot: Bool) {
            guard let scnView = view else { return }
            scnView.isPlaying = true
            scnView.rendersContinuously = hot || selectedTabNeedsContinuousRenderer
        }

        private func restoreRendererMode() {
            guard let scnView = view else { return }
            scnView.rendersContinuously = selectedTabNeedsContinuousRenderer
            scnView.setNeedsDisplay()
        }

        // Safe AVAudioPlayer — used in place of SCNAction.playAudio/SCNAudioPlayer which
        // crash when AVAudioEngine is interrupted (app background) or scene tears down (tab switch).
        private lazy var popAVPlayer: AVAudioPlayer? = {
            let candidates: [(name: String, ext: String?)] = [
                ("pop", "mp3"),
                ("pop", "caf"),
                ("pop", "wav")
            ]
            for cand in candidates {
                if let url = Bundle.main.url(forResource: cand.name, withExtension: cand.ext) {
                    if let player = try? AVAudioPlayer(contentsOf: url) {
                        player.volume = 0.9
                        player.numberOfLoops = 0
                        player.prepareToPlay()
                        return player
                    }
                }
            }
            return nil
        }()

        init(_ parent: CubeSceneView) {
            self.parent = parent
            super.init()
            startObservingHold()
            startAccelerometerSimulation()
            startPeriodicPLogoTimer()
            skinChangeObserver = NotificationCenter.default.addObserver(forName: .CubeSkinDidChange, object: nil, queue: .main) { [weak self] _ in
                self?.refreshMaterialsForSkinChange()
            }
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
            
            // Flash/torch notifications - illuminate cube when flashlight is ON
            NotificationCenter.default.addObserver(forName: Notification.Name("CubeStartFlashing"), object: nil, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                print("💡 [CubeTabView] Flash ON - illuminating cube")
                self.startFlashing()
            }
            
            NotificationCenter.default.addObserver(forName: Notification.Name("CubeStopFlashing"), object: nil, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                print("🔦 [CubeTabView] Flash OFF - stopping cube illumination")
                self.stopFlashing()
            }

            profileIconOverrideObserver = NotificationCenter.default.addObserver(forName: .CubeProfileIconOverrideChanged, object: nil, queue: .main) { [weak self] notification in
                guard let self = self else { return }
                let title = notification.userInfo?["title"] as? String
                let systemImage = notification.userInfo?["systemImage"] as? String
                if let title, let systemImage {
                    self.profileIconOverride = (title, systemImage)
                } else {
                    self.profileIconOverride = nil
                }
                self.applyCurrentProfileIconOverride()
            }

            faceOverrideObserver = NotificationCenter.default.addObserver(forName: .CubeFaceOverrideChanged, object: nil, queue: .main) { [weak self] notification in
                guard let self = self,
                      let face = notification.userInfo?["face"] as? String,
                      let index = Self.faceMaterialIndex(for: face) else { return }
                let title = notification.userInfo?["title"] as? String
                let systemImage = notification.userInfo?["systemImage"] as? String
                if let title, let systemImage {
                    self.faceOverrides[index] = (title, systemImage)
                } else {
                    self.faceOverrides.removeValue(forKey: index)
                }
                self.applyDynamicFace(at: index)
            }

            // TV Guide open/close → swap feed face icon (material[2] = -Z back = feed at yaw=-180°)
            let tvOpenToken = NotificationCenter.default.addObserver(forName: .FeedTVGuideBecameVisible, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.isTVGuideOpen = true
                self.applyFeedFaceIcon()
            }
            let tvHideToken = NotificationCenter.default.addObserver(forName: .FeedTVGuideBecameHidden, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.isTVGuideOpen = false
                self.applyFeedFaceIcon()
            }
            tvGuideObservers = [tvOpenToken, tvHideToken]
            resignActiveToken = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                self?.endBlink()
                self?.stopFlashing()
            }
            NotificationCenter.default.addObserver(forName: Notification.Name("RecordingStarted"), object: nil, queue: .main) { [weak self] _ in
                self?.view?.rendersContinuously = false
            }
            NotificationCenter.default.addObserver(forName: Notification.Name("RecordingStopped"), object: nil, queue: .main) { [weak self] _ in
                self?.restoreRendererMode()
            }
            // ML object detection → one-shot pop when camera finds something new
            NotificationCenter.default.addObserver(forName: Notification.Name("MLCubePopTrigger"), object: nil, queue: .main) { [weak self] _ in
                self?.triggerPreviewPop()
            }
        }

        deinit {
            peekTimer?.invalidate()
            peekTimer = nil
            if let token = skinChangeObserver {
                NotificationCenter.default.removeObserver(token)
                skinChangeObserver = nil
            }
            if let token = previewSimObserver {
                NotificationCenter.default.removeObserver(token)
                previewSimObserver = nil
            }
            if let token = profileIconOverrideObserver {
                NotificationCenter.default.removeObserver(token)
                profileIconOverrideObserver = nil
            }
            if let token = faceOverrideObserver {
                NotificationCenter.default.removeObserver(token)
                faceOverrideObserver = nil
            }
            if let token = resignActiveToken {
                NotificationCenter.default.removeObserver(token)
                resignActiveToken = nil
            }
            tvGuideObservers.forEach { NotificationCenter.default.removeObserver($0) }
            tvGuideObservers = []
            stopObservingMotion()
            stopObservingHold()
            stopAccelerometerSimulation()
        }

        func bindGeneratedCubeMaterials(from scene: SCNScene?) {
            guard let cube = scene?.rootNode.childNode(withName: "cube", recursively: true),
                  let box = cube.geometry as? SCNBox else {
                cubeMaterials = []
                return
            }
            cubeMaterials = box.materials
            applyAllDynamicFaces()
        }

        func setSettingsFaceActive(_ active: Bool) {
            guard active != wasOnSettingsTab else { return }
            wasOnSettingsTab = active
            if active {
                profileIconOverride = ("Settings", "gearshape.fill")
            } else {
                profileIconOverride = nil
            }
            applyCurrentProfileIconOverride()
        }

        func applyCurrentProfileIconOverride() {
            applyDynamicFace(at: 1)
        }

        func applyFeedFaceIcon() {
            applyDynamicFace(at: 0)
        }

        func applyAllDynamicFaces() {
            for index in 0...3 {
                applyDynamicFace(at: index)
            }
        }

        private static func faceMaterialIndex(for face: String) -> Int? {
            switch face.lowercased() {
            case "feed": return 0
            case "profile", "settings": return 1
            case "map": return 2
            case "camera", "record": return 3
            default: return nil
            }
        }

        private func defaultFaceSpec(for index: Int) -> (title: String, systemImage: String)? {
            switch index {
            case 0: return ("Feed",    "tv.fill")
            case 1: return ("Profile", "person.fill")
            case 2: return ("Map",     "map.fill")
            case 3: return ("Camera",  "camera.fill")
            default: return nil
            }
        }

        private func effectiveFaceSpec(for index: Int) -> (title: String, systemImage: String)? {
            if let override = faceOverrides[index] {
                return override
            }
            if index == 0, isTVGuideOpen {
                return ("TV Guide", "list.and.film")
            }
            if index == 1, let profileIconOverride {
                return profileIconOverride
            }
            return defaultFaceSpec(for: index)
        }

        private func applyDynamicFace(at index: Int) {
            guard cubeMaterials.indices.contains(index),
                  let spec = effectiveFaceSpec(for: index) else { return }
            let skin = CubeSkinStore.shared.current
            cubeMaterials[index].emission.contents = parent.faceEmissionMask(
                title: spec.title,
                systemImage: spec.systemImage,
                borderColor: skin.borderAccentColor,
                iconColor: skin.iconFillColor
            )
        }

        func setInitialYaw(for tab: AppTab) {
            let idx = tabs.firstIndex(of: tab) ?? 0
            currentIndex = idx
            currentYaw = Float(idx) * (-Float.pi / 2)
            guard let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            cube.removeAction(forKey: "peekPLogo")
            peekPitch = 0; peekActive = false
            applyCombinedRotation(to: cube)
        }

        @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
            if gesture.direction == .up, parent.selectedTab == .record {
                onSwipeUp?()
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
            } else if parent.selectedTab == .feed {
                print("[CubeTabView] Tap -> posting CubeTapped for feed")
                NotificationCenter.default.post(name: Notification.Name("CubeTapped"), object: nil)
            } else if parent.selectedTab == .profile {
                print("[CubeTabView] Tap -> posting CubeTapped for profile")
                NotificationCenter.default.post(name: Notification.Name("CubeTapped"), object: nil)
            } else {
                print("[CubeTabView] Tap ignored for tab: \(parent.selectedTab)")
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            let currentLocation = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began:
                cubeHoldLastLocation = currentLocation
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
            case .changed:
                guard let lastLocation = cubeHoldLastLocation else {
                    cubeHoldLastLocation = currentLocation
                    return
                }
                let userInfo: [String: CGFloat] = [
                    "deltaX": currentLocation.x - lastLocation.x,
                    "deltaY": currentLocation.y - lastLocation.y
                ]
                cubeHoldLastLocation = currentLocation
                NotificationCenter.default.post(name: .cubeHoldMoved, object: nil, userInfo: userInfo)
                NotificationCenter.default.post(name: Notification.Name("CameraCubeHoldMoved"), object: nil, userInfo: userInfo)
            case .ended, .cancelled, .failed:
                cubeHoldLastLocation = nil
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
                setRendererHot(true)
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

                // Cancel any active peek so pan takes full control
                if peekActive { cube.removeAction(forKey: "peekPLogo"); peekPitch = 0; peekActive = false }
                applyCombinedRotation(to: cube)

                // Clear motion lean while panning
                self.liveRotation = SCNVector3Zero
                self.liveRollYaw = 0

            case .ended, .cancelled, .failed:
                // Snap to nearest face based on currentYaw
                let targetIndex = snappedIndex(from: currentYaw)
                let targetYaw = nearestEquivalentYaw(for: targetIndex, from: currentYaw)

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

                // Reset motion lean after snap
                self.liveRotation = SCNVector3Zero
                self.liveRollYaw = 0

            default:
                break
            }
        }

        func syncToSelectedTab(_ tab: AppTab) {
            // .settings is a profile sub-screen — show the Profile face
            let resolvedTab: AppTab = (tab == .settings) ? .profile : tab
            guard let scnView = view, let _ = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            if let idx = tabs.firstIndex(of: resolvedTab), idx != currentIndex {
                let targetYaw = continuousYaw(to: idx)
                currentIndex = idx
                currentYaw = targetYaw
                animateToYaw(currentYaw)

                if resolvedTab != .feed {
                    NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                }
                if resolvedTab == .record {
                    NotificationCenter.default.post(name: Notification.Name("RecordTabBecameActive"), object: nil)
                }
            }
        }

        func resumeForCameraTab() {
            guard let scnView = view,
                  let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            scnView.isPlaying = true
            scnView.rendersContinuously = true
            if !isBlinking {
                cube.removeAction(forKey: "recordBlink")
                cube.scale = SCNVector3(1.0, 1.0, 1.0)
            }
            // Skip eulerAngles snap while a pan/bounce animation is in progress —
            // otherwise directly setting eulerAngles cancels the SCNAction and the
            // cube freezes instead of animating into the camera face.
            if !isInteracting {
                applyCombinedRotation(to: cube)
            }
        }

        private func animateToYaw(_ yaw: Float, bouncy: Bool = false) {
            guard let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            setRendererHot(true)

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
                self.restoreRendererMode()
                if isRunningInPreviews && self.parent.enablePreviewSpin {
                    let spin = SCNAction.repeatForever(SCNAction.rotateBy(x: 0, y: CGFloat.pi * 2, z: 0, duration: 8.0))
                    spin.timingMode = .linear
                    cube.runAction(spin, forKey: "previewSpin")
                }
            }

            // Use customAction with explicit quaternion construction so Z is mathematically
            // impossible (we never touch the Z axis). simdOrientation bypasses eulerAngles
            // entirely to avoid any conversion round-trip that could introduce roll.
            if bouncy {
                let overshoot: CGFloat = 0.12
                let dur1 = 0.18 * parent.rotationSpeedMultiplier
                let dur2 = 0.22 * parent.rotationSpeedMultiplier
                let startY = CGFloat(lastSetYaw)
                let midY = cgYaw + overshoot
                let action1 = SCNAction.customAction(duration: dur1) { [weak self] node, elapsed in
                    guard let self else { return }
                    let t = min(1.0, elapsed / CGFloat(dur1))
                    let e = t * t * (3 - 2 * t)
                    let y = Float(startY + (midY - startY) * e)
                    self.lastSetYaw = y
                    node.simdOrientation = simd_quatf(angle: y, axis: SIMD3<Float>(0, 1, 0))
                }
                let action2 = SCNAction.customAction(duration: dur2) { [weak self] node, elapsed in
                    guard let self else { return }
                    let t = min(1.0, elapsed / CGFloat(dur2))
                    let e = t * t * (3 - 2 * t)
                    let y = Float(midY + (cgYaw - midY) * e)
                    self.lastSetYaw = y
                    node.simdOrientation = simd_quatf(angle: y, axis: SIMD3<Float>(0, 1, 0))
                }
                cube.runAction(SCNAction.sequence([action1, action2]), completionHandler: completionBlock)
            } else {
                let dur = 0.28 * parent.rotationSpeedMultiplier
                let startY = CGFloat(lastSetYaw)
                let action = SCNAction.customAction(duration: dur) { [weak self] node, elapsed in
                    guard let self else { return }
                    let t = min(1.0, elapsed / CGFloat(dur))
                    let e = t * t * (3 - 2 * t)
                    let y = Float(startY + (cgYaw - startY) * e)
                    self.lastSetYaw = y
                    node.simdOrientation = simd_quatf(angle: y, axis: SIMD3<Float>(0, 1, 0))
                }
                cube.runAction(action, completionHandler: completionBlock)
            }
        }

        private func rotateCube(_ node: SCNNode, to index: Int, animated: Bool = true, bouncy: Bool = false) {
            let baseAngle = animated ? continuousYaw(to: index) : canonicalYaw(for: index)
            if !animated {
                currentIndex = index
                currentYaw = baseAngle
                lastSetYaw = baseAngle
                node.simdOrientation = simd_quatf(angle: baseAngle, axis: SIMD3<Float>(0, 1, 0))
                return
            }
            currentIndex = index
            currentYaw = baseAngle
            animateToYaw(currentYaw, bouncy: bouncy)
        }

        func startObservingMotion() {
            stopObservingMotion()
            if SettingsStore.shared.tiltControlEnabled {
                CubeMotionPoster.shared.start()
            }
            motionObserver = NotificationCenter.default.addObserver(forName: Notification.Name("CubeMotionUpdate"), object: nil, queue: .main) { [weak self] notif in
                guard let self,
                      let scnView = self.view,
                      let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }

                if self.isInteracting {
                    self.liveRollYaw = 0
                    return
                }

                guard SettingsStore.shared.tiltControlEnabled,
                      let roll = notif.userInfo?["roll"] as? Double else {
                    if self.liveRollYaw != 0 {
                        self.liveRollYaw = 0
                        self.applyCombinedRotation(to: cube)
                    }
                    return
                }

                // Subtle cube lean: follows device tilt, max ~12° at 45° tilt
                self.liveRollYaw = Float(-roll) * 0.27
                self.applyCombinedRotation(to: cube)

                // Tab snap when tilt exceeds ~34° with 1.5 s cooldown
                let snapThreshold: Double = 0.60
                let now = CACurrentMediaTime()
                guard abs(roll) > snapThreshold, now - self.lastTiltSnapTime > 1.5 else { return }

                self.lastTiltSnapTime = now
                // Negative roll = tilt left = previous tab; positive = tilt right = next tab
                let direction = roll < 0 ? -1 : 1
                let tabs = [AppTab.map, .record, .feed, .profile]
                let newIndex = (self.currentIndex + direction + tabs.count) % tabs.count
                self.rotateCube(cube, to: newIndex, animated: true, bouncy: true)
                self.currentIndex = newIndex
                self.parent.selectedTab = tabs[newIndex]
                self.haptic.impactOccurred(intensity: 0.9)

                let newTab = tabs[newIndex]
                if newTab != .feed {
                    NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                }
                if newTab == .record {
                    NotificationCenter.default.post(name: Notification.Name("RecordTabBecameActive"), object: nil)
                }
            }
        }

        func stopObservingMotion() {
            if let token = motionObserver {
                NotificationCenter.default.removeObserver(token)
                motionObserver = nil
            }
            liveRollYaw = 0
            CubeMotionPoster.shared.stop()
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

            // Pop sound at peak — use AVAudioPlayer via SCNAction.run to avoid the
            // SCNAction.playAudio crash when AVAudioEngine is interrupted (background or tab switch).
            let peakSound: SCNAction = SCNAction.run { [weak self] _ in
                guard let self, self.parent.selectedTab != .record else { return }
                DispatchQueue.main.async { self.playPopSafely() }
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

        private func playPopSafely() {
            guard let player = popAVPlayer else { return }
            guard PoplurEQSync.shared.shouldPlayTransientSound(minimumInterval: 0.16) else { return }
            if player.isPlaying { player.stop() }
            player.currentTime = 0
            player.play()
        }

        // MARK: - Flash/Torch Illumination
        
        /// Start illuminating cube when flashlight is ON - makes icons glow from within
        private func startFlashing() {
            guard let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            
            // Stop any existing flash animation
            cube.removeAction(forKey: "flashGlow")
            
            print("💡 [CubeTabView] Starting flash - boosting emission intensity")
            
            // IMPORTANT: Don't change emission.contents - it contains the mask image!
            // Instead, just boost the intensity to make the EXISTING icons glow brighter
            
            // Warm flashlight color for emission tint
            _ = UIColor(red: 1.0, green: 0.95, blue: 0.85, alpha: 1.0)
            
            // Apply to all cube face materials
            for material in cubeMaterials {
                // Boost emission intensity dramatically to make icons glow
                material.emission.intensity = 2.5 // Much brighter
            }
            
            // Add subtle pulsing animation by varying the intensity
            let brighten = SCNAction.customAction(duration: 1.2) { [weak self] node, elapsed in
                guard let self = self else { return }
                let progress = elapsed / 1.2
                // Pulse intensity between 2.0 and 3.0
                let baseIntensity: CGFloat = 2.5
                let pulseAmount: CGFloat = 0.5
                let intensity = baseIntensity + (sin(progress * .pi * 2) * pulseAmount)
                
                for material in self.cubeMaterials {
                    material.emission.intensity = intensity
                }
            }
            
            let forever = SCNAction.repeatForever(brighten)
            cube.runAction(forever, forKey: "flashGlow")
            
            print("✨ [CubeTabView] Cube icons glowing at intensity 2.5-3.0 (flash ON)")
        }
        
        /// Stop illuminating cube when flashlight is OFF - return to normal
        private func stopFlashing() {
            guard let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            
            print("🔦 [CubeTabView] Stopping flash - restoring normal emission")
            
            // Stop glow animation
            cube.removeAction(forKey: "flashGlow")
            
            // Restore original emission settings over 0.4 seconds
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.4
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
            
            for material in cubeMaterials {
                // DON'T change emission.contents - keep the mask!
                // Just restore normal intensity
                material.emission.intensity = 0.5
            }
            
            SCNTransaction.commit()
            
            print("💤 [CubeTabView] Cube returned to normal emission intensity (flash OFF)")
        }

        private func startPeriodicPLogoTimer() {
            // Peek animation disabled — cube must not rotate on X/Z axis
            peekTimer?.invalidate()
            peekTimer = nil
        }

        private func triggerPLogoPeek() {
            // Disabled — X-axis tilt is not permitted
        }

        private func refreshMaterialsForSkinChange() {
            guard let scnView = view,
                  let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true),
                  let box = cube.geometry as? SCNBox else { return }
            CubeFaceImageCache.clearSkinCache()
            var mats = parent.makeMaterials(baseColor: parent.baseColor)
            let elementCount = box.elementCount
            if elementCount > mats.count {
                let edgeMat = parent.makeChamferEdgeMaterial()
                while mats.count < elementCount { mats.append(edgeMat) }
            }
            box.materials = mats
            cubeMaterials = mats
            applyAllDynamicFaces()
            scnView.isPlaying = true
        }

        private func applyCombinedRotation(to node: SCNNode) {
            lastSetYaw = currentYaw
            // Cube only rotates on Y — no X/Z tilt permitted
            let qY = simd_quatf(angle: currentYaw + liveRollYaw, axis: SIMD3<Float>(0, 1, 0))
            node.simdOrientation = qY
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
            setRendererHot(true)
            
            let shouldPlaySound = parent.previewPopSoundEnabled
            
            // Adjusted: slow the one-shot pop
            let up = SCNAction.scale(to: 1.12, duration: 0.35)
            up.timingMode = .easeInEaseOut
            let down = SCNAction.scale(to: 1.0, duration: 0.40)
            down.timingMode = .easeInEaseOut
            let restore = SCNAction.run { [weak self] _ in self?.restoreRendererMode() }
            cube.runAction(SCNAction.sequence([up, down, restore]), forKey: "previewPop")
            
            if shouldPlaySound {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.playPopSafely()
                }
            }
        }

        enum YawDirection { case left, right }
        func applyYaw(steps: Int, direction: YawDirection) {
            guard steps != 0, let scnView = view, let cube = scnView.scene?.rootNode.childNode(withName: "cube", recursively: true) else { return }
            setRendererHot(true)
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
                self.restoreRendererMode()
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
    
    @State private var exportMessage: String = ""
    @State private var showExportAlert: Bool = false

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
                    
                    Divider()
                    
                    // Export Controls
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Export Cube Faces").font(.headline)
                        
                        HStack(spacing: 10) {
                            Button("Export to Photos") {
                                CubeFaceExporter.exportToPhotos(baseColor: base) { result in
                                    switch result {
                                    case .success(let count):
                                        exportMessage = "✅ Saved \(count) images to Photos"
                                        showExportAlert = true
                                    case .failure(let error):
                                        exportMessage = "❌ Error: \(error.localizedDescription)"
                                        showExportAlert = true
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            
                            Button("Export to Files") {
                                let urls = CubeFaceExporter.exportToFiles(baseColor: base)
                                exportMessage = "✅ Saved \(urls.count) images\n\nPaths logged to console"
                                showExportAlert = true
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Text("Exports 3 variants per tab:\n• Full Face\n• Emission Mask\n• Background Only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .alert("Export Complete", isPresented: $showExportAlert) {
                        Button("OK") { }
                    } message: {
                        Text(exportMessage)
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
        PoplurEQSync.shared.configureAudioSession(for: .ambientPlayback)
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
