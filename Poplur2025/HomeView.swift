import SwiftUI
import CoreLocation
import AVFoundation
import SceneKit
import CoreMotion

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

@MainActor
final class SceneMotionController: ObservableObject {
    private let motion = CMMotionManager()

    func start() {
        guard motion.isDeviceMotionAvailable else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 60.0
        motion.startDeviceMotionUpdates(to: .main) { data, _ in
            guard let attitude = data?.attitude else { return }
            let userInfo: [String: Double] = [
                "roll": attitude.roll,
                "pitch": attitude.pitch,
                "yaw": attitude.yaw
            ]
            NotificationCenter.default.post(name: .CubeMotionUpdate, object: nil, userInfo: userInfo)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }
}

struct HomeView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase

    // Start on record for camera-first testing
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

    @StateObject private var motionController = SceneMotionController()

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
            CameraPreviewHost(controller: cameraController, coordinate: locationProvider.coordinate)
                .ignoresSafeArea()
        }
        .task {
            ensureCameraRunningIfNeeded()
        }
        .onAppear {
            ensureCameraRunningIfNeeded()
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
            }
            .padding(.bottom, 28)
            .ignoresSafeArea(edges: .bottom)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        // Detect swipe down; settings no longer accessible via tab
                        if value.translation.height > 20, selectedTab == .profile {
                            // No-op: settings access removed from tab navigation
                        }
                    }
            )
            
            if selectedTab == .profile {
                VStack {
                    Spacer()
                    ArrowDownPrompt()
                        .frame(height: 80)
                        .padding(.bottom, 100)
                }
                .transition(.opacity)
            }
        }
        .task {
            // Removed motionController.start() here per instructions
            
            // Minimal bootstrap: start location early (cheap) and trigger feed load if feed is initial tab
            await cameraController.prewarm()
            await cameraController.preparePreviewIfNeeded()
            locationProvider.request()
            if selectedTab == .feed, !didTriggerFeedInitialLoad {
                didTriggerFeedInitialLoad = true
                NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
            }
            if selectedTab != .feed {
                NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
            }
        }
        .onAppear {
            // Removed motionController.start() here per instructions
            
            // Keep startup minimal; no mass notifications
            locationProvider.request()
            if selectedTab == .feed, !didTriggerFeedInitialLoad {
                didTriggerFeedInitialLoad = true
                NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
            }
            if selectedTab != .feed {
                NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
            }
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
            if selectedTab == .feed {
                NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil) // optional: clear lingering players before resuming
            } else {
                NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
            }
            // Start motion when cube overlay is visible (always shown) and app is active; stop on other tabs if desired
            if selectedTab == .record {
                motionController.start()
            } else {
                motionController.stop()
            }
            NotificationCenter.default.post(name: .ResetTabToTop, object: nil)
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
                // Resume motion only on Record tab
                if selectedTab == .record { motionController.start() }
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
        }
    }
}

struct ArrowDownPrompt: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        let scene = SCNScene()
        view.scene = scene
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        // Simple arrow using a pyramid and a box to suggest a down arrow
        let arrowNode = SCNNode()

        let shaft = SCNBox(width: 0.06, height: 0.16, length: 0.02, chamferRadius: 0.01)
        let shaftNode = SCNNode(geometry: shaft)
        shaftNode.position = SCNVector3(0, 0.06, 0)

        let head = SCNPyramid(width: 0.14, height: 0.10, length: 0.02)
        let headNode = SCNNode(geometry: head)
        headNode.position = SCNVector3(0, -0.02, 0)
        headNode.eulerAngles.x = .pi // point down

        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.emission.contents = UIColor.white
        shaft.materials = [material]
        head.materials = [material]

        arrowNode.addChildNode(shaftNode)
        arrowNode.addChildNode(headNode)
        scene.rootNode.addChildNode(arrowNode)

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0.1, 0.6)
        scene.rootNode.addChildNode(cameraNode)

        // Subtle animation to draw attention
        let moveDown = SCNAction.moveBy(x: 0, y: -0.02, z: 0, duration: 0.6)
        moveDown.timingMode = .easeInEaseOut
        let moveUp = moveDown.reversed()
        let sequence = SCNAction.sequence([moveDown, moveUp])
        let repeatForever = SCNAction.repeatForever(sequence)
        arrowNode.runAction(repeatForever)

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

