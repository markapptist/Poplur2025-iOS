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
    
    // Routed user ID when tapping on a username in Feed
    @State private var routedUserID: String? = nil
    
    // Location only when needed
    @StateObject private var locationProvider = LocationProvider()
    
    // Use injected, shared camera controller (prewarmed in App)
    @ObservedObject var cameraController: CameraKitController
    
    // AR Filters
    @StateObject private var arFilterManager = ARFilterManager()
    @State private var showARFilters = false
    
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
    
    // User recognition manager for face detection
    @StateObject private var userRecognitionManager = UserRecognitionManager()
    
    @StateObject private var motionController = SceneMotionController()
    @StateObject private var cubeTouchConfig = CubeTouchConfiguration()
    
    @State private var recordHoldTask: Task<Void, Never>? = nil
    @State private var isRecordHolding: Bool = false
    
    // Recording countdown state
    @State private var isRecording: Bool = false
    @State private var recordingSecondsRemaining: Int = 10
    @State private var recordingTimer: Timer? = nil
    @State private var cubeFlashTimer: Timer? = nil
    @State private var isCubeFlashing: Bool = false
    
    // Post count state (for displaying user's total posts)
    @State private var userPostCount: Int = 0
    
    // Radius trend tracking for post count display
    @State private var previousRadius: Double? = nil
    @State private var radiusTrend: RadiusTrend = .neutral
    
    enum RadiusTrend {
        case up, down, neutral
    }
    
    // Added state for cube yaw angle
    @State private var cubeYawDegrees: Double = 0
    
    // Added per instruction to gate animations
    @State private var isSceneKitReady: Bool = false

    // Added per instructions to control initial yaw set once
    @State private var didSetInitialCubeYaw: Bool = false
    
    // Upload status state
    @State private var showUploadStatus: Bool = false
    @State private var uploadStatusMessage: String = ""
    @State private var uploadStatusIcon: String = "arrow.up.circle.fill"
    @State private var uploadStatusColor: Color = .blue

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
            // Camera preview with UIKit gestures enabled
            // UIKit gestures: swipe up/down (flash), double-tap (flip camera), long-press (AR filters)
            HomeCameraPreviewHost(controller: cameraController)
                .ignoresSafeArea()
                .allowsHitTesting(true) // Enable UIKit gesture recognizers
            
            // ML Detection Overlay (hidden when AR filters shown)
            if !showARFilters {
                LiveMLDetectionOverlay(
                    controller: cameraController,
                    userRecognitionManager: userRecognitionManager
                )
                .allowsHitTesting(false)
                .transition(.opacity)
            }
            
            // Animated instructional text overlay (hidden when AR filters shown)
            if !showARFilters {
                CameraInstructionsOverlay()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
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
                    
                    // 🆕 Setup AR filter support
                    if let cameraVC = cameraController.recordPreviewViewController as? CameraPreviewViewController {
                        cameraController.setupARFilterSupport(
                            filterManager: arFilterManager,
                            displayLayer: cameraVC.displayLayer as! AVSampleBufferDisplayLayer
                        )
                    }
                    
                    // Enable ML detection with user recognition
                    cameraController.enableMLDetection()
                    
                    // Setup user recognition callback
                    cameraController.mlDetectionManager?.onFrameProcessed = { [weak userRecognitionManager] pixelBuffer, objects in
                        userRecognitionManager?.processDetectedObjects(objects, from: pixelBuffer)
                    }
                    
                    // Start recognition session to pre-load user radius
                    await userRecognitionManager.startRecognitionSession()
                case .notDetermined:
                    // Do not prompt on appear; let user interaction trigger request
                    break
                default:
                    break
                }
            }
        }
        .onDisappear {
            // Disable ML detection when leaving camera tab
            cameraController.disableMLDetection()
            userRecognitionManager.clearRecognition()
            // Reset filters and flag when leaving camera tab
            showARFilters = false
            arFilterManager.activeFilter = .none
            UserDefaults.standard.set(false, forKey: "ARFiltersShown")
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
            // Continue ramping as long as recording is active (even after user releases)
            while !Task.isCancelled && (isRecordHolding || isRecording) && selectedTab == .record {
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
    
    // MARK: - Recording Countdown Functions
    
    /// Start the 10-second countdown timer and cube flashing
    /// Recording will continue even after user releases the hold (after 2 seconds)
    private func startRecordingCountdown() {
        isRecording = true
        recordingSecondsRemaining = 10
        startCubeFlashing()
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            DispatchQueue.main.async {
                if self.recordingSecondsRemaining > 0 {
                    self.recordingSecondsRemaining -= 1
                } else {
                    // Recording complete - stop everything
                    self.stopRecordingCountdown()
                    self.stopRecordHoldRamp(reset: true)
                    // Force stop the actual recording
                    NotificationCenter.default.post(name: .cameraCubeHoldEnded, object: nil)
                }
            }
        }
    }
    
    private func stopRecordingCountdown() {
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        stopCubeFlashing()
    }
    
    private func startCubeFlashing() {
        isCubeFlashing = true
        NotificationCenter.default.post(name: Notification.Name("CubeStartFlashing"), object: nil)
    }
    
    private func stopCubeFlashing() {
        isCubeFlashing = false
        NotificationCenter.default.post(name: Notification.Name("CubeStopFlashing"), object: nil)
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
        case .settings: return 0 // Settings not currently in rotation
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
        case .settings: return .feed // Settings not in rotation, default to feed
        }
    }
    
    private func previousTab(from tab: AppTab) -> AppTab {
        switch tab {
        case .map: return .profile
        case .record: return .map
        case .feed: return .record
        case .profile: return .feed
        case .settings: return .feed // Settings not in rotation, default to feed
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
        
        NavigationStack {
            ProfileView(userID: resolvedUserID)
                .environment(\.routedUserID, routedUserID)
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
                    VStack(spacing: 12) {
                        Image(systemName: "gearshape.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Settings are not available from here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
                @unknown default:
                    feedTabContent
                }
            }
            
            // Upload Status Overlay
            if showUploadStatus {
                VStack {
                    HStack(spacing: 12) {
                        Image(systemName: uploadStatusIcon)
                            .font(.title2)
                            .foregroundStyle(uploadStatusColor)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                        
                        Text(uploadStatusMessage)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .padding(.top, 60)
                    
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(999)
            }
            
            // AR Filter Selector above cube (Snapchat-style)
            if showARFilters && selectedTab == .record {
                VStack(spacing: 0) {
                    // Transparent spacer that allows touches to pass through
                    Color.clear
                        .allowsHitTesting(false)
                    
                    // Filter selector (captures touches for buttons)
                    ARFilterSelectorHorizontal(
                        filterManager: arFilterManager,
                        cameraController: cameraController,
                        isPresented: $showARFilters
                    )
                    .allowsHitTesting(true) // Enable touches for filter buttons
                    .padding(.bottom, 160) // Position closer to cube (reduced from 280)
                }
                .zIndex(999)
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
                            NotificationCenter.default.post(
                                name: Notification.Name("CenterMapOnUser"),
                                object: nil,
                                userInfo: nil
                            )
                        } else if selectedTab == .profile {
                            NotificationCenter.default.post(
                                name: .CubeGlobalTap,
                                object: nil
                            )
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
            
            // Camera roll button overlay (bottom-left, aligned with radius display)
            GeometryReader { proxy in
                let safe = proxy.safeAreaInsets
                
                VStack {
                    Spacer()
                    HStack {
                        // Show camera roll button when on record tab and not recording
                        if selectedTab == .record && !isRecording {
                            CameraRollButton()
                        }
                        Spacer()
                    }
                    .padding(.leading, safe.leading + 16)
                    .padding(.bottom, safe.bottom + 20) // Align with RadiusNumberDisplay center line
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .zIndex(1000)
            .allowsHitTesting(true)
            
            // Recording countdown overlay (separate positioning, slightly above camera roll button)
            GeometryReader { proxy in
                let safe = proxy.safeAreaInsets
                
                VStack {
                    Spacer()
                    HStack {
                        RecordingCountdownView(
                            isRecording: $isRecording,
                            secondsRemaining: $recordingSecondsRemaining,
                            postCount: $userPostCount,
                            selectedTab: $selectedTab,
                            radiusTrend: $radiusTrend
                        )
                        Spacer()
                    }
                    .padding(.leading, safe.leading + 16)
                    .padding(.bottom, safe.bottom + 85) // Position above camera roll button
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
            .zIndex(1001)
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
            // Removed cameraController.prewarm() and preparePreviewIfNeeded() here per instructions
            
            // Keep startup minimal; no immediate location or feed triggers here
            if selectedTab != .feed {
                NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
            }
            if selectedTab == .profile {
                NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
            }

            // Insert initial cube yaw set on first appear
            if !didSetInitialCubeYaw {
                didSetInitialCubeYaw = true
                // Start cube on Feed face (90°) without animation
                cubeYawDegrees = yawForTab(.feed)
            }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                await Task.yield()
                enableLowerHitArea = false // Disabled to prevent accidental taps outside cube
                
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
        }
        .onChange(of: selectedTab) { newTab in
            if !didSetInitialCubeYaw {
                didSetInitialCubeYaw = true
                cubeYawDegrees = yawForTab(selectedTab)
            } else {
                animateYaw(to: yawForTab(selectedTab), duration: 0.45, direction: nil)
            }

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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ToggleARFilters"))) { _ in
            // Handle AR filter toggle from CameraPreviewViewController
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                showARFilters.toggle()
                UserDefaults.standard.set(showARFilters, forKey: "ARFiltersShown")
                NotificationCenter.default.post(
                    name: Notification.Name("ARFiltersStateChanged"),
                    object: nil,
                    userInfo: ["isShown": showARFilters]
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .cameraCubeHoldBegan)) { _ in
            guard selectedTab == .record else { return }
            isRecordHolding = true
            ensureCameraRunningIfNeeded()
            startRecordHoldRamp()
            startRecordingCountdown() // Start 10-second countdown
        }
        .onReceive(NotificationCenter.default.publisher(for: .cameraCubeHoldEnded)) { _ in
            // Only stop if recording hasn't started yet (user released before 2 seconds)
            // If recording is in progress, let the countdown timer handle the stop
            if !isRecording {
                isRecordHolding = false
                stopRecordHoldRamp(reset: true)
                stopRecordingCountdown()
            }
            // If recording is active, isRecordHolding is set to false but recording continues
            isRecordHolding = false
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenCameraAtCoordinate"))) { notification in
            // Handle long press on map - switch to camera tab and set coordinate
            guard let userInfo = notification.userInfo,
                  let latitude = userInfo["latitude"] as? Double,
                  let longitude = userInfo["longitude"] as? Double else {
                return
            }
            
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
            
            // Switch to map tab
            selectedTab = .map
            
            // Forward the notification to MapView (it will enter post placement mode)
            // The notification already contains the image/videoURL in userInfo
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowLocationOnMap"))) { notification in
            // Handle request to show post location on map (from long-press)
            guard let userInfo = notification.userInfo,
                  let coordinate = userInfo["coordinate"] as? CLLocationCoordinate2D else { return }
            
            // Switch to map tab
            selectedTab = .map
            
            // The notification is already posted to MapView which will center the camera
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowLocationOnMapFromPost"))) { note in
            // Expect userInfo: ["latitude": Double, "longitude": Double]
            guard let userInfo = note.userInfo,
                  let latitude = userInfo["latitude"] as? Double,
                  let longitude = userInfo["longitude"] as? Double else { return }
            selectedTab = .map
            NotificationCenter.default.post(name: Notification.Name("ShowLocationOnMap"), object: nil, userInfo: [
                "coordinate": CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            ])
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UploadPostToCoordinate"))) { notification in
            // Handle post upload after user selected location on map
            guard let userInfo = notification.userInfo,
                  let latitude = userInfo["latitude"] as? Double,
                  let longitude = userInfo["longitude"] as? Double else {
                return
            }
            
            // Show upload starting status
            uploadStatusMessage = "Uploading your post..."
            uploadStatusIcon = "arrow.up.circle.fill"
            uploadStatusColor = .blue
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showUploadStatus = true
            }
            
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
            
            // Switch to profile tab to show the post once uploaded
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                selectedTab = .profile
                NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PostUploadStarted"))) { notification in
            // Show upload started status
            uploadStatusMessage = notification.userInfo?["message"] as? String ?? "Uploading..."
            uploadStatusIcon = "arrow.up.circle.fill"
            uploadStatusColor = .blue
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showUploadStatus = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PostUploadSuccess"))) { _ in
            // Show success status
            uploadStatusMessage = "Post uploaded successfully!"
            uploadStatusIcon = "checkmark.circle.fill"
            uploadStatusColor = .green
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showUploadStatus = true
            }
            
            // Ask profile to refresh its content and scroll to the new post if provided
            NotificationCenter.default.post(name: Notification.Name("RefreshProfileAfterUpload"), object: nil)
            
            // Ensure we land on profile to see the new post
            selectedTab = .profile
            
            NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
            
            // Hide after 2 seconds
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showUploadStatus = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PostUploadFailed"))) { notification in
            // Show failure status
            let error = notification.userInfo?["error"] as? String ?? "Upload failed"
            uploadStatusMessage = error
            uploadStatusIcon = "xmark.circle.fill"
            uploadStatusColor = .red
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showUploadStatus = true
            }
            
            // Hide after 3 seconds
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showUploadStatus = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToFeedTab"))) { _ in
            // Switch to feed tab (used after successful upload in Camera -> Map flow)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToProfileTab"))) { _ in
            // Switch to profile tab (used after successful upload in Map -> Camera flow)
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToMapTab"))) { _ in
            // Switch to map tab (used when long-pressing on post in feed/profile)
        }
        .onReceive(NotificationCenter.default.publisher(for: .ShowUserProfile)) { note in
            if let uid = note.object as? String {
                routedUserID = uid
                selectedTab = .profile
                NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowUserProfileContext"))) { note in
            // Expect userInfo: ["userID": String, "radius": Double?, "currentPostID": String?]
            if let userInfo = note.userInfo,
               let uid = userInfo["userID"] as? String {
                routedUserID = uid
                // Forward radius/currentPostID to profile via Notification so ProfileView can reflect the tapped user's context
                var forwardInfo: [String: Any] = ["userID": uid]
                if let r = userInfo["radius"] as? Double { forwardInfo["radius"] = r }
                if let pid = userInfo["currentPostID"] as? String { forwardInfo["currentPostID"] = pid }
                NotificationCenter.default.post(name: Notification.Name("ProfileShowUserContext"), object: nil, userInfo: forwardInfo)
                selectedTab = .profile
                NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FeedCurrentPostContext"))) { note in
            // Keep track of the last tapped user's context to be used by profile if needed
            if let userInfo = note.userInfo, let uid = userInfo["userID"] as? String {
                routedUserID = uid
            }
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
        }
        .onReceive(NotificationCenter.default.publisher(for: .MapSuggestedRadius)) { note in
            if let value = note.userInfo?["radius"] as? Double {
                // Clamp to app cap and apply to the global bar with animation on every update
                let clampedValue = min(value, 3_323_000.0)
                let anim = Animation.easeInOut(duration: 2.0)
                withAnimation(anim) {
                    isometricBarModel.radius = clampedValue
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .currentPostRadiusDidChange)) { note in
            if let value = note.userInfo?["radius"] as? Double {
                let duration = (note.userInfo?["duration"] as? Double) ?? 0.8
                let clampedValue = min(value, 3_323_000.0)
                
                // Track radius trend
                let oldTrend = radiusTrend
                if let prev = previousRadius {
                    if clampedValue > prev {
                        radiusTrend = .up
                    } else if clampedValue < prev {
                        radiusTrend = .down
                    } else {
                        radiusTrend = .neutral
                    }
                } else {
                    radiusTrend = .neutral
                }
                previousRadius = clampedValue
                
                if oldTrend != radiusTrend {
                }
                
                let anim = Animation.easeInOut(duration: duration)
                withAnimation(anim) {
                    isometricBarModel.radius = clampedValue
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .animateRadiusBarToValue)) { note in
            if let value = note.userInfo?["radius"] as? Double {
                let duration = (note.userInfo?["duration"] as? Double) ?? 0.8
                let clampedValue = min(value, 3_323_000.0)
                let anim = Animation.easeInOut(duration: duration)
                withAnimation(anim) {
                    isometricBarModel.radius = clampedValue
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UserPostCountDidChange"))) { note in
            if let count = note.userInfo?["count"] as? Int {
                userPostCount = count
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ShowUserProfile)) { note in
            if let uid = note.object as? String {
                routedUserID = uid
                selectedTab = .profile
                NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
            }
        }
        .onChange(of: selectedTab) { newTab in
            if newTab != .profile && routedUserID != nil {
                routedUserID = nil
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

struct HomeBarPlacementPreview: View {
    @State private var radius: Double = 0
    //@StateObject private var tuning = BarCubePreviewTuning() // Removed tuning usage
    
    @State private var selectedTab: AppTab
    
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

    init(initialTab: AppTab = .record) {
        _selectedTab = State(initialValue: initialTab)
    }
    
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
        case .settings: return 0 // Settings not currently in rotation
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
        case .settings: return .feed // Settings not in rotation, default to feed
        }
    }
    
    private func previousPreviewTab(from tab: AppTab) -> AppTab {
        switch tab {
        case .map: return .profile
        case .record: return .map
        case .feed: return .record
        case .profile: return .feed
        case .settings: return .feed // Settings not in rotation, default to feed
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

struct HomePreviewSettings {
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

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            RealTabLayoutPreviewShell(tab: .record) {
                HomeBarPlacementPreview(initialTab: .record)
                    .environmentObject(HomePreviewSettings.settings)
            }
            .previewDisplayName("Home Real UI Layout - Record")

            RealTabLayoutPreviewShell(tab: .map) {
                HomeBarPlacementPreview(initialTab: .map)
                    .environmentObject(HomePreviewSettings.settings)
            }
            .previewDisplayName("Home Real UI Layout - Map")

        }
        .ignoresSafeArea(.container, edges: [.bottom, .leading, .trailing])
    }
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
            "AR Filters",
            "Long-press anywhere on camera to show beauty filters and effects"
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
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    
                    Text(instructions[currentInstructionIndex].message)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.top, -4)
            .padding(14)
            .frame(minHeight: 90) // Increased height for longer messages
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

// MARK: - Live ML Detection Overlay

/// Displays live ML object detection results and recognized users at the top of the camera view
private struct LiveMLDetectionOverlay: View {
    @ObservedObject var controller: CameraKitController
    @ObservedObject var userRecognitionManager: UserRecognitionManager
    @State private var detectedObjects: [DetectedObject] = []
    @State private var isDetecting: Bool = false
    
    var body: some View {
        VStack {
            // Show user recognition if available
            if let recognizedUser = userRecognitionManager.recognizedUser, recognizedUser.isRecent {
                RecognizedUserCard(user: recognizedUser)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: recognizedUser.id)
            } else if !detectedObjects.isEmpty {
                // Show generic detections if no user recognized
                VStack(spacing: 8) {
                    // Primary detection (largest, most confident)
                    if let primary = detectedObjects.first {
                        HStack(spacing: 12) {
                            // Icon
                            Text(getIcon(for: primary.identifier))
                                .font(.system(size: 32))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(primary.identifier.capitalized)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                
                                Text("\(primary.confidencePercentage)% confidence")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                    }
                    
                    // Additional detections (compact)
                    if detectedObjects.count > 1 {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                            
                            Text("Also seeing: \(detectedObjects.dropFirst().map { $0.identifier.capitalized }.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                }
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.75), value: detectedObjects.count)
            } else if isDetecting {
                // Scanning indicator
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                    
                    Text("Scanning...")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.top, 60)
                .transition(.opacity)
            }
            
            Spacer()
        }
        .onAppear {
            isDetecting = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MLObjectsDetected"))) { notification in
            if let objects = notification.userInfo?["objects"] as? [DetectedObject] {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    detectedObjects = objects
                    isDetecting = !objects.isEmpty
                }
                
                // Clear detections after 2 seconds of no updates
                clearDetectionsAfterDelay()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("UserRecognizedInCamera"))) { notification in
            // When user is recognized, update the global radius display
            if let radiusMeters = notification.userInfo?["radius"] as? Double {
                NotificationCenter.default.post(
                    name: .SharedRadiusDidChange,
                    object: nil,
                    userInfo: ["radius": radiusMeters]
                )
            }
        }
    }
    
    private func clearDetectionsAfterDelay() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !detectedObjects.isEmpty {
                withAnimation(.easeOut(duration: 0.3)) {
                    detectedObjects = []
                    isDetecting = true
                }
            }
        }
    }
    
    private func getIcon(for identifier: String) -> String {
        let lowercased = identifier.lowercased()
        
        // Map identifiers to emojis
        if lowercased.contains("person") || lowercased.contains("face") || lowercased.contains("human") {
            return "👤"
        }
        if lowercased.contains("dog") { return "🐕" }
        if lowercased.contains("cat") { return "🐈" }
        if lowercased.contains("bird") { return "🐦" }
        if lowercased.contains("car") || lowercased.contains("vehicle") { return "🚗" }
        if lowercased.contains("phone") || lowercased.contains("mobile") { return "📱" }
        if lowercased.contains("food") || lowercased.contains("pizza") || lowercased.contains("burger") { return "🍔" }
        if lowercased.contains("drink") || lowercased.contains("coffee") || lowercased.contains("cup") { return "☕️" }
        if lowercased.contains("tree") || lowercased.contains("plant") { return "🌳" }
        if lowercased.contains("flower") { return "🌸" }
        if lowercased.contains("building") || lowercased.contains("house") { return "🏢" }
        if lowercased.contains("book") { return "📚" }
        if lowercased.contains("computer") || lowercased.contains("laptop") { return "💻" }
        if lowercased.contains("beach") || lowercased.contains("ocean") { return "🏖" }
        if lowercased.contains("mountain") { return "⛰" }
        if lowercased.contains("sky") || lowercased.contains("cloud") { return "☁️" }
        
        return "🔍" // Default search icon
    }
}

// MARK: - Recognized User Card

/// Card showing recognized user with their radius
private struct RecognizedUserCard: View {
    let user: RecognizedUser
    
    var body: some View {
        VStack(spacing: 10) {
            // User header
            HStack(spacing: 12) {
                // Profile icon/image
                Circle()
                    .fill(LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("@\(user.profile.username)")
                        .font(.headline)
                        .foregroundStyle(.white)
                    
                    Text("Tap to view profile")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Confidence badge
                Text("\(Int(user.confidence * 100))%")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.2))
                    .clipShape(Capsule())
            }
            
            // Radius display
            HStack(spacing: 12) {
                Image(systemName: "circle.dashed")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Radius")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                    
                    Text(user.formattedRadius)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                // Trend indicator (optional)
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(8)
                    .background(Color.green.opacity(0.2))
                    .clipShape(Circle())
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
        .padding(.top, 60)
        .padding(.horizontal, 16)
    }
}
