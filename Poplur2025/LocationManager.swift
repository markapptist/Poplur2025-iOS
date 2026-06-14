import SwiftUI
import CoreLocation
import MapKit

final class LocationManager: NSObject, ObservableObject {
    @Published var location: CLLocation? = nil
    private let manager = CLLocationManager()
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
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
    @MainActor
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
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
    
    @MainActor
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        self.location = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationManager error: \(error)")
    }
}
