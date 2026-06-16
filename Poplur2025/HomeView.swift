import SwiftUI
import CoreLocation
import AVFoundation
import Combine
import MediaPlayer
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

private struct HomeCapturePreviewItem: Identifiable {
    let id = UUID()
    let image: UIImage?
    let videoURL: URL?
}

private struct HiddenSystemVolumeBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        view.showsVolumeSlider = true
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

private struct HomeFeedLaunchCover: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: 132, height: 132)
                .scaleEffect(pulse ? 1.04 : 0.96)
                .opacity(pulse ? 1.0 : 0.86)
                .animation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: pulse
                )
        }
        .onAppear {
            pulse = true
        }
    }
}

private extension Notification.Name {
    static let feedHardwareVolumeChanged = Notification.Name("FeedHardwareVolumeChanged")
}

@MainActor
private final class DeviceVolumeObserver: ObservableObject {
    @Published private(set) var level: Float
    @Published private(set) var isShowing: Bool = false

    private let session = AVAudioSession.sharedInstance()
    private var observation: NSKeyValueObservation?
    private var volumeNotificationObserver: NSObjectProtocol?
    private var refreshTimer: AnyCancellable?
    private var hideTask: Task<Void, Never>?
    private var volumePopPlayer: AVAudioPlayer?
    private var lastVolumePopTime: TimeInterval = 0
    private var isSuppressed = false

    init() {
        level = session.outputVolume

        if !PreviewEnvHomeView.isPreview {
            try? session.setActive(true)
            observation = session.observe(\.outputVolume, options: [.new]) { [weak self] session, change in
                let nextLevel = change.newValue ?? session.outputVolume
                Task { @MainActor in
                    self?.handleVolumeChange(nextLevel)
                }
            }
            volumeNotificationObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("AVSystemController_SystemVolumeDidChangeNotification"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let notifiedLevel = notification.userInfo?["AVSystemController_AudioVolumeNotificationParameter"] as? Float
                let nextLevel = notifiedLevel ?? AVAudioSession.sharedInstance().outputVolume
                NotificationCenter.default.post(name: .feedHardwareVolumeChanged, object: nil, userInfo: [
                    "level": nextLevel
                ])
                Task { @MainActor in
                    self?.handleVolumeChange(nextLevel, forceShow: true)
                }
            }
            refreshTimer = Timer.publish(every: 0.25, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.handleVolumeChange(self.session.outputVolume)
                }
        }
    }

    deinit {
        observation?.invalidate()
        if let volumeNotificationObserver {
            NotificationCenter.default.removeObserver(volumeNotificationObserver)
        }
        refreshTimer?.cancel()
        hideTask?.cancel()
        volumePopPlayer?.stop()
    }

    func showForHardwareVolumePress(level newLevel: Float? = nil) {
        if isSuppressed {
            setSuppressed(false)
        }
        handleVolumeChange(newLevel ?? session.outputVolume, forceShow: true)
    }

    func setSuppressed(_ suppressed: Bool) {
        isSuppressed = suppressed
        if suppressed {
            hideTask?.cancel()
            isShowing = false
        }
    }

    private func handleVolumeChange(_ newLevel: Float, forceShow: Bool = false) {
        let clampedLevel = max(0, min(1, newLevel))
        let changed = abs(clampedLevel - level) > 0.005
        level = clampedLevel
        guard !isSuppressed else { return }
        if changed || forceShow {
            playVolumePop()
            showTemporarily()
        }
    }

    private func playVolumePop() {
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastVolumePopTime > 0.08 else { return }
        lastVolumePopTime = now

        guard let url = Bundle.main.url(forResource: "pop", withExtension: "mp3") ?? Bundle.main.url(forResource: "pop", withExtension: "wav") else {
            AudioServicesPlaySystemSound(1104)
            return
        }

        do {
            try? session.setActive(true)
            if volumePopPlayer == nil {
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = 0
                player.volume = 0.9
                player.prepareToPlay()
                volumePopPlayer = player
            }
            volumePopPlayer?.currentTime = 0
            volumePopPlayer?.play()
        } catch {
            print("[VolumePop] Failed to play pop sound: \(error)")
            AudioServicesPlaySystemSound(1104)
        }
    }

    private func showTemporarily() {
        hideTask?.cancel()
        withAnimation(.easeOut(duration: 0.12)) {
            isShowing = true
        }
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            withAnimation(.easeIn(duration: 0.18)) {
                isShowing = false
            }
        }
    }
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

struct HomeCameraPreviewHost: UIViewControllerRepresentable {
    @ObservedObject var controller: CameraKitController

    func makeUIViewController(context: Context) -> UIViewController {
        // Removed controller.preparePreviewIfNeeded() per instructions
        let previewController = controller.recordPreviewViewController ?? controller.previewViewController ?? UIViewController()
        forceCameraPreviewLayout(in: previewController)
        return previewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        forceCameraPreviewLayout(in: uiViewController)
    }

    private func forceCameraPreviewLayout(in viewController: UIViewController) {
        if let previewController = viewController as? CameraPreviewViewController {
            previewController.forcePreviewLayout()
        }
        viewController.children.forEach(forceCameraPreviewLayout)
    }
}

@MainActor
private final class LazyHomeCameraControllerHolder: ObservableObject {
    @Published private(set) var controller: CameraKitController?
    private var cancellable: AnyCancellable?

    func resolve() -> CameraKitController {
        if let controller {
            return controller
        }

        let controller = CameraKitController()
        controller.preparePreviewIfNeeded()
        cancellable = controller.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        self.controller = controller
        return controller
    }

    func stopIfLoaded() {
        controller?.stop()
    }
}

@MainActor
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

    @StateObject private var cameraControllerHolder = LazyHomeCameraControllerHolder()

    // AR Filters
    @State private var arFilterManager: ARFilterManager?
    @State private var showARFilters = false

    // One-time flags to avoid doing heavy work repeatedly
    @State private var didTriggerFeedInitialLoad = false
    @State private var didTriggerMapInitialLoad = false
    @State private var didTriggerProfileInitialLoad = false
    @State private var enableLowerHitArea: Bool = false
    @State private var didApplyDefaultBarSettings = false
    @State private var didRunLaunchSequence = false
    @State private var bottomChromeVisible = false
    @State private var isFeedLaunchLoading = true
    @State private var feedLaunchSuppressionTask: Task<Void, Never>? = nil
    @State private var isMainTabChildRouteVisible = false

    // HUD sleep timer
    @State private var isChromeAsleep: Bool = false
    @State private var chromeSleepTask: Task<Void, Never>? = nil

    // Shared radius model controlling the global isometric bar value across all tabs
    @StateObject private var isometricBarModel = IsometricBarModel(radius: 0)

    // User recognition manager for face detection
    @State private var userRecognitionManager: UserRecognitionManager?

    @State private var recordHoldTask: Task<Void, Never>? = nil
    @State private var isRecordHolding: Bool = false

    // Recording countdown state
    @State private var isRecording: Bool = false
    @State private var recordingSecondsRemaining: Int = 10
    @State private var recordingTimer: Timer? = nil
    @State private var capturePreviewItem: HomeCapturePreviewItem? = nil
    @StateObject private var deviceVolumeObserver = DeviceVolumeObserver()

    // Post count state (for displaying user's total posts)
    @State private var userPostCount: Int = 0

    // Radius trend tracking for post count display
    @State private var previousRadius: Double? = nil
    @State private var radiusTrend: RadiusTrend = .neutral

    enum RadiusTrend {
        case up, down, neutral
    }

    private var isCubeVisibleOnCurrentRoute: Bool {
        [.map, .record, .feed, .profile].contains(selectedTab)
    }

    private var isLowerCubeHitAreaActive: Bool {
        isCubeVisibleOnCurrentRoute && !isMainTabChildRouteVisible
    }

    // Added state for cube yaw angle
    @State private var cubeYawDegrees: Double = 90

    // Added per instructions to control initial yaw set once
    @State private var didSetInitialCubeYaw: Bool = false

    // Upload status state
    @State private var showUploadStatus: Bool = false
    @State private var uploadStatusMessage: String = ""
    @State private var uploadStatusIcon: String = "arrow.up.circle.fill"
    @State private var uploadStatusColor: Color = .blue

    // In-app call
    @ObservedObject private var callManager = CallSessionManager.shared
    @State private var incomingCallInfo: (callerName: String, channelId: String, documentId: String)? = nil

    init() {
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
        Group {
            if let cameraController = cameraControllerHolder.controller {
                ZStack {
                    // Camera preview with UIKit gestures enabled
                    HomeCameraPreviewHost(controller: cameraController)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                        .allowsHitTesting(true)

                    if cameraController.isScreenFlashOn && cameraController.currentCameraPosition == .front {
                        FrontCameraFlashEdgeOverlay()
                            .ignoresSafeArea()
                            .transition(.opacity)
                            .zIndex(8)
                    }

                    if !showARFilters {
                        RecordCameraControlsOverlay(controller: cameraController)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: cameraController.isScreenFlashOn)
            } else {
                Color.black
                    .ignoresSafeArea()
            }
        }
        .onAppear {
            Task { @MainActor in
                // Removed guard !PreviewEnvHomeView.isPreview else { return }
                guard selectedTab == .record else { return }
                let cameraController = cameraControllerHolder.resolve()
                let status = AVCaptureDevice.authorizationStatus(for: .video)
                switch status {
                case .authorized:
                    let support = ensureRecordSupportManagers()
                    await cameraController.resumePreviewAfterInterruption()

                    // 🆕 Setup AR filter support
                    if let cameraVC = cameraController.recordPreviewViewController as? CameraPreviewViewController,
                       let displayLayer = cameraVC.displayLayer {
                        cameraController.setupARFilterSupport(
                            filterManager: support.filterManager,
                            displayLayer: displayLayer
                        )
                    }

                    // Enable ML detection with user recognition
                    cameraController.enableMLDetection()

                    // Setup user recognition callback
                    cameraController.mlDetectionManager?.onFrameProcessed = { [weak recognitionManager = support.recognitionManager] pixelBuffer, objects in
                        recognitionManager?.processDetectedObjects(objects, from: pixelBuffer)
                    }

                    // Start recognition session to pre-load user radius
                    await support.recognitionManager.startRecognitionSession()
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
            cameraControllerHolder.controller?.disableMLDetection()
            userRecognitionManager?.clearRecognition()
            // Reset filters and flag when leaving camera tab
            showARFilters = false
            arFilterManager?.activeFilter = .none
            UserDefaults.standard.set(false, forKey: "ARFiltersShown")
        }
    }

    private func ensureCameraRunningIfNeeded() {
        Task { @MainActor in
            guard !PreviewEnvHomeView.isPreview else { return }
            guard selectedTab == .record else {
                return
            }
            let cameraController = cameraControllerHolder.resolve()
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            switch status {
            case .authorized:
                await cameraController.resumePreviewAfterInterruption()
            case .notDetermined:
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                if granted {
                    await cameraController.resumePreviewAfterInterruption()
                }
            default:
                // denied or restricted — optionally present guidance UI
                break
            }
        }
    }

    @MainActor
    private func ensureRecordSupportManagers() -> (filterManager: ARFilterManager, recognitionManager: UserRecognitionManager) {
        if arFilterManager == nil {
            arFilterManager = ARFilterManager()
        }
        if userRecognitionManager == nil {
            userRecognitionManager = UserRecognitionManager()
        }
        return (arFilterManager!, userRecognitionManager!)
    }

    private func deferUntilAfterLaunch(_ work: @escaping @Sendable () async -> Void) {
        Task { @MainActor in
            await Task.yield()
            await work()
        }
    }

    @MainActor
    private func triggerFeedInitialLoadIfNeeded() {
        guard !didTriggerFeedInitialLoad else { return }
        didTriggerFeedInitialLoad = true
        NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
    }

    private func runLaunchSequenceIfNeeded() {
        guard !didRunLaunchSequence else { return }
        didRunLaunchSequence = true
        triggerFeedInitialLoadIfNeeded()
    }

    private func revealBottomChromeIfNeeded() {
        guard !bottomChromeVisible else { return }
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeOut(duration: 0.18)) {
                bottomChromeVisible = true
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
        guard !isRecording else { return }
        isRecording = true
        recordingSecondsRemaining = 10
        startCubeFlashing()
        cameraControllerHolder.resolve().beginRecording()

        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            DispatchQueue.main.async {
                self.recordingSecondsRemaining = max(0, self.recordingSecondsRemaining - 1)
                if self.recordingSecondsRemaining == 0 {
                    // Recording complete - stop everything
                    self.stopRecordingCountdown()
                    self.stopRecordHoldRamp(reset: true)
                }
            }
        }
    }

    private func stopRecordingCountdown() {
        let wasRecording = isRecording
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        stopCubeFlashing()
        if wasRecording {
            cameraControllerHolder.controller?.endRecording()
        }
    }

    private func startCubeFlashing() {
        NotificationCenter.default.post(name: Notification.Name("CubeStartFlashing"), object: nil)
    }

    private func stopCubeFlashing() {
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

    // MARK: - HUD sleep timer

    private func resetChromeSleepTimer() {
        guard SettingsStore.shared.hudSleepTimerEnabled else {
            if isChromeAsleep {
                withAnimation(.easeIn(duration: 0.35)) { isChromeAsleep = false }
            }
            return
        }
        chromeSleepTask?.cancel()
        if isChromeAsleep {
            withAnimation(.easeIn(duration: 0.35)) { isChromeAsleep = false }
        }
        chromeSleepTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.8)) { isChromeAsleep = true }
        }
    }

    private func putChromeToSleepImmediately() {
        chromeSleepTask?.cancel()
        withAnimation(.easeOut(duration: 0.5)) { isChromeAsleep = true }
    }

    // MARK: - Body split for type-checker performance

    private var rootStack: some View {
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

            HiddenSystemVolumeBridge()
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .opacity(0.01)

            // Upload Status Overlay
            if showUploadStatus && !isMainTabChildRouteVisible {
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
            if showARFilters,
               selectedTab == .record,
               let arFilterManager,
               let cameraController = cameraControllerHolder.controller {
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

            if let item = capturePreviewItem {
                CapturePreviewOverlay(
                    image: item.image,
                    videoURL: item.videoURL,
                    onDismiss: {
                        capturePreviewItem = nil
                    }
                )
                .transition(.opacity)
                .zIndex(900)
            }

            if let info = incomingCallInfo {
                IncomingCallView(
                    callerName: info.callerName,
                    channelId: info.channelId,
                    documentId: info.documentId
                )
                .transition(.opacity)
                .zIndex(900)
            }

            if isCubeVisibleOnCurrentRoute {
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
                .zIndex(6000)
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
                .opacity(isChromeAsleep ? 0.2 : 1)
                .allowsHitTesting(!isChromeAsleep)
            }

#if DEBUG
            // Invisible hit area temporarily disabled for input testing
            // (Re-enable after verifying CubeTabView touch responsiveness)
#else
            if enableLowerHitArea && isLowerCubeHitAreaActive {
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

            // Counter overlays share one row so their separator lines stay level.
            GeometryReader { proxy in
                let safe = proxy.safeAreaInsets

                VStack {
                    Spacer()
                    HStack(alignment: .counterSeparator) {
                        RecordingCountdownView(
                            isRecording: $isRecording,
                            secondsRemaining: $recordingSecondsRemaining,
                            postCount: $userPostCount,
                            selectedTab: $selectedTab,
                            radiusTrend: $radiusTrend
                        )
                        .frame(width: 150, alignment: .leading)

                        Spacer(minLength: 0)

                        // Choose your preferred radius display style:
                        // Option 1: Default card style (recommended)
                        RadiusNumberDisplay(radiusMeters: $isometricBarModel.radius)
                            .frame(width: 150, alignment: .trailing)

                        // Option 2: Compact badge style
                        // RadiusNumberBadge(radiusMeters: $isometricBarModel.radius)

                        // Option 3: Corner badge style
                        // RadiusCornerBadge(radiusMeters: $isometricBarModel.radius)

                        // Option 4: Icon-centered style
                        // RadiusDisplayWithIcon(radiusMeters: $isometricBarModel.radius)
                    }
                    .padding(.leading, safe.leading + (selectedTab == .map ? 0 : 16))
                    .padding(.trailing, safe.trailing + (selectedTab == .map ? 0 : 16))
                    .padding(.bottom, safe.bottom + 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .opacity(bottomChromeVisible && !isMainTabChildRouteVisible ? (isChromeAsleep ? 0.2 : 1) : 0)
                .onAppear {
                    revealBottomChromeIfNeeded()
                }
            }
            .ignoresSafeArea(.container, edges: [.bottom, .leading, .trailing])
            .zIndex(1001)
            .allowsHitTesting(false)

            if selectedTab == .feed && deviceVolumeObserver.isShowing && !isMainTabChildRouteVisible {
                GeometryReader { proxy in
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()

                            FeedVolumeBars(volumeLevel: deviceVolumeObserver.level)
                                .frame(width: 64, height: 320)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Volume \(Int(deviceVolumeObserver.level * 100)) percent")
                                .transition(.opacity)
                        }
                        .padding(.trailing, proxy.safeAreaInsets.trailing + 28)
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 170)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
                .zIndex(1002)
                .allowsHitTesting(false)
            }

            if selectedTab == .record && !isRecording {
                GeometryReader { proxy in
                    let safe = proxy.safeAreaInsets

                    VStack {
                        Spacer()
                        HStack {
                            CameraRollButton()
                            Spacer()
                        }
                        .padding(.leading, safe.leading + 28)
                        .padding(.bottom, safe.bottom + 20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                .zIndex(1000)
                .allowsHitTesting(true)
            }

            if selectedTab == .feed && isFeedLaunchLoading {
                HomeFeedLaunchCover()
                    .zIndex(900)
                    .transition(.opacity)
            }

        }
    }

    // MARK: - Body (split into steps to help Swift type-checker)
    var body: some View {
        // Step 1: apply environment values and lifecycle modifiers
        let step1 = rootStack
            .environment(\.isometricRadiusBarDistance, isometricBarSettings.horizontalOffset)
            .environment(\.isometricBarModel, isometricBarModel)
            .task {
                // Startup tasks deferred; nothing to do here
            }
            .onAppear {
                CallSessionManager.shared.startListeningForIncomingCalls()
                runLaunchSequenceIfNeeded()
                if selectedTab != .feed {
                    NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                }
                if selectedTab == .profile {
                    NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
                }
                if !didSetInitialCubeYaw {
                    didSetInitialCubeYaw = true
                    cubeYawDegrees = yawForTab(.feed)
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    await Task.yield()
                    enableLowerHitArea = false
                    if !didApplyDefaultBarSettings {
                        didApplyDefaultBarSettings = true
                        isometricBarSettings.horizontalOffset = 40
                        isometricBarSettings.bottomOffset = -80
                        isometricBarSettings.barWidth = 98
                        isometricBarSettings.barHeight = 390
                        isometricBarSettings.barTiltDegrees = -8
                    }
                }
                resetChromeSleepTimer()
            }
            .onChange(of: selectedTab) { _, newTab in
                if !didSetInitialCubeYaw {
                    didSetInitialCubeYaw = true
                    cubeYawDegrees = yawForTab(selectedTab)
                } else {
                    animateYaw(to: yawForTab(selectedTab), duration: 0.45, direction: nil)
                }
                if !([AppTab.map, .record, .feed, .profile].contains(selectedTab)) {
                    selectedTab = .feed
                }
                if newTab != .profile {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        isometricBarModel.radius = 0
                    }
                }
                if selectedTab == .feed {
                    NotificationCenter.default.post(name: .ResumeFeedAudio, object: nil)
                } else {
                    NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
                }
                if selectedTab == .record {
                    ensureCameraRunningIfNeeded()
                }
                if selectedTab == .profile {
                    if !PreviewEnvHomeView.isPreview {
                        cameraControllerHolder.stopIfLoaded()
                    }
                }
                NotificationCenter.default.post(name: .ResetTabToTop, object: nil)
                if selectedTab != .record {
                    isRecordHolding = false
                    stopRecordHoldRamp(reset: false)
                }
                enableLowerHitArea = (selectedTab != .record)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FeedLaunchLoadingDidStart"))) { _ in
                isFeedLaunchLoading = true
                deviceVolumeObserver.setSuppressed(true)
                feedLaunchSuppressionTask?.cancel()
                feedLaunchSuppressionTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { return }
                    isFeedLaunchLoading = false
                    deviceVolumeObserver.setSuppressed(false)
                    feedLaunchSuppressionTask = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FeedLaunchLoadingDidFinish"))) { _ in
                feedLaunchSuppressionTask?.cancel()
                feedLaunchSuppressionTask = nil
                isFeedLaunchLoading = false
                deviceVolumeObserver.setSuppressed(false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .MainTabChildRouteVisibilityChanged)) { notification in
                isMainTabChildRouteVisible = (notification.object as? Bool) ?? false
            }
            .onReceive(NotificationCenter.default.publisher(for: .feedHardwareVolumeChanged)) { notification in
                guard selectedTab == .feed else { return }
                if isFeedLaunchLoading {
                    feedLaunchSuppressionTask?.cancel()
                    feedLaunchSuppressionTask = nil
                    isFeedLaunchLoading = false
                    deviceVolumeObserver.setSuppressed(false)
                }
                let rawLevel = notification.userInfo?["level"]
                let level = (rawLevel as? Float) ?? (rawLevel as? Double).map(Float.init)
                deviceVolumeObserver.showForHardwareVolumePress(level: level)
            }
            .onChange(of: auth.isAuthenticated) { _, authed in
                if authed {
                    DispatchQueue.main.async {
                        selectedTab = .feed
                        runLaunchSequenceIfNeeded()
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    if selectedTab == .record {
                        ensureCameraRunningIfNeeded()
                    }
                case .background:
                    cameraControllerHolder.stopIfLoaded()
                    NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
                    NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                case .inactive:
                    NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
                    NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                @unknown default:
                    break
                }
            }
            .onChange(of: isPreviewRuntime) { _, isPreview in
                if isPreview {
                    if let mapped = AppTab(fromPreview: previewSelectedTab) {
                        selectedTab = mapped
                    }
                }
            }
            .onChange(of: previewSelectedTab) { _, tab in
                guard isPreviewRuntime else { return }
                if let mapped = AppTab(fromPreview: tab) {
                    selectedTab = mapped
                }
            }
            .onChange(of: selectedTab) { _, newTab in
                if newTab != .profile && routedUserID != nil {
                    routedUserID = nil
                }
            }

        // Step 2: apply notification receivers and remaining tasks
        return step1
            .onReceive(NotificationCenter.default.publisher(for: .SharedRadiusDidChange)) { note in
                if let value = note.userInfo?["radius"] as? Double {
                    isometricBarModel.radius = min(value, 3_323_000.0)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UserRecognizedInCamera"))) { note in
                if let radiusMeters = note.userInfo?["radius"] as? Double {
                    NotificationCenter.default.post(
                        name: .SharedRadiusDidChange,
                        object: nil,
                        userInfo: ["radius": radiusMeters]
                    )
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InlinePreviewDismissRequested"))) { _ in
                isometricBarModel.radius = 0
                NotificationCenter.default.post(name: .SharedRadiusDidChange, object: nil, userInfo: ["radius": 0.0])
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ToggleARFilters"))) { _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    if selectedTab == .record {
                        _ = cameraControllerHolder.resolve()
                        _ = ensureRecordSupportManagers()
                    }
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
                startRecordingCountdown()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cameraCubeHoldEnded)) { _ in
                guard selectedTab == .record else { return }
                isRecordHolding = false
                if !isRecording {
                    stopRecordHoldRamp(reset: true)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RecordingOutputReady"))) { notification in
                guard let url = notification.userInfo?["url"] as? URL else { return }
                capturePreviewItem = HomeCapturePreviewItem(image: nil, videoURL: url)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowCapturePreviewOverlay"))) { notification in
                if let image = notification.object as? UIImage {
                    capturePreviewItem = HomeCapturePreviewItem(image: image, videoURL: nil)
                } else if let url = notification.object as? URL {
                    capturePreviewItem = HomeCapturePreviewItem(image: nil, videoURL: url)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenCameraAtCoordinate"))) { notification in
                guard let userInfo = notification.userInfo,
                      let latitude = userInfo["latitude"] as? Double,
                      let longitude = userInfo["longitude"] as? Double else { return }
                selectedTab = .record
                NotificationCenter.default.post(
                    name: Notification.Name("SetCameraCoordinate"),
                    object: nil,
                    userInfo: ["latitude": latitude, "longitude": longitude]
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenMapToSelectPostLocation"))) { _ in
                selectedTab = .map
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowLocationOnMap"))) { notification in
                guard notification.userInfo?["coordinate"] is CLLocationCoordinate2D else { return }
                selectedTab = .map
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowLocationOnMapFromPost"))) { note in
                guard let userInfo = note.userInfo,
                      let latitude = userInfo["latitude"] as? Double,
                      let longitude = userInfo["longitude"] as? Double else { return }
                selectedTab = .map
                NotificationCenter.default.post(name: Notification.Name("ShowLocationOnMap"), object: nil, userInfo: [
                    "coordinate": CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                ])
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UploadPostToCoordinate"))) { notification in
                guard let userInfo = notification.userInfo,
                      let latitude = userInfo["latitude"] as? Double,
                      let longitude = userInfo["longitude"] as? Double else { return }
                uploadStatusMessage = "Uploading your post..."
                uploadStatusIcon = "arrow.up.circle.fill"
                uploadStatusColor = .blue
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showUploadStatus = true }
                NotificationCenter.default.post(
                    name: Notification.Name("SetCameraCoordinate"),
                    object: nil,
                    userInfo: ["latitude": latitude, "longitude": longitude]
                )
                if let image = userInfo["image"] as? UIImage {
                    NotificationCenter.default.post(name: Notification.Name("UploadImageToCurrentCoordinate"), object: image)
                } else if let videoURL = userInfo["videoURL"] as? URL {
                    NotificationCenter.default.post(name: Notification.Name("UploadVideoToCurrentCoordinate"), object: videoURL)
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    selectedTab = .profile
                    NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PostUploadStarted"))) { notification in
                uploadStatusMessage = notification.userInfo?["message"] as? String ?? "Uploading..."
                uploadStatusIcon = "arrow.up.circle.fill"
                uploadStatusColor = .blue
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showUploadStatus = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PostUploadSuccess"))) { _ in
                uploadStatusMessage = "Post uploaded successfully!"
                uploadStatusIcon = "checkmark.circle.fill"
                uploadStatusColor = .green
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showUploadStatus = true }
                NotificationCenter.default.post(name: Notification.Name("RefreshProfileAfterUpload"), object: nil)
                selectedTab = .profile
                NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showUploadStatus = false }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PostUploadFailed"))) { notification in
                let error = notification.userInfo?["error"] as? String ?? "Upload failed"
                uploadStatusMessage = error
                uploadStatusIcon = "xmark.circle.fill"
                uploadStatusColor = .red
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showUploadStatus = true }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showUploadStatus = false }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToFeedTab"))) { _ in }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToProfileTab"))) { _ in }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToMapTab"))) { _ in }
            .onReceive(NotificationCenter.default.publisher(for: .ShowUserProfile)) { note in
                if let uid = note.object as? String {
                    routedUserID = uid
                    selectedTab = .profile
                    NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowUserProfileContext"))) { note in
                if let userInfo = note.userInfo, let uid = userInfo["userID"] as? String {
                    routedUserID = uid
                    var forwardInfo: [String: Any] = ["userID": uid]
                    if let r = userInfo["radius"] as? Double { forwardInfo["radius"] = r }
                    if let pid = userInfo["currentPostID"] as? String { forwardInfo["currentPostID"] = pid }
                    NotificationCenter.default.post(name: Notification.Name("ProfileShowUserContext"), object: nil, userInfo: forwardInfo)
                    selectedTab = .profile
                    NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FeedCurrentPostContext"))) { note in
                if let userInfo = note.userInfo, let uid = userInfo["userID"] as? String {
                    routedUserID = uid
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .MapSuggestedRadius)) { note in
                if let value = note.userInfo?["radius"] as? Double {
                    let clampedValue = min(value, 3_323_000.0)
                    withAnimation(.easeInOut(duration: 2.0)) {
                        isometricBarModel.radius = clampedValue
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .currentPostRadiusDidChange)) { note in
                if let value = note.userInfo?["radius"] as? Double {
                    let duration = (note.userInfo?["duration"] as? Double) ?? 0.8
                    let clampedValue = min(value, 3_323_000.0)
                    let oldTrend = radiusTrend
                    if let prev = previousRadius {
                        if clampedValue > prev { radiusTrend = .up }
                        else if clampedValue < prev { radiusTrend = .down }
                        else { radiusTrend = .neutral }
                    } else {
                        radiusTrend = .neutral
                    }
                    previousRadius = clampedValue
                    _ = oldTrend
                    if duration <= 0 {
                        isometricBarModel.radius = clampedValue
                    } else {
                        withAnimation(.easeInOut(duration: duration)) {
                            isometricBarModel.radius = clampedValue
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .animateRadiusBarToValue)) { note in
                if let value = note.userInfo?["radius"] as? Double {
                    let duration = (note.userInfo?["duration"] as? Double) ?? 0.8
                    let clampedValue = min(value, 3_323_000.0)
                    if duration <= 0 {
                        isometricBarModel.radius = clampedValue
                    } else {
                        withAnimation(.easeInOut(duration: duration)) {
                            isometricBarModel.radius = clampedValue
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UserPostCountDidChange"))) { note in
                if let count = note.userInfo?["count"] as? Int {
                    userPostCount = count
                }
            }
            // ── In-app incoming call presentation ────────────────────────────
            .onChange(of: callManager.callState) { _, newState in
                if case .incoming(let callerName, let channelId, let documentId) = newState {
                    incomingCallInfo = (callerName, channelId, documentId)
                } else if incomingCallInfo != nil {
                    incomingCallInfo = nil
                }
            }
            // ─────────────────────────────────────────────────────────────────
            // ── HUD sleep timer ──────────────────────────────────────────────
            .onReceive(NotificationCenter.default.publisher(for: .popularPhoneDidPresent)) { _ in
                putChromeToSleepImmediately()
            }
            .simultaneousGesture(
                TapGesture().onEnded { resetChromeSleepTimer() }
            )
            // ─────────────────────────────────────────────────────────────────
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
    @State private var yawDegrees: Double = 90

    // Inserted states as per instructions:
    @State private var isPreviewRotating: Bool = false
    @State private var queuedPreviewTab: AppTab? = nil

    // Changed per instructions to EnvironmentObject
    @EnvironmentObject private var isometricBarSettings: IsometricBarSettings

    var usesImperial: Bool { Locale.current.measurementSystem != .metric }
    var earthMaxUnit: Double { usesImperial ? 3958.8 : 6371.0 }

    // Added state to control animation flag
    @State private var previewAnimateTabChange: Bool = true

    init(initialTab: AppTab = .feed) {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: previewHoldActive) { _, newValue in
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
        .onChange(of: selectedTab) { _, newValue in
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

// MARK: - Record Camera Controls

private struct RecordCameraControlsOverlay: View {
    @ObservedObject var controller: CameraKitController

    private var isFlashActive: Bool {
        controller.isTorchOn || controller.isScreenFlashOn
    }

    var body: some View {
        VStack {
            HStack {
                CameraIconControlButton(
                    systemName: isFlashActive ? "bolt.fill" : "bolt.slash.fill",
                    isActive: isFlashActive,
                    action: {
                        if isFlashActive {
                            controller.toggleTorchOff()
                        } else {
                            controller.toggleTorchOn()
                        }
                    }
                )

                Spacer()

                CameraIconControlButton(
                    systemName: "arrow.triangle.2.circlepath.camera.fill",
                    isActive: false,
                    action: {
                        controller.flipCamera()
                    }
                )
            }
            .padding(.top, 0)
            .padding(.horizontal, 18)

            Spacer()
        }
    }
}

private struct CameraIconControlButton: View {
    let systemName: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isActive ? Color.yellow : Color.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.38), in: Circle())
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemName.contains("bolt") ? "Toggle flash" : "Switch camera")
    }
}

private struct FrontCameraFlashEdgeOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            let edgeThickness = max(proxy.size.width, proxy.size.height) * 0.07

            ZStack {
                Color.clear

                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.white.opacity(0.5), Color.white.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: edgeThickness)

                    Spacer(minLength: 0)

                    LinearGradient(
                        colors: [Color.white.opacity(0), Color.white.opacity(0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: edgeThickness)
                }

                HStack(spacing: 0) {
                    LinearGradient(
                        colors: [Color.white.opacity(0.5), Color.white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: edgeThickness)

                    Spacer(minLength: 0)

                    LinearGradient(
                        colors: [Color.white.opacity(0), Color.white.opacity(0.5)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: edgeThickness)
                }
            }
            .blendMode(.screen)
        }
        .allowsHitTesting(false)
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

private struct FeedVolumeBars: View {
    let volumeLevel: Float

    private let barCount = 18
    private let meterGreen = Color(red: 0.23, green: 1.0, blue: 0.18)

    var body: some View {
        let activeLevel = Int(ceil(Double(max(0, min(1, volumeLevel))) * Double(barCount)))

        VStack(spacing: 6.4) {
            ForEach((0..<barCount).reversed(), id: \.self) { index in
                let active = index < activeLevel
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(meterGreen.opacity(active ? 1.0 : 0.18))
                    .shadow(color: meterGreen.opacity(active ? 0.55 : 0), radius: 3, x: 0, y: 0)
                    .frame(width: 32, height: 8)
            }
        }
        .frame(width: 64, height: 320)
        .drawingGroup()
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
