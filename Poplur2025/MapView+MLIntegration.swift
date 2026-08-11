//
//  MapView+MLIntegration.swift
//  Connect ML detection with your MapView AI recommendations
//

import Foundation
import MapKit
import CoreLocation
import SwiftUI
import Combine
import Vision

// MARK: - ML Integration Helper (ObservableObject for SwiftUI)

/// ObservableObject that manages ML integration state for MapView
class MapMLIntegrationManager: ObservableObject {
    
    static let shared = MapMLIntegrationManager()
    
    @Published var currentRecommendation: String = "Explore what's happening around you right now!"
    @Published var detectedObjects: [DetectedObject] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupNotificationHandlers()
    }
    
    /// Setup notification listeners for ML detections
    private func setupNotificationHandlers() {
        // Listen for ML detections from camera
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MLDetectionUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            // Handle Vision framework detections (VNClassificationObservation)
            if let classifications = notification.userInfo?["classifications"] as? [VNClassificationObservation] {
                let objects = classifications.map { observation in
                    DetectedObject(
                        identifier: observation.identifier,
                        confidence: observation.confidence
                    )
                }
                self.handleMLDetections(objects, userLocation: nil)
            }
        }
        
        // Also listen for custom DetectedObject format
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MLObjectsDetected"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let objects = notification.userInfo?["objects"] as? [DetectedObject] else { return }
            
            self.handleMLDetections(objects, userLocation: nil)
        }
    }
    
    /// Handle ML detections and update recommendations
    func handleMLDetections(_ objects: [DetectedObject], userLocation: CLLocationCoordinate2D?) {
        // Update stored detections
        detectedObjects = objects
        
        // Generate context-aware AI recommendation
        let recommendation = generateRecommendation(for: objects, at: userLocation)
        
        // Update recommendation state
        currentRecommendation = recommendation
        
        // Store detection metadata
        storeDetectionMetadata(objects, at: userLocation)
        
        // Update ML metadata singleton
        MLPostMetadata.shared.updateDetections(objects)
        
        print("🤖 ML Integration: \(recommendation)")
    }
    
    /// Generate AI recommendation based on detected objects
    func generateRecommendation(for objects: [DetectedObject], at location: CLLocationCoordinate2D?) -> String {
        guard !objects.isEmpty else {
            return "Explore what's happening around you right now!"
        }
        
        let topObject = objects[0]
        let identifier = topObject.identifier.lowercased()
        
        // Scene-specific recommendations
        if identifier.contains("food") || identifier.contains("restaurant") || identifier.contains("pizza") || identifier.contains("burger") {
            return "🍽 Food spot detected! People love sharing food pics here — capture your meal!"
        } else if identifier.contains("beach") || identifier.contains("ocean") || identifier.contains("sand") {
            return "🏖 Beach vibes detected! Perfect for a stunning sunset or ocean shot!"
        } else if identifier.contains("dog") || identifier.contains("pet") {
            return "🐕 Dog-friendly spot! Pet posts are trending — share your furry friend!"
        } else if identifier.contains("coffee") || identifier.contains("cafe") {
            return "☕️ Cozy cafe detected! Coffee and ambiance shots work great here!"
        } else if identifier.contains("building") || identifier.contains("architecture") || identifier.contains("bridge") {
            return "🏙 Urban architecture detected! Capture the city's character!"
        } else if identifier.contains("tree") || identifier.contains("forest") || identifier.contains("nature") {
            return "🌳 Nature spot detected! Outdoor content performs well here!"
        } else if identifier.contains("mountain") || identifier.contains("hiking") {
            return "⛰ Scenic views detected! Share the breathtaking landscape!"
        } else if identifier.contains("sunset") || identifier.contains("sky") {
            return "🌅 Beautiful sky detected! Golden hour is perfect for photos!"
        } else if identifier.contains("person") {
            return "📸 Great spot for portraits! Lighting looks perfect for people photos!"
        } else {
            // Generic but personalized
            let emoji = getEmojiForObject(identifier)
            return "\(emoji) \(topObject.identifier.capitalized) detected! This would make a great post!"
        }
    }
    
    /// Store detection metadata for future use
    private func storeDetectionMetadata(_ objects: [DetectedObject], at location: CLLocationCoordinate2D?) {
        var metadata: [String: Any] = [
            "detectedObjects": objects.map { ["identifier": $0.identifier, "confidence": $0.confidence] },
            "timestamp": Date().timeIntervalSince1970
        ]
        
        if let location = location {
            metadata["location"] = ["latitude": location.latitude, "longitude": location.longitude]
        }
        
        // Store for post creation
        UserDefaults.standard.set(metadata, forKey: "lastMLDetectionMetadata")
        
        print("💾 Stored detection metadata: \(objects.map { $0.identifier }.joined(separator: ", "))")
    }
    
    /// Get emoji for detected object
    private func getEmojiForObject(_ identifier: String) -> String {
        let lowercased = identifier.lowercased()
        
        if lowercased.contains("dog") { return "🐕" }
        if lowercased.contains("cat") { return "🐈" }
        if lowercased.contains("bird") { return "🐦" }
        if lowercased.contains("person") { return "👤" }
        if lowercased.contains("car") { return "🚗" }
        if lowercased.contains("phone") { return "📱" }
        if lowercased.contains("food") { return "🍔" }
        if lowercased.contains("coffee") { return "☕️" }
        if lowercased.contains("tree") { return "🌳" }
        if lowercased.contains("flower") { return "🌸" }
        if lowercased.contains("building") { return "🏢" }
        if lowercased.contains("beach") { return "🏖" }
        if lowercased.contains("mountain") { return "⛰" }
        if lowercased.contains("sky") { return "☁️" }
        
        return "✨"
    }
}

// MARK: - Post Creation with ML Metadata

/// Helper to attach ML detection data to posts
class MLPostMetadata {
    
    static let shared = MLPostMetadata()
    
    private var currentDetections: [DetectedObject] = []
    
    /// Update current detections from camera
    func updateDetections(_ objects: [DetectedObject]) {
        currentDetections = objects
    }
    
    /// Get auto-generated tags based on detections
    func getAutoTags() -> [String] {
        return currentDetections
            .filter { $0.confidence > 0.3 } // Only high-confidence objects
            .map { "#\($0.identifier.replacingOccurrences(of: " ", with: ""))" }
    }
    
    /// Get smart caption suggestion
    func getSmartCaption(for location: String?) -> String {
        guard !currentDetections.isEmpty else {
            return "Check out this place!"
        }
        
        let topObject = currentDetections[0].identifier.lowercased()
        
        if topObject.contains("food") {
            return location.map { "Great food at \($0)! 🍽" } ?? "Delicious! 🍽"
        } else if topObject.contains("beach") {
            return location.map { "Beach day at \($0)! 🏖" } ?? "Beach vibes! 🏖"
        } else if topObject.contains("dog") {
            return location.map { "Dog-friendly spot at \($0)! 🐕" } ?? "Puppy love! 🐕"
        } else if topObject.contains("coffee") {
            return location.map { "Coffee time at \($0)! ☕️" } ?? "Coffee break! ☕️"
        } else {
            return location.map { "At \($0)" } ?? "Check this out!"
        }
    }
    
    /// Get detection summary for analytics
    func getDetectionSummary() -> [String: Any] {
        return [
            "objectCount": currentDetections.count,
            "objects": currentDetections.map { $0.identifier },
            "topConfidence": currentDetections.first?.confidence ?? 0,
            "timestamp": Date().timeIntervalSince1970
        ]
    }
}

// MARK: - Integration with Posting Flow

extension Notification.Name {
    static let mlDetectionReady = Notification.Name("MLDetectionReady")
    static let attachMLMetadata = Notification.Name("AttachMLMetadata")
}

/// Example integration with your posting flow
class PostCreationWithML {
    
    /// When user takes a photo, attach ML metadata
    func handlePhotoCapture(_ image: UIImage, at coordinate: CLLocationCoordinate2D) {
        // Get ML metadata
        let tags = MLPostMetadata.shared.getAutoTags()
        let caption = MLPostMetadata.shared.getSmartCaption(for: nil)
        let summary = MLPostMetadata.shared.getDetectionSummary()
        
        print("📝 Auto-generated tags: \(tags.joined(separator: " "))")
        print("💬 Suggested caption: \(caption)")
        print("📊 Detection summary: \(summary)")
        
        // Create post with ML data
        let postData: [String: Any] = [
            "image": image,
            "coordinate": coordinate,
            "tags": tags,
            "suggestedCaption": caption,
            "mlMetadata": summary,
            "timestamp": Date()
        ]
        
        // Post to your backend or local storage
        NotificationCenter.default.post(
            name: .attachMLMetadata,
            object: nil,
            userInfo: postData
        )
    }
}

// MARK: - Complete Integration Example

/// Shows how to tie everything together
class CompleteMLMapIntegration {
    
    private let mlManager = SimplifiedMLDetectionManager()
    private var currentLocation: CLLocationCoordinate2D?
    private var locationObserver: NSObjectProtocol?

    deinit {
        if let locationObserver {
            NotificationCenter.default.removeObserver(locationObserver)
        }
    }
    
    func setup() {
        // Configure ML detection
        mlManager.confidenceThreshold = 0.25
        mlManager.frameSkipInterval = 5
        mlManager.maxResults = 3
        
        // Handle detections - explicitly type the closure parameter
        mlManager.onDetection = { [weak self] (objects: [DetectedObject]) in
            self?.handleDetection(objects)
        }
        
        // Listen for location updates
        if let locationObserver {
            NotificationCenter.default.removeObserver(locationObserver)
        }
        locationObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LocationUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let location = notification.userInfo?["coordinate"] as? CLLocationCoordinate2D {
                self?.currentLocation = location
            }
        }
    }
    
    private func handleDetection(_ objects: [DetectedObject]) {
        // Update metadata
        MLPostMetadata.shared.updateDetections(objects)
        
        // Post ML detection event
        NotificationCenter.default.post(
            name: NSNotification.Name("MLObjectsDetected"),
            object: nil,
            userInfo: ["objects": objects]
        )
        
        // Log for analytics
        print("🔍 ML Detection: \(objects.map { "\($0.identifier) (\($0.confidencePercentage)%)" }.joined(separator: ", "))")
        
        // Check for location-specific patterns
        if let location = currentLocation {
            checkLocationSpecificPatterns(objects: objects, at: location)
        }
    }
    
    private func checkLocationSpecificPatterns(objects: [DetectedObject], at location: CLLocationCoordinate2D) {
        // Example: Beach detection near coastlines
        let hasWaterObjects = objects.contains { 
            $0.identifier.lowercased().contains("beach") || 
            $0.identifier.lowercased().contains("ocean")
        }
        
        if hasWaterObjects {
            print("🏖 Beach pattern detected at \(location.latitude), \(location.longitude)")
            
            // Boost beach-related recommendations
            NotificationCenter.default.post(
                name: NSNotification.Name("BoostRecommendation"),
                object: nil,
                userInfo: ["pattern": "beach", "location": location]
            )
        }
    }
}

// MARK: - Usage in MapView (SwiftUI)

/*
 How to use in your MapViewProduction:
 
 1. Add @StateObject to your view:
    @StateObject private var mlIntegration = MapMLIntegrationManager.shared
 
 2. Listen for ML recommendation updates in your view:
    .onReceive(mlIntegration.$currentRecommendation) { recommendation in
        // Update your AI text when ML detections occur
        if !mlIntegration.detectedObjects.isEmpty {
            self.aiRecommendation = recommendation
        }
    }
 
 3. Alternative: Use the global singleton directly without @StateObject:
    Text(MapMLIntegrationManager.shared.currentRecommendation)
 
 4. When creating a post:
    let tags = MLPostMetadata.shared.getAutoTags()
    let caption = MLPostMetadata.shared.getSmartCaption(for: currentCity)
    
 5. Integration with camera flow:
    - User opens camera from map location
    - Camera detects objects in real-time via CameraKitController+MLDetection
    - ML detections posted via NotificationCenter "MLDetectionUpdated"
    - MapMLIntegrationManager receives and processes detections
    - Map AI recommendation updates automatically
    - Post created with smart tags and caption from MLPostMetadata
 
 EXAMPLE:
 
 struct MapViewProduction: View {
     @StateObject private var mlIntegration = MapMLIntegrationManager.shared
     @State private var aiRecommendation: String = "Explore what's around you!"
     
     var body: some View {
         Map()
             .overlay(alignment: .top) {
                 Text(aiRecommendation)
                     .padding()
                     .background(.ultraThinMaterial)
             }
             .onReceive(mlIntegration.$currentRecommendation) { recommendation in
                 // Automatically update when ML detects objects
                 if !mlIntegration.detectedObjects.isEmpty {
                     aiRecommendation = recommendation
                 }
             }
     }
 }
 
 */

// MARK: - Example: Complete Flow

/*
 COMPLETE FLOW EXAMPLE:
 
 1. User views map at Golden Gate Park
    → Map shows: "Explore what's happening around you!"
 
 2. User opens camera
    → Camera enables ML detection
    → Detects: dog, tree, grass
 
 3. ML system updates recommendation
    → Map shows: "🐕 Dog-friendly spot! Pet posts are trending!"
 
 4. User takes photo
    → Auto-tags: #dog #tree #grass
    → Suggested caption: "Dog-friendly spot at Golden Gate Park! 🐕"
    → ML metadata attached
 
 5. Post created with intelligence
    → Location: Golden Gate Park
    → Tags: #dog #tree #grass
    → Caption: "Dog-friendly spot at Golden Gate Park! 🐕"
    → Metadata: { objectCount: 3, topConfidence: 0.87, ... }
 
 6. Other users see enhanced content
    → Search works better (can find by #dog)
    → AI recommendations improve
    → Location patterns emerge
 */
