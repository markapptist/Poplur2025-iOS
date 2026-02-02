import UIKit
import AVFoundation

/// A lightweight view controller that hosts an AVCaptureVideoPreviewLayer
/// for a provided AVCaptureSession.
final class CameraPreviewViewController: UIViewController {
    private let session: AVCaptureSession
    private let previewLayer: AVCaptureVideoPreviewLayer
    /// Called when the shutter button is tapped.
    var onShutter: (() -> Void)?
    // Video recording callbacks
    var onStartVideo: (() -> Void)?
    var onStopVideo: (() -> Void)?
    private let shutterButton = UIButton(type: .system)

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

        // Shutter button setup
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        shutterButton.tintColor = .black
        shutterButton.setImage(UIImage(systemName: "camera.fill"), for: .normal)
        shutterButton.layer.cornerRadius = 32
        shutterButton.layer.shadowColor = UIColor.black.cgColor
        shutterButton.layer.shadowOpacity = 0.3
        shutterButton.layer.shadowRadius = 6
        shutterButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        view.addSubview(shutterButton)

        NSLayoutConstraint.activate([
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            shutterButton.widthAnchor.constraint(equalToConstant: 64),
            shutterButton.heightAnchor.constraint(equalToConstant: 64)
        ])

        // Long press to record video
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleShutterLongPress(_:)))
        longPress.minimumPressDuration = 0.2
        shutterButton.addGestureRecognizer(longPress)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
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
}
