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
    /// Map-first flow: Map Tab -> Select coordinate -> Camera -> Capture -> Preview -> Edit -> Channel -> Post
    case mapToCamera(coordinate: CLLocationCoordinate2D)
    
    /// Camera-first flow: Camera Tab -> Capture -> Preview -> Map -> Edit -> Channel -> Post
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

enum PostCaptureFilter: String, CaseIterable, Identifiable {
    case original
    case pop
    case noir
    case chrome
    case warm
    case cool

    var id: String { rawValue }
}

struct PostCaptureChannel: Identifiable, Hashable {
    let id: String
    let number: Int
    let emoji: String
    let title: String
    let subtitle: String

    static let all: [PostCaptureChannel] = [
        PostCaptureChannel(id: "food", number: 101, emoji: "🍔", title: "Food", subtitle: "Restaurants, recipes, cravings"),
        PostCaptureChannel(id: "gaming", number: 102, emoji: "🎮", title: "Gaming", subtitle: "Streams, clips, wins"),
        PostCaptureChannel(id: "music", number: 103, emoji: "🎵", title: "Music", subtitle: "Songs, shows, studios"),
        PostCaptureChannel(id: "city", number: 104, emoji: "🏙️", title: "City", subtitle: "Local scenes and street moments"),
        PostCaptureChannel(id: "style", number: 105, emoji: "💄", title: "Style", subtitle: "Beauty, fashion, looks"),
        PostCaptureChannel(id: "sports", number: 106, emoji: "⚽", title: "Sports", subtitle: "Games, training, highlights"),
        PostCaptureChannel(id: "film", number: 107, emoji: "🎬", title: "Film", subtitle: "Movies, edits, reviews"),
        PostCaptureChannel(id: "shopping", number: 108, emoji: "🛍️", title: "Shopping", subtitle: "Finds, hauls, drops"),
        PostCaptureChannel(id: "french", number: 109, emoji: "🇫🇷", title: "French", subtitle: "French-language broadcasts"),
        PostCaptureChannel(id: "spanish", number: 110, emoji: "🇪🇸", title: "Spanish", subtitle: "Spanish-language broadcasts")
    ]
}

struct PostCaptureEdits {
    let filter: PostCaptureFilter
    let videoTrimSeconds: Double?
    let channel: PostCaptureChannel
    let tvMetadata: TVStyleMetadata?
}

struct PendingPostMetadata {
    let coordinate: CLLocationCoordinate2D
    let filterID: String
    let videoTrimSeconds: Double?
    let channelID: String
    let channelTitle: String
    let tvMetadata: TVStyleMetadata?
}

/// Observable object to manage capture flow state across views
final class CaptureFlowManager: ObservableObject {
    static let shared = CaptureFlowManager()
    
    @Published var currentFlow: CaptureFlow?
    @Published var capturedImage: UIImage?
    @Published var capturedVideoURL: URL?
    @Published var confirmedCoordinate: CLLocationCoordinate2D?

    private var pendingPostMetadata: PendingPostMetadata?
    
    private init() {}
    
    /// Start Map -> Camera flow: user clicked a coordinate on map and wants to post there
    func startMapToCameraFlow(coordinate: CLLocationCoordinate2D) {
        currentFlow = .mapToCamera(coordinate: coordinate)
        capturedImage = nil
        capturedVideoURL = nil
        confirmedCoordinate = coordinate
        print("📍 [CaptureFlowManager] Started Map -> Camera flow at: \(coordinate.latitude), \(coordinate.longitude)")
    }
    
    /// Start Camera -> Map flow: user captured in camera and needs to select location
    func startCameraToMapFlow(image: UIImage?, videoURL: URL?) {
        currentFlow = .cameraToMap
        capturedImage = image
        capturedVideoURL = videoURL
        confirmedCoordinate = nil
        print("📸 [CaptureFlowManager] Started Camera -> Map flow with \(image != nil ? "image" : "video")")
    }

    func confirmLocation(_ coordinate: CLLocationCoordinate2D) {
        confirmedCoordinate = coordinate
        print("📍 [CaptureFlowManager] Confirmed post coordinate: \(coordinate.latitude), \(coordinate.longitude)")
    }
    
    /// Complete the flow and post to the final coordinate
    func completeFlow(finalCoordinate: CLLocationCoordinate2D, edits: PostCaptureEdits? = nil) {
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

        if let edits {
            userInfo["filterID"] = edits.filter.rawValue
            userInfo["channelID"] = edits.channel.id
            userInfo["channelTitle"] = edits.channel.title
            if let seconds = edits.videoTrimSeconds {
                userInfo["videoTrimSeconds"] = seconds
            }
            pendingPostMetadata = PendingPostMetadata(
                coordinate: finalCoordinate,
                filterID: edits.filter.rawValue,
                videoTrimSeconds: edits.videoTrimSeconds,
                channelID: edits.channel.id,
                channelTitle: edits.channel.title,
                tvMetadata: edits.tvMetadata
            )
        }
        
        NotificationCenter.default.post(
            name: Notification.Name("UploadPostToCoordinate"),
            object: nil,
            userInfo: userInfo
        )
        
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
        pendingPostMetadata = nil
        reset()
    }

    func consumePendingPostMetadata() -> PendingPostMetadata? {
        let metadata = pendingPostMetadata
        pendingPostMetadata = nil
        return metadata
    }
    
    /// Reset all state
    private func reset() {
        currentFlow = nil
        capturedImage = nil
        capturedVideoURL = nil
        confirmedCoordinate = nil
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

    /// Posted when a confirmed capture is ready for filters, trimming, and channel selection.
    static let showPostCaptureEditor = Notification.Name("ShowPostCaptureEditor")
}
