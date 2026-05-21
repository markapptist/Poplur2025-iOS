//
//  SimplifiedMLDetection.swift
//  Ready-to-use ML detection using Vision's built-in capabilities
//

import Foundation
import Vision
import AVFoundation
import UIKit
import SCSDKCameraKit
import ObjectiveC

// Forward declaration to help Swift find CameraViewController
// This ensures the extension below can see the class
#if canImport(Poplur2025)
import Poplur2025
#endif

/// Simple ML detection manager using Vision's built-in image classification
/// This works out-of-the-box without requiring additional CoreML models
public class SimplifiedMLDetectionManager {
    
    // MARK: - Configuration
    
    /// Whether detection is enabled
    public var isEnabled: Bool = true
    
    /// Minimum confidence threshold (0.0 - 1.0)
    public var confidenceThreshold: Float = 0.15
    
    /// Process every Nth frame (higher = better performance, lower = more responsive)
    public var frameSkipInterval: Int = 5
    
    /// Maximum number of classifications to report
    public var maxResults: Int = 3
    
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
        let request = VNClassifyImageRequest { [weak self] request, error in
            guard let self = self else { return }
            
            defer { self.isProcessing = false }
            
            if let error = error {
                DispatchQueue.main.async {
                    self.onError?(error)
                }
                return
            }
            
            guard let observations = request.results as? [VNClassificationObservation] else {
                return
            }
            
            let detectedObjects = observations
                .filter { $0.confidence >= self.confidenceThreshold }
                .prefix(self.maxResults)
                .map { DetectedObject(identifier: $0.identifier, confidence: $0.confidence) }
            
            if !detectedObjects.isEmpty {
                DispatchQueue.main.async {
                    self.onDetection?(Array(detectedObjects))
                    // Also pass the pixel buffer for face recognition
                    self.onFrameProcessed?(pixelBuffer, Array(detectedObjects))
                }
            }
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            DispatchQueue.main.async {
                self.onError?(error)
            }
            isProcessing = false
        }
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

extension CameraViewController {
    
    private static var mlDetectionManagerKey: UInt8 = 0
    private static var mlDetectionBadgeKey: UInt8 = 0
    private static var mlVideoDelegateKey: UInt8 = 0
    
    /// Get or create the ML detection manager
    public var mlDetectionManager: SimplifiedMLDetectionManager? {
        get {
            return objc_getAssociatedObject(self, &Self.mlDetectionManagerKey) as? SimplifiedMLDetectionManager
        }
        set {
            objc_setAssociatedObject(self, &Self.mlDetectionManagerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    /// Get or create the ML detection badge view
    public var mlDetectionBadge: MLDetectionBadgeView? {
        get {
            return objc_getAssociatedObject(self, &Self.mlDetectionBadgeKey) as? MLDetectionBadgeView
        }
        set {
            objc_setAssociatedObject(self, &Self.mlDetectionBadgeKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    /// Internal video delegate for ML processing
    private var mlVideoDelegate: MLVideoDataOutputDelegate? {
        get {
            return objc_getAssociatedObject(self, &Self.mlVideoDelegateKey) as? MLVideoDataOutputDelegate
        }
        set {
            objc_setAssociatedObject(self, &Self.mlVideoDelegateKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    /// Enable ML object detection with a simple one-liner
    public func enableMLDetection() {
        // Create manager if needed
        if mlDetectionManager == nil {
            let manager = SimplifiedMLDetectionManager()
            mlDetectionManager = manager
            
            // Setup callbacks
            manager.onDetection = { [weak self] objects in
                self?.handleMLDetections(objects)
            }
            
            manager.onError = { error in
                print("❌ ML Detection Error: \(error.localizedDescription)")
            }
        }
        
        // Create and add badge view if needed
        if mlDetectionBadge == nil {
            let badge = MLDetectionBadgeView()
            badge.translatesAutoresizingMaskIntoConstraints = false
            cameraView.addSubview(badge)
            
            NSLayoutConstraint.activate([
                badge.topAnchor.constraint(equalTo: cameraView.safeAreaLayoutGuide.topAnchor, constant: 16),
                badge.centerXAnchor.constraint(equalTo: cameraView.centerXAnchor),
                badge.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
            ])
            
            mlDetectionBadge = badge
        }
        
        // Setup video output for frame capture
        setupMLVideoOutput()
        
        print("✅ ML Object Detection enabled!")
    }
    
    /// Disable ML detection
    public func disableMLDetection() {
        mlDetectionManager?.isEnabled = false
        mlDetectionBadge?.clear()
        print("🛑 ML Object Detection disabled")
    }
    
    // MARK: - Private Helpers
    
    private func setupMLVideoOutput() {
        guard let captureSession = cameraController.captureSession else {
            print("❌ No capture session available")
            return
        }
        
        // Create delegate if needed
        if mlVideoDelegate == nil {
            let delegate = MLVideoDataOutputDelegate()
            delegate.mlManager = mlDetectionManager
            mlVideoDelegate = delegate
        }
        
        // Check if we already have a video output
        let existingOutputs = captureSession.outputs.compactMap { $0 as? AVCaptureVideoDataOutput }
        if let existingOutput = existingOutputs.first {
            // Reuse existing output
            existingOutput.setSampleBufferDelegate(mlVideoDelegate, queue: DispatchQueue(label: "ml-video-queue"))
            print("✅ Reusing existing video output for ML")
            return
        }
        
        // Create new video output
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(mlVideoDelegate, queue: DispatchQueue(label: "ml-video-queue"))
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
    
    private func handleMLDetections(_ objects: [DetectedObject]) {
        mlDetectionBadge?.updateDetections(objects)
        
        // Optional: Post notification for other parts of the app
        NotificationCenter.default.post(
            name: NSNotification.Name("MLObjectsDetected"),
            object: nil,
            userInfo: ["objects": objects]
        )
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
