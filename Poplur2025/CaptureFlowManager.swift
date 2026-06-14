//
//  CaptureFlowManager.swift
//  Poplur2025
//
//  Created on 2025-05-09.
//

import SwiftUI
import CoreLocation

/// Manages the two different post capture flows in the app
enum CaptureFlow {
    /// Flow 1: Map Tab -> Select coordinate -> Camera -> Capture -> Preview -> Post to selected location
    case mapToCamera(coordinate: CLLocationCoordinate2D)
    
    /// Flow 2: Camera Tab -> Capture -> Preview -> Map -> Select coordinate -> Post
    case cameraToMap
    
    var isMapFirst: Bool {
        if case .mapToCamera = self {
            return true
        }
        return false
    }
    
    var isCameraFirst: Bool {
        if case .cameraToMap = self {
            return true
        }
        return false
    }
    
    var preselectedCoordinate: CLLocationCoordinate2D? {
        if case .mapToCamera(let coordinate) = self {
            return coordinate
        }
        return nil
    }
}

/// Observable object to manage capture flow state across views
final class CaptureFlowManager: ObservableObject {
    static let shared = CaptureFlowManager()
    
    @Published var currentFlow: CaptureFlow?
    @Published var capturedImage: UIImage?
    @Published var capturedVideoURL: URL?
    
    private init() {}
    
    /// Start Map -> Camera flow: user clicked a coordinate on map and wants to post there
    func startMapToCameraFlow(coordinate: CLLocationCoordinate2D) {
        currentFlow = .mapToCamera(coordinate: coordinate)
        capturedImage = nil
        capturedVideoURL = nil
        print("📍 [CaptureFlowManager] Started Map -> Camera flow at: \(coordinate.latitude), \(coordinate.longitude)")
    }
    
    /// Start Camera -> Map flow: user captured in camera and needs to select location
    func startCameraToMapFlow(image: UIImage?, videoURL: URL?) {
        currentFlow = .cameraToMap
        capturedImage = image
        capturedVideoURL = videoURL
        print("📸 [CaptureFlowManager] Started Camera -> Map flow with \(image != nil ? "image" : "video")")
    }
    
    /// Complete the flow and post to the final coordinate
    func completeFlow(finalCoordinate: CLLocationCoordinate2D) {
        guard currentFlow != nil else {
            print("❌ [CaptureFlowManager] No active flow to complete")
            return
        }

        print("✅ [CaptureFlowManager] Completing flow with final coordinate: \(finalCoordinate.latitude), \(finalCoordinate.longitude)")
        
        // Post notification to upload the media
        var userInfo: [String: Any] = [
            "latitude": finalCoordinate.latitude,
            "longitude": finalCoordinate.longitude
        ]
        
        if let image = capturedImage {
            userInfo["image"] = image
        }
        
        if let videoURL = capturedVideoURL {
            userInfo["videoURL"] = videoURL
        }
        
        NotificationCenter.default.post(
            name: Notification.Name("UploadPostToCoordinate"),
            object: nil,
            userInfo: userInfo
        )
        
        // Show success notification
        NotificationCenter.default.post(
            name: Notification.Name("PostUploadStarted"),
            object: nil,
            userInfo: [
                "message": "Uploading your post...",
                "coordinate": finalCoordinate
            ]
        )
        
        // Reset flow
        reset()
    }
    
    /// Cancel the current flow
    func cancelFlow() {
        print("🚫 [CaptureFlowManager] Canceling flow")
        reset()
    }
    
    /// Reset all state
    private func reset() {
        currentFlow = nil
        capturedImage = nil
        capturedVideoURL = nil
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when user taps "Post Here" button in map after selecting coordinate
    /// Flow 1 (Map -> Camera): Opens camera at selected coordinate
    /// Flow 2 (Camera -> Map): Completes upload to selected coordinate
    static let postToSelectedCoordinate = Notification.Name("PostToSelectedCoordinate")
    
    /// Posted when capture is complete in camera and needs location selection
    static let captureNeedsLocation = Notification.Name("CaptureNeedsLocation")
    
    /// Posted when a post upload has started
    static let postUploadStarted = Notification.Name("PostUploadStarted")
    
    /// Posted when a post upload completes successfully
    static let postUploadSuccess = Notification.Name("PostUploadSuccess")
    
    /// Posted when a post upload fails
    static let postUploadFailed = Notification.Name("PostUploadFailed")
}
