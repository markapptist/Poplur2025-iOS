//
//  CameraViewController+MLDetection.swift
//  ML Object Detection Integration for Camera
//

import Foundation
import AVFoundation
import Vision
import UIKit

// MARK: - ML Detection Extension

extension CameraKitController {
    
    /// Setup ML object detection for the camera feed
    public func setupMLObjectDetection() {
        // Add the camera as a video data output delegate to receive frames
        addVideoDataOutput()
    }
    
    /// Add video data output to capture frames for ML processing
    private func addVideoDataOutput() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: .userInitiated))
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            
            if self.captureSession.canAddOutput(videoOutput) {
                self.captureSession.addOutput(videoOutput)
                print("✅ Added video output for ML detection")
            } else {
                print("❌ Could not add video output for ML detection")
            }
        }
    }
    
    /// Toggle ML detection on/off
    public func toggleMLDetection(enabled: Bool) {
        // You would store an MLObjectDetectionManager instance and toggle it here
        // Future enhancement: add a property to track ML detection state
        print("ℹ️ ML detection toggled: \(enabled)")
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraKitController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Process the frame for ML detection
        processFrameForMLDetection(sampleBuffer)
    }
    
    private func processFrameForMLDetection(_ sampleBuffer: CMSampleBuffer) {
        // For now, we'll do inline detection using Vision
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        performObjectDetection(on: pixelBuffer)
    }
    
    private func performObjectDetection(on pixelBuffer: CVPixelBuffer) {
        // Create a Vision request for object classification
        // Note: This is a simplified version using image classification
        // For full object detection with bounding boxes, you'll need a CoreML model
        
        let request = VNClassifyImageRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Classification error: \(error.localizedDescription)")
                return
            }
            
            guard let observations = request.results as? [VNClassificationObservation] else {
                return
            }
            
            // Get top 3 classifications with confidence > 10%
            let topClassifications = observations.prefix(3)
                .filter { $0.confidence > 0.1 }
            
            if !topClassifications.isEmpty {
                self.updateDetectionDisplay(with: topClassifications)
            }
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("❌ Failed to perform classification: \(error)")
            }
        }
    }
    
    private func updateDetectionDisplay(with classifications: [VNClassificationObservation]) {
        DispatchQueue.main.async {
            // Create a string with detected objects
            let detectedObjects = classifications
                .map { "\($0.identifier) (\(Int($0.confidence * 100))%)" }
                .joined(separator: "\n")
            
            // Print to console (you can extend this to update UI if needed)
            if let topObject = classifications.first {
                print("🔍 Detected: \(topObject.identifier) at \(Int(topObject.confidence * 100))%")
            }
            
            // Post notification that other views can listen to
            NotificationCenter.default.post(
                name: Notification.Name("MLDetectionUpdated"),
                object: nil,
                userInfo: ["detections": detectedObjects, "classifications": classifications]
            )
        }
    }
}

// MARK: - ML Detection UI Helper
// To display ML detections in your SwiftUI views, listen to the "MLDetectionUpdated" notification
// Example:
//
// .onReceive(NotificationCenter.default.publisher(for: Notification.Name("MLDetectionUpdated"))) { notification in
//     if let detections = notification.userInfo?["detections"] as? String {
//         // Update your UI with detected objects
//     }
// }
