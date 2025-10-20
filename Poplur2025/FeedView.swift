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
                VStack {
                    Text("Location: \(post.latitude), \(post.longitude)")
                    AsyncImage(url: URL(string: post.mediaURL)) { image in
                        image.resizable()
                             .scaledToFit()
                             .frame(width: 100, height: 100)
                    } placeholder: {
                        ProgressView()
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
            guard let snapshot = snapshot else { return }
            
            for document in snapshot.documents {
                let data = document.data()
                let post = Post(id: document.documentID, latitude: data["latitude"] as! Double, longitude: data["longitude"] as! Double, mediaURL: data["mediaURL"] as! String, radius: data["radius"] as! Int, viewCount: data["radius"] as! Int)
                posts.append(post)
            }
        }
    }
    
    func incrementViewCount(postID: String) {
        let db = Firestore.firestore()
        let postRef = db.collection("posts").document(postID)
        
        postRef.updateData([
            "viewCount": FieldValue.increment(Int64(1))
        ]) { error in
            if error == nil {
                checkAndIncreaseRadius(postRef: postRef)
            }
        }
    }
    
    func checkAndIncreaseRadius(postRef: DocumentReference) {
        postRef.getDocument { document, error in
            guard let document = document, document.exists else { return }
            let data = document.data()!
            let viewCount = data["viewCount"] as! Int
            var radius = data["radius"] as! Int
            
            if viewCount % 10 == 0 { // Increase radius after 10 views
                radius += 1000
                postRef.updateData(["radius": radius])
            }
        }
    }
}

#Preview {
    FeedView()
}


