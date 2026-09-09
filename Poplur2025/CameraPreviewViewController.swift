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
    private var filteredFramePresentationGeneration: UInt64 = 0
    private var parkedPreviewCanResume = false
    private var parkedPreviewImageView: UIImageView?
    private var resumePreviewButton: UIButton?
    private var notificationObservers: [NSObjectProtocol] = []
    var onParkedPreviewTap: (() -> Void)?

    /// Expose the AR display layer for external configuration (e.g., CameraKitController)
    public func getARDisplayLayer() -> AVSampleBufferDisplayLayer? {
        return displayLayer
    }

    /// A face rectangle from the ISP, in 0..1 of THIS VIEW, top-left origin.
    ///
    /// `transformedMetadataObject(for:)` is the right tool for an
    /// AVMetadataObject specifically: the preview layer is the only object that
    /// knows its own `.resizeAspectFill` crop, the rotation applied to its
    /// connection, and the front camera's automatic mirroring, and it applies
    /// all three. (The Vision path must NOT use it — those boxes are already
    /// normalised and already mirrored, so it would transform them twice.)
    ///
    /// Main-thread only: CALayer is not thread-safe, and a conversion made off
    /// the main queue returns numbers that look plausible and are wrong.
    @MainActor
    func normalizedPreviewRect(for metadataObject: AVMetadataObject) -> CGRect? {
        guard let layer = previewLayer, layer.connection != nil else { return nil }
        let bounds = layer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        guard let transformed = layer.transformedMetadataObject(for: metadataObject) else { return nil }
        let rect = transformed.bounds
        guard rect.width > 0, rect.height > 0,
              rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite else { return nil }
        return CGRect(
            x: (rect.minX - bounds.minX) / bounds.width,
            y: (rect.minY - bounds.minY) / bounds.height,
            width: rect.width / bounds.width,
            height: rect.height / bounds.height,
        )
    }

    // Attach an AVCaptureSession to the base preview layer so raw camera shows immediately
    public func setCaptureSession(_ session: AVCaptureSession) {
        // LOAD THE VIEW FIRST. This used to test `previewLayer` before the view
        // existed, so on the first call it took the else branch, built a
        // session-ful preview layer, and then touched `view` — which ran
        // viewDidLoad, which saw `previewLayer` still nil and built a SECOND,
        // session-less AVCaptureVideoPreviewLayer plus the AR display layer
        // above it. The session-ful layer was then inserted underneath both,
        // leaving that empty second preview layer sitting directly ON TOP of
        // the AR display layer for the life of the screen, and leaving
        // applyPreviewLayerVisibility() hiding a layer that was not the only
        // one in front of the filtered output.
        loadViewIfNeeded()
        guard let base = previewLayer else { return }
        base.session = session
        base.videoGravity = .resizeAspectFill

        // Set preview layer connection to portrait. viewDidLoad cannot do this
        // — a preview layer has no connection until it has a session — so it
        // belongs here, after the session is attached.
        if let connection = base.connection,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        // Keep the AR overlay above the base preview.
        if let overlay = displayLayer {
            overlay.removeFromSuperlayer()
            view.layer.insertSublayer(overlay, above: base)
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

        installParkedPreviewImageView()
        installColdBudgetResumeAffordance()
        installCameraGestures()
        
        notificationObservers.append(NotificationCenter.default.addObserver(forName: Notification.Name("CubeInteractionDisabled"), object: nil, queue: .main) { [weak self] _ in
            self?.singleTapRecognizer?.isEnabled = false
        })
        notificationObservers.append(NotificationCenter.default.addObserver(forName: Notification.Name("CubeInteractionEnabled"), object: nil, queue: .main) { [weak self] _ in
            self?.singleTapRecognizer?.isEnabled = true
        })

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
        notificationObservers.forEach(NotificationCenter.default.removeObserver)
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
            filteredFramePresentationGeneration &+= 1
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
            filteredFramePresentationGeneration &+= 1
            hasFilteredFrame = false
            displayLayer?.flushAndRemoveImage()
        }
        applyPreviewLayerVisibility()
    }

    public func markFilteredFrameReady(holdDuration: TimeInterval = 0.18) {
        guard wantsFilteredPreview else { return }
        filteredFramePresentationGeneration &+= 1
        let generation = filteredFramePresentationGeneration
        let boundedHoldDuration = max(0.18, min(holdDuration, 2.0))
        hasFilteredFrame = true
        applyPreviewLayerVisibility()
        // Each new filtered frame supersedes the previous expiry. The AR lane
        // therefore remains visually continuous at its bounded sampled rate,
        // instead of flashing raw preview between samples, while a stalled
        // filter still falls back to the live hardware preview within 2s.
        DispatchQueue.main.asyncAfter(deadline: .now() + boundedHoldDuration) { [weak self] in
            guard let self,
                  self.filteredFramePresentationGeneration == generation,
                  self.wantsFilteredPreview else { return }
            self.hasFilteredFrame = false
            self.displayLayer?.flushAndRemoveImage()
            self.applyPreviewLayerVisibility()
        }
    }

    private var lastLoggedShowFiltered: Bool?
    private func applyPreviewLayerVisibility() {
        let showFiltered = wantsFilteredPreview && hasFilteredFrame
        if lastLoggedShowFiltered != showFiltered {
            lastLoggedShowFiltered = showFiltered
            PoplurDiagLog.append("arfilter: preview showFiltered=\(showFiltered) wants=\(wantsFilteredPreview) hasFrame=\(hasFilteredFrame) trayVisible=\(isARFilterTrayVisible) filter=\(activeARFilterRawValue)")
        }
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

    public func setColdBudgetResumeAffordanceVisible(_ visible: Bool) {
        loadViewIfNeeded()
        parkedPreviewCanResume = visible
        resumePreviewButton?.isHidden = !visible
    }

    /// A single retained frame replaces the live AVCapture preview after the
    /// hard camera budget expires. It lets the session release every input and
    /// output without turning the Camera surface into an unexplained black box.
    public func setParkedPreviewImage(_ image: UIImage?) {
        loadViewIfNeeded()
        parkedPreviewImageView?.image = image
        parkedPreviewImageView?.isHidden = (image == nil)
    }

    private func installParkedPreviewImageView() {
        guard parkedPreviewImageView == nil else { return }
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.isUserInteractionEnabled = false
        imageView.isHidden = true
        view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        parkedPreviewImageView = imageView
    }

    private func installColdBudgetResumeAffordance() {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("Tap to resume camera", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = 0.8
        button.layer.shadowRadius = 3
        button.layer.shadowOffset = .zero
        button.backgroundColor = .clear
        button.isHidden = true
        button.accessibilityHint = "Restarts the camera after it was paused"
        button.addTarget(self, action: #selector(handleParkedPreviewTap), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        resumePreviewButton = button
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

        let singleTap = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap(_:)))
        singleTap.cancelsTouchesInView = false
        singleTap.require(toFail: doubleTap)
        view.addGestureRecognizer(singleTap)
        singleTapRecognizer = singleTap

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
        guard parkedPreviewCanResume else { return }
        onParkedPreviewTap?()
    }

    @objc private func handleParkedPreviewTap() {
        guard parkedPreviewCanResume else { return }
        onParkedPreviewTap?()
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
