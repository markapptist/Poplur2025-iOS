import SwiftUI
import CoreLocation
import MapKit
import UIKit

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published var location: CLLocation? = nil
    private let manager = CLLocationManager()
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var updateTimeoutTask: Task<Void, Never>?
    private var bestPendingLocation: CLLocation?
    private var updatesRequested = false
    private var isUpdating = false

    private static let acceptableHorizontalAccuracy: CLLocationAccuracy = 250
    private static let updateTimeoutNanoseconds: UInt64 = 8_000_000_000
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // Without a distanceFilter, every movement delivers an update and the
        // radio never rests. 50m matches the block-level use this class serves.
        manager.distanceFilter = 50

        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.suspendForBackground()
            }
        })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resumeIfRequested()
            }
        })
    }

    func requestAuthorizationIfNeeded() {
        updatesRequested = true
        guard CLLocationManager.locationServicesEnabled() else { return }

        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedAlways || status == .authorizedWhenInUse {
            beginOneShotUpdate()
        }
    }

    func stop() {
        updatesRequested = false
        stopHardwareUpdates()
    }

    func centerOnUser(_ camera: inout MapKit.MapCameraPosition) {
        guard let coord = location?.coordinate else { return }
        camera = .camera(MapKit.MapCamera(centerCoordinate: coord, distance: 12_000, heading: 0, pitch: 0))
    }

    private func beginOneShotUpdate() {
        guard updatesRequested,
              UIApplication.shared.applicationState == .active,
              !isUpdating else { return }

        bestPendingLocation = nil
        isUpdating = true
        manager.startUpdatingLocation()

        updateTimeoutTask?.cancel()
        updateTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.updateTimeoutNanoseconds)
            guard !Task.isCancelled else { return }
            guard let self else { return }
            if let bestPendingLocation = self.bestPendingLocation {
                self.location = bestPendingLocation
            }
            self.stopHardwareUpdates()
        }
    }

    private func stopHardwareUpdates() {
        updateTimeoutTask?.cancel()
        updateTimeoutTask = nil
        bestPendingLocation = nil
        guard isUpdating else { return }
        manager.stopUpdatingLocation()
        isUpdating = false
    }

    private func suspendForBackground() {
        stopHardwareUpdates()
    }

    private func resumeIfRequested() {
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        beginOneShotUpdate()
    }

    private func receive(_ locations: [CLLocation]) {
        guard updatesRequested, isUpdating else { return }

        for candidate in locations where candidate.horizontalAccuracy >= 0 {
            if let bestPendingLocation,
               bestPendingLocation.horizontalAccuracy <= candidate.horizontalAccuracy {
                continue
            }
            bestPendingLocation = candidate
        }

        guard let bestPendingLocation else { return }
        location = bestPendingLocation
        if bestPendingLocation.horizontalAccuracy <= Self.acceptableHorizontalAccuracy {
            stopHardwareUpdates()
        }
    }

    deinit {
        updateTimeoutTask?.cancel()
        manager.stopUpdatingLocation()
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                self.beginOneShotUpdate()
            case .denied, .restricted:
                self.stopHardwareUpdates()
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            self?.receive(locations)
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationManager error: \(error)")
        Task { @MainActor [weak self] in
            self?.stopHardwareUpdates()
        }
    }
}
