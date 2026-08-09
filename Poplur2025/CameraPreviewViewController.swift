import UIKit
import AVFoundation

final class CameraPreviewViewController: UIViewController {
    // MARK: - Preview layer and camera controller placeholders
    /// Layer used to display camera preview content.
    var displayLayer: AVSampleBufferDisplayLayer?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var singleTapRecognizer: UITapGestureRecognizer?
    private var isARFilterTrayVisible = false
    private var activeARFilterRawValue = "None"
    private var wantsFilteredPreview = false
    private var hasFilteredFrame = false

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
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
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
        forcePreviewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.clipsToBounds = false

        // Base preview layer (raw camera) as fallback to avoid black screen
        if previewLayer == nil {
            // Try to find an AVCaptureSession from any known parent or responder chain if needed.
            // Prefer to attach later externally if your controller manages the session.
            // Here we create a layer without a session; the owning controller should set the session on it later.
            let base = AVCaptureVideoPreviewLayer()
            base.videoGravity = .resizeAspectFill

            // Set preview layer connection to portrait
            if let connection = base.connection {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
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
            layer.opacity = 0.0
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

        // Keep the raw camera layer visible until an AR filter is actively selected.
        displayLayer?.opacity = 0.0

        installCameraGestures()
        
        NotificationCenter.default.addObserver(forName: Notification.Name("CubeInteractionDisabled"), object: nil, queue: .main) { [weak self] _ in
            self?.singleTapRecognizer?.isEnabled = false
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("CubeInteractionEnabled"), object: nil, queue: .main) { [weak self] _ in
            self?.singleTapRecognizer?.isEnabled = true
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePreviewGeometryChanged),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePreviewGeometryChanged),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePreviewGeometryChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleARFiltersStateChanged(_:)),
            name: Notification.Name("ARFiltersStateChanged"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleARFilterChanged(_:)),
            name: Notification.Name("ARFilterChanged"),
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        forcePreviewLayout()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        forcePreviewLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPreviewLayers()
    }

    public func forcePreviewLayout() {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        layoutPreviewLayers()
    }

    @objc private func handlePreviewGeometryChanged() {
        forcePreviewLayout()
    }

    @objc private func handleARFiltersStateChanged(_ notification: Notification) {
        let isShown = notification.userInfo?["isShown"] as? Bool ?? false
        isARFilterTrayVisible = isShown
        if !isShown {
            activeARFilterRawValue = "None"
        }
        updateFilteredPreviewVisibility()
    }

    @objc private func handleARFilterChanged(_ notification: Notification) {
        let nextFilter = (notification.userInfo?["filter"] as? String) ?? "None"
        if nextFilter != activeARFilterRawValue {
            hasFilteredFrame = false
            displayLayer?.flushAndRemoveImage()
        }
        activeARFilterRawValue = nextFilter
        updateFilteredPreviewVisibility()
    }

    private func updateFilteredPreviewVisibility() {
        let hasActiveFilter = activeARFilterRawValue.caseInsensitiveCompare("None") != .orderedSame
        setFilteredPreviewVisible(isARFilterTrayVisible && hasActiveFilter)
    }

    private func setFilteredPreviewVisible(_ visible: Bool) {
        wantsFilteredPreview = visible
        if !visible {
            hasFilteredFrame = false
            displayLayer?.flushAndRemoveImage()
        }
        applyPreviewLayerVisibility()
    }

    public func markFilteredFrameReady() {
        guard wantsFilteredPreview else { return }
        hasFilteredFrame = true
        applyPreviewLayerVisibility()
    }

    private func applyPreviewLayerVisibility() {
        let showFiltered = wantsFilteredPreview && hasFilteredFrame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.opacity = showFiltered ? 0.0 : 1.0
        displayLayer?.opacity = showFiltered ? 1.0 : 0.0
        CATransaction.commit()
    }

    private func layoutPreviewLayers() {
        let frame = fullScreenPreviewFrame()

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if let base = previewLayer {
            base.frame = frame
            base.videoGravity = .resizeAspectFill
        }
        if let overlay = displayLayer {
            overlay.frame = frame
            overlay.videoGravity = .resizeAspectFill
        }

        CATransaction.commit()
    }

    private func fullScreenPreviewFrame() -> CGRect {
        guard let window = view.window else {
            return view.bounds
        }

        let windowBoundsInView = view.convert(window.bounds, from: window)
        return view.bounds.union(windowBoundsInView)
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

        // Photo capture is intentionally handled only by CubeTabView.
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
        NotificationCenter.default.post(name: Notification.Name("cameraCubeTabViewTapped"), object: nil)
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
        if status == .failed {
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
