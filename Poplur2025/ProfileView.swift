import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

struct ProfileView: View {
    @State private var user: UserProfile? // Holds user data from Firestore
    @State private var posts: [Post] = [] // Holds the user's posts
    @State private var isEditingProfile = false // To toggle profile editing mode
    
    var body: some View {
        VStack {
            if let user = user {
                // Profile Section
                HStack {
                    if let imageUrl = user.profilePictureURL {
                        AsyncImage(url: imageUrl) { image in
                            image.resizable()
                                 .scaledToFill()
                                 .frame(width: 100, height: 100)
                                 .clipShape(Circle())
                        } placeholder: {
                            ProgressView()
                        }
                    } else {
                        Circle()
                            .frame(width: 100, height: 100)
                            .foregroundColor(.gray)
                    }
                    
                    VStack(alignment: .leading) {
                        Text(user.username)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text(user.email)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                
                // Edit Profile Button
                Button(action: {
                    isEditingProfile.toggle()
                }) {
                    Text("Edit Profile")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .padding()
                
                // Posts Section
                Text("Your Posts")
                    .font(.headline)
                    .padding(.top)
                
                if posts.isEmpty {
                    Text("No posts yet.")
                        .foregroundColor(.gray)
                } else {
                    List(posts) { post in
                        VStack(alignment: .leading) {
                            // Check if the mediaURL is not empty and valid
                            if !post.mediaURL.isEmpty, let url = URL(string: post.mediaURL) {
                                AsyncImage(url: url) { image in
                                    image.resizable()
                                         .scaledToFit()
                                         .frame(height: 200)
                                         .cornerRadius(10)
                                } placeholder: {
                                    ProgressView()
                                }
                            }
                            
                            Text("Latitude: \(post.latitude), Longitude: \(post.longitude)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.bottom)
                    }
                }
            } else {
                ProgressView() // Loading user data
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
            }
            
            // Log out button
            Button(action: {
                logOut()
            }) {
                Text("Log Out")
                    .font(.subheadline)
                    .foregroundColor(.red)
            }
            .padding(.top)
        }
        .onAppear {
            fetchUserData()
            fetchUserPosts()
        }
        .sheet(isPresented: $isEditingProfile) {
            // Profile editing UI can go here
            EditProfileView(user: $user)
        }
    }
    
    func fetchUserData() {
        // Fetch user data from Firestore using Firebase Authentication
        if let userId = Auth.auth().currentUser?.uid {
            let db = Firestore.firestore()
            db.collection("users").document(userId).getDocument { document, error in
                if let document = document, document.exists {
                    let data = document.data()
                    self.user = UserProfile(
                        username: data?["username"] as? String ?? "Unknown",
                        email: data?["email"] as? String ?? "No email",
                        profilePictureURL: URL(string: data?["profilePictureURL"] as? String ?? "")
                    )
                } else {
                    print("User data not found or error: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }
    
    func fetchUserPosts() {
        // Fetch posts of the user from Firestore
        if let userId = Auth.auth().currentUser?.uid {
            let db = Firestore.firestore()
            db.collection("posts").whereField("userID", isEqualTo: userId).getDocuments { snapshot, error in
                if let error = error {
                    print("Error fetching posts: \(error.localizedDescription)")
                    return
                }
                
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
            }
        }
    }
    
    func logOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            print("Error signing out: \(error.localizedDescription)")
        }
    }
}

struct UserProfile {
    var username: String
    var email: String
    var profilePictureURL: URL?
}

struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
    }
}
