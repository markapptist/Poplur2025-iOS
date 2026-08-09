//
//  SimplifiedMLDetection.swift
//  Ready-to-use ML detection using Vision's built-in capabilities
//

import Foundation
import Vision
import CoreML
import AVFoundation
import UIKit
import ObjectiveC

/// Simple ML detection manager using Vision's built-in image classification
/// This works out-of-the-box without requiring additional CoreML models
public class SimplifiedMLDetectionManager {
    
    // MARK: - Configuration
    
    /// Whether detection is enabled
    public var isEnabled: Bool = true
    
    /// Minimum confidence threshold (0.0 - 1.0)
    public var confidenceThreshold: Float = 0.15
    
    /// Process every Nth frame (higher = better performance, lower = more responsive)
    /// Process every Nth frame. VNClassifyImageRequest is a full-taxonomy
    /// classifier and is expensive: every 5th frame of 30fps meant six of them
    /// a second, forever, which the phone paid for in heat. Ten a second was
    /// never needed to label what the camera is pointed at.
    public var frameSkipInterval: Int = 12
    
    /// Maximum number of classifications to report
    public var maxResults: Int = 1
    
    // MARK: - Callbacks
    
    /// Called when objects are detected
    public var onDetection: (([DetectedObject]) -> Void)?
    
    /// Called when detection fails
    public var onError: ((Error) -> Void)?
    
    /// Called with pixel buffer for face recognition
    public var onFrameProcessed: ((CVPixelBuffer, [DetectedObject]) -> Void)?
    
    // MARK: - Private Properties
    
    private var frameCount: Int = 0
    private let detectionQueue = DispatchQueue(label: "com.app.ml-detection", qos: .userInitiated)
    private var isProcessing: Bool = false
    private var portalHitStreak: Int = 0
    private lazy var productClassifier: VNCoreMLModel? = {
        guard let modelURL = Bundle.main.url(
            forResource: "PoplurProductClassifier",
            withExtension: "mlmodelc"
        ) else {
            print("Poplur product classifier is not bundled; using Vision fallback")
            return nil
        }

        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        do {
            let model = try MLModel(contentsOf: modelURL, configuration: configuration)
            return try VNCoreMLModel(for: model)
        } catch {
            print("Unable to load Poplur product classifier: \(error)")
            return nil
        }
    }()
    
    // MARK: - Public Methods
    
    /// Process a camera frame for object detection
    public func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isEnabled, !isProcessing else { return }
        
        // Frame skipping for performance
        frameCount += 1
        guard frameCount % frameSkipInterval == 0 else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        isProcessing = true
        
        detectionQueue.async { [weak self] in
            self?.performDetection(on: pixelBuffer)
        }
    }
    
    // MARK: - Private Methods
    
    private func performDetection(on pixelBuffer: CVPixelBuffer) {
        defer { isProcessing = false }

        if let portalResult = classifyCommercialProduct(on: pixelBuffer) {
            publish(portalResult, for: pixelBuffer)
            return
        }

        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            let observations = (request.results ?? [])
                .filter { $0.confidence >= min(confidenceThreshold, 0.08) }
                .prefix(14)
            publish(preferredCommercialResult(from: Array(observations)), for: pixelBuffer)
        } catch {
            DispatchQueue.main.async {
                self.onError?(error)
            }
        }
    }

    /// The bundled classifier is deliberately narrow: it identifies a
    /// PlayStation Portal and rejects visually similar commercial hardware.
    /// A very strong first frame is immediate; borderline hits need temporal
    /// agreement so an unrelated widescreen device cannot flash the name.
    private func classifyCommercialProduct(on pixelBuffer: CVPixelBuffer) -> [DetectedObject]? {
        guard let productClassifier else { return nil }

        let request = VNCoreMLRequest(model: productClassifier)
        request.imageCropAndScaleOption = .centerCrop
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])

        do {
            try handler.perform([request])
        } catch {
            print("Poplur product classification failed: \(error)")
            portalHitStreak = 0
            return nil
        }

        guard let observations = request.results as? [VNClassificationObservation],
              let portal = observations.first(where: { $0.identifier == "PlayStation_Portal" }) else {
            portalHitStreak = 0
            return nil
        }

        if portal.confidence >= 0.90 {
            portalHitStreak = 2
        } else if portal.confidence >= 0.72 {
            portalHitStreak += 1
        } else {
            portalHitStreak = 0
        }

        guard portalHitStreak >= 2 else { return nil }
        return [DetectedObject(identifier: "PlayStation Portal", confidence: portal.confidence)]
    }

    private func publish(_ detectedObjects: [DetectedObject], for pixelBuffer: CVPixelBuffer) {
        // Always report, including an empty result. The overlay uses an empty
        // update to clear a stale label after the camera moves away.
        DispatchQueue.main.async {
            self.onDetection?(detectedObjects)
            if !detectedObjects.isEmpty {
                self.onFrameProcessed?(pixelBuffer, detectedObjects)
            }
        }
    }

    /// Vision's built-in classifier is broad scene taxonomy, so commercial
    /// hardware often arrives as several useful but generic clues. Fold those
    /// clues into one stable product answer before publishing it. This stays
    /// entirely on-device and avoids uploading a live camera stream.
    private func preferredCommercialResult(from observations: [VNClassificationObservation]) -> [DetectedObject] {
        guard let strongest = observations.first else { return [] }
        // Only the LEADING labels may steer the answer.
        //
        // This used to search all fourteen observations — including ones kept
        // at 0.08 confidence purely as context — so a single weak "screen" or
        // "remote control" anywhere in the bag routed the whole frame into a
        // gaming/handheld bucket. Point the camera at a chair in a room with a
        // monitor in it and the answer came back "handheld device"; everything
        // that was not gaming hardware either got mislabelled or fell through
        // to nothing. The refinement below is genuinely useful when the frame
        // really is a console handheld, so it stays — it just has to earn it
        // from the top of the list rather than from the tail.
        let leading = observations.prefix(3).map { $0.identifier.lowercased() }
        let joined = leading.joined(separator: " | ")

        func containsAny(_ terms: [String]) -> Bool {
            terms.contains { joined.contains($0) }
        }

        let gaming = containsAny([
            "game controller", "gamepad", "gaming", "joystick", "video game"
        ])
        let handheld = containsAny([
            "hand-held computer", "handheld", "portable computer", "remote control"
        ])
        let display = containsAny([
            "display", "lcd", "monitor", "screen", "television"
        ])

        if gaming && (handheld || display) {
            return [DetectedObject(
                identifier: "gaming handheld",
                confidence: max(strongest.confidence, 0.76)
            )]
        }
        if gaming {
            return [DetectedObject(
                identifier: "game controller",
                confidence: max(strongest.confidence, 0.72)
            )]
        }
        if handheld && display {
            return [DetectedObject(
                identifier: "handheld device",
                confidence: max(strongest.confidence, 0.68)
            )]
        }

        guard strongest.confidence >= confidenceThreshold else { return [] }
        return [DetectedObject(
            identifier: Self.readableLabel(strongest.identifier),
            confidence: strongest.confidence
        )]
    }

    /// Vision's taxonomy identifiers are machine-shaped ("coffee_mug",
    /// "chair, seat"). The overlay and the shopping card both show this string
    /// to a person, so hand them the plain-English head of it.
    static func readableLabel(_ identifier: String) -> String {
        let head = identifier.split(separator: ",").first.map(String.init) ?? identifier
        return head
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Detected Object Model

/// Represents a detected object
public struct DetectedObject {
    /// Object identifier/name (e.g., "cat", "dog", "car")
    public let identifier: String
    
    /// Confidence score (0.0 - 1.0)
    public let confidence: Float
    
    /// Formatted confidence percentage
    public var confidencePercentage: Int {
        Int(confidence * 100)
    }
    
    /// Human-readable description
    public var description: String {
        "\(identifier.capitalized) (\(confidencePercentage)%)"
    }
}

// MARK: - ML Detection UI View

/// A simple view that displays detected objects at the top of the camera
public class MLDetectionBadgeView: UIView {
    
    // MARK: - UI Elements
    
    private let containerStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()
    
    private let iconLabel: UILabel = {
        let label = UILabel()
        label.text = "🔍"
        label.font = .systemFont(ofSize: 24)
        return label
    }()
    
    private let detectionLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.text = "Scanning..."
        return label
    }()
    
    private let confidenceLabel: UILabel = {
        let label = UILabel()
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = UIColor.white.withAlphaComponent(0.8)
        label.textAlignment = .center
        return label
    }()
    
    // MARK: - Initialization
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        // Background blur effect
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(blurView)
        
        // Add stack
        addSubview(containerStack)
        containerStack.addArrangedSubview(iconLabel)
        containerStack.addArrangedSubview(detectionLabel)
        containerStack.addArrangedSubview(confidenceLabel)
        
        // Styling
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        clipsToBounds = true
        
        // Constraints
        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: topAnchor),
            blurView.leadingAnchor.constraint(equalTo: leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: bottomAnchor),
            
            containerStack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            containerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            containerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            containerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
        
        // Initially hidden
        alpha = 0
    }
    
    // MARK: - Public Methods
    
    /// Update the view with detected objects
    public func updateDetections(_ objects: [DetectedObject]) {
        guard !objects.isEmpty else {
            fadeOut()
            return
        }
        
        let topObject = objects[0]
        
        // Update labels
        iconLabel.text = getIcon(for: topObject.identifier)
        detectionLabel.text = topObject.identifier.capitalized
        
        if objects.count > 1 {
            let others = objects.dropFirst().map { $0.identifier.capitalized }.joined(separator: ", ")
            confidenceLabel.text = "\(topObject.confidencePercentage)% • Also: \(others)"
        } else {
            confidenceLabel.text = "\(topObject.confidencePercentage)% confidence"
        }
        
        // Animate in
        fadeIn()
        
        // Pulse animation for high confidence
        if topObject.confidence > 0.5 {
            pulseAnimation()
        }
    }
    
    /// Hide the detection badge
    public func clear() {
        fadeOut()
    }
    
    // MARK: - Private Methods
    
    private func fadeIn() {
        guard alpha < 1.0 else { return }
        
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseOut]) {
            self.alpha = 1.0
            self.transform = .identity
        }
    }
    
    private func fadeOut() {
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseIn]) {
            self.alpha = 0
            self.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }
    }
    
    private func pulseAnimation() {
        UIView.animate(withDuration: 0.2, delay: 0, options: [.autoreverse, .curveEaseInOut]) {
            self.transform = CGAffineTransform(scaleX: 1.05, y: 1.05)
        } completion: { _ in
            UIView.animate(withDuration: 0.2) {
                self.transform = .identity
            }
        }
    }
    
    private func getIcon(for identifier: String) -> String {
        let lowercased = identifier.lowercased()
        
        // Map identifiers to emojis
        if lowercased.contains("dog") { return "🐕" }
        if lowercased.contains("cat") { return "🐈" }
        if lowercased.contains("bird") { return "🐦" }
        if lowercased.contains("person") || lowercased.contains("human") { return "👤" }
        if lowercased.contains("car") || lowercased.contains("vehicle") { return "🚗" }
        if lowercased.contains("phone") || lowercased.contains("mobile") { return "📱" }
        if lowercased.contains("food") || lowercased.contains("pizza") || lowercased.contains("burger") { return "🍔" }
        if lowercased.contains("drink") || lowercased.contains("coffee") || lowercased.contains("cup") { return "☕️" }
        if lowercased.contains("tree") || lowercased.contains("plant") { return "🌳" }
        if lowercased.contains("flower") { return "🌸" }
        if lowercased.contains("building") || lowercased.contains("house") { return "🏢" }
        if lowercased.contains("book") { return "📚" }
        if lowercased.contains("computer") || lowercased.contains("laptop") { return "💻" }
        if lowercased.contains("beach") || lowercased.contains("ocean") { return "🏖" }
        if lowercased.contains("mountain") { return "⛰" }
        if lowercased.contains("sky") || lowercased.contains("cloud") { return "☁️" }
        
        return "🔍" // Default search icon
    }
}

// MARK: - Easy Integration Extension
// Note: CameraViewController extension removed - it was part of Snap Camera Kit SDK
// If you need to integrate with a custom camera controller, create a similar extension for your own camera class

// MARK: - CameraKitController Integration Extension
// Note: CameraKitController already has mlDetectionManager property defined in its class
// This extension only adds the helper methods and video delegate storage

extension CameraKitController {
    
    private static var mlVideoDelegateKey: UInt8 = 0
    
    /// Internal video delegate for ML processing
    private var mlVideoDelegate: MLVideoDataOutputDelegate? {
        get {
            return objc_getAssociatedObject(self, &Self.mlVideoDelegateKey) as? MLVideoDataOutputDelegate
        }
        set {
            objc_setAssociatedObject(self, &Self.mlVideoDelegateKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    /// Enable ML object detection for CameraKitController
    public func enableMLObjectDetection() {
        // Create manager if needed
        if mlDetectionManager == nil {
            let manager = SimplifiedMLDetectionManager()
            mlDetectionManager = manager
            
            // Setup callbacks
            manager.onDetection = { objects in
                // Post notification for UI updates
                NotificationCenter.default.post(
                    name: NSNotification.Name("MLObjectsDetected"),
                    object: nil,
                    userInfo: ["objects": objects]
                )
            }
            
            manager.onError = { error in
                print("❌ ML Detection Error: \(error.localizedDescription)")
            }
        }
        
        // Setup video output for frame capture
        setupMLVideoOutput()
        
        isMLDetectionEnabled = true
        print("✅ ML Object Detection enabled for CameraKitController!")
    }
    
    /// Disable ML detection
    public func disableMLObjectDetection() {
        mlDetectionManager?.isEnabled = false
        isMLDetectionEnabled = false
        print("🛑 ML Object Detection disabled")
    }
    
    // MARK: - Private Helpers
    
    private func setupMLVideoOutput() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let captureSession = self.captureSession
            
            // Create delegate if needed
            if self.mlVideoDelegate == nil {
                let delegate = MLVideoDataOutputDelegate()
                delegate.mlManager = self.mlDetectionManager
                self.mlVideoDelegate = delegate
            }
            
            // Check if we already have a video output
            let existingOutputs = captureSession.outputs.compactMap { $0 as? AVCaptureVideoDataOutput }
            if let existingOutput = existingOutputs.first {
                // Reuse existing output
                existingOutput.setSampleBufferDelegate(self.mlVideoDelegate, queue: DispatchQueue(label: "ml-video-queue"))
                print("✅ Reusing existing video output for ML")
                return
            }
            
            // Create new video output
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self.mlVideoDelegate, queue: DispatchQueue(label: "ml-video-queue"))
            videoOutput.alwaysDiscardsLateVideoFrames = true
            
            captureSession.beginConfiguration()
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                print("✅ Added new video output for ML")
            } else {
                print("❌ Cannot add video output")
            }
            captureSession.commitConfiguration()
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate Extension

/// Delegate wrapper to handle video frames without modifying CameraViewController's conformance
private class MLVideoDataOutputDelegate: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    weak var mlManager: SimplifiedMLDetectionManager?
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        mlManager?.processFrame(sampleBuffer)
    }
}
