import AVFoundation
import Combine
import CoreLocation
import CoreMedia
import CoreVideo
import Foundation
import UIKit

private enum CameraAnalysisPipeline: Int {
    case faceRecognition
    case classification
    case objectBoxes

    var next: CameraAnalysisPipeline {
        CameraAnalysisPipeline(rawValue: (rawValue + 1) % 3) ?? .faceRecognition
    }
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
        return controller
    }()
    private var currentVideoInput: AVCaptureDeviceInput?
    private var isSessionConfigured: Bool = false

    // Queues
    let sessionQueue: DispatchQueue = DispatchQueue(label: "com.poplur.camerakit.session")
    let videoOutputQueue: DispatchQueue = DispatchQueue(label: "com.poplur.camerakit.videoOutput")

    // Video output and connection
    var videoDataOutput: AVCaptureVideoDataOutput?
    /// Real bounding boxes from Vision's built-in detectors. Optional because
    /// only the web home wants them; the native HomeView draws its own.
    var visionBoxDetector: VisionBoxDetector?
    var previewConnection: AVCaptureConnection?

    // Display layer for rendering processed frames
    var displayLayer: AVSampleBufferDisplayLayer?
    private var liveTimer: Timer?
    private var performanceRegistration: PoplurPerformanceRegistration?
    private var performanceWantsCapture = false
    private let frameProcessingLock = NSLock()
    private var frameProcessingAllowed = false
    /// Camera analysis is useful at human-response speed, not video frame rate.
    /// Start at face recognition so the classifier callback cannot immediately
    /// launch a duplicate face request on the first camera frame.
    private var nextAnalysisPipeline: CameraAnalysisPipeline = .faceRecognition
    private var nextAnalysisDispatchUptime: TimeInterval = 0
    private let minimumAnalysisDispatchSpacing: TimeInterval = 0.34

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
        videoDataOutput?.setSampleBufferDelegate(nil, queue: nil)
        let session = captureSession
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    @MainActor
    func prewarm() async {
        await configureSessionIfNeeded()
    }

    @MainActor
    func startPreview() async {
        await configureSessionIfNeeded()
        guard isReady else { return }
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

    /// Suspends the capture stream without tearing down session config.
    /// Call on tab-hide; pair with resumeCapture() on tab-show.
    @MainActor
    func suspendCapture() {
        performanceWantsCapture = false
        performanceRegistration?.setVisible(false)
        applyCapturePerformance(policy: PoplurPerformanceManager.shared.policy, granted: false)
        mlDetectionManager?.isEnabled = false
    }

    /// Resumes the capture stream after suspendCapture().
    /// Does nothing if the session was never configured.
    @MainActor
    func resumeCapture() {
        guard isReady else { return }
        performanceWantsCapture = true
        let registration = ensurePerformanceRegistration()
        registration.setVisible(true)
    }

    @MainActor
    func stop() {
        performanceWantsCapture = false
        performanceRegistration?.setVisible(false)
        isReady = false
        isRecording = false
        stopLiveVideo()
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }

    @MainActor
    func beginRecording() {
        resumeCapture()
        guard performanceRegistration?.isGrantedRendering == true else { return }
        isRecording = true
        lastVideoURL = nil
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("poplur-recording-\(UUID().uuidString)")
            .appendingPathExtension("mov")

        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.configureSessionIfNeededOnQueue(),
                  self.captureSession.outputs.contains(where: { $0 === self.movieOutput }) else {
                DispatchQueue.main.async { self.isRecording = false }
                return
            }

            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }

            if let connection = self.movieOutput.connection(with: .video) {
                self.configureVideoConnection(connection)
            }

            guard !self.movieOutput.isRecording else { return }
            self.movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        }
    }

    @MainActor
    func endRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            } else {
                DispatchQueue.main.async { self.isRecording = false }
            }
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
        capturePhoto()
    }

    /// Public shutter for the web-home bridge: the web cube tap on the camera
    /// tab fires the same capture path as the native cube-tap capture.
    @MainActor
    func triggerShutter() {
        capturePhoto()
    }

    @MainActor
    private func capturePhoto() {
        resumeCapture()
        guard performanceRegistration?.isGrantedRendering == true else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.configureSessionIfNeededOnQueue(),
                  self.captureSession.outputs.contains(where: { $0 === self.photoOutput }) else {
                return
            }

            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }

            if let connection = self.photoOutput.connection(with: .video) {
                self.configureVideoConnection(connection)
            }

            self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
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

            // The preview, web overlay, Vision requests and in-app recording all
            // fit comfortably in 720p. `.high` can select 1080p/4K depending on
            // the device, making the sensor, ISP and BGRA frame output process
            // substantially more pixels without improving the phone-sized UI.
            if captureSession.canSetSessionPreset(.hd1280x720) {
                captureSession.sessionPreset = .hd1280x720
            } else if captureSession.canSetSessionPreset(.high) {
                captureSession.sessionPreset = .high
            }

            guard captureSession.canAddInput(input) else { return false }
            captureSession.addInput(input)
            currentVideoInput = input
            currentCameraPosition = device.position
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
                self?.displayLayer?.flushAndRemoveImage()
                self?.arFilterManager?.stopARSession()
            }
        )
        performanceRegistration = registration
        return registration
    }

    @MainActor
    private func applyCapturePerformance(policy: PoplurPerformancePolicy, granted: Bool) {
        let shouldRun = granted && performanceWantsCapture
        frameProcessingLock.lock()
        frameProcessingAllowed = shouldRun
        frameProcessingLock.unlock()
        mlDetectionManager?.isEnabled = shouldRun && isMLDetectionEnabled && policy.mode != .emergency

        let requestedFPS = max(10, min(30, policy.targetFPS(for: .interactive)))
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.videoDataOutput?.connection(with: .video)?.isEnabled = shouldRun
            if shouldRun {
                self.applyCameraFrameRateOnQueue(requestedFPS)
                if !self.captureSession.isRunning { self.captureSession.startRunning() }
            } else if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }

        if !shouldRun {
            displayLayer?.flushAndRemoveImage()
            arFrameLock.lock()
            arFrameInFlight = false
            arFrameLock.unlock()
        }
    }

    private func applyCameraFrameRateOnQueue(_ requestedFPS: Int) {
        guard let device = currentVideoInput?.device else { return }
        let fps = Double(requestedFPS)
        guard device.activeFormat.videoSupportedFrameRateRanges.contains(where: {
            $0.minFrameRate <= fps && fps <= $0.maxFrameRate
        }) else { return }
        do {
            try device.lockForConfiguration()
            let duration = CMTime(value: 1, timescale: CMTimeScale(requestedFPS))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            #if DEBUG
            print("[PoplurPerformance] Camera FPS update failed: \(error.localizedDescription)")
            #endif
        }
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
                applyDefaultZoomOnQueue(to: device)
            } else if let oldInput = currentVideoInput, captureSession.canAddInput(oldInput) {
                captureSession.addInput(oldInput)
            }

            [photoOutput.connection(with: .video), movieOutput.connection(with: .video), videoDataOutput?.connection(with: .video)]
                .compactMap { $0 }
                .forEach(configureVideoConnection)

            captureSession.commitConfiguration()

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
            guard let self,
                  self.currentCameraPosition != .front,
                  let device = self.currentVideoInput?.device,
                  device.hasTorch else { return }

            do {
                try device.lockForConfiguration()
                if enabled, device.isTorchModeSupported(.on) {
                    try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                } else {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
            } catch {
                print("❌ [CameraKitController] Failed to update torch: \(error)")
            }
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
        isRecording = false
        lastVideoURL = url
        NotificationCenter.default.post(
            name: Notification.Name("RecordingOutputReady"),
            object: nil,
            userInfo: ["url": url]
        )
        NotificationCenter.default.post(
            name: Notification.Name("CaptureComplete"),
            object: nil,
            userInfo: ["videoURL": url]
        )
    }
}

extension CameraKitController: AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            print("❌ [CameraKitController] Photo capture failed: \(error)")
            return
        }

        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }

        Task { @MainActor in
            self.completePhotoCapture(image)
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

        guard FileManager.default.fileExists(atPath: outputFileURL.path) else {
            Task { @MainActor in self.isRecording = false }
            return
        }

        Task { @MainActor in
            self.completeVideoCapture(outputFileURL)
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
            // setupARFilterSupport() would replace this output; if AR is already
            // running, its output is already feeding the same delegate.
            guard self.videoDataOutput == nil else { return }
            self.attachVideoDataOutputOnQueue()
        }
    }

    /// Shared by AR setup and the ML-only path. MUST run on `sessionQueue`.
    private func attachVideoDataOutputOnQueue() {
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoOutputQueue)

        captureSession.beginConfiguration()
        if let existingOutput = videoDataOutput {
            captureSession.removeOutput(existingOutput)
        }
        if captureSession.canAddOutput(output) {
            captureSession.addOutput(output)
            videoDataOutput = output
            if let connection = output.connection(with: .video) {
                connection.isEnabled = true
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
    }

    /// Setup AR filter video processing
    func setupARFilterSupport(filterManager: ARFilterManager, displayLayer: AVSampleBufferDisplayLayer?) {
        self.arFilterManager = filterManager
        self.displayLayer = displayLayer
        
        // Enable default filter immediately on main actor
        Task { @MainActor in
            filterManager.activeFilter = .none
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Create video data output
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: self.videoOutputQueue)
            
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
                    connection.isEnabled = true
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
    
    // CRITICAL: Do NOT use @MainActor here - video frames arrive at 30-60fps
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

        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            dispatchNextAnalysisPipeline(
                sampleBuffer: sampleBuffer,
                pixelBuffer: pixelBuffer
            )
        }
        
        // If user recognition manager exposes registered-user radius, publish it here
        // Example:
        // if let radius = userRecognition.currentRegisteredUserRadius { Task { @MainActor in self.publishRegisteredUserRadius(radius) } }
        
        // Process AR filters and display frames
        guard let displayLayer = displayLayer else {
            // No display layer setup - AR filters not configured
            return
        }
        
        // Check if we have a filter manager
        guard let filterManager = arFilterManager else {
            // No filter manager - just display raw frames
            DispatchQueue.main.async {
                // Ensure displayLayer transform is correct for front / back
                if self.currentCameraPosition == .front {
                    self.displayLayer?.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
                } else {
                    self.displayLayer?.setAffineTransform(.identity)
                }
                // Recover display layer if it has failed or is unknown
                let status = displayLayer.status
                if status == .failed {
                    displayLayer.flushAndRemoveImage()
                }
                self.safelyEnqueueSampleBuffer(sampleBuffer, to: displayLayer)
            }
            return
        }
        
        // Vision + Core Image may take longer than a camera frame. Process at
        // most one frame at a time; otherwise asynchronous requests accumulate
        // and the filtered preview starts flashing or goes black under load.
        arFrameLock.lock()
        guard !arFrameInFlight else {
            arFrameLock.unlock()
            return
        }
        arFrameInFlight = true
        arFrameLock.unlock()

        // Track filter processing start time for performance monitoring
        let processingStartTime = CFAbsoluteTimeGetCurrent()
        
        // Process frame with AR filter (the method is nonisolated so it's safe to call from background thread)
        filterManager.applyFilterToVideoFrame(sampleBuffer) { [weak self] filteredBuffer in
            guard let self else { return }
            self.arFrameLock.lock()
            self.arFrameInFlight = false
            self.arFrameLock.unlock()
            guard let displayLayer = self.displayLayer else { return }
            
            // Calculate processing time
            let processingTime = (CFAbsoluteTimeGetCurrent() - processingStartTime) * 1000 // ms
            
            // Log performance if it takes longer than expected (>33ms for 30fps)
            if processingTime > 33 {
            }
            
            // Display the filtered (or original if filtering failed) frame
            let bufferToDisplay = filteredBuffer ?? sampleBuffer
            
            // Enqueue on main thread as CALayer operations must be on main thread
            DispatchQueue.main.async {
                // Ensure displayLayer transform is correct for front / back
                if self.currentCameraPosition == .front {
                    self.displayLayer?.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
                } else {
                    self.displayLayer?.setAffineTransform(.identity)
                }
                
                // Recover display layer if it has failed or is unknown
                let status = displayLayer.status
                if status == .failed {
                    displayLayer.flushAndRemoveImage()
                }
                
                if self.safelyEnqueueSampleBuffer(bufferToDisplay, to: displayLayer) {
                    self.cameraPreviewViewController.markFilteredFrameReady()
                }
            }
        }
    }

    /// Run at most one expensive Vision/Core ML family per scheduled camera
    /// frame. The old path handed the same buffer to classification, four box
    /// detectors and face recognition together. Their private queues then
    /// competed for CPU/GPU/Neural Engine time even though each result changes
    /// slowly. Round-robin dispatch keeps every feature live at roughly 1 Hz
    /// while leaving clear recovery time between pipelines.
    private func dispatchNextAnalysisPipeline(
        sampleBuffer: CMSampleBuffer,
        pixelBuffer: CVPixelBuffer
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= nextAnalysisDispatchUptime else { return }
        nextAnalysisDispatchUptime = now + minimumAnalysisDispatchSpacing

        let pipeline = nextAnalysisPipeline
        nextAnalysisPipeline = pipeline.next

        switch pipeline {
        case .faceRecognition:
            if let userRecognition = userRecognitionManager {
                // UserRecognitionManager publishes UI-observable state. Keep
                // its entry point on the main actor as before; only the Vision
                // request itself moves to its background queue.
                Task { @MainActor in
                    userRecognition.detectFaces(in: pixelBuffer)
                }
            }
        case .classification:
            if isMLDetectionEnabled {
                mlDetectionManager?.processFrame(sampleBuffer)
            }
        case .objectBoxes:
            visionBoxDetector?.process(pixelBuffer: pixelBuffer)
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
        mlDetectionManager?.onDetection = onDetection ?? { objects in
            NotificationCenter.default.post(
                name: NSNotification.Name("MLObjectsDetected"),
                object: nil,
                userInfo: ["objects": objects]
            )
        }
        isMLDetectionEnabled = true
    }
    
    /// Disable ML detection
    @MainActor
    func disableMLDetection() {
        mlDetectionManager?.isEnabled = false
        isMLDetectionEnabled = false
    }
}
