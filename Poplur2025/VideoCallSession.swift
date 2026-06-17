import AVFoundation
import SwiftUI

@MainActor
final class VideoCallSession: ObservableObject {
    @Published private(set) var isMuted = false
    @Published private(set) var isFrontCamera = true
    @Published private(set) var cameraAuthorized = false

    let captureSession = AVCaptureSession()

    private var currentInput: AVCaptureDeviceInput?

    func requestAndStart() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            cameraAuthorized = true
        case .notDetermined:
            cameraAuthorized = await AVCaptureDevice.requestAccess(for: .video)
        default:
            cameraAuthorized = false
        }
        guard cameraAuthorized else { return }
        await startSession(front: true)
    }

    func stop() {
        Task.detached { [captureSession] in
            captureSession.stopRunning()
        }
    }

    func toggleMute() {
        isMuted.toggle()
    }

    func flipCamera() {
        isFrontCamera.toggle()
        Task { await startSession(front: isFrontCamera) }
    }

    private func startSession(front: Bool) async {
        let position: AVCaptureDevice.Position = front ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else { return }

        await MainActor.run {
            captureSession.beginConfiguration()
            if let old = currentInput { captureSession.removeInput(old) }
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                currentInput = input
            }
            captureSession.commitConfiguration()
        }

        if !captureSession.isRunning {
            Task.detached { [captureSession] in
                captureSession.startRunning()
            }
        }
    }
}
