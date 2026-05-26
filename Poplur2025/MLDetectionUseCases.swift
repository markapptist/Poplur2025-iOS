//
//  MLDetectionUseCases.swift
//  Practical examples of using ML detection in your app
//

import Foundation
import UIKit
import CoreLocation

// MARK: - Use Case 1: Auto-Tagging Posts

/// Automatically tag posts with detected objects
class PostAutoTagger {
    
    private let mlManager = SimplifiedMLDetectionManager()
    
    func setupAutoTagging() {
        mlManager.confidenceThreshold = 0.3 // Only tag high-confidence objects
        mlManager.maxResults = 5 // Get top 5 tags
        
        mlManager.onDetection = { [weak self] objects in
            self?.handleDetectedTags(objects)
        }
    }
    
    private func handleDetectedTags(_ objects: [DetectedObject]) {
        // Convert to hashtags
        let tags = objects.map { "#\($0.identifier.replacingOccurrences(of: " ", with: ""))" }
        
        // Post notification with suggested tags
        NotificationCenter.default.post(
            name: NSNotification.Name("SuggestPostTags"),
            object: nil,
            userInfo: ["tags": tags]
        )
        
        print("📝 Suggested tags: \(tags.joined(separator: " "))")
    }
}

// MARK: - Use Case 2: Smart Location Context

/// Enhance location posts with detected objects
class SmartLocationContext {
    
    private let mlManager = SimplifiedMLDetectionManager()
    
    var currentLocation: CLLocationCoordinate2D?
    var detectedContext: [String] = []
    
    func startContextDetection() {
        mlManager.frameSkipInterval = 10 // Lower frequency for context
        mlManager.confidenceThreshold = 0.4
        
        mlManager.onDetection = { [weak self] objects in
            self?.updateContext(with: objects)
        }
    }
    
    private func updateContext(with objects: [DetectedObject]) {
        // Build context description
        detectedContext = objects.map { $0.identifier }
        
        // Generate smart caption
        if let caption = generateCaption(from: objects) {
            print("💬 Smart caption: \(caption)")
            
            // Post to AI recommendation system
            NotificationCenter.default.post(
                name: NSNotification.Name("UpdateLocationContext"),
                object: nil,
                userInfo: ["caption": caption, "objects": objects]
            )
        }
    }
    
    private func generateCaption(from objects: [DetectedObject]) -> String? {
        guard !objects.isEmpty else { return nil }
        
        let topObject = objects[0].identifier
        
        // Smart captions based on detected objects
        if topObject.contains("food") || topObject.contains("restaurant") {
            return "Great food spot! 🍽"
        } else if topObject.contains("beach") || topObject.contains("ocean") {
            return "Beautiful beach day! 🏖"
        } else if topObject.contains("mountain") || topObject.contains("hiking") {
            return "Amazing views here! ⛰"
        } else if topObject.contains("dog") {
            return "Dog-friendly location! 🐕"
        } else if topObject.contains("coffee") || topObject.contains("cafe") {
            return "Perfect coffee spot! ☕️"
        } else {
            return "Check out this place!"
        }
    }
}

// MARK: - Use Case 3: Content Filtering

/// Filter inappropriate content using ML detection
class ContentFilterManager {
    
    private let mlManager = SimplifiedMLDetectionManager()
    
    var onInappropriateContent: (() -> Void)?
    
    // Flagged content categories
    private let flaggedCategories = ["weapon", "violence", "explicit"]
    
    func startContentMonitoring() {
        mlManager.confidenceThreshold = 0.5
        
        mlManager.onDetection = { [weak self] objects in
            self?.checkContent(objects)
        }
    }
    
    private func checkContent(_ objects: [DetectedObject]) {
        for object in objects {
            if flaggedCategories.contains(where: { object.identifier.lowercased().contains($0) }) {
                print("⚠️ Inappropriate content detected: \(object.identifier)")
                onInappropriateContent?()
                return
            }
        }
    }
}

// MARK: - Use Case 4: Scene Recognition for AI Recommendations

/// Use detected objects to enhance AI recommendations
class SceneBasedRecommendations {
    
    private let mlManager = SimplifiedMLDetectionManager()
    
    var currentScene: SceneType = .unknown
    
    enum SceneType {
        case restaurant
        case outdoor
        case beach
        case urban
        case nature
        case indoor
        case unknown
        
        var recommendation: String {
            switch self {
            case .restaurant:
                return "People love posting food photos here! Capture your meal 📸"
            case .outdoor:
                return "Perfect outdoor lighting for photos! 🌞"
            case .beach:
                return "Beach posts are trending! Share your view 🏖"
            case .urban:
                return "Urban spots are popular! Show the city vibe 🏙"
            case .nature:
                return "Nature content performs well! Capture the beauty 🌳"
            case .indoor:
                return "Indoor shots work great here! Get creative 💡"
            case .unknown:
                return "Explore what's happening around you!"
            }
        }
    }
    
    func startSceneRecognition() {
        mlManager.frameSkipInterval = 8 // Moderate frequency
        mlManager.confidenceThreshold = 0.3
        
        mlManager.onDetection = { [weak self] objects in
            self?.analyzeScene(objects)
        }
    }
    
    private func analyzeScene(_ objects: [DetectedObject]) {
        guard !objects.isEmpty else { return }
        
        let identifiers = objects.map { $0.identifier.lowercased() }
        
        // Determine scene type
        if identifiers.contains(where: { $0.contains("food") || $0.contains("restaurant") || $0.contains("table") }) {
            currentScene = .restaurant
        } else if identifiers.contains(where: { $0.contains("beach") || $0.contains("ocean") || $0.contains("sand") }) {
            currentScene = .beach
        } else if identifiers.contains(where: { $0.contains("tree") || $0.contains("grass") || $0.contains("forest") }) {
            currentScene = .nature
        } else if identifiers.contains(where: { $0.contains("building") || $0.contains("street") || $0.contains("car") }) {
            currentScene = .urban
        } else if identifiers.contains(where: { $0.contains("sky") || $0.contains("cloud") }) {
            currentScene = .outdoor
        } else {
            currentScene = .indoor
        }
        
        // Update AI recommendation
        updateRecommendation()
    }
    
    private func updateRecommendation() {
        NotificationCenter.default.post(
            name: NSNotification.Name("UpdateAIRecommendation"),
            object: nil,
            userInfo: [
                "scene": currentScene,
                "recommendation": currentScene.recommendation
            ]
        )
    }
}

// MARK: - Use Case 5: Object-Based Search

/// Enable searching for posts by detected objects
class ObjectBasedSearch {
    
    private let mlManager = SimplifiedMLDetectionManager()
    
    var searchableObjects: Set<String> = []
    
    func startObjectTracking() {
        mlManager.frameSkipInterval = 15 // Lower frequency, just building index
        mlManager.confidenceThreshold = 0.4
        
        mlManager.onDetection = { [weak self] objects in
            self?.indexObjects(objects)
        }
    }
    
    private func indexObjects(_ objects: [DetectedObject]) {
        // Add to searchable objects
        for object in objects {
            searchableObjects.insert(object.identifier)
        }
        
        print("📚 Indexed objects: \(searchableObjects.count) unique categories")
    }
    
    func search(query: String) -> Bool {
        return searchableObjects.contains { $0.lowercased().contains(query.lowercased()) }
    }
}

// MARK: - Use Case 6: Location-Specific Object Detection

/// Detect location-specific objects and suggest related content
class LocationSpecificDetection {
    
    private let mlManager = SimplifiedMLDetectionManager()
    
    var currentCity: String?
    
    // City-specific trending objects
    private let cityTrends: [String: [String]] = [
        "San Francisco": ["Golden Gate Bridge", "cable car", "hills"],
        "New York": ["taxi", "skyscraper", "subway"],
        "Los Angeles": ["palm tree", "beach", "Hollywood"],
        "Miami": ["beach", "art deco", "ocean"]
    ]
    
    func startLocationAwareDetection(city: String) {
        currentCity = city
        
        mlManager.onDetection = { [weak self] objects in
            self?.checkLocationRelevance(objects)
        }
    }
    
    private func checkLocationRelevance(_ objects: [DetectedObject]) {
        guard let city = currentCity,
              let trendingObjects = cityTrends[city] else { return }
        
        // Check if detected objects match city trends
        for object in objects {
            for trend in trendingObjects {
                if object.identifier.lowercased().contains(trend.lowercased()) {
                    print("🎯 Detected trending object in \(city): \(object.identifier)")
                    
                    // Boost recommendation
                    NotificationCenter.default.post(
                        name: NSNotification.Name("DetectedTrendingObject"),
                        object: nil,
                        userInfo: ["object": object.identifier, "city": city]
                    )
                }
            }
        }
    }
}

// MARK: - Use Case 7: Smart Camera Hints

/// Provide real-time hints to improve photos
class SmartCameraHints {
    
    private let mlManager = SimplifiedMLDetectionManager()
    
    var onHint: ((String) -> Void)?
    
    func startHintSystem() {
        mlManager.frameSkipInterval = 6
        mlManager.confidenceThreshold = 0.35
        
        mlManager.onDetection = { [weak self] objects in
            self?.generateHint(for: objects)
        }
    }
    
    private func generateHint(for objects: [DetectedObject]) {
        guard let topObject = objects.first else { return }
        
        let hint: String
        
        // Object-specific photography hints
        switch topObject.identifier.lowercased() {
        case let id where id.contains("person"):
            hint = "💡 Tip: Try portrait mode for better depth!"
        case let id where id.contains("food"):
            hint = "💡 Tip: Get closer and use natural light!"
        case let id where id.contains("building"):
            hint = "💡 Tip: Try a lower angle for dramatic effect!"
        case let id where id.contains("sunset") || id.contains("sky"):
            hint = "💡 Tip: Enable HDR for better colors!"
        case let id where id.contains("pet") || id.contains("dog") || id.contains("cat"):
            hint = "💡 Tip: Get down to eye level!"
        default:
            hint = "💡 Tip: Make sure your subject is well-lit!"
        }
        
        onHint?(hint)
    }
}

// MARK: - Integration Example

/// Complete example showing how to use these features together
class ComprehensiveMLIntegration {
    
    private let autoTagger = PostAutoTagger()
    private let locationContext = SmartLocationContext()
    private let sceneRecognition = SceneBasedRecommendations()
    private let cameraHints = SmartCameraHints()
    
    func setupAllFeatures() {
        // Setup auto-tagging
        autoTagger.setupAutoTagging()
        
        // Setup location context
        locationContext.startContextDetection()
        
        // Setup scene recognition
        sceneRecognition.startSceneRecognition()
        
        // Setup camera hints
        cameraHints.startHintSystem()
        cameraHints.onHint = { hint in
            print(hint)
            // Show hint in UI
        }
        
        // Listen for recommendations
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("UpdateAIRecommendation"),
            object: nil,
            queue: .main
        ) { notification in
            if let recommendation = notification.userInfo?["recommendation"] as? String {
                print("🤖 AI: \(recommendation)")
            }
        }
    }
}
