import SwiftUI
import ARKit
import UIKit

struct HSOutput {
    let usdzURL: URL?
    let previewImage: UIImage?
}

enum HSError: Error {
    case unavailable
    case failed(String)
    case cancelled
}

class HSScannerViewController: UIViewController, ARSessionDelegate {
    var onComplete: ((Swift.Result<HSOutput, HSError>) -> Void)?

    private var arView: ARSCNView!

    override func viewDidLoad() {
        super.viewDidLoad()
        arView = ARSCNView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(arView)
        arView.session.delegate = self

        // Configure ARKit for face scanning
        guard ARFaceTrackingConfiguration.isSupported else {
            onComplete?(Swift.Result.failure(HSError.unavailable))
            return
        }
        let configuration = ARFaceTrackingConfiguration()
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        // Add cancel button
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16)
        ])
    }

    @objc private func cancelTapped() {
        arView.session.pause()
        onComplete?(Swift.Result.failure(HSError.cancelled))
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        // We could start scanning when face anchor is added
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        // Handle face mesh updates if needed
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        // Handle anchor removals if needed
    }

    // Simulate completion after scanning or manual trigger
    // In real implementation, you'd gather face mesh and export USDZ and preview image
    func completeScan() {
        // Simulate saved USDZ file URL (replace with real export logic)
        let usdzURL = FileManager.default.temporaryDirectory.appendingPathComponent("headScan.usdz")

        // Simulate preview image capture
        let previewImage = arView.snapshot()

        arView.session.pause()
        onComplete?(Swift.Result.success(HSOutput(usdzURL: usdzURL, previewImage: previewImage)))
    }
}

struct HeadScannerView: View {
    var onComplete: (Swift.Result<HSOutput, HSError>) -> Void

    var body: some View {
        HSScannerViewControllerRepresentable(onComplete: onComplete)
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct HSScannerViewControllerRepresentable: UIViewControllerRepresentable {
    typealias UIViewControllerType = HSScannerViewController

    var onComplete: (Swift.Result<HSOutput, HSError>) -> Void

    func makeUIViewController(context: Context) -> HSScannerViewController {
        let vc = HSScannerViewController()
        vc.onComplete = onComplete
        return vc
    }

    func updateUIViewController(_ uiViewController: HSScannerViewController, context: Context) {}
}
