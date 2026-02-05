import UIKit
import AVFoundation

/// A lightweight view controller that hosts an AVCaptureVideoPreviewLayer
/// for a provided AVCaptureSession.
final class CameraPreviewViewController: UIViewController {
    private let session: AVCaptureSession
    private let previewLayer: AVCaptureVideoPreviewLayer
    private var isTorchOn: Bool = false
    /// Called when the shutter button is tapped.
    var onShutter: (() -> Void)?
    // Video recording callbacks
    var onStartVideo: (() -> Void)?
    var onStopVideo: (() -> Void)?
    // Swipe navigation callbacks
    var onSwipeLeft: (() -> Void)?
    var onSwipeRight: (() -> Void)?
    private let shutterButton = UIButton(type: .system)
    private let torchButton = UIButton(type: .system)
    private let flipButton = UIButton(type: .system)

    init(session: AVCaptureSession) {
        self.session = session
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(nibName: nil, bundle: nil)
        self.previewLayer.videoGravity = .resizeAspectFill
        self.shutterButton.accessibilityLabel = "Shutter"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.layer.addSublayer(previewLayer)

        shutterButton.isHidden = true
        shutterButton.removeTarget(self, action: #selector(shutterTapped), for: .touchUpInside)

        // Torch button setup
        torchButton.translatesAutoresizingMaskIntoConstraints = false
        torchButton.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        torchButton.tintColor = .black
        torchButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        torchButton.layer.cornerRadius = 20
        torchButton.addTarget(self, action: #selector(torchTapped), for: .touchUpInside)
        view.addSubview(torchButton)

        // Flip camera button setup
        flipButton.translatesAutoresizingMaskIntoConstraints = false
        flipButton.backgroundColor = UIColor.white.withAlphaComponent(0.8)
        flipButton.tintColor = .black
        flipButton.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera"), for: .normal)
        flipButton.layer.cornerRadius = 20
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

        updateTorchAvailability()

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
        updateTorchAvailability()
    }

    /// Programmatically trigger the shutter to take a photo.
    /// Call this when an external UI (e.g., the cube in CubeTabView) is pressed on the record tab.
    func triggerShutter() {
        onShutter?()
    }

    @objc private func shutterTapped() {
        onShutter?()
    }

    @objc private func handleShutterLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            onStartVideo?()
        case .ended, .cancelled, .failed:
            onStopVideo?()
        default:
            break
        }
    }

    private func activeDevice() -> AVCaptureDevice? {
        return (session.inputs.first as? AVCaptureDeviceInput)?.device
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
        if supported {
            isTorchOn = device.isTorchActive
            let icon = isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"
            torchButton.setImage(UIImage(systemName: icon), for: .normal)
        } else {
            isTorchOn = false
            torchButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        }
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
            print("[Camera] Torch error: \(error)")
            isTorchOn = false
        }
        let icon = isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"
        torchButton.setImage(UIImage(systemName: icon), for: .normal)
    }

    @objc private func flipTapped() {
        guard let currentInput = session.inputs.first as? AVCaptureDeviceInput else { return }
        let newPosition: AVCaptureDevice.Position = currentInput.device.position == .back ? .front : .back
        session.beginConfiguration()
        session.removeInput(currentInput)
        var didAdd = false
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
           let newInput = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(newInput) {
            session.addInput(newInput)
            didAdd = true
        }
        if didAdd == false {
            // Re-add old input on failure
            if session.canAddInput(currentInput) {
                session.addInput(currentInput)
            }
        }
        session.commitConfiguration()
        // Reset torch UI after flip; front camera typically lacks torch
        isTorchOn = false
        torchButton.setImage(UIImage(systemName: "flashlight.off.fill"), for: .normal)
        // Update availability after swap
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.updateTorchAvailability()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let threshold: CGFloat = 80
        switch gesture.state {
        case .ended:
            if abs(translation.x) > abs(translation.y) {
                if translation.x <= -threshold {
                    onSwipeLeft?()
                } else if translation.x >= threshold {
                    onSwipeRight?()
                }
            }
        default:
            break
        }
    }
}
