import SwiftUI
import CoreLocation
import AVFoundation
import SceneKit
import CoreMotion
import Combine

extension Notification.Name {
    static let ResetTabToTop = Notification.Name("ResetTabToTop")
}

extension Notification.Name {
    static let CubeMotionUpdate = Notification.Name("CubeMotionUpdate")
}

extension Notification.Name {
    static let FeedReady = Notification.Name("FeedReady")
}

extension Notification.Name {
    static let PauseFeedAudio = Notification.Name("PauseFeedAudio")
    static let ResumeFeedAudio = Notification.Name("ResumeFeedAudio")
}

extension Notification.Name {
    static let CenterMapOnUser = Notification.Name("CenterMapOnUser")
}

struct HomeCameraPreviewHost: UIViewControllerRepresentable {
    @ObservedObject var controller: CameraKitController

    func makeUIViewController(context: Context) -> UIViewController {
        // Ensure the controller prepares its preview
        controller.preparePreviewIfNeeded()
        return controller.recordPreviewViewController ?? controller.previewViewController ?? UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No-op; preview controller is managed by CameraKitController
    }
}

@MainActor
final class SceneMotionController: ObservableObject {
    private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        motion.startDeviceMotionUpdates(to: queue) { [weak self] data, _ in
            guard let attitude = data?.attitude else { return }
            let userInfo: [String: Double] = [
                "roll": attitude.roll,
                "pitch": attitude.pitch,
                "yaw": attitude.yaw
            ]
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .CubeMotionUpdate, object: nil, userInfo: userInfo)
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }
}

struct HomeView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.renderingConfig) private var renderingConfig

    // Start on map tab instead of record tab
    @State private var selectedTab: AppTab = .record

    // Location only when needed
    @StateObject private var locationProvider = LocationProvider()

    // Use injected, shared camera controller (prewarmed in App)
    @ObservedObject var cameraController: CameraKitController

    // One-time flags to avoid doing heavy work repeatedly
    @State private var didTriggerFeedInitialLoad = false
    @State private var didTriggerMapInitialLoad = false
    @State private var didTriggerProfileInitialLoad = false
    @State private var didStartCameraOnce = false
    @State private var isFeedReady: Bool = false
    @State private var enableLowerHitArea: Bool = false
    @State private var didPrewarmSceneKit = false

    @StateObject private var motionController = SceneMotionController()
    @StateObject private var cubeTouchConfig = CubeTouchConfiguration()
    
    init(cameraController: CameraKitController) {
        self.cameraController = cameraController

        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = .clear
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        UITabBar.appearance().isTranslucent = true
    }

    @ViewBuilder
    private var mapTabContent: some View {
        MapView()
            .task {
                if selectedTab == .map, !didTriggerMapInitialLoad {
                    didTriggerMapInitialLoad = true
                    NotificationCenter.default.post(name: .LoadMapNow, object: nil)
                }
            }
            .onAppear {
                if selectedTab == .map, !didTriggerMapInitialLoad {
                    didTriggerMapInitialLoad = true
                    NotificationCenter.default.post(name: .LoadMapNow, object: nil)
                }
            }
    }

    @ViewBuilder
    private var recordTabContent: some View {
        ZStack {
            HomeCameraPreviewHost(controller: cameraController)
                .ignoresSafeArea()
        }
        .task {
            let t0 = CFAbsoluteTimeGetCurrent()
            // Small delay to allow overlay UI to render before heavy camera work
            try? await Task.sleep(nanoseconds: 60_000_000)
            await cameraController.start()
            let dt = CFAbsoluteTimeGetCurrent() - t0
            print("[Camera] start() took \(dt)s")
        }
        .onAppear {
            Task { @MainActor in
                let t0 = CFAbsoluteTimeGetCurrent()
                try? await Task.sleep(nanoseconds: 40_000_000)
                await cameraController.startPreview()
                let dt = CFAbsoluteTimeGetCurrent() - t0
                print("[Camera] startPreview() took \(dt)s")
            }
        }
    }

    private func ensureCameraRunningIfNeeded() {
        Task { @MainActor in
            guard selectedTab == .record else {
                return
            }
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            switch status {
            case .authorized:
                if !cameraController.isReady {
                    await cameraController.startPreview()
                }
            case .notDetermined:
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted {
                    if !cameraController.isReady {
                        await cameraController.start()
                    }
                }
            default:
                // denied or restricted — optionally present guidance UI
                break
            }
        }
    }

    @ViewBuilder
    private var feedTabContent: some View {
        FeedView()
            .task {
                if selectedTab == .feed {
                    if !didTriggerFeedInitialLoad {
                        didTriggerFeedInitialLoad = true
                        NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                    }
                }
            }
            .onAppear {
                if selectedTab == .feed {
                    if !didTriggerFeedInitialLoad {
                        didTriggerFeedInitialLoad = true
                        NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                    }
                }
            }
            .onDisappear {
                // Ensure all feed players stop when leaving Feed tab view hierarchy
                NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
            }
    }

    @ViewBuilder
    private var profileTabContent: some View {
        ProfileView()
            .task {
                if selectedTab == .profile, !didTriggerProfileInitialLoad {
                    didTriggerProfileInitialLoad = true
                    NotificationCenter.default.post(name: .LoadProfileNow, object: nil)
                }
            }
            .onAppear {
                if selectedTab == .profile, !didTriggerProfileInitialLoad {
                    didTriggerProfileInitialLoad = true
                    NotificationCenter.default.post(name: .LoadProfileNow, object: nil)
                }
            }
            .onDisappear {
                NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
            }
    }

    var body: some View {
        ZStack {
            // Content switching by selectedTab (replaces TabView)
            Group {
                switch selectedTab {
                case .map:
                    mapTabContent
                case .record:
                    recordTabContent
                case .feed:
                    feedTabContent
                case .profile:
                    profileTabContent
                @unknown default:
                    feedTabContent
                }
            }
            // 3D Cube tab control overlay
            VStack {
                Spacer()
                CubeTabView(selectedTab: $selectedTab, onSwipeUp: {
                    if selectedTab == .record {
                        NotificationCenter.default.post(name: Notification.Name("TriggerCameraCapture"), object: nil)
                    } else {
                        NotificationCenter.default.post(name: Notification.Name("ShowRecordCaptureUI"), object: nil)
                    }
                })
                .tint(.white)
                .transition(.opacity)
                .padding(.trailing, 4) // Changed from 8 to 4 as per instructions
                .onTapGesture {
                    NotificationCenter.default.post(name: .CenterMapOnUser, object: nil)
                }
                .simultaneousGesture(
                    TapGesture()
                        .onEnded {
                            print("[CubeTabView] tap")
                        }
                )
            }
            .padding(.bottom, 24)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(true)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        // Detect swipe down; settings no longer accessible via tab
                        if value.translation.height > 20, selectedTab == .profile {
                            // No-op: settings access removed from tab navigation
                        }
                    }
            )
            
            #if DEBUG
            // Invisible hit area temporarily disabled for input testing
            // (Re-enable after verifying CubeTabView touch responsiveness)
            #else
            if enableLowerHitArea {
                // Invisible hit area to detect touches in the lower third of the screen
                VStack {
                    Spacer()
                    GeometryReader { geo in
                        let height = geo.size.height
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(height: height / 2) // lower half of the screen
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let boost: CGFloat = 1.35
                                        let boosted = CGSize(width: value.translation.width * boost,
                                                             height: value.translation.height * boost)
                                        NotificationCenter.default.post(name: Notification.Name("CubeGlobalDragChanged"), object: nil, userInfo: [
                                            "location": NSValue(cgPoint: value.location),
                                            "translation": NSValue(cgSize: boosted)
                                        ])
                                    }
                                    .onEnded { value in
                                        let boost: CGFloat = 1.35
                                        let boosted = CGSize(width: value.translation.width * boost,
                                                             height: value.translation.height * boost)
                                        NotificationCenter.default.post(name: Notification.Name("CubeGlobalDragEnded"), object: nil, userInfo: [
                                            "location": NSValue(cgPoint: value.location),
                                            "translation": NSValue(cgSize: boosted)
                                        ])
                                    }
                            )
                            .simultaneousGesture(
                                TapGesture()
                                    .onEnded {
                                        NotificationCenter.default.post(name: Notification.Name("CubeGlobalTap"), object: nil)
                                    }
                            )
                            .onTapGesture {
                                NotificationCenter.default.post(name: .CenterMapOnUser, object: nil)
                            }
                            .ignoresSafeArea(edges: .bottom)
                    }
                    .frame(height: 1) // GeometryReader expands; constrain with container
                }
                .allowsHitTesting(true)
                .transition(.opacity)
            }
            #endif
        }
        .task {
            // Removed cameraController.prewarm() and preparePreviewIfNeeded() here per instructions
            
            // Minimal bootstrap: start location early (cheap) and trigger feed load if feed is initial tab
            locationProvider.request()
            if selectedTab == .feed, !didTriggerFeedInitialLoad {
                didTriggerFeedInitialLoad = true
                NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
            }
            if selectedTab != .feed {
                NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
            }
            if selectedTab == .profile {
                NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
            }
        }
        .onAppear {
            let appearT0 = CFAbsoluteTimeGetCurrent()
            print("[HomeView] onAppear at t=\(appearT0)")
            // Removed cameraController.prewarm() and preparePreviewIfNeeded() here per instructions
            
            // Keep startup minimal; no mass notifications
            locationProvider.request()
            if selectedTab == .feed, !didTriggerFeedInitialLoad {
                didTriggerFeedInitialLoad = true
                NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
            }
            if selectedTab != .feed {
                NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
            }
            if selectedTab == .profile {
                NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                enableLowerHitArea = true
            }
            
            if !didPrewarmSceneKit {
                didPrewarmSceneKit = true
                // Prewarm a tiny offscreen SCNView to compile pipelines early
                DispatchQueue.global(qos: .userInitiated).async {
                    let tmpView = SCNView(frame: .init(x: 0, y: 0, width: 1, height: 1))
                    tmpView.scene = SCNScene()
                    tmpView.antialiasingMode = .none
                    tmpView.isPlaying = true
                    // Prepare a minimal node to trigger geometry/material setup
                    let box = SCNBox(width: 0.01, height: 0.01, length: 0.01, chamferRadius: 0)
                    let node = SCNNode(geometry: box)
                    tmpView.scene?.rootNode.addChildNode(node)
                    tmpView.prepare([box], completionHandler: { _ in
                        // Drop reference after preparation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            _ = tmpView // keep alive briefly
                        }
                    })
                }
            }
            
            print("[HomeView] onAppear work took \(CFAbsoluteTimeGetCurrent() - appearT0)s")
        }
        .onChange(of: selectedTab) { _ in
            if !([AppTab.map, .record, .feed, .profile].contains(selectedTab)) {
                selectedTab = .feed
            }
            // Pause/resume feed audio based on visibility
            if selectedTab == .feed {
                NotificationCenter.default.post(name: .ResumeFeedAudio, object: nil)
            } else {
                NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
            }
            // Motion is managed by scene phase now (runs on all tabs when active)
            
            if selectedTab == .profile {
                cameraController.stop()
            }
            NotificationCenter.default.post(name: .ResetTabToTop, object: nil)

            if selectedTab == .record {
                Task { @MainActor in
                    let t0 = CFAbsoluteTimeGetCurrent()
                    await cameraController.prewarm()
                    let t1 = CFAbsoluteTimeGetCurrent()
                    print("[Camera] prewarm() took \(t1 - t0)s")
                    await cameraController.preparePreviewIfNeeded()
                    let t2 = CFAbsoluteTimeGetCurrent()
                    print("[Camera] preparePreviewIfNeeded() took \(t2 - t1)s")
                }
            }
        }
        .onChange(of: auth.isAuthenticated) { authed in
            if authed {
                selectedTab = .feed
                if !didTriggerFeedInitialLoad {
                    didTriggerFeedInitialLoad = true
                    NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                // Start motion on all tabs when app becomes active, with a slight delay
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    motionController.start()
                }
            case .background, .inactive:
                cameraController.stop()
                didStartCameraOnce = false
                motionController.stop()
                // Ensure feed audio is paused when app not active
                NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
                NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
            @unknown default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .FeedReady)) { _ in
            isFeedReady = true
            print("[Feed] ready received at \(Date())")
        }
        .onReceive(NotificationCenter.default.publisher(for: .CubeMotionUpdate)) { _ in
            // Motion updates silenced
        }
    }
}
struct ArrowDownPrompt: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        // Reuse a static scene to avoid reallocating nodes/materials per view
        struct SharedScene {
            static let scene: SCNScene = {
                let scene = SCNScene()

                // Arrow node tree
                let arrowNode = SCNNode()

                let shaft = SCNBox(width: 0.06, height: 0.16, length: 0.02, chamferRadius: 0.01)
                let head = SCNPyramid(width: 0.14, height: 0.10, length: 0.02)

                // Single shared material
                let material = SCNMaterial()
                material.diffuse.contents = UIColor.white
                material.emission.contents = UIColor.white
                material.lightingModel = .constant
                shaft.materials = [material]
                head.materials = [material]

                let shaftNode = SCNNode(geometry: shaft)
                shaftNode.position = SCNVector3(0, 0.06, 0)
                let headNode = SCNNode(geometry: head)
                headNode.position = SCNVector3(0, -0.02, 0)
                headNode.eulerAngles.x = .pi

                arrowNode.addChildNode(shaftNode)
                arrowNode.addChildNode(headNode)
                scene.rootNode.addChildNode(arrowNode)

                // Camera (orthographic-ish simple camera)
                let cameraNode = SCNNode()
                let camera = SCNCamera()
                camera.usesOrthographicProjection = false
                cameraNode.camera = camera
                cameraNode.position = SCNVector3(0, 0.1, 0.6)
                scene.rootNode.addChildNode(cameraNode)

                // Prepare geometry asynchronously to warm GPU/CPU pipelines
                scene.rootNode.flattenedClone() // encourage early geometry preparation
                scene.isPaused = false

                // Animate after scene is ready
                let moveDown = SCNAction.moveBy(x: 0, y: -0.02, z: 0, duration: 0.6)
                moveDown.timingMode = .easeInEaseOut
                let moveUp = moveDown.reversed()
                let sequence = SCNAction.sequence([moveDown, moveUp])
                let repeatForever = SCNAction.repeatForever(sequence)
                arrowNode.runAction(repeatForever)

                return scene
            }()
        }

        let view = SCNView()
        view.scene = SharedScene.scene
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.antialiasingMode = .none
        view.preferredFramesPerSecond = 30
        view.isPlaying = true

        // Ask SceneKit to prepare resources asynchronously for faster first frame
        if let scene = view.scene {
            view.prepare([scene], completionHandler: { _ in })
        }

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

