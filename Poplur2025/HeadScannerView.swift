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

    // UI overlays
    private let instructionLabel = UILabel()
    private let startButton = UIButton(type: .system)
    private let finishButton = UIButton(type: .system)
    private let progressView = UIProgressView(progressViewStyle: .default)
    private let cancelButton = UIButton(type: .system)

    // Scanning state
    private var isScanning = false
    private var coverageProgress: Float = 0 { didSet { updateProgressUI() } }

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
        configuration.isLightEstimationEnabled = true
        arView.automaticallyUpdatesLighting = true
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        setupOverlayUI()
        updateUIForIdle()
    }

    private func setupOverlayUI() {
        // Instruction label
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        instructionLabel.textAlignment = .center
        instructionLabel.textColor = .white
        instructionLabel.numberOfLines = 0
        instructionLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        instructionLabel.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        instructionLabel.layer.cornerRadius = 10
        instructionLabel.layer.masksToBounds = true
        view.addSubview(instructionLabel)

        // Progress view
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progressTintColor = .systemGreen
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.3)
        view.addSubview(progressView)

        // Start button
        startButton.setTitle("Start Scan", for: .normal)
        startButton.translatesAutoresizingMaskIntoConstraints = false
        startButton.addTarget(self, action: #selector(startTapped), for: .touchUpInside)
        view.addSubview(startButton)

        // Finish button
        finishButton.setTitle("Finish", for: .normal)
        finishButton.translatesAutoresizingMaskIntoConstraints = false
        finishButton.addTarget(self, action: #selector(finishTapped), for: .touchUpInside)
        view.addSubview(finishButton)

        // Cancel button
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            // Instructions centered at top
            instructionLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            // Progress view under instructions
            progressView.topAnchor.constraint(equalTo: instructionLabel.bottomAnchor, constant: 12),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            // Start button bottom-left
            startButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            startButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            // Finish button bottom-right
            finishButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            finishButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            // Cancel button top-left
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16)
        ])
    }

    private func updateUIForIdle() {
        isScanning = false
        coverageProgress = 0
        instructionLabel.text = "Center your face in the frame. Tap Start, then slowly turn your head left and right. Keep the phone at arm's length."
        startButton.isHidden = false
        startButton.isEnabled = true
        finishButton.isHidden = false
        finishButton.isEnabled = false
        progressView.isHidden = false
    }

    private func updateUIForScanning() {
        instructionLabel.text = "Turn your head slowly: left, right, up, and down until the bar fills. Hold steady and keep your face in view."
        startButton.isEnabled = false
        finishButton.isEnabled = false
    }

    private func updateProgressUI() {
        progressView.setProgress(coverageProgress, animated: true)
        if coverageProgress >= 0.95 {
            instructionLabel.text = "Great! Hold steady and tap Finish to complete the scan."
            finishButton.isEnabled = true
        }
    }

    @objc private func startTapped() {
        isScanning = true
        updateUIForScanning()
    }

    @objc private func finishTapped() {
        guard isScanning else { return }
        completeScan()
    }

    @objc private func cancelTapped() {
        arView.session.pause()
        onComplete?(Swift.Result.failure(HSError.cancelled))
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        guard isScanning else { return }
        // Estimate coverage progress using face anchor geometry updates
        for anchor in anchors {
            if let faceAnchor = anchor as? ARFaceAnchor {
                // Simple heuristic: use blendShapes variation + geometry vertex count visibility as a proxy
                // This is a placeholder approach; production apps should compute real coverage.
                let mouth = faceAnchor.blendShapes[.jawOpen]?.floatValue ?? 0
                let brow = faceAnchor.blendShapes[.browOuterUpLeft]?.floatValue ?? 0
                let turn = max(abs(faceAnchor.transform.columns.2.x), abs(faceAnchor.transform.columns.2.y))
                let sample = min(1.0, Float(0.3 * mouth + 0.3 * brow + 0.4 * turn + coverageProgress * 0.9))
                coverageProgress = max(coverageProgress, sample)
            }
        }
    }

    // Simulate completion after scanning
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
    @State private var result: HSOutput? = nil
    @State private var showResult = false
    @State private var lastError: HSError? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            HSScannerViewControllerRepresentable { res in
                switch res {
                case .success(let output):
                    result = output
                    showResult = true
                    onComplete(res)
                case .failure(let error):
                    lastError = error
                    onComplete(res)
                }
            }
            .ignoresSafeArea()

            // On-screen quick instructions overlay (SwiftUI side)
            VStack(spacing: 8) {
                Text("Head Scan Guide")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("1) Center your face. 2) Tap Start. 3) Turn left/right/up/down slowly. 4) Tap Finish.")
                    .font(.subheadline)
                    .foregroundStyle(.white)
            }
            .padding(12)
            .background(.black.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showResult) {
            VStack(spacing: 16) {
                if let img = result?.previewImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Text("No preview available")
                }
                if let url = result?.usdzURL {
                    Text("Model exported to: \(url.lastPathComponent)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ShareLink(item: url) {
                        Label("Share USDZ", systemImage: "square.and.arrow.up")
                    }
                }
                Button("Done") {
                    showResult = false
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .presentationDetents([.medium, .large])
        }
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
