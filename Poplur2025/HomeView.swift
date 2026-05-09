import SwiftUI
import CoreLocation
import AVFoundation
@preconcurrency import SceneKit
import CoreMotion
import Combine
import AudioToolbox
import Foundation

private enum PreviewEnvHomeView {
    static var isPreview: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || env["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
    }
}

// Preview tab enum for environment
enum PreviewAppTab: Hashable, CaseIterable {
    case map, record, feed, profile
}

// Verified: no references to deprecated map2 remain.

// Usage elsewhere:
// @Environment(\.isometricRadiusBarDistance) private var isometricRadiusBarDistance
// Use `isometricRadiusBarDistance` to position your isometric radius bar from the screen center
// Or use the shared settings object:
// @Environment(\.isometricBarSettings) private var barSettings
// barSettings.horizontalOffset / barSettings.bottomOffset

// Shared model for the isometric bar radius value
final class IsometricBarModel: ObservableObject {
    @Published var radius: Double
    init(radius: Double = 0) { self.radius = radius }
}

private struct IsometricBarModelKey: EnvironmentKey {
    static let defaultValue: IsometricBarModel = IsometricBarModel()
}

// Deprecated: prefer using `isometricBarSettings.horizontalOffset` and `.bottomOffset`
private struct IsometricRadiusBarDistanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 2000 // default distance in points; adjust as needed
}

private struct HomeViewIsPreviewRuntimeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct PreviewSelectedTabKey: EnvironmentKey {
    static let defaultValue: PreviewAppTab = .feed
}

extension EnvironmentValues {

    var isometricRadiusBarDistance: CGFloat {
        get { self[IsometricRadiusBarDistanceKey.self] }
        set { self[IsometricRadiusBarDistanceKey.self] = newValue }
    }

    var isometricBarModel: IsometricBarModel {
        get { self[IsometricBarModelKey.self] }
        set { self[IsometricBarModelKey.self] = newValue }
    }
    
    var homeViewIsPreviewRuntime: Bool {
        get { self[HomeViewIsPreviewRuntimeKey.self] }
        set { self[HomeViewIsPreviewRuntimeKey.self] = newValue }
    }
    
    var previewSelectedTab: PreviewAppTab {
        get { self[PreviewSelectedTabKey.self] }
        set { self[PreviewSelectedTabKey.self] = newValue }
    }
}

// One-time SceneKit prewarmer to avoid first-frame stalls
private enum HomeSceneKitPrewarmer {
    private static var didPrewarm: Bool = false

    static func prewarmIfNeeded() async {
        if didPrewarm { return }
        didPrewarm = true

        // Build a tiny scene off-main
        let scene = SCNScene()
        let box = SCNBox(width: 0.01, height: 0.01, length: 0.01, chamferRadius: 0)
        let mat = SCNMaterial()
        mat.lightingModel = .physicallyBased
        box.materials = [mat]
        let node = SCNNode(geometry: box)
        scene.rootNode.addChildNode(node)

        // 1) Offscreen renderer path (no view)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let device = MTLCreateSystemDefaultDevice()
                let renderer = SCNRenderer(device: device, options: nil)
                renderer.scene = scene
                renderer.render(atTime: 0)
                cont.resume()
            }
        }

        // 2) Tiny SCNView path to exercise view-based code
        await MainActor.run {
            let tmpView = SCNView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
            tmpView.antialiasingMode = .none
            tmpView.isPlaying = false
            tmpView.scene = scene
            tmpView.prepare([box], completionHandler: { _ in })
        }
    }
}

struct HomeCameraPreviewHost: UIViewControllerRepresentable {
    @ObservedObject var controller: CameraKitController

    func makeUIViewController(context: Context) -> UIViewController {
        // Removed controller.preparePreviewIfNeeded() per instructions
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
    
    @Environment(\.homeViewIsPreviewRuntime) private var isPreviewRuntime
    @Environment(\.previewSelectedTab) private var previewSelectedTab
    
    // Changed per instructions to use EnvironmentObject
    @EnvironmentObject private var isometricBarSettings: IsometricBarSettings
    
    // Start on feed tab instead of record tab
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
    @State private var isFeedReady: Bool = false
    @State private var enableLowerHitArea: Bool = false
    @State private var didPrewarmSceneKit = false
    @State private var showBarTuner: Bool = false
    @State private var didApplyDefaultBarSettings = false
    
    // Shared radius model controlling the global isometric bar value across all tabs
    @StateObject private var isometricBarModel = IsometricBarModel(radius: 0)
    
    @StateObject private var motionController = SceneMotionController()
    @StateObject private var cubeTouchConfig = CubeTouchConfiguration()
    
    @State private var recordHoldTask: Task<Void, Never>? = nil
    @State private var isRecordHolding: Bool = false
    
    // Added state for cube yaw angle
    @State private var cubeYawDegrees: Double = 0
    
    // Added per instruction to gate animations
    @State private var isSceneKitReady: Bool = false

    private let launchGate = LaunchGate.shared
    
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
        // LOCKED: MapViewProduction is the ONLY map view used in production.
        // DO NOT replace with any other map view (MapView, MapView_PreviewAlt, etc.)
        // MapViewProduction provides:
        // - Hybrid map style with realistic 3D elevation
        // - AI recommendations overlay
        // - Navigation controls (places list, address search)
        // - Optimized camera with 60° pitch at 700m distance
        MapViewProduction()
            .task {
                if selectedTab == .map, !didTriggerMapInitialLoad {
                    deferUntilAfterLaunch {
                        await MainActor.run {
                            didTriggerMapInitialLoad = true
                            NotificationCenter.default.post(name: .LoadMapNow, object: nil)
                            locationProvider.request()
                        }
                    }
                }
            }
    }
    
    @ViewBuilder
    private var recordTabContent: some View {
        ZStack {
            HomeCameraPreviewHost(controller: cameraController)
                .ignoresSafeArea()
            
            // Animated instructional text overlay
            CameraInstructionsOverlay()
                .allowsHitTesting(false)
        }
        .onAppear {
            Task { @MainActor in
                // Removed guard !PreviewEnvHomeView.isPreview else { return }
                guard selectedTab == .record else { return }
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                switch status {
                case .authorized:
                    if !cameraController.isReady {
                        await cameraController.startPreview()
                    }
                case .notDetermined:
                    // Do not prompt on appear; let user interaction trigger request
                    break
                default:
                    break
                }
            }
        }
    }
    
    private func ensureCameraRunningIfNeeded() {
        Task { @MainActor in
            guard !PreviewEnvHomeView.isPreview else { return }
            guard selectedTab == .record, isRecordHolding else {
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

    private func deferUntilAfterLaunch(_ work: @escaping @Sendable () async -> Void) {
        launchGate.afterGate(work)
    }
    
    private func startRecordHoldRamp() {
        recordHoldTask?.cancel()
        let maxMeters: Double = 3_323_000.0
        let duration: Double = 10.0 // seconds to reach max
        let start = isometricBarModel.radius
        let t0 = CACurrentMediaTime()
        recordHoldTask = Task { @MainActor in
            while !Task.isCancelled && isRecordHolding && selectedTab == .record {
                let t = min(1.0, (CACurrentMediaTime() - t0) / duration)
                let eased = t * t * (3 - 2 * t) // smoothstep ease-in-out
                let next = start + (maxMeters - start) * eased
                isometricBarModel.radius = min(maxMeters, next)
                try? await Task.sleep(nanoseconds: 16_000_000) // ~60fps
            }
        }
    }

    private func stopRecordHoldRamp(reset: Bool) {
        recordHoldTask?.cancel()
        recordHoldTask = nil
        if reset {
            withAnimation(.easeOut(duration: 0.35)) {
                isometricBarModel.radius = 0
            }
            NotificationCenter.default.post(name: .SharedRadiusDidChange, object: nil, userInfo: ["radius": 0.0])
        }
    }
    
    // MARK: - Helper rotation logic for cube yaw and tab switching
    
    private enum RotationDirection { case left, right }
    
    private func yawForTab(_ tab: AppTab) -> Double {
        // Define faces: record=0°, feed=90°, profile=180°, map=270°
        switch tab {
        case .record: return 0
        case .feed: return 90
        case .profile: return 180
        case .map: return 270
        @unknown default: return 0
        }
    }
    
    private func normalizedDelta(from current: Double, to target: Double, prefer direction: RotationDirection?) -> Double {
        // Compute shortest delta in [-180, 180]
        var delta = fmod(target - current + 540, 360) - 180
        if let dir = direction {
            // Force direction if provided
            if dir == .left && delta > 0 { delta -= 360 }
            if dir == .right && delta < 0 { delta += 360 }
        }
        return delta
    }
    
    private func animateYaw(to targetYaw: Double, duration: Double = 0.45, direction: RotationDirection? = nil) {
        let current = cubeYawDegrees.truncatingRemainder(dividingBy: 360)
        let delta = normalizedDelta(from: current, to: targetYaw, prefer: direction)
        let final = current + delta
        if isSceneKitReady {
            withAnimation(.timingCurve(0.2, 0.8, 0.2, 1.0, duration: duration)) {
                cubeYawDegrees = final
            }
        } else {
            cubeYawDegrees = final
        }
    }
    
    private func nextTab(from tab: AppTab) -> AppTab {
        switch tab {
        case .map: return .record
        case .record: return .feed
        case .feed: return .profile
        case .profile: return .map
        @unknown default: return .feed
        }
    }
    
    private func previousTab(from tab: AppTab) -> AppTab {
        switch tab {
        case .map: return .profile
        case .record: return .map
        case .feed: return .record
        case .profile: return .feed
        @unknown default: return .feed
        }
    }
    
    private func rotateCube(to newTab: AppTab, direction: RotationDirection) {
        let targetYaw = yawForTab(newTab)
        animateYaw(to: targetYaw, duration: 0.45, direction: direction)
        selectedTab = newTab
    }
    
    @ViewBuilder
    private var feedTabContent: some View {
        FeedView()
            .task {
                if selectedTab == .feed, !didTriggerFeedInitialLoad {
                    deferUntilAfterLaunch {
                        await MainActor.run {
                            didTriggerFeedInitialLoad = true
                            NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                        }
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
        let resolvedUserID: String = {
            // Try to discover a plausible user id without requiring a concrete API on AuthViewModel.
            let modelMirror = Mirror(reflecting: auth)

            // 1) Look for a child named `currentUserID`, `userID`, or `uid` directly on the auth model
            let commonIDKeys = ["currentUserID", "userID", "uid", "id"]
            for key in commonIDKeys {
                if let child = modelMirror.children.first(where: { $0.label == key }) {
                    if let id = child.value as? String { return id }
                    if let idOpt = child.value as? String? { return idOpt ?? "" }
                }
            }

            // 2) If there is a `user`-like child (e.g., `currentUser`, `userObject`, etc.), search it for an id
            let possibleUserKeys = ["user", "currentUser", "account", "profile"]
            for key in possibleUserKeys {
                if let userChild = modelMirror.children.first(where: { $0.label == key }) {
                    let userMirror = Mirror(reflecting: userChild.value)
                    for idKey in commonIDKeys + ["identifier"] {
                        if let idChild = userMirror.children.first(where: { $0.label == idKey }) {
                            if let id = idChild.value as? String { return id }
                            if let idOpt = idChild.value as? String? { return idOpt ?? "" }
                        }
                    }
                }
            }

            // 3) Give up and return empty string
            return ""
        }()
        ProfileView(userID: resolvedUserID)
            .task {
                if selectedTab == .profile, !didTriggerProfileInitialLoad {
                    deferUntilAfterLaunch {
                        await MainActor.run {
                            didTriggerProfileInitialLoad = true
                            NotificationCenter.default.post(name: .LoadProfileNow, object: nil)
                        }
                    }
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
                CubeTabView(
                    selectedTab: $selectedTab,
                    tintColor: .indigo,
                    onSwipeUp: {
                        if selectedTab == .record {
                            NotificationCenter.default.post(name: Notification.Name("TriggerCameraCapture"), object: nil)
                        } else {
                            NotificationCenter.default.post(name: Notification.Name("ShowRecordCaptureUI"), object: nil)
                        }
                    },
                    onCubeTap: {
                        if selectedTab == .map {
                            print("[HomeView] Cube tapped on map tab - centering on user")
                            NotificationCenter.default.post(name: .CenterMapOnUser, object: nil)
                        }
                    }
                )
                .tint(.white)
                .frame(height: 230)
                .padding(.bottom, 8)
                .padding(.trailing, 8)
            }
            .padding(.bottom, 24)
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(true)
            .zIndex(998)
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        // Detect swipe down; settings no longer accessible via tab
                        if value.translation.height > 20, selectedTab == .profile {
                            // No-op: settings access removed from tab navigation
                        }
                        // New swipe logic for cube rotation based on horizontal swipe
                        let dx = value.translation.width
                        let dy = value.translation.height
                        if abs(dx) > abs(dy) {
                            if dx < -20 {
                                // swipe left -> next tab, rotate right 90°
                                rotateCube(to: nextTab(from: selectedTab), direction: .right)
                            } else if dx > 20 {
                                // swipe right -> previous tab, rotate left 90°
                                rotateCube(to: previousTab(from: selectedTab), direction: .left)
                            }
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
                            .ignoresSafeArea(edges: .bottom)
                    }
                    .frame(height: 1) // GeometryReader expands; constrain with container
                }
                .allowsHitTesting(true)
                .transition(.opacity)
            }
#endif
            
            // Global radius number display overlay (visible on all tabs) — safe-area aware
            GeometryReader { proxy in
                let safe = proxy.safeAreaInsets

                VStack {
                    Spacer()
                    HStack {
                        Spacer(minLength: 0)
                        
                        // Choose your preferred radius display style:
                        // Option 1: Default card style (recommended)
                        RadiusNumberDisplay(radiusMeters: $isometricBarModel.radius)
                        
                        // Option 2: Compact badge style
                        // RadiusNumberBadge(radiusMeters: $isometricBarModel.radius)
                        
                        // Option 3: Corner badge style
                        // RadiusCornerBadge(radiusMeters: $isometricBarModel.radius)
                        
                        // Option 4: Icon-centered style
                        // RadiusDisplayWithIcon(radiusMeters: $isometricBarModel.radius)
                    }
                    .padding(.trailing, safe.trailing + 16)
                    .padding(.bottom, safe.bottom + 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .animation(.spring(response: 0.5, dampingFraction: 0.75), value: isometricBarModel.radius)
            }
            .ignoresSafeArea(.container, edges: [.bottom, .leading, .trailing])
            .zIndex(999)
            .allowsHitTesting(false)
            
        }
        
        // Inject global settings for radius display (kept for compatibility)
        .environment(\.isometricRadiusBarDistance, isometricBarSettings.horizontalOffset)
        // Removed `.environment(\.isometricBarSettings, isometricBarSettings)` per instructions
        .environment(\.isometricBarModel, isometricBarModel)
        
        .task {
            // Removed cameraController.prewarm() and preparePreviewIfNeeded() here per instructions

            // Removed all feed triggers to defer until launch gate
        }
        // Removed locationProvider.request() task entirely per instructions

        .onAppear {
            launchGate.start()
            let appearT0 = CFAbsoluteTimeGetCurrent()
            print("[HomeView] onAppear at t=\(appearT0)")
            // Removed cameraController.prewarm() and preparePreviewIfNeeded() here per instructions
            
            // Keep startup minimal; no immediate location or feed triggers here
            if selectedTab != .feed {
                NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
            }
            if selectedTab == .profile {
                NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                await Task.yield()
                enableLowerHitArea = true
                
                if !didApplyDefaultBarSettings {
                    didApplyDefaultBarSettings = true
                    // Apply unified defaults for bar settings
                    isometricBarSettings.horizontalOffset = 40
                    isometricBarSettings.bottomOffset = -80
                    isometricBarSettings.barWidth = 98
                    isometricBarSettings.barHeight = 390
                    isometricBarSettings.barTiltDegrees = -8
                }
            }
            
            // Removed entire SceneKit prewarm block per instructions
            
            print("[HomeView] onAppear work took \(CFAbsoluteTimeGetCurrent() - appearT0)s")
        }
        .onChange(of: selectedTab) { newTab in
            animateYaw(to: yawForTab(selectedTab), duration: 0.45, direction: nil)

            if !([AppTab.map, .record, .feed, .profile].contains(selectedTab)) {
                selectedTab = .feed
            }
            
            // Animate radius bar to 0 when switching tabs
            // Exception: when switching TO profile, don't reset (will be set by profile view)
            if newTab != .profile {
                withAnimation(.easeInOut(duration: 0.6)) {
                    isometricBarModel.radius = 0
                }
            }
            
            // Pause/resume feed audio based on visibility
            if selectedTab == .feed {
                NotificationCenter.default.post(name: .ResumeFeedAudio, object: nil)
            } else {
                NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
            }
            // Motion is managed by scene phase now (runs on all tabs when active)
            
            if selectedTab == .profile {
                if !PreviewEnvHomeView.isPreview {
                    cameraController.stop()
                }
            }
            NotificationCenter.default.post(name: .ResetTabToTop, object: nil)
            
            // Removed prewarm and preparePreviewIfNeeded task per instructions
            
            if selectedTab != .record {
                isRecordHolding = false
                stopRecordHoldRamp(reset: false)
            }
            
            enableLowerHitArea = (selectedTab != .record)
        }
        .onChange(of: auth.isAuthenticated) { authed in
            if authed {
                DispatchQueue.main.async {
                    selectedTab = .feed
                    if !didTriggerFeedInitialLoad {
                        didTriggerFeedInitialLoad = true
                        NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                    }
                }
            }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                Task { @MainActor in
                    guard !PreviewEnvHomeView.isPreview else { return }
                    deferUntilAfterLaunch {
                        await MainActor.run { self.motionController.start() }
                    }
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
            DispatchQueue.main.async {
                isFeedReady = true
                print("[Feed] ready received at \(Date())")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .CubeMotionUpdate)) { _ in
            // Motion updates silenced
        }
        .onReceive(NotificationCenter.default.publisher(for: .SharedRadiusDidChange)) { note in
            if let value = note.userInfo?["radius"] as? Double {
                // Clamp to cap used in app (3,323,000) per updated cap
                isometricBarModel.radius = min(value, 3_323_000.0)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InlinePreviewDismissRequested"))) { _ in
            // Reset the radius bar so the user can capture again
            isometricBarModel.radius = 0
            NotificationCenter.default.post(name: .SharedRadiusDidChange, object: nil, userInfo: ["radius": 0.0])
        }
        .onReceive(NotificationCenter.default.publisher(for: .cameraCubeHoldBegan)) { _ in
            guard selectedTab == .record else { return }
            isRecordHolding = true
            ensureCameraRunningIfNeeded()
            startRecordHoldRamp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cameraCubeHoldEnded)) { _ in
            isRecordHolding = false
            stopRecordHoldRamp(reset: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenCameraAtCoordinate"))) { notification in
            // Handle long press on map - switch to camera tab and set coordinate
            guard let userInfo = notification.userInfo,
                  let latitude = userInfo["latitude"] as? Double,
                  let longitude = userInfo["longitude"] as? Double else {
                return
            }
            
            print("📍 [HomeView] Received map long-press coordinate: \(latitude), \(longitude)")
            
            // Switch to camera/record tab
            selectedTab = .record
            
            // Post notification with coordinate for CameraKitController to use
            NotificationCenter.default.post(
                name: Notification.Name("SetCameraCoordinate"),
                object: nil,
                userInfo: [
                    "latitude": latitude,
                    "longitude": longitude
                ]
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenMapToSelectPostLocation"))) { notification in
            // Handle request to select location for captured media - switch to map tab
            print("🗺️ [HomeView] Opening map to select post location")
            
            // Switch to map tab
            selectedTab = .map
            
            // Forward the notification to MapView (it will enter post placement mode)
            // The notification already contains the image/videoURL in userInfo
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowLocationOnMap"))) { notification in
            // Handle request to show post location on map (from long-press)
            guard let userInfo = notification.userInfo,
                  let coordinate = userInfo["coordinate"] as? CLLocationCoordinate2D else { return }
            
            print("📍 [HomeView] Showing location on map: \(coordinate.latitude), \(coordinate.longitude)")
            
            // Switch to map tab
            selectedTab = .map
            
            // The notification is already posted to MapView which will center the camera
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UploadPostToCoordinate"))) { notification in
            // Handle post upload after user selected location on map
            guard let userInfo = notification.userInfo,
                  let latitude = userInfo["latitude"] as? Double,
                  let longitude = userInfo["longitude"] as? Double else {
                return
            }
            
            print("📤 [HomeView] Uploading post to coordinate: \(latitude), \(longitude)")
            
            // Send to CameraKitController to handle the upload
            NotificationCenter.default.post(
                name: Notification.Name("SetCameraCoordinate"),
                object: nil,
                userInfo: [
                    "latitude": latitude,
                    "longitude": longitude
                ]
            )
            
            // Trigger the upload with the media from userInfo
            if let image = userInfo["image"] as? UIImage {
                // Upload image
                NotificationCenter.default.post(
                    name: Notification.Name("UploadImageToCurrentCoordinate"),
                    object: image
                )
            } else if let videoURL = userInfo["videoURL"] as? URL {
                // Upload video
                NotificationCenter.default.post(
                    name: Notification.Name("UploadVideoToCurrentCoordinate"),
                    object: videoURL
                )
            }
            
            // Switch back to profile or feed tab
            selectedTab = .profile
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToFeedTab"))) { _ in
            // Switch to feed tab (used after successful upload in Camera -> Map flow)
            print("🔄 [HomeView] Switching to feed tab after upload")
            selectedTab = .feed
        }
        .onChange(of: isPreviewRuntime) { isPreview in
            if isPreview {
                if let mapped = AppTab(fromPreview: previewSelectedTab) {
                    selectedTab = mapped
                }
            }
        }
        .onChange(of: previewSelectedTab) { tab in
            guard isPreviewRuntime else { return }
            if let mapped = AppTab(fromPreview: tab) {
                selectedTab = mapped
            }
        }
        .task {
            deferUntilAfterLaunch {
                await MainActor.run { isSceneKitReady = true }
            }
        }
        .task {
            // Removed the 2s TTI marker print task per instructions
        }
        .task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            print("[Startup] Watchdog 5s: heavy work deferred until 10s gate; if UI is still slow, check synchronous work on main thread")
        }
        .onReceive(NotificationCenter.default.publisher(for: .MapSuggestedRadius)) { note in
            if let value = note.userInfo?["radius"] as? Double {
                print("[HomeView] Received MapSuggestedRadius: \(Int(value))m")
                // Clamp to app cap and apply to the global bar with animation on every update
                let clampedValue = min(value, 3_323_000.0)
                withAnimation(.easeInOut(duration: 2.0)) {
                    isometricBarModel.radius = clampedValue
                }
                print("[HomeView] Updated isometricBarModel.radius to: \(Int(clampedValue))m")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .currentPostRadiusDidChange)) { note in
            if let value = note.userInfo?["radius"] as? Double {
                print("[HomeView] Received currentPostRadiusDidChange: \(Int(value))m")
                let duration = (note.userInfo?["duration"] as? Double) ?? 0.8
                let clampedValue = min(value, 3_323_000.0)
                withAnimation(.easeInOut(duration: duration)) {
                    isometricBarModel.radius = clampedValue
                }
                print("[HomeView] Updated isometricBarModel.radius to: \(Int(clampedValue))m (from feed)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .animateRadiusBarToValue)) { note in
            if let value = note.userInfo?["radius"] as? Double {
                print("[HomeView] Received animateRadiusBarToValue: \(Int(value))m")
                let duration = (note.userInfo?["duration"] as? Double) ?? 0.8
                let clampedValue = min(value, 3_323_000.0)
                withAnimation(.easeInOut(duration: duration)) {
                    isometricBarModel.radius = clampedValue
                }
                print("[HomeView] Updated isometricBarModel.radius to: \(Int(clampedValue))m (from animator)")
            }
        }
        // Removed .onChange handler - the binding $isometricBarModel.radius automatically triggers updateUIView in RadiusBarSceneView
    }
    
    
}
final class BarCubePreviewTuning: ObservableObject {
    // Removed barHorizontalOffset, barBottomOffset, barTiltDegrees, barWidth, barHeight per instructions (no longer used)
}

private struct CubeAndBarOverlay: View {
    @Binding var radius: Double
    // Changed per instructions to EnvironmentObject
    @EnvironmentObject private var isometricBarSettings: IsometricBarSettings

    var body: some View {
        GeometryReader { proxy in
            let safe = proxy.safeAreaInsets

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    // Use the new numeric display in preview
                    RadiusNumberDisplay(radiusMeters: $radius)
                }
                .padding(.trailing, safe.trailing + 16)
                .padding(.bottom, safe.bottom + 20)
            }
            .allowsHitTesting(false)
        }
    }
}

private struct HomeBarPlacementPreview: View {
    @State private var radius: Double = 0
    //@StateObject private var tuning = BarCubePreviewTuning() // Removed tuning usage
    
    @State private var selectedTab: AppTab = .record
    
    @State private var previewHover: Bool = false
    @State private var previewPopTrigger: Int = 0
    @State private var previewPopSoundEnabled: Bool = true
    
    @State private var previewHoldActive: Bool = false
    @State private var holdTask: Task<Void, Never>? = nil
    
    // Added state for continuous yaw
    @State private var yawDegrees: Double = 0
    
    // Inserted states as per instructions:
    @State private var isPreviewRotating: Bool = false
    @State private var queuedPreviewTab: AppTab? = nil
    
    // Changed per instructions to EnvironmentObject
    @EnvironmentObject private var isometricBarSettings: IsometricBarSettings
    
    var usesImperial: Bool { Locale.current.usesMetricSystem == false }
    var earthMaxUnit: Double { usesImperial ? 3958.8 : 6371.0 }
    
    // Added state to control animation flag
    @State private var previewAnimateTabChange: Bool = true
    
    private func playPopSound() {
        // Use a lightweight system sound for preview pop feedback
        let systemSoundID: SystemSoundID = 1104 // Tock-like sound
        AudioServicesPlaySystemSound(systemSoundID)
    }
    
    private func startPreviewHoldRamp() {
        holdTask?.cancel()
        let maxMeters: Double = 3_323_000.0
        let duration: Double = 10.0
        let start = radius
        let t0 = CACurrentMediaTime()
        holdTask = Task { @MainActor in
            while !Task.isCancelled && previewHoldActive && selectedTab == .record {
                let t = min(1.0, (CACurrentMediaTime() - t0) / duration)
                let eased = t * t * (3 - 2 * t)
                let next = start + (maxMeters - start) * eased
                radius = min(maxMeters, next)
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }
    
    private func stopPreviewHoldRamp(reset: Bool) {
        holdTask?.cancel()
        holdTask = nil
        if reset {
            withAnimation(.easeOut(duration: 0.35)) { radius = 0 }
        }
    }
    
    // MARK: - Helper rotation logic for preview cube yaw and tab switching
    private enum RotationDirection { case left, right }
    
    private func yawForTab(_ tab: AppTab) -> Double {
        switch tab {
        case .record: return 0
        case .feed: return 90
        case .profile: return 180
        case .map: return 270
        @unknown default: return 0
        }
    }
    
    private func normalizedDelta(from current: Double, to target: Double, prefer direction: RotationDirection?) -> Double {
        var delta = fmod(target - current + 540, 360) - 180
        if let dir = direction {
            if dir == .left && delta > 0 { delta -= 360 }
            if dir == .right && delta < 0 { delta += 360 }
        }
        return delta
    }
    
    private func animateYaw(to targetYaw: Double, duration: Double = 0.8, direction: RotationDirection? = nil) {
        let current = yawDegrees.truncatingRemainder(dividingBy: 360)
        let delta = normalizedDelta(from: current, to: targetYaw, prefer: direction)
        let final = current + delta
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1.0, duration: duration)) {
            yawDegrees = final
        }
    }
    
    private func nextPreviewTab(from tab: AppTab) -> AppTab {
        switch tab {
        case .map: return .record
        case .record: return .feed
        case .feed: return .profile
        case .profile: return .map
        @unknown default: return .feed
        }
    }
    
    private func previousPreviewTab(from tab: AppTab) -> AppTab {
        switch tab {
        case .map: return .profile
        case .record: return .map
        case .feed: return .record
        case .profile: return .feed
        @unknown default: return .feed
        }
    }
    
    // Replaced rotatePreview function as per instructions:
    private func rotatePreview(to newTab: AppTab, direction: RotationDirection) {
        let duration: Double = 1.0
        // If a rotation is in progress, queue this request
        if isPreviewRotating {
            queuedPreviewTab = newTab
            return
        }
        isPreviewRotating = true
        withAnimation(Animation.timingCurve(0.2, 0.8, 0.2, 1.0, duration: duration)) {
            selectedTab = newTab
        }
        // Schedule completion to allow chained rotations
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            isPreviewRotating = false
            if let queued = queuedPreviewTab {
                queuedPreviewTab = nil
                rotatePreview(to: queued, direction: direction)
            }
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black.opacity(0.2), .black.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack {
                Spacer()
                CubeTabView(
                    selectedTab: $selectedTab,
                    previewHover: $previewHover,
                    previewPopTrigger: $previewPopTrigger,
                    previewPopSoundEnabled: $previewPopSoundEnabled,
                    previewHoldActive: $previewHoldActive
                )
                .tint(.white)
                .frame(height: 230)
                .transaction { tx in
                    tx.animation = .timingCurve(0.2, 0.8, 0.2, 1.0, duration: 1.0)
                }
                .gesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            let dx = value.translation.width
                            let dy = value.translation.height
                            if abs(dx) > abs(dy) {
                                if dx < -20 {
                                    rotatePreview(to: nextPreviewTab(from: selectedTab), direction: .right)
                                } else if dx > 20 {
                                    rotatePreview(to: previousPreviewTab(from: selectedTab), direction: .left)
                                }
                            }
                        }
                )
                .padding(.bottom, 8)
                .padding(.trailing, 8)
            }
            .ignoresSafeArea(edges: .bottom)

            CubeAndBarOverlay(radius: $radius)
                .animation(nil, value: radius)

            VStack {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Tab", selection: $selectedTab) {
                        Text("Record").tag(AppTab.record)
                        Text("Map").tag(AppTab.map)
                        Text("Profile").tag(AppTab.profile)
                        Text("Feed").tag(AppTab.feed)
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("Horizontal")
                        Slider(
                            value: Binding<Double>(
                                get: { Double(isometricBarSettings.horizontalOffset) },
                                set: { isometricBarSettings.horizontalOffset = CGFloat($0) }
                            ),
                            in: -200...200
                        )
                        Text("\(Int(isometricBarSettings.horizontalOffset))").monospacedDigit()
                    }
                    HStack {
                        Text("Bottom")
                        Slider(
                            value: Binding<Double>(
                                get: { Double(isometricBarSettings.bottomOffset) },
                                set: { isometricBarSettings.bottomOffset = CGFloat($0) }
                            ),
                            in: -440...240
                        )
                        Text("\(Int(isometricBarSettings.bottomOffset))").monospacedDigit()
                    }
                    HStack {
                        Text("Tilt")
                        Slider(
                            value: Binding<Double>(
                                get: { isometricBarSettings.barTiltDegrees },
                                set: { isometricBarSettings.barTiltDegrees = $0 }
                            ),
                            in: -25...0,
                            step: 1
                        )
                        Text("\(Int(isometricBarSettings.barTiltDegrees))°").monospacedDigit()
                    }
                    HStack {
                        Text("Width")
                        Slider(
                            value: Binding<Double>(
                                get: { Double(isometricBarSettings.barWidth) },
                                set: { isometricBarSettings.barWidth = CGFloat($0) }
                            ),
                            in: 64...128
                        )
                        Text("\(Int(isometricBarSettings.barWidth))").monospacedDigit()
                    }
                    HStack {
                        Text("Height")
                        Slider(
                            value: Binding<Double>(
                                get: { Double(isometricBarSettings.barHeight) },
                                set: { isometricBarSettings.barHeight = CGFloat($0) }
                            ),
                            in: 260...480
                        )
                        Text("\(Int(isometricBarSettings.barHeight))").monospacedDigit()
                    }
                    HStack {
                        Text("Radius")
                        Slider(
                            value: Binding(
                                get: {
                                    let meters = radius
                                    return usesImperial ? (meters / 1609.34) : (meters / 1000.0)
                                },
                                set: { unitValue in
                                    if usesImperial { radius = unitValue * 1609.34 } else { radius = unitValue * 1000.0 }
                                }
                            ),
                            in: 0...earthMaxUnit
                        )
                        Text({
                            let unitSymbol = usesImperial ? "mi" : "km"
                            let unitVal = usesImperial ? (radius / 1609.34) : (radius / 1000.0)
                            return "\(Int(unitVal)) \(unitSymbol)"
                        }())
                        .monospacedDigit()
                    }
                    Text(usesImperial ? "out of 3,958.8 mi" : "out of 6,371 km")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button(role: .destructive) {
                            isometricBarSettings.horizontalOffset = 80
                            isometricBarSettings.bottomOffset = 1
                            isometricBarSettings.barWidth = 98
                            isometricBarSettings.barHeight = 390
                            isometricBarSettings.barTiltDegrees = -8
                            // Optionally reset preview radius as well
                            radius = 0
                        } label: {
                            Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.top, 24)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: previewHoldActive) { newValue in
            if newValue && selectedTab == .record {
                // Trigger pop animation immediately on hold begin
                previewPopTrigger += 1
                // Start the radius growth ramp
                startPreviewHoldRamp()
                // Play pop sound at the end of the pop animation
                let popAnimationDuration: Double = 0.35
                DispatchQueue.main.asyncAfter(deadline: .now() + popAnimationDuration) {
                    if previewPopSoundEnabled {
                        playPopSound()
                    }
                }
            } else {
                stopPreviewHoldRamp(reset: true)
            }
        }
        .onChange(of: selectedTab) { newValue in
            if newValue != .record {
                previewHoldActive = false
                stopPreviewHoldRamp(reset: true)
            }
        }
        .onDisappear {
            previewHoldActive = false
            stopPreviewHoldRamp(reset: false)
        }
        // Removed the entire `.onAppear { ... }` block here as per instructions
    }
}

private struct SharedPreviewSettings {
    static let settings: IsometricBarSettings = {
        let s = IsometricBarSettings()
        s.horizontalOffset = 40
        s.bottomOffset = -113
        s.barWidth = 98
        s.barHeight = 390
        s.barTiltDegrees = -8
        return s
    }()
}

#Preview("HomeView") {
    HomeBarPlacementPreview()
        .previewDevice("iPhone 15 Pro")
        .ignoresSafeArea(.container, edges: [.bottom, .leading, .trailing])
        .environmentObject(SharedPreviewSettings.settings)
}

private extension AppTab {
    init?(fromPreview tab: PreviewAppTab) {
        switch tab {
        case .map: self = .map
        case .record: self = .record
        case .feed: self = .feed
        case .profile: self = .profile
        }
    }
}

// MARK: - Camera Instructions Overlay

private struct CameraInstructionsOverlay: View {
    @State private var currentInstructionIndex = 0
    @State private var instructionOpacity: Double = 1.0
    
    private let instructions: [(title: String, message: String)] = [
        (
            "Camera Controls",
            "Tap cube to take photo • Hold cube to record video"
        ),
        (
            "Torch Control",
            "Swipe up to turn flashlight ON • Swipe down to turn flashlight OFF"
        ),
        (
            "Flip Camera",
            "Double tap anywhere on screen to switch between front and back camera"
        ),
        (
            "Select Location",
            "Long-press on the map to choose where you want to post your content"
        )
    ]
    
    var body: some View {
        VStack {
            Spacer().frame(height: 24)
            
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(instructions[currentInstructionIndex].title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text(instructions[currentInstructionIndex].message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.top, -4)
            .padding(14)
            .frame(minHeight: 90) // Increased height for longer messages
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(radius: 4)
            .padding(.horizontal, 12)
            .opacity(instructionOpacity)
            
            Spacer()
        }
        .task {
            // Cycle through instructions every 6 seconds
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                
                // Fade out
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.3)) {
                        instructionOpacity = 0.0
                    }
                }
                
                try? await Task.sleep(nanoseconds: 300_000_000)
                
                // Change instruction
                await MainActor.run {
                    currentInstructionIndex = (currentInstructionIndex + 1) % instructions.count
                }
                
                // Fade in
                await MainActor.run {
                    withAnimation(.easeIn(duration: 0.3)) {
                        instructionOpacity = 1.0
                    }
                }
            }
        }
    }
}

