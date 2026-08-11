import Foundation
import CoreLocation
import Combine
import SwiftUI
import MapKit
import UIKit

@MainActor
final class LocationProvider: NSObject, ObservableObject {
    static let shared = LocationProvider()

    @Published var coordinate: CLLocationCoordinate2D?
    
    /// Compatibility property for MapView - converts coordinate to CLLocation
    var location: CLLocation? {
        guard let coordinate = coordinate else { return nil }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private let manager = CLLocationManager()
    private var observerTokens: [NSObjectProtocol] = []
    private var updateTimeoutTask: Task<Void, Never>?
    private var didRequest = false
    private var updatesRequested = false
    private var isUpdating = false

    private static let acceptableHorizontalAccuracy: CLLocationAccuracy = 250
    private static let updateTimeoutNanoseconds: UInt64 = 8_000_000_000

    override init() {
        super.init()
        manager.delegate = self
        // Radius/map features need a block-level fix, not a continuous
        // navigation-grade stream. Each visible/requested lease below runs for
        // one adequate fix (or eight seconds), then turns the radio off.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        // A yes on the web's clay location card is the ONE thing allowed to
        // raise the real iOS dialog. See requestIfAlreadyAuthorized().
        let center = NotificationCenter.default
        observerTokens.append(center.addObserver(
            forName: Notification.Name("PoplurPermissionHandled"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard (note.userInfo?["permission"] as? String) == "location",
                  (note.userInfo?["granted"] as? Bool) == true else { return }
            Task { @MainActor [weak self] in self?.request() }
        })
        observerTokens.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.suspendForBackground()
            }
        })
        observerTokens.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resumeIfRequested()
            }
        })
        // If app already has permission, optionally seed with last known location
        if let loc = manager.location?.coordinate {
            self.coordinate = loc
        }
    }
    
    /// Returns a MapCameraPosition centered on the user's current location
    func getCenteredCamera() -> MapCameraPosition? {
        guard let coord = coordinate else { return nil }
        return .camera(MapCamera(centerCoordinate: coord, distance: 300, heading: 0, pitch: 60))
    }
    
    /// Centers the map camera on the user's current location (mutating version)
    func centerOnUser(_ camera: Binding<MapCameraPosition>) {
        guard let coord = coordinate else { return }
        camera.wrappedValue = .camera(MapCamera(centerCoordinate: coord, distance: 300, heading: 0, pitch: 60))
    }

    /// Start location WITHOUT ever showing the system dialog.
    ///
    /// The map used to call `request()` the moment the tab loaded, which fired
    /// `requestWhenInUseAuthorization()` directly — so the bare iOS alert landed
    /// over the map and the app's own clay primer never got to go first. That
    /// ordering is the whole point of the primer: the system prompt is one-shot
    /// per install, so a reflexive "Don't Allow" on a bare alert costs the
    /// permission permanently, while declining the clay card costs nothing.
    ///
    /// Anything that merely WANTS location (map load, a passive fix) calls this.
    /// Only an explicit yes on the primer — or a user action that is itself the
    /// ask — is allowed to call `request()`.
    func requestIfAlreadyAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            didRequest = true
            updatesRequested = true
            startUpdatesIfAuthorized()
        default:
            break
        }
    }

    func request() {
        updatesRequested = true

        // Avoid spamming requests
        if didRequest { startUpdatesIfAuthorized(); return }
        didRequest = true

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdatesIfAuthorized()
        case .denied, .restricted:
            // Keep coordinate nil; user can enable in Settings
            break
        @unknown default:
            break
        }
    }

    private func startUpdatesIfAuthorized() {
        guard updatesRequested,
              UIApplication.shared.applicationState == .active,
              !isUpdating else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        isUpdating = true

        // Use the continuous API only inside this strictly bounded lease so we
        // can wait briefly for an adequate fix and then shut it down ourselves.
        manager.startUpdatingLocation()
        updateTimeoutTask?.cancel()
        updateTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.updateTimeoutNanoseconds)
            guard !Task.isCancelled else { return }
            self?.stopHardwareUpdates()
        }
    }

    /// Ends the caller's visible/requested lease. A subsequent explicit request
    /// safely starts a fresh bounded fix.
    func stop() {
        updatesRequested = false
        stopHardwareUpdates()
    }

    private func stopHardwareUpdates() {
        updateTimeoutTask?.cancel()
        updateTimeoutTask = nil
        guard isUpdating else { return }
        manager.stopUpdatingLocation()
        isUpdating = false
    }

    private func suspendForBackground() {
        stopHardwareUpdates()
    }

    private func resumeIfRequested() {
        startUpdatesIfAuthorized()
    }

    deinit {
        updateTimeoutTask?.cancel()
        manager.stopUpdatingLocation()
        observerTokens.forEach(NotificationCenter.default.removeObserver)
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                startUpdatesIfAuthorized()
            case .denied, .restricted:
                stopHardwareUpdates()
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let self, self.updatesRequested, self.isUpdating else { return }
            guard let best = locations
                .filter({ $0.horizontalAccuracy >= 0 })
                .min(by: { $0.horizontalAccuracy < $1.horizontalAccuracy }) else { return }
            self.coordinate = best.coordinate
            if best.horizontalAccuracy <= Self.acceptableHorizontalAccuracy {
                self.stopHardwareUpdates()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // You could surface an error state if needed
        // For now, just stop updates to avoid loops
        Task { @MainActor [weak self] in
            self?.stopHardwareUpdates()
        }
    }
}
