import Foundation
import CoreLocation
import WeatherKit

// Simple WeatherKit manager to fetch weather for a coordinate
actor WeatherManager {
    private let service = WeatherService.shared

    func currentWeather(at coordinate: CLLocationCoordinate2D) async throws -> Weather {
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return try await service.weather(for: loc)
    }
}
