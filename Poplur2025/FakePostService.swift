import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreLocation

/// Foreground-only generator that seeds and periodically inserts fake posts into Firestore,
/// and can simulate daily posting plus engagement from fake users.
/// Writes fields: latitude, longitude, mediaURL, radius, viewCount, userID, createdAt (serverTimestamp), createdAtMillis (Int64).
@MainActor
final class FakePostService: ObservableObject {
    static let shared = FakePostService()

    private let db = Firestore.firestore()

    // MARK: Timers
    private var periodicTimer: Timer?          // every few minutes to add a random world post (legacy)
    private var dailyTimer: Timer?             // compressed "daily" tick (devDailySeconds)
    private var engagementTimer: Timer?        // frequent engagement (views) tick

    // MARK: Flags
    private var didInitialCitySeed = false

    // MARK: Media pools (mix images and videos)
    private let imagePool: [String] = [
        "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?w=1600",
        "https://images.unsplash.com/photo-1518779578993-ec3579fee39f?w=1600",
        "https://images.unsplash.com/photo-1501785888041-af3ef285b470?w=1600",
        "https://images.unsplash.com/photo-1470770903676-69b98201ea1c?w=1600",
        "https://images.unsplash.com/photo-1469474968028-56623f02e42e?w=1600",
        "https://images.unsplash.com/photo-1519681393784-d120267933ba?w=1600",
        "https://images.unsplash.com/photo-1482192596544-9eb780fc7f66?w=1600",
        "https://images.unsplash.com/photo-1491553895911-0055eca6402d?w=1600"
    ]
    // Public-domain human TV drama/soap clips with dialogue for closed-caption testing.
    private let videoPool: [String] = [
        "https://archive.org/download/Guiding_Light/GuidingLightMarch4-1953.mp4",
        "https://archive.org/download/Love_Of_Life_Soap/LoveofLifeMarch20-1953.mp4",
        "https://archive.org/download/Valiant_Lady/Valiant_Lady.mp4",
        "https://archive.org/download/GuidingLight9April1953/GuidingLight9April1953.mp4",
        "https://archive.org/download/1967_PD_Soapie/LoveisaManySplenderedThing1967.mp4"
    ]

    private var mixedMediaPool: [String] {
        (imagePool + videoPool)
    }

    // Radius choices in meters
    private let radiusChoices: [Int] = [500, 1000, 3000, 5000, 10000]

    private init() { }

    // MARK: - Legacy start/stop (kept)
    func start() {
        if !didInitialCitySeed {
            didInitialCitySeed = true
            Task { await seedInitialPostsIfNeeded(countPerCity: 2) }
        }
        stopPeriodic()
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 60 * 5, repeats: true) { [weak self] _ in
            Task { await self?.addRandomWorldPost() }
        }
    }

    func stop() {
        stopPeriodic()
        stopWorldSimulator()
    }

    private func stopPeriodic() {
        periodicTimer?.invalidate()
        periodicTimer = nil
    }

    // Public/internal wrapper to allow UI to request city demo seeding,
    // while keeping the detailed implementation private.
    func seedCityDemoIfNeeded(countPerCity: Int) async {
        await seedInitialPostsIfNeeded(countPerCity: countPerCity)
    }

    // MARK: - City seed (existing demo)
    private func seedInitialPostsIfNeeded(countPerCity: Int) async {
        // If already have some fake_user_ posts, skip
        do {
            let snapshot = try await db.collection("posts")
                .whereField("userID", isGreaterThanOrEqualTo: "fake_user_")
                .whereField("userID", isLessThan: "fake_user_\u{f8ff}")
                .limit(to: 10)
                .getDocuments()
            if !snapshot.documents.isEmpty { return }
        } catch { /* continue */ }

        for (idx, city) in worldCities.enumerated() {
            for j in 0..<countPerCity {
                let uid = "fake_user_\(idx)_\(j)"
                let coord = jitteredCoordinate(lat: city.lat, lon: city.lon, meters: Double.random(in: 0...2500))
                let media = mixedMediaPool.randomElement() ?? ""
                let radius = radiusChoices.randomElement() ?? 5000
                await addPost(latitude: coord.latitude, longitude: coord.longitude, mediaURL: media, radius: radius, userID: uid)
            }
        }
    }

    // MARK: - GTA seeding (from earlier)
    func seedGTA(count: Int = 200) async {
        // Skip if already seeded
        do {
            let snapshot = try await db.collection("posts")
                .whereField("userID", isGreaterThanOrEqualTo: "fake_gta_")
                .whereField("userID", isLessThan: "fake_gta_\u{f8ff}")
                .limit(to: 1)
                .getDocuments()
            if !snapshot.documents.isEmpty {
                print("FakePostService: GTA seed already present; skipping.")
                return
            }
        } catch { /* continue */ }

        for i in 0..<count {
            let coord = randomGTACoordinate()
            let uid = String(format: "fake_gta_%04d", i + 1)
            let media = mixedMediaPool.randomElement() ?? ""
            let radius = radiusChoices.randomElement() ?? 5000
            await addPost(latitude: coord.latitude, longitude: coord.longitude, mediaURL: media, radius: radius, userID: uid)
        }
        print("FakePostService: Seeded \(count) GTA posts.")
    }

    // MARK: - New: North America seeding (1000 posts across CA/US)
    func seedInitialNorthAmerica(total: Int = 1000) async {
        // Skip if already seeded NA users
        do {
            let snapshot = try await db.collection("posts")
                .whereField("userID", isGreaterThanOrEqualTo: "na_user_")
                .whereField("userID", isLessThan: "na_user_\u{f8ff}")
                .limit(to: 1)
                .getDocuments()
            if !snapshot.documents.isEmpty {
                print("FakePostService: NA seed already present; skipping.")
                return
            }
        } catch { /* continue */ }

        // Split Canada/USA (roughly 40/60)
        let caCount = Int(Double(total) * 0.4)
        let usCount = total - caCount

        for i in 0..<caCount {
            let city = canadaCities.randomElement()!
            let coord = jitteredCoordinate(lat: city.lat, lon: city.lon, meters: Double.random(in: 0...8000))
            let uid = String(format: "na_user_ca_%04d", i + 1)
            let media = mixedMediaPool.randomElement() ?? ""
            let radius = radiusChoices.randomElement() ?? 5000
            await addPost(latitude: coord.latitude, longitude: coord.longitude, mediaURL: media, radius: radius, userID: uid)
        }

        for i in 0..<usCount {
            let city = usaCities.randomElement()!
            let coord = jitteredCoordinate(lat: city.lat, lon: city.lon, meters: Double.random(in: 0...8000))
            let uid = String(format: "na_user_us_%04d", i + 1)
            let media = mixedMediaPool.randomElement() ?? ""
            let radius = radiusChoices.randomElement() ?? 5000
            await addPost(latitude: coord.latitude, longitude: coord.longitude, mediaURL: media, radius: radius, userID: uid)
        }

        print("FakePostService: Seeded \(total) NA posts (CA \(caCount), US \(usCount)).")
    }

    // MARK: - New: World simulator (daily posts + engagement)

    /// Start the simulator. devDailySeconds compresses a "day" to a short interval for testing.
    func startWorldSimulator(devDailySeconds: TimeInterval = 120) {
        stopWorldSimulator()

        // Daily posts (~200 per simulated day)
        dailyTimer = Timer.scheduledTimer(withTimeInterval: max(10, devDailySeconds), repeats: true) { [weak self] _ in
            Task { await self?.dailyWorldPosts(count: 200) }
        }

        // Engagement tick (every 60–120s)
        engagementTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
            Task { await self?.performEngagementTick() }
        }

        print("FakePostService: World simulator started (day=\(devDailySeconds)s).")
    }

    func stopWorldSimulator() {
        dailyTimer?.invalidate(); dailyTimer = nil
        engagementTimer?.invalidate(); engagementTimer = nil
        print("FakePostService: World simulator stopped.")
    }

    private func dailyWorldPosts(count: Int) async {
        // Distribute across world cities
        for _ in 0..<count {
            guard let city = worldCities.randomElement() else { continue }
            let coord = jitteredCoordinate(lat: city.lat, lon: city.lon, meters: Double.random(in: 0...15000))
            let uid = String(format: "world_user_%04d", Int.random(in: 1...9999))
            let media = mixedMediaPool.randomElement() ?? ""
            let radius = radiusChoices.randomElement() ?? 5000
            await addPost(latitude: coord.latitude, longitude: coord.longitude, mediaURL: media, radius: radius, userID: uid)
        }
        print("FakePostService: Added \(count) world posts this simulated day.")
    }

    private func performEngagementTick() async {
        // Pick some random "users" near random cities and engage with nearby posts.
        // We'll do a handful of engagements to avoid heavy write load.
        let iterations = 60
        for _ in 0..<iterations {
            guard let city = worldCities.randomElement() else { continue }
            let userCoord = jitteredCoordinate(lat: city.lat, lon: city.lon, meters: Double.random(in: 0...20000))
            await engageNearbyPosts(around: CLLocationCoordinate2D(latitude: userCoord.latitude, longitude: userCoord.longitude),
                                    withinMeters: Double.random(in: 3000...15000),
                                    engagements: Int.random(in: 1...4))
        }
        print("FakePostService: Engagement tick completed.")
    }

    private func engageNearbyPosts(around center: CLLocationCoordinate2D, withinMeters radius: Double, engagements: Int) async {
        // Approximate by querying all posts and filtering in client (simple, but not scalable).
        // For a demo, this is acceptable; for production, use geohashing or a proper geo index.
        do {
            let snapshot = try await db.collection("posts").limit(to: 300).getDocuments()
            var candidates: [(id: String, distance: Double)] = []
            for doc in snapshot.documents {
                let data = doc.data()
                guard let lat = (data["latitude"] as? Double) ?? (data["latitude"] as? NSNumber)?.doubleValue,
                      let lon = (data["longitude"] as? Double) ?? (data["longitude"] as? NSNumber)?.doubleValue else { continue }
                let d = Self.distanceMeters(from: center, to: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                if d <= radius {
                    candidates.append((id: doc.documentID, distance: d))
                }
            }
            candidates.shuffle()
            let selected = candidates.prefix(engagements)
            for item in selected {
                try await incrementViewCountAndMaybeRadius(postID: item.id)
            }
        } catch {
            print("FakePostService: engageNearbyPosts error \(error.localizedDescription)")
        }
    }

    private func incrementViewCountAndMaybeRadius(postID: String) async throws {
        let ref = db.collection("posts").document(postID)
        try await ref.updateData(["viewCount": FieldValue.increment(Int64(1))])
        // Mirror your client rule: every 10 views, +1000m radius.
        let snap = try await ref.getDocument()
        if let data = snap.data() {
            let viewCount = (data["viewCount"] as? Int) ?? (data["viewCount"] as? NSNumber)?.intValue ?? 0
            var radius = (data["radius"] as? Int) ?? (data["radius"] as? NSNumber)?.intValue ?? 0
            if viewCount > 0 && viewCount % 10 == 0 {
                radius += 1000
                try? await ref.updateData(["radius": radius])
            }
        }
    }

    // MARK: - World cities, Canada, USA lists

    private let worldCities: [(name: String, lat: Double, lon: Double)] = [
        ("San Francisco", 37.7749, -122.4194),
        ("New York", 40.7128, -74.0060),
        ("London", 51.5074, -0.1278),
        ("Paris", 48.8566, 2.3522),
        ("Tokyo", 35.6895, 139.6917),
        ("Sydney", -33.8688, 151.2093),
        ("Rio", -22.9068, -43.1729),
        ("Toronto", 43.6532, -79.3832),
        ("Mexico City", 19.4326, -99.1332),
        ("Cape Town", -33.9249, 18.4241),
        ("Berlin", 52.5200, 13.4050),
        ("Rome", 41.9028, 12.4964),
        ("Madrid", 40.4168, -3.7038),
        ("Dubai", 25.2048, 55.2708),
        ("Singapore", 1.3521, 103.8198),
        ("Hong Kong", 22.3193, 114.1694),
        ("Seoul", 37.5665, 126.9780),
        ("Los Angeles", 34.0522, -118.2437),
        ("Chicago", 41.8781, -87.6298),
        ("Vancouver", 49.2827, -123.1207)
    ]

    private let canadaCities: [(name: String, lat: Double, lon: Double)] = [
        ("Toronto", 43.6532, -79.3832),
        ("Vancouver", 49.2827, -123.1207),
        ("Montreal", 45.5017, -73.5673),
        ("Calgary", 51.0447, -114.0719),
        ("Ottawa", 45.4215, -75.6972),
        ("Edmonton", 53.5461, -113.4938),
        ("Winnipeg", 49.8951, -97.1384),
        ("Quebec City", 46.8139, -71.2080),
        ("Halifax", 44.6488, -63.5752),
        ("Victoria", 48.4284, -123.3656)
    ]

    private let usaCities: [(name: String, lat: Double, lon: Double)] = [
        ("New York", 40.7128, -74.0060),
        ("Los Angeles", 34.0522, -118.2437),
        ("Chicago", 41.8781, -87.6298),
        ("Houston", 29.7604, -95.3698),
        ("Phoenix", 33.4484, -112.0740),
        ("Philadelphia", 39.9526, -75.1652),
        ("San Antonio", 29.4241, -98.4936),
        ("San Diego", 32.7157, -117.1611),
        ("Dallas", 32.7767, -96.7970),
        ("San Jose", 37.3382, -121.8863)
    ]

    // MARK: - Random helpers

    private func addRandomWorldPost() async {
        guard let city = worldCities.randomElement() else { return }
        let uid = "fake_user_\(Int.random(in: 1000...9999))"
        let coord = jitteredCoordinate(lat: city.lat, lon: city.lon, meters: Double.random(in: 0...5000))
        let media = mixedMediaPool.randomElement() ?? ""
        let radius = radiusChoices.randomElement() ?? 5000
        await addPost(latitude: coord.latitude, longitude: coord.longitude, mediaURL: media, radius: radius, userID: uid)
    }

    private func addPost(latitude: Double, longitude: Double, mediaURL: String, radius: Int, userID: String) async {
        let nowMillis = Int64(Date().timeIntervalSince1970 * 1000)
        let data: [String: Any] = [
            "latitude": latitude,
            "longitude": longitude,
            "mediaURL": mediaURL,
            "radius": radius,
            "viewCount": 0,
            "userID": userID,
            "createdAt": FieldValue.serverTimestamp(),
            "createdAtMillis": nowMillis
        ]
        do {
            _ = try await db.collection("posts").addDocument(data: data)
        } catch {
            print("FakePostService: failed to write post: \(error.localizedDescription)")
        }
    }

    // Jitter coordinate by ~meters using simple great-circle math
    private func jitteredCoordinate(lat: Double, lon: Double, meters: Double) -> (latitude: Double, longitude: Double) {
        guard meters > 0 else { return (lat, lon) }
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

    // GTA bounding box
    private func randomGTACoordinate() -> (latitude: Double, longitude: Double) {
        let latMin = 43.30
        let latMax = 44.10
        let lonMin = -80.00
        let lonMax = -78.80
        let lat = Double.random(in: latMin...latMax)
        let lon = Double.random(in: lonMin...lonMax)
        return (lat, lon)
    }

    // MARK: - Distance helper

    static func distanceMeters(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let ca = CLLocation(latitude: a.latitude, longitude: a.longitude)
        let cb = CLLocation(latitude: b.latitude, longitude: b.longitude)
        return ca.distance(from: cb)
    }
}
