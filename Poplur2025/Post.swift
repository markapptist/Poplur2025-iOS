import Foundation
import CoreLocation

struct Post: Identifiable, Codable, Hashable {
    let id: String
    let latitude: Double
    let longitude: Double
    let mediaURL: String
    var radius: Int
    var viewCount: Int
    let userID: String
    var posterURL: String? // Optional thumbnail URL for videos

    // Convenience computed property if you ever need CLLocationCoordinate2D
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case latitude
        case longitude
        case mediaURL
        case radius
        case viewCount
        case userID
        case posterURL
    }
}
