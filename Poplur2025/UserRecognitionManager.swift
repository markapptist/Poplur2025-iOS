//
//  UserRecognitionManager.swift
//  User face recognition and profile matching
//

import Foundation
@preconcurrency import Vision
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

    /// Normalized Vision face bounds for the recognized user.
    @Published var recognizedFaceBounds: CGRect?
    
    /// Whether recognition is actively running
    @Published var isRecognizing: Bool = false
    
    // MARK: - Private Properties
    
    private let db = Firestore.firestore()
    private var faceDetectionRequest: VNDetectFaceRectanglesRequest?
    private var cachedUserProfiles: [String: UserProfile] = [:]
    private var lastRecognitionTime: Date = .distantPast
    private var savedFaceImage: UIImage?
    private var savedFaceObservation: VNFaceObservation?
    
    // Minimum time between recognition attempts (prevents spam)
    private let recognitionCooldown: TimeInterval = 0.5
    
    // MARK: - Initialization
    
    init() {
        setupFaceDetection()
        loadSavedFaceImage()
        setupNotificationObserver()
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
    
    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: Notification.Name("FaceImageUpdatedForML"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let image = userInfo["image"] as? UIImage else { return }
            
            Task { @MainActor in
                await self.processSavedFaceImage(image)
            }
        }
    }
    
    private func loadSavedFaceImage() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("face_recognition.jpg")
        
        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            Task { @MainActor in
                await self.processSavedFaceImage(image)
            }
        } else {
            print("ℹ️ No saved face image found for recognition")
        }
    }
    
    private func processSavedFaceImage(_ image: UIImage) async {
        guard let cgImage = image.cgImage else {
            print("❌ Failed to get CGImage from saved face image")
            return
        }
        
        // Detect face in the saved image to get face observation for comparison
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        
        do {
            try handler.perform([request])
            
            if let faceObservations = request.results as? [VNFaceObservation],
               let firstFace = faceObservations.first {
                self.savedFaceImage = image
                self.savedFaceObservation = firstFace
                print("✅ Saved face image loaded and processed for recognition")
                print("   Face bounds: \(firstFace.boundingBox)")
            } else {
                print("⚠️ No face detected in saved image")
            }
        } catch {
            print("❌ Failed to detect face in saved image: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Public Methods
    
    /// Start recognition session and load current user's radius
    func startRecognitionSession() async {
        guard let currentUserID = Auth.auth().currentUser?.uid else {
            print("⚠️ Cannot start recognition - no user logged in")
            return
        }
        
        // Pre-load current user's radius so it's ready when face is detected
        do {
            let userDoc = try await db.collection("users").document(currentUserID).getDocument()
            if let radiusMeters = userDoc.data()?["radius"] as? Double {
                print("✅ Pre-loaded current user radius: \(Int(radiusMeters))m")
                // Cache it for instant display on recognition
                NotificationCenter.default.post(
                    name: Notification.Name("CachedUserRadius"),
                    object: nil,
                    userInfo: ["radius": radiusMeters]
                )
            }
        } catch {
            print("❌ Failed to pre-load user radius: \(error.localizedDescription)")
        }
    }
    
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
            recognizedFaceBounds = nil
            return
        }
        
        // Get the most prominent face (largest bounding box)
        guard let primaryFace = faces.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) else {
            return
        }
        
        // Check if we have a saved face to compare against
        guard savedFaceImage != nil, savedFaceObservation != nil else {
            print("ℹ️ No saved face image - cannot perform recognition")
            recognizedUser = nil
            return
        }
        
        // Compare the detected face with the saved face
        let similarity = compareFaces(detected: primaryFace, saved: savedFaceObservation!)
        
        print("👤 Face similarity: \(String(format: "%.2f", similarity * 100))%")
        
        // If similarity is high enough, recognize as the current user
        if similarity > 0.7 {  // 70% similarity threshold
            recognizedFaceBounds = primaryFace.boundingBox
            await recognizeCurrentUser(confidence: Float(similarity))
        } else {
            recognizedUser = nil
            recognizedFaceBounds = nil
        }
    }
    
    /// Compare two face observations for similarity
    private func compareFaces(detected: VNFaceObservation, saved: VNFaceObservation) -> Double {
        // Simple comparison based on face bounds and aspect ratio
        // In production, you'd use VNFaceObservation features or a custom ML model
        
        let detectedBounds = detected.boundingBox
        let savedBounds = saved.boundingBox
        
        // Compare aspect ratios
        let detectedAspect = detectedBounds.width / detectedBounds.height
        let savedAspect = savedBounds.width / savedBounds.height
        let aspectDiff = abs(detectedAspect - savedAspect)
        
        // Lower difference = higher similarity
        // Convert to 0-1 range where 1 is perfect match
        let aspectSimilarity = max(0, 1.0 - (aspectDiff * 2))
        
        // Compare size (normalized)
        let detectedSize = detectedBounds.width * detectedBounds.height
        let savedSize = savedBounds.width * savedBounds.height
        let sizeDiff = abs(detectedSize - savedSize) / max(detectedSize, savedSize)
        let sizeSimilarity = max(0, 1.0 - sizeDiff)
        
        // Combined similarity score
        let similarity = (aspectSimilarity * 0.6 + sizeSimilarity * 0.4)
        
        return similarity
    }
    
    /// Recognize the current user (whose face is saved)
    private func recognizeCurrentUser(confidence: Float) async {
        guard let currentUserID = Auth.auth().currentUser?.uid else {
            print("⚠️ No current user logged in")
            return
        }
        
        do {
            // Fetch current user's profile
            if let cachedProfile = cachedUserProfiles[currentUserID] {
                // Fetch radius from Firestore
                let userDoc = try await db.collection("users").document(currentUserID).getDocument()
                let radiusMeters = userDoc.data()?["radius"] as? Double ?? 5000.0
                updateRecognizedUser(cachedProfile, radius: radiusMeters, confidence: confidence)
            } else {
                let result = try await fetchUserProfile(userID: currentUserID)
                cachedUserProfiles[currentUserID] = result.profile
                updateRecognizedUser(result.profile, radius: result.radius, confidence: confidence)
            }
        } catch {
            print("❌ Error fetching current user profile: \(error.localizedDescription)")
        }
    }
    
    
    /// Fetch user profile from Firestore
    private func fetchUserProfile(userID: String) async throws -> (profile: UserProfile, radius: Double) {
        let userDoc = try await db.collection("users").document(userID).getDocument()
        
        guard let data = userDoc.data() else {
            throw NSError(domain: "UserRecognition", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        let username = data["username"] as? String ?? "Unknown"
        let email = data["email"] as? String ?? ""
        let radiusMeters = data["radius"] as? Double ?? 5000.0
        let profileImageURLString = data["profileImageURL"] as? String
        let profilePictureURL = profileImageURLString.flatMap { URL(string: $0) }
        
        let profile = UserProfile(
            id: userID,
            username: username,
            email: email,
            profilePictureURL: profilePictureURL
        )
        
        return (profile, radiusMeters)
    }
    
    private func updateRecognizedUser(_ profile: UserProfile, radius: Double, confidence: Float = 0.85) {
        recognizedUser = RecognizedUser(
            profile: profile,
            detectedAt: Date(),
            confidence: confidence,
            radiusMeters: radius
        )
        
        print("👤 Recognized user: @\(profile.username) with \(Int(radius))m radius (confidence: \(Int(confidence * 100))%)")
        
        // Post notification for other parts of app
        NotificationCenter.default.post(
            name: NSNotification.Name("UserRecognizedInCamera"),
            object: nil,
            userInfo: [
                "userID": profile.id,
                "username": profile.username,
                "radius": radius,
                "confidence": confidence
            ]
        )
        
        // Update radius bar to show the recognized user's radius
        NotificationCenter.default.post(
            name: Notification.Name("currentPostRadiusDidChange"),
            object: nil,
            userInfo: ["radius": radius]
        )
    }
    
    /// Clear recognition when no face is detected
    func clearRecognition() {
        if recognizedUser != nil {
            recognizedUser = nil
            recognizedFaceBounds = nil
            print("👤 User recognition cleared")
        }
    }
}

// MARK: - Supporting Types

/// Recognized user with detection metadata
struct RecognizedUser: Identifiable {
    let profile: UserProfile
    let detectedAt: Date
    let confidence: Float
    let radiusMeters: Double // Store radius separately since it's not in the main UserProfile
    
    var id: String { profile.id }
    
    var isRecent: Bool {
        Date().timeIntervalSince(detectedAt) < 3.0
    }
    
    var formattedRadius: String {
        let usesMetric = Locale.current.measurementSystem == .metric

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

// MARK: - Notification Names

extension NSNotification.Name {
    static let UserRecognizedInCamera = NSNotification.Name("UserRecognizedInCamera")
}
