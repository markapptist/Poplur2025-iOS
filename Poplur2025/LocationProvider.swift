import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationProvider: NSObject, ObservableObject {
    @Published var coordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()
    private var didRequest = false
    private var isUpdating = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 10
        // If app already has permission, optionally seed with last known location
        if let loc = manager.location?.coordinate {
            self.coordinate = loc
        }
    }

    func request() {
        // Avoid spamming requests
        if didRequest { startUpdatesIfAuthorized(); return }
        didRequest = true

        switch CLLocationManager.authorizationStatus() {
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
        let status = CLLocationManager.authorizationStatus()
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
