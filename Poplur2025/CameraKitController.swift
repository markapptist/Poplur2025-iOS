import AVFoundation
import Combine
import CoreLocation
import CoreMedia
import CoreVideo
import UIKit

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
    var previewConnection: AVCaptureConnection?

    // Display layer for rendering processed frames
    var displayLayer: AVSampleBufferDisplayLayer?
    private var liveTimer: Timer?

    // Camera position tracking
    var currentCameraPosition: AVCaptureDevice.Position = .back

    // Managers (declared as optionals to avoid hard dependencies here)
    var arFilterManager: ARFilterManager?
    var mlDetectionManager: SimplifiedMLDetectionManager?
    var userRecognitionManager: UserRecognitionManager?

    // Feature flags
    var isMLDetectionEnabled: Bool = false

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
    }

    @MainActor
    func prewarm() async {
        await configureSessionIfNeeded()
    }

    @MainActor
    func startPreview() async {
        await configureSessionIfNeeded()
        guard isReady else { return }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
        }
    }

    @MainActor
    func preparePreviewIfNeeded() {
        Task { await configureSessionIfNeeded() }
    }

    @MainActor
    func resumePreviewAfterInterruption() async {
        await startPreview()
    }

    @MainActor
    func stop() {
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

    @MainActor
    private func capturePhoto() {
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

            if captureSession.canSetSessionPreset(.high) {
                captureSession.sessionPreset = .high
            }

            guard captureSession.canAddInput(input) else { return false }
            captureSession.addInput(input)
            currentVideoInput = input
            currentCameraPosition = device.position

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
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video)
    }

    private func configureVideoConnection(_ connection: AVCaptureConnection) {
        if connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = (currentCameraPosition == .front)
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
    private func safelyEnqueueSampleBuffer(_ sampleBuffer: CMSampleBuffer, to displayLayer: AVSampleBufferDisplayLayer) {
        // Validate buffer
        if !CMSampleBufferIsValid(sampleBuffer) { return }
        if !CMSampleBufferDataIsReady(sampleBuffer) { return }

        // Validate layer status
        let status = displayLayer.status
        if status == .failed {
            displayLayer.flushAndRemoveImage()
            return
        }
        if status == .unknown {
            // Try flushing unknown state and wait for next frame
            displayLayer.flushAndRemoveImage()
            return
        }

        // Respect backpressure; drop frame if not ready
        if !displayLayer.isReadyForMoreMediaData { return }

        // Optionally ensure presentation time is monotonic
        displayLayer.enqueue(sampleBuffer)
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
        // Process ML detection if enabled
        if isMLDetectionEnabled {
            mlDetectionManager?.processFrame(sampleBuffer)
        }
        
        // Process user recognition (face detection for registered users)
        if let userRecognition = userRecognitionManager,
           let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            Task { @MainActor in
                userRecognition.detectFaces(in: pixelBuffer)
            }
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
                if status == .failed || status == .unknown {
                    displayLayer.flushAndRemoveImage()
                }
                self.safelyEnqueueSampleBuffer(sampleBuffer, to: displayLayer)
            }
            return
        }
        
        // Track filter processing start time for performance monitoring
        let processingStartTime = CFAbsoluteTimeGetCurrent()
        
        // Process frame with AR filter (the method is nonisolated so it's safe to call from background thread)
        filterManager.applyFilterToVideoFrame(sampleBuffer) { [weak self] filteredBuffer in
            guard let self = self,
                  let displayLayer = self.displayLayer else {
                return
            }
            
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
                if status == .failed || status == .unknown {
                    displayLayer.flushAndRemoveImage()
                }
                
                self.safelyEnqueueSampleBuffer(bufferToDisplay, to: displayLayer)
            }
        }
    }
    
    // MARK: - ML Detection Helper
    
    /// Enable ML detection with optional callback
    @MainActor
    func enableMLDetection(onDetection: (([DetectedObject]) -> Void)? = nil) {
        if mlDetectionManager == nil {
            mlDetectionManager = SimplifiedMLDetectionManager()
        }
        mlDetectionManager?.isEnabled = true
        mlDetectionManager?.onDetection = onDetection
        isMLDetectionEnabled = true
    }
    
    /// Disable ML detection
    @MainActor
    func disableMLDetection() {
        mlDetectionManager?.isEnabled = false
        isMLDetectionEnabled = false
    }
}
