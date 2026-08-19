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
    let continuousRenderingAllowed: Bool

    func targetFPS(for rateClass: PoplurFrameRateClass) -> Int {
        switch rateClass {
        case .decorative: return targetFPS
        case .interactive: return interactiveTargetFPS
        }
    }
}

/// Bounded, content-free evidence captured when iOS changes thermal state.
///
/// iOS intentionally exposes a thermal pressure state rather than a battery or
/// enclosure temperature in Celsius. Capturing the renderer lease *before* it
/// is revoked lets a later, disconnected device run identify which subsystem
/// was active when the operating system raised the pressure level. This is an
/// attribution lead, not proof that the named renderer caused the transition.
struct PoplurThermalTransitionRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let previousState: String
    let state: String
    let previousStateDurationSeconds: Double
    let activeHeavyRenderer: String?
    let activeHeavyOwnershipDurationSeconds: Double?
    let visibleRenderers: [String]
    let modeBeforeTransition: String
    let decorativeFPSBeforeTransition: Int
    let interactiveFPSBeforeTransition: Int
    let applicationLifecycle: String
    let cacheBytesBeforePurge: Int
    let cachedItemCountBeforePurge: Int
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

    /// Master off-switch for every automatic degradation: the thermal ladder,
    /// the tripwire, low-power and memory-pressure demotion, and the FPS caps
    /// in the full policy. Diagnostics keep reporting the true thermal state —
    /// only the *reactions* stop. Backgrounding still drops to emergency; a
    /// hidden app has nothing to render.
    ///
    /// OFF means the phone WILL heat: the 14 Aug camera baseline measured 58s
    /// to `fair` without these brakes and 25min with them.
    ///
    /// Recontracted after the 17 Aug thermal audit: the FULL tier no longer
    /// masks quality at rest (60fps interactive / 30fps decorative below),
    /// so there is nothing here worth switching off in normal use — this
    /// switch now only kills the safety ladder, and the camera's
    /// systemPressureState brakes stay armed regardless (CameraKitController
    /// installs them unconditionally). Ship it true only for an experiment,
    /// on purpose.
    static let governorDisabled = false

    @Published private(set) var mode: PoplurPerformanceMode
    @Published private(set) var policy: PoplurPerformancePolicy
    @Published private(set) var thermalState: ProcessInfo.ThermalState
    /// Whether the device is on a charger.
    ///
    /// The governor used to be blind to this, and the device log says that was
    /// the wrong call: of 17 recorded nominal->fair transitions, 14 happened
    /// while charging, and two of the three SERIOUS(throttling) events did too.
    /// One of those was at battery=100%, where the charger draws almost nothing
    /// -- so that heat was the app spending a 60fps budget the device no longer
    /// had the headroom for, not the charger.
    @Published private(set) var isCharging: Bool
    @Published private(set) var thermalCondition: String
    @Published private(set) var isLowPowerModeEnabled: Bool
    @Published private(set) var memoryPressureActive = false
    @Published private(set) var applicationLifecycle: PoplurApplicationLifecycle = .inactive
    @Published private(set) var currentSceneIsVisible = false
    @Published private(set) var visibleRendererCount = 0
    @Published private(set) var activeHeavyRendererCount = 0
    @Published private(set) var currentRendererName: String?
    @Published private(set) var memoryWarningCount = 0
    @Published private(set) var isThermalTripwireActive: Bool
    @Published private(set) var thermalTripwireCooldownEndsAt: Date?
    @Published private(set) var recentThermalTransitions: [PoplurThermalTransitionRecord]

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
    var continuousRenderingAllowed: Bool { policy.continuousRenderingAllowed }
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
    private var activeHeavyRendererGrantedAt: Date?
    private var activationSequence: UInt64 = 0
    private var notificationTokens: [NSObjectProtocol] = []
    private var memoryRecoveryTask: Task<Void, Never>?
    private var thermalRecoveryTask: Task<Void, Never>?
    private var thermalStateEnteredAt: Date
    private var monitoringStarted = false

    private static let thermalRecoveryCooldown: TimeInterval = 30
    private static let thermalTransitionLimit = 16
    private static let thermalTransitionDefaultsKey = "PoplurPerformance.thermalTransitions.v1"

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
        let now = Date()
        self.mode = initialMode
        self.thermalState = thermal
        self.isCharging = Self.readCharging()
        self.thermalCondition = Self.thermalName(thermal)
        self.isLowPowerModeEnabled = lowPower
        self.policy = Self.makePolicy(mode: initialMode, baseCacheByteLimit: baseCacheLimits.byteLimit)
        self.isThermalTripwireActive = Self.governorDisabled ? false : thermal != .nominal
        self.thermalTripwireCooldownEndsAt = nil
        self.recentThermalTransitions = Self.loadThermalTransitions()
        self.thermalStateEnteredAt = now
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
            center.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshSystemSignals(reason: "Charger") }
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
        // Recompute first so every renderer receives granted=false before any
        // teardown callback is asked to destroy the resources it was using.
        recomputeMode(reason: "App \(lifecycle.rawValue)")
        if lifecycle != .active {
            // Inactive is already off-screen from the person's perspective
            // (Control Centre, app switcher, calls). Do not wait for the later
            // background notification to release reusable CPU/GPU resources.
            _ = assetCache.purge(reason: lifecycle == .background ? .background : .inactive)
            purgeInactiveRendererResources()
            releaseReusableRendererAssets()
        }
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
        PoplurWebCaptureStore.purge()
        purgeInactiveRendererResources()
        logDiagnostics(reason: "Manual purge")
    }

    func diagnosticsLine() -> String {
        let cache = assetCache.snapshot()
        let usedMB = Int((Double(cache.estimatedByteCount) / 1_048_576.0).rounded())
        let limitMB = Int((Double(cache.byteLimit) / 1_048_576.0).rounded())
        let tripwire = thermalTripwireStatus
        let lastTransition = recentThermalTransitions.last.map {
            "\($0.previousState)>\($0.state):\($0.activeHeavyRenderer ?? "none")"
        } ?? "none"
        return "mode=\(mode.diagnosticName) thermal=\(thermalCondition) fps=\(targetFPS) "
            + "heavy=\(activeHeavyRendererCount) visible=\(visibleRendererCount) "
            + "cache=\(usedMB)/\(limitMB)MB assets=\(cache.itemCount)/\(cache.itemLimit) "
            + "renderer=\(currentRendererName ?? "none") tripwire=\(tripwire) "
            + "charging=\(isCharging) "
            + "lastThermal=\(lastTransition) warnings=\(memoryWarningCount)"
    }

    /// Human-readable, bounded history suitable for a debug overlay or a
    /// post-run device log. Renderer names are fixed subsystem labels; no user
    /// or content data is retained.
    func thermalDiagnosticsSummary(limit: Int = 5) -> String {
        let boundedLimit = max(1, min(limit, Self.thermalTransitionLimit))
        let formatter = ISO8601DateFormatter()
        return recentThermalTransitions.suffix(boundedLimit).map { record in
            let stateDuration = String(format: "%.1fs", record.previousStateDurationSeconds)
            let ownerDuration = record.activeHeavyOwnershipDurationSeconds.map {
                String(format: "%.1fs", $0)
            } ?? "n/a"
            let visible = record.visibleRenderers.isEmpty ? "none" : record.visibleRenderers.joined(separator: ",")
            return "\(formatter.string(from: record.timestamp)) "
                + "\(record.previousState)>\(record.state) "
                + "previousStateFor=\(stateDuration) "
                + "owner=\(record.activeHeavyRenderer ?? "none") ownerFor=\(ownerDuration) "
                + "visible=\(visible) mode=\(record.modeBeforeTransition) "
                + "fps=\(record.decorativeFPSBeforeTransition)/\(record.interactiveFPSBeforeTransition)"
        }.joined(separator: "\n")
    }

    fileprivate func rendererVisibilityDidChange(_ registration: PoplurPerformanceRegistration) {
        guard registrations[registration.id]?.value != nil else { return }
        activationSequence &+= 1
        registration.activationSequence = activationSequence

        if !registration.isVisible {
            registration.purgeIfInactive()
            if registration.classification == .heavy {
                releaseReusableRendererAssets()
            }
            debugLog("Paused renderer: \(registration.name) (not visible)")
        }
        reconcileRenderers()
    }

    fileprivate func removeRenderer(_ registration: PoplurPerformanceRegistration) {
        registration.apply(policy, granted: false)
        registration.onPurgeInactiveResources()
        registrations.removeValue(forKey: registration.id)
        if activeHeavyRendererID == registration.id {
            activeHeavyRendererID = nil
            activeHeavyRendererGrantedAt = nil
        }
        if registration.classification == .heavy { releaseReusableRendererAssets() }
        reconcileRenderers()
    }

    fileprivate func rendererRegistrationDidDeinit(id: UUID) {
        let wasHeavy = registrations[id]?.value?.classification == .heavy
        registrations.removeValue(forKey: id)
        if activeHeavyRendererID == id {
            activeHeavyRendererID = nil
            activeHeavyRendererGrantedAt = nil
        }
        if wasHeavy { releaseReusableRendererAssets() }
        reconcileRenderers()
    }

    /// Battery monitoring is enabled at app start (Poplur2025App), but enable it
    /// here too: this type can be constructed before that runs, and an unenabled
    /// monitor reports .unknown, which would read as "not charging" and quietly
    /// disable the clamp below.
    private static func readCharging() -> Bool {
        if !UIDevice.current.isBatteryMonitoringEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }

    private func refreshSystemSignals(reason: String) {
        let observedThermalState = processInfo.thermalState
        let transition = observedThermalState == thermalState
            ? nil
            : makeThermalTransitionRecord(to: observedThermalState)

        thermalState = observedThermalState
        thermalCondition = Self.thermalName(thermalState)
        isLowPowerModeEnabled = processInfo.isLowPowerModeEnabled
        isCharging = Self.readCharging()
        updateThermalTripwire(for: observedThermalState)
        recomputeMode(reason: reason)

        if let transition {
            appendThermalTransition(transition)
            thermalStateEnteredAt = transition.timestamp
            debugLog(
                "Thermal transition \(transition.previousState) -> \(transition.state); "
                    + "owner=\(transition.activeHeavyRenderer ?? "none") "
                    + "visible=\(transition.visibleRenderers.joined(separator: ","))"
            )
            if observedThermalState != .nominal {
                enforceThermalTripwire(reason: "Thermal state became \(thermalCondition)")
            }
        } else if reason == "Startup", isThermalTripwireActive {
            // The manager may be created while the phone is already warm, in
            // which case there is no transition notification to trigger the
            // initial fail-safe purge.
            enforceThermalTripwire(reason: "Startup thermal state is \(thermalCondition)")
        }
    }

    private func handleMemoryWarning() {
        memoryWarningCount += 1
        memoryPressureActive = true
        recomputeMode(reason: "Memory pressure")
        _ = assetCache.purge(reason: .memoryPressure)
        PoplurWebCaptureStore.purge()
        purgeInactiveRendererResources()

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
        var nextMode = Self.mode(
            for: thermalState,
            lowPower: isLowPowerModeEnabled,
            memoryPressure: memoryPressureActive,
            lifecycle: applicationLifecycle
        )
        if isThermalTripwireActive {
            // A nominal reading during the cooldown remains reduced. Serious
            // and critical pressure enter the emergency policy immediately.
            nextMode = max(nextMode, thermalState == .serious || thermalState == .critical ? .emergency : .reduced)
        }
        // Plugged in, the phone is already turning charge into heat, so the same
        // frame budget costs more headroom than it does on battery. Take a step
        // down rather than wait for thermalState to degrade -- the ladder above
        // is REACTIVE by construction (nominal -> full, fair -> reduced), so
        // without this the app spends the full budget right up until the device
        // is already hot, which is exactly the pattern the device log shows.
        //
        // Deliberately a floor, not a fixed mode: real thermal pressure can
        // still push this further down, and unplugging restores full quality.
        // One line to tune if REDUCED turns out to be too cautious.
        if isCharging {
            nextMode = max(nextMode, .reduced)
        }
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
        // Lease revocation/policy downgrade must precede resource destruction.
        // Teardown callbacks can otherwise race a renderer that still believes
        // it owns its textures, session, or player graph.
        reconcileRenderers()

        if nextMode > previous {
            purgeInactiveRendererResources()
            releaseReusableRendererAssets()
            if nextMode >= .lowPower {
                // A serious thermal signal means retaining a warm working set
                // is less useful than returning it immediately. New requests
                // can repopulate only within the smaller policy budget.
                _ = assetCache.purge(reason: .thermalPressure)
            }
        }
        logDiagnostics(reason: reason)
    }

    private func reconcileRenderers() {
        compactRegistrations()
        let previousHeavyID = activeHeavyRendererID
        // Visibility and exclusivity own renderer lifetime. A thermal signal
        // may adjust policy, but it must not revoke the one page the user is
        // actively looking at and turn that page into a frozen placeholder.
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
        if previousHeavyID != activeHeavyRendererID {
            activeHeavyRendererGrantedAt = activeHeavyRendererID == nil ? nil : Date()
        }
        if previousHeavyID != activeHeavyRendererID,
           let previous = previousHeavyID.flatMap({ registrations[$0]?.value }),
           let current = activeHeavyRendererID.flatMap({ registrations[$0]?.value }) {
            previous.purgeIfInactive()
            releaseReusableRendererAssets()
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

    /// Live renderer objects own their currently displayed resources. These
    /// entries are reusable copies only, so dropping them on a heavy-renderer
    /// handoff cannot blank the new screen and prevents inactive 3D/video
    /// resources from lingering outside the strict budget.
    private func releaseReusableRendererAssets() {
        assetCache.removeAll(category: .model)
        assetCache.removeAll(category: .scene)
        assetCache.removeAll(category: .texture)
        assetCache.removeAll(category: .video)
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

    private var thermalTripwireStatus: String {
        guard isThermalTripwireActive else { return "off" }
        guard thermalState == .nominal,
              let cooldownEnd = thermalTripwireCooldownEndsAt else { return "active" }
        let seconds = max(0, Int(cooldownEnd.timeIntervalSinceNow.rounded(.up)))
        return "cooldown(\(seconds)s)"
    }

    /// Updates only the tripwire latch. Renderer revocation happens in the
    /// following `recomputeMode` call, after attribution has already captured
    /// the current owner.
    private func updateThermalTripwire(for state: ProcessInfo.ThermalState) {
        thermalRecoveryTask?.cancel()
        thermalRecoveryTask = nil

        if Self.governorDisabled {
            isThermalTripwireActive = false
            thermalTripwireCooldownEndsAt = nil
            return
        }

        guard state == .nominal else {
            isThermalTripwireActive = true
            thermalTripwireCooldownEndsAt = nil
            return
        }

        guard isThermalTripwireActive else {
            thermalTripwireCooldownEndsAt = nil
            return
        }

        let cooldownEnd = Date().addingTimeInterval(Self.thermalRecoveryCooldown)
        thermalTripwireCooldownEndsAt = cooldownEnd
        thermalRecoveryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.thermalRecoveryCooldown))
            guard !Task.isCancelled,
                  let self,
                  self.processInfo.thermalState == .nominal else { return }
            self.isThermalTripwireActive = false
            self.thermalTripwireCooldownEndsAt = nil
            self.thermalRecoveryTask = nil
            self.recomputeMode(reason: "Thermal recovery cooldown elapsed")
        }
    }

    private func enforceThermalTripwire(reason: String) {
        // `recomputeMode` has already revoked heavy/decorative leases. Their
        // callbacks stop capture, AR, media and scripted rendering before the
        // app-owned reusable working set is discarded.
        purgeInactiveRendererResources()
        releaseReusableRendererAssets()
        let releasedBytes = assetCache.purge(reason: .thermalPressure)
        debugLog("Thermal tripwire enforced; released \(releasedBytes) bytes. Reason: \(reason)")
    }

    private func makeThermalTransitionRecord(
        to nextState: ProcessInfo.ThermalState
    ) -> PoplurThermalTransitionRecord {
        let now = Date()
        let cache = assetCache.snapshot()
        let live = registrations.values.compactMap(\.value)
        let owner = activeHeavyRendererID.flatMap { registrations[$0]?.value }
        let ownershipDuration = owner.flatMap { _ in
            activeHeavyRendererGrantedAt.map { max(0, now.timeIntervalSince($0)) }
        }
        return PoplurThermalTransitionRecord(
            id: UUID(),
            timestamp: now,
            previousState: Self.thermalName(thermalState),
            state: Self.thermalName(nextState),
            previousStateDurationSeconds: max(0, now.timeIntervalSince(thermalStateEnteredAt)),
            activeHeavyRenderer: owner?.name,
            activeHeavyOwnershipDurationSeconds: ownershipDuration,
            visibleRenderers: live.filter(\.isVisible).map(\.name).sorted(),
            modeBeforeTransition: mode.diagnosticName,
            decorativeFPSBeforeTransition: policy.targetFPS,
            interactiveFPSBeforeTransition: policy.interactiveTargetFPS,
            applicationLifecycle: applicationLifecycle.rawValue,
            cacheBytesBeforePurge: cache.estimatedByteCount,
            cachedItemCountBeforePurge: cache.itemCount
        )
    }

    private func appendThermalTransition(_ record: PoplurThermalTransitionRecord) {
        recentThermalTransitions.append(record)
        if recentThermalTransitions.count > Self.thermalTransitionLimit {
            recentThermalTransitions.removeFirst(recentThermalTransitions.count - Self.thermalTransitionLimit)
        }
        guard let data = try? JSONEncoder().encode(recentThermalTransitions) else { return }
        UserDefaults.standard.set(data, forKey: Self.thermalTransitionDefaultsKey)
    }

    private static func loadThermalTransitions() -> [PoplurThermalTransitionRecord] {
        guard let data = UserDefaults.standard.data(forKey: thermalTransitionDefaultsKey),
              let records = try? JSONDecoder().decode([PoplurThermalTransitionRecord].self, from: data) else {
            return []
        }
        return Array(records.suffix(thermalTransitionLimit))
    }

    private static func mode(
        for thermal: ProcessInfo.ThermalState,
        lowPower: Bool,
        memoryPressure: Bool,
        lifecycle: PoplurApplicationLifecycle
    ) -> PoplurPerformanceMode {
        if governorDisabled {
            return lifecycle != .active ? .emergency : .full
        }
        var result: PoplurPerformanceMode
        switch thermal {
        case .nominal: result = .full
        case .fair: result = .reduced
        case .serious, .critical: result = .emergency
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
                // Full quality is the resting state: gestures and real motion
                // get 60, decoration runs at 30 while visible and sleeps via
                // the web governor's ambient lease when the user goes idle.
                // The old 12/24 caps were the quality masking that got the
                // whole governor switched off — do not bring them back here;
                // the ladder below is where thermal reductions live.
                targetFPS: 30,
                interactiveTargetFPS: 60,
                particlesAllowed: true,
                particleDensityMultiplier: 0.15,
                dynamicShadowsAllowed: false,
                postProcessingAllowed: false,
                physicsQuality: .reduced,
                maximumPreferredTextureResolution: 1_024,
                assetCacheByteLimit: baseCacheByteLimit,
                decorativeRenderingAllowed: true,
                expensiveVideoTexturesAllowed: false,
                continuousRenderingAllowed: false
            )
        case .reduced:
            return PoplurPerformancePolicy(
                mode: mode,
                targetFPS: 8,
                interactiveTargetFPS: 15,
                particlesAllowed: true,
                particleDensityMultiplier: 0.05,
                dynamicShadowsAllowed: false,
                postProcessingAllowed: false,
                physicsQuality: .minimal,
                maximumPreferredTextureResolution: 768,
                assetCacheByteLimit: baseCacheByteLimit * 3 / 4,
                decorativeRenderingAllowed: true,
                expensiveVideoTexturesAllowed: false,
                continuousRenderingAllowed: false
            )
        case .lowPower:
            return PoplurPerformancePolicy(
                mode: mode,
                targetFPS: 4,
                interactiveTargetFPS: 10,
                particlesAllowed: false,
                particleDensityMultiplier: 0,
                dynamicShadowsAllowed: false,
                postProcessingAllowed: false,
                physicsQuality: .paused,
                maximumPreferredTextureResolution: 512,
                assetCacheByteLimit: baseCacheByteLimit / 2,
                decorativeRenderingAllowed: false,
                expensiveVideoTexturesAllowed: false,
                continuousRenderingAllowed: false
            )
        case .emergency:
            return PoplurPerformancePolicy(
                mode: mode,
                targetFPS: 1,
                interactiveTargetFPS: 5,
                particlesAllowed: false,
                particleDensityMultiplier: 0,
                dynamicShadowsAllowed: false,
                postProcessingAllowed: false,
                physicsQuality: .paused,
                maximumPreferredTextureResolution: 256,
                assetCacheByteLimit: baseCacheByteLimit / 4,
                decorativeRenderingAllowed: false,
                expensiveVideoTexturesAllowed: false,
                continuousRenderingAllowed: false
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
        // Static SceneKit content is event-driven: property, action and camera
        // changes still invalidate the view, but an unchanged scene no longer
        // burns a display loop just because a caller once requested it.
        rendersContinuously = desiredRendersContinuously && policy.continuousRenderingAllowed
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
