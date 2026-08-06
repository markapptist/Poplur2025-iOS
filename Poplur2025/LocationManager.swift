import SwiftUI
import CoreLocation
import MapKit

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published var location: CLLocation? = nil
    private let manager = CLLocationManager()
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Without a distanceFilter, every movement delivers an update and the
        // radio never rests. 50m matches the block-level use this class serves.
        manager.distanceFilter = 50
        if CLLocationManager.locationServicesEnabled() {
            let status = manager.authorizationStatus
            if status == .authorizedAlways || status == .authorizedWhenInUse {
                manager.startUpdatingLocation()
            }
        }
    }

    func requestAuthorizationIfNeeded() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedAlways || status == .authorizedWhenInUse {
            manager.startUpdatingLocation()
        }
    }

    func centerOnUser(_ camera: inout MapKit.MapCameraPosition) {
        guard let coord = location?.coordinate else { return }
        camera = .camera(MapKit.MapCamera(centerCoordinate: coord, distance: 12_000, heading: 0, pitch: 0))
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.startUpdatingLocation()
            case .denied, .restricted:
                break
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.location = locations.last
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationManager error: \(error)")
    }
}
