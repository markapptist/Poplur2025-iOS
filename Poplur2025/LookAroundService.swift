//
//  LookAroundService.swift
//  Poplur2025
//
//  iOS street-view provider backed by Apple MapKit Look Around.
//  Do not use Mapbox or Mapillary here — iOS street view is Apple-only.
//

import Foundation
import CoreLocation
import MapKit

protocol LookAroundProviding {
    func lookAroundScene(latitude: Double, longitude: Double) async throws -> MKLookAroundScene?
}

/// Concrete Apple MapKit Look Around provider. Requires iOS 16+.
@available(iOS 16.0, *)
struct LookAroundService: LookAroundProviding {
    func lookAroundScene(latitude: Double, longitude: Double) async throws -> MKLookAroundScene? {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let request = MKLookAroundSceneRequest(coordinate: coordinate)
        return try await request.scene
    }
}
