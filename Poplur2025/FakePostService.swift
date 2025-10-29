import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreLocation

/// Foreground-only generator that seeds and periodically inserts fake posts into Firestore.
/// Writes fields: latitude, longitude, mediaURL, radius, viewCount, userID ("fake_user_…"), createdAt (serverTimestamp).
@MainActor
final class FakePostService: ObservableObject {
    static let shared = FakePostService()

    private var timer: Timer?
    private var isSeedingDone = false
    private let db = Firestore.firestore()

    // A few world cities with lat/lon for distribution
    private let cities: [(name: String, lat: Double, lon: Double)] = [
        ("San Francisco", 37.7749, -122.4194),
        ("New York", 40.7128, -74.0060),
        ("London", 51.5074, -0.1278),
        ("Paris", 48.8566, 2.3522),
        ("Tokyo", 35.6895, 139.6917),
        ("Sydney", -33.8688, 151.2093),
        ("Rio", -22.9068, -43.1729),
        ("Toronto", 43.6532, -79.3832),
        ("Mexico City", 19.4326, -99.1332),
        ("Cape Town", -33.9249, 18.4241)
    ]

    // A small set of placeholder media; swap with your own if desired.
    private let mediaPool: [String] = [
        "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=1600",
        "https://images.unsplash.com/photo-1518779578993-ec3579fee39f?w=1600",
        "https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=1600",
        "https://images.unsplash.com/photo-1470770903676-69b98201ea1c?w=1600",
        "https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=1600"
    ]

    // Radius choices in meters (tune as you like)
    private let radiusChoices: [Int] = [1000, 3000, 5000, 10000]

    private init() { }

    func start() {
        // Seed once per app run (idempotent enough for demo)
        if !isSeedingDone {
            isSeedingDone = true
            Task { await seedInitialPostsIfNeeded(countPerCity: 2) }
        }

        // Periodically add a post every N minutes while foregrounded
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 5, repeats: true) { [weak self] _ in
            Task { await self?.addRandomFakePost() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Seeding

    private func seedInitialPostsIfNeeded(countPerCity: Int) async {
        // Quick heuristic: if there are already > X posts with userID starting with "fake_user_", skip
        do {
            let snapshot = try await db.collection("posts")
                .whereField("userID", isGreaterThanOrEqualTo: "fake_user_")
                .whereField("userID", isLessThan: "fake_user_\u{f8ff}")
                .limit(to: 10)
                .getDocuments()
            if !snapshot.documents.isEmpty { return }
        } catch {
            // Proceed anyway
        }

        for (idx, city) in cities.enumerated() {
            for j in 0..<countPerCity {
                let uid = "fake_user_\(idx)_\(j)"
                let coord = jitteredCoordinate(lat: city.lat, lon: city.lon, meters: Double.random(in: 0...2500))
                let media = mediaPool.randomElement() ?? ""
                let radius = radiusChoices.randomElement() ?? 5000
                await addPost(latitude: coord.latitude, longitude: coord.longitude, mediaURL: media, radius: radius, userID: uid)
            }
        }
    }

    private func addRandomFakePost() async {
        guard let city = cities.randomElement() else { return }
        let uid = "fake_user_\(Int.random(in: 1000...9999))"
        let coord = jitteredCoordinate(lat: city.lat, lon: city.lon, meters: Double.random(in: 0...5000))
        let media = mediaPool.randomElement() ?? ""
        let radius = radiusChoices.randomElement() ?? 5000
        await addPost(latitude: coord.latitude, longitude: coord.longitude, mediaURL: media, radius: radius, userID: uid)
    }

    private func addPost(latitude: Double, longitude: Double, mediaURL: String, radius: Int, userID: String) async {
        var data: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude,
            "mediaURL": mediaURL,
            "radius": radius,
            "viewCount": 0,
            "userID": userID,
            "createdAt": FieldValue.serverTimestamp()
        ]
        // If you want to tag the real current user as creator, you can override userID here with Auth.auth().currentUser?.uid

        do {
            _ = try await db.collection("posts").addDocument(data: data)
        } catch {
            print("FakePostService: failed to write post: \(error.localizedDescription)")
        }
    }

    // Jitter coordinate by ~meters using simple lat/lon delta approximation
    private func jitteredCoordinate(lat: Double, lon: Double, meters: Double) -> (latitude: Double, longitude: Double) {
        guard meters > 0 else { return (lat, lon) }
        // Random bearing and distance
        let bearing = Double.random(in: 0..<(2 * .pi))
        let earthRadius = 6_371_000.0
        let distRatio = meters / earthRadius

        let lat1 = lat * .pi / 180
        let lon1 = lon * .pi / 180

        let lat2 = asin(sin(lat1) * cos(distRatio) + cos(lat1) * sin(distRatio) * cos(bearing))
        let lon2 = lon1 + atan2(sin(bearing) * sin(distRatio) * cos(lat1),
                                cos(distRatio) - sin(lat1) * sin(lat2))

        return (lat2 * 180 / .pi, lon2 * 180 / .pi)
    }

    // MARK: - Distance helper (static so views can use it too)

    static func distanceMeters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let ca = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let cb = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return ca.distance(from: cb)
    }
}

