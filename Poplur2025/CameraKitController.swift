import AVFoundation
import Combine
import CoreImage
import CoreLocation
import CoreMedia
import CoreVideo
import Foundation
import UIKit

private enum CameraAnalysisPipeline: Int {
    case faceRecognition
    case classification
    case objectBoxes
    case arFilter

    var next: CameraAnalysisPipeline {
        CameraAnalysisPipeline(rawValue: (rawValue + 1) % 4) ?? .faceRecognition
    }

    var diagnosticName: String {
        switch self {
        case .faceRecognition: return "face"
        case .classification: return "classification"
        case .objectBoxes: return "boxes"
        case .arFilter: return "arFilter"
        }
    }
}

private struct CameraAnalysisClaim {
    let id: UInt64
    let generation: UInt64
    let pipeline: CameraAnalysisPipeline
}

enum CameraColdBudgetState: String, Codable, Sendable {
    case running
    case parked
    case recording
}

enum CameraColdBudgetReason: String, Codable, Sendable {
    case entry
    case explicitResume
    case windowExpired
    case recordingStarted
    case recordingFinished
    case thermal
    case leftCamera
    case unavailable
}

struct CameraColdBudgetUpdate: Sendable {
    let state: CameraColdBudgetState
    let reason: CameraColdBudgetReason
    let canResume: Bool
    let windowMilliseconds: Int
}

private struct CameraColdBudgetRecord: Codable, Sendable {
    let timestamp: Date
    let state: CameraColdBudgetState
    let reason: CameraColdBudgetReason
    let canResume: Bool
    let activeWindowDurationSeconds: Double
    let thermalState: String
    let performanceMode: String
    let applicationLifecycle: String
    let analysisFamilyInFlight: String?
    let lastAnalysisTimeoutFamily: String?
    let cameraPosition: String
    let wasRecording: Bool
    let mlEnabled: Bool
    let arEnabled: Bool
    let torchEnabled: Bool
}

final class CameraKitController: NSObject, ObservableObject, RecordPreviewViewControllerProviding, RecordPreviewViewProviding, PreviewViewControllerProviding, PreviewViewProviding {
    @Published var isReady: Bool = false
    @Published var isRecording: Bool = false
    @Published var lastVideoURL: URL? = nil
    @Published var isTorchOn: Bool = false
    @Published var isScreenFlashOn: Bool = false
    @Published var isLiveVideoActive: Bool = false
    @Published var liveVideoSeconds: Int = 0
    @Published var liveViewerCount: Int = 0
    @Published var liveLocationName: String? = nil
    @Published var liveCoordinate: CLLocationCoordinate2D? = nil
    @Published var liveRadiusMeters: Double = 0

    // Core capture components
    let captureSession: AVCaptureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let arFrameLock = NSLock()
    private var arFrameInFlight = false
    private let movieOutput = AVCaptureMovieFileOutput()
    private lazy var cameraPreviewViewController: CameraPreviewViewController = {
        let controller = CameraPreviewViewController()
        controller.setCaptureSession(captureSession)
        controller.onParkedPreviewTap = { [weak self] in
            Task { @MainActor [weak self] in
                await self?.resumePreviewFromUserGesture()
            }
        }
        return controller
    }()
    private var currentVideoInput: AVCaptureDeviceInput?
    private var isSessionConfigured: Bool = false

    // Queues
    let sessionQueue: DispatchQueue = DispatchQueue(label: "com.poplur.camerakit.session")
    let videoOutputQueue: DispatchQueue = DispatchQueue(label: "com.poplur.camerakit.videoOutput")
    private let coldBudgetDeadlineQueue = DispatchQueue(label: "com.poplur.camerakit.coldBudgetDeadline")

    // Video output and connection
    var videoDataOutput: AVCaptureVideoDataOutput?
    /// Capability survives a hard park so an explicit resume can rebuild the
    /// frame-output path without relying on the web layer to mount again.
    private var wantsVideoFrameDelivery = false
    private var isVideoFrameDelegateAttached = false
    /// Real bounding boxes from Vision's built-in detectors. Optional because
    /// only the web home wants them; the native HomeView draws its own.
    var visionBoxDetector: VisionBoxDetector?
    var previewConnection: AVCaptureConnection?

    // Display layer for rendering processed frames
    var displayLayer: AVSampleBufferDisplayLayer?
    private var liveTimer: Timer?
    private var performanceRegistration: PoplurPerformanceRegistration?
    private var thermalTripwireCancellable: AnyCancellable?
    /// Capture-device pressure rises before the process-wide thermal tripwire.
    /// Observe it without polling so Camera can shed sensor/ISP work while the
    /// preview remains continuously visible. Owned and invalidated on the
    /// serial session queue so a parked camera retains no device observer.
    private var systemPressureObservation: NSKeyValueObservation?
    private var capturePressureCappedForCurrentLease = false
    private var performanceWantsCapture = false
    private var recordingDeadlineTask: DispatchWorkItem?
    private var photoAtomicDeadlineTask: DispatchWorkItem?
    private var previewWindowStartedAt: Date?
    private var isPreviewWindowActive = false
    private var isColdBudgetParked = false
    private var preserveLastPreviewFrame = false
    private var photoCaptureInFlight = false
    private var activePhotoSettingsUniqueID: Int64?
    private var photoOpenedItsOwnWindow = false
    private var parkAfterPhotoCapture = false
    private var pendingPhotoParkReason: CameraColdBudgetReason = .windowExpired
    private var pendingPhotoCanResume = true
    private var pendingPhotoPreserveLastFrame = true
    private var recordingStopRequested = false
    private var activeRecordingID: UUID?
    private var activeRecordingOutputURL: URL?
    private var recordingTerminalReason: CameraColdBudgetReason = .recordingFinished
    private var recordingCanResume = true
    private var recordingSuspendedARFilter: ARFilterManager.ARFilter?
    private var latestColdBudgetUpdate = CameraColdBudgetUpdate(
        state: .parked,
        reason: .unavailable,
        canResume: false,
        windowMilliseconds: 0
    )
    var onColdBudgetStateChange: ((CameraColdBudgetUpdate) -> Void)? {
        didSet {
            onColdBudgetStateChange?(latestColdBudgetUpdate)
            let shouldShowNativeAffordance = onColdBudgetStateChange == nil
                && latestColdBudgetUpdate.state == .parked
                && latestColdBudgetUpdate.canResume
            DispatchQueue.main.async { [weak self] in
                self?.cameraPreviewViewController.setColdBudgetResumeAffordanceVisible(
                    shouldShowNativeAffordance
                )
            }
        }
    }

    // Preview stays live while Camera is genuinely front-most. Hidden surfaces
    // and any non-nominal thermal state still hard-park immediately; an
    // arbitrary visible ten-second cutoff made the camera feel broken.
    private static let recordingMaximumDuration: TimeInterval = 10
    private static let recordingStopAcknowledgementDuration: TimeInterval = 1
    private static let photoAtomicMaximumDuration: TimeInterval = 3
    // Keep the sharp 1080p preview, but cap its capture graph below the old
    // 24 FPS sustained load. Recording remains 24 FPS. If capture-device
    // pressure rises, 15 FPS is the conservative continuous-preview floor;
    // this deliberately avoids the visibly laggy 10 FPS deployment.
    private static let previewFrameRate = 18
    private static let pressurePreviewFrameRate = 15
    private static let recordingFrameRateLimit = 24
    private static let previewAnalysisFrameSampleInterval: TimeInterval = 2.5
    private static let pressureAnalysisFrameSampleInterval: TimeInterval = 3.5
    private static let activeFilterFrameSampleInterval: TimeInterval = 0.5
    private static let pressureActiveFilterFrameSampleInterval: TimeInterval = 0.75
    private static let activeFilterPresentationHoldDuration: TimeInterval = 1.25
    private static let pressureActiveFilterPresentationHoldDuration: TimeInterval = 1.75
    private static let coldBudgetRecordLimit = 16
    private static let coldBudgetDefaultsKey = "CameraKitController.coldBudget.v2"

    /// Deadline ownership is read on the capture-session queue and mutated on
    /// the main actor. A tiny lock lets a cancelled, already-fired work item
    /// prove that it still owns the same preview/capture before stopping the
    /// sensor, so an old deadline cannot stop a newly resumed camera.
    private let hardDeadlineStateLock = NSLock()
    private var hardDeadlinePhotoSettingsUniqueID: Int64?
    private var hardDeadlineRecordingID: UUID?

    /// Every queued start/stop proves it still owns the current desired state.
    /// This prevents an old configure/start closure from reopening the sensor
    /// after a newer hard park has already won the race.
    private let captureLeaseStateLock = NSLock()
    private var captureLeaseGeneration: UInt64 = 0
    private var captureDesiredOn = false

    /// Retain only the latest sampled preview frame while capture is live. Hard park turns
    /// it into one UIImage, releases the pixel buffer, then removes every
    /// AVCapture input/output so the sensor and ISP have no remaining owner.
    private let retainedPreviewLock = NSLock()
    private var retainedPreviewPixelBuffer: CVPixelBuffer?

    private let frameProcessingLock = NSLock()
    private var frameProcessingAllowed = false
    private let analysisFrameGateLock = NSLock()
    private var analysisFrameGateOpen = false
    private var nextAnalysisSampleWorkItem: DispatchWorkItem?
    /// Camera analysis is useful at human-response speed, not video frame rate.
    /// Start at face recognition so the classifier callback cannot immediately
    /// launch a duplicate face request on the first camera frame.
    private var nextAnalysisPipeline: CameraAnalysisPipeline = .faceRecognition
    private var nextAnalysisDispatchUptime: TimeInterval = 0
    private var lastAnalysisDispatchUptime: [CameraAnalysisPipeline: TimeInterval] = [:]
    private let analysisStateLock = NSLock()
    private var analysisInFlight = false
    private var activeAnalysisPipeline: CameraAnalysisPipeline?
    private var analysisClaimID: UInt64 = 0
    /// A park invalidates result delivery without pretending an already-running
    /// Vision/Core ML request was cancelled. Its claim remains quarantined until
    /// the real callback arrives, so resume cannot overlap expensive families.
    private var analysisDeliveryGeneration: UInt64 = 0
    private var analysisDeliveryEnabled = false
    private var analysisClaimTimeoutTask: Task<Void, Never>?
    private var analysisTimedOutForCurrentWindow = false
    private var quarantinedAnalysisClaimID: UInt64?
    private var quarantinedAnalysisPipeline: CameraAnalysisPipeline?
    private var lastAnalysisTimeoutFamily: String?
    /// Protected by analysisStateLock. Explicit AR gets a separate bounded
    /// lane so its overlay remains usable without restoring the default idle
    /// AI cadence for face/classification/box work.
    private var activeFilterMinimumDispatchSpacing = CameraKitController.activeFilterFrameSampleInterval
    private var activeFilterPresentationHold = CameraKitController.activeFilterPresentationHoldDuration
    private var pendingMLDetectionHandler: (([DetectedObject]) -> Void)?
    private var faceRecognitionCompletion: AnyCancellable?
    private let arFilterStateLock = NSLock()
    private var arFilterProcessingWanted = false
    private var arFilterSelectionCancellable: AnyCancellable?
    /// At 0.67 seconds between families and two seconds between uses of the
    /// same family, face/classification/boxes each run no faster than ~0.5 Hz.
    private let minimumAnalysisDispatchSpacing: TimeInterval = 0.67
    private let minimumPerFamilyAnalysisSpacing: TimeInterval = 2.0
    private let maximumAnalysisClaimDuration: TimeInterval = 4.0
    /// Session-queue confined. AI/filters still receive fresh frames, but an
    /// idle preview does not wake the BGRA + Vision/Core ML path every 1.5s.
    private var analysisFrameSampleInterval = CameraKitController.previewAnalysisFrameSampleInterval

    // Camera position tracking
    var currentCameraPosition: AVCaptureDevice.Position = .back

    // Managers (declared as optionals to avoid hard dependencies here)
    var arFilterManager: ARFilterManager?
    var mlDetectionManager: SimplifiedMLDetectionManager?
    var userRecognitionManager: UserRecognitionManager?

    // Feature flags
    var isMLDetectionEnabled: Bool = true

    var recordPreviewViewController: UIViewController? { cameraPreviewViewController }
    var recordPreviewView: UIView? { nil }
    var previewViewController: UIViewController? { cameraPreviewViewController }
    var previewView: UIView? { nil }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(toggleTorchOn), name: Notification.Name("CameraToggleTorchOn"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(toggleTorchOff), name: Notification.Name("CameraToggleTorchOff"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(flipCamera), name: Notification.Name("FlipCameraRequested"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCubeTapCapture), name: Notification.Name("cameraCubeTabViewTapped"), object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        liveTimer?.invalidate()
        systemPressureObservation?.invalidate()
        videoDataOutput?.setSampleBufferDelegate(nil, queue: nil)
        let session = captureSession
        let temporaryRecordingURLs = [activeRecordingOutputURL, lastVideoURL].compactMap { $0 }
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
            temporaryRecordingURLs.forEach(PoplurTemporaryFileOwnership.deleteIfOwned)
        }
    }

    @discardableResult
    private func setCaptureDesired(_ desired: Bool) -> UInt64 {
        captureLeaseStateLock.lock()
        if captureDesiredOn != desired {
            captureDesiredOn = desired
            captureLeaseGeneration &+= 1
        }
        let generation = captureLeaseGeneration
        captureLeaseStateLock.unlock()
        return generation
    }

    private func captureLeaseMatches(generation: UInt64, desired: Bool) -> Bool {
        captureLeaseStateLock.lock()
        let matches = captureLeaseGeneration == generation && captureDesiredOn == desired
        captureLeaseStateLock.unlock()
        return matches
    }

    private func isCaptureDesired() -> Bool {
        captureLeaseStateLock.lock()
        let desired = captureDesiredOn
        captureLeaseStateLock.unlock()
        return desired
    }

    /// Safe for result bridges on any queue. A late callback may finish its own
    /// bookkeeping after park, but only a currently-owned processing lease may
    /// publish boxes, labels, filtered frames, or speech/UI side effects.
    var acceptsAnalysisResults: Bool {
        frameProcessingLock.lock()
        let processingAllowed = frameProcessingAllowed
        frameProcessingLock.unlock()
        return processingAllowed && isCaptureDesired()
    }

    @MainActor
    func prewarm() async {
        await configureSessionIfNeeded()
    }

    @MainActor
    func startPreview() async {
        await configureSessionIfNeeded()
        guard isReady else {
            publishColdBudgetState(state: .parked, reason: .unavailable, canResume: false)
            return
        }
        resumeCapture()
    }

    @MainActor
    func preparePreviewIfNeeded() {
        Task { await configureSessionIfNeeded() }
    }

    @MainActor
    func resumePreviewAfterInterruption() async {
        await startPreview()
    }

    /// Hard-parks capture whenever Camera is covered or leaves the foreground.
    /// Returning to a genuinely visible Camera surface may configure it again;
    /// hidden overlays and background lifecycle can never retain the sensor.
    @MainActor
    func suspendCapture(resetEntryBudget: Bool = true) {
        if photoCaptureInFlight,
           !PoplurPerformanceManager.shared.isThermalTripwireActive {
            isPreviewWindowActive = false
            parkAfterPhotoCapture = true
            pendingPhotoParkReason = .leftCamera
            pendingPhotoCanResume = !resetEntryBudget
            pendingPhotoPreserveLastFrame = !resetEntryBudget
            frameProcessingLock.lock()
            frameProcessingAllowed = false
            frameProcessingLock.unlock()
            invalidateAnalysisDeliveryForPark()
            CameraAIAnnouncer.shared.setLiveCameraActive(false)
            mlDetectionManager?.isEnabled = false
            toggleTorchOff()
            return
        }
        parkCamera(
            reason: .leftCamera,
            canResume: !resetEntryBudget,
            preserveLastFrame: !resetEntryBudget
        )
    }

    /// Opens preview on genuine Camera entry.
    @MainActor
    func resumeCapture() {
        beginPreviewWindow(reason: .entry, explicitUserResume: false)
    }

    /// Reopens a thermally parked preview from a deliberate tap after policy
    /// recovery. Ordinary menu/composer visibility uses startPreview().
    @MainActor
    func resumePreviewFromUserGesture() async {
        guard !photoCaptureInFlight, !isRecording else { return }
        await configureSessionIfNeeded()
        guard isReady else {
            publishColdBudgetState(state: .parked, reason: .unavailable, canResume: false)
            return
        }
        beginPreviewWindow(reason: .explicitResume, explicitUserResume: true)
    }

    @MainActor
    private func schedulePhotoHardDeadline(settingsUniqueID: Int64) {
        photoAtomicDeadlineTask?.cancel()
        hardDeadlineStateLock.lock()
        hardDeadlinePhotoSettingsUniqueID = settingsUniqueID
        hardDeadlineStateLock.unlock()

        let deadline = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.sessionQueue.async { [weak self] in
                guard let self else { return }
                self.hardDeadlineStateLock.lock()
                let stillOwnsPhoto = self.hardDeadlinePhotoSettingsUniqueID == settingsUniqueID
                if stillOwnsPhoto {
                    self.hardDeadlinePhotoSettingsUniqueID = nil
                }
                self.hardDeadlineStateLock.unlock()
                guard stillOwnsPhoto else { return }

                self.forceHardwareTorchOffOnQueue()
                if self.captureSession.isRunning {
                    self.captureSession.stopRunning()
                }
                DispatchQueue.main.async { [weak self] in
                    self?.expirePhotoCapture(settingsUniqueID: settingsUniqueID)
                }
            }
        }
        photoAtomicDeadlineTask = deadline
        coldBudgetDeadlineQueue.asyncAfter(
            deadline: .now() + Self.photoAtomicMaximumDuration,
            execute: deadline
        )
    }

    @MainActor
    private func cancelPhotoHardDeadline(settingsUniqueID: Int64?) {
        photoAtomicDeadlineTask?.cancel()
        photoAtomicDeadlineTask = nil
        hardDeadlineStateLock.lock()
        if settingsUniqueID == nil || hardDeadlinePhotoSettingsUniqueID == settingsUniqueID {
            hardDeadlinePhotoSettingsUniqueID = nil
        }
        hardDeadlineStateLock.unlock()
    }

    @MainActor
    private func expirePhotoCapture(settingsUniqueID: Int64) {
        guard photoCaptureInFlight,
              activePhotoSettingsUniqueID == settingsUniqueID else { return }
        parkAfterPhotoCapture = true
        pendingPhotoParkReason = .unavailable
        pendingPhotoCanResume = true
        pendingPhotoPreserveLastFrame = true
        // Invalidate the request before any late delegate callback can race a
        // later shutter press. The session and physical torch are already off.
        finishPhotoBudget()
    }

    @MainActor
    private func beginPreviewWindow(
        reason: CameraColdBudgetReason,
        explicitUserResume: Bool
    ) {
        guard isReady else {
            publishColdBudgetState(state: .parked, reason: .unavailable, canResume: false)
            return
        }
        let registration = ensurePerformanceRegistration()
        guard !PoplurPerformanceManager.shared.isThermalTripwireActive else {
            parkCamera(reason: .thermal, canResume: false, preserveLastFrame: true)
            return
        }
        guard !isPreviewWindowActive else { return }
        // Visibility is now the preview lease. Returning from Camera Roll,
        // composer or Hold legitimately resumes; only a thermal tripwire or a
        // hidden/background surface keeps the sensor parked.
        isPreviewWindowActive = true
        isColdBudgetParked = false
        preserveLastPreviewFrame = false
        cameraPreviewViewController.setParkedPreviewImage(nil)
        previewWindowStartedAt = Date()
        performanceWantsCapture = true
        CameraAIAnnouncer.shared.setLiveCameraActive(true)
        analysisStateLock.lock()
        analysisDeliveryEnabled = true
        analysisTimedOutForCurrentWindow = false
        lastAnalysisTimeoutFamily = nil
        analysisStateLock.unlock()
        restoreCameraFeaturesAfterRecordingIfNeeded()

        registration.setVisible(true)
        guard registration.isGrantedRendering else {
            parkCamera(reason: .unavailable, canResume: true, preserveLastFrame: true)
            return
        }

        applyCapturePerformance(policy: PoplurPerformanceManager.shared.policy, granted: true)
        publishColdBudgetState(state: .running, reason: reason, canResume: false)
        // There is deliberately no wall-clock preview cutoff. The OS thermal
        // tripwire, lifecycle/visibility and explicit media budgets are the
        // limits; normal Camera use must remain smooth and uninterrupted.
    }

    private func retainedPreviewImageOnQueue() -> UIImage? {
        retainedPreviewLock.lock()
        let pixelBuffer = retainedPreviewPixelBuffer
        retainedPreviewPixelBuffer = nil
        retainedPreviewLock.unlock()
        guard let pixelBuffer else { return nil }

        // One local context performs one conversion and is immediately
        // released; unlike a retained CIContext it cannot keep GPU caches warm
        // while the camera is parked.
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return nil }
        // The AVCaptureVideoDataOutput connection already rotates portrait
        // buffers by 90 degrees and mirrors the front camera. Tagging this
        // image `.right`/`.rightMirrored` would apply both transforms twice.
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    /// Close the delivery generation immediately when capture is parked. Vision,
    /// Core ML and AR requests already executing are not synchronously
    /// cancellable; keep their claim quarantined until its real callback arrives,
    /// while making every result from the old generation ineligible for UI,
    /// speech, or display-layer delivery.
    private func invalidateAnalysisDeliveryForPark() {
        analysisStateLock.lock()
        analysisDeliveryEnabled = false
        analysisDeliveryGeneration &+= 1
        if analysisInFlight {
            quarantinedAnalysisClaimID = analysisClaimID
            quarantinedAnalysisPipeline = activeAnalysisPipeline
        } else if quarantinedAnalysisClaimID == nil {
            activeAnalysisPipeline = nil
        }
        analysisInFlight = false
        analysisClaimTimeoutTask?.cancel()
        analysisClaimTimeoutTask = nil
        analysisStateLock.unlock()
    }

    /// The cold-budget acknowledgement. This runs entirely on the serial
    /// capture queue, stops the physical session synchronously, releases every
    /// input/output and only then publishes `parked` back on the main actor.
    private func hardParkCapture(
        reason: CameraColdBudgetReason,
        canResume: Bool,
        preserveLastFrame: Bool
    ) {
        let generation = setCaptureDesired(false)
        sessionQueue.async { [weak self] in
            guard let self,
                  self.captureLeaseMatches(generation: generation, desired: false) else { return }

            self.setVideoFrameDeliveryActiveOnQueue(false)
            self.forceHardwareTorchOffOnQueue()
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
            self.systemPressureObservation?.invalidate()
            self.systemPressureObservation = nil
            self.capturePressureCappedForCurrentLease = false

            self.hardDeadlineStateLock.lock()
            let captureDelegateOwnsOutputs = self.hardDeadlinePhotoSettingsUniqueID != nil
                || self.hardDeadlineRecordingID != nil
            self.hardDeadlineStateLock.unlock()
            guard !captureDelegateOwnsOutputs,
                  self.captureLeaseMatches(generation: generation, desired: false) else { return }

            if self.isSessionConfigured || !self.captureSession.inputs.isEmpty || !self.captureSession.outputs.isEmpty {
                self.captureSession.beginConfiguration()
                self.captureSession.inputs.forEach(self.captureSession.removeInput)
                self.captureSession.outputs.forEach(self.captureSession.removeOutput)
                self.captureSession.commitConfiguration()
            }
            self.currentVideoInput = nil
            self.videoDataOutput = nil
            self.previewConnection = nil
            self.isSessionConfigured = false

            let retainedImage = preserveLastFrame ? self.retainedPreviewImageOnQueue() : nil
            if !preserveLastFrame {
                self.retainedPreviewLock.lock()
                self.retainedPreviewPixelBuffer = nil
                self.retainedPreviewLock.unlock()
            }
            let stopped = !self.captureSession.isRunning
                && self.captureSession.inputs.isEmpty
                && self.captureSession.outputs.isEmpty

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.captureLeaseMatches(generation: generation, desired: false),
                      self.isColdBudgetParked else { return }
                self.isReady = false
                self.cameraPreviewViewController.setParkedPreviewImage(retainedImage)
                self.displayLayer?.flushAndRemoveImage()
                self.publishColdBudgetState(state: .parked, reason: reason, canResume: canResume)
                self.previewWindowStartedAt = nil
                #if DEBUG
                print(
                    "[CameraColdBudget] stopAck running=\(self.captureSession.isRunning) "
                        + "inputs=\(self.captureSession.inputs.count) outputs=\(self.captureSession.outputs.count) "
                        + "delegate=\(self.isVideoFrameDelegateAttached) complete=\(stopped) "
                        + "generation=\(generation)"
                )
                #endif
            }
        }
    }

    @MainActor
    private func parkCamera(
        reason: CameraColdBudgetReason,
        canResume: Bool,
        preserveLastFrame: Bool
    ) {
        isPreviewWindowActive = false
        isColdBudgetParked = true
        preserveLastPreviewFrame = preserveLastFrame
        invalidateAnalysisDeliveryForPark()
        CameraAIAnnouncer.shared.setLiveCameraActive(false)
        if photoCaptureInFlight {
            parkAfterPhotoCapture = true
            pendingPhotoParkReason = reason
            pendingPhotoCanResume = canResume
            pendingPhotoPreserveLastFrame = preserveLastFrame
        }

        if isRecording {
            requestRecordingStop(reason: reason, canResume: canResume)
        }
        performanceWantsCapture = false
        toggleTorchOff()
        mlDetectionManager?.isEnabled = false
        performanceRegistration?.setVisible(false)
        applyCapturePerformance(policy: PoplurPerformanceManager.shared.policy, granted: false)
        arFilterManager?.stopARSession()

        // Photo/recording delegates own their outputs until their bounded
        // completion/watchdog. Their finish paths call parkCamera again; only
        // then is it safe to remove the entire capture graph.
        guard !photoCaptureInFlight, !isRecording else { return }
        hardParkCapture(
            reason: reason,
            canResume: canResume,
            preserveLastFrame: preserveLastFrame
        )
    }

    @MainActor
    private func suspendExpensiveCameraFeaturesForRecording() {
        frameProcessingLock.lock()
        frameProcessingAllowed = false
        frameProcessingLock.unlock()
        // A Vision/Core ML request launched by the live preview can finish after
        // recording has taken exclusive ownership of the capture graph. Close
        // that preview generation now so its late callback cannot paint, speak,
        // or enqueue a filtered frame over the recording UI.
        invalidateAnalysisDeliveryForPark()
        CameraAIAnnouncer.shared.setLiveCameraActive(false)
        mlDetectionManager?.isEnabled = false

        if let manager = arFilterManager, manager.activeFilter != .none {
            recordingSuspendedARFilter = manager.activeFilter
            manager.activeFilter = .none
            manager.stopARSession()
            NotificationCenter.default.post(
                name: Notification.Name("ARFiltersStateChanged"),
                object: nil,
                userInfo: ["isShown": false]
            )
        }
    }

    @MainActor
    private func restoreCameraFeaturesAfterRecordingIfNeeded() {
        guard let filter = recordingSuspendedARFilter else { return }
        recordingSuspendedARFilter = nil
        arFilterManager?.activeFilter = filter
        NotificationCenter.default.post(
            name: Notification.Name("ARFiltersStateChanged"),
            object: nil,
            userInfo: ["isShown": true]
        )
        NotificationCenter.default.post(
            name: Notification.Name("ARFilterChanged"),
            object: nil,
            userInfo: ["filter": filter.rawValue]
        )
    }

    @MainActor
    private func scheduleRecordingHardDeadline(recordingID: UUID) {
        recordingDeadlineTask?.cancel()
        hardDeadlineStateLock.lock()
        hardDeadlineRecordingID = recordingID
        hardDeadlineStateLock.unlock()

        let deadline = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.sessionQueue.async { [weak self] in
                guard let self else { return }
                self.hardDeadlineStateLock.lock()
                let stillOwnsRecording = self.hardDeadlineRecordingID == recordingID
                self.hardDeadlineStateLock.unlock()
                guard stillOwnsRecording else { return }

                // End the movie at the monotonic ten-second deadline on the
                // capture queue. The delegate gets a short bounded interval to
                // finalize the file before the emergency watchdog tears down
                // the whole session and settles UI state.
                self.forceHardwareTorchOffOnQueue()
                if self.movieOutput.isRecording {
                    self.movieOutput.stopRecording()
                }
                // `maxRecordedDuration` may have already made isRecording
                // false while its successful delegate is merely queued. Wait
                // the same bounded acknowledgement interval in both cases so
                // that legitimate ten-second output is not invalidated.
                self.scheduleRecordingStopWatchdog(
                    recordingID: recordingID,
                    reason: .recordingFinished,
                    canResume: true
                )
                DispatchQueue.main.async { [weak self] in
                    self?.recordingDeadlineDidFire(recordingID: recordingID)
                }
            }
        }
        recordingDeadlineTask = deadline
        coldBudgetDeadlineQueue.asyncAfter(
            deadline: .now() + Self.recordingMaximumDuration,
            execute: deadline
        )
    }

    @MainActor
    private func recordingDeadlineDidFire(recordingID: UUID) {
        guard activeRecordingID == recordingID, isRecording else { return }
        recordingDeadlineTask = nil
        recordingStopRequested = true
        recordingTerminalReason = .recordingFinished
        recordingCanResume = true
        // Physical torch shutdown already happened on the capture queue. Keep
        // published UI state consistent without waiting for another queue hop.
        isTorchOn = false
        isScreenFlashOn = false
        NotificationCenter.default.post(name: Notification.Name("ScreenFlashOff"), object: nil)
    }

    @MainActor
    private func cancelRecordingHardDeadline(clearOwnership: Bool) {
        recordingDeadlineTask?.cancel()
        recordingDeadlineTask = nil
        guard clearOwnership else { return }
        let recordingID = activeRecordingID
        hardDeadlineStateLock.lock()
        if recordingID == nil || hardDeadlineRecordingID == recordingID {
            hardDeadlineRecordingID = nil
        }
        hardDeadlineStateLock.unlock()
    }

    private func scheduleRecordingStopWatchdog(
        recordingID: UUID,
        reason: CameraColdBudgetReason,
        canResume: Bool
    ) {
        coldBudgetDeadlineQueue.asyncAfter(
            deadline: .now() + Self.recordingStopAcknowledgementDuration
        ) { [weak self] in
            guard let self else { return }
            self.sessionQueue.async { [weak self] in
                guard let self else { return }
                self.hardDeadlineStateLock.lock()
                let stillOwnsRecording = self.hardDeadlineRecordingID == recordingID
                self.hardDeadlineStateLock.unlock()
                guard stillOwnsRecording else { return }

                if self.movieOutput.isRecording {
                    self.movieOutput.stopRecording()
                }
                self.forceHardwareTorchOffOnQueue()
                if self.captureSession.isRunning {
                    self.captureSession.stopRunning()
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.activeRecordingID == recordingID else { return }
                    #if DEBUG
                    print("[CameraColdBudget] recording delegate watchdog forced session stop")
                    #endif
                    self.finishRecordingBudget(reason: reason, canResume: canResume)
                }
            }
        }
    }

    @MainActor
    private func finishRecordingBudget(
        reason: CameraColdBudgetReason,
        canResume: Bool,
        preserveOutput: Bool = false
    ) {
        let unfinishedOutputURL = activeRecordingOutputURL
        cancelRecordingHardDeadline(clearOwnership: true)
        recordingStopRequested = true
        isRecording = false
        activeRecordingID = nil
        activeRecordingOutputURL = nil
        if !preserveOutput, let unfinishedOutputURL {
            PoplurTemporaryFileOwnership.deleteIfOwned(unfinishedOutputURL)
        }
        parkCamera(reason: reason, canResume: canResume, preserveLastFrame: true)
        recordingStopRequested = false
    }

    @MainActor
    private func finishPhotoBudget(reason: CameraColdBudgetReason? = nil) {
        let settingsUniqueID = activePhotoSettingsUniqueID
        cancelPhotoHardDeadline(settingsUniqueID: settingsUniqueID)
        let hadPendingPark = parkAfterPhotoCapture
        let shouldPark = photoOpenedItsOwnWindow || hadPendingPark || reason != nil
        let finalReason = hadPendingPark ? pendingPhotoParkReason : (reason ?? pendingPhotoParkReason)
        let finalCanResume = hadPendingPark ? pendingPhotoCanResume : true
        let finalPreserveLastFrame = hadPendingPark ? pendingPhotoPreserveLastFrame : true
        photoCaptureInFlight = false
        activePhotoSettingsUniqueID = nil
        photoOpenedItsOwnWindow = false
        parkAfterPhotoCapture = false
        if shouldPark {
            parkCamera(
                reason: finalReason,
                canResume: finalCanResume,
                preserveLastFrame: finalPreserveLastFrame
            )
        }
    }

    @MainActor
    private func publishColdBudgetState(
        state: CameraColdBudgetState,
        reason: CameraColdBudgetReason,
        canResume: Bool
    ) {
        let update = CameraColdBudgetUpdate(
            state: state,
            reason: reason,
            canResume: canResume,
            windowMilliseconds: 0
        )
        guard latestColdBudgetUpdate.state != update.state
                || latestColdBudgetUpdate.reason != update.reason
                || latestColdBudgetUpdate.canResume != update.canResume else { return }

        let now = Date()
        let activeDuration = previewWindowStartedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        analysisStateLock.lock()
        let analysisFamily = activeAnalysisPipeline?.diagnosticName
        let timedOutAnalysisFamily = lastAnalysisTimeoutFamily
        analysisStateLock.unlock()
        let performanceManager = PoplurPerformanceManager.shared
        let record = CameraColdBudgetRecord(
            timestamp: now,
            state: state,
            reason: reason,
            canResume: canResume,
            activeWindowDurationSeconds: activeDuration,
            thermalState: Self.thermalName(ProcessInfo.processInfo.thermalState),
            performanceMode: performanceManager.mode.diagnosticName,
            applicationLifecycle: performanceManager.applicationLifecycle.rawValue,
            analysisFamilyInFlight: analysisFamily,
            lastAnalysisTimeoutFamily: timedOutAnalysisFamily,
            cameraPosition: currentCameraPosition == .front ? "front" : "back",
            wasRecording: isRecording,
            mlEnabled: mlDetectionManager?.isEnabled == true,
            arEnabled: arFilterManager?.activeFilter != .none,
            torchEnabled: isTorchOn || isScreenFlashOn
        )
        var records = Self.loadColdBudgetRecords()
        records.append(record)
        records = Array(records.suffix(Self.coldBudgetRecordLimit))
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.coldBudgetDefaultsKey)
        }

        latestColdBudgetUpdate = update
        cameraPreviewViewController.setColdBudgetResumeAffordanceVisible(
            onColdBudgetStateChange == nil && state == .parked && canResume
        )
        onColdBudgetStateChange?(update)
        #if DEBUG
        print(
            "[CameraColdBudget] state=\(state.rawValue) reason=\(reason.rawValue) "
            + "active=\(String(format: "%.2f", activeDuration))s thermal=\(record.thermalState) "
            + "mode=\(record.performanceMode) lifecycle=\(record.applicationLifecycle) "
            + "analysis=\(record.analysisFamilyInFlight ?? "none") recording=\(record.wasRecording) "
            + "analysisTimeout=\(record.lastAnalysisTimeoutFamily ?? "none") "
            + "ml=\(record.mlEnabled) ar=\(record.arEnabled) torch=\(record.torchEnabled)"
        )
        #endif
    }

    @MainActor
    func cameraColdBudgetDiagnosticsSummary(limit: Int = 8) -> String {
        Self.persistedColdBudgetDiagnosticsSummary(limit: limit)
    }

    static func persistedColdBudgetDiagnosticsSummary(limit: Int = 8) -> String {
        let records = Self.loadColdBudgetRecords().suffix(max(0, min(limit, Self.coldBudgetRecordLimit)))
        guard !records.isEmpty else { return "Camera cold budget: no transitions recorded" }
        let formatter = ISO8601DateFormatter()
        return records.map { record in
            "\(formatter.string(from: record.timestamp)) \(record.state.rawValue)/\(record.reason.rawValue) "
                + "duration=\(String(format: "%.2f", record.activeWindowDurationSeconds))s "
                + "thermal=\(record.thermalState) mode=\(record.performanceMode) "
                + "lifecycle=\(record.applicationLifecycle) analysis=\(record.analysisFamilyInFlight ?? "none") "
                + "analysisTimeout=\(record.lastAnalysisTimeoutFamily ?? "none") "
                + "camera=\(record.cameraPosition) recording=\(record.wasRecording) "
                + "ml=\(record.mlEnabled) ar=\(record.arEnabled) torch=\(record.torchEnabled)"
        }.joined(separator: "\n")
    }

    private static func loadColdBudgetRecords() -> [CameraColdBudgetRecord] {
        guard let data = UserDefaults.standard.data(forKey: coldBudgetDefaultsKey),
              let decoded = try? JSONDecoder().decode([CameraColdBudgetRecord].self, from: data) else {
            return []
        }
        return Array(decoded.suffix(coldBudgetRecordLimit))
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

    @MainActor
    func stop() {
        cancelRecordingHardDeadline(clearOwnership: !isRecording)
        if photoCaptureInFlight {
            finishPhotoBudget(reason: .leftCamera)
        } else {
            cancelPhotoHardDeadline(settingsUniqueID: activePhotoSettingsUniqueID)
        }
        parkCamera(reason: .leftCamera, canResume: false, preserveLastFrame: false)
        isReady = false
        stopLiveVideo()
    }

    @MainActor
    func beginRecording() {
        guard !isRecording, !photoCaptureInFlight else { return }
        beginPreviewWindow(reason: .recordingStarted, explicitUserResume: true)
        guard performanceRegistration?.isGrantedRendering == true,
              !PoplurPerformanceManager.shared.isThermalTripwireActive else {
            parkCamera(reason: .thermal, canResume: false, preserveLastFrame: true)
            return
        }

        isPreviewWindowActive = false
        previewWindowStartedAt = Date()
        let recordingID = UUID()
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("poplur-recording-\(recordingID.uuidString)")
            .appendingPathExtension("mov")
        PoplurTemporaryFileOwnership.claim(outputURL)
        recordingStopRequested = false
        activeRecordingID = recordingID
        activeRecordingOutputURL = outputURL
        recordingTerminalReason = .recordingFinished
        recordingCanResume = true
        isRecording = true
        replaceLastVideoURL(with: nil)
        suspendExpensiveCameraFeaturesForRecording()
        publishColdBudgetState(state: .recording, reason: .recordingStarted, canResume: false)
        applyCapturePerformance(
            policy: PoplurPerformanceManager.shared.policy,
            granted: performanceRegistration?.isGrantedRendering == true
        )

        scheduleRecordingHardDeadline(recordingID: recordingID)

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.hardDeadlineStateLock.lock()
            let stillOwnsRecording = self.hardDeadlineRecordingID == recordingID
            self.hardDeadlineStateLock.unlock()
            guard stillOwnsRecording else {
                PoplurTemporaryFileOwnership.deleteIfOwned(outputURL)
                return
            }
            guard self.isCaptureDesired() else {
                DispatchQueue.main.async {
                    guard self.activeRecordingID == recordingID else { return }
                    self.finishRecordingBudget(reason: .leftCamera, canResume: false)
                }
                return
            }
            guard self.configureSessionIfNeededOnQueue(),
                  self.captureSession.outputs.contains(where: { $0 === self.movieOutput }) else {
                DispatchQueue.main.async {
                    guard self.activeRecordingID == recordingID else { return }
                    self.finishRecordingBudget(reason: .unavailable, canResume: false)
                }
                return
            }

            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }

            if let connection = self.movieOutput.connection(with: .video) {
                self.configureVideoConnection(connection)
            }

            guard !self.movieOutput.isRecording else {
                DispatchQueue.main.async {
                    guard self.activeRecordingID == recordingID else { return }
                    self.finishRecordingBudget(reason: .unavailable, canResume: false)
                }
                return
            }
            self.movieOutput.maxRecordedDuration = CMTime(
                seconds: Self.recordingMaximumDuration,
                preferredTimescale: 600
            )
            self.movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        }
    }

    @MainActor
    func endRecording() {
        requestRecordingStop(reason: .recordingFinished, canResume: true)
    }

    @MainActor
    private func requestRecordingStop(reason: CameraColdBudgetReason, canResume: Bool) {
        guard isRecording, !recordingStopRequested else { return }
        guard let recordingID = activeRecordingID else {
            finishRecordingBudget(reason: reason, canResume: canResume)
            return
        }
        recordingStopRequested = true
        recordingTerminalReason = reason
        recordingCanResume = canResume
        cancelRecordingHardDeadline(clearOwnership: false)
        toggleTorchOff()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.hardDeadlineStateLock.lock()
            let stillOwnsRecording = self.hardDeadlineRecordingID == recordingID
            self.hardDeadlineStateLock.unlock()
            guard stillOwnsRecording else { return }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
            // False can mean AVFoundation has stopped the movie but has not
            // delivered its final delegate yet. Preserve ownership until that
            // callback or the bounded watchdog, rather than dropping output.
            self.scheduleRecordingStopWatchdog(
                recordingID: recordingID,
                reason: reason,
                canResume: canResume
            )
        }
    }

    @MainActor
    @objc func toggleLiveVideo() {
        if isLiveVideoActive {
            stopLiveVideo()
        } else {
            NotificationCenter.default.post(name: Notification.Name("LiveVideoNeedsLocation"), object: nil)
        }
    }

    @MainActor
    func startLiveVideo(
        at coordinate: CLLocationCoordinate2D,
        locationName: String,
        radiusMeters: Double,
        initialViewers: Int = 128
    ) {
        if isRecording {
            endRecording()
        }
        liveTimer?.invalidate()
        liveCoordinate = coordinate
        liveLocationName = locationName
        liveRadiusMeters = max(radiusMeters, 1_000)
        liveVideoSeconds = 0
        liveViewerCount = max(initialViewers, 1)
        isLiveVideoActive = true
        liveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isLiveVideoActive else { return }
                self.liveVideoSeconds += 1
                self.liveViewerCount = max(1, initialViewers + ((self.liveVideoSeconds * 7) % 43))
            }
        }
        NotificationCenter.default.post(
            name: Notification.Name("LiveVideoDidStart"),
            object: nil,
            userInfo: [
                "latitude": coordinate.latitude,
                "longitude": coordinate.longitude,
                "locationName": locationName,
                "radius": liveRadiusMeters
            ]
        )
    }

    @MainActor
    func stopLiveVideo() {
        liveTimer?.invalidate()
        liveTimer = nil
        isLiveVideoActive = false
        liveVideoSeconds = 0
        liveViewerCount = 0
        liveLocationName = nil
        liveCoordinate = nil
        liveRadiusMeters = 0
        NotificationCenter.default.post(name: Notification.Name("LiveVideoDidStop"), object: nil)
    }

    @MainActor
    @objc func toggleTorch() {
        isTorchOn ? toggleTorchOff() : toggleTorchOn()
    }

    @MainActor
    @objc func toggleTorchOn() {
        guard (isPreviewWindowActive || isRecording),
              performanceRegistration?.isGrantedRendering == true,
              !PoplurPerformanceManager.shared.isThermalTripwireActive else {
            toggleTorchOff()
            return
        }
        if currentCameraPosition == .front {
            isScreenFlashOn = true
            NotificationCenter.default.post(name: Notification.Name("ScreenFlashOn"), object: nil)
        } else {
            isTorchOn = true
            setHardwareTorch(enabled: true)
        }
    }

    @MainActor
    @objc func toggleTorchOff() {
        isTorchOn = false
        isScreenFlashOn = false
        NotificationCenter.default.post(name: Notification.Name("ScreenFlashOff"), object: nil)
        setHardwareTorch(enabled: false)
    }

    @MainActor
    @objc func toggleFlash() {
        toggleTorch()
    }

    /// Shared-web Camera zoom. The clay channel arrows and pinch gesture both
    /// send an absolute factor so repeated events cannot drift out of sync.
    @MainActor
    func setZoomFactor(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentVideoInput?.device else { return }
            // `factor` arrives in UI units (0.5× / 1× / 2×). Scale by the
            // device's 1× baseline so a dual-wide virtual device lands on the
            // right lens: UI 0.5× = factor 1.0 (ultra-wide), UI 1× = the
            // switch-over factor (wide), and so on.
            let baseline = Self.displayZoomBaseline(for: device)
            let minimum = device.minAvailableVideoZoomFactor
            let maximum = min(4 * baseline, device.maxAvailableVideoZoomFactor)
            let next = min(maximum, max(minimum, factor * baseline))
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = next
                device.unlockForConfiguration()
            } catch {
                print("❌ [CameraKitController] Failed to update zoom: \(error)")
            }
        }
    }

    @MainActor
    @objc func flipCamera() {
        currentCameraPosition = currentCameraPosition == .front ? .back : .front
        if currentCameraPosition != .front {
            isScreenFlashOn = false
            NotificationCenter.default.post(name: Notification.Name("ScreenFlashOff"), object: nil)
        } else {
            isTorchOn = false
            setHardwareTorch(enabled: false)
        }

        sessionQueue.async { [weak self] in
            self?.switchCameraOnQueue()
        }
    }

    @MainActor
    @objc func switchCamera() {
        flipCamera()
    }

    @MainActor
    @objc private func handleCubeTapCapture() {
        guard isPreviewWindowActive,
              !isColdBudgetParked,
              performanceWantsCapture else { return }
        capturePhoto()
    }

    /// Public shutter for the web-home bridge: the web cube tap on the camera
    /// tab fires the same capture path as the native cube-tap capture.
    @MainActor
    func triggerShutter() {
        guard isPreviewWindowActive,
              !isColdBudgetParked,
              performanceWantsCapture else { return }
        capturePhoto()
    }

    @MainActor
    private func capturePhoto() {
        guard !photoCaptureInFlight,
              !isRecording,
              isPreviewWindowActive,
              !isColdBudgetParked,
              performanceWantsCapture else { return }
        let alreadyRunning = isPreviewWindowActive
        beginPreviewWindow(reason: .explicitResume, explicitUserResume: true)
        guard performanceRegistration?.isGrantedRendering == true,
              !PoplurPerformanceManager.shared.isThermalTripwireActive else {
            parkCamera(reason: .thermal, canResume: false, preserveLastFrame: true)
            return
        }

        let photoSettings = AVCapturePhotoSettings()
        photoCaptureInFlight = true
        activePhotoSettingsUniqueID = photoSettings.uniqueID
        photoOpenedItsOwnWindow = !alreadyRunning
        parkAfterPhotoCapture = false
        pendingPhotoParkReason = .windowExpired
        pendingPhotoCanResume = true
        pendingPhotoPreserveLastFrame = true
        schedulePhotoHardDeadline(settingsUniqueID: photoSettings.uniqueID)

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.hardDeadlineStateLock.lock()
            let stillOwnsPhoto = self.hardDeadlinePhotoSettingsUniqueID == photoSettings.uniqueID
            self.hardDeadlineStateLock.unlock()
            guard stillOwnsPhoto else { return }
            guard self.isCaptureDesired(),
                  self.configureSessionIfNeededOnQueue(),
                  self.captureSession.outputs.contains(where: { $0 === self.photoOutput }) else {
                DispatchQueue.main.async {
                    guard self.activePhotoSettingsUniqueID == photoSettings.uniqueID else { return }
                    self.finishPhotoBudget(reason: .unavailable)
                }
                return
            }

            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }

            if let connection = self.photoOutput.connection(with: .video) {
                self.configureVideoConnection(connection)
            }

            self.photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }

    @MainActor
    private func configureSessionIfNeeded() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                let configured = self.configureSessionIfNeededOnQueue()
                DispatchQueue.main.async {
                    self.isReady = configured
                    self.cameraPreviewViewController.setCaptureSession(self.captureSession)
                    continuation.resume()
                }
            }
        }
    }

    @discardableResult
    private func configureSessionIfNeededOnQueue() -> Bool {
        guard !isSessionConfigured else { return true }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            return false
        }

        guard let device = preferredVideoDevice(position: currentCameraPosition) else {
            return false
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            captureSession.beginConfiguration()
            defer { captureSession.commitConfiguration() }

            // Keep an explicit 1080p ceiling for a sharp full-screen preview;
            // `.high` can silently select 4K on newer devices. Sensor/ISP
            // bandwidth is capped separately below, so energy reduction does
            // not come from returning to the blurry 720p configuration.
            if captureSession.canSetSessionPreset(.hd1920x1080) {
                captureSession.sessionPreset = .hd1920x1080
            } else if captureSession.canSetSessionPreset(.hd1280x720) {
                captureSession.sessionPreset = .hd1280x720
            } else if captureSession.canSetSessionPreset(.high) {
                captureSession.sessionPreset = .high
            }

            guard captureSession.canAddInput(input) else { return false }
            captureSession.addInput(input)
            currentVideoInput = input
            currentCameraPosition = device.position
            installSystemPressureObservationOnQueue(for: device)
            applyDefaultZoomOnQueue(to: device)

            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
            }

            if captureSession.canAddOutput(movieOutput) {
                captureSession.addOutput(movieOutput)
            }

            [photoOutput.connection(with: .video), movieOutput.connection(with: .video)]
                .compactMap { $0 }
                .forEach(configureVideoConnection)

            isSessionConfigured = true
            return true
        } catch {
            print("❌ [CameraKitController] Failed to configure camera input: \(error)")
            return false
        }
    }

    private func preferredVideoDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // The dual-wide virtual device spans ultra-wide + wide, which is what
        // makes the 0.5× preset real glass instead of a clamped no-op. Front
        // cameras (and older hardware) fall through to the plain wide angle.
        AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
    }

    /// Capture pressure is a camera-specific early warning and typically moves
    /// before ProcessInfo's device-wide thermal state. Once it rises during a
    /// lease, latch the conservative cap until Camera is fully parked rather
    /// than oscillating between frame rates as the enclosure cools.
    private func installSystemPressureObservationOnQueue(for device: AVCaptureDevice) {
        systemPressureObservation?.invalidate()
        capturePressureCappedForCurrentLease = device.systemPressureState.level != .nominal
        updateAnalysisCadenceOnQueue()
        systemPressureObservation = device.observe(\.systemPressureState, options: [.new]) {
            [weak self, weak device] _, _ in
            guard let self, let device else { return }
            let level = device.systemPressureState.level
            self.sessionQueue.async { [weak self, weak device] in
                guard let self,
                      let device,
                      self.currentVideoInput?.device.uniqueID == device.uniqueID else { return }
                self.applyCaptureSystemPressureOnQueue(level)
            }
        }
    }

    private func applyCaptureSystemPressureOnQueue(
        _ level: AVCaptureDevice.SystemPressureState.Level
    ) {
        guard level != .nominal else { return }
        capturePressureCappedForCurrentLease = true
        updateAnalysisCadenceOnQueue()
        guard isCaptureDesired(), !isRecording else { return }
        let applied = applyCameraFrameRateOnQueue(Self.pressurePreviewFrameRate)
        #if DEBUG
        print(
            "[PoplurPerformance] Camera pressure=\(level.rawValue) "
                + "fps=\(Self.pressurePreviewFrameRate) analysis="
                + "\(analysisFrameSampleInterval)s applied=\(applied)"
        )
        #endif
    }

    /// Session-queue entry point for both the default AI sampler and the
    /// explicit-filter lane. AR raises only its own bounded cadence; face,
    /// classification and object-box analysis are paused while AR is active.
    private func updateAnalysisCadenceOnQueue() {
        let filterActive = isARFilterProcessingWanted()
        let pressureCapped = capturePressureCappedForCurrentLease
        analysisFrameSampleInterval = filterActive
            ? (pressureCapped
                ? Self.pressureActiveFilterFrameSampleInterval
                : Self.activeFilterFrameSampleInterval)
            : (pressureCapped
                ? Self.pressureAnalysisFrameSampleInterval
                : Self.previewAnalysisFrameSampleInterval)

        analysisStateLock.lock()
        activeFilterMinimumDispatchSpacing = pressureCapped
            ? Self.pressureActiveFilterFrameSampleInterval
            : Self.activeFilterFrameSampleInterval
        activeFilterPresentationHold = pressureCapped
            ? Self.pressureActiveFilterPresentationHoldDuration
            : Self.activeFilterPresentationHoldDuration
        analysisStateLock.unlock()
    }

    /// The video zoom factor that shows as "1×" in the UI. On a virtual
    /// dual-wide device the wide lens sits at the first switch-over factor
    /// (factor 1.0 IS the ultra-wide, which the UI calls 0.5×); on a single
    /// wide camera this is simply 1.
    private static func displayZoomBaseline(for device: AVCaptureDevice) -> CGFloat {
        device.virtualDeviceSwitchOverVideoZoomFactors.first
            .map { CGFloat(truncating: $0) } ?? 1
    }

    /// Park a freshly configured device on UI 1× (the wide lens), not the
    /// ultra-wide the dual-wide device would otherwise open on.
    private func applyDefaultZoomOnQueue(to device: AVCaptureDevice) {
        let baseline = Self.displayZoomBaseline(for: device)
        guard baseline > 1 else { return }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = min(baseline, device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        } catch {
            print("❌ [CameraKitController] Failed to set default zoom: \(error)")
        }
    }

    private func configureVideoConnection(_ connection: AVCaptureConnection) {
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = (currentCameraPosition == .front)
        }
    }

    @MainActor
    private func ensurePerformanceRegistration() -> PoplurPerformanceRegistration {
        if let performanceRegistration { return performanceRegistration }
        let registration = PoplurPerformanceManager.shared.registerRenderer(
            name: "NativeCamera",
            classification: .heavy,
            rateClass: .interactive,
            priority: 120,
            onPolicy: { [weak self] policy, granted in
                self?.applyCapturePerformance(policy: policy, granted: granted)
            },
            onPurgeInactiveResources: { [weak self] in
                self?.purgeInactiveCameraResources()
            }
        )
        performanceRegistration = registration
        thermalTripwireCancellable = PoplurPerformanceManager.shared.$isThermalTripwireActive
            .removeDuplicates()
            .sink { [weak self] isActive in
                guard let self else { return }
                if isActive, self.performanceWantsCapture, !self.isColdBudgetParked {
                    self.parkCamera(reason: .thermal, canResume: false, preserveLastFrame: true)
                } else if !isActive,
                          self.isColdBudgetParked,
                          self.latestColdBudgetUpdate.reason == .thermal {
                    // Recovery only restores the explicit affordance. It never
                    // reopens the sensor or grants a fresh automatic window.
                    self.publishColdBudgetState(state: .parked, reason: .thermal, canResume: true)
                }
            }
        return registration
    }

    @MainActor
    private func applyCapturePerformance(policy: PoplurPerformancePolicy, granted: Bool) {
        if !granted,
           performanceWantsCapture,
           PoplurPerformanceManager.shared.isThermalTripwireActive,
           !isColdBudgetParked {
            parkCamera(reason: .thermal, canResume: false, preserveLastFrame: true)
            return
        }

        let shouldRun = granted && performanceWantsCapture
        let recording = isRecording
        let dataProcessingAllowed = shouldRun && !recording
        frameProcessingLock.lock()
        frameProcessingAllowed = dataProcessingAllowed
        frameProcessingLock.unlock()
        mlDetectionManager?.isEnabled = dataProcessingAllowed
            && isMLDetectionEnabled
            && policy.mode != .emergency

        let requestedFPS = recording
            ? max(1, min(Self.recordingFrameRateLimit, policy.targetFPS(for: .interactive)))
            : max(1, min(Self.previewFrameRate, policy.targetFPS(for: .interactive)))
        let captureGeneration = setCaptureDesired(shouldRun)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if shouldRun {
                guard self.captureLeaseMatches(
                    generation: captureGeneration,
                    desired: true
                ) else { return }
                let pressureCapped = self.capturePressureCappedForCurrentLease && !recording
                self.updateAnalysisCadenceOnQueue()
                let effectiveFPS = pressureCapped
                    ? min(requestedFPS, Self.pressurePreviewFrameRate)
                    : requestedFPS
                if self.wantsVideoFrameDelivery && self.videoDataOutput == nil {
                    self.attachVideoDataOutputOnQueue()
                }
                self.setVideoFrameDeliveryActiveOnQueue(dataProcessingAllowed)
                guard self.applyCameraFrameRateOnQueue(effectiveFPS) else {
                    DispatchQueue.main.async { [weak self] in
                        self?.parkCamera(reason: .unavailable, canResume: true, preserveLastFrame: true)
                    }
                    return
                }
                guard self.captureLeaseMatches(
                    generation: captureGeneration,
                    desired: true
                ) else { return }
                if !self.captureSession.isRunning { self.captureSession.startRunning() }
            } else if self.movieOutput.isRecording {
                self.setVideoFrameDeliveryActiveOnQueue(false)
                self.movieOutput.stopRecording()
            } else {
                self.setVideoFrameDeliveryActiveOnQueue(false)
                if self.captureSession.isRunning {
                    self.captureSession.stopRunning()
                }
            }
        }

        if !shouldRun {
            if !preserveLastPreviewFrame {
                displayLayer?.flushAndRemoveImage()
            }
            arFrameLock.lock()
            arFrameInFlight = false
            arFrameLock.unlock()
        }
    }

    @discardableResult
    private func currentCaptureFrameRateLimitOnQueue() -> Int {
        if isRecording { return Self.recordingFrameRateLimit }
        return capturePressureCappedForCurrentLease
            ? Self.pressurePreviewFrameRate
            : Self.previewFrameRate
    }

    @discardableResult
    private func applyCameraFrameRateOnQueue(_ requestedFPS: Int) -> Bool {
        guard let input = currentVideoInput else { return false }
        let device = input.device
        let supportedRanges = device.activeFormat.videoSupportedFrameRateRanges
        // A recording that cannot run at 24 should preserve motion quality at
        // 30 before considering the preview's lower-energy rates. Preview and
        // pressure paths intentionally keep their low-first fallback order.
        let candidates = isRecording
            ? [requestedFPS, 30, Self.previewFrameRate, Self.pressurePreviewFrameRate]
            : [requestedFPS, Self.pressurePreviewFrameRate, Self.previewFrameRate, 24, 30]
        guard let selectedFPS = candidates.first(where: { candidate in
            let fps = Double(candidate)
            return supportedRanges.contains(where: {
                $0.minFrameRate <= fps && fps <= $0.maxFrameRate
            })
        }) else { return false }

        let duration = CMTime(value: 1, timescale: CMTimeScale(selectedFPS))
        let currentOverride = input.videoMinFrameDurationOverride
        let overrideNeedsUpdate = !currentOverride.isValid
            || currentOverride.timescale == 0
            || CMTimeCompare(currentOverride, duration) != 0
        let requiresLiveReconfiguration = captureSession.isRunning && overrideNeedsUpdate
        if requiresLiveReconfiguration {
            captureSession.beginConfiguration()
        }
        defer {
            if requiresLiveReconfiguration {
                captureSession.commitConfiguration()
            }
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            // activeVideo* controls delivered cadence. The input override is
            // equally important: it tells AVCaptureSession to allocate the
            // capture graph for this maximum rather than the active format's
            // potentially 60/120/240 FPS ceiling. Without it, a nominally
            // 24 FPS preview can still carry the sensor/ISP pressure of that
            // much higher format maximum.
            input.videoMinFrameDurationOverride = duration
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            return true
        } catch {
            #if DEBUG
            print("[PoplurPerformance] Camera FPS update failed: \(error.localizedDescription)")
            #endif
            return false
        }
    }

    @MainActor
    private func purgeInactiveCameraResources() {
        if !preserveLastPreviewFrame {
            displayLayer?.flushAndRemoveImage()
        }
        arFilterManager?.stopARSession()
        arFrameLock.lock()
        arFrameInFlight = false
        arFrameLock.unlock()
    }

    private func switchCameraOnQueue() {
        guard isSessionConfigured else { return }
        guard let device = preferredVideoDevice(position: currentCameraPosition) else { return }

        do {
            let newInput = try AVCaptureDeviceInput(device: device)
            captureSession.beginConfiguration()
            if let oldInput = currentVideoInput {
                captureSession.removeInput(oldInput)
            }

            if captureSession.canAddInput(newInput) {
                captureSession.addInput(newInput)
                currentVideoInput = newInput
                currentCameraPosition = device.position
                installSystemPressureObservationOnQueue(for: device)
                applyDefaultZoomOnQueue(to: device)
            } else if let oldInput = currentVideoInput, captureSession.canAddInput(oldInput) {
                captureSession.addInput(oldInput)
            }

            [photoOutput.connection(with: .video), movieOutput.connection(with: .video), videoDataOutput?.connection(with: .video)]
                .compactMap { $0 }
                .forEach(configureVideoConnection)

            captureSession.commitConfiguration()

            let fpsLimit = currentCaptureFrameRateLimitOnQueue()
            if !applyCameraFrameRateOnQueue(fpsLimit) {
                DispatchQueue.main.async { [weak self] in
                    self?.parkCamera(reason: .unavailable, canResume: true, preserveLastFrame: true)
                }
            }

            DispatchQueue.main.async {
                self.cameraPreviewViewController.setCaptureSession(self.captureSession)
                if self.currentCameraPosition == .front {
                    self.displayLayer?.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
                } else {
                    self.displayLayer?.setAffineTransform(.identity)
                }
            }
        } catch {
            print("❌ [CameraKitController] Failed to switch camera: \(error)")
        }
    }

    private func setHardwareTorch(enabled: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !enabled {
                self.forceHardwareTorchOffOnQueue()
                return
            }
            guard
                  self.currentCameraPosition != .front,
                  let device = self.currentVideoInput?.device,
                  device.hasTorch else { return }

            do {
                try device.lockForConfiguration()
                if device.isTorchModeSupported(.on) {
                    try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                }
                device.unlockForConfiguration()
            } catch {
                print("❌ [CameraKitController] Failed to update torch: \(error)")
            }
        }
    }

    /// Runs only on `sessionQueue`; hard deadlines use it before waiting for a
    /// main-actor state update so physical torch heat cannot outlive the cap.
    private func forceHardwareTorchOffOnQueue() {
        guard let device = currentVideoInput?.device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = .off
            device.unlockForConfiguration()
        } catch {
            print("❌ [CameraKitController] Failed to force torch off: \(error)")
        }
    }

    @MainActor
    private func completePhotoCapture(_ image: UIImage) {
        NotificationCenter.default.post(name: Notification.Name("ShowCapturePreviewOverlay"), object: image)
        NotificationCenter.default.post(
            name: Notification.Name("CaptureComplete"),
            object: nil,
            userInfo: ["image": image]
        )
    }

    @MainActor
    private func completeVideoCapture(_ url: URL) {
        replaceLastVideoURL(with: url)
        NotificationCenter.default.post(
            name: Notification.Name("RecordingOutputReady"),
            object: nil,
            userInfo: [
                "url": url,
                PoplurTemporaryFileOwnership.notificationKey: true
            ]
        )
        NotificationCenter.default.post(
            name: Notification.Name("CaptureComplete"),
            object: nil,
            userInfo: [
                "videoURL": url,
                PoplurTemporaryFileOwnership.notificationKey: true
            ]
        )
    }

    @MainActor
    private func replaceLastVideoURL(with replacement: URL?) {
        if let previous = lastVideoURL,
           previous.standardizedFileURL != replacement?.standardizedFileURL {
            PoplurTemporaryFileOwnership.deleteIfOwned(previous)
        }
        lastVideoURL = replacement
    }
}

extension CameraKitController: AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let settingsUniqueID = photo.resolvedSettings.uniqueID
        Task { @MainActor in
            guard self.photoCaptureInFlight,
                  self.activePhotoSettingsUniqueID == settingsUniqueID else {
                return
            }

            if let error {
                print("❌ [CameraKitController] Photo capture failed: \(error)")
                self.finishPhotoBudget(reason: .unavailable)
                return
            }

            guard let data = photo.fileDataRepresentation(),
                  let image = UIImage(data: data) else {
                self.finishPhotoBudget(reason: .unavailable)
                return
            }

            self.completePhotoCapture(image)
            self.finishPhotoBudget()
        }
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        if let error {
            print("❌ [CameraKitController] Video recording finished with error: \(error)")
        }

        Task { @MainActor in
            guard self.isRecording,
                  self.activeRecordingOutputURL == outputFileURL else {
                PoplurTemporaryFileOwnership.deleteIfOwned(outputFileURL)
                return
            }
            let reason = self.recordingTerminalReason
            let canResume = self.recordingCanResume
            let hasOutput = FileManager.default.fileExists(atPath: outputFileURL.path)
            self.finishRecordingBudget(
                reason: reason,
                canResume: canResume,
                preserveOutput: hasOutput
            )
            if hasOutput {
                self.completeVideoCapture(outputFileURL)
            }
        }
    }
}

// MARK: - AR Filter Support & AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraKitController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    /// Start delivering frames to `captureOutput`, with no AR-filter machinery.
    ///
    /// ML detection had no frames at all on the shipping path. The classifier,
    /// the face detector and the green boxes were all wired up and waiting on
    /// `captureOutput(_:didOutput:from:)`, which only fires when an
    /// AVCaptureVideoDataOutput is attached — and the ONLY code that attached one
    /// was `setupARFilterSupport`, called from exactly one place, `HomeView`.
    /// `HomeView` is not mounted when `PoplurWebHome.isEnabled`, so the web home
    /// ran a camera that never produced a single frame for Vision. Nothing
    /// errored; detection simply never happened.
    ///
    /// Same shape as the AVCaptureSession that was never stopped: capability
    /// wired only on the old native path and missed when Home became a WebView.
    /// This is the AR-free half, so the web home can have detection without
    /// pulling in a filter manager or a display layer it does not use.
    func startVideoFrameDelivery() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.wantsVideoFrameDelivery = true
            // setupARFilterSupport() would replace this output; if AR is already
            // running, its output is already feeding the same delegate.
            if self.videoDataOutput == nil {
                self.attachVideoDataOutputOnQueue()
            } else {
                self.frameProcessingLock.lock()
                let active = self.frameProcessingAllowed && self.isCaptureDesired()
                self.frameProcessingLock.unlock()
                self.setVideoFrameDeliveryActiveOnQueue(active)
            }
        }
    }

    /// Runs on sessionQueue. The hardware preview remains continuously visible
    /// at its governed cadence. Default AI opens the costly BGRA path every
    /// 2.5s (3.5s under pressure); an explicit AR filter temporarily uses its
    /// separate 0.5s/0.75s lane. Neither owns the full-rate sensor preview.
    private func setVideoFrameDeliveryActiveOnQueue(_ active: Bool) {
        nextAnalysisSampleWorkItem?.cancel()
        nextAnalysisSampleWorkItem = nil
        guard let output = videoDataOutput else { return }
        let connection = output.connection(with: .video)

        guard active else {
            analysisFrameGateLock.lock()
            analysisFrameGateOpen = false
            analysisFrameGateLock.unlock()
            connection?.isEnabled = false
            output.setSampleBufferDelegate(nil, queue: nil)
            isVideoFrameDelegateAttached = false
            return
        }

        if !isVideoFrameDelegateAttached {
            output.setSampleBufferDelegate(self, queue: videoOutputQueue)
            isVideoFrameDelegateAttached = true
        }
        analysisFrameGateLock.lock()
        analysisFrameGateOpen = true
        analysisFrameGateLock.unlock()
        connection?.isEnabled = true
    }

    private func closeSampleGateAndScheduleNextFrame() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.videoDataOutput?.connection(with: .video)?.isEnabled = false
            self.nextAnalysisSampleWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self,
                      self.isCaptureDesired() else { return }
                self.frameProcessingLock.lock()
                let allowed = self.frameProcessingAllowed
                self.frameProcessingLock.unlock()
                guard allowed, self.isVideoFrameDelegateAttached else { return }
                self.analysisFrameGateLock.lock()
                self.analysisFrameGateOpen = true
                self.analysisFrameGateLock.unlock()
                self.videoDataOutput?.connection(with: .video)?.isEnabled = true
            }
            self.nextAnalysisSampleWorkItem = work
            self.sessionQueue.asyncAfter(
                deadline: .now() + self.analysisFrameSampleInterval,
                execute: work
            )
        }
    }

    /// Shared by AR setup and the ML-only path. MUST run on `sessionQueue`.
    private func attachVideoDataOutputOnQueue() {
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true

        captureSession.beginConfiguration()
        if let existingOutput = videoDataOutput {
            captureSession.removeOutput(existingOutput)
        }
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            videoDataOutput = output
            if let connection = output.connection(with: .video) {
                connection.isEnabled = false
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = (currentCameraPosition == .front)
                }
                previewConnection = connection
            }
        }
        captureSession.commitConfiguration()
        frameProcessingLock.lock()
        let shouldDeliver = frameProcessingAllowed && isCaptureDesired()
        frameProcessingLock.unlock()
        setVideoFrameDeliveryActiveOnQueue(shouldDeliver)
        let fpsLimit = currentCaptureFrameRateLimitOnQueue()
        if !applyCameraFrameRateOnQueue(fpsLimit) {
            DispatchQueue.main.async { [weak self] in
                self?.parkCamera(reason: .unavailable, canResume: true, preserveLastFrame: true)
            }
        }
    }

    /// Setup AR filter video processing
    func setupARFilterSupport(filterManager: ARFilterManager, displayLayer: AVSampleBufferDisplayLayer?) {
        self.arFilterManager = filterManager
        self.displayLayer = displayLayer
        
        // Mirror the selected filter into a tiny lock-protected flag read by
        // the video queue. The hardware preview stays smooth at its governed
        // frame rate while both `.none` and active filters sample BGRA frames
        // without violating ARFilterManager's main-actor isolation.
        Task { @MainActor [weak self, weak filterManager] in
            guard let self, let filterManager else { return }
            self.arFilterSelectionCancellable = filterManager.$activeFilter
                .removeDuplicates()
                .sink { [weak self] filter in
                    self?.setARFilterProcessingWanted(filter != .none)
                }
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.wantsVideoFrameDelivery = true
            
            // Create video data output
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.alwaysDiscardsLateVideoFrames = true
            // Add to session
            self.captureSession.beginConfiguration()
            
            // Remove existing video output if any
            if let existingOutput = self.videoDataOutput {
                self.captureSession.removeOutput(existingOutput)
            }
            
            // Add new output
            if self.captureSession.canAddOutput(output) {
                self.captureSession.addOutput(output)
                self.videoDataOutput = output
                
                // Configure video orientation
                if let connection = output.connection(with: .video) {
                    connection.isEnabled = false
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                    if connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = (self.currentCameraPosition == .front)
                    }
                    self.previewConnection = connection
                }
            }
            
            self.captureSession.commitConfiguration()
            self.frameProcessingLock.lock()
            let shouldDeliver = self.frameProcessingAllowed && self.isCaptureDesired()
            self.frameProcessingLock.unlock()
            self.setVideoFrameDeliveryActiveOnQueue(shouldDeliver)
            let fpsLimit = self.currentCaptureFrameRateLimitOnQueue()
            if !self.applyCameraFrameRateOnQueue(fpsLimit) {
                DispatchQueue.main.async { [weak self] in
                    self?.parkCamera(reason: .unavailable, canResume: true, preserveLastFrame: true)
                }
            }
            
            // Setup displayLayer videoGravity and transform
            DispatchQueue.main.async {
                self.displayLayer?.videoGravity = .resizeAspectFill
                self.displayLayer?.opacity = 0.0
                if self.currentCameraPosition == .front {
                    self.displayLayer?.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
                } else {
                    self.displayLayer?.setAffineTransform(.identity)
                }
            }
        }
    }
    
    // Centralized safe enqueue to suppress spurious errors and respect backpressure
    @discardableResult
    private func safelyEnqueueSampleBuffer(_ sampleBuffer: CMSampleBuffer, to displayLayer: AVSampleBufferDisplayLayer) -> Bool {
        // Validate buffer
        if !CMSampleBufferIsValid(sampleBuffer) { return false }
        if !CMSampleBufferDataIsReady(sampleBuffer) { return false }

        // Validate layer status
        let status = displayLayer.status
        if status == .failed {
            displayLayer.flushAndRemoveImage()
            return false
        }
        if status == .unknown {
            // `.unknown` is also the initial state. Flush stale contents, then allow
            // this first ready frame to initialize the layer instead of staying blank.
            displayLayer.flushAndRemoveImage()
        }

        // Respect backpressure; drop frame if not ready
        if !displayLayer.isReadyForMoreMediaData { return false }

        // Optionally ensure presentation time is monotonic
        displayLayer.enqueue(sampleBuffer)
        return true
    }
    
    // Broadcast radius updates for registered user recognition
    @MainActor
    func publishRegisteredUserRadius(_ radius: Int) {
        NotificationCenter.default.post(name: Notification.Name("RegisteredUserRadiusUpdated"), object: nil, userInfo: ["radius": radius])
    }
    
    // MARK: - Video Sample Buffer Delegate
    
    // CRITICAL: Do NOT use @MainActor here - sampled video frames arrive on
    // the dedicated output queue.
    // Running this on main thread will freeze the UI
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameProcessingLock.lock()
        let mayProcessFrame = frameProcessingAllowed
        frameProcessingLock.unlock()
        guard mayProcessFrame else { return }

        analysisFrameGateLock.lock()
        let ownsSample = analysisFrameGateOpen
        analysisFrameGateOpen = false
        analysisFrameGateLock.unlock()
        guard ownsSample else { return }
        closeSampleGateAndScheduleNextFrame()

        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            retainedPreviewLock.lock()
            retainedPreviewPixelBuffer = pixelBuffer
            retainedPreviewLock.unlock()
            dispatchNextAnalysisPipeline(
                sampleBuffer: sampleBuffer,
                pixelBuffer: pixelBuffer
            )
        }
        
        // If user recognition manager exposes registered-user radius, publish it here
        // Example:
        // if let radius = userRecognition.currentRegisteredUserRadius { Task { @MainActor in self.publishRegisteredUserRadius(radius) } }
        
        // Once an AR manager exists, filtered frames are scheduled as one of
        // the serialized sampled families below. Running its landmark request
        // on every hardware-preview frame was the camera's largest
        // avoidable spike.
        guard let displayLayer, !isARFilterProcessingWanted() else { return }
        DispatchQueue.main.async {
            if self.currentCameraPosition == .front {
                self.displayLayer?.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
            } else {
                self.displayLayer?.setAffineTransform(.identity)
            }
            let status = displayLayer.status
            if status == .failed {
                displayLayer.flushAndRemoveImage()
            }
            self.safelyEnqueueSampleBuffer(sampleBuffer, to: displayLayer)
        }
    }

    /// Claim one expensive camera-analysis family at a time. A claim is held
    /// until that family's actual asynchronous completion callback, not merely
    /// until it has enqueued work. This prevents Vision, Core ML and AR
    /// landmark requests from overlapping on CPU/GPU/Neural Engine.
    private func claimNextAnalysisPipeline(at now: TimeInterval) -> CameraAnalysisClaim? {
        analysisStateLock.lock()
        defer { analysisStateLock.unlock() }
        guard analysisDeliveryEnabled,
              !analysisInFlight,
              quarantinedAnalysisClaimID == nil,
              !analysisTimedOutForCurrentWindow,
              now >= nextAnalysisDispatchUptime else { return nil }

        let activeFilterOnly = isARFilterProcessingWanted()
        var candidate: CameraAnalysisPipeline = activeFilterOnly ? .arFilter : nextAnalysisPipeline
        let candidateCount = activeFilterOnly ? 1 : 4
        for _ in 0..<candidateCount {
            let lastDispatch = lastAnalysisDispatchUptime[candidate] ?? -.greatestFiniteMagnitude
            let requiredSpacing = candidate == .arFilter
                ? activeFilterMinimumDispatchSpacing
                : minimumPerFamilyAnalysisSpacing
            let familyIsDue = now - lastDispatch >= requiredSpacing
            let familyIsAvailable: Bool
            switch candidate {
            case .faceRecognition:
                familyIsAvailable = userRecognitionManager != nil
            case .classification:
                familyIsAvailable = isMLDetectionEnabled && mlDetectionManager != nil
            case .objectBoxes:
                familyIsAvailable = visionBoxDetector != nil
            case .arFilter:
                familyIsAvailable = activeFilterOnly
                    && arFilterManager != nil
                    && displayLayer != nil
            }

            nextAnalysisPipeline = activeFilterOnly ? .arFilter : candidate.next
            if familyIsDue && familyIsAvailable {
                analysisInFlight = true
                activeAnalysisPipeline = candidate
                analysisClaimID &+= 1
                let claim = CameraAnalysisClaim(
                    id: analysisClaimID,
                    generation: analysisDeliveryGeneration,
                    pipeline: candidate
                )
                lastAnalysisDispatchUptime[candidate] = now
                nextAnalysisDispatchUptime = now + (candidate == .arFilter
                    ? activeFilterMinimumDispatchSpacing
                    : minimumAnalysisDispatchSpacing)
                analysisClaimTimeoutTask?.cancel()
                analysisClaimTimeoutTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(self?.maximumAnalysisClaimDuration ?? 4))
                    guard !Task.isCancelled else { return }
                    self?.expireAnalysisClaim(claim.id)
                }
                return claim
            }
            candidate = activeFilterOnly ? .arFilter : candidate.next
        }
        return nil
    }

    private func finishAnalysisPipeline(claimID: UInt64) {
        analysisStateLock.lock()
        guard analysisClaimID == claimID,
              analysisInFlight || quarantinedAnalysisClaimID == claimID else {
            analysisStateLock.unlock()
            return
        }
        analysisInFlight = false
        activeAnalysisPipeline = nil
        if quarantinedAnalysisClaimID == claimID {
            quarantinedAnalysisClaimID = nil
            quarantinedAnalysisPipeline = nil
        }
        analysisClaimTimeoutTask?.cancel()
        analysisClaimTimeoutTask = nil
        analysisStateLock.unlock()
    }

    private func isAnalysisClaimCurrent(_ claim: CameraAnalysisClaim) -> Bool {
        analysisStateLock.lock()
        let isCurrent = analysisDeliveryEnabled
            && analysisInFlight
            && analysisClaimID == claim.id
            && analysisDeliveryGeneration == claim.generation
        analysisStateLock.unlock()
        return isCurrent && acceptsAnalysisResults
    }

    private func expireAnalysisClaim(_ claimID: UInt64) {
        analysisStateLock.lock()
        guard analysisInFlight, analysisClaimID == claimID else {
            analysisStateLock.unlock()
            return
        }
        let family = activeAnalysisPipeline?.diagnosticName ?? "unknown"
        quarantinedAnalysisPipeline = activeAnalysisPipeline
        analysisInFlight = false
        activeAnalysisPipeline = nil
        // The bookkeeping latch is released so UI/capture cannot wedge, but
        // the timed-out Vision/CoreML/AR operation may still be executing and
        // is not safely cancellable. Quarantine its claim until its real late
        // completion arrives; explicit resume can show raw preview meanwhile
        // but can never overlap it with another expensive family.
        quarantinedAnalysisClaimID = claimID
        analysisTimedOutForCurrentWindow = true
        lastAnalysisTimeoutFamily = family
        analysisClaimTimeoutTask = nil
        analysisStateLock.unlock()
        #if DEBUG
        print("[CameraColdBudget] analysis timeout family=\(family); analysis parked for this preview window")
        #endif
        Task { @MainActor [weak self] in
            guard let self, self.performanceWantsCapture else { return }
            // A stuck AR request retains either its last completed filtered
            // frame or the still-visible hardware preview. Parking here emits
            // the explicit resume affordance and prevents a black auto-loop.
            self.parkCamera(reason: .unavailable, canResume: true, preserveLastFrame: true)
        }
    }

    private func isARFilterProcessingWanted() -> Bool {
        arFilterStateLock.lock()
        let wanted = arFilterProcessingWanted
        arFilterStateLock.unlock()
        return wanted
    }

    private func setARFilterProcessingWanted(_ wanted: Bool) {
        arFilterStateLock.lock()
        arFilterProcessingWanted = wanted
        arFilterStateLock.unlock()
        sessionQueue.async { [weak self] in
            guard let self, self.isCaptureDesired() else { return }
            self.updateAnalysisCadenceOnQueue()
            self.analysisStateLock.lock()
            self.nextAnalysisPipeline = wanted ? .arFilter : .faceRecognition
            self.nextAnalysisDispatchUptime = 0
            self.analysisStateLock.unlock()
            self.frameProcessingLock.lock()
            let allowed = self.frameProcessingAllowed
            self.frameProcessingLock.unlock()
            self.setVideoFrameDeliveryActiveOnQueue(allowed)
        }
    }

    private func currentActiveFilterPresentationHold() -> TimeInterval {
        analysisStateLock.lock()
        let duration = activeFilterPresentationHold
        analysisStateLock.unlock()
        return duration
    }

    private func runARAnalysis(
        manager: ARFilterManager,
        sampleBuffer: CMSampleBuffer,
        claim: CameraAnalysisClaim
    ) {
        guard let displayLayer else {
            finishAnalysisPipeline(claimID: claim.id)
            return
        }
        let presentationHold = currentActiveFilterPresentationHold()
        manager.applyFilterToVideoFrame(sampleBuffer) { [weak self, weak displayLayer] filteredBuffer in
            guard let self else { return }
            defer { self.finishAnalysisPipeline(claimID: claim.id) }
            guard self.isAnalysisClaimCurrent(claim) else { return }
            guard let displayLayer else { return }
            let bufferToDisplay = filteredBuffer ?? sampleBuffer
            DispatchQueue.main.async {
                if self.currentCameraPosition == .front {
                    self.displayLayer?.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
                } else {
                    self.displayLayer?.setAffineTransform(.identity)
                }
                let status = displayLayer.status
                if status == .failed {
                    displayLayer.flushAndRemoveImage()
                }
                if self.safelyEnqueueSampleBuffer(bufferToDisplay, to: displayLayer) {
                    self.cameraPreviewViewController.markFilteredFrameReady(
                        holdDuration: presentationHold
                    )
                }
            }
        }
    }

    /// Default AI families run no faster than once every two seconds. An
    /// explicitly selected AR filter temporarily owns the serialized lane at
    /// its bounded 2/1.3 FPS cadence; classification, boxes and recognition
    /// stay paused until the filter is dismissed.
    private func dispatchNextAnalysisPipeline(
        sampleBuffer: CMSampleBuffer,
        pixelBuffer: CVPixelBuffer
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        guard let claim = claimNextAnalysisPipeline(at: now) else { return }

        switch claim.pipeline {
        case .faceRecognition:
            guard let userRecognition = userRecognitionManager else {
                finishAnalysisPipeline(claimID: claim.id)
                return
            }
            Task { @MainActor [weak self, weak userRecognition] in
                guard let self else { return }
                guard let userRecognition else {
                    self.finishAnalysisPipeline(claimID: claim.id)
                    return
                }
                guard !userRecognition.isRecognizing else {
                    self.finishAnalysisPipeline(claimID: claim.id)
                    return
                }
                self.faceRecognitionCompletion?.cancel()
                self.faceRecognitionCompletion = userRecognition.$isRecognizing
                    .dropFirst()
                    .filter { !$0 }
                    .prefix(1)
                    .sink { [weak self, weak userRecognition] _ in
                        if let self,
                           !self.isAnalysisClaimCurrent(claim) {
                            // UserRecognitionManager owns its Vision request and
                            // may have published just before isRecognizing fell.
                            // Remove that stale UI state; speech was gated off
                            // synchronously at parkCamera().
                            userRecognition?.clearRecognition()
                        }
                        self?.faceRecognitionCompletion = nil
                        self?.finishAnalysisPipeline(claimID: claim.id)
                    }
                userRecognition.detectFaces(in: pixelBuffer)
                if !userRecognition.isRecognizing {
                    self.faceRecognitionCompletion?.cancel()
                    self.faceRecognitionCompletion = nil
                    self.finishAnalysisPipeline(claimID: claim.id)
                }
            }
        case .classification:
            guard let manager = mlDetectionManager, isMLDetectionEnabled else {
                finishAnalysisPipeline(claimID: claim.id)
                return
            }
            let downstreamDetection = manager.onDetection
            let downstreamError = manager.onError
            manager.onDetection = { [weak self, weak manager] objects in
                guard let self else {
                    manager?.onDetection = downstreamDetection
                    manager?.onError = downstreamError
                    return
                }
                if self.isAnalysisClaimCurrent(claim) {
                    downstreamDetection?(objects)
                }
                self.analysisStateLock.lock()
                let pendingHandler = self.pendingMLDetectionHandler
                self.pendingMLDetectionHandler = nil
                self.analysisStateLock.unlock()
                manager?.onDetection = pendingHandler ?? downstreamDetection
                manager?.onError = downstreamError
                self.finishAnalysisPipeline(claimID: claim.id)
            }
            manager.onError = { [weak self, weak manager] error in
                guard let self else {
                    manager?.onDetection = downstreamDetection
                    manager?.onError = downstreamError
                    return
                }
                if self.isAnalysisClaimCurrent(claim) {
                    downstreamError?(error)
                }
                self.analysisStateLock.lock()
                let pendingHandler = self.pendingMLDetectionHandler
                self.pendingMLDetectionHandler = nil
                self.analysisStateLock.unlock()
                manager?.onDetection = pendingHandler ?? downstreamDetection
                manager?.onError = downstreamError
                self.finishAnalysisPipeline(claimID: claim.id)
            }
            manager.processFrame(sampleBuffer)
        case .objectBoxes:
            guard let detector = visionBoxDetector else {
                finishAnalysisPipeline(claimID: claim.id)
                return
            }
            let downstream = detector.onBoxes
            detector.onBoxes = { [weak self, weak detector] boxes in
                if self?.isAnalysisClaimCurrent(claim) == true {
                    downstream?(boxes)
                }
                detector?.onBoxes = downstream
                self?.finishAnalysisPipeline(claimID: claim.id)
            }
            if !detector.process(pixelBuffer: pixelBuffer) {
                detector.onBoxes = downstream
                finishAnalysisPipeline(claimID: claim.id)
            }
        case .arFilter:
            guard let manager = arFilterManager else {
                finishAnalysisPipeline(claimID: claim.id)
                return
            }
            runARAnalysis(manager: manager, sampleBuffer: sampleBuffer, claim: claim)
        }
    }
    
    // MARK: - ML Detection Helper
    
    /// Enable ML detection with optional callback
    @MainActor
    func enableMLDetection(onDetection: (([DetectedObject]) -> Void)? = nil) {
        if mlDetectionManager == nil {
            mlDetectionManager = SimplifiedMLDetectionManager()
        }
        // CameraKitController owns the cross-pipeline cadence. Keeping the
        // manager's former every-12th-frame gate as well would compound the two
        // schedulers and make classification update only every ~12 seconds.
        mlDetectionManager?.frameSkipInterval = 1
        mlDetectionManager?.isEnabled = true
        let handler = onDetection ?? { objects in
            NotificationCenter.default.post(
                name: NSNotification.Name("MLObjectsDetected"),
                object: nil,
                userInfo: ["objects": objects]
            )
        }
        analysisStateLock.lock()
        if activeAnalysisPipeline == .classification
            || quarantinedAnalysisPipeline == .classification {
            // Do not overwrite the completion wrapper while a request is in
            // flight; install the new consumer atomically when it finishes.
            pendingMLDetectionHandler = handler
        } else {
            mlDetectionManager?.onDetection = handler
        }
        analysisStateLock.unlock()
        isMLDetectionEnabled = true
    }
    
    /// Disable ML detection
    @MainActor
    func disableMLDetection() {
        mlDetectionManager?.isEnabled = false
        isMLDetectionEnabled = false
    }
}
