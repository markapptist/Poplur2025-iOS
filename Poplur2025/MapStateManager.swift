//
//  MapStateManager.swift
//  Poplur2025
//
//  Created on 2025-05-09.
//

import SwiftUI
import CoreLocation

/// Defines the different modes/states the map can be in
enum MapMode: Equatable {
    /// Normal browsing mode - user is exploring the map
    case browsing
    
    /// User has clicked a coordinate and is deciding whether to post there (Map → Camera flow)
    case coordinateSelected(coordinate: CLLocationCoordinate2D)
    
    /// User captured media first and is now selecting where to post it (Camera → Map flow)
    case selectingPostLocation
    
    /// Automatic tour mode - flying between cities
    case autoTour
    
    /// Navigating to show a specific post location (from long-press on feed post)
    case showingPostLocation(coordinate: CLLocationCoordinate2D)
    
    // MARK: - Equatable Conformance
    
    static func == (lhs: MapMode, rhs: MapMode) -> Bool {
        switch (lhs, rhs) {
        case (.browsing, .browsing):
            return true
        case (.selectingPostLocation, .selectingPostLocation):
            return true
        case (.autoTour, .autoTour):
            return true
        case (.coordinateSelected(let lhsCoord), .coordinateSelected(let rhsCoord)):
            return lhsCoord.latitude == rhsCoord.latitude && lhsCoord.longitude == rhsCoord.longitude
        case (.showingPostLocation(let lhsCoord), .showingPostLocation(let rhsCoord)):
            return lhsCoord.latitude == rhsCoord.latitude && lhsCoord.longitude == rhsCoord.longitude
        default:
            return false
        }
    }
    
    // MARK: - Computed Properties
    
    var isInteractive: Bool {
        switch self {
        case .browsing, .coordinateSelected, .selectingPostLocation:
            return true
        case .autoTour, .showingPostLocation:
            return false
        }
    }
    
    var shouldShowAIRecommendations: Bool {
        switch self {
        case .browsing, .autoTour:
            return true
        case .coordinateSelected, .selectingPostLocation, .showingPostLocation:
            return false
        }
    }
    
    var allowsTourToStart: Bool {
        switch self {
        case .browsing:
            return true
        case .coordinateSelected, .selectingPostLocation, .autoTour, .showingPostLocation:
            return false
        }
    }
    
    var shouldCenterOnUserLocation: Bool {
        // Only center on user location when first entering browsing mode
        // NOT when in selection or navigation modes
        switch self {
        case .browsing:
            return false // Don't auto-center, let user control
        case .coordinateSelected, .selectingPostLocation, .autoTour, .showingPostLocation:
            return false
        }
    }
}

/// Manages the state and behavior of the map view
@MainActor
final class MapStateManager: ObservableObject {
    static let shared = MapStateManager()
    
    // MARK: - Published State
    
    @Published var mode: MapMode = .browsing {
        didSet {
            print("🗺️ [MapState] Mode changed: \(oldValue) → \(mode)")
            handleModeChange(from: oldValue, to: mode)
        }
    }
    
    @Published var lastInteractionTime: Date = Date()
    @Published var idleTimerTask: Task<Void, Never>?
    
    // MARK: - Configuration
    
    /// How long to wait before starting auto-tour (30 seconds)
    let tourIdleThreshold: TimeInterval = 30.0
    
    /// Minimum time between tour start attempts
    let tourCooldown: TimeInterval = 5.0
    
    private var lastTourStartTime: Date = .distantPast
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Call this whenever user interacts with the map
    func noteUserInteraction() {
        lastInteractionTime = Date()
        
        // Stop tour if it's running
        if case .autoTour = mode {
            print("🗺️ [MapState] User interaction detected - stopping tour")
            mode = .browsing
        }
        
        // Cancel and restart idle timer
        restartIdleTimer()
    }
    
    /// Enter coordinate selection mode (Map → Camera flow)
    func selectCoordinate(_ coordinate: CLLocationCoordinate2D) {
        print("🗺️ [MapState] Coordinate selected: \(coordinate.latitude), \(coordinate.longitude)")
        mode = .coordinateSelected(coordinate: coordinate)
        cancelIdleTimer() // Don't start tour while selecting
    }
    
    /// Enter post location selection mode (Camera → Map flow)
    func enterPostLocationSelectionMode() {
        print("🗺️ [MapState] Entering post location selection mode")
        mode = .selectingPostLocation
        cancelIdleTimer() // Don't start tour while selecting
    }
    
    /// Navigate to show a specific post location
    func showPostLocation(_ coordinate: CLLocationCoordinate2D) {
        print("🗺️ [MapState] Showing post location: \(coordinate.latitude), \(coordinate.longitude)")
        mode = .showingPostLocation(coordinate: coordinate)
        cancelIdleTimer() // Don't start tour while showing post
    }
    
    /// Start auto-tour mode
    func startTour() {
        guard mode.allowsTourToStart else {
            print("🗺️ [MapState] Cannot start tour - current mode doesn't allow it: \(mode)")
            return
        }
        
        // Check cooldown
        let timeSinceLastTour = Date().timeIntervalSince(lastTourStartTime)
        guard timeSinceLastTour > tourCooldown else {
            print("🗺️ [MapState] Tour cooldown active - wait \(tourCooldown - timeSinceLastTour)s")
            return
        }
        
        print("🗺️ [MapState] Starting auto-tour")
        mode = .autoTour
        lastTourStartTime = Date()
        cancelIdleTimer() // Tour manages its own timing
    }
    
    /// Stop tour and return to browsing
    func stopTour() {
        guard case .autoTour = mode else { return }
        print("🗺️ [MapState] Stopping tour")
        mode = .browsing
        restartIdleTimer()
    }
    
    /// Cancel current operation and return to browsing
    func cancelCurrentOperation() {
        print("🗺️ [MapState] Canceling current operation")
        mode = .browsing
        restartIdleTimer()
    }
    
    /// Check if enough time has passed to start tour
    func checkIdleTimeout() {
        guard mode.allowsTourToStart else { return }
        
        let idleTime = Date().timeIntervalSince(lastInteractionTime)
        if idleTime >= tourIdleThreshold {
            print("🗺️ [MapState] Idle timeout reached (\(idleTime)s) - starting tour")
            startTour()
        }
    }
    
    // MARK: - Private Methods
    
    private func handleModeChange(from oldMode: MapMode, to newMode: MapMode) {
        // Post notifications for mode changes if needed
        switch newMode {
        case .autoTour:
            NotificationCenter.default.post(name: .mapTourStarted, object: nil)
        case .browsing where oldMode == .autoTour:
            NotificationCenter.default.post(name: .mapTourStopped, object: nil)
        case .selectingPostLocation:
            NotificationCenter.default.post(name: .mapEnterPostSelectionMode, object: nil)
        case .showingPostLocation(let coordinate):
            NotificationCenter.default.post(
                name: .mapNavigatingToPost,
                object: nil,
                userInfo: ["coordinate": coordinate]
            )
        default:
            break
        }
    }
    
    private func restartIdleTimer() {
        cancelIdleTimer()
        
        guard mode.allowsTourToStart else { return }
        
        idleTimerTask = Task { @MainActor in
            print("🗺️ [MapState] Idle timer started - will check in \(tourIdleThreshold)s")
            
            try? await Task.sleep(nanoseconds: UInt64(tourIdleThreshold * 1_000_000_000))
            
            guard !Task.isCancelled else {
                print("🗺️ [MapState] Idle timer cancelled")
                return
            }
            
            checkIdleTimeout()
        }
    }
    
    private func cancelIdleTimer() {
        idleTimerTask?.cancel()
        idleTimerTask = nil
    }
    
    // MARK: - Convenience Getters
    
    var selectedCoordinate: CLLocationCoordinate2D? {
        switch mode {
        case .coordinateSelected(let coordinate):
            return coordinate
        case .showingPostLocation(let coordinate):
            return coordinate
        default:
            return nil
        }
    }
    
    var isInSelectionMode: Bool {
        switch mode {
        case .coordinateSelected, .selectingPostLocation:
            return true
        default:
            return false
        }
    }
    
    var isInTourMode: Bool {
        if case .autoTour = mode {
            return true
        }
        return false
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let mapTourStarted = Notification.Name("MapTourStarted")
    static let mapTourStopped = Notification.Name("MapTourStopped")
    static let mapEnterPostSelectionMode = Notification.Name("MapEnterPostSelectionMode")
    static let mapNavigatingToPost = Notification.Name("MapNavigatingToPost")
}
