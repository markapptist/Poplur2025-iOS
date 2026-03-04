import SwiftUI
import CoreLocation
import AVFoundation
import SceneKit
import CoreMotion
import Combine

// Usage elsewhere:
// @Environment(\.isometricRadiusBarDistance) private var isometricRadiusBarDistance
// Use `isometricRadiusBarDistance` to position your isometric radius bar from the screen center
// Or use the shared settings object:
// @Environment(\.isometricBarSettings) private var barSettings
// barSettings.horizontalOffset / barSettings.bottomOffset

// Shared settings for isometric radius bar positioning
final class IsometricBarSettings: ObservableObject {
    // Horizontal distance from screen center (points)
    @Published var horizontalOffset: CGFloat
    // Vertical distance from bottom safe area (points)
    @Published var bottomOffset: CGFloat

    init(horizontalOffset: CGFloat = 23, bottomOffset: CGFloat = 24) {
        self.horizontalOffset = horizontalOffset
        self.bottomOffset = bottomOffset
    }
}

// Shared model for the isometric bar radius value
final class IsometricBarModel: ObservableObject {
    @Published var radius: Double
    init(radius: Double = 0) { self.radius = radius }
}

private struct IsometricBarSettingsKey: EnvironmentKey {
    static let defaultValue: IsometricBarSettings = IsometricBarSettings()
}

private struct IsometricBarModelKey: EnvironmentKey {
    static let defaultValue: IsometricBarModel = IsometricBarModel()
}

// Deprecated: prefer using `isometricBarSettings.horizontalOffset` and `.bottomOffset`
private struct IsometricRadiusBarDistanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 2000 // default distance in points; adjust as needed
}

extension EnvironmentValues {
    var isometricBarSettings: IsometricBarSettings {
        get { self[IsometricBarSettingsKey.self] }
        set { self[IsometricBarSettingsKey.self] = newValue }
    }

    var isometricRadiusBarDistance: CGFloat {
        get { self[IsometricRadiusBarDistanceKey.self] }
        set { self[IsometricRadiusBarDistanceKey.self] = newValue }
    }

    var isometricBarModel: IsometricBarModel {
        get { self[IsometricBarModelKey.self] }
        set { self[IsometricBarModelKey.self] = newValue }
    }
}

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

extension Notification.Name {
    static let SharedRadiusDidChange = Notification.Name("SharedRadiusDidChange")
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
    @State private var showBarTuner: Bool = false
    
    // Shared radius model controlling the global isometric bar value across all tabs
    @StateObject private var isometricBarModel = IsometricBarModel(radius: 0)
    
    // Shared settings controlling isometric bar offsets across all views
    @StateObject private var isometricBarSettings = IsometricBarSettings(horizontalOffset: 80, bottomOffset: -80)
    
    @StateObject private var motionController = SceneMotionController()
    @StateObject private var cubeTouchConfig = CubeTouchConfiguration()
    
    @State private var recordHoldTask: Task<Void, Never>? = nil
    @State private var isRecordHolding: Bool = false
    
    // Added state for cube yaw angle
    @State private var cubeYawDegrees: Double = 0
    
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
                    DispatchQueue.main.async {
                        didTriggerMapInitialLoad = true
                        NotificationCenter.default.post(name: .LoadMapNow, object: nil)
                    }
                }
            }
            .onAppear {
                if selectedTab == .map, !didTriggerMapInitialLoad {
                    DispatchQueue.main.async {
                        didTriggerMapInitialLoad = true
                        NotificationCenter.default.post(name: .LoadMapNow, object: nil)
                    }
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
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1.0, duration: duration)) {
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
                if selectedTab == .feed {
                    if !didTriggerFeedInitialLoad {
                        DispatchQueue.main.async {
                            didTriggerFeedInitialLoad = true
                            NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                        }
                    }
                }
            }
            .onAppear {
                if selectedTab == .feed {
                    if !didTriggerFeedInitialLoad {
                        DispatchQueue.main.async {
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
                    DispatchQueue.main.async {
                        didTriggerProfileInitialLoad = true
                        NotificationCenter.default.post(name: .LoadProfileNow, object: nil)
                    }
                }
            }
            .onAppear {
                if selectedTab == .profile, !didTriggerProfileInitialLoad {
                    DispatchQueue.main.async {
                        didTriggerProfileInitialLoad = true
                        NotificationCenter.default.post(name: .LoadProfileNow, object: nil)
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
                CubeTabView(selectedTab: $selectedTab, tintColor: .indigo, onSwipeUp: {
                    if selectedTab == .record {
                        NotificationCenter.default.post(name: Notification.Name("TriggerCameraCapture"), object: nil)
                    } else {
                        NotificationCenter.default.post(name: Notification.Name("ShowRecordCaptureUI"), object: nil)
                    }
                })
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
            
            // Global isometric radius bar overlay (visible on all tabs)
            VStack {
                Spacer()
                HStack {
                    Spacer(minLength: 0)
                    IsometricRadiusBar(radius: $isometricBarModel.radius, growthSpeed: 1.5, maxSceneHeight: 1.8, uiScale: 1.5, maxRuntimeRadius: 3_323_000.0)
                        .frame(width: 98, height: 390)
                        .rotation3DEffect(.degrees(-8), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
                        .animation(.interpolatingSpring(stiffness: 180, damping: 18), value: isometricBarModel.radius)
                        .padding(.trailing, isometricBarSettings.horizontalOffset)
                }
                .padding(.trailing, 8)
                .padding(.bottom, isometricBarSettings.bottomOffset) // Restored bottom alignment to first tick
                .background(Color.clear) // placeholder to keep structure; ticks assumed removed in IsometricRadiusBar component
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(.container, edges: [.bottom, .leading, .trailing])
            .zIndex(999)
            .allowsHitTesting(false)
            
        }
        
        // Inject global settings for isometric radius bar positioning
        .environment(\.isometricRadiusBarDistance, isometricBarSettings.horizontalOffset)
        .environment(\.isometricBarSettings, isometricBarSettings)
        .environment(\.isometricBarModel, isometricBarModel)
        
        .task {
            // Removed cameraController.prewarm() and preparePreviewIfNeeded() here per instructions
            
            // Minimal bootstrap: start location early (cheap) and trigger feed load if feed is initial tab
            locationProvider.request()
            if selectedTab == .feed, !didTriggerFeedInitialLoad {
                DispatchQueue.main.async {
                    didTriggerFeedInitialLoad = true
                    NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                }
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
                DispatchQueue.main.async {
                    didTriggerFeedInitialLoad = true
                    NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                }
            }
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
            }
            
            if !didPrewarmSceneKit {
                didPrewarmSceneKit = true
                DispatchQueue.main.async {
                    let tmpView = SCNView(frame: .init(x: 0, y: 0, width: 1, height: 1))
                    tmpView.scene = SCNScene()
                    tmpView.antialiasingMode = .none
                    tmpView.isPlaying = true
                    let box = SCNBox(width: 0.01, height: 0.01, length: 0.01, chamferRadius: 0)
                    let node = SCNNode(geometry: box)
                    tmpView.scene?.rootNode.addChildNode(node)
                    tmpView.prepare([box], completionHandler: { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            _ = tmpView
                        }
                    })
                }
            }
            
            print("[HomeView] onAppear work took \(CFAbsoluteTimeGetCurrent() - appearT0)s")
        }
        .onChange(of: selectedTab) { _ in
            animateYaw(to: yawForTab(selectedTab), duration: 0.45, direction: nil)

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
            if selectedTab != .record {
                isRecordHolding = false
                stopRecordHoldRamp(reset: false)
            }
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
            startRecordHoldRamp()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cameraCubeHoldEnded)) { _ in
            isRecordHolding = false
            stopRecordHoldRamp(reset: true)
        }
    }
    
    
}
final class BarCubePreviewTuning: ObservableObject {
    @Published var barHorizontalOffset: CGFloat = 23
    @Published var barBottomOffset: CGFloat = 24
    @Published var barTiltDegrees: Double = -8
    @Published var barWidth: CGFloat = 98
    @Published var barHeight: CGFloat = 390
}

private struct CubeAndBarOverlay: View {
    @Binding var radius: Double
    @ObservedObject var tuning: BarCubePreviewTuning

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                IsometricRadiusBar(radius: $radius, uiScale: 1.0)
                    .frame(width: tuning.barWidth, height: tuning.barHeight)
                    .rotation3DEffect(.degrees(tuning.barTiltDegrees), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
                    .padding(.trailing, tuning.barHorizontalOffset)
            }
            .padding(.trailing, 8)
            .padding(.bottom, max(8, tuning.barBottomOffset))
        }
        .allowsHitTesting(false)
    }
}

private struct HomeBarPlacementPreview: View {
    @State private var radius: Double = 0
    @StateObject private var tuning = BarCubePreviewTuning()
    @State private var selectedTab: AppTab = .record
    
    @State private var previewHover: Bool = false
    @State private var previewPopTrigger: Int = 0
    @State private var previewPopSoundEnabled: Bool = true
    
    @State private var previewHoldActive: Bool = false
    @State private var holdTask: Task<Void, Never>? = nil
    
    // Added state for continuous yaw
    @State private var yawDegrees: Double = 0
    
    var usesImperial: Bool { Locale.current.usesMetricSystem == false }
    var earthMaxUnit: Double { usesImperial ? 3958.8 : 6371.0 }
    
    // Added state to control animation flag
    @State private var previewAnimateTabChange: Bool = true
    
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
    
    private func rotatePreview(to newTab: AppTab, direction: RotationDirection) {
        // Animate the selectedTab change so CubeTabView performs a visible 90° rotation in the requested direction
        if previewAnimateTabChange {
            withAnimation(Animation.timingCurve(0.2, 0.8, 0.2, 1.0, duration: 1.0)) {
                selectedTab = newTab
            }
        } else {
            selectedTab = newTab
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

            CubeAndBarOverlay(radius: $radius, tuning: tuning)

            VStack {
                // Inserted segmented control picker for tab selection
                VStack {
                    Picker("Tab", selection: $selectedTab) {
                        Text("Record").tag(AppTab.record)
                        Text("Map").tag(AppTab.map)
                        Text("Profile").tag(AppTab.profile)
                        Text("Feed").tag(AppTab.feed)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 16)
                HStack(spacing: 12) {
                    Text("Simulate Swipe:")
                    Button("Left 90°") {
                        rotatePreview(to: previousPreviewTab(from: selectedTab), direction: .left)
                    }
                    .buttonStyle(.bordered)
                    Button("Right 90°") {
                        rotatePreview(to: nextPreviewTab(from: selectedTab), direction: .right)
                    }
                    .buttonStyle(.bordered)
                    Button("Pop") { previewPopTrigger += 1 }
                        .buttonStyle(.bordered)
                    Toggle("Hover", isOn: $previewHover)
                        .toggleStyle(.switch)
                }
                .padding(.horizontal, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Bar/Cube Placement Tuning").font(.headline)
                    HStack {
                        Text("Horizontal")
                        Slider(value: Binding(get: { Double(tuning.barHorizontalOffset) }, set: { tuning.barHorizontalOffset = CGFloat($0) }), in: 0...80)
                        Text("\(Int(tuning.barHorizontalOffset))").monospacedDigit()
                    }
                    HStack {
                        Text("Bottom")
                        Slider(value: Binding(get: { Double(tuning.barBottomOffset) }, set: { tuning.barBottomOffset = CGFloat($0) }), in: 0...80)
                        Text("\(Int(tuning.barBottomOffset))").monospacedDigit()
                    }
                    HStack {
                        Text("Tilt")
                        Slider(value: $tuning.barTiltDegrees, in: -25...0, step: 1)
                        Text("\(Int(tuning.barTiltDegrees))°").monospacedDigit()
                    }
                    HStack {
                        Text("Width")
                        Slider(value: Binding(get: { Double(tuning.barWidth) }, set: { tuning.barWidth = CGFloat($0) }), in: 64...128)
                        Text("\(Int(tuning.barWidth))").monospacedDigit()
                    }
                    HStack {
                        Text("Height")
                        Slider(value: Binding(get: { Double(tuning.barHeight) }, set: { tuning.barHeight = CGFloat($0) }), in: 260...480)
                        Text("\(Int(tuning.barHeight))").monospacedDigit()
                    }
                    HStack {
                        Text("Radius")
                        Slider(
                            value: Binding(
                                get: {
                                    // Convert meters to unit (km or mi)
                                    let meters = radius
                                    if usesImperial { return meters / 1609.34 } else { return meters / 1000.0 }
                                },
                                set: { unitValue in
                                    // Convert unit (km or mi) back to meters
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
                startPreviewHoldRamp()
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
    }
}

#Preview("HomeView Bar Placement") {
    HomeBarPlacementPreview()
}

