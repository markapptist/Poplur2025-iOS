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
        
        installRadiusBar()

        setupButtons()
        setupGestures()
        updateTorchAvailability()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleCubeTappedNotification), name: .cubeTabViewTapped, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        updateTorchAvailability()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .cubeTabViewTapped, object: nil)
    }

    // MARK: - Public Trigger
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
            onStartVideo?()
        case .ended, .cancelled, .failed:
            onStopVideo?()
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

        session.beginConfiguration()
        session.removeInput(currentInput)

        var didAdd = false
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
           let newInput = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(newInput) {
            session.addInput(newInput)
            didAdd = true
        }

        if didAdd == false, session.canAddInput(currentInput) {
            session.addInput(currentInput)
        }

        session.commitConfiguration()

        // Front camera usually has no torch
        isTorchOn = false
        torchButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.updateTorchAvailability()
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
                .onChange(of: value) { newVal in
                    onChange(newVal)
                }
        }
    }
}

