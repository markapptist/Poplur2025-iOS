//
//  PreviewModels.swift
//  PreviewSupport
//
//  Shared preview models that can be used across multiple preview files
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Tab Management

public enum PreviewAppTab: Hashable, CaseIterable, Identifiable {
    case map, record, feed, profile
    
    public var id: Self { self }
    
    public var displayName: String {
        switch self {
        case .map: return "Map"
        case .record: return "Record"
        case .feed: return "Feed"
        case .profile: return "Profile"
        }
    }
}

// MARK: - Authentication

public final class PreviewAuthViewModel: ObservableObject {
    @Published public var isAuthenticated: Bool = false
    
    public init(isAuthenticated: Bool = false) {
        self.isAuthenticated = isAuthenticated
    }
    
    public func signIn() {
        isAuthenticated = true
    }
    
    public func signOut() {
        isAuthenticated = false
    }
}

// MARK: - Camera Controller

public final class PreviewCameraKitController: ObservableObject {
    @Published public var isReady: Bool = false
    
    public var previewViewController: UIViewController?
    public var recordPreviewViewController: UIViewController?
    
    public init() {
        previewViewController = PreviewViewController()
        recordPreviewViewController = RecordPreviewViewController()
    }
    
    public func startPreview() async {
        await MainActor.run {
            self.isReady = true
        }
    }
    
    public func start() async {
        await MainActor.run {
            self.isReady = true
        }
    }
    
    public func stop() async {
        await MainActor.run {
            self.isReady = false
        }
    }
    
    private final class PreviewViewController: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = UIColor.systemBlue
            
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "Camera Preview"
            label.font = .boldSystemFont(ofSize: 20)
            label.textColor = .white
            label.textAlignment = .center
            
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
    }
    
    private final class RecordPreviewViewController: UIViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = UIColor.systemIndigo
            
            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.text = "Record Preview"
            label.font = .boldSystemFont(ofSize: 20)
            label.textColor = .white
            label.textAlignment = .center
            
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }
    }
}

// MARK: - Settings

public final class PreviewIsometricBarSettings: ObservableObject {
    @Published public var horizontalOffset: CGFloat = 0
    @Published public var bottomOffset: CGFloat = 0
    @Published public var barWidth: CGFloat = 20
    @Published public var barHeight: CGFloat = 150
    @Published public var barTiltDegrees: Double = 45
    
    public init() {}
}

// MARK: - Location

public final class PreviewLocationProvider: ObservableObject {
    @Published public var coordinate: (latitude: Double, longitude: Double)?
    
    public init() {}
    
    public func request() {
        coordinate = (latitude: 37.7749, longitude: -122.4194) // San Francisco
    }
}

// MARK: - Notifications

public extension Notification.Name {
    static let preview_CubeMotionUpdate = Notification.Name("preview_CubeMotionUpdate")
    static let preview_LoadMapNow = Notification.Name("preview_LoadMapNow")
    static let preview_LoadFeedNow = Notification.Name("preview_LoadFeedNow")
    static let preview_LoadProfileNow = Notification.Name("preview_LoadProfileNow")
    static let preview_PauseGlobalFeedAudio = Notification.Name("preview_PauseGlobalFeedAudio")
    static let preview_PauseFeedAudio = Notification.Name("preview_PauseFeedAudio")
    static let preview_ResumeFeedAudio = Notification.Name("preview_ResumeFeedAudio")
    static let preview_ResetTabToTop = Notification.Name("preview_ResetTabToTop")
    static let preview_CenterMapOnUser = Notification.Name("preview_CenterMapOnUser")
    static let preview_FeedReady = Notification.Name("preview_FeedReady")
    static let preview_SharedRadiusDidChange = Notification.Name("preview_SharedRadiusDidChange")
    static let preview_InlinePreviewDismissRequested = Notification.Name("preview_InlinePreviewDismissRequested")
    static let preview_cameraCubeHoldBegan = Notification.Name("preview_cameraCubeHoldBegan")
    static let preview_cameraCubeHoldEnded = Notification.Name("preview_cameraCubeHoldEnded")
    static let preview_TriggerCameraCapture = Notification.Name("preview_TriggerCameraCapture")
    static let preview_ShowRecordCaptureUI = Notification.Name("preview_ShowRecordCaptureUI")
    static let preview_CubeGlobalDragChanged = Notification.Name("preview_CubeGlobalDragChanged")
    static let preview_CubeGlobalDragEnded = Notification.Name("preview_CubeGlobalDragEnded")
    static let preview_CubeGlobalTap = Notification.Name("preview_CubeGlobalTap")
}
