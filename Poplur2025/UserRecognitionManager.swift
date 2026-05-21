//
//  UserRecognitionManager.swift
//  User face recognition and profile matching
//

import Foundation
import Vision
import CoreImage
import UIKit
import FirebaseFirestore
import FirebaseAuth

/// Manages user face recognition and profile matching
@MainActor
class UserRecognitionManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Currently recognized user in the camera view
    @Published var recognizedUser: RecognizedUser?
    
    /// Whether recognition is actively running
    @Published var isRecognizing: Bool = false
    
    // MARK: - Private Properties
    
    private let db = Firestore.firestore()
    private var faceDetectionRequest: VNDetectFaceRectanglesRequest?
    private var cachedUserProfiles: [String: UserProfile] = [:]
    private var lastRecognitionTime: Date = .distantPast
    
    // Minimum time between recognition attempts (prevents spam)
    private let recognitionCooldown: TimeInterval = 0.5
    
    // MARK: - Initialization
    
    init() {
        setupFaceDetection()
    }
    
    // MARK: - Setup
    
    private func setupFaceDetection() {
        faceDetectionRequest = VNDetectFaceRectanglesRequest { [weak self] request, error in
            guard let self = self else { return }
            
            if let error = error {
                print("❌ Face detection error: \(error.localizedDescription)")
                return
            }
            
            guard let results = request.results as? [VNFaceObservation] else {
                return
            }
            
            Task { @MainActor in
                await self.processFaceDetections(results)
            }
        }
        
        // Configure for better face detection
        faceDetectionRequest?.revision = VNDetectFaceRectanglesRequestRevision3
    }
    
    // MARK: - Public Methods
    
    /// Process detected objects to find users
    func processDetectedObjects(_ objects: [DetectedObject], from pixelBuffer: CVPixelBuffer?) {
        guard Date().timeIntervalSince(lastRecognitionTime) > recognitionCooldown else {
            return
        }
        
        // Check if any object is a person
        let hasPerson = objects.contains { object in
            let identifier = object.identifier.lowercased()
            return identifier.contains("person") || 
                   identifier.contains("face") ||
                   identifier.contains("human")
        }
        
        guard hasPerson else {
            // No person detected, clear recognized user
            if recognizedUser != nil {
                recognizedUser = nil
            }
            return
        }
        
        // If we have a pixel buffer, try face detection
        if let buffer = pixelBuffer {
            detectFaces(in: buffer)
        }
    }
    
    /// Detect faces in the camera frame
    func detectFaces(in pixelBuffer: CVPixelBuffer) {
        guard let request = faceDetectionRequest else { return }
        
        isRecognizing = true
        lastRecognitionTime = Date()
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
            } catch {
                print("❌ Failed to perform face detection: \(error)")
                Task { @MainActor in
                    self.isRecognizing = false
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func processFaceDetections(_ faces: [VNFaceObservation]) async {
        defer { isRecognizing = false }
        
        guard !faces.isEmpty else {
            recognizedUser = nil
            return
        }
        
        // Get the most prominent face (largest bounding box)
        guard let primaryFace = faces.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else {
            return
        }
        
        // In a real implementation, you would:
        // 1. Extract face features/encoding from primaryFace
        // 2. Compare against stored user face encodings in database
        // 3. Match to specific user
        
        // For now, we'll simulate user recognition by checking nearby users
        await recognizeNearbyUser()
    }
    
    /// Attempt to recognize a nearby user
    /// In production, this would use face encoding matching
    private func recognizeNearbyUser() async {
        // TODO: Replace this with actual face matching logic
        // For now, we'll check if there are any nearby users from the feed
        
        // Simulate recognition by checking recent user interactions
        // In reality, you'd compare face encodings here
        
        do {
            // Example: Get users who have posted nearby
            let snapshot = try await db.collection("posts")
                .order(by: "timestamp", descending: true)
                .limit(to: 10)
                .getDocuments()
            
            // For demo purposes, take the first user
            // In production, this would be based on face matching
            if let firstDoc = snapshot.documents.first,
               let userID = firstDoc.data()["userID"] as? String {
                
                // Fetch user profile
                if let profile = cachedUserProfiles[userID] {
                    updateRecognizedUser(profile)
                } else {
                    let userProfile = try await fetchUserProfile(userID: userID)
                    cachedUserProfiles[userID] = userProfile
                    updateRecognizedUser(userProfile)
                }
            }
        } catch {
            print("❌ Error recognizing user: \(error.localizedDescription)")
        }
    }
    
    /// Fetch user profile from Firestore
    private func fetchUserProfile(userID: String) async throws -> UserProfile {
        let userDoc = try await db.collection("users").document(userID).getDocument()
        
        guard let data = userDoc.data() else {
            throw NSError(domain: "UserRecognition", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        let username = data["username"] as? String ?? "Unknown"
        let radiusMeters = data["radius"] as? Double ?? 0
        let profileImageURL = data["profileImageURL"] as? String
        
        return UserProfile(
            userID: userID,
            username: username,
            radiusMeters: radiusMeters,
            profileImageURL: profileImageURL
        )
    }
    
    private func updateRecognizedUser(_ profile: UserProfile) {
        recognizedUser = RecognizedUser(
            profile: profile,
            detectedAt: Date(),
            confidence: 0.85 // Placeholder - would come from face matching
        )
        
        print("👤 Recognized user: @\(profile.username) with \(Int(profile.radiusMeters))m radius")
        
        // Post notification for other parts of app
        NotificationCenter.default.post(
            name: NSNotification.Name("UserRecognizedInCamera"),
            object: nil,
            userInfo: [
                "userID": profile.userID,
                "username": profile.username,
                "radius": profile.radiusMeters
            ]
        )
    }
    
    /// Clear recognition when no face is detected
    func clearRecognition() {
        if recognizedUser != nil {
            recognizedUser = nil
            print("👤 User recognition cleared")
        }
    }
}

// MARK: - Supporting Types

/// User profile information
struct UserProfile: Codable, Identifiable {
    let userID: String
    let username: String
    let radiusMeters: Double
    let profileImageURL: String?
    
    var id: String { userID }
    
    var formattedRadius: String {
        let usesMetric = Locale.current.usesMetricSystem
        
        if usesMetric {
            if radiusMeters >= 1000 {
                return String(format: "%.1f km", radiusMeters / 1000)
            } else {
                return "\(Int(radiusMeters)) m"
            }
        } else {
            let miles = radiusMeters * 0.000621371
            if miles >= 1 {
                return String(format: "%.1f mi", miles)
            } else {
                let feet = radiusMeters * 3.28084
                return "\(Int(feet)) ft"
            }
        }
    }
}

/// Recognized user with detection metadata
struct RecognizedUser: Identifiable {
    let profile: UserProfile
    let detectedAt: Date
    let confidence: Float
    
    var id: String { profile.userID }
    
    var isRecent: Bool {
        Date().timeIntervalSince(detectedAt) < 3.0
    }
}

// MARK: - Notification Names

extension NSNotification.Name {
    static let UserRecognizedInCamera = NSNotification.Name("UserRecognizedInCamera")
}
