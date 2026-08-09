import Foundation
import CoreLocation
import Combine
import SwiftUI
import MapKit

@MainActor
final class LocationProvider: NSObject, ObservableObject {
    @Published var coordinate: CLLocationCoordinate2D?
    
    /// Compatibility property for MapView - converts coordinate to CLLocation
    var location: CLLocation? {
        guard let coordinate = coordinate else { return nil }
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private let manager = CLLocationManager()
    private var didRequest = false
    private var isUpdating = false
    private var hasPreciseFix = false

    override init() {
        super.init()
        manager.delegate = self
        // Precise for the FIRST fix only. Continuous ten-metre GNSS keeps the
        // radio in its hottest mode for the whole foreground session, and it is
        // one of the big reasons the app heats the phone. After the first good
        // fix lands, didUpdateLocations downshifts to hundred-metre / 50m
        // filter — the radius product needs "which block", not "which metre".
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        // A yes on the web's clay location card is the ONE thing allowed to
        // raise the real iOS dialog. See requestIfAlreadyAuthorized().
        NotificationCenter.default.addObserver(
            forName: Notification.Name("PoplurPermissionHandled"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard (note.userInfo?["permission"] as? String) == "location",
                  (note.userInfo?["granted"] as? Bool) == true else { return }
            Task { @MainActor in self?.request() }
        }
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
            startUpdatesIfAuthorized()
        default:
            break
        }
    }

    func request() {
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
        guard !isUpdating else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
        isUpdating = true

        // For a quick coordinate, requestLocation() gives one update then stops
        manager.requestLocation()
        // Optionally also startUpdatingLocation to keep it fresh while in foreground
        manager.startUpdatingLocation()
    }

    private func stopUpdates() {
        if isUpdating {
            manager.stopUpdatingLocation()
            isUpdating = false
        }
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                startUpdatesIfAuthorized()
            case .denied, .restricted:
                stopUpdates()
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        Task { @MainActor in
            self.coordinate = last.coordinate
            // First usable fix delivered — drop the continuous stream to the
            // cool tier. Anything that needs a precise moment (posting, a
            // claim) should take its own one-shot requestLocation() rather
            // than holding the whole session at ten metres.
            if !self.hasPreciseFix {
                self.hasPreciseFix = true
                self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
                self.manager.distanceFilter = 50
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // You could surface an error state if needed
        // For now, just stop updates to avoid loops
        Task { @MainActor in
            self.stopUpdates()
        }
    }
}
