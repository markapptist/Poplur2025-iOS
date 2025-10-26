import AVFoundation
import UIKit

enum CaptureMode {
    case photo
    case video
}

@MainActor
final class CameraSession: NSObject, ObservableObject {
    @Published var isRunning = false
    @Published var lastPhoto: UIImage?
    @Published var lastVideoURL: URL?
    @Published var mode: CaptureMode = .video
    @Published var isRecording = false
    @Published var isUsingFrontCamera = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "CameraSession.sessionQueue")
    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let movieOutput = AVCaptureMovieFileOutput()

    override init() {
        super.init()
        configureSession()
    }

    func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        // Camera input
        guard let device = defaultCamera(position: .back) else {
            print("CameraSession: No camera device available")
            session.commitConfiguration()
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            print("CameraSession: Failed to create device input")
            session.commitConfiguration()
            return
        }
        guard session.canAddInput(input) else {
            print("CameraSession: Cannot add camera input to session")
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        videoDeviceInput = input
        isUsingFrontCamera = (device.position == .front)

        // Audio input for video
        if let audio = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audio),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        } else {
            // Not fatal for photo capture
            print("CameraSession: Audio input not added (OK for photos)")
        }

        // Photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
        } else {
            print("CameraSession: Cannot add photo output")
        }

        // Movie output
        if session.canAddOutput(movieOutput) {
            session.addOutput(movieOutput)
        } else {
            print("CameraSession: Cannot add movie output")
        }

        session.commitConfiguration()
    }

    func start() {
        guard !session.isRunning else { return }
        sessionQueue.async { [weak self] in
            self?.session.startRunning()
            Task { @MainActor in self?.isRunning = true }
        }
    }

    func stop() {
        guard session.isRunning else { return }
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            Task { @MainActor in self?.isRunning = false }
        }
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let newPosition: AVCaptureDevice.Position = (self.isUsingFrontCamera ? .back : .front)

            guard let newDevice = self.defaultCamera(position: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
                print("CameraSession: Failed to switch camera")
                return
            }

            self.session.beginConfiguration()
            if let current = self.videoDeviceInput {
                self.session.removeInput(current)
            }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.videoDeviceInput = newInput
                Task { @MainActor in self.isUsingFrontCamera = (newPosition == .front) }
            } else {
                print("CameraSession: Cannot add new camera input")
            }
            self.session.commitConfiguration()
        }
    }

    func takePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.isHighResolutionPhotoEnabled = true
        if videoDeviceInput?.device.isFlashAvailable == true {
            settings.flashMode = .off // Add a UI toggle if you want flash
        }
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func startRecording() {
        guard !movieOutput.isRecording else { return }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")
        movieOutput.startRecording(to: tempURL, recordingDelegate: self)
        isRecording = true
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
        isRecording = false
    }

    private func defaultCamera(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) {
            return device
        }
        // Fallback to any available
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
        }
    }
}
