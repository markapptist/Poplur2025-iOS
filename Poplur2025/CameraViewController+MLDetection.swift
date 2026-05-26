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
    
    /// Enable/disable ML object detection
    /// Note: This uses the SimplifiedMLDetectionManager configured in the main class
    public func toggleMLDetection(enabled: Bool) {
        Task { @MainActor in
            self.isMLDetectionEnabled = enabled
            print("ℹ️ ML detection toggled: \(enabled)")
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
