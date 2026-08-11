import Combine
import Foundation
import SceneKit
import SpriteKit
import UIKit

enum PoplurPerformanceMode: Int, CaseIterable, Comparable, Sendable {
    case full = 0
    case reduced = 1
    case lowPower = 2
    case emergency = 3

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var diagnosticName: String {
        switch self {
        case .full: return "FULL"
        case .reduced: return "REDUCED"
        case .lowPower: return "LOW_POWER"
        case .emergency: return "EMERGENCY"
        }
    }
}

enum PoplurRendererClassification: Sendable {
    case lightweight
    case decorative
    case heavy
}

enum PoplurFrameRateClass: Sendable {
    case decorative
    case interactive
}

enum PoplurPhysicsQuality: String, Sendable {
    case full
    case reduced
    case minimal
    case paused
}

enum PoplurApplicationLifecycle: String, Sendable {
    case active
    case inactive
    case background
}

struct PoplurPerformancePolicy: Equatable, Sendable {
    let mode: PoplurPerformanceMode
    let targetFPS: Int
    let interactiveTargetFPS: Int
    let particlesAllowed: Bool
    let particleDensityMultiplier: Double
    let dynamicShadowsAllowed: Bool
    let postProcessingAllowed: Bool
    let physicsQuality: PoplurPhysicsQuality
    let maximumPreferredTextureResolution: Int
    let assetCacheByteLimit: Int
    let decorativeRenderingAllowed: Bool
    let expensiveVideoTexturesAllowed: Bool

    func targetFPS(for rateClass: PoplurFrameRateClass) -> Int {
        switch rateClass {
        case .decorative: return targetFPS
        case .interactive: return interactiveTargetFPS
        }
    }
}

@MainActor
final class PoplurPerformanceRegistration {
    fileprivate weak var manager: PoplurPerformanceManager?
    fileprivate let id = UUID()
    fileprivate let name: String
    fileprivate let classification: PoplurRendererClassification
    fileprivate let rateClass: PoplurFrameRateClass
    fileprivate let priority: Int
    fileprivate let onPolicy: (PoplurPerformancePolicy, Bool) -> Void
    fileprivate let onPurgeInactiveResources: () -> Void
    fileprivate var activationSequence: UInt64 = 0
    fileprivate(set) var isVisible = false
    fileprivate(set) var isGrantedRendering = false
    private var lastPolicy: PoplurPerformancePolicy?
    private var isInvalidated = false

    fileprivate init(
        manager: PoplurPerformanceManager,
        name: String,
        classification: PoplurRendererClassification,
        rateClass: PoplurFrameRateClass,
        priority: Int,
        onPolicy: @escaping (PoplurPerformancePolicy, Bool) -> Void,
        onPurgeInactiveResources: @escaping () -> Void
    ) {
        self.manager = manager
        self.name = name
        self.classification = classification
        self.rateClass = rateClass
        self.priority = priority
        self.onPolicy = onPolicy
        self.onPurgeInactiveResources = onPurgeInactiveResources
    }

    func setVisible(_ visible: Bool) {
        guard !isInvalidated, visible != isVisible else { return }
        isVisible = visible
        manager?.rendererVisibilityDidChange(self)
    }

    func invalidate() {
        guard !isInvalidated else { return }
        isInvalidated = true
        isVisible = false
        manager?.removeRenderer(self)
        manager = nil
    }

    fileprivate func apply(_ policy: PoplurPerformancePolicy, granted: Bool) {
        guard !isInvalidated else { return }
        let changed = granted != isGrantedRendering || policy != lastPolicy
        isGrantedRendering = granted
        lastPolicy = policy
        if changed { onPolicy(policy, granted) }
    }

    fileprivate func purgeIfInactive() {
        guard !isVisible || !isGrantedRendering else { return }
        onPurgeInactiveResources()
    }

    deinit {
        let registrationID = id
        if let manager {
            Task { @MainActor in
                manager.rendererRegistrationDidDeinit(id: registrationID)
            }
        }
    }
}

@MainActor
final class PoplurPerformanceManager: ObservableObject {
    static let shared = PoplurPerformanceManager()

    @Published private(set) var mode: PoplurPerformanceMode
    @Published private(set) var policy: PoplurPerformancePolicy
    @Published private(set) var thermalState: ProcessInfo.ThermalState
    @Published private(set) var thermalCondition: String
    @Published private(set) var isLowPowerModeEnabled: Bool
    @Published private(set) var memoryPressureActive = false
    @Published private(set) var applicationLifecycle: PoplurApplicationLifecycle = .inactive
    @Published private(set) var currentSceneIsVisible = false
    @Published private(set) var visibleRendererCount = 0
    @Published private(set) var activeHeavyRendererCount = 0
    @Published private(set) var currentRendererName: String?
    @Published private(set) var memoryWarningCount = 0

    var targetFPS: Int { policy.targetFPS }
    var particlesAllowed: Bool { policy.particlesAllowed }
    var particleDensityMultiplier: Double { policy.particleDensityMultiplier }
    var dynamicShadowsAllowed: Bool { policy.dynamicShadowsAllowed }
    var postProcessingAllowed: Bool { policy.postProcessingAllowed }
    var physicsQuality: PoplurPhysicsQuality { policy.physicsQuality }
    var maximumPreferredTextureResolution: Int { policy.maximumPreferredTextureResolution }
    var modelAndTextureCacheBudget: Int { policy.assetCacheByteLimit }
    var decorativeRenderingAllowed: Bool { policy.decorativeRenderingAllowed }
    var expensiveVideoTexturesAllowed: Bool { policy.expensiveVideoTexturesAllowed }
    var isApplicationActive: Bool { applicationLifecycle == .active }

    private final class WeakRegistration {
        weak var value: PoplurPerformanceRegistration?
        init(_ value: PoplurPerformanceRegistration) { self.value = value }
    }

    private let processInfo: ProcessInfo
    private let assetCache: PoplurAssetCache
    private let baseCacheLimits: PoplurAssetCache.Limits
    private var registrations: [UUID: WeakRegistration] = [:]
    private var activeHeavyRendererID: UUID?
    private var activationSequence: UInt64 = 0
    private var notificationTokens: [NSObjectProtocol] = []
    private var memoryRecoveryTask: Task<Void, Never>?
    private var monitoringStarted = false

    private init(
        processInfo: ProcessInfo = .processInfo,
        assetCache: PoplurAssetCache = .shared
    ) {
        self.processInfo = processInfo
        self.assetCache = assetCache
        self.baseCacheLimits = assetCache.currentLimits()
        let thermal = processInfo.thermalState
        let lowPower = processInfo.isLowPowerModeEnabled
        let initialMode = Self.mode(for: thermal, lowPower: lowPower, memoryPressure: false, lifecycle: .inactive)
        self.mode = initialMode
        self.thermalState = thermal
        self.thermalCondition = Self.thermalName(thermal)
        self.isLowPowerModeEnabled = lowPower
        self.policy = Self.makePolicy(mode: initialMode, baseCacheByteLimit: baseCacheLimits.byteLimit)
    }

    func startMonitoring() {
        guard !monitoringStarted else { return }
        monitoringStarted = true

        let center = NotificationCenter.default
        notificationTokens = [
            center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshSystemSignals(reason: "Thermal pressure") }
            },
            center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshSystemSignals(reason: "Low Power Mode") }
            },
            center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleMemoryWarning() }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setApplicationLifecycle(.active) }
            },
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setApplicationLifecycle(.inactive) }
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setApplicationLifecycle(.background) }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.setApplicationLifecycle(.inactive) }
            },
        ]

        let state = UIApplication.shared.applicationState
        setApplicationLifecycle(state == .active ? .active : (state == .background ? .background : .inactive))
        refreshSystemSignals(reason: "Startup")
    }

    func setApplicationLifecycle(_ lifecycle: PoplurApplicationLifecycle) {
        guard applicationLifecycle != lifecycle else { return }
        applicationLifecycle = lifecycle
        if lifecycle == .background {
            assetCache.trim(toByteCount: baseCacheLimits.byteLimit / 2, reason: .background)
        }
        recomputeMode(reason: "App \(lifecycle.rawValue)")
    }

    func targetFPS(for rateClass: PoplurFrameRateClass) -> Int {
        policy.targetFPS(for: rateClass)
    }

    @discardableResult
    func registerRenderer(
        name: String,
        classification: PoplurRendererClassification,
        rateClass: PoplurFrameRateClass = .decorative,
        priority: Int = 0,
        onPolicy: @escaping (PoplurPerformancePolicy, Bool) -> Void,
        onPurgeInactiveResources: @escaping () -> Void = {}
    ) -> PoplurPerformanceRegistration {
        let registration = PoplurPerformanceRegistration(
            manager: self,
            name: name,
            classification: classification,
            rateClass: rateClass,
            priority: priority,
            onPolicy: onPolicy,
            onPurgeInactiveResources: onPurgeInactiveResources
        )
        registrations[registration.id] = WeakRegistration(registration)
        registration.apply(policy, granted: false)
        updateDiagnostics()
        return registration
    }

    func purgeCaches() {
        _ = assetCache.purge(reason: .manual)
        purgeInactiveRendererResources()
        logDiagnostics(reason: "Manual purge")
    }

    func diagnosticsLine() -> String {
        let cache = assetCache.snapshot()
        let usedMB = Int((Double(cache.estimatedByteCount) / 1_048_576.0).rounded())
        let limitMB = Int((Double(cache.byteLimit) / 1_048_576.0).rounded())
        return "mode=\(mode.diagnosticName) thermal=\(thermalCondition) fps=\(targetFPS) "
            + "heavy=\(activeHeavyRendererCount) visible=\(visibleRendererCount) "
            + "cache=\(usedMB)/\(limitMB)MB assets=\(cache.itemCount)/\(cache.itemLimit) "
            + "renderer=\(currentRendererName ?? "none") warnings=\(memoryWarningCount)"
    }

    fileprivate func rendererVisibilityDidChange(_ registration: PoplurPerformanceRegistration) {
        guard registrations[registration.id]?.value != nil else { return }
        activationSequence &+= 1
        registration.activationSequence = activationSequence

        if !registration.isVisible {
            registration.purgeIfInactive()
            debugLog("Paused renderer: \(registration.name) (not visible)")
        }
        reconcileRenderers()
    }

    fileprivate func removeRenderer(_ registration: PoplurPerformanceRegistration) {
        registration.apply(policy, granted: false)
        registration.onPurgeInactiveResources()
        registrations.removeValue(forKey: registration.id)
        if activeHeavyRendererID == registration.id { activeHeavyRendererID = nil }
        reconcileRenderers()
    }

    fileprivate func rendererRegistrationDidDeinit(id: UUID) {
        registrations.removeValue(forKey: id)
        if activeHeavyRendererID == id { activeHeavyRendererID = nil }
        reconcileRenderers()
    }

    private func refreshSystemSignals(reason: String) {
        thermalState = processInfo.thermalState
        thermalCondition = Self.thermalName(thermalState)
        isLowPowerModeEnabled = processInfo.isLowPowerModeEnabled
        recomputeMode(reason: reason)
    }

    private func handleMemoryWarning() {
        memoryWarningCount += 1
        memoryPressureActive = true
        _ = assetCache.purge(reason: .memoryPressure)
        purgeInactiveRendererResources()
        recomputeMode(reason: "Memory pressure")

        memoryRecoveryTask?.cancel()
        memoryRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self else { return }
            self.memoryPressureActive = false
            self.recomputeMode(reason: "Memory pressure recovery window elapsed")
        }
    }

    private func recomputeMode(reason: String) {
        let previousPolicy = policy
        let nextMode = Self.mode(
            for: thermalState,
            lowPower: isLowPowerModeEnabled,
            memoryPressure: memoryPressureActive,
            lifecycle: applicationLifecycle
        )
        let previous = mode
        mode = nextMode
        policy = Self.makePolicy(mode: nextMode, baseCacheByteLimit: baseCacheLimits.byteLimit)
        assetCache.updateByteLimit(policy.assetCacheByteLimit)
        if policy.maximumPreferredTextureResolution < previousPolicy.maximumPreferredTextureResolution {
            // High-resolution variants must not survive a downgrade simply
            // because the aggregate byte budget still has room for them.
            assetCache.removeAll(category: .texture)
            assetCache.removeAll(category: .decodedImage)
        }

        if previous != nextMode {
            debugLog("Mode changed \(previous.diagnosticName) -> \(nextMode.diagnosticName). Reason: \(reason)")
        }
        reconcileRenderers()
        logDiagnostics(reason: reason)
    }

    private func reconcileRenderers() {
        compactRegistrations()
        let previousHeavyID = activeHeavyRendererID
        activeHeavyRendererID = applicationLifecycle == .active
            ? registrations.values
                .compactMap(\.value)
                .filter { $0.isVisible && $0.classification == .heavy }
                .max {
                    if $0.priority != $1.priority { return $0.priority < $1.priority }
                    if $0.activationSequence != $1.activationSequence {
                        return $0.activationSequence < $1.activationSequence
                    }
                    return $0.id.uuidString < $1.id.uuidString
                }?.id
            : nil
        if previousHeavyID != activeHeavyRendererID,
           let previous = previousHeavyID.flatMap({ registrations[$0]?.value }),
           let current = activeHeavyRendererID.flatMap({ registrations[$0]?.value }) {
            debugLog("Paused renderer: \(previous.name) (replaced by \(current.name))")
        }

        for registration in registrations.values.compactMap(\.value) {
            let granted: Bool
            guard applicationLifecycle == .active, registration.isVisible else {
                registration.apply(policy, granted: false)
                continue
            }
            switch registration.classification {
            case .heavy:
                granted = registration.id == activeHeavyRendererID
            case .decorative:
                granted = policy.decorativeRenderingAllowed
            case .lightweight:
                granted = true
            }
            registration.apply(policy, granted: granted)
        }
        updateDiagnostics()
    }

    private func purgeInactiveRendererResources() {
        compactRegistrations()
        registrations.values.compactMap(\.value).forEach { $0.purgeIfInactive() }
    }

    private func compactRegistrations() {
        registrations = registrations.filter { $0.value.value != nil }
    }

    private func updateDiagnostics() {
        let live = registrations.values.compactMap(\.value)
        visibleRendererCount = live.filter(\.isVisible).count
        activeHeavyRendererCount = live.filter {
            $0.classification == .heavy && $0.isGrantedRendering
        }.count
        currentRendererName = live.first {
            $0.classification == .heavy && $0.isGrantedRendering
        }?.name
        currentSceneIsVisible = visibleRendererCount > 0

        assert(activeHeavyRendererCount <= 1, "Poplur must never grant more than one heavy renderer")
    }

    private func logDiagnostics(reason: String) {
        #if DEBUG
        debugLog("\(diagnosticsLine()) reason=\(reason)")
        #endif
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[PoplurPerformance] \(message)")
        #endif
    }

    private static func mode(
        for thermal: ProcessInfo.ThermalState,
        lowPower: Bool,
        memoryPressure: Bool,
        lifecycle: PoplurApplicationLifecycle
    ) -> PoplurPerformanceMode {
        var result: PoplurPerformanceMode
        switch thermal {
        case .nominal: result = .full
        case .fair: result = .reduced
        case .serious: result = .lowPower
        case .critical: result = .emergency
        @unknown default: result = .reduced
        }
        if lowPower { result = max(result, .lowPower) }
        if memoryPressure { result = max(result, .lowPower) }
        if lifecycle != .active { result = .emergency }
        return result
    }

    private static func makePolicy(mode: PoplurPerformanceMode, baseCacheByteLimit: Int) -> PoplurPerformancePolicy {
        switch mode {
        case .full:
            return PoplurPerformancePolicy(
                mode: mode,
                targetFPS: 30,
                interactiveTargetFPS: 60,
                particlesAllowed: true,
                particleDensityMultiplier: 1,
                dynamicShadowsAllowed: true,
                postProcessingAllowed: true,
                physicsQuality: .full,
                maximumPreferredTextureResolution: 2_048,
                assetCacheByteLimit: baseCacheByteLimit,
                decorativeRenderingAllowed: true,
                expensiveVideoTexturesAllowed: true
            )
        case .reduced:
            return PoplurPerformancePolicy(
                mode: mode,
                targetFPS: 24,
                interactiveTargetFPS: 30,
                particlesAllowed: true,
                particleDensityMultiplier: 0.5,
                dynamicShadowsAllowed: false,
                postProcessingAllowed: false,
                physicsQuality: .reduced,
                maximumPreferredTextureResolution: 1_024,
                assetCacheByteLimit: baseCacheByteLimit * 3 / 4,
                decorativeRenderingAllowed: true,
                expensiveVideoTexturesAllowed: false
            )
        case .lowPower:
            return PoplurPerformancePolicy(
                mode: mode,
                targetFPS: 15,
                interactiveTargetFPS: 24,
                particlesAllowed: true,
                particleDensityMultiplier: 0.22,
                dynamicShadowsAllowed: false,
                postProcessingAllowed: false,
                physicsQuality: .minimal,
                maximumPreferredTextureResolution: 1_024,
                assetCacheByteLimit: baseCacheByteLimit / 2,
                decorativeRenderingAllowed: true,
                expensiveVideoTexturesAllowed: false
            )
        case .emergency:
            return PoplurPerformancePolicy(
                mode: mode,
                targetFPS: 10,
                interactiveTargetFPS: 15,
                particlesAllowed: false,
                particleDensityMultiplier: 0,
                dynamicShadowsAllowed: false,
                postProcessingAllowed: false,
                physicsQuality: .paused,
                maximumPreferredTextureResolution: 512,
                assetCacheByteLimit: baseCacheByteLimit / 4,
                decorativeRenderingAllowed: false,
                expensiveVideoTexturesAllowed: false
            )
        }
    }

    private static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

// MARK: - Lifecycle-aware SceneKit/SpriteKit hosts

@MainActor
class PoplurManagedSCNView: SCNView {
    private let performanceName: String
    private let classification: PoplurRendererClassification
    private let rateClass: PoplurFrameRateClass
    private var performanceRegistration: PoplurPerformanceRegistration?
    private var playbackWasCaptured = false
    private var desiredIsPlaying = false
    private var desiredRendersContinuously = false
    private var savedTechnique: SCNTechnique?
    private var didCaptureTechnique = false
    private var savedAntialiasingMode: SCNAntialiasingMode = .none
    private var didCaptureAntialiasing = false
    private var particleBirthRates: [ObjectIdentifier: CGFloat] = [:]
    private var shadowSettings: [ObjectIdentifier: Bool] = [:]

    init(
        performanceName: String,
        classification: PoplurRendererClassification = .decorative,
        rateClass: PoplurFrameRateClass = .decorative,
        frame: CGRect = .zero,
        options: [String: Any]? = nil
    ) {
        self.performanceName = performanceName
        self.classification = classification
        self.rateClass = rateClass
        super.init(frame: frame, options: options)
    }

    required init?(coder: NSCoder) {
        performanceName = "SceneKit"
        classification = .decorative
        rateClass = .decorative
        super.init(coder: coder)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { ensurePerformanceRegistration() }
        performanceRegistration?.setVisible(window != nil && !isHidden && alpha > 0.01)
    }

    override var isHidden: Bool {
        didSet { performanceRegistration?.setVisible(window != nil && !isHidden && alpha > 0.01) }
    }

    override var alpha: CGFloat {
        didSet { performanceRegistration?.setVisible(window != nil && !isHidden && alpha > 0.01) }
    }

    func poplurTearDown(releaseScene: Bool = true) {
        performanceRegistration?.setVisible(false)
        performanceRegistration?.invalidate()
        performanceRegistration = nil
        isPlaying = false
        rendersContinuously = false
        scene?.isPaused = true
        if releaseScene { scene = nil }
    }

    private func ensurePerformanceRegistration() {
        guard performanceRegistration == nil else { return }
        capturePlaybackIntentIfNeeded()
        performanceRegistration = PoplurPerformanceManager.shared.registerRenderer(
            name: performanceName,
            classification: classification,
            rateClass: rateClass,
            onPolicy: { [weak self] policy, granted in
                self?.apply(policy: policy, granted: granted)
            },
            onPurgeInactiveResources: { [weak self] in
                guard let self, self.window == nil else { return }
                self.scene?.isPaused = true
                self.isPlaying = false
                self.rendersContinuously = false
            }
        )
    }

    private func capturePlaybackIntentIfNeeded() {
        guard !playbackWasCaptured else { return }
        playbackWasCaptured = true
        desiredIsPlaying = isPlaying
        desiredRendersContinuously = rendersContinuously
    }

    private func apply(policy: PoplurPerformancePolicy, granted: Bool) {
        preferredFramesPerSecond = policy.targetFPS(for: rateClass)
        applyQuality(policy)
        guard granted else {
            if scene?.isPaused == false {
                desiredIsPlaying = isPlaying
                desiredRendersContinuously = rendersContinuously
            }
            isPlaying = false
            rendersContinuously = false
            scene?.isPaused = true
            return
        }
        scene?.isPaused = false
        isPlaying = desiredIsPlaying
        rendersContinuously = desiredRendersContinuously
        setNeedsDisplay()
    }

    private func applyQuality(_ policy: PoplurPerformancePolicy) {
        if !didCaptureTechnique {
            didCaptureTechnique = true
            savedTechnique = technique
        }
        technique = policy.postProcessingAllowed ? savedTechnique : nil

        if !didCaptureAntialiasing {
            didCaptureAntialiasing = true
            savedAntialiasingMode = antialiasingMode
        }
        switch policy.mode {
        case .full: antialiasingMode = savedAntialiasingMode
        case .reduced: antialiasingMode = savedAntialiasingMode == .none ? .none : .multisampling2X
        case .lowPower, .emergency: antialiasingMode = .none
        }

        scene?.rootNode.enumerateHierarchy { [weak self] node, _ in
            guard let self else { return }
            if let light = node.light {
                let key = ObjectIdentifier(light)
                if self.shadowSettings[key] == nil { self.shadowSettings[key] = light.castsShadow }
                light.castsShadow = policy.dynamicShadowsAllowed && (self.shadowSettings[key] ?? false)
            }
            node.particleSystems?.forEach { particles in
                let key = ObjectIdentifier(particles)
                if self.particleBirthRates[key] == nil { self.particleBirthRates[key] = particles.birthRate }
                let baseline = self.particleBirthRates[key] ?? particles.birthRate
                particles.birthRate = CGFloat(policy.particleDensityMultiplier) * baseline
            }
        }
    }
}

@MainActor
class PoplurManagedSKView: SKView {
    private let performanceName: String
    private let classification: PoplurRendererClassification
    private let rateClass: PoplurFrameRateClass
    private var performanceRegistration: PoplurPerformanceRegistration?
    private var desiredViewPaused = false
    private var desiredScenePaused = false
    private var playbackWasCaptured = false
    private var particleBirthRates: [ObjectIdentifier: CGFloat] = [:]

    init(
        performanceName: String,
        classification: PoplurRendererClassification = .decorative,
        rateClass: PoplurFrameRateClass = .decorative,
        frame: CGRect = .zero
    ) {
        self.performanceName = performanceName
        self.classification = classification
        self.rateClass = rateClass
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        performanceName = "SpriteKit"
        classification = .decorative
        rateClass = .decorative
        super.init(coder: coder)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { ensurePerformanceRegistration() }
        performanceRegistration?.setVisible(window != nil && !isHidden && alpha > 0.01)
    }

    override var isHidden: Bool {
        didSet { performanceRegistration?.setVisible(window != nil && !isHidden && alpha > 0.01) }
    }

    override var alpha: CGFloat {
        didSet { performanceRegistration?.setVisible(window != nil && !isHidden && alpha > 0.01) }
    }

    func poplurTearDown(releaseScene: Bool = true) {
        performanceRegistration?.setVisible(false)
        performanceRegistration?.invalidate()
        performanceRegistration = nil
        isPaused = true
        scene?.isPaused = true
        scene?.removeAllActions()
        if releaseScene { presentScene(nil) }
    }

    private func ensurePerformanceRegistration() {
        guard performanceRegistration == nil else { return }
        capturePlaybackIntentIfNeeded()
        performanceRegistration = PoplurPerformanceManager.shared.registerRenderer(
            name: performanceName,
            classification: classification,
            rateClass: rateClass,
            onPolicy: { [weak self] policy, granted in
                self?.apply(policy: policy, granted: granted)
            },
            onPurgeInactiveResources: { [weak self] in
                guard let self, self.window == nil else { return }
                self.isPaused = true
                self.scene?.isPaused = true
            }
        )
    }

    private func capturePlaybackIntentIfNeeded() {
        guard !playbackWasCaptured else { return }
        playbackWasCaptured = true
        desiredViewPaused = isPaused
        desiredScenePaused = scene?.isPaused ?? false
    }

    private func apply(policy: PoplurPerformancePolicy, granted: Bool) {
        preferredFramesPerSecond = policy.targetFPS(for: rateClass)
        shouldCullNonVisibleNodes = true
        applyParticleQuality(policy)
        guard granted else {
            desiredViewPaused = isPaused
            desiredScenePaused = scene?.isPaused ?? false
            isPaused = true
            scene?.isPaused = true
            return
        }
        isPaused = desiredViewPaused
        scene?.isPaused = desiredScenePaused
        setNeedsDisplay()
    }

    private func applyParticleQuality(_ policy: PoplurPerformancePolicy) {
        guard let scene else { return }
        scene.enumerateChildNodes(withName: "//*") { [weak self] node, _ in
            guard let self, let emitter = node as? SKEmitterNode else { return }
            let key = ObjectIdentifier(emitter)
            if self.particleBirthRates[key] == nil { self.particleBirthRates[key] = emitter.particleBirthRate }
            let baseline = self.particleBirthRates[key] ?? emitter.particleBirthRate
            emitter.particleBirthRate = CGFloat(policy.particleDensityMultiplier) * baseline
        }
    }
}

#if DEBUG
import SwiftUI

struct PoplurPerformanceDiagnosticsView: View {
    @ObservedObject private var performance = PoplurPerformanceManager.shared

    var body: some View {
        Text(performance.diagnosticsLine())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(7)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityLabel("Poplur performance diagnostics")
            .allowsHitTesting(false)
    }
}
#endif
