import UIKit
import AVFoundation
import SwiftUI
import AudioToolbox

extension Notification.Name {
    static let cameraCubeTabViewTapped = Notification.Name("Camera_CubeTabViewTappedNotification")
    static let cameraCubeHoldBegan = Notification.Name("Camera_CubeHoldBegan")
    static let cameraCubeHoldEnded = Notification.Name("Camera_CubeHoldEnded")
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

    private var didRunInitialAppearanceSync = false

    // Recording helpers
    private var recordStartDate: Date?
    private var recordTimer: CADisplayLink?
    private let recordMaxDuration: TimeInterval = 10.0
    private var recordProgress: Double = 0.0 // 0...1

    // Simple vertical progress bar next to the radius bar
    private let recordProgressView: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor.systemRed.withAlphaComponent(0.9)
        v.layer.cornerRadius = 3
        v.isHidden = true
        return v
    }()

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
        // Insert preview layer at the bottom to avoid zPosition quirks
        previewLayer.isHidden = false
        view.layer.insertSublayer(previewLayer, at: 0)
        
        if debugEnabled {
            view.layer.addSublayer(debugBorderLayer)
        }
        
        installRadiusBar()

        // Install a simple recording progress bar next to the radius bar
        view.addSubview(recordProgressView)
        recordProgressView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            recordProgressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -80),
            recordProgressView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -45),
            recordProgressView.widthAnchor.constraint(equalToConstant: 6),
            recordProgressView.heightAnchor.constraint(equalToConstant: 0)
        ])

        setupButtons()
        setupGestures()
        updateTorchAvailability()
        
        print("[CameraPreviewVC] viewDidLoad window? \(self.view.window != nil), layer frame: \(self.previewLayer.frame)")
        
        // Start the session as early as possible to avoid cold-start delay
        if autoManageSession && !session.isRunning {
            sessionQueue.async { [weak self] in
                guard let self = self else { return }
                self.session.startRunning()
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.prepareUIForCubeLoad()
                }
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleCubeTappedNotification), name: .cameraCubeTabViewTapped, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCubeHoldBegan), name: .cameraCubeHoldBegan, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleCubeHoldEnded), name: .cameraCubeHoldEnded, object: nil)
        
        // Ensure initial layout/UI sync on first load
        view.setNeedsLayout()
        view.layoutIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.prepareUIForCubeLoad()
        }
        
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
        print("[CameraPreviewVC] viewWillAppear window? \(self.view.window != nil), bounds: \(self.view.bounds)")
        isAppActive = true
        updateTorchAvailability()
        
        previewLayer.isHidden = false
        prepareUIForCubeLoad()
        
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
        print("[CameraPreviewVC] viewDidAppear window? \(self.view.window != nil), bounds: \(self.view.bounds)")
        print("[CameraPreviewVC] appeared; session running: \(session.isRunning), layer frame: \(previewLayer.frame)")
        if let connection = previewLayer.connection {
            print("[CameraPreviewVC] connection active: \(connection.isEnabled), videoOrientation: \(connection.videoOrientation.rawValue)")
        } else {
            print("[CameraPreviewVC] no preview connection")
        }
        prepareUIForCubeLoad()

        if didRunInitialAppearanceSync == false {
            didRunInitialAppearanceSync = true

            // Ensure preview layer is at the bottom
            if previewLayer.superlayer !== view.layer {
                view.layer.insertSublayer(previewLayer, at: 0)
            } else if let sublayers = view.layer.sublayers, let idx = sublayers.firstIndex(of: previewLayer), idx != 0 {
                previewLayer.removeFromSuperlayer()
                view.layer.insertSublayer(previewLayer, at: 0)
            }

            // Force frame and orientation now that we're in a window
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = view.bounds
            if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
                switch currentInterfaceOrientation() {
                case .portrait: connection.videoOrientation = .portrait
                case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
                case .landscapeLeft: connection.videoOrientation = .landscapeLeft
                case .landscapeRight: connection.videoOrientation = .landscapeRight
                default: break
                }
            }
            CATransaction.commit()

            // Final UI sync
            prepareUIForCubeLoad()
        }
        
        if autoManageSession && !session.isRunning {
            sessionQueue.async { [weak self] in
                self?.session.startRunning()
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    // Ensure preview layer is at the bottom
                    if self.previewLayer.superlayer !== self.view.layer {
                        self.view.layer.insertSublayer(self.previewLayer, at: 0)
                    } else if let sublayers = self.view.layer.sublayers, let idx = sublayers.firstIndex(of: self.previewLayer), idx != 0 {
                        self.previewLayer.removeFromSuperlayer()
                        self.view.layer.insertSublayer(self.previewLayer, at: 0)
                    }
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.previewLayer.frame = self.view.bounds
                    if let connection = self.previewLayer.connection, connection.isVideoOrientationSupported {
                        switch self.currentInterfaceOrientation() {
                        case .portrait: connection.videoOrientation = .portrait
                        case .portraitUpsideDown: connection.videoOrientation = .portraitUpsideDown
                        case .landscapeLeft: connection.videoOrientation = .landscapeLeft
                        case .landscapeRight: connection.videoOrientation = .landscapeRight
                        default: break
                        }
                    }
                    CATransaction.commit()
                    self.prepareUIForCubeLoad()
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Reset torch UI to safe state; actual session control should be managed by owner
        isTorchOn = false
        torchButton.setImage(UIImage(systemName: "flashlight.slash.circle.fill"), for: .normal)
        
        if autoManageSession && session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.stopRunning()
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .cameraCubeTabViewTapped, object: nil)
        NotificationCenter.default.removeObserver(self, name: .cameraCubeHoldBegan, object: nil)
        NotificationCenter.default.removeObserver(self, name: .cameraCubeHoldEnded, object: nil)
        if let obs = appDidBecomeActiveObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = appWillResignActiveObserver { NotificationCenter.default.removeObserver(obs) }
    }

    private func currentInterfaceOrientation() -> UIInterfaceOrientation {
        if let o = view.window?.windowScene?.interfaceOrientation {
            return o
        }
        return .portrait
    }

    /// Sync UI with current capture session/preview state. Safe to call multiple times.
    private func prepareUIForCubeLoad() {
        // Ensure preview layer is visible and sized
        previewLayer.isHidden = false
        if previewLayer.frame != view.bounds {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            previewLayer.frame = view.bounds
            CATransaction.commit()
        }

        // Update torch and buttons state
        updateTorchAvailability()
        flipButton.isEnabled = true
        torchButton.isEnabled = torchButton.isEnabled // no-op to trigger UI refresh
    }

    // MARK: - Public Trigger
    
    /// Begin recording via external (cube) hold
    public func startVideoHold() {
        // Ensure UI is ready
        prepareUIForCubeLoad()
        print("[CameraPreviewVC] startVideoHold()")
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        // Start UI and callbacks
        animateRecordingUI(started: true)
        startRecordingUI()
        DispatchQueue.main.async { [weak self] in
            self?.onStartVideo?()
        }
    }

    /// End recording via external (cube) release
    public func stopVideoHold() {
        print("[CameraPreviewVC] stopVideoHold()")
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        animateRecordingUI(started: false)
        stopRecordingUI()
        DispatchQueue.main.async { [weak self] in
            self?.onStopVideo?()
        }
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
    
    @objc private func handleCubeHoldBegan() {
        print("[CameraPreviewVC] handleCubeHoldBegan notification")
        startVideoHold()
    }

    @objc private func handleCubeHoldEnded() {
        print("[CameraPreviewVC] handleCubeHoldEnded notification")
        stopVideoHold()
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
        torchButton.setImage(UIImage(systemName: "flashlight.slash.circle.fill"), for: .normal)
        torchButton.addTarget(self, action: #selector(torchTapped), for: .touchUpInside)
        view.addSubview(torchButton)

        // Flip
        flipButton.translatesAutoresizingMaskIntoConstraints = false
        flipButton.backgroundColor = UIColor.white.withAlphaComponent(0.85)
        flipButton.tintColor = .black
        flipButton.layer.cornerRadius = 20
        flipButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera.circle.fill"), for: .normal)
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
            startRecordingUI()
            // Defer start to next runloop to avoid blocking UI
            DispatchQueue.main.async { [weak self] in
                self?.onStartVideo?()
            }
        case .ended, .cancelled, .failed:
            animateRecordingUI(started: false)
            stopRecordingUI()
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
            torchButton.setImage(UIImage(systemName: "flashlight.slash.circle.fill"), for: .normal)
            return
        }

        let supported = device.hasTorch
        torchButton.isEnabled = supported
        torchButton.alpha = supported ? 1.0 : 0.5

        isTorchOn = device.isTorchActive
        let icon = isTorchOn ? "flashlight.on.circle.fill" : "flashlight.slash.circle.fill"
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

        let icon = isTorchOn ? "flashlight.on.circle.fill" : "flashlight.slash.circle.fill"
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
                self.torchButton.setImage(UIImage(systemName: "flashlight.slash.circle.fill"), for: .normal)

                self.refreshRadiusBar()
                self.updateTorchAvailability()
                self.flipButton.isEnabled = true
                
                self.flipButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera.circle.fill"), for: .normal)

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
    
    // MARK: - Recording UI & Timer
    private func startRecordingUI() {
        recordStartDate = Date()
        recordProgress = 0
        // Show progress bar and reset height to 0
        if let heightConstraint = recordProgressView.constraints.first(where: { $0.firstAttribute == .height }) {
            heightConstraint.constant = 0
        }
        recordProgressView.isHidden = false
        // Start a display link to update progress smoothly
        let link = CADisplayLink(target: self, selector: #selector(updateRecordingProgress))
        link.add(to: .main, forMode: .common)
        recordTimer = link
        // Start pop/tick sound (placeholder system sound)
        AudioServicesPlaySystemSound(1104) // initial tick
    }

    private func stopRecordingUI() {
        recordTimer?.invalidate()
        recordTimer = nil
        recordStartDate = nil
        recordProgress = 0
        recordProgressView.isHidden = true
        // Stop any ongoing feedback (no loop here; if you add AVAudioPlayer loop, stop it)
    }

    @objc private func updateRecordingProgress() {
        guard let start = recordStartDate else { return }
        let elapsed = Date().timeIntervalSince(start)
        let progress = min(1.0, elapsed / recordMaxDuration)
        recordProgress = progress
        // Map progress to height up to the radius bar height (~220)
        let maxHeight: CGFloat = 220
        if let heightConstraint = recordProgressView.constraints.first(where: { $0.firstAttribute == .height }) {
            heightConstraint.constant = maxHeight * CGFloat(progress)
        }
        recordProgressView.setNeedsLayout()
        // Provide a subtle tick every second as a placeholder for a pop loop
        if floor(elapsed) != floor(elapsed - 1) {
            AudioServicesPlaySystemSound(1104)
        }
        // Auto-stop at max duration
        if elapsed >= recordMaxDuration {
            recordTimer?.invalidate()
            recordTimer = nil
            DispatchQueue.main.async { [weak self] in
                self?.animateRecordingUI(started: false)
                self?.stopRecordingUI()
                self?.onStopVideo?()
            }
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
