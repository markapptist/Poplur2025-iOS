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

    /// How many things one frame may name. The camera used to publish exactly
    /// ONE object per frame — the single strongest observation — so a room full
    /// of recognisable things reported a single label, and the narrow product
    /// model's one subject hid the rest of the frame behind it. Vision hands
    /// back a ranked bag; report the bag.
    public var maxReportedObjects: Int = 6

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
    /// The readout has one primary answer, even though every frame publishes
    /// several findings. Remember its prior ordering so two close Vision
    /// scores do not make the scene phrase flicker while the phone is still.
    /// This state is confined to `detectionQueue` with the rest of inference.
    private var lastPresentationIdentifiers: [String] = []
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

        // The bundled product classifier knows exactly one subject, so it is a
        // BONUS label, never a gate. It used to `return` the moment it saw its
        // one product, which is why the camera looked blind everywhere except
        // at that product: a hit suppressed the full-taxonomy pass entirely.
        let product = classifyCommercialProduct(on: pixelBuffer) ?? []

        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
            let observations = (request.results ?? [])
                .filter { $0.confidence >= min(confidenceThreshold, 0.08) }
                .prefix(14)
            let scene = preferredCommercialResult(from: Array(observations))
            publish(Self.merged(product, scene), for: pixelBuffer)
        } catch {
            // The scene pass failed — still report whatever the product model
            // saw rather than dropping the frame's only answer.
            publish(product, for: pixelBuffer)
            DispatchQueue.main.async {
                self.onError?(error)
            }
        }
    }

    /// Product hits lead (they are the specific answer), then the scene labels,
    /// with duplicates by name collapsed to their most confident reading.
    private static func merged(_ lists: [DetectedObject]...) -> [DetectedObject] {
        var seen = Set<String>()
        var out: [DetectedObject] = []
        for object in lists.flatMap({ $0 }) {
            let key = object.identifier.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(object)
        }
        return out
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

        // The refinement, when it fires, is the most SPECIFIC thing we can say
        // about the frame, so it leads. It no longer *replaces* the frame's
        // other contents — returning only this meant pointing the camera at a
        // desk with a controller on it reported "game controller" and nothing
        // else in the shot.
        var refined: DetectedObject?
        if gaming && (handheld || display) {
            refined = DetectedObject(
                identifier: "gaming handheld",
                confidence: max(strongest.confidence, 0.76)
            )
        } else if gaming {
            refined = DetectedObject(
                identifier: "game controller",
                confidence: max(strongest.confidence, 0.72)
            )
        } else if handheld && display {
            refined = DetectedObject(
                identifier: "handheld device",
                confidence: max(strongest.confidence, 0.68)
            )
        }

        // Everything else the frame actually contains. Keep the complete bag,
        // but choose the first (display) answer by semantic usefulness rather
        // than raw probability alone. VNClassifyImageRequest quite reasonably
        // gives visual clues such as "cord", "line", "texture" and "structure"
        // high scores; those clues help the scanner, but presenting one as the
        // camera's entire understanding of a room is not useful to a person.
        var named = observations
            .filter { $0.confidence >= confidenceThreshold }
            .map {
                DetectedObject(
                    identifier: Self.readableLabel($0.identifier),
                    confidence: $0.confidence
                )
            }

        // Vision often reports the explicit room/place label below several
        // texture clues. Surface that context without inventing a class: every
        // synthesized phrase below is backed by an identifier Vision emitted
        // for this same frame, and carries that observation's real confidence.
        if let context = Self.sceneContext(
            from: observations,
            minimumConfidence: confidenceThreshold
        ) {
            named.insert(context, at: 0)
        }

        var candidates = Self.merged(refined.map { [$0] } ?? [], named)
        candidates.sort {
            let lhs = Self.presentationScore(for: $0)
            let rhs = Self.presentationScore(for: $1)
            if lhs == rhs { return $0.confidence > $1.confidence }
            return lhs > rhs
        }

        // Hysteresis only holds the previous answer when Vision still sees it
        // and the new winner is close. Panning to a genuinely different scene
        // switches immediately because the old label is absent (or far weaker).
        if let previous = lastPresentationIdentifiers.first,
           let previousIndex = candidates.firstIndex(where: {
               $0.identifier.caseInsensitiveCompare(previous) == .orderedSame
           }),
           let winner = candidates.first {
            let previousCandidate = candidates[previousIndex]
            let winnerScore = Self.presentationScore(for: winner)
            let previousScore = Self.presentationScore(for: previousCandidate)
            if previousScore + 0.10 >= winnerScore {
                candidates.remove(at: previousIndex)
                candidates.insert(previousCandidate, at: 0)
            }
        }

        // Keep close runners-up in their prior order while they remain present.
        // A much stronger new result must move forward immediately; otherwise
        // an old 15% clue could stay ahead of a new 90% object indefinitely.
        if let primary = candidates.first, lastPresentationIdentifiers.count > 1 {
            var stable = [primary]
            var remaining = Array(candidates.dropFirst())
            for previous in lastPresentationIdentifiers.dropFirst() {
                guard let index = remaining.firstIndex(where: {
                    $0.identifier.caseInsensitiveCompare(previous) == .orderedSame
                }) else { continue }
                let previousCandidate = remaining[index]
                let nextScore = remaining.first.map { Self.presentationScore(for: $0) }
                    ?? -Float.greatestFiniteMagnitude
                guard Self.presentationScore(for: previousCandidate) + 0.10 >= nextScore else {
                    continue
                }
                stable.append(remaining.remove(at: index))
            }
            stable.append(contentsOf: remaining)
            candidates = stable
        }

        let presented = Array(candidates.prefix(maxReportedObjects))
        lastPresentationIdentifiers = presented.map(\.identifier)
        return presented
    }

    /// A scene phrase derived from Vision's own broad scene taxonomy. Specific
    /// rooms win over generic indoor/outdoor groupings.
    private static func sceneContext(
        from observations: [VNClassificationObservation],
        minimumConfidence: Float
    ) -> DetectedObject? {
        let groups: [(label: String, terms: [String])] = [
            ("living room", ["living room", "lounge"]),
            ("bedroom", ["bedroom", "bedchamber"]),
            ("kitchen", ["kitchen"]),
            ("bathroom", ["bathroom", "washroom"]),
            ("office", ["office", "workspace"]),
            ("store", ["shop", "store", "supermarket"]),
            ("restaurant", ["restaurant", "dining room", "cafe"]),
            ("street scene", ["street scene", "street", "roadway", "sidewalk"]),
            ("outdoor scene", ["outdoor", "outdoors", "landscape", "natural scene"]),
            ("indoor room", ["indoor", "interior", "room", "home interior"])
        ]

        let eligible = groups.compactMap { group -> DetectedObject? in
            let matches = observations.filter { observation in
                guard observation.confidence >= minimumConfidence else { return false }
                let identifier = observation.identifier.lowercased()
                let tokens = identifier.split(whereSeparator: { !$0.isLetter }).map(String.init)
                let words = Set(tokens)
                let boundedPhrase = " \(tokens.joined(separator: " ")) "
                return group.terms.contains { term in
                    let phraseWords = term.split(separator: " ").map(String.init)
                    return phraseWords.count > 1
                        ? boundedPhrase.contains(" \(phraseWords.joined(separator: " ")) ")
                        : words.contains(term)
                }
            }
            guard let strongest = matches.max(by: { $0.confidence < $1.confidence }) else { return nil }
            return DetectedObject(identifier: group.label, confidence: strongest.confidence)
        }
        return eligible.max(by: { $0.confidence < $1.confidence })
    }

    /// Rank what is most useful to SAY, while retaining original confidence
    /// for the percentage and all downstream scan/commerce decisions.
    private static func presentationScore(for object: DetectedObject) -> Float {
        let label = object.identifier.lowercased()
        var score = object.confidence

        let sceneTerms = [
            "room", "indoor", "outdoor", "interior", "kitchen", "bedroom",
            "bathroom", "office", "restaurant", "store", "street", "landscape"
        ]
        let concreteTerms = [
            "person", "face", "cat", "dog", "animal", "chair", "table", "desk",
            "door", "window", "cabinet", "sofa", "couch", "bed", "computer",
            "laptop", "monitor", "screen", "television", "phone", "camera",
            "book", "bottle", "cup", "plant", "car", "bicycle", "food"
        ]
        let clueOnlyTerms = [
            "cord", "wire", "line", "edge", "pattern", "texture", "material",
            "shadow", "color", "shape", "structure", "artifact"
        ]
        let labelTerms = Set(label.split(whereSeparator: { !$0.isLetter }).map(String.init))

        if sceneTerms.contains(where: { labelTerms.contains($0) }) { score += 0.14 }
        if concreteTerms.contains(where: { labelTerms.contains($0) }) { score += 0.07 }
        if clueOnlyTerms.contains(where: { labelTerms.contains($0) }) { score -= 0.12 }
        return score
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
