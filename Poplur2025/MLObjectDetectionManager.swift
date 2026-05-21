//
//  MLObjectDetectionManager.swift
//  Real-time object detection using Vision framework
//

import Foundation
import Vision
import CoreML
import AVFoundation
import UIKit

/// Protocol for receiving object detection results
public protocol MLObjectDetectionDelegate: AnyObject {
    /// Called when objects are detected in the frame
    /// - Parameters:
    ///   - observations: Array of detected objects with confidence scores
    ///   - frame: The analyzed frame
    func didDetectObjects(_ observations: [VNRecognizedObjectObservation], in frame: CVPixelBuffer)
    
    /// Called when detection fails
    /// - Parameter error: The error that occurred
    func detectionDidFail(with error: Error)
}

/// Manages real-time object detection from camera frames using Vision framework
public class MLObjectDetectionManager {
    
    // MARK: - Properties
    
    public weak var delegate: MLObjectDetectionDelegate?
    
    /// Whether detection is currently enabled
    public var isDetectionEnabled: Bool = true {
        didSet {
            if !isDetectionEnabled {
                // Clear any pending requests
                detectionQueue.cancelAllOperations()
            }
        }
    }
    
    /// Minimum confidence threshold (0.0 - 1.0) for detections to be reported
    public var confidenceThreshold: Float = 0.5
    
    /// Maximum number of objects to detect per frame
    public var maxDetections: Int = 5
    
    /// Frame skip interval - only process every Nth frame for performance
    public var frameSkipInterval: Int = 3
    
    private var frameCount: Int = 0
    
    // Vision request
    private lazy var objectDetectionRequest: VNCoreMLRequest = {
        do {
            // Use Apple's YOLOv3 or MobileNet object detection model
            // Note: You can replace this with a custom CoreML model
            let configuration = MLModelConfiguration()
            configuration.computeUnits = .cpuAndGPU // or .all for Neural Engine
            
            // Try to load built-in object detection model
            // For iOS 14+, you can use Vision's built-in object detection
            let model = try VNCoreMLModel(for: createObjectDetectionModel(configuration: configuration))
            
            let request = VNCoreMLRequest(model: model) { [weak self] request, error in
                self?.handleDetectionResults(request: request, error: error)
            }
            
            request.imageCropAndScaleOption = .scaleFit
            
            return request
        } catch {
            fatalError("Failed to load object detection model: \(error)")
        }
    }()
    
    // Queue for processing detection requests
    private let detectionQueue = OperationQueue()
    
    // MARK: - Initialization
    
    public init() {
        detectionQueue.maxConcurrentOperationCount = 1 // Process one frame at a time
        detectionQueue.qualityOfService = .userInitiated
    }
    
    // MARK: - Public Methods
    
    /// Process a video frame for object detection
    /// - Parameter sampleBuffer: Camera frame from AVCaptureOutput
    public func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isDetectionEnabled else { return }
        
        // Skip frames for performance
        frameCount += 1
        guard frameCount % frameSkipInterval == 0 else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        processPixelBuffer(pixelBuffer)
    }
    
    /// Process a pixel buffer for object detection
    /// - Parameter pixelBuffer: The image buffer to analyze
    public func processPixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        guard isDetectionEnabled else { return }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        detectionQueue.addOperation { [weak self] in
            guard let self = self else { return }
            
            do {
                try handler.perform([self.objectDetectionRequest])
            } catch {
                DispatchQueue.main.async {
                    self.delegate?.detectionDidFail(with: error)
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func handleDetectionResults(request: VNRequest, error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.delegate?.detectionDidFail(with: error)
            }
            return
        }
        
        guard let results = request.results as? [VNRecognizedObjectObservation] else {
            return
        }
        
        // Filter by confidence threshold
        let filteredResults = results
            .filter { $0.confidence >= confidenceThreshold }
            .prefix(maxDetections)
        
        if !filteredResults.isEmpty {
            // Note: We don't have the pixel buffer here, so we'll need to modify the delegate protocol
            // or pass it through the request userInfo
            DispatchQueue.main.async {
                // Get pixel buffer from request context if available
                // Use direct cast since CVPixelBuffer is a typealias for CVBuffer
                if let pixelBufferValue = request.value(forKey: "pixelBuffer"),
                   CFGetTypeID(pixelBufferValue as CFTypeRef) == CVPixelBufferGetTypeID() {
                    let pixelBuffer = pixelBufferValue as! CVPixelBuffer
                    self.delegate?.didDetectObjects(Array(filteredResults), in: pixelBuffer)
                }
            }
        }
    }
    
    /// Create or load an object detection CoreML model
    /// - Parameter configuration: ML model configuration
    /// - Returns: The CoreML model for object detection
    private func createObjectDetectionModel(configuration: MLModelConfiguration) -> MLModel {
        // For iOS 15+, you can use built-in models or custom models
        // Here we'll create a simple wrapper that uses Vision's built-in capabilities
        
        // Note: In a real implementation, you would:
        // 1. Add a .mlmodel file to your project (e.g., YOLOv3, MobileNet)
        // 2. Load it here: try YOLOv3().model
        
        // For this example, we'll use a placeholder approach
        // You should replace this with an actual model
        
        // Option 1: Use a custom CoreML model from your bundle
        // guard let modelURL = Bundle.main.url(forResource: "YOLOv3", withExtension: "mlmodelc"),
        //       let model = try? MLModel(contentsOf: modelURL, configuration: configuration) else {
        //     fatalError("Failed to load ML model")
        // }
        // return model
        
        // Option 2: For demo purposes, create a minimal model
        // In production, you MUST use a real object detection model
        fatalError("Please add a CoreML object detection model to your project. Download YOLOv3 or MobileNet from Apple's CoreML models gallery: https://developer.apple.com/machine-learning/models/")
    }
}

// MARK: - Alternative Approach: Using Vision's Built-in Object Tracking

/// Alternative manager that uses Vision's built-in object tracking (iOS 14+)
public class MLObjectTrackingManager {
    
    public weak var delegate: MLObjectDetectionDelegate?
    
    /// Whether tracking is currently enabled
    public var isTrackingEnabled: Bool = true
    
    /// Minimum confidence threshold
    public var confidenceThreshold: Float = 0.5
    
    private var frameCount: Int = 0
    private var frameSkipInterval: Int = 3
    
    // Vision request for saliency-based object detection
    private lazy var saliencyRequest: VNGenerateAttentionBasedSaliencyImageRequest = {
        let request = VNGenerateAttentionBasedSaliencyImageRequest { [weak self] request, error in
            self?.handleSaliencyResults(request: request, error: error)
        }
        return request
    }()
    
    // Vision request for object recognition (rectangles)
    private lazy var rectangleRequest: VNDetectRectanglesRequest = {
        let request = VNDetectRectanglesRequest { [weak self] request, error in
            self?.handleRectangleResults(request: request, error: error)
        }
        request.minimumConfidence = confidenceThreshold
        request.maximumObservations = 10
        return request
    }()
    
    // Queue for processing
    private let trackingQueue = OperationQueue()
    
    public init() {
        trackingQueue.maxConcurrentOperationCount = 1
        trackingQueue.qualityOfService = .userInitiated
    }
    
    /// Process a video frame for object tracking
    public func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard isTrackingEnabled else { return }
        
        frameCount += 1
        guard frameCount % frameSkipInterval == 0 else { return }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        trackingQueue.addOperation { [weak self] in
            guard let self = self else { return }
            
            do {
                // Use saliency for interesting object detection
                try handler.perform([self.saliencyRequest])
            } catch {
                DispatchQueue.main.async {
                    self.delegate?.detectionDidFail(with: error)
                }
            }
        }
    }
    
    private func handleSaliencyResults(request: VNRequest, error: Error?) {
        // Handle saliency-based detection
        if let error = error {
            print("Saliency detection error: \(error)")
            return
        }
        
        guard let results = request.results as? [VNSaliencyImageObservation] else {
            return
        }
        
        // Process saliency results
        // This tells you what's "interesting" in the frame
        for observation in results {
            print("Detected salient regions: \(observation.salientObjects?.count ?? 0)")
            
            // Convert to recognized object observations for consistency
            if let salientObjects = observation.salientObjects {
                _ = salientObjects.compactMap { rect -> VNRecognizedObjectObservation? in
                    // Create a recognized object observation from the rectangle
                    // Note: This is a simplified conversion
                    return nil // Would need proper conversion logic
                }
                
                // Notify delegate
                // DispatchQueue.main.async {
                //     self.delegate?.didDetectObjects(recognizedObjects, in: pixelBuffer)
                // }
            }
        }
    }
    
    private func handleRectangleResults(request: VNRequest, error: Error?) {
        // Handle rectangle detection
        if let error = error {
            print("Rectangle detection error: \(error)")
            return
        }
    }
}

// MARK: - Detection Overlay View

/// A view that displays detected objects as overlay boxes
public class DetectionOverlayView: UIView {
    
    /// Detected objects to display
    public var detections: [VNRecognizedObjectObservation] = [] {
        didSet {
            setNeedsDisplay()
        }
    }
    
    /// Color for detection boxes
    public var boxColor: UIColor = .systemGreen
    
    /// Width of detection box lines
    public var boxLineWidth: CGFloat = 3.0
    
    /// Whether to show labels
    public var showLabels: Bool = true
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    
    public override func draw(_ rect: CGRect) {
        super.draw(rect)
        
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        context.saveGState()
        
        for detection in detections {
            // Convert Vision coordinates (normalized, origin bottom-left) to UIKit coordinates
            let boundingBox = detection.boundingBox
            let transform = CGAffineTransform(scaleX: 1, y: -1).translatedBy(x: 0, y: -1)
            let convertedBox = boundingBox.applying(transform)
            
            let x = convertedBox.origin.x * bounds.width
            let y = convertedBox.origin.y * bounds.height
            let width = convertedBox.width * bounds.width
            let height = convertedBox.height * bounds.height
            
            let rect = CGRect(x: x, y: y, width: width, height: height)
            
            // Draw bounding box
            context.setStrokeColor(boxColor.cgColor)
            context.setLineWidth(boxLineWidth)
            context.stroke(rect)
            
            // Draw label if available
            if showLabels, let topLabel = detection.labels.first {
                let label = "\(topLabel.identifier) (\(Int(topLabel.confidence * 100))%)"
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: UIColor.white,
                    .backgroundColor: boxColor
                ]
                
                let labelSize = label.size(withAttributes: attributes)
                let labelRect = CGRect(x: x, y: y - labelSize.height - 4, width: labelSize.width + 8, height: labelSize.height + 4)
                
                context.setFillColor(boxColor.cgColor)
                context.fill(labelRect)
                
                (label as NSString).draw(at: CGPoint(x: x + 4, y: y - labelSize.height - 2), withAttributes: attributes)
            }
        }
        
        context.restoreGState()
    }
}
