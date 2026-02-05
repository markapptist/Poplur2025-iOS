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

// Lightweight model for annotations (renamed to avoid conflicts with other Post types)
private struct MapAnnotationPost: Identifiable, Hashable {
    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: MapAnnotationPost, rhs: MapAnnotationPost) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.coordinate.latitude == rhs.coordinate.latitude && lhs.coordinate.longitude == rhs.coordinate.longitude
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }
}

// Simple location manager to get current user location and authorization
private final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var location: CLLocation?
    private let manager = CLLocationManager()

    override init() {
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    func requestAuthorizationIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func centerOnUser(_ map: inout MapCameraPosition?) {
        guard let loc = location else { return }
        // Keep a pleasant 3D angle when centering
        map = .camera(MapCamera(
            centerCoordinate: loc.coordinate,
            distance: 800,
            heading: 0,
            pitch: 55
        ))
    }

    // MARK: CLLocationManagerDelegate
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

// A simple 3D radius bar using SceneKit embedded via SwiftUI
private struct RadiusBar3D: View {
    @Binding var radius: Double // meters

    var body: some View {
        VStack {
            SceneView(
                scene: makeScene(),
                options: [.allowsCameraControl]
            )
            .frame(width: 44, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                VStack {
                    Text("\(Int(radius/1000)) km")
                        .font(.caption2)
                        .padding(.top, 4)
                    Spacer()
                }
            )
            Slider(value: Binding(
                get: { min(max(radius, 100), 50_000) },
                set: { radius = min(max($0, 100), 50_000) }
            ), in: 100...50_000)
            .rotationEffect(.degrees(-90))
            .frame(height: 44)
            .opacity(0.001) // invisible slider capturing vertical drags
        }
        .frame(width: 44)
    }

    private func makeScene() -> SCNScene {
        let scene = SCNScene()
        // A simple bar that scales with radius
        let bar = SCNBox(width: 0.3, height: CGFloat(0.5 + min(radius, 50_000) / 50_000), length: 0.3, chamferRadius: 0.05)
        let node = SCNNode(geometry: bar)
        node.geometry?.firstMaterial?.diffuse.contents = UIColor.systemTeal
        node.position = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(node)

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 1
        let camNode = SCNNode()
        camNode.camera = camera
        camNode.position = SCNVector3(0, 0, 3)
        scene.rootNode.addChildNode(camNode)

        let light = SCNLight()
        light.type = .omni
        let lightNode = SCNNode()
        lightNode.light = light
        lightNode.position = SCNVector3(0, 5, 5)
        scene.rootNode.addChildNode(lightNode)

        return scene
    }
}

// Lightweight Google-style pin replacement when GoogleMaps3D.Pin is unavailable
private struct GoogleStylePin: View {
    var body: some View {
        ZStack {
            // Pin body
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let circleDiameter = min(w, h) * 0.6
                let tipHeight = h - circleDiameter

                VStack(spacing: 0) {
                    Circle()
                        .fill(LinearGradient(colors: [Color.red, Color.red.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                        .frame(width: circleDiameter, height: circleDiameter)
                        .overlay(
                            Circle().stroke(Color.white.opacity(0.9), lineWidth: circleDiameter * 0.06)
                        )
                        .shadow(color: Color.black.opacity(0.25), radius: 2, x: 0, y: 1)

                    Triangle()
                        .fill(LinearGradient(colors: [Color.red.opacity(0.95), Color.red.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                        .frame(width: circleDiameter * 0.4, height: tipHeight)
                        .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 1)
                        .offset(y: -1)
                }
                .frame(width: w, height: h, alignment: .top)
            }
        }
        .aspectRatio(0.6, contentMode: .fit)
    }
}

// Simple triangle shape for the pin tip
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

struct MapView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var camera: MapCameraPosition? = .camera(MapCamera(
        centerCoordinate: CLLocationCoordinate2D(latitude: 40.748339, longitude: -73.985912),
        distance: 1039,
        heading: 52,
        pitch: 68
    ))
    @State private var posts: [MapAnnotationPost] = []
    @State private var radiusMeters: Double = 5_000 // default 5km

    var body: some View {
        ZStack(alignment: .topTrailing) {
            mapLayer

            // Current location floating button
            VStack(spacing: 12) {
                Button(action: {
                    locationManager.centerOnUser(&camera)
                }) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Circle().fill(.blue))
                        .shadow(radius: 3)
                }

                // 3D radius bar
                RadiusBar3D(radius: $radiusMeters)
            }
            .padding(.trailing, 12)
            .padding(.top, 12)
        }
        .onAppear {
            locationManager.requestAuthorizationIfNeeded()
            fetchPosts()
        }
    }

    private var mapLayer: some View {
        Map(position: Binding(get: { camera ?? .automatic }, set: { newValue in
            camera = newValue
        })) {
            // User location annotation if available
            if locationManager.location != nil {
                UserAnnotation() {
                    Label("You", systemImage: "location.fill")
                }
            }

            // Posts with Google-style pin visuals
            ForEach(filteredPosts(), id: \ .id) { post in
                Annotation(coordinate: post.coordinate) {
                    GoogleStylePin()
                        .frame(width: 32, height: 32)
                        .accessibilityLabel(Text(post.title))
                } label: {
                    Text(post.title)
                }
            }
        }
        .mapStyle(.hybrid(elevation: .realistic))
    }

    private func filteredPosts() -> [MapAnnotationPost] {
        guard let userLoc = locationManager.location else { return posts }
        return posts.filter { post in
            let d = MKMapPoint(userLoc.coordinate).distance(to: MKMapPoint(post.coordinate))
            return d <= radiusMeters
        }
    }

    private func fetchPosts() {
        let db = Firestore.firestore()
        db.collection("posts").getDocuments { snapshot, error in
            if let error = error {
                print("Error fetching posts: \(error)")
                return
            }
            guard let docs = snapshot?.documents else { return }
            let mapped: [MapAnnotationPost] = docs.compactMap { doc in
                let data = doc.data()
                guard let lat = data["latitude"] as? CLLocationDegrees,
                      let lon = data["longitude"] as? CLLocationDegrees else { return nil }
                let title = (data["title"] as? String) ?? "Post"
                return MapAnnotationPost(id: doc.documentID, title: title, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
            self.posts = mapped
        }
    }
}

