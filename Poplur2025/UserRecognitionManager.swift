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
    
    private lazy var db = Firestore.firestore()
    private var faceDetectionRequest: VNDetectFaceRectanglesRequest?
    private var cachedUserProfiles: [String: UserProfile] = [:]
    private var lastRecognitionTime: Date = .distantPast
    private var savedFaceImage: UIImage?
    private var savedFaceObservation: VNFaceObservation?
    private var faceImageObserver: NSObjectProtocol?
    
    // Minimum time between recognition attempts. CameraKitController offers a
    // dedicated face slot at roughly 1 Hz; this guard also protects callers
    // outside that capture path without making recognition feel delayed.
    private let recognitionCooldown: TimeInterval = 1.0
    
    // MARK: - Initialization
    
    init() {
        setupFaceDetection()
        loadSavedFaceImage()
        setupNotificationObserver()
    }

    deinit {
        if let faceImageObserver {
            NotificationCenter.default.removeObserver(faceImageObserver)
        }
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
        if let faceImageObserver {
            NotificationCenter.default.removeObserver(faceImageObserver)
        }
        faceImageObserver = NotificationCenter.default.addObserver(
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
    func processDetectedObjects(_ _: [DetectedObject], from _: CVPixelBuffer?) {
        // CameraKitController schedules face recognition independently from
        // classification. Keeping the former callback-triggered request here
        // would put face Vision work back onto the classifier's frame and undo
        // the round-robin energy budget. The compatibility hook remains because
        // both native and web camera bridges still use it for result handling.
    }
    
    /// Detect faces in the camera frame
    func detectFaces(in pixelBuffer: CVPixelBuffer) {
        guard !isRecognizing else { return }
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
            CameraAIAnnouncer.shared.clearLastUser()
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
            CameraAIAnnouncer.shared.clearLastUser()
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
            if let cachedProfile = cachedUserProfiles[currentUserID] {
                let userDoc = try await db.collection("users").document(currentUserID).getDocument()
                var profile = cachedProfile
                if profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    let storedDisplayName = (userDoc.data()?["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let authDisplayName = Auth.auth().currentUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                    profile.displayName = storedDisplayName?.isEmpty == false ? storedDisplayName : (authDisplayName?.isEmpty == false ? authDisplayName : nil)
                    cachedUserProfiles[currentUserID] = profile
                }
                let radiusMeters = userDoc.data()?["radius"] as? Double ?? 5000.0
                let postCount = userDoc.data()?["postCount"] as? Int ?? 0
                updateRecognizedUser(profile, radius: radiusMeters, postCount: postCount, confidence: confidence)
            } else {
                let result = try await fetchUserProfile(userID: currentUserID)
                cachedUserProfiles[currentUserID] = result.profile
                updateRecognizedUser(result.profile, radius: result.radius, postCount: result.postCount, confidence: confidence)
            }
        } catch {
            print("❌ Error fetching current user profile: \(error.localizedDescription)")
        }
    }
    
    
    /// Fetch user profile from Firestore
    private func fetchUserProfile(userID: String) async throws -> (profile: UserProfile, radius: Double, postCount: Int) {
        let userDoc = try await db.collection("users").document(userID).getDocument()

        guard let data = userDoc.data() else {
            throw NSError(domain: "UserRecognition", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }

        let username = data["username"] as? String ?? "Unknown"
        let email = data["email"] as? String ?? ""
        let storedDisplayName = (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let authDisplayName = Auth.auth().currentUser?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = storedDisplayName?.isEmpty == false ? storedDisplayName : (authDisplayName?.isEmpty == false ? authDisplayName : nil)
        let radiusMeters = data["radius"] as? Double ?? 5000.0
        let postCount = data["postCount"] as? Int ?? 0
        let profileImageURLString = data["profileImageURL"] as? String
        let profilePictureURL = profileImageURLString.flatMap { URL(string: $0) }

        let profile = UserProfile(
            id: userID,
            username: username,
            email: email,
            displayName: displayName,
            profilePictureURL: profilePictureURL
        )

        return (profile, radiusMeters, postCount)
    }
    
    private func updateRecognizedUser(_ profile: UserProfile, radius: Double, postCount: Int = 0, confidence: Float = 0.85) {
        let user = RecognizedUser(
            profile: profile,
            detectedAt: Date(),
            confidence: confidence,
            radiusMeters: radius,
            postCount: postCount
        )
        recognizedUser = user

        print("👤 Recognized user name: \(user.nameForSpeech), username: @\(profile.username), radius: \(Int(radius))m, posts: \(postCount), confidence: \(Int(confidence * 100))%")
        CameraAIAnnouncer.shared.announceRecognizedUser(user)

        NotificationCenter.default.post(
            name: NSNotification.Name("UserRecognizedInCamera"),
            object: nil,
            userInfo: [
                "userID": profile.id,
                "username": profile.username,
                "displayName": user.nameForSpeech,
                "radius": radius,
                "postCount": postCount,
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
            CameraAIAnnouncer.shared.clearLastUser()
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
    let radiusMeters: Double
    let postCount: Int
    
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

    var nameForSpeech: String {
        guard let displayName = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !displayName.isEmpty else {
            return profile.username
        }
        return displayName
    }
}

// MARK: - Notification Names

extension NSNotification.Name {
    static let UserRecognizedInCamera = NSNotification.Name("UserRecognizedInCamera")
}
