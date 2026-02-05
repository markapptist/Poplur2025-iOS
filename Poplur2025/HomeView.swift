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

    // Start on Feed
    @State private var selectedTab: AppTab = .feed

    // Location only when needed
    @StateObject private var locationProvider = LocationProvider()

    // Use injected, shared camera controller (prewarmed in App)
    @ObservedObject var cameraController: CameraKitController

    // One-time flags to avoid doing heavy work repeatedly
    @State private var didTriggerFeedInitialLoad = false
    @State private var didTriggerMapInitialLoad = false
    @State private var didTriggerProfileInitialLoad = false
    @State private var didStartCameraOnce = false

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
                 
                }
            }
            .onAppear {
                if selectedTab == .map, !didTriggerMapInitialLoad {
                    didTriggerMapInitialLoad = true
                   
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
            Task { @MainActor in
                guard selectedTab == .record else { return }
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                if status == .authorized, !cameraController.isReady {
                    await cameraController.start()
                }
            }
        }
        .onAppear {
            Task { @MainActor in
                guard selectedTab == .record else { return }
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                if status == .authorized, !cameraController.isReady {
                    await cameraController.start()
                }
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
                case .settings:
                    AppSettingsView()
                }
            }
            // 3D Cube tab control overlay
            VStack {
                Spacer()
                CubeTabView(selectedTab: $selectedTab, onSwipeUp: {
                    if selectedTab == .settings {
                        // Swipe up on settings returns to profile
                        withAnimation { selectedTab = .profile }
                    } else if selectedTab == .record {
                        // On record tab, swipe triggers capture
                        NotificationCenter.default.post(name: Notification.Name("TriggerCameraCapture"), object: nil)
                    } else {
                        // Default: keep existing behavior if needed
                        NotificationCenter.default.post(name: Notification.Name("ShowRecordCaptureUI"), object: nil)
                    }
                })
                .tint(.white)
                .padding(.bottom, 28)
            }
            .ignoresSafeArea(edges: .bottom)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        // Detect swipe down
                        if value.translation.height > 20, selectedTab == .profile {
                            withAnimation { selectedTab = .settings }
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
        .background(Color.clear)
        .task {
            motionController.start()
            // Minimal bootstrap: start location early (cheap) and trigger feed load if feed is initial tab
            locationProvider.request()
            if selectedTab == .feed, !didTriggerFeedInitialLoad {
                didTriggerFeedInitialLoad = true
                NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
            }
        }
        .onAppear {
            motionController.start()
            // Keep startup minimal; no mass notifications
            locationProvider.request()
            if selectedTab == .feed, !didTriggerFeedInitialLoad {
                didTriggerFeedInitialLoad = true
                NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
            }
        }
        .onChange(of: selectedTab) { _ in
            // Only reset-to-top on tab changes; no mass loads
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
                // No-op; we’ll lazily start heavy work when tabs appear
                break
            case .background, .inactive:
                cameraController.stop()
                didStartCameraOnce = false
                motionController.stop()
            @unknown default:
                break
            }
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

