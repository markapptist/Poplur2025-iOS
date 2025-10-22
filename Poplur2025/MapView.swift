import SwiftUI
import MapKit
import FirebaseAuth
import FirebaseFirestore
import CoreLocation

struct MapView: View {
    // Region will continuously follow user when coordinates update.
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var posts: [Post] = []
    @State private var annotations: [PostAnnotation] = []
    // Side bar shows the selected post's radius
    @State private var selectedPost: Post?

    // Tune this as needed for your product
    private let maxRadiusForBar: Int = 10_000

    // Location handling
    @StateObject private var locationManager = MapLocationManager()
    @State private var showLocationAlert = false
    @State private var locationAlertMessage = ""

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Map(
                    coordinateRegion: $region,
                    interactionModes: .all,
                    showsUserLocation: true,
                    annotationItems: annotations
                ) { annotation in
                    MapAnnotation(coordinate: annotation.coordinate) {
                        Button {
                            // Select this post to update the side bar
                            selectedPost = annotation.post
                        } label: {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.white, lineWidth: 1))
                                .shadow(radius: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .edgesIgnoringSafeArea(.all)

                if posts.isEmpty {
                    Text("No posts available.")
                        .foregroundColor(.gray)
                        .padding(.top, 8)
                }
            }

            // Right-pinned side bar showing the selected post's radius
            if let selected = selectedPost {
                VStack {
                    Spacer()
                    // You can tweak maxHeight/width/color as desired
                    VerticalRadiusBar(
                        radius: selected.radius,
                        maxRadius: maxRadiusForBar,
                        width: 10,
                        maxHeight: 160,
                        color: .pink,
                        showsLabel: true,
                        labelFormat: { r in
                            if r >= 1000 {
                                return "\(r / 1000) km"
                            } else {
                                return "\(r) m"
                            }
                        }
                    )
                    .padding(.trailing, 12)
                    .padding(.bottom, 32) // keep above any bottom bars
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .allowsHitTesting(false) // bar is visual only; taps pass through to map
            }
        }
        .onAppear {
            // Start location updates
            locationManager.requestWhenInUse()
            // Load posts for the current user
            fetchPosts()
        }
        // Recenter on every coordinate update (always follow the user)
        .onReceive(locationManager.$coordinate.compactMap { $0 }) { coord in
            withAnimation(.easeInOut(duration: 0.2)) {
                region.center = coord
                region.span = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
            }
        }
        .onReceive(locationManager.$authorizationStatus) { status in
            switch status {
            case .denied, .restricted:
                locationAlertMessage = "Location access is disabled. Enable it in Settings to keep the map centered on your current location."
                showLocationAlert = true
            default:
                break
            }
        }
        .alert("Location Access", isPresented: $showLocationAlert) {
            Button("OK", role: .cancel) { }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                }
            }
        } message: {
            Text(locationAlertMessage)
        }
    }

    func fetchPosts() {
        // Fetch posts from Firestore and create annotations
        if let userId = Auth.auth().currentUser?.uid {
            let db = Firestore.firestore()
            db.collection("posts").whereField("userID", isEqualTo: userId).getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching posts: \(error.localizedDescription)")
                    return
                }

                // Parse posts and create annotations
                self.posts = snapshot?.documents.compactMap { document -> Post? in
                    let data = document.data()
                    return Post(
                        id: document.documentID,
                        latitude: data["latitude"] as? Double ?? 0.0,
                        longitude: data["longitude"] as? Double ?? 0.0,
                        mediaURL: data["mediaURL"] as? String ?? "",
                        radius: data["radius"] as? Int ?? 0,
                        viewCount: data["viewCount"] as? Int ?? 0
                    )
                } ?? []

                // Create annotations for the posts
                self.annotations = self.posts.map { post in
                    PostAnnotation(post: post)
                }

                // If nothing selected yet, optionally select the first post
                if selectedPost == nil, let first = self.posts.first {
                    selectedPost = first
                }
            }
        }
    }
}

// MARK: - Location Manager for MapView

final class MapLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        // manager.distanceFilter = 20 // optional tuning
    }

    func requestWhenInUse() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            authorizationStatus = manager.authorizationStatus
        @unknown default:
            authorizationStatus = manager.authorizationStatus
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate = locations.last?.coordinate
        // Keep updating to always follow the user
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location update failed: \(error.localizedDescription)")
    }
}

// MARK: - Existing Models

struct PostAnnotation: Identifiable {
    var id = UUID() // Unique identifier for the annotation
    var post: Post

    var coordinate: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: post.latitude, longitude: post.longitude)
    }
}

struct Post: Identifiable {
    var id: String
    var latitude: Double
    var longitude: Double
    var mediaURL: String
    var radius: Int
    var viewCount: Int
}

struct MapView_Previews: PreviewProvider {
    static var previews: some View {
        MapView()
    }
}
