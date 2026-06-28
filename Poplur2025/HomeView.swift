import SwiftUI
import CoreLocation
import AVFoundation
import Combine
import MediaPlayer
import AudioToolbox
import Foundation
import SpriteKit

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
final class IsometricBarModel: ObservableObject {
    @Published var radius: Double
    init(radius: Double = 0) { self.radius = radius }
}

private struct HomeCapturePreviewItem: Identifiable {
    let id = UUID()
    let image: UIImage?
    let videoURL: URL?
}

private struct HomePostCaptureComposerItem: Identifiable {
    let id = UUID()
    let image: UIImage?
    let videoURL: URL?
    let coordinate: CLLocationCoordinate2D
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

// MARK: - HomeFeedLaunchCover
// Uses Core Animation exclusively: CAEmitterLayer (GPU confetti), CABasicAnimation /
// CAKeyframeAnimation (render-server transforms). These run in Apple's backboardd
// render-server process — completely immune to main-thread stalls during feed loading.

private struct HomeFeedLaunchCover: View {
    let showSlowDetails: Bool
    var body: some View {
        _LaunchCoverRep()
            .ignoresSafeArea()
    }
}

private struct _LaunchCoverRep: UIViewRepresentable {
    func makeUIView(context: Context) -> _LaunchCoverView { _LaunchCoverView() }
    func updateUIView(_ uiView: _LaunchCoverView, context: Context) {}
}

private final class _LaunchCoverView: UIView {

    // MARK: Sublayers / subviews
    private let emitter       = CAEmitterLayer()
    private let logoImageView: UIImageView = {
        let skin = CubeSkinStore.shared.current
        let image = UIImage(named: skin.logoAssetName) ?? UIImage(named: "logo")
        return UIImageView(image: image)
    }()
    private let trackLayer    = CALayer()
    private let fillLayer     = CALayer()
    private let phaseLabel    = UILabel()

    private let loadingBarWidth:  CGFloat = 200
    private let loadingBarHeight: CGFloat = 4

    // MARK: Phase cycling (main-thread timer — only text updates, not animation frames)
    private var phaseIdx   = 0
    private let phases: [String] = ([
        "scanning your social radius",
        "calibrating your neural feed",
        "learning local creator signals",
        "mapping nearby content",
        "ranking posts by proximity",
        "discovering your community",
        "processing social graph data",
        "tuning your experience",
        "building your intelligent feed",
        "syncing real-time signals",
        "personalizing your world",
        "analyzing nearby activity",
        "warming up AI radio voice",
        "loading radio voice model",
        "preparing Poplur Radio",
        "priming map voice system",
        "caching AI voice patterns",
        "preloading city radio scripts",
        "tuning the AI broadcast",
        "syncing radio to your area",
        "connecting to local broadcasts",
        "loading ambient map audio",
        "indexing creator sound profiles",
        "fetching area audio landscape",
        "streaming radio AI model",
        "loading proximity sound data",
        "loading area content signals",
        "building your map experience",
        "fetching live location data",
        "resolving nearby creators",
        "compiling your local scene",
        "loading discovery engine",
        "wiring up real-time feeds",
        "computing social clusters",
        "preparing AI insights",
    ] as [String]).shuffled()
    private var phaseTimer: Timer?
    private var popTimer:   Timer?
    private var started = false

    // MARK: Palette — matches WelcomeView confetti
    private static let palette: [UIColor] = [
        .systemPink, .systemOrange, .systemYellow,
        .systemGreen, .systemBlue, .systemPurple,
    ]

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        setupSubviews()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { phaseTimer?.invalidate(); popTimer?.invalidate() }

    // MARK: - Setup

    private func setupSubviews() {
        // Confetti — GPU particle system, never touches the main thread per frame
        emitter.emitterShape = .line
        emitter.renderMode   = .unordered
        emitter.emitterCells = makeConfettiCells()
        layer.addSublayer(emitter)

        logoImageView.contentMode = .scaleAspectFit
        logoImageView.alpha = 0
        addSubview(logoImageView)

        trackLayer.backgroundColor = UIColor.black.withAlphaComponent(0.12).cgColor
        trackLayer.cornerRadius = 2
        layer.addSublayer(trackLayer)

        // anchorPoint=(0, 0.5) keeps the left edge fixed while bounds.width animates rightward
        fillLayer.backgroundColor = UIColor(red: 0, green: 0.471, blue: 1, alpha: 1).cgColor
        fillLayer.cornerRadius    = 2
        fillLayer.anchorPoint     = CGPoint(x: 0, y: 0.5)
        layer.addSublayer(fillLayer)

        phaseLabel.textAlignment = .center
        phaseLabel.font          = .systemFont(ofSize: 14, weight: .medium)
        phaseLabel.textColor     = UIColor.black.withAlphaComponent(0.60)
        phaseLabel.numberOfLines = 2
        phaseLabel.text          = "AI \(phases[0])"
        addSubview(phaseLabel)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 1 else { return }

        let cx = bounds.midX, cy = bounds.midY
        let logoSz: CGFloat = 200
        let barY    = cy + logoSz / 2 + 28
        let barLeft = cx - loadingBarWidth / 2

        emitter.frame           = bounds
        emitter.emitterPosition = CGPoint(x: cx, y: -40)
        emitter.emitterSize     = CGSize(width: bounds.width + 400, height: bounds.height * 2)

        logoImageView.frame = CGRect(x: cx - logoSz/2, y: cy - logoSz/2, width: logoSz, height: logoSz)
        trackLayer.frame    = CGRect(x: barLeft, y: barY, width: loadingBarWidth, height: loadingBarHeight)

        if !started {
            // Set initial fill-layer geometry once, before the animation begins
            fillLayer.bounds   = CGRect(x: 0, y: 0, width: 8, height: loadingBarHeight)
            fillLayer.position = CGPoint(x: barLeft, y: barY + loadingBarHeight / 2)
        }

        phaseLabel.frame = CGRect(x: cx - 100, y: barY + loadingBarHeight + 10, width: 200, height: 44)

        if !started {
            started = true
            startAnimations()
        }
    }

    // MARK: - Confetti cells

    private func makeConfettiCells() -> [CAEmitterCell] {
        Self.palette.enumerated().map { i, color in
            let cell = CAEmitterCell()
            cell.birthRate         = 70
            cell.lifetime          = 7.5
            cell.lifetimeRange     = 1.5
            cell.velocity          = 120
            cell.velocityRange     = 80
            cell.emissionLongitude = .pi      // straight down
            cell.emissionRange     = .pi / 6
            cell.spin              = 3.0
            cell.spinRange         = .pi
            cell.scale             = 1.0
            cell.scaleRange        = 0.5
            cell.scaleSpeed        = -0.06
            cell.alphaRange        = 0.1
            cell.alphaSpeed        = -0.05
            cell.xAcceleration     = 25
            cell.yAcceleration     = 200
            cell.contents          = confettiCGImage(color: color)
            return cell
        }
    }

    private func confettiCGImage(color: UIColor) -> CGImage? {
        let size = CGSize(width: 8, height: 15)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }.cgImage
    }

    // MARK: - Animations

    private func startAnimations() {
        animateLogo()
        startLoadingLoop()
    }

    private func animateLogo() {
        UIView.animate(withDuration: 0.35) { self.logoImageView.alpha = 1 }

        let lyr = logoImageView.layer

        // Continuous rotation — render server, never pauses due to main-thread load
        let rot = CABasicAnimation(keyPath: "transform.rotation.z")
        rot.toValue     = Double.pi * 2
        rot.duration    = 12
        rot.repeatCount = .infinity
        rot.isRemovedOnCompletion = false
        lyr.add(rot, forKey: "rotation")

        // Entrance bounce: 0.35 → overshoot → settle at 1.0
        let entrance = CAKeyframeAnimation(keyPath: "transform.scale")
        entrance.values   = [0.35, 1.16, 0.91, 1.04, 1.0]
        entrance.keyTimes = [0,    0.56,  0.75, 0.88,  1.0]
        entrance.duration = 0.75
        entrance.isRemovedOnCompletion = true
        lyr.add(entrance, forKey: "entrance")

        // Pop loop — trigger is on the main thread, but the CAKeyframeAnimation
        // itself executes on the render server with no further main-thread involvement
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.firePop()
            self?.popTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
                self?.firePop()
            }
        }
    }

    private func firePop() {
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values   = [1.0, 1.42, 0.82, 1.12, 0.94, 1.0, 1.05, 0.95, 1.0]
        pop.keyTimes = [0,   0.045, 0.085, 0.12, 0.15, 0.18, 0.50, 0.77, 1.0]
        pop.duration = 2.0
        pop.isRemovedOnCompletion = true
        logoImageView.layer.add(pop, forKey: "pop")
    }

    // Bar cycles over and over until the loading screen is dismissed.
    // Each cycle the text advances to a new loading message.
    private func startLoadingLoop() {
        runBarCycle()
        phaseTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.phaseIdx = (self.phaseIdx + 1) % self.phases.count
            UIView.transition(with: self.phaseLabel, duration: 0.2, options: .transitionCrossDissolve) {
                self.phaseLabel.text = "AI \(self.phases[self.phaseIdx])"
            }
            self.runBarCycle()
        }
    }

    private func runBarCycle() {
        fillLayer.removeAnimation(forKey: "fill")
        // Reset width to near-zero without animation
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.bounds = CGRect(x: 0, y: 0, width: 8, height: loadingBarHeight)
        CATransaction.commit()

        let fill = CABasicAnimation(keyPath: "bounds")
        fill.fromValue      = NSValue(cgRect: CGRect(x: 0, y: 0, width: 8,              height: loadingBarHeight))
        fill.toValue        = NSValue(cgRect: CGRect(x: 0, y: 0, width: loadingBarWidth, height: loadingBarHeight))
        fill.duration       = 2.4
        fill.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fill.fillMode       = .forwards
        fill.isRemovedOnCompletion = false
        fillLayer.add(fill, forKey: "fill")
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
            // Defer audio session activation to avoid blocking the first render.
            // KVO observation and notification delivery work without an active session;
            // only playback (pop sound) requires it, which won't be needed immediately.
            Task { @MainActor in
                try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
                try? AVAudioSession.sharedInstance().setActive(true)
            }
            observation = session.observe(\.outputVolume, options: [.old, .new]) { [weak self] session, change in
                let nextLevel = change.newValue ?? session.outputVolume
                Task { @MainActor in
                    self?.handleVolumeChange(nextLevel, forceShow: true)
                }
            }
            volumeNotificationObserver = NotificationCenter.default.addObserver(
                forName: NSNotification.Name("AVSystemController_SystemVolumeDidChangeNotification"),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleSystemVolumeNotification(notification)
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

    private nonisolated func handleSystemVolumeNotification(_ notification: Notification) {
        let notifiedLevel = notification.userInfo?["AVSystemController_AudioVolumeNotificationParameter"] as? Float
        let reason = notification.userInfo?["AVSystemController_AudioVolumeChangeReasonNotificationParameter"] as? String
        let nextLevel = notifiedLevel ?? AVAudioSession.sharedInstance().outputVolume

        Task { @MainActor in
            NotificationCenter.default.post(name: .feedHardwareVolumeChanged, object: nil, userInfo: [
                "level": nextLevel,
                "reason": reason ?? "unknown"
            ])
            self.handleVolumeChange(nextLevel, forceShow: reason == nil || reason == "ExplicitVolumeChange")
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

private struct HomeViewIsPreviewRuntimeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct PreviewSelectedTabKey: EnvironmentKey {
    static let defaultValue: PreviewAppTab = .feed
}

extension EnvironmentValues {

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
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var cubeSkinStore = CubeSkinStore.shared

    @Environment(\.homeViewIsPreviewRuntime) private var isPreviewRuntime
    @Environment(\.previewSelectedTab) private var previewSelectedTab

    // Start on feed tab instead of record tab
    @State private var selectedTab: AppTab = .feed

    // Routed user ID when tapping on a username in Feed
    @State private var routedUserID: String? = nil

    // Post count of user detected by camera face recognition (nil when nobody detected)
    @State private var cameraDetectedPostCount: Int? = nil

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
    @State private var didRunLaunchSequence = false
    @State private var showAppInitializationCover = true
    @State private var showSlowInitializationDetails = false
    @State private var bottomChromeVisible = false
    @State private var isFeedLaunchLoading = false
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
    @StateObject private var feedCubeMenuWheel = CubeMenuWheelController()
    @StateObject private var cameraCubeMenuWheel = CubeMenuWheelController()
    @StateObject private var poplurAI = PoplurAIAssistantController()
    @State private var showFeedCommentComposer = false
    @State private var showLiveLocationPicker = false

    // Recording countdown state
    @State private var isRecording: Bool = false
    @State private var recordingSecondsRemaining: Int = 10
    @State private var recordingTimer: Timer? = nil
    @State private var capturePreviewItem: HomeCapturePreviewItem? = nil
    @State private var postCaptureComposerItem: HomePostCaptureComposerItem? = nil
    @State private var showCameraRollWindow = false
    @StateObject private var deviceVolumeObserver = DeviceVolumeObserver()

    // Post count state (for displaying user's total posts)
    @State private var userPostCount: Int = 0
    @State private var currentPostLikesCount: Int = 0

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

    private var shouldSleepChromeForCurrentTab: Bool {
        selectedTab == .feed && isChromeAsleep
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

    // Channel object animation (fires twice/minute while on feed tab)
    @State private var channelLogoVisible: Bool = false
    @State private var cubeHiddenForChannelLogo: Bool = false
    @State private var channelLogoInfo: (id: String, name: String, emoji: String) = ("music", "Music", "🎵")
    @State private var channelLogoObjectId: String = "star"
    @State private var channelLogoPeriodicTask: Task<Void, Never>? = nil
    @State private var channelLogoAnimTask: Task<Void, Never>? = nil
    @State private var channelLogoPopPlayer: AVAudioPlayer? = nil

    // MARK: - Channel Object Animation

    private func startChannelLogoTimer() {
        stopChannelLogoTimer()
        channelLogoPeriodicTask = Task { @MainActor in
            // First firing after 30 seconds
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            while !Task.isCancelled {
                triggerChannelLogoAnimation()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private func stopChannelLogoTimer() {
        channelLogoPeriodicTask?.cancel()
        channelLogoPeriodicTask = nil
        channelLogoAnimTask?.cancel()
        channelLogoAnimTask = nil
        channelLogoVisible = false
        cubeHiddenForChannelLogo = false
    }

    private func triggerChannelLogoAnimation() {
        guard selectedTab == .feed, !channelLogoVisible else { return }
        channelLogoObjectId = Self.randomChannelObject(for: channelLogoInfo.id)
        playChannelLogoPopSound()
        withAnimation(.spring(response: 0.26, dampingFraction: 0.65)) {
            cubeHiddenForChannelLogo = true
        }
        channelLogoAnimTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 340_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.12)) { channelLogoVisible = true }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { channelLogoVisible = false }
            try? await Task.sleep(nanoseconds: 210_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                cubeHiddenForChannelLogo = false
            }
            channelLogoAnimTask = nil
        }
    }

    private static func randomChannelObject(for channelId: String) -> String {
        let options: [String]
        switch channelId.lowercased() {
        case "food":
            options = ["banana", "cake", "fruit"]
        case "beauty", "style":
            options = ["lipstick", "compact", "sparkle"]
        case "sports", "fitness":
            options = ["ball", "trophy", "dumbbell"]
        case "modelling":
            options = ["camera", "spotlight", "star"]
        case "fashion", "shopping":
            options = ["dress", "shoe", "bag"]
        case "music":
            options = ["microphone", "note", "speaker"]
        case "tech", "gaming":
            options = ["laptop", "chip", "controller"]
        case "news":
            options = ["newspaper", "globe", "camera"]
        case "french":
            options = ["eiffel", "croissant", "beret"]
        case "spanish":
            options = ["guitar", "sun", "fan"]
        default:
            options = ["star", "globe", "sparkle"]
        }
        return options.randomElement() ?? "star"
    }

    private func playChannelLogoPopSound() {
        guard let url = Bundle.main.url(forResource: "pop", withExtension: "mp3")
            ?? Bundle.main.url(forResource: "pop", withExtension: "caf")
            ?? Bundle.main.url(forResource: "pop", withExtension: "wav") else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.volume = 0.85
            player.prepareToPlay()
            player.play()
            channelLogoPopPlayer = player
        } catch {}
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

                    if let recognitionManager = userRecognitionManager {
                        RecognizedFaceBoxOverlay(recognitionManager: recognitionManager)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                            .zIndex(7)
                    }

                    MLCameraShaderOverlay()
                        .allowsHitTesting(false)
                        .zIndex(8)
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
                    cameraController.userRecognitionManager = support.recognitionManager
                    cameraController.enableMLDetection()

                    // Setup user recognition callback
                    cameraController.mlDetectionManager?.onFrameProcessed = { [weak recognitionManager = support.recognitionManager] pixelBuffer, objects in
                        CameraAIAnnouncer.shared.announceMLObjects(objects)
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
            cameraControllerHolder.controller?.userRecognitionManager = nil
            userRecognitionManager?.clearRecognition()
            CameraAIAnnouncer.shared.resetSession()
            // Reset filters and flag when leaving camera tab
            showARFilters = false
            arFilterManager?.activeFilter = .none
            UserDefaults.standard.set(false, forKey: "ARFiltersShown")
        }
    }

    private func ensureCameraRunningIfNeeded() {
        Task { @MainActor in
            guard !PreviewEnvHomeView.isPreview else { return }
            guard selectedTab == .record else { return }
            let cameraController = cameraControllerHolder.resolve()
            // Skip if already running — resumePreviewAfterInterruption flushes the display layer
            // and re-wires the session, causing a visible freeze when called unnecessarily.
            guard !cameraController.captureSession.isRunning else { return }
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
        Task { await PoplurMapRadioHost.shared.prewarm() }
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

    @MainActor
    private func showCompletedVideoPreview(url: URL) {
        selectedTab = .record
        cameraCubeMenuWheel.endHold(activateSelected: false)
        isRecordHolding = false
        stopRecordHoldRamp(reset: true)
        withAnimation(.easeInOut(duration: 0.18)) {
            capturePreviewItem = HomeCapturePreviewItem(image: nil, videoURL: url)
        }
    }

    private var cameraCubeMenuItems: [CubeSubmenuItem] {
        [
            CubeSubmenuItem(
                id: "camera-photo",
                title: "Photo",
                systemImage: "camera.fill",
                tint: .green,
                action: triggerCameraPhotoFromCubeMenu
            ),
            CubeSubmenuItem(
                id: "camera-video",
                title: "Video",
                systemImage: "video.fill",
                tint: .indigo,
                action: triggerCameraVideoFromCubeMenu
            ),
            CubeSubmenuItem(
                id: "camera-live",
                title: "Live",
                systemImage: "dot.radiowaves.left.and.right",
                tint: .red,
                action: toggleLiveVideoFromCubeMenu
            ),
            CubeSubmenuItem(
                id: "camera-ar-filters",
                title: "AR",
                systemImage: "sparkles",
                tint: .cyan,
                action: openARFiltersFromCubeMenu
            )
        ]
    }

    private var feedCubeMenuItems: [CubeSubmenuItem] {
        [
            CubeSubmenuItem(
                id: "feed-like",
                title: "Like",
                systemImage: "heart.fill",
                tint: .pink,
                action: {
                    NotificationCenter.default.post(name: .FeedLikeCurrentPost, object: nil)
                }
            ),
            CubeSubmenuItem(
                id: "feed-comment",
                title: "Comment",
                systemImage: "bubble.left.and.bubble.right.fill",
                tint: .cyan,
                action: {
                    NotificationCenter.default.post(name: .FeedOpenCommentComposer, object: nil)
                }
            ),
            CubeSubmenuItem(
                id: "feed-profile",
                title: "Profile",
                systemImage: "person.crop.circle.fill",
                tint: .indigo,
                action: {
                    NotificationCenter.default.post(name: .FeedOpenCurrentPostProfile, object: nil)
                }
            ),
            CubeSubmenuItem(
                id: "feed-news",
                title: "News",
                systemImage: "newspaper.fill",
                tint: .red,
                action: {
                    NotificationCenter.default.post(name: .FeedOpenNews, object: nil)
                }
            ),
            CubeSubmenuItem(
                id: "feed-tv-guide",
                title: "TV Guide",
                systemImage: "tv.fill",
                tint: .green,
                action: {
                    NotificationCenter.default.post(name: .FeedOpenTVGuide, object: nil)
                }
            ),
            CubeSubmenuItem(
                id: "feed-captions",
                title: settings.closedCaptionsEnabled ? "CC On" : "CC Off",
                systemImage: "text.bubble.fill",
                tint: settings.closedCaptionsEnabled ? .mint : .gray,
                action: {
                    settings.toggleClosedCaptions()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
            )
        ]
    }

    @MainActor
    private func openFeedCommentComposer() {
        guard selectedTab == .feed else { return }
        chromeSleepTask?.cancel()
        chromeSleepTask = nil
        isMainTabChildRouteVisible = true
        withAnimation(.spring(response: 0.36, dampingFraction: 0.78)) {
            isChromeAsleep = true
            showFeedCommentComposer = true
        }
    }

    @MainActor
    private func closeFeedCommentComposer() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            showFeedCommentComposer = false
        }
        isMainTabChildRouteVisible = false
        resetChromeSleepTimer()
    }

    @MainActor
    private func submitFeedComment(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NotificationCenter.default.post(name: .FeedCommentSubmitted, object: trimmed)
        closeFeedCommentComposer()
    }

    @MainActor
    private func triggerCameraPhotoFromCubeMenu() {
        guard selectedTab == .record else { return }
        guard !cameraControllerHolder.resolve().isLiveVideoActive else { return }
        ensureCameraRunningIfNeeded()
        NotificationCenter.default.post(name: .cameraCubeTabViewTapped, object: nil)
    }

    @MainActor
    private func triggerCameraVideoFromCubeMenu() {
        guard selectedTab == .record, !isRecording else { return }
        let controller = cameraControllerHolder.resolve()
        guard !controller.isLiveVideoActive else { return }
        isRecordHolding = true
        ensureCameraRunningIfNeeded()
        startRecordHoldRamp()
        startRecordingCountdown()
    }

    @MainActor
    private func toggleLiveVideoFromCubeMenu() {
        guard selectedTab == .record else { return }
        let controller = cameraControllerHolder.resolve()
        isRecordHolding = false
        if isRecording {
            stopRecordingCountdown()
        }
        stopRecordHoldRamp(reset: true)
        ensureCameraRunningIfNeeded()
        if controller.isLiveVideoActive {
            controller.stopLiveVideo()
            LiveVideoSessionStore.shared.stopLocalSession()
            isMainTabChildRouteVisible = false
        } else {
            openLiveLocationPicker()
        }
    }

    @MainActor
    private func openLiveLocationPicker() {
        locationProvider.request()
        isMainTabChildRouteVisible = true
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            showLiveLocationPicker = true
        }
    }

    @MainActor
    private func closeLiveLocationPicker() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
            showLiveLocationPicker = false
        }
        isMainTabChildRouteVisible = false
    }

    @MainActor
    private func startLiveVideo(at location: LiveBroadcastLocation) {
        let controller = cameraControllerHolder.resolve()
        ensureCameraRunningIfNeeded()
        if isRecording {
            stopRecordingCountdown()
        }
        stopRecordHoldRamp(reset: true)
        controller.startLiveVideo(
            at: location.coordinate,
            locationName: location.title,
            radiusMeters: location.radiusMeters,
            initialViewers: 128
        )
        _ = LiveVideoSessionStore.shared.startLocalSession(
            at: location,
            viewerCount: controller.liveViewerCount
        )
        closeLiveLocationPicker()
    }

    private var liveLocationChoices: [LiveBroadcastLocation] {
        var choices: [LiveBroadcastLocation] = []
        if let coordinate = locationProvider.coordinate {
            choices.append(
                LiveBroadcastLocation(
                    id: "current-location",
                    title: "Current Spot",
                    subtitle: "Use your current camera location",
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    radiusMeters: max(isometricBarModel.radius, 5_000)
                )
            )
        }
        choices.append(contentsOf: LiveVideoSessionStore.defaultLocationChoices)
        return choices
    }

    @MainActor
    private func openARFiltersFromCubeMenu() {
        guard selectedTab == .record else { return }
        _ = cameraControllerHolder.resolve()
        _ = ensureRecordSupportManagers()
        ensureCameraRunningIfNeeded()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showARFilters = true
        }
        UserDefaults.standard.set(true, forKey: "ARFiltersShown")
        NotificationCenter.default.post(
            name: Notification.Name("ARFiltersStateChanged"),
            object: nil,
            userInfo: ["isShown": true]
        )
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

    @MainActor
    private func handlePoplurAICommand(_ command: PoplurAICommand?) {
        guard let command else { return }
        resetChromeSleepTimer()

        switch command {
        case .openTab(let tab):
            selectedTab = tab
        case .openPage(let page):
            openPoplurAIPage(page)
        case .goToChannel(let query):
            selectedTab = .feed
            NotificationCenter.default.post(
                name: .PoplurAIGoToFeedChannel,
                object: nil,
                userInfo: ["query": query]
            )
        case .postToLocation(let location):
            selectedTab = .map
            NotificationCenter.default.post(
                name: .PoplurAIStartMapPost,
                object: nil,
                userInfo: ["location": location ?? ""]
            )
        case .camera(let mode):
            selectedTab = .record
            ensureCameraRunningIfNeeded()
            switch mode {
            case .open:
                break
            case .photo:
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    triggerCameraPhotoFromCubeMenu()
                }
            case .video:
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    triggerCameraVideoFromCubeMenu()
                }
            }
        case .setTourActive(let active):
            selectedTab = .map
            NotificationCenter.default.post(
                name: .PoplurAISetTourActive,
                object: nil,
                userInfo: ["active": active]
            )
        case .logout:
            auth.signOut()
        case .sortPosts(let order):
            selectedTab = .profile
            NotificationCenter.default.post(
                name: .PoplurAIProfileSortRequested,
                object: nil,
                userInfo: ["order": order.rawValue]
            )
        case .showAnalytics:
            selectedTab = .profile
            NotificationCenter.default.post(name: .PoplurAIShowAnalytics, object: nil)
        case .unknown:
            break
        }
    }

    @MainActor
    private func openPoplurAIPage(_ page: String) {
        let normalized = page.lowercased()
        if normalized.contains("tv guide") {
            selectedTab = .feed
            NotificationCenter.default.post(name: .FeedOpenTVGuide, object: nil)
        } else if normalized.contains("message") || normalized.contains("mail") || normalized.contains("dm") {
            selectedTab = .profile
            NotificationCenter.default.post(name: .OpenDMsRequested, object: nil)
        } else if normalized.contains("setting") {
            selectedTab = .profile
            NotificationCenter.default.post(name: .OpenSettingsRequested, object: nil)
        } else if normalized.contains("stat") || normalized.contains("analytic") {
            selectedTab = .profile
            NotificationCenter.default.post(name: .PoplurAIShowAnalytics, object: nil)
        } else if normalized.contains("map") {
            selectedTab = .map
        } else if normalized.contains("camera") || normalized.contains("record") {
            selectedTab = .record
        } else if normalized.contains("profile") {
            selectedTab = .profile
        } else {
            selectedTab = .feed
        }
    }

    @ViewBuilder
    private var feedTabContent: some View {
        FeedView(homeChromeInactive: selectedTab == .feed && isChromeAsleep)
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
        chromeSleepTask?.cancel()
        chromeSleepTask = nil
        if showFeedCommentComposer {
            if !isChromeAsleep {
                withAnimation(.easeOut(duration: 0.35)) { isChromeAsleep = true }
            }
            return
        }
        // Only auto-sleep on the feed tab; on all other tabs keep chrome awake
        guard selectedTab == .feed, !isMainTabChildRouteVisible else {
            if isChromeAsleep {
                withAnimation(.easeIn(duration: 0.35)) { isChromeAsleep = false }
            }
            return
        }
        if isChromeAsleep {
            withAnimation(.easeIn(duration: 0.35)) { isChromeAsleep = false }
        }
        chromeSleepTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000) // 1 minute
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.8)) { isChromeAsleep = true }
        }
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

            FeedChromeNotificationBridge(
                isActive: selectedTab == .feed,
                onHoldBegan: {
                    resetChromeSleepTimer()
                    feedCubeMenuWheel.beginHold(items: feedCubeMenuItems)
                },
                onHoldEnded: {
                    resetChromeSleepTimer()
                    feedCubeMenuWheel.endHold(activateSelected: true)
                },
                onInteraction: resetChromeSleepTimer
            )
            .allowsHitTesting(false)

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
                .zIndex(7200)
            }

            if let item = postCaptureComposerItem {
                PostCaptureComposerOverlay(
                    image: item.image,
                    videoURL: item.videoURL,
                    coordinate: item.coordinate,
                    onDismiss: {
                        postCaptureComposerItem = nil
                    }
                )
                .transition(.opacity)
                .zIndex(7250)
            }

            CubeMenuWheelOverlay(controller: cameraCubeMenuWheel)
                .opacity(selectedTab == .record ? 1 : 0)
                .zIndex(6100)

            CubeMenuWheelOverlay(controller: feedCubeMenuWheel)
                .opacity(selectedTab == .feed ? 1 : 0)
                .zIndex(6101)

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
                // 3D Cube tab control overlay — pinned to bottom
                VStack(alignment: .center) {
                    Spacer()
                    ZStack(alignment: .center) {
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
                        .scaleEffect(cubeHiddenForChannelLogo ? 0.01 : 1.0)
                        .opacity(cubeHiddenForChannelLogo ? 0 : 1)
                        .animation(.spring(response: 0.26, dampingFraction: 0.65), value: cubeHiddenForChannelLogo)

                        if channelLogoVisible {
                            ChannelObjectSceneView(
                                channelId: channelLogoInfo.id,
                                objectId: channelLogoObjectId
                            )
                            .allowsHitTesting(false)
                            .frame(width: 200, height: 200)
                            .transition(.scale(scale: 0.01).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 230, maxHeight: 230)
                    .animation(.easeInOut(duration: 0.15), value: channelLogoVisible)
                    .padding(.bottom, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
                .ignoresSafeArea(edges: .bottom)
                .animation(.easeInOut(duration: 0.15), value: channelLogoVisible)
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
                .opacity(shouldSleepChromeForCurrentTab ? 0.2 : 1)
                .allowsHitTesting(!shouldSleepChromeForCurrentTab)
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
                            likesCount: $currentPostLikesCount,
                            selectedTab: $selectedTab,
                            radiusTrend: $radiusTrend,
                            detectedUserPostCount: cameraDetectedPostCount
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
                    .padding(.leading, safe.leading + 16)
                    .padding(.trailing, safe.trailing + 16)
                    .padding(.bottom, safe.bottom + 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transaction { transaction in
                    transaction.animation = nil
                }
                .opacity(bottomChromeVisible && !isMainTabChildRouteVisible ? (shouldSleepChromeForCurrentTab ? 0.2 : 1) : 0)
                .onAppear {
                    revealBottomChromeIfNeeded()
                }
            }
            .ignoresSafeArea(.container, edges: [.bottom, .leading, .trailing])
            .zIndex(1001)
            .allowsHitTesting(false)

            if deviceVolumeObserver.isShowing {
                GeometryReader { proxy in
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()

                            PoplurVolumeBars(volumeLevel: deviceVolumeObserver.level)
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

            if showFeedCommentComposer {
                FeedCommentComposerOverlay(
                    onSubmit: submitFeedComment,
                    onDismiss: closeFeedCommentComposer
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.84).combined(with: .opacity),
                    removal: .scale(scale: 0.94).combined(with: .opacity)
                ))
                .zIndex(7000)
            }

            if showLiveLocationPicker {
                LiveLocationPickerOverlay(
                    locations: liveLocationChoices,
                    onSelect: startLiveVideo,
                    onDismiss: closeLiveLocationPicker
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.88).combined(with: .opacity),
                    removal: .scale(scale: 0.96).combined(with: .opacity)
                ))
                .zIndex(7060)
            }

            if showCameraRollWindow && selectedTab == .record {
                CameraRollWindowOverlay(
                    onDismiss: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            showCameraRollWindow = false
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .zIndex(7080)
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

            PoplurAIAssistantOverlay(
                controller: poplurAI,
                accent: cubeSkinStore.current.appTheme.accent
            )
            .zIndex(9500)

        }
    }

    // MARK: - Notification receivers (split to help Swift type-checker)

    private var notificationReceiversB: some View {
        Color.clear
            .onReceive(NotificationCenter.default.publisher(for: .showPostCaptureEditor)) { notification in
                guard let userInfo = notification.userInfo,
                      let latitude = userInfo["latitude"] as? Double,
                      let longitude = userInfo["longitude"] as? Double else { return }
                let image = userInfo["image"] as? UIImage
                let videoURL = userInfo["videoURL"] as? URL
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                postCaptureComposerItem = HomePostCaptureComposerItem(
                    image: image,
                    videoURL: videoURL,
                    coordinate: coordinate
                )
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
                    // Auto-dismiss after navigating to profile — PostUploadSuccess is never
                    // guaranteed to fire, so don't leave the banner stuck.
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { showUploadStatus = false }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PostUploadStarted"))) { notification in
                uploadStatusMessage = "Uploading your post..."
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
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToFeedTab"))) { _ in
                selectedTab = .feed
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SwitchToProfileTab"))) { _ in
                selectedTab = .profile
                NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
            }
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
            .onReceive(NotificationCenter.default.publisher(for: .PoplurAIShowWakeTutorial)) { _ in
                poplurAI.start()
                poplurAI.showWakeTutorialPulse()
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
                    if let count = note.userInfo?["postCount"] as? Int {
                        userPostCount = count
                    }
                    if let likes = note.userInfo?["likesCount"] as? Int {
                        currentPostLikesCount = likes
                    }
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
            .onChange(of: callManager.callState) { _, newState in
                if case .incoming(let callerName, let channelId, let documentId) = newState {
                    incomingCallInfo = (callerName, channelId, documentId)
                } else if incomingCallInfo != nil {
                    incomingCallInfo = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .popularPhoneDidPresent)) { _ in
                resetChromeSleepTimer()
            }
    }

    // MARK: - Body (split into steps to help Swift type-checker)
    var body: some View {
        // Step 1: apply environment values and lifecycle modifiers
        let step1 = rootStack
            .task {
                guard showAppInitializationCover else { return }
                // Show loading bar + text immediately
                withAnimation(.easeOut(duration: 0.18)) {
                    showSlowInitializationDetails = true
                }
                // Long safety-net only; the feed-ready notification should dismiss the cover.
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                withAnimation(.easeOut(duration: 0.30)) {
                    showAppInitializationCover = false
                    showSlowInitializationDetails = false
                }
            }
            .onAppear {
                if !PreviewEnvHomeView.isPreview {
                    poplurAI.start()
                }
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
                }
                resetChromeSleepTimer()
                if selectedTab == .feed {
                    startChannelLogoTimer()
                }
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
                    NotificationCenter.default.post(name: .StopMapAudio, object: nil)
                }
                if selectedTab == .profile {
                    if !PreviewEnvHomeView.isPreview {
                        cameraControllerHolder.stopIfLoaded()
                    }
                }
                NotificationCenter.default.post(name: .ResetTabToTop, object: nil)
                if selectedTab != .record {
                    isRecordHolding = false
                    showCameraRollWindow = false
                    cameraCubeMenuWheel.endHold(activateSelected: false)
                    stopRecordHoldRamp(reset: false)
                }
                if selectedTab != .feed {
                    feedCubeMenuWheel.endHold(activateSelected: false)
                    if showFeedCommentComposer {
                        showFeedCommentComposer = false
                        isMainTabChildRouteVisible = false
                    }
                    stopChannelLogoTimer()
                } else {
                    startChannelLogoTimer()
                }
                enableLowerHitArea = (selectedTab != .record)
                resetChromeSleepTimer()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FeedLaunchLoadingDidStart"))) { _ in
                isFeedLaunchLoading = true
                deviceVolumeObserver.setSuppressed(true)
                feedLaunchSuppressionTask?.cancel()
                feedLaunchSuppressionTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.50)) {
                        isFeedLaunchLoading = false
                    }
                    deviceVolumeObserver.setSuppressed(false)
                    feedLaunchSuppressionTask = nil
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("FeedLaunchLoadingDidFinish"))) { _ in
                feedLaunchSuppressionTask?.cancel()
                feedLaunchSuppressionTask = nil
                withAnimation(.easeOut(duration: 0.50)) {
                    isFeedLaunchLoading = false
                }
                deviceVolumeObserver.setSuppressed(false)
                withAnimation(.easeOut(duration: 0.40)) {
                    showAppInitializationCover = false
                    showSlowInitializationDetails = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .MainTabChildRouteVisibilityChanged)) { notification in
                isMainTabChildRouteVisible = (notification.object as? Bool) ?? false
                resetChromeSleepTimer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .FeedChannelDidChange)) { notification in
                if let info = notification.userInfo,
                   let id = info["id"] as? String,
                   let name = info["name"] as? String,
                   let emoji = info["emoji"] as? String {
                    channelLogoInfo = (id: id, name: name, emoji: emoji)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .feedHardwareVolumeChanged)) { notification in
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
                    if !PreviewEnvHomeView.isPreview {
                        poplurAI.start()
                    }
                    if selectedTab == .record {
                        ensureCameraRunningIfNeeded()
                    }
                    if selectedTab == .feed {
                        NotificationCenter.default.post(name: .ResumeFeedAudio, object: nil)
                    }
                case .background:
                    poplurAI.stop()
                    cameraControllerHolder.stopIfLoaded()
                    NotificationCenter.default.post(name: .PauseFeedAudio, object: nil)
                    NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                case .inactive:
                    poplurAI.stop()
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
                if newTab != .record { cameraDetectedPostCount = nil }
                if newTab != .profile && routedUserID != nil {
                    routedUserID = nil
                }
            }
            .onChange(of: poplurAI.commandToken) { _, _ in
                handlePoplurAICommand(poplurAI.lastCommand)
            }

        // Step 2: apply notification receivers and remaining tasks
        return step1
            .onReceive(NotificationCenter.default.publisher(for: .FeedOpenCommentComposer)) { _ in
                openFeedCommentComposer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .SharedRadiusDidChange)) { note in
                if let value = note.userInfo?["radius"] as? Double {
                    isometricBarModel.radius = min(value, 3_323_000.0)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CachedUserRadius"))) { note in
                if let value = note.userInfo?["radius"] as? Double {
                    isometricBarModel.radius = min(max(value, 0), 3_323_000.0)
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
                cameraDetectedPostCount = note.userInfo?["postCount"] as? Int
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
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LiveVideoNeedsLocation"))) { _ in
                guard selectedTab == .record else { return }
                openLiveLocationPicker()
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LiveVideoDidStop"))) { _ in
                LiveVideoSessionStore.shared.stopLocalSession()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showCameraRollWindow)) { _ in
                guard selectedTab == .record else { return }
                withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                    showCameraRollWindow = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cameraCubeHoldBegan)) { _ in
                guard selectedTab == .record else { return }
                isRecordHolding = true
                ensureCameraRunningIfNeeded()
                cameraCubeMenuWheel.beginHold(items: cameraCubeMenuItems)
            }
            .onReceive(NotificationCenter.default.publisher(for: .cameraCubeHoldEnded)) { _ in
                guard selectedTab == .record else { return }
                isRecordHolding = false
                cameraCubeMenuWheel.endHold(activateSelected: true)
                if !isRecording {
                    stopRecordHoldRamp(reset: true)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RecordingOutputReady"))) { notification in
                guard let url = notification.userInfo?["url"] as? URL else { return }
                showCompletedVideoPreview(url: url)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ShowCapturePreviewOverlay"))) { notification in
                if let image = notification.object as? UIImage {
                    capturePreviewItem = HomeCapturePreviewItem(image: image, videoURL: nil)
                } else if let url = notification.object as? URL {
                    showCompletedVideoPreview(url: url)
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
            .background(notificationReceiversB)
            .simultaneousGesture(
                TapGesture().onEnded {
                    if selectedTab == .feed && isChromeAsleep {
                        return
                    }
                    resetChromeSleepTimer()
                }
            )
            .overlay {
                if showAppInitializationCover {
                    HomeFeedLaunchCover(showSlowDetails: showSlowInitializationDetails)
                        .ignoresSafeArea()
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeOut(duration: 0.30), value: showAppInitializationCover)
            .animation(.easeOut(duration: 0.18), value: showSlowInitializationDetails)
            .preferredColorScheme(settings.colorSchemePreference.colorScheme)
            // ─────────────────────────────────────────────────────────────────
    }
}

private struct FeedCommentComposerOverlay: View {
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void

    @ObservedObject private var settings = SettingsStore.shared
    @State private var draft = ""
    @State private var isPresented = false
    @State private var glitterScene = FeedCommentComposerGlitterScene.make()
    @FocusState private var isFocused: Bool

    private var canSubmit: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.46)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onDismiss()
                    }

                VStack(spacing: 16) {
                    composerCard(in: proxy.size)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 20)
                .padding(.bottom, proxy.safeAreaInsets.bottom + 74)
                .modifier(
                    ComposerTransitionMotion(
                        style: settings.transitionStylePreference,
                        isPresented: isPresented
                    )
                )
                .animation(.spring(response: 0.42, dampingFraction: 0.72), value: isPresented)
            }
        }
        .onAppear {
            isPresented = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                isFocused = true
            }
        }
    }

    private func composerCard(in size: CGSize) -> some View {
        let width = min(size.width - 40, 430)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.sparkles.fill")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(.cyan)

                Text("Comment")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.black.opacity(0.36), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            ZStack(alignment: .topLeading) {
                SpriteView(scene: glitterScene, options: [.allowsTransparency])
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .allowsHitTesting(false)

                TextEditor(text: $draft)
                    .focused($isFocused)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .tint(.cyan)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(14)

                if draft.isEmpty {
                    Text("Say it like the lights are still rolling...")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.44))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 168)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.05, green: 0.04, blue: 0.09).opacity(0.94),
                                Color(red: 0.12, green: 0.03, blue: 0.11).opacity(0.86),
                                Color(red: 0.02, green: 0.10, blue: 0.13).opacity(0.88)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.cyan.opacity(0.95), .pink.opacity(0.84), .yellow.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .shadow(color: .cyan.opacity(0.34), radius: 24, x: -10, y: 10)
            .shadow(color: .pink.opacity(0.3), radius: 26, x: 12, y: 16)

            HStack(spacing: 12) {
                Button(action: onDismiss) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(.white.opacity(0.84))
                        .frame(width: 46, height: 46)
                        .background(Color.black.opacity(0.34), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    onSubmit(draft)
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(canSubmit ? .black : .white.opacity(0.42))
                        .frame(width: 52, height: 46)
                        .background(canSubmit ? Color.cyan : Color.white.opacity(0.13), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(canSubmit ? 0.0 : 0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
            }
        }
        .frame(width: width)
        .padding(18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.42), radius: 38, x: 0, y: 28)
    }
}

private struct ComposerTransitionMotion: ViewModifier {
    let style: TransitionStylePreference
    let isPresented: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .twoD:
            content
                .scaleEffect(isPresented ? 1 : 0.88)
                .opacity(isPresented ? 1 : 0)
        case .threeD:
            content
                .rotation3DEffect(
                    .degrees(isPresented ? 0 : 22),
                    axis: (x: 1, y: -0.18, z: 0),
                    anchor: .center,
                    perspective: 0.72
                )
                .scaleEffect(isPresented ? 1 : 0.82)
                .opacity(isPresented ? 1 : 0)
        }
    }
}

private struct LiveLocationPickerOverlay: View {
    let locations: [LiveBroadcastLocation]
    let onSelect: (LiveBroadcastLocation) -> Void
    let onDismiss: () -> Void

    @State private var isPresented = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onDismiss()
                    }

                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.22))
                                .frame(width: 42, height: 42)
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 18, weight: .black))
                                .foregroundStyle(.red)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Go Live")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                            Text("Choose where the live radius starts")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.62))
                        }

                        Spacer()

                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.black.opacity(0.32), in: Circle())
                                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(spacing: 9) {
                        ForEach(locations.prefix(6)) { location in
                            Button {
                                onSelect(location)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "location.fill")
                                        .font(.system(size: 16, weight: .black))
                                        .foregroundStyle(Color(red: 0.36, green: 1.0, blue: 0.42))
                                        .frame(width: 34, height: 34)
                                        .background(Color.black.opacity(0.34), in: Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(location.title)
                                            .font(.system(size: 17, weight: .black, design: .rounded))
                                            .foregroundStyle(.white)
                                        Text("\(location.subtitle) - \(formatRadius(location.radiusMeters))")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.58))
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Image(systemName: "arrow.up.forward")
                                        .font(.system(size: 14, weight: .black))
                                        .foregroundStyle(.white.opacity(0.72))
                                }
                                .padding(.horizontal, 13)
                                .frame(height: 60)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: min(proxy.size.width - 34, 430))
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.02, green: 0.02, blue: 0.04).opacity(0.96),
                                    Color(red: 0.13, green: 0.02, blue: 0.04).opacity(0.94),
                                    Color(red: 0.02, green: 0.10, blue: 0.08).opacity(0.94)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.red.opacity(0.9), .cyan.opacity(0.55), .white.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
                .shadow(color: .red.opacity(0.28), radius: 28, x: 0, y: 18)
                .shadow(color: .black.opacity(0.52), radius: 34, x: 0, y: 24)
                .position(x: proxy.size.width / 2, y: proxy.size.height - proxy.safeAreaInsets.bottom - 265)
                .scaleEffect(isPresented ? 1 : 0.86)
                .opacity(isPresented ? 1 : 0)
                .animation(.spring(response: 0.38, dampingFraction: 0.74), value: isPresented)
            }
        }
        .onAppear { isPresented = true }
    }

    private func formatRadius(_ meters: Double) -> String {
        if meters >= 1_000_000 {
            return String(format: "%.1fM m", meters / 1_000_000)
        }
        if meters >= 1_000 {
            return String(format: "%.0fk m", meters / 1_000)
        }
        return "\(Int(meters)) m"
    }
}

private final class FeedCommentComposerGlitterScene: SKScene {
    static func make() -> FeedCommentComposerGlitterScene {
        FeedCommentComposerGlitterScene(size: CGSize(width: 430, height: 168))
    }

    override init(size: CGSize) {
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        addGlitterField()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func addGlitterField() {
        let colors: [UIColor] = [.systemCyan, .systemPink, .systemYellow, .white]
        for index in 0..<34 {
            let node = SKShapeNode(circleOfRadius: CGFloat.random(in: 1.4...3.6))
            node.fillColor = colors[index % colors.count].withAlphaComponent(CGFloat.random(in: 0.56...0.92))
            node.strokeColor = .clear
            node.position = CGPoint(
                x: CGFloat.random(in: 0...size.width),
                y: CGFloat.random(in: 0...size.height)
            )
            node.glowWidth = CGFloat.random(in: 1...4)
            node.alpha = CGFloat.random(in: 0.38...0.95)
            addChild(node)

            let drift = SKAction.moveBy(
                x: CGFloat.random(in: -28...28),
                y: CGFloat.random(in: 18...56),
                duration: TimeInterval.random(in: 2.1...4.4)
            )
            drift.timingMode = .easeInEaseOut
            let fade = SKAction.sequence([
                .fadeAlpha(to: 0.18, duration: TimeInterval.random(in: 0.6...1.2)),
                .fadeAlpha(to: 0.95, duration: TimeInterval.random(in: 0.8...1.5))
            ])
            let wander = SKAction.sequence([drift, drift.reversed()])
            node.run(.repeatForever(.group([wander, fade])))
        }
    }
}

final class BarCubePreviewTuning: ObservableObject {
    // Removed barHorizontalOffset, barBottomOffset, barTiltDegrees, barWidth, barHeight per instructions (no longer used)
}

private struct FeedChromeNotificationBridge: View {
    let isActive: Bool
    let onHoldBegan: () -> Void
    let onHoldEnded: () -> Void
    let onInteraction: () -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onReceive(NotificationCenter.default.publisher(for: .cubeHoldBegan)) { _ in
                guard isActive else { return }
                onHoldBegan()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cubeHoldEnded)) { _ in
                guard isActive else { return }
                onHoldEnded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .FeedUserInteraction)) { _ in
                guard isActive else { return }
                onInteraction()
            }
    }
}

private struct CubeAndBarOverlay: View {
    @Binding var radius: Double

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
            }
            .padding(.bottom, 24)
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

            if controller.isLiveVideoActive {
                LiveVideoStatusBadge(
                    seconds: controller.liveVideoSeconds,
                    viewers: controller.liveViewerCount,
                    locationName: controller.liveLocationName
                )
                .padding(.top, 12)
            }

            Spacer()
        }
    }
}

private struct LiveVideoStatusBadge: View {
    let seconds: Int
    let viewers: Int
    let locationName: String?

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
                    .shadow(color: .red.opacity(0.8), radius: 7)

                Text("LIVE")
                    .font(.system(size: 12, weight: .black))
                    .tracking(1.1)
                    .foregroundStyle(.white)
            }

            Text(formatDuration(seconds))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))

            Text("\(viewers) watching")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color(red: 0.36, green: 1.0, blue: 0.42))

            if let locationName, !locationName.isEmpty {
                Text(locationName)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 118, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.black.opacity(0.58), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 5)
        .accessibilityLabel("Live video, \(formatDuration(seconds)), \(viewers) watching")
    }

    private func formatDuration(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
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
                .contentShape(Circle())
                .shadow(color: .black.opacity(0.45), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemName.contains("bolt") ? "Toggle flash" : "Switch camera")
    }
}

private struct RecognizedFaceBoxOverlay: View {
    @ObservedObject var recognitionManager: UserRecognitionManager

    var body: some View {
        GeometryReader { proxy in
            if let user = recognitionManager.recognizedUser,
               user.isRecent,
               let bounds = recognitionManager.recognizedFaceBounds {
                let rect = bounds.visionBoxToViewRect(in: proxy.size)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(red: 0.36, green: 1.0, blue: 0.42), lineWidth: 3)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .shadow(color: Color(red: 0.36, green: 1.0, blue: 0.42).opacity(0.8), radius: 10)

                    Text("@\(user.profile.username)")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(red: 0.36, green: 1.0, blue: 0.42), in: Capsule())
                        .position(x: rect.minX + 34, y: max(rect.minY - 12, 14))
                }
                .animation(.easeInOut(duration: 0.16), value: bounds)
            }
        }
        .ignoresSafeArea()
    }
}

private extension CGRect {
    func visionBoxToViewRect(in size: CGSize) -> CGRect {
        CGRect(
            x: origin.x * size.width,
            y: (1 - origin.y - height) * size.height,
            width: width * size.width,
            height: height * size.height
        )
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
            "Tap cube to take photo • Hold cube for Photo, Video, or Live"
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

private struct PoplurVolumeBars: View {
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

// MARK: - ML Camera Shader Overlay

/// Real-time ML object detection overlay shown at top center of the camera view.
/// Fires a cube pop when new objects are detected.
private struct MLCameraShaderOverlay: View {
    @State private var detectedObjects: [DetectedObject] = []
    @State private var lastDetectionKey: String = ""
    @State private var lastPopTime: Date = .distantPast

    private let popCooldown: TimeInterval = 2.5

    var body: some View {
        VStack(spacing: 0) {
            if !detectedObjects.isEmpty {
                mlBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: detectedObjects.map(\.identifier))
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MLObjectsDetected"))) { note in
            guard let objects = note.userInfo?["objects"] as? [DetectedObject] else { return }
            detectedObjects = objects
            let key = objects.prefix(3).map(\.identifier).joined(separator: ",")
            if key != lastDetectionKey, !objects.isEmpty {
                let now = Date()
                if now.timeIntervalSince(lastPopTime) >= popCooldown {
                    lastPopTime = now
                    NotificationCenter.default.post(name: Notification.Name("MLCubePopTrigger"), object: nil)
                }
                lastDetectionKey = key
            }
        }
    }

    @ViewBuilder
    private var mlBanner: some View {
        VStack(spacing: 8) {
            if let primary = detectedObjects.first {
                MLShaderLabel(text: primary.identifier.uppercased())
            }
            if detectedObjects.count > 1 {
                HStack(spacing: 7) {
                    ForEach(Array(detectedObjects.dropFirst().prefix(3).enumerated()), id: \.offset) { idx, obj in
                        MLFloat3DChip(text: obj.identifier.capitalized, delay: Double(idx) * 0.2)
                    }
                }
            }
        }
        .padding(.top, 54)
        .frame(maxWidth: .infinity)
    }
}

private struct MLShaderLabel: View {
    let text: String
    @State private var glowPhase: Double = 0

    var body: some View {
        ZStack {
            // Outer bloom
            Text(text)
                .font(.system(size: 19, weight: .black, design: .monospaced))
                .foregroundStyle(Color.cyan.opacity(0.3))
                .blur(radius: 14)
            // Mid glow
            Text(text)
                .font(.system(size: 19, weight: .black, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.4))
                .blur(radius: 5)
            // Animated shimmer gradient
            Text(text)
                .font(.system(size: 19, weight: .black, design: .monospaced))
                .tracking(3)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            .white,
                            Color.cyan.opacity(0.9),
                            Color.white.opacity(0.55 + sin(glowPhase) * 0.45),
                            Color.cyan,
                            .white
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .shadow(color: .cyan.opacity(0.75), radius: 10)
        .shadow(color: .white.opacity(0.35), radius: 4)
        .onAppear {
            withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: true)) {
                glowPhase = .pi * 2
            }
        }
    }
}

private struct MLFloat3DChip: View {
    let text: String
    let delay: Double
    @State private var floatOffset: CGFloat = 0

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.9))
            .tracking(1.1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.cyan.opacity(0.45), lineWidth: 0.8)
            )
            .rotation3DEffect(.degrees(9), axis: (x: 1, y: 0, z: 0))
            .offset(y: floatOffset)
            .shadow(color: .cyan.opacity(0.35), radius: 6)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.1 + delay * 0.3)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    floatOffset = -5
                }
            }
    }
}
