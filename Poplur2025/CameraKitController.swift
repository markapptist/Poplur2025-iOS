import Foundation
import UIKit
import AVFoundation
import ARKit
import SwiftUI
import SCSDKCameraKit
import SCSDKCameraKitReferenceUI
import SCSDKCameraKitReferenceSwiftUI

// Adapter for SCSDKCameraKit ErrorHandler that simply logs errors.
private final class CameraKitPrintErrorHandler: ErrorHandler {
    func handleError(_ error: NSException) {
        print("[CK][ErrorHandler] CameraKit exception:", error.name.rawValue, error.reason ?? "(no reason)")
        if !error.callStackSymbols.isEmpty {
            print("[CK][ErrorHandler] stack:\n", error.callStackSymbols.joined(separator: "\n"))
        }
    }

    func handle(error: Error) {
        print("[CK][ErrorHandler] CameraKit error:", error.localizedDescription)
    }
}

final class CameraKitController: NSObject, ObservableObject {
    // UI-facing state must be main-actor; updates already hop to main.
    @MainActor @Published var lastPhoto: UIImage?
    @MainActor @Published var lastVideoURL: URL?
    @MainActor @Published var isRecording: Bool = false
    @MainActor @Published var isUsingFrontCamera: Bool = false
    @MainActor @Published var mode: CaptureMode = .video
    @MainActor @Published var flashOn: Bool = false
    // New: readiness gate for UI
    @MainActor @Published private(set) var isReady: Bool = false
    @MainActor @Published private(set) var cameraKitConfigured: Bool = false

    // Lenses
    @MainActor @Published var lenses: [Lens] = []
    @MainActor @Published var selectedLens: Lens? = nil

    // Reference UI Camera Controller (CameraKit-managed)
    private var cameraController: CameraController?

    // Expose CameraKit session (read-only) for SwiftUI PreviewView hookup
    var cameraKitSession: CameraKitProtocol? {
        cameraController?.cameraKit
    }

    // UIKit CameraKit PreviewView (from SCSDKCameraKit) - no longer used by SwiftUI path
    private var previewView: SCSDKCameraKit.PreviewView?

    // Keep AVFoundation pieces for your capture actions (photo/video) for now
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "CameraKitController.sessionQueue")

    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()

    private var activeRecordingURL: URL?

    private var isShuttingDown = false
    private var isStarting = false
    private var hasConfigured = false

    // MARK: - Public camera characteristics
    var minZoomFactor: CGFloat {
        (videoDeviceInput?.device.minAvailableVideoZoomFactor).map(CGFloat.init) ?? 1.0
    }

    var maxZoomFactor: CGFloat {
        (videoDeviceInput?.device.maxAvailableVideoZoomFactor).map(CGFloat.init) ?? 1.0
    }

    var previewHostView: UIView? { previewView }
    
    // Torch availability for current active device
    var isTorchAvailable: Bool {
        var available = false
        sessionQueue.sync {
            available = self.videoDeviceInput?.device.hasTorch ?? false
        }
        return available
    }

    // Expose session running state for diagnostics (thread-safe snapshot)
    var captureSessionRunning: Bool {
        var running = false
        sessionQueue.sync {
            running = self.captureSession.isRunning
        }
        return running
    }

    // Expose AVFoundation session for diagnostics / fallback preview (read-only)
    var avCaptureSession: AVCaptureSession { captureSession }
    
    // MARK: - Lenses plumbing placeholders
    private var lensesRepository: LensesRepository?

    private enum CameraKitConstants {
        static var apiToken: String {
            let token = Bundle.main.object(forInfoDictionaryKey: "CameraKitAPIToken") as? String ?? ""
            return token
        }
        static var lensGroupID: String? {
            Bundle.main.object(forInfoDictionaryKey: "CameraKitLensGroupID") as? String
        }
    }

    // Simple lenses persistence
    private let lensesCacheURL: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("lenses-cache.json")
    }()

    private func loadCachedLenses() -> [Lens] {
        // If your Lens type conforms to Codable, this will work.
        // If not, you can persist only the minimal metadata you need.
        do {
            let data = try Data(contentsOf: lensesCacheURL)
            let decoded = try JSONDecoder().decode([Lens].self, from: data)
            return decoded
        } catch {
            return []
        }
    }

    private func saveCachedLenses(_ list: [Lens]) {
        do {
            let data = try JSONEncoder().encode(list)
            try data.write(to: lensesCacheURL, options: .atomic)
        } catch {
            // Non-fatal
        }
    }

    func makePreviewView() -> UIView {
        if let pv = previewView { return pv }
        // Use the SCSDKCameraKit UIKit PreviewView (legacy UIKit path; SwiftUI path uses the SDK wrapper)
        let pv = SCSDKCameraKit.PreviewView()
        pv.automaticallyConfiguresTouchHandler = true
        pv.backgroundColor = .black
        // Fill the container; its layer uses resizeAspectFill already
        pv.contentMode = .aspectFill
        pv.layer.contentsGravity = .resizeAspectFill
        pv.insetsLayoutMarginsFromSafeArea = false
        previewView = pv
        return pv
    }

    // MARK: - Public lifecycle

    func start() async {
        // Immediately surface cached lenses to make UI feel instant.
        if await MainActor.run(body: { self.lenses.isEmpty }) {
            let cached = loadCachedLenses()
            if !cached.isEmpty {
                await MainActor.run {
                    self.lenses = cached
                    if self.selectedLens == nil {
                        self.selectedLens = cached.first
                    }
                }
            }
        }

        await configureIfNeeded()

        // Ensure captureSession is running before marking ready
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { cont.resume(); return }
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }
                cont.resume()
            }
        }

        // Update readiness and add diagnostics
        let runningNow = self.captureSessionRunning
        print("[CK][Start] captureSession running after start attempt: \(runningNow)")
        await MainActor.run { self.isReady = runningNow }

        if self.cameraKitSession == nil {
            print("[CK][Start] cameraKitSession is nil after start; attempting reconfigure")
            await self.configureIfNeeded()
        }

        // If not running yet, try one lightweight retry after a short delay
        if !runningNow {
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                let stillRunning = self.captureSessionRunning
                if !stillRunning {
                    print("[CK][Start] Session not running yet; attempting second start")
                    await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                        self.sessionQueue.async { [weak self] in
                            guard let self else { cont.resume(); return }
                            if !self.captureSession.isRunning {
                                self.captureSession.startRunning()
                            }
                            cont.resume()
                        }
                    }
                    let runningAfterRetry = self.captureSessionRunning
                    print("[CK][Start] captureSession running after retry: \(runningAfterRetry)")
                    await MainActor.run { self.isReady = runningAfterRetry }
                }
            }
        }

        // Ensure preview exists for UI layout immediately (UIKit path only).
        _ = makePreviewView()

        // Defer nonessential work slightly so the camera becomes interactive first.
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            await loadLensesIfConfigured()
            // After preview is up, bump preset to high for quality.
            bumpPresetToHighIfPossible()
        }

        Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let running = self.captureSessionRunning
            let hasCK = (self.cameraKitSession != nil)
            print("[CK][Start] Post-start check: running=\(running) cameraKitSession=\(hasCK)")
        }
    }

    func stop() {
        Task { @MainActor in self.isReady = false }
        // We keep the session running; OS throttles in background. Add stop if you prefer.
    }

    // MARK: - Configuration bootstrap

    private func configureIfNeeded() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { cont.resume(); return }

                // Build CameraKit CameraController once
                if self.cameraController == nil {
                    let token = CameraKitConstants.apiToken

                    // Increase cache size to reduce re-downloads of lens content.
                    let lensesConfig = LensesConfig(
                        cacheConfig: CacheConfig(lensContentMaxSize: 300 * 1024 * 1024) // 300 MB
                    )
                    let session = Session(sessionConfig: SessionConfig(apiToken: token),
                                          lensesConfig: lensesConfig,
                                          errorHandler: CameraKitPrintErrorHandler())

                    // Create controller with our session and our own AVCaptureSession
                    let controller = CameraController(cameraKit: session, captureSession: self.captureSession)

                    if let group = CameraKitConstants.lensGroupID, !group.isEmpty {
                        controller.groupIDs = [group]
                    }

                    self.cameraController = controller
                }

                // Configure CameraController (starts CameraKit and AV input) once
                if let controller = self.cameraController, !self.hasConfigured {
                    let orientation: AVCaptureVideoOrientation = .portrait
                    controller.configure(
                        orientation: orientation,
                        textInputContextProvider: nil,
                        agreementsPresentationContextProvider: nil,
                        completion: { [weak self] in
                            guard let self else { return }
                            print("[CK][Config] CameraController.configure completion called")
                            Task { @MainActor in
                                self.cameraKitConfigured = true
                            }
                        }
                    )
                    self.hasConfigured = true
                    if controller.cameraKit == nil {
                        print("[CK][Config] Warning: cameraKit session is nil right after configure")
                    } else {
                        print("[CK][Config] cameraKit session available after configure")
                    }
                }

                // If we already configured AVFoundation capture session, skip setup
                if self.videoDeviceInput == nil {
                    // Keep AVFoundation session for your photo/video actions
                    self.captureSession.beginConfiguration()
                    // Faster startup: begin with medium, bump to high later
                    if self.captureSession.canSetSessionPreset(.medium) {
                        self.captureSession.sessionPreset = .medium
                    } else {
                        self.captureSession.sessionPreset = .high
                    }

                    let defaultDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                        ?? AVCaptureDevice.default(for: .video)

                    guard let device = defaultDevice else {
                        self.captureSession.commitConfiguration()
                        cont.resume()
                        return
                    }

                    do {
                        let deviceInput = try AVCaptureDeviceInput(device: device)

                        if self.captureSession.canAddInput(deviceInput) {
                            self.captureSession.addInput(deviceInput)
                            self.videoDeviceInput = deviceInput
                            DispatchQueue.main.async {
                                self.isUsingFrontCamera = (device.position == .front)
                            }
                        } else {
                            print("[CK][Config] Cannot add video device input")
                        }

                        if self.captureSession.canAddOutput(self.photoOutput) {
                            self.captureSession.addOutput(self.photoOutput)
                            self.photoOutput.isHighResolutionCaptureEnabled = true
                        } else {
                            print("[CK][Config] Cannot add photo output")
                        }

                        if self.captureSession.canAddOutput(self.movieOutput) {
                            self.captureSession.addOutput(self.movieOutput)
                            if let connection = self.movieOutput.connection(with: .video), connection.isVideoOrientationSupported {
                                connection.videoOrientation = .portrait
                            }
                        } else {
                            print("[CK][Config] Cannot add movie output")
                        }

                        self.captureSession.commitConfiguration()
                    } catch {
                        print("[CK][Config] Failed to create device input: \(error.localizedDescription)")
                        self.captureSession.commitConfiguration()
                    }
                }

                // IMPORTANT: start running the capture session so CameraKit receives frames
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }

                // Initialize lenses repository placeholder if lens group is configured
                if let groupID = CameraKitConstants.lensGroupID {
                    self.lensesRepository = LensesRepository(groupID: groupID)
                }

                print("[CK][Config] hasConfigured=\(self.hasConfigured), inputs=\(self.captureSession.inputs.count), outputs=\(self.captureSession.outputs.count), running=\(self.captureSession.isRunning)")

                cont.resume()
            }
        }
    }

    // After initial bring-up, bump to .high for quality.
    private func bumpPresetToHighIfPossible() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            if self.captureSession.canSetSessionPreset(.high) {
                self.captureSession.sessionPreset = .high
            }
            self.captureSession.commitConfiguration()
        }
    }

    // MARK: - Lenses loading using placeholder repository

    private func loadLensesIfConfigured() async {
        guard let repo = lensesRepository else { return }
        do {
            let fetched = try await repo.fetchLenses()
            await MainActor.run {
                self.lenses = fetched
                self.selectedLens = self.selectedLens ?? fetched.first
            }
            // Persist for next launch warm start
            saveCachedLenses(fetched)
        } catch {
            print("[CK][Lenses] Failed to fetch lenses:", error.localizedDescription)
        }
    }

    // MARK: - Camera controls (AVFoundation for now)

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let currentInput = self.videoDeviceInput else { return }

            let newPosition: AVCaptureDevice.Position = (currentInput.device.position == .back) ? .front : .back
            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
                return
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)
                self.captureSession.beginConfiguration()
                self.captureSession.removeInput(currentInput)
                if self.captureSession.canAddInput(newInput) {
                    self.captureSession.addInput(newInput)
                    self.videoDeviceInput = newInput
                    DispatchQueue.main.async {
                        self.isUsingFrontCamera = (newPosition == .front)
                    }
                    // Turn off torch on camera switch to avoid invalid state when moving to a device without torch
                    if let oldDevice = currentInput.device as AVCaptureDevice?, oldDevice.hasTorch {
                        if oldDevice.isTorchActive {
                            do { try oldDevice.lockForConfiguration(); oldDevice.torchMode = .off; oldDevice.unlockForConfiguration() } catch {}
                        }
                    }
                    // Notify UI by re-publishing flashOn if torch not available on new device
                    DispatchQueue.main.async {
                        if !(self.videoDeviceInput?.device.hasTorch ?? false) {
                            self.flashOn = false
                        }
                    }
                } else {
                    if self.captureSession.canAddInput(currentInput) {
                        self.captureSession.addInput(currentInput)
                    }
                }
                self.captureSession.commitConfiguration()
                
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                    print("[CK][SwitchCamera] captureSession restarted after input swap")
                }
                
                print("[CK][SwitchCamera] Switched to \(newPosition == .front ? "front" : "back") camera")
            } catch {
                // no print here
            }
        }
    }

    func setTorch(on: Bool) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            guard device.hasTorch, device.isTorchAvailable else {
                DispatchQueue.main.async { self.flashOn = false }
                return
            }
            do {
                try device.lockForConfiguration()
                if on {
                    if device.isTorchModeSupported(.on) {
                        device.torchMode = .on
                        try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                        DispatchQueue.main.async { self.flashOn = true }
                    } else {
                        DispatchQueue.main.async { self.flashOn = false }
                    }
                } else {
                    device.torchMode = .off
                    DispatchQueue.main.async { self.flashOn = false }
                }
                device.unlockForConfiguration()
            } catch {
                DispatchQueue.main.async { self.flashOn = false }
            }
        }
    }

    func setZoom(factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()
                let clamped = max(device.minAvailableVideoZoomFactor, min(factor, device.maxAvailableVideoZoomFactor))
                device.videoZoomFactor = clamped
                device.unlockForConfiguration()
            } catch {
                // no print
            }
        }
    }

    func focus(at point: CGPoint, in view: UIView) {
        sessionQueue.async { [weak self] in
            guard let self, let device = self.videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {
                // no print
            }
        }
    }

    func takePhoto() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.captureSession.isRunning {
                print("[CK][Photo] Ignored: captureSession not running")
                return
            }
            if !self.captureSession.outputs.contains(self.photoOutput) {
                print("[CK][Photo] Ignored: photoOutput not attached")
                return
            }
            let settings = AVCapturePhotoSettings()
            settings.isHighResolutionPhotoEnabled = true
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func startRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.captureSession.isRunning {
                print("[CK][Video] Cannot start: captureSession not running")
                return
            }
            if !self.captureSession.outputs.contains(self.movieOutput) {
                print("[CK][Video] Cannot start: movieOutput not attached")
                return
            }
            guard !self.movieOutput.isRecording else { return }

            // Enforce max duration from settings (default 10s)
            let maxSeconds = SettingsStore.shared.maxVideoDurationSeconds
            self.movieOutput.maxRecordedDuration = CMTimeMakeWithSeconds(maxSeconds, preferredTimescale: 600)

            let tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mov")
            self.activeRecordingURL = tmpURL
            
            print("[CK][Video] Starting recording to: \(tmpURL)")
            print("[CK][Video] outputs attached at start: \(self.captureSession.outputs)")

            self.movieOutput.startRecording(to: tmpURL, recordingDelegate: self)
            DispatchQueue.main.async { self.isRecording = true }
        }
    }

    func stopRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard self.movieOutput.isRecording else {
                print("[CK][Video] Stop ignored: not recording")
                return
            }
            print("[CK][Video] stopRecording() called")
            self.movieOutput.stopRecording()
        }
    }
    
    // Safety net: if delegate failed to publish, try to persist active temp file
    func flushPendingRecordingIfAny() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let tmpURL = self.activeRecordingURL else {
                print("[CK][Video] flushPendingRecordingIfAny: no activeRecordingURL")
                return
            }
            let fm = FileManager.default
            guard fm.fileExists(atPath: tmpURL.path) else {
                print("[CK][Video] flushPendingRecordingIfAny: temp file missing at \(tmpURL.path)")
                return
            }
            do {
                let caches = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let recordingsDir = caches.appendingPathComponent("Recordings", isDirectory: true)
                if !fm.fileExists(atPath: recordingsDir.path) {
                    try fm.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
                }
                let dest = recordingsDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
                do {
                    try fm.moveItem(at: tmpURL, to: dest)
                    print("[CK][Video] flushPending: moved temp to \(dest)")
                    Task { @MainActor in
                        self.lastVideoURL = dest
                        print("[CK][Video] flushPending: published lastVideoURL: \(dest)")
                    }
                } catch {
                    print("[CK][Video] flushPending: move failed (\(error.localizedDescription)); attempting copy")
                    do {
                        try fm.copyItem(at: tmpURL, to: dest)
                        print("[CK][Video] flushPending: copied temp to \(dest)")
                        Task { @MainActor in
                            self.lastVideoURL = dest
                            print("[CK][Video] flushPending: published lastVideoURL (copied): \(dest)")
                        }
                    } catch {
                        print("[CK][Video] flushPending: copy failed: \(error.localizedDescription)")
                    }
                }
            } catch {
                print("[CK][Video] flushPending: failed to prepare caches dir: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - AVCapture delegates

extension CameraKitController: AVCapturePhotoCaptureDelegate, AVCaptureFileOutputRecordingDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("[CK][Photo] Error:", error.localizedDescription)
            return
        }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            print("[CK][Photo] No data")
            return
        }
        Task { @MainActor in
            self.lastPhoto = image
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        print("[CK][Video] didFinishRecording delegate fired")
        print("[CK][Video] outputFileURL: \(outputFileURL)")
        if let error = error {
            print("[CK][Video] Error in delegate: \(error.localizedDescription)")
        } else {
            print("[CK][Video] No error in delegate")
        }

        // Reset limit so next recordings can adopt updated settings if changed
        output.maxRecordedDuration = CMTime.invalid

        // Attempt to persist the temp file to Caches/Recordings and publish URL
        let fm = FileManager.default
        var finalURL: URL? = nil

        do {
            // Ensure the file actually exists before proceeding
            if fm.fileExists(atPath: outputFileURL.path) {
                let caches = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let recordingsDir = caches.appendingPathComponent("Recordings", isDirectory: true)
                if !fm.fileExists(atPath: recordingsDir.path) {
                    try fm.createDirectory(at: recordingsDir, withIntermediateDirectories: true)
                }
                let destURL = recordingsDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
                do {
                    try fm.moveItem(at: outputFileURL, to: destURL)
                    finalURL = destURL
                    print("[CK][Video] Moved recording to caches: \(destURL)")
                } catch {
                    print("[CK][Video] Move failed (\(error.localizedDescription)); attempting copy")
                    do {
                        try fm.copyItem(at: outputFileURL, to: destURL)
                        finalURL = destURL
                        print("[CK][Video] Copied recording to caches: \(destURL)")
                    } catch {
                        print("[CK][Video] Copy also failed: \(error.localizedDescription); will fall back to temp URL if usable")
                        // As a last resort, use the temp URL if it still exists
                        if fm.fileExists(atPath: outputFileURL.path) {
                            finalURL = outputFileURL
                        }
                    }
                }
            } else {
                print("[CK][Video] Temp output file does not exist; cannot persist")
            }
        } catch {
            print("[CK][Video] Failed to prepare recordings directory: \(error.localizedDescription)")
            if fm.fileExists(atPath: outputFileURL.path) {
                finalURL = outputFileURL
            }
        }

        Task { @MainActor in
            self.isRecording = false
            if let url = finalURL {
                self.lastVideoURL = url
                print("[CK][Video] Published lastVideoURL: \(url)")
            } else {
                self.lastVideoURL = nil
                print("[CK][Video] Unable to publish lastVideoURL (nil)")
            }
        }
    }
}

