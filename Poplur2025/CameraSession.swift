import AVFoundation
import UIKit

enum CaptureMode {
    case photo
    case video
}

enum SessionState: Equatable {
    case idle
    case configuring
    case running
    case interrupted(reason: AVCaptureSession.InterruptionReason?)
    case failed(message: String)
}

@MainActor
final class CameraSession: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var lastPhoto: UIImage?
    @Published var lastVideoURL: URL?
    @Published var mode: CaptureMode = .video
    @Published var isRecording = false
    @Published var isUsingFrontCamera = false

    @Published var cameraAuthorization: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var microphoneAuthorization: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published var sessionState: SessionState = .idle

    // Flash/torch
    @Published var flashMode: AVCaptureDevice.FlashMode = .off

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "CameraSession.sessionQueue")
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let videoDataOutput = AVCaptureVideoDataOutput()

    private var notificationTokens: [NSObjectProtocol] = []

    override init() {
        super.init()
        installObservers()
        Task { @MainActor in
            await ensurePermissionsAndConfigureIfNeeded()
        }
    }

    deinit { removeObservers() }

    private func installObservers() {
        let center = NotificationCenter.default
        let interrupted = center.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { [weak self] note in
            guard let self else { return }
            let reasonNum = note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber
            let reason = reasonNum.flatMap { AVCaptureSession.InterruptionReason(rawValue: $0.intValue) }
            self.sessionState = .interrupted(reason: reason)
            self.isRunning = self.session.isRunning
        }
        let interruptionEnded = center.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.cameraAuthorization == .authorized && !self.session.isRunning {
                Task { await self.start() }
            } else {
                self.sessionState = self.session.isRunning ? .running : .idle
            }
        }
        let runtimeError = center.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] note in
            guard let self else { return }
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
            self.sessionState = .failed(message: error?.localizedDescription ?? "Unknown camera error.")
            self.isRunning = self.session.isRunning
        }
        notificationTokens.append(contentsOf: [interrupted, interruptionEnded, runtimeError])
    }

    nonisolated private func removeObservers() {
        var tokens: [NSObjectProtocol] = []
        MainActor.assumeIsolated {
            tokens = self.notificationTokens
            self.notificationTokens.removeAll()
        }
        let center = NotificationCenter.default
        for token in tokens { center.removeObserver(token) }
    }

    // MARK: - Permissions + configuration

    private func ensurePermissionsAndConfigureIfNeeded() async {
        cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
        microphoneAuthorization = AVCaptureDevice.authorizationStatus(for: .audio)

        if cameraAuthorization == .notDetermined {
            let granted = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .video) { continuation.resume(returning: $0) }
            }
            cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
            if !granted {
                sessionState = .idle
                return
            }
        }

        if cameraAuthorization == .authorized {
            configureSessionIfNeeded()
        } else {
            sessionState = .idle
        }
    }

    private var didConfigure = false
    private func configureSessionIfNeeded() {
        guard !didConfigure else { return }
        sessionState = .configuring

        session.beginConfiguration()
        session.sessionPreset = .high

        guard let device = bestCamera(position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            sessionState = .failed(message: "Unable to access camera input.")
            return
        }
        session.addInput(input)
        videoDeviceInput = input
        isUsingFrontCamera = (device.position == .front)

        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
        }
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        }
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }

        session.commitConfiguration()
        didConfigure = true
        sessionState = .idle
    }

    private func prepareAudioSessionIfNeeded() {
        guard microphoneAuthorization == .authorized else { return }
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: [])
        } catch {
            return
        }
    }

    private func addAudioInputIfNeeded() {
        guard microphoneAuthorization == .authorized else { return }
        prepareAudioSessionIfNeeded()
        let hasAudio = session.inputs.contains { ($0 as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true }
        guard !hasAudio,
              let audio = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audio) else { return }

        session.beginConfiguration()
        if session.canAddInput(audioInput) { session.addInput(audioInput) }
        session.commitConfiguration()
    }

    // MARK: - Start/Stop (async)

    func start() async {
        if cameraAuthorization != .authorized {
            if cameraAuthorization == .notDetermined {
                await ensurePermissionsAndConfigureIfNeeded()
                if cameraAuthorization != .authorized {
                    return
                }
            } else {
                return
            }
        } else if !didConfigure {
            await MainActor.run { self.configureSessionIfNeeded() }
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { cont.resume(); return }

                if self.microphoneAuthorization == .authorized {
                    self.addAudioInputIfNeeded()
                }

                if self.session.isRunning {
                    Task { @MainActor in
                        self.isRunning = true
                        self.sessionState = .running
                        cont.resume()
                    }
                    return
                }

                self.session.startRunning()
                let running = self.session.isRunning
                Task { @MainActor in
                    self.isRunning = running
                    self.sessionState = running ? .running : .idle
                    cont.resume()
                }
            }
        }
    }

    func stop() {
        if !session.isRunning {
            Task { @MainActor in
                self.isRunning = false
                if self.cameraAuthorization == .authorized {
                    self.sessionState = .idle
                }
            }
            return
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.stopRunning()
            Task { @MainActor in
                self.isRunning = false
                self.sessionState = .idle
            }
        }
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let newPosition: AVCaptureDevice.Position = (self.isUsingFrontCamera ? .back : .front)

            guard let newDevice = self.bestCamera(position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                return
            }

            self.session.beginConfiguration()
            if let current = self.videoDeviceInput {
                self.session.removeInput(current)
            }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoDeviceInput = newInput
                Task { @MainActor in
                    self.isUsingFrontCamera = (newPosition == .front)
                }
            }
            self.session.commitConfiguration()

            // Re-apply torch state if toggled on and the new device supports it
            if self.flashMode == .on {
                self.sessionQueue.async { [weak self] in
                    self?.setTorch(on: true)
                }
            }
        }
    }

    // MARK: - Photo/Video

    func takePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true

        // Apply flash mode if supported by the current device
        if let device = videoDeviceInput?.device, device.isFlashAvailable {
            settings.flashMode = flashMode
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func startRecording() {
        guard !movieOutput.isRecording else { return }

        if microphoneAuthorization == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    self?.microphoneAuthorization = AVCaptureDevice.authorizationStatus(for: .audio)
                    if granted {
                        self?.sessionQueue.async { [weak self] in
                            self?.addAudioInputIfNeeded()
                        }
                    }
                }
            }
        } else if microphoneAuthorization == .authorized {
            sessionQueue.async { [weak self] in
                self?.addAudioInputIfNeeded()
            }
        }

        // Keep torch on during video if flashMode == .on and device supports it
        if flashMode == .on {
            sessionQueue.async { [weak self] in
                self?.setTorch(on: true)
            }
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")
        movieOutput.startRecording(to: tempURL, recordingDelegate: self)
        Task { @MainActor in
            self.isRecording = true
        }
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
        // If we enabled torch for recording, you may want to keep it on if user left flash on.
        // We’ll keep torch state as-is to match the toggle UI expectation.
        Task { @MainActor in
            self.isRecording = false
        }
    }

    // MARK: - Flash/Torch control

    func toggleFlash() {
        flashMode = (flashMode == .on ? .off : .on)
        let shouldTorch = (flashMode == .on)
        sessionQueue.async { [weak self] in
            self?.setTorch(on: shouldTorch)
        }
    }

    func setTorch(on: Bool) {
        guard let device = videoDeviceInput?.device,
              device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            if on {
                if device.isTorchModeSupported(.on) {
                    try? device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                }
            } else {
                if device.isTorchModeSupported(.off) {
                    device.torchMode = .off
                }
            }
            device.unlockForConfiguration()
        } catch {
            // Ignore torch errors; not critical
        }
    }

    // MARK: - Device selection

    private func bestCamera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera,
            .builtInDualCamera,
            .builtInTripleCamera,
            .builtInDualWideCamera,
            .builtInTrueDepthCamera
        ]
        let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: position)
        if let device = discovery.devices.first { return device }
        return AVCaptureDevice.default(for: .video)
    }

    private func defaultCamera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return device
        }
        return AVCaptureDevice.default(for: .video)
    }
}

extension CameraSession: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            print("CameraSession: photo capture error \(error?.localizedDescription ?? "-")")
            return
        }
        Task { @MainActor in
            self.lastPhoto = image
            self.lastVideoURL = nil
        }
    }
}

extension CameraSession: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(_ output: AVCaptureFileOutput,
                                didFinishRecordingTo outputFileURL: URL,
                                from connections: [AVCaptureConnection],
                                error: Error?) {
        if let error = error {
            print("CameraSession: recording error \(error.localizedDescription)")
            return
        }
        Task { @MainActor in
            self.lastVideoURL = outputFileURL
            self.lastPhoto = nil
            self.isRecording = false
        }
    }
}
