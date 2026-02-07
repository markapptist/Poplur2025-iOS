import SwiftUI
import MapKit
import FirebaseFirestore
import FirebaseAuth
import CoreLocation
import UserNotifications
import SceneKit
import GoogleMaps3D

enum GoogleMaps3DConfig {
    static let apiKey: String = "AIzaSyDgMYA1YisgbpEGyl0Nj8VGoorbqmfAkG0"
}

// MARK: - Constants (LOCKED CAMERA VALUES)
private let fixedDistance: CLLocationDistance = 1039   // 🔒 zoom / height
private let fixedPitch: CGFloat = 68                   // 🔒 pitch

// MARK: - Models
private struct MapAnnotationPost: Identifiable, Hashable {
    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D
    let radius: Double

    static func == (lhs: MapAnnotationPost, rhs: MapAnnotationPost) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}


// MARK: - Location Manager
private final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var location: CLLocation?
    private let manager = CLLocationManager()

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    func requestAuthorizationIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func centerOnUser(_ camera: inout MapCameraPosition?) {
        guard let loc = location else { return }
        camera = .camera(
            MapCamera(
                centerCoordinate: loc.coordinate,
                distance: fixedDistance,
                heading: 0,
                pitch: fixedPitch
            )
        )
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }
}

// MARK: - Google Style Pin
private struct GoogleStylePin: View {
    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(.red)
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(.white, lineWidth: 2))

            Triangle()
                .fill(.red)
                .frame(width: 10, height: 12)
                .offset(y: -1)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Map View
struct MapView: View {
    @StateObject private var locationManager = LocationManager()

    @State private var camera: MapCameraPosition? = .camera(
        MapCamera(
            centerCoordinate: CLLocationCoordinate2D(latitude: 40.748339, longitude: -73.985912),
            distance: fixedDistance,
            heading: 52,
            pitch: fixedPitch
        )
    )

    @State private var posts: [MapAnnotationPost] = []
    @State private var selectedIndex: Int?
    @State private var radiusMeters: Double = 5_000

    var body: some View {
        ZStack(alignment: .topTrailing) {
            mapLayer

            VStack(spacing: 12) {
                Button {
                    locationManager.centerOnUser(&camera)
                } label: {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Circle().fill(.blue))
                }

                HStack(spacing: 10) {
                    Button { cyclePost(direction: -1) } label: {
                        Image(systemName: "chevron.left")
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Circle().fill(.black.opacity(0.5)))
                    }

                    Button { cyclePost(direction: 1) } label: {
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(Circle().fill(.black.opacity(0.5)))
                    }
                }

                IsometricRadiusBar(radius: $radiusMeters)
                    .padding(.top, 40)
            }
            .padding(.trailing, 12)
            .padding(.top, 12)
        }
        .onAppear {
            locationManager.requestAuthorizationIfNeeded()
            fetchPosts()
        }
    }

    // MARK: - Map Layer (LOCKED ZOOM)
    private var mapLayer: some View {
        Map(
            position: Binding(
                get: { camera ?? .automatic },
                set: { camera = lockCamera($0) }
            ),
            interactionModes: [.pan, .rotate]
        ) {
            if locationManager.location != nil {
                UserAnnotation {
                    Label("You", systemImage: "location.fill")
                }
            }

            ForEach(filteredPosts()) { post in
                Annotation(coordinate: post.coordinate) {
                    GoogleStylePin()
                } label: {
                    Text(post.title)
                }

                MapCircle(center: post.coordinate, radius: post.radius)
                    .foregroundStyle(.blue.opacity(0.15))
                    .stroke(.blue.opacity(0.6), lineWidth: 1)
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
    }

    // MARK: - Camera Lock
    private func lockCamera(_ pos: MapCameraPosition) -> MapCameraPosition {
        pos.camera.map {
            .camera(
                MapCamera(
                    centerCoordinate: $0.centerCoordinate,
                    distance: fixedDistance,
                    heading: $0.heading,
                    pitch: fixedPitch
                )
            )
        } ?? pos
    }


    // MARK: - Navigation
    private func panTo(_ coordinate: CLLocationCoordinate2D) {
        let heading = camera?.camera?.heading ?? 0
        withAnimation(.easeInOut(duration: 0.8)) {
            camera = .camera(
                MapCamera(
                    centerCoordinate: coordinate,
                    distance: fixedDistance,
                    heading: heading,
                    pitch: fixedPitch
                )
            )
        }
    }

    private func cyclePost(direction: Int) {
        let items = filteredPosts()
        guard !items.isEmpty else { return }

        if let idx = selectedIndex {
            selectedIndex = (idx + direction + items.count) % items.count
        } else {
            selectedIndex = 0
        }

        if let idx = selectedIndex {
            panTo(items[idx].coordinate)
        }
    }

    // MARK: - Data
    private func filteredPosts() -> [MapAnnotationPost] {
        guard let userLoc = locationManager.location else { return posts }
        return posts.filter {
            MKMapPoint(userLoc.coordinate).distance(to: MKMapPoint($0.coordinate)) <= radiusMeters
        }
    }

    private func fetchPosts() {
        Firestore.firestore().collection("posts").getDocuments { snap, _ in
            posts = snap?.documents.compactMap { doc in
                let d = doc.data()
                guard let lat = d["latitude"] as? CLLocationDegrees,
                      let lon = d["longitude"] as? CLLocationDegrees else { return nil }

                return MapAnnotationPost(
                    id: doc.documentID,
                    title: d["title"] as? String ?? "Post",
                    coordinate: .init(latitude: lat, longitude: lon),
                    radius: (d["radius"] as? Double) ?? 5_000
                )
            } ?? []
        }
    }
}
