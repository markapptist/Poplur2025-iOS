import Foundation
import UIKit
import AVFoundation
import SnapCameraKit

@MainActor
final class CameraKitController: NSObject, ObservableObject {
    // Published outputs to keep your UI/UploadBridge working the same way
    @Published var lastPhoto: UIImage?
    @Published var lastVideoURL: URL?
    @Published var isRecording: Bool = false
    @Published var isUsingFrontCamera: Bool = false
    @Published var mode: CaptureMode = .video
    @Published var flashOn: Bool = false

    // Camera Kit components
    private var cameraController: CKCameraController?
    private var previewView: CKPreviewView?

    // Storage for temporary video file when recording
    private var activeRecordingURL: URL?

    // MARK: - Public API

    func makePreviewView() -> UIView {
        if let pv = previewView { return pv }
        let pv = CKPreviewView()
        pv.videoGravity = .resizeAspectFill
        previewView = pv
        return pv
    }

    func start() async {
        if cameraController == nil {
            await configureIfNeeded()
        }
        do {
            try await cameraController?.startRunning()
        } catch {
            print("[CameraKit] startRunning error: \(error.localizedDescription)")
        }
    }

    func stop() {
        Task {
            do { try await cameraController?.stopRunning() }
            catch { print("[CameraKit] stopRunning error: \(error.localizedDescription)") }
        }
    }

    func switchCamera() {
        Task {
            guard let cameraController else { return }
            do {
                try await cameraController.flipCamera()
                let current = await cameraController.currentPosition
                await MainActor.run {
                    self.isUsingFrontCamera = (current == .front)
                }
            } catch {
                print("[CameraKit] flipCamera error: \(error.localizedDescription)")
            }
        }
    }

    func setTorch(on: Bool) {
        Task {
            guard let cameraController else { return }
            do {
                try await cameraController.setTorchEnabled(on)
                await MainActor.run { self.flashOn = on }
            } catch {
                print("[CameraKit] setTorchEnabled error: \(error.localizedDescription)")
            }
        }
    }

    func takePhoto() {
        Task {
            guard let cameraController else { return }
            do {
                let photo = try await cameraController.capturePhoto()
                await MainActor.run {
                    self.lastPhoto = photo.image
                    self.lastVideoURL = nil
                }
            } catch {
                print("[CameraKit] capturePhoto error: \(error.localizedDescription)")
            }
        }
    }

    func startRecording() {
        Task {
            guard let cameraController else { return }
            do {
                // Create temp .mov file URL
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
                try await cameraController.startRecording(to: url)
                await MainActor.run {
                    self.isRecording = true
                    self.activeRecordingURL = url
                }
            } catch {
                print("[CameraKit] startRecording error: \(error.localizedDescription)")
            }
        }
    }

    func stopRecording() {
        Task {
            guard let cameraController else { return }
            do {
                try await cameraController.stopRecording()
                let url = await MainActor.run { self.activeRecordingURL }
                await MainActor.run {
                    self.isRecording = false
                    self.lastVideoURL = url
                    self.lastPhoto = nil
                    self.activeRecordingURL = nil
                }
            } catch {
                print("[CameraKit] stopRecording error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private

    private func configureIfNeeded() async {
        guard cameraController == nil else { return }

        // Initialize CameraKit with default configuration for basic camera
        let config = CKConfiguration() // For basic camera use; lenses not configured
        let controller = CKCameraController(configuration: config)

        // Attach preview view
        if let pv = previewView {
            controller.setPreviewView(pv)
        } else {
            let pv = CKPreviewView()
            pv.videoGravity = .resizeAspectFill
            previewView = pv
            controller.setPreviewView(pv)
        }

        // Default to back camera
        await controller.setCameraPosition(.back)
        self.isUsingFrontCamera = false

        // Audio session is managed internally; no external AVAudioSession setup required for basic capture
        self.cameraController = controller
    }
}

private extension CKCapturedPhoto {
    var image: UIImage {
        if let ui = uiImage { return ui }
        if let data = jpegData { return UIImage(data: data) ?? UIImage() }
        return UIImage()
    }
}

