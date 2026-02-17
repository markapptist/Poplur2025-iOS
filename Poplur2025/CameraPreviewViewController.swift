import UIKit
import AVFoundation
import SwiftUI

extension Notification.Name {
    static let cubeTabViewTapped = Notification.Name("CubeTabViewTappedNotification")
}

/// Hosts an AVCaptureVideoPreviewLayer for a provided AVCaptureSession.
final class CameraPreviewViewController: UIViewController {

    // MARK: - Properties
    private let session: AVCaptureSession
    private let previewLayer: AVCaptureVideoPreviewLayer

    private let sessionQueue = DispatchQueue(label: "camera.session.queue", qos: .userInitiated)

    /// Photo capture callback
    var onShutter: (() -> Void)?

    /// Video recording callbacks
    var onStartVideo: (() -> Void)?
    var onStopVideo: (() -> Void)?

    /// Swipe navigation callbacks (optional)
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?
    
    /// Radius value displayed/edited by the radius bar (in meters)
    var radius: Double = 250 {
        didSet { onRadiusChanged?(radius) }
    }
    /// Callback when radius changes interactively
    var onRadiusChanged: ((Double) -> Void)?
    
    private var radiusHostController: UIHostingController<CameraRadiusBar>?

    private let torchButton = UIButton(type: .system)
    private let flipButton = UIButton(type: .system)

    private var isTorchOn: Bool = false
    
    private let loadingOverlay = UIActivityIndicatorView(style: .large)
    private var overlayAutoHideWorkItem: DispatchWorkItem?

    // Debug utilities
    private let debugEnabled: Bool = true
    private let debugBorderLayer: CALayer = {
        let l = CALayer()
        l.borderColor = UIColor.systemGreen.withAlphaComponent(0.9).cgColor
        l.borderWidth = 2
        l.backgroundColor = UIColor.clear.cgColor
        l.isHidden = false
        return l
    }()

    private var appDidBecomeActiveObserver: NSObjectProtocol?
    private var appWillResignActiveObserver: NSObjectProtocol?
    private var isAppActive: Bool = true

    /// If true, this controller will start/stop the capture session automatically on appear/disappear.
    /// Leave true unless your owner manages the session lifecycle explicitly.
    var autoManageSession: Bool = true

    // MARK: - Init
    init(session: AVCaptureSession) {
        self.session = session
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(nibName: nil, bundle: nil)
        self.previewLayer.videoGravity = .resizeAspectFill
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.layer.addSublayer(previewLayer)
        previewLayer.isHidden = false
        previewLayer.zPosition = -1
        
        if debugEnabled {
            view.layer.addSublayer(debugBorderLayer)
        }
        
        installRadiusBar()

        setupButtons()
        setupGestures()
        updateTorchAvailability()
        
        // Start the session as early as possible to avoid cold-start delay
        if autoManageSession && !session.isRunning {
            sessionQueue.async { [weak self] in
                guard let self = self else { return }
                self.session.startRunning()
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.prepareUIForCubeLoad()
                    if let connection = self.previewLayer.connection, connection.isEnabled {
                        self.loadingOverlay.stopAnimating()
                        self.overlayAutoHideWorkItem?.cancel()
                        self.overlayAutoHideWorkItem = nil
                    }
                }
            }
        }
        
        // Lightweight spinner overlay for first frame
        loadingOverlay.translatesAutoresizingMaskIntoConstraints = false
        loadingOverlay.hidesWhenStopped = true
        view.addSubview(loadingOverlay)
        NSLayoutConstraint.activate([
            loadingOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingOverlay.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        loadingOverlay.startAnimating()
        // Auto-hide as a fallback after 0.35s
        let hideWork = DispatchWorkItem { [weak self] in self?.loadingOverlay.stopAnimating() }
        overlayAutoHideWorkItem = hideWork
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: hideWork)
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleCubeTappedNotification), name: .cubeTabViewTapped, object: nil)
        
        appDidBecomeActiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.isAppActive = true
            // If the session isn't running (or was interrupted), start it and then re-sync UI
            if self.autoManageSession && !self.session.isRunning {
                self.sessionQueue.async { [weak self] in
                    guard let self = self else { return }
                    self.session.startRunning()
                    DispatchQueue.main.async { [weak self] in
                        self?.prepareUIForCubeLoad()
                        self?.updateTorchAvailability()
                    }
                }
            } else {
                // Session already running; just re-sync UI
                self.prepareUIForCubeLoad()
                self.updateTorchAvailability()
            }
        }
        appWillResignActiveObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isAppActive = false
            // Ensure torch state reflects hardware; we don't force-on when app resigns
            self?.updateTorchAvailability()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = view.bounds
        CATransaction.commit()
        
        if debugEnabled {
            debugBorderLayer.frame = view.bounds
        }
        
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            if let orientation = view.window?.windowScene?.interfaceOrientation {
                switch orientation {
                case .portrait: connection.videoOrientation = .portrait
                case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
                case .landscapeLeft: connection.videoOrientation = .landscapeLeft
                case .landscapeRight: connection.videoOrientation = .landscapeRight
                default: break
                }
            }
        }
        
        updateTorchAvailability()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isAppActive = true
        updateTorchAvailability()
        
        previewLayer.isHidden = false
        prepareUIForCubeLoad()
        
        // Defer a second pass to the next runloop to catch first-attach-to-window cases
        DispatchQueue.main.async { [weak self] in
            self?.prepareUIForCubeLoad()
        }
        
        if autoManageSession && !session.isRunning {
            // Start as early as possible off the main thread to avoid blocking initial UI
            sessionQueue.async { [weak self] in
                self?.session.startRunning()
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.prepareUIForCubeLoad()
                }
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        print("[CameraPreviewVC] appeared; session running: \(session.isRunning), layer frame: \(previewLayer.frame)")
        if let connection = previewLayer.connection {
            print("[CameraPreviewVC] connection active: \(connection.isEnabled), videoOrientation: \(connection.videoOrientation.rawValue)")
        } else {
            print("[CameraPreviewVC] no preview connection")
        }
        prepareUIForCubeLoad()
        
        if session.isRunning, let connection = previewLayer.connection, connection.isEnabled {
            loadingOverlay.stopAnimating()
            overlayAutoHideWorkItem?.cancel()
            overlayAutoHideWorkItem = nil
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Reset torch UI to safe state; actual session control should be managed by owner
        isTorchOn = false
        torchButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        
        loadingOverlay.stopAnimating()
        overlayAutoHideWorkItem?.cancel()
        overlayAutoHideWorkItem = nil
        
        if autoManageSession && session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .cubeTabViewTapped, object: nil)
        if let obs = appDidBecomeActiveObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = appWillResignActiveObserver { NotificationCenter.default.removeObserver(obs) }
    }

    // MARK: - Public Trigger
    
    /// Ensure UI is fully initialized and in-sync when the cube loads
    /// Call this right after presenting/embedding this controller for immediate readiness.
    public func prepareUIForCubeLoad() {
        // Make sure layer is attached and visible
        previewLayer.isHidden = false
        // Ensure correct frame without animations
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = view.bounds
        CATransaction.commit()

        // Sync orientation if possible
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported,
           let orientation = view.window?.windowScene?.interfaceOrientation {
            switch orientation {
            case .portrait: connection.videoOrientation = .portrait
            case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
            case .landscapeLeft: connection.videoOrientation = .landscapeLeft
            case .landscapeRight: connection.videoOrientation = .landscapeRight
            default: break
            }
        }

        // Refresh dependent UI
        refreshRadiusBar()
        updateTorchAvailability()

        // Apply layout immediately
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    /// Programmatically trigger a photo capture
    func triggerShutter() {
        onShutter?()
    }
    
    /// Call this when the CubeTabView is pressed to take a photo.
    func cubePressed() {
        // Reuse the same shutter pathway
        onShutter?()
    }
    
    @objc private func handleCubeTappedNotification() {
        cubePressed()
    }

    /// Ask the owning coordinator/controller to present a preview after photo capture completes.
    /// Call this from your capture completion handler once you have the image data ready.
    var onRequestPreview: (() -> Void)?

    // MARK: - Setup
    private func setupButtons() {
        // Torch
        torchButton.translatesAutoresizingMaskIntoConstraints = false
        torchButton.backgroundColor = UIColor.white.withAlphaComponent(0.85)
        torchButton.tintColor = .black
        torchButton.layer.cornerRadius = 20
        torchButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        torchButton.addTarget(self, action: #selector(torchTapped), for: .touchUpInside)
        view.addSubview(torchButton)

        // Flip
        flipButton.translatesAutoresizingMaskIntoConstraints = false
        flipButton.backgroundColor = UIColor.white.withAlphaComponent(0.85)
        flipButton.tintColor = .black
        flipButton.layer.cornerRadius = 20
        flipButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera"), for: .normal)
        flipButton.addTarget(self, action: #selector(flipTapped), for: .touchUpInside)
        view.addSubview(flipButton)

        NSLayoutConstraint.activate([
            torchButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            torchButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            torchButton.widthAnchor.constraint(equalToConstant: 40),
            torchButton.heightAnchor.constraint(equalToConstant: 40),

            flipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            flipButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            flipButton.widthAnchor.constraint(equalToConstant: 40),
            flipButton.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    private func setupGestures() {
        // Long press = video record
        let longPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.25
        view.addGestureRecognizer(longPress)

        // Horizontal pan = swipe navigation
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
    }

    // MARK: - Gesture Handlers
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            // Immediate UI feedback
            animateRecordingUI(started: true)
            // Defer start to next runloop to avoid blocking UI
            DispatchQueue.main.async { [weak self] in
                self?.onStartVideo?()
            }
        case .ended, .cancelled, .failed:
            animateRecordingUI(started: false)
            DispatchQueue.main.async { [weak self] in
                self?.onStopVideo?()
            }
        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let threshold: CGFloat = 80

        if gesture.state == .ended, abs(translation.x) > abs(translation.y) {
            if translation.x <= -threshold {
                onSwipeLeft?()
            } else if translation.x >= threshold {
                onSwipeRight?()
            }
        }
    }

    // MARK: - Torch / Flip
    private func activeDevice() -> AVCaptureDevice? {
        (session.inputs.first as? AVCaptureDeviceInput)?.device
    }

    private func updateTorchAvailability() {
        guard let device = activeDevice() else {
            torchButton.isEnabled = false
            torchButton.alpha = 0.5
            isTorchOn = false
            torchButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
            return
        }

        let supported = device.hasTorch
        torchButton.isEnabled = supported
        torchButton.alpha = supported ? 1.0 : 0.5

        isTorchOn = device.isTorchActive
        let icon = isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"
        torchButton.setImage(UIImage(systemName: icon), for: .normal)
    }

    @objc private func torchTapped() {
        guard session.inputs.first != nil else { return }
        guard let device = activeDevice(), device.hasTorch else { return }

        do {
            try device.lockForConfiguration()
            if device.isTorchActive {
                device.torchMode = .off
                isTorchOn = false
            } else {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
                isTorchOn = true
            }
            device.unlockForConfiguration()
        } catch {
            print("[CameraPreviewVC] Torch error:", error)
            isTorchOn = false
        }

        let icon = isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"
        torchButton.setImage(UIImage(systemName: icon), for: .normal)
    }

    @objc private func flipTapped() {
        guard let currentInput = session.inputs.first as? AVCaptureDeviceInput else { return }

        let newPosition: AVCaptureDevice.Position =
            currentInput.device.position == .back ? .front : .back

        // Immediate UI feedback
        flipButton.isEnabled = false

        DispatchQueue.global(qos: .userInitiated).async {
            self.session.beginConfiguration()
            self.session.removeInput(currentInput)

            var didAdd = false
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
               let newInput = try? AVCaptureDeviceInput(device: device),
               self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                didAdd = true
            }

            if didAdd == false, self.session.canAddInput(currentInput) {
                self.session.addInput(currentInput)
            }

            self.session.commitConfiguration()

            DispatchQueue.main.async {
                // Front camera usually has no torch
                self.isTorchOn = false
                self.torchButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)

                self.refreshRadiusBar()
                self.updateTorchAvailability()
                self.flipButton.isEnabled = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.updateTorchAvailability()
                }
            }
        }
    }
    
    private func installRadiusBar() {
        let bar = CameraRadiusBar(initialRadius: radius) { [weak self] newValue in
            self?.radius = newValue
        }
        let host = UIHostingController(rootView: bar)
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.didMove(toParent: self)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            host.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -45),
            host.view.widthAnchor.constraint(equalToConstant: 60),
            host.view.heightAnchor.constraint(equalToConstant: 220)
        ])
        radiusHostController = host
    }
    
    private func refreshRadiusBar() {
        guard let host = radiusHostController else { return }
        host.rootView = CameraRadiusBar(initialRadius: radius) { [weak self] newValue in
            self?.radius = newValue
        }
    }
    
    // Immediate visual feedback when recording starts/stops
    private func animateRecordingUI(started: Bool) {
        let targetAlpha: CGFloat = started ? 0.6 : 1.0
        UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut]) {
            self.torchButton.alpha = targetAlpha
            self.flipButton.alpha = targetAlpha
        }
    }
}
// MARK: - SwiftUI bridge for interactive radius bar
private struct CameraRadiusBar: View {
    @State private var value: Double
    var onChange: (Double) -> Void
    
    init(initialRadius: Double, onChange: @escaping (Double) -> Void) {
        _value = State(initialValue: initialRadius)
        self.onChange = onChange
    }
    
    var body: some View {
        ZStack {
            IsometricRadiusBar(radius: $value)
                .onChange(of: value) { _, newVal in
                    onChange(newVal)
                }
        }
    }
}

