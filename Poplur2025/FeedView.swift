//
//  FeedView.swift
//  Poplur2025
//
//  Created by Apptist Inc. on 2025-08-03.
//


import SwiftUI
import MapKit
import FirebaseFirestore

struct FeedView: View {
    @State private var posts: [Post] = []
    
    var body: some View {
        VStack {
            Text("Nearby Posts")
                .font(.title)
                .padding()
            
            List(posts) { post in
                HStack(alignment: .center, spacing: 12) {
                    VerticalRadiusBar(
                        radius: post.radius,
                        maxRadius: 10_000,
                        width: 8,
                        maxHeight: 80,
                        color: .blue,
                        showsLabel: true
                    )
                    
                    VStack(alignment: .leading) {
                        Text("Location: \(post.latitude), \(post.longitude)")
                        AsyncImage(url: URL(string: post.mediaURL)) { image in
                            image.resizable()
                                 .scaledToFit()
                                 .frame(width: 100, height: 100)
                        } placeholder: {
                            ProgressView()
                        }
                    }
                }
                .onTapGesture {
                    incrementViewCount(postID: post.id)
                }
            }
            .onAppear {
                loadPosts()
            }
        }
    }
    
    func loadPosts() {
        let db = Firestore.firestore()
        db.collection("posts").getDocuments { snapshot, error in
            if let error = error {
                print("Error loading posts: \(error.localizedDescription)")
                return
            }
            guard let snapshot = snapshot else {
                self.posts = []
                return
            }
            
            // Safely parse documents
            let newPosts: [Post] = snapshot.documents.compactMap { document in
                let data = document.data()
                
                // latitude/longitude can be Double or NSNumber
                let latitude = (data["latitude"] as? Double)
                    ?? (data["latitude"] as? NSNumber)?.doubleValue
                let longitude = (data["longitude"] as? Double)
                    ?? (data["longitude"] as? NSNumber)?.doubleValue
                
                // radius and viewCount can be Int or NSNumber
                let radius = (data["radius"] as? Int)
                    ?? (data["radius"] as? NSNumber)?.intValue
                let viewCount = (data["viewCount"] as? Int)
                    ?? (data["viewCount"] as? NSNumber)?.intValue
                
                let mediaURL = data["mediaURL"] as? String ?? ""
                
                // If lat/long are missing, skip this post
                guard let lat = latitude, let lon = longitude else { return nil }
                
                return Post(
                    id: document.documentID,
                    latitude: lat,
                    longitude: lon,
                    mediaURL: mediaURL,
                    radius: radius ?? 0,
                    viewCount: viewCount ?? 0
                )
            }
            
            // Assign once to avoid duplicates on repeated onAppear
            self.posts = newPosts
        }
    }
    
    func incrementViewCount(postID: String) {
        let db = Firestore.firestore()
        let postRef = db.collection("posts").document(postID)
        
        postRef.updateData([
            "viewCount": FieldValue.increment(Int64(1))
        ]) { error in
            if let error = error {
                print("Failed to increment view count: \(error.localizedDescription)")
                return
            }
            checkAndIncreaseRadius(postRef: postRef)
        }
    }
    
    func checkAndIncreaseRadius(postRef: DocumentReference) {
        postRef.getDocument { document, error in
            if let error = error {
                print("Failed to fetch post for radius check: \(error.localizedDescription)")
                return
            }
            guard let document = document, document.exists, let data = document.data() else { return }
            
            let viewCount = (data["viewCount"] as? Int)
                ?? (data["viewCount"] as? NSNumber)?.intValue
                ?? 0
            var radius = (data["radius"] as? Int)
                ?? (data["radius"] as? NSNumber)?.intValue
                ?? 0
            
            if viewCount % 10 == 0 { // Increase radius after 10 views
                radius += 1000
                postRef.updateData(["radius": radius]) { error in
                    if let error = error {
                        print("Failed to update radius: \(error.localizedDescription)")
                    } else {
                        // Optionally refresh local list to reflect new radius
                        loadPosts()
                    }
                }
            }
        }
    }
}

#Preview {
    FeedView()
}
