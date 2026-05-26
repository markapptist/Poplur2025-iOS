import UIKit
import AVFoundation

final class CameraPreviewViewController: UIViewController {
    // MARK: - Preview layer and camera controller placeholders
    /// Layer used to display camera preview content.
    var displayLayer: AVSampleBufferDisplayLayer?
    private var previewLayer: AVCaptureVideoPreviewLayer?

    /// Expose the AR display layer for external configuration (e.g., CameraKitController)
    public func getARDisplayLayer() -> AVSampleBufferDisplayLayer? {
        return displayLayer
    }

    // Attach an AVCaptureSession to the base preview layer so raw camera shows immediately
    public func setCaptureSession(_ session: AVCaptureSession) {
        if let base = previewLayer {
            base.session = session
        } else {
            let base = AVCaptureVideoPreviewLayer(session: session)
            base.videoGravity = .resizeAspectFill
            
            // Set preview layer connection to portrait
            if let connection = base.connection {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            
            view.layer.insertSublayer(base, at: 0)
            previewLayer = base
            // Keep overlay above base if present
            if let overlay = displayLayer {
                overlay.removeFromSuperlayer()
                view.layer.insertSublayer(overlay, above: base)
            }
        }
        // Ensure frames are laid out
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // Base preview layer (raw camera) as fallback to avoid black screen
        if previewLayer == nil {
            // Try to find an AVCaptureSession from any known parent or responder chain if needed.
            // Prefer to attach later externally if your controller manages the session.
            // Here we create a layer without a session; the owning controller should set the session on it later.
            let base = AVCaptureVideoPreviewLayer()
            base.videoGravity = .resizeAspectFill
            
            // Set preview layer connection to portrait
            if let connection = base.connection {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
            }
            
            view.layer.insertSublayer(base, at: 0)
            previewLayer = base
        } else if let base = previewLayer, base.superlayer == nil {
            view.layer.insertSublayer(base, at: 0)
        }

        // Ensure display layer exists and is installed in the view hierarchy
        if displayLayer == nil {
            let layer = AVSampleBufferDisplayLayer()
            layer.videoGravity = .resizeAspectFill
            layer.opacity = 1.0
            view.layer.insertSublayer(layer, at: 0)
            displayLayer = layer
        } else if let layer = displayLayer, layer.superlayer == nil {
            // If provided externally but not attached yet, attach it
            view.layer.insertSublayer(layer, at: 0)
        }

        if let base = previewLayer, let overlay = displayLayer, overlay.superlayer === view.layer {
            // Ensure overlay is above base preview layer
            overlay.removeFromSuperlayer()
            view.layer.insertSublayer(overlay, above: base)
        }
        
        if let overlay = displayLayer {
            print("[PreviewVC] AR displayLayer installed, frame: \(overlay.frame), opacity: \(overlay.opacity)")
        }

        // Temporarily hide displayLayer to validate base preview
        displayLayer?.opacity = 1.0

        installCameraGestures()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let bounds = view.bounds
        if let base = previewLayer {
            base.frame = bounds
            base.videoGravity = .resizeAspectFill
        }
        if let overlay = displayLayer {
            overlay.frame = bounds
            overlay.videoGravity = .resizeAspectFill
        }

        CATransaction.commit()

        // TEMP sanity log to confirm frames match bounds
        print("[PreviewVC] bounds: \(bounds), preview: \(String(describing: previewLayer?.frame)), display: \(String(describing: displayLayer?.frame))")
    }

    // MARK: - Gesture recognizers for camera controls
    private func installCameraGestures() {
        // Swipe up: Torch ON
        let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeUp(_:)))
        swipeUp.direction = .up
        swipeUp.cancelsTouchesInView = false
        view.addGestureRecognizer(swipeUp)

        // Swipe down: Torch OFF
        let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeDown(_:)))
        swipeDown.direction = .down
        swipeDown.cancelsTouchesInView = false
        view.addGestureRecognizer(swipeDown)

        // Double tap: Flip camera
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        view.addGestureRecognizer(doubleTap)

        // Long press: Toggle AR filters
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.cancelsTouchesInView = false
        view.addGestureRecognizer(longPress)

        // Single tap: Take picture (cube tap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.numberOfTapsRequired = 1
        singleTap.cancelsTouchesInView = false
        // Ensure single tap waits for double tap to fail to avoid conflicts
        singleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(singleTap)
    }

    @objc private func handleSwipeUp(_ gesture: UISwipeGestureRecognizer) {
        // Turn torch ON via notification; controller observes and applies
        NotificationCenter.default.post(name: Notification.Name("CameraToggleTorchOn"), object: nil)
    }

    @objc private func handleSwipeDown(_ gesture: UISwipeGestureRecognizer) {
        // Turn torch OFF
        NotificationCenter.default.post(name: Notification.Name("CameraToggleTorchOff"), object: nil)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        // Flip camera
        NotificationCenter.default.post(name: Notification.Name("FlipCameraRequested"), object: nil)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        // Toggle AR filters UI
        NotificationCenter.default.post(name: Notification.Name("ToggleARFilters"), object: nil)
    }

    @objc private func handleSingleTap(_ gesture: UITapGestureRecognizer) {
        NotificationCenter.default.post(name: Notification.Name("cubeTabViewTapped"), object: nil)
    }

    /// Minimal protocol to satisfy `currentCameraPosition` usage. Replace with your real controller if available.
    private protocol CameraPositioning {
        var currentCameraPosition: AVCaptureDevice.Position { get }
    }
    
    /// Reference to the camera controller; conforms to `CameraPositioning`.
    private var cameraController: CameraPositioning?

    // ... other properties and methods ...

    // Immediate visual feedback when recording starts/stops
    /// Apply the appropriate affine transform on `displayLayer` based on current camera position.
    private func applyDisplayLayerTransformForCurrentCamera() {
        guard let _ = displayLayer else { return }
        // Temporarily disabled complex transforms to avoid shrinking/rotation issues.
        // Mirroring for front camera is handled in CameraKitController when enqueuing frames.
    }

    private func recoverDisplayLayerIfNeeded() {
        guard let dl = displayLayer else { return }
        let status = dl.status
        if status == .failed || status == .unknown {
            print("⚠️ [CameraPreviewVC] Display layer status \(status.rawValue) — flushing to recover")
            dl.flushAndRemoveImage()
        }
    }

    func animateRecordingUI(started: Bool) {
        // ... method implementation ...
    }

    // ... other methods ...
}

// Note: the top-level duplicate of applyDisplayLayerTransformForCurrentCamera has been removed.

