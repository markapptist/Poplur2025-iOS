//
//  MapStreetViewViewModelTests.swift
//  Poplur2025Tests
//

import Testing
import MapKit
@testable import Poplur2025

@MainActor
struct MapStreetViewViewModelTests {

    private final class FakeLookAroundProvider: LookAroundProviding {
        var result: () throws -> MKLookAroundScene?
        private(set) var lastRequestedLatitude: Double?
        private(set) var lastRequestedLongitude: Double?

        init(result: @escaping () throws -> MKLookAroundScene?) {
            self.result = result
        }

        func lookAroundScene(latitude: Double, longitude: Double) async throws -> MKLookAroundScene? {
            lastRequestedLatitude = latitude
            lastRequestedLongitude = longitude
            return try result()
        }
    }

    private struct SampleError: Error {}

    private func settle() async {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    @Test func startsIdle() {
        let viewModel = MapStreetViewViewModel(service: FakeLookAroundProvider(result: { nil }))
        #expect(viewModel.state == .idle)
    }

    @Test func noCoordinateSelectedWhenNothingToCheck() {
        let viewModel = MapStreetViewViewModel(service: FakeLookAroundProvider(result: { nil }))
        viewModel.checkStreetView(selectedCoordinate: nil, mapCenter: nil)
        #expect(viewModel.state == .noCoordinateSelected)
    }

    @Test func fallsBackToMapCenterWhenNoSelectionExists() async {
        let center = CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857)
        let provider = FakeLookAroundProvider(result: { nil })
        let viewModel = MapStreetViewViewModel(service: provider)
        viewModel.checkStreetView(selectedCoordinate: nil, mapCenter: center)
        #expect(viewModel.state == .checking)
        await settle()
        #expect(provider.lastRequestedLatitude == center.latitude)
        #expect(provider.lastRequestedLongitude == center.longitude)
    }

    @Test func prefersSelectedCoordinateOverMapCenter() async {
        let selected = CLLocationCoordinate2D(latitude: 1, longitude: 2)
        let center = CLLocationCoordinate2D(latitude: 40.7484, longitude: -73.9857)
        let provider = FakeLookAroundProvider(result: { nil })
        let viewModel = MapStreetViewViewModel(service: provider)
        viewModel.checkStreetView(selectedCoordinate: selected, mapCenter: center)
        await settle()
        #expect(provider.lastRequestedLatitude == selected.latitude)
        #expect(provider.lastRequestedLongitude == selected.longitude)
    }

    @Test func resolvesToUnavailableWhenSceneIsNil() async {
        let viewModel = MapStreetViewViewModel(service: FakeLookAroundProvider(result: { nil }))
        viewModel.checkStreetView(
            selectedCoordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            mapCenter: nil
        )
        #expect(viewModel.state == .checking)
        await settle()
        #expect(viewModel.state == .unavailable)
    }

    @Test func resolvesToErrorWhenServiceThrows() async {
        let viewModel = MapStreetViewViewModel(service: FakeLookAroundProvider(result: { throw SampleError() }))
        viewModel.checkStreetView(
            selectedCoordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            mapCenter: nil
        )
        await settle()
        guard case .error = viewModel.state else {
            Issue.record("Expected .error state, got \(viewModel.state)")
            return
        }
    }

    @Test func resetReturnsToIdle() async {
        let viewModel = MapStreetViewViewModel(service: FakeLookAroundProvider(result: { nil }))
        viewModel.checkStreetView(
            selectedCoordinate: CLLocationCoordinate2D(latitude: 1, longitude: 1),
            mapCenter: nil
        )
        await settle()
        viewModel.reset()
        #expect(viewModel.state == .idle)
    }
}
