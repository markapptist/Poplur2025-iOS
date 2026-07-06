//
//  MapStreetViewViewModel.swift
//  Poplur2025
//
//  Drives the "Street View" button on the map: resolves the coordinate to use,
//  requests an Apple Look Around scene, and exposes state for the UI to render.
//

import Foundation
import CoreLocation
import MapKit

@MainActor
final class MapStreetViewViewModel: ObservableObject {
    @Published private(set) var state: LookAroundState = .idle

    private let service: LookAroundProviding?
    private var checkTask: Task<Void, Never>?

    /// Pass a service explicitly for testing; defaults to the real Apple Look Around
    /// provider when available, or `nil` when the OS is below iOS 16.
    init(service: LookAroundProviding? = nil) {
        if let service {
            self.service = service
        } else if #available(iOS 16.0, *) {
            self.service = LookAroundService()
        } else {
            self.service = nil
        }
    }

    /// Resolves the coordinate to check — the selected pin/tap coordinate if present,
    /// otherwise the current map camera center — and requests a Look Around scene.
    /// Cancels any in-flight check for a previous coordinate.
    func checkStreetView(selectedCoordinate: CLLocationCoordinate2D?, mapCenter: CLLocationCoordinate2D?) {
        checkTask?.cancel()

        guard let service else {
            state = .unsupported
            return
        }

        guard let coordinate = selectedCoordinate ?? mapCenter else {
            state = .noCoordinateSelected
            return
        }

        state = .checking
        checkTask = Task { [weak self] in
            do {
                let scene = try await service.lookAroundScene(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
                guard !Task.isCancelled, let self else { return }
                if let scene {
                    self.state = .available(scene)
                } else {
                    self.state = .unavailable
                }
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.state = .error("Street View could not be loaded. Try again.")
            }
        }
    }

    /// Cancels any in-flight check, e.g. when the selected coordinate changes.
    func cancelInFlightCheck() {
        checkTask?.cancel()
    }

    /// Returns the button to its default state, e.g. after the viewer/alert is dismissed.
    func reset() {
        checkTask?.cancel()
        state = .idle
    }

    deinit {
        checkTask?.cancel()
    }
}
