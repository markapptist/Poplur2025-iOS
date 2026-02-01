import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

class CameraKitController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, RecordPreviewViewControllerProviding, PreviewViewControllerProviding {
    // MARK: - Properties
    let sessionQueue = DispatchQueue(label: "camera.session.queue")
    let captureSession = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    
    // Snap Kit / Record-specific camera VC. Set this from your Snap setup code.
    var recordPreviewViewController: UIViewController?

    // Optional generic preview VC fallback if needed elsewhere.
    var previewViewController: UIViewController?
    
    @Published var isReady: Bool = false
    @Published var hasRecordPreview: Bool = false

    // MARK: - SnapKit Integration
    @MainActor
    func installSnapRecordPreview(_ viewController: UIViewController) {
        self.recordPreviewViewController = viewController
        self.hasRecordPreview = true
        // If we haven't started yet, mark ready to allow UI to render immediately
        if !self.isReady {
            self.isReady = true
        }
    }

    // MARK: - Photo Capture
    func takePhoto() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            // Ensure session is running
            if !self.captureSession.isRunning {
                print("[CK][Photo] Session not running — attempting to start before capture")
                self.captureSession.startRunning()
            }

            // Ensure photoOutput is attached
            if !self.captureSession.outputs.contains(self.photoOutput) {
                print("[CK][Photo] photoOutput missing — attempting to attach")
                self.captureSession.beginConfiguration()
                if self.captureSession.canAddOutput(self.photoOutput) {
                    self.captureSession.addOutput(self.photoOutput)
                    self.photoOutput.isHighResolutionCaptureEnabled = true
                } else {
                    print("[CK][Photo] Cannot add photoOutput even after attempt")
                }
                self.captureSession.commitConfiguration()
            }

            // Verify running and connection
            guard self.captureSession.isRunning else {
                print("[CK][Photo] Abort: session still not running")
                return
            }

            // Fetch the video connection for photoOutput
            var connection = self.photoOutput.connection(with: .video)
            if connection == nil || (connection?.isEnabled == false) {
                print("[CK][Photo] No active/enabled video connection — attempting to reconfigure")
                self.captureSession.beginConfiguration()
                // Try to re-add the output to refresh connections
                if self.captureSession.outputs.contains(self.photoOutput) {
                    self.captureSession.removeOutput(self.photoOutput)
                }
                if self.captureSession.canAddOutput(self.photoOutput) {
                    self.captureSession.addOutput(self.photoOutput)
                    self.photoOutput.isHighResolutionCaptureEnabled = true
                }
                self.captureSession.commitConfiguration()
                // Re-fetch connection
                connection = self.photoOutput.connection(with: .video)
            }

            guard let videoConnection = connection, videoConnection.isEnabled else {
                print("[CK][Photo] Abort: No active and enabled video connection after reconfigure")
                return
            }

            // Optionally align orientation if supported
            if videoConnection.isVideoOrientationSupported {
                videoConnection.videoOrientation = .portrait
            }

            let settings = AVCapturePhotoSettings()
            settings.isHighResolutionPhotoEnabled = true
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("[CK][Photo] Processing error: \(error)")
        } else {
            print("[CK][Photo] Photo captured with \(photo.fileDataRepresentation()?.count ?? 0) bytes")
        }
    }
    
    @MainActor
    func start() async {
        // Start the capture session on the dedicated queue, then mark ready on main.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { cont.resume(); return }
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }
                cont.resume()
            }
        }
        self.isReady = self.hasRecordPreview || self.captureSession.isRunning
    }

    @MainActor
    func stop() {
        // Stop session asynchronously; update readiness immediately for UI.
        self.isReady = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }
        }
    }
}

