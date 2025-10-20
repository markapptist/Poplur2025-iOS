import SwiftUI
import MapKit
import FirebaseAuth
import FirebaseFirestore

struct MapView: View {
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194), // Initial region (e.g., San Francisco)
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var posts: [Post] = [] // Holds the user's posts
    @State private var annotations: [PostAnnotation] = [] // Holds map annotations
    // Tune this as needed for your product
    private let maxRadiusForBar: Int = 10_000
    
    var body: some View {
        VStack {
            // Map view that will show posts as annotations
            Map(coordinateRegion: $region, interactionModes: .all, showsUserLocation: true, annotationItems: annotations) { annotation in
                MapAnnotation(coordinate: annotation.coordinate) {
                    VStack(spacing: 4) {
                        VerticalRadiusBar(
                            radius: annotation.post.radius,
                            maxRadius: maxRadiusForBar,
                            width: 6,
                            maxHeight: 60,
                            color: .blue,
                            showsLabel: false
                        )
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                            .overlay(Circle().stroke(Color.white, lineWidth: 1))
                            .shadow(radius: 1)
                    }
                }
            }
            .edgesIgnoringSafeArea(.all)
            
            if posts.isEmpty {
                Text("No posts available.")
                    .foregroundColor(.gray)
            }
        }
        .onAppear {
            fetchPosts()
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
            }
        }
    }
}

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
