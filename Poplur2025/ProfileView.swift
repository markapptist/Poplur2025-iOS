import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

struct ProfileView: View {
    @State private var user: UserProfile? // Holds user data from Firestore (or fallback from Auth)
    @State private var posts: [Post] = [] // Holds the user's posts
    @State private var isEditingProfile = false // To toggle profile editing mode
    
    // Loading/error states to avoid infinite spinner
    @State private var isLoadingUser = true
    @State private var userLoadError: String?

    // Deterministic readiness
    @State private var profileReady = false
    @State private var didLoadUserOnce = false
    @State private var didLoadPostsOnce = false

    // Configuration for the accumulated radius visualization
    private let accumulatedMaxRadius: Int = 50_000 // 50 km default cap for scaling
    
    // Sum of all post radii (accumulated)
    private var totalRadius: Int {
        posts.reduce(0) { $0 + $1.radius }
    }
    
    var body: some View {
        VStack {
            if isLoadingUser {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .padding()
            } else {
                let headerUser = user ?? fallbackUserFromAuth()
                
                HStack {
                    if let imageUrl = headerUser.profilePictureURL {
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
                        Text(headerUser.username)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text(headerUser.email)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        if let userLoadError = userLoadError {
                            Text(userLoadError)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.top, 2)
                        }
                    }
                }
                .padding()
                
                Button(action: { isEditingProfile.toggle() }) {
                    Text("Edit Profile")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .padding()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Accumulated Radius")
                        .font(.headline)
                    HStack(alignment: .center, spacing: 12) {
                        VerticalRadiusBar(
                            radius: totalRadius,
                            maxRadius: accumulatedMaxRadius,
                            width: 10,
                            maxHeight: 120,
                            color: .green,
                            showsLabel: true,
                            labelFormat: { r in
                                if r >= 1000 {
                                    return "Total: \(r / 1000) km"
                                } else {
                                    return "Total: \(r) m"
                                }
                            }
                        )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total across \(posts.count) post(s)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Max scale: \(accumulatedMaxRadius / 1000) km")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                Text("Your Posts")
                    .font(.headline)
                    .padding(.top)
                
                if posts.isEmpty {
                    VStack(spacing: 8) {
                        Text("No Posts Yet")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        Text("Upload your first post to see it here.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 16)
                } else {
                    List(posts) { post in
                        VStack(alignment: .leading) {
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
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden) // hide List’s default white background
                    .listRowBackground(Color.clear)    // make each row transparent
                    .background(Color.clear)           // keep the List transparent
                }
            }
            
            Button(action: { logOut() }) {
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
            EditProfileView(user: $user)
        }
        .background(Color.clear)                  // make the whole tab transparent
        .toolbarBackground(.clear, for: .tabBar)  // keep tab bar area clear on this screen
        .toolbar(.visible, for: .tabBar)
        // Publish readiness once both user and posts have attempted to load
        .preference(key: ProfileReadyPreferenceKey.self, value: profileReady)
    }
    
    // Fallback user built from FirebaseAuth if Firestore user document is missing/unavailable
    private func fallbackUserFromAuth() -> UserProfile {
        let authUser = Auth.auth().currentUser
        let email = authUser?.email ?? "No email"
        let defaultUsername: String
        if let email = authUser?.email, let name = email.split(separator: "@").first {
            defaultUsername = String(name)
        } else {
            defaultUsername = "Unknown"
        }
        return UserProfile(username: user?.username ?? defaultUsername,
                           email: user?.email ?? email,
                           profilePictureURL: user?.profilePictureURL)
    }
    
    private func finishIfBothLoaded() {
        if didLoadUserOnce && didLoadPostsOnce && !profileReady {
            profileReady = true
        }
    }

    func fetchUserData() {
        isLoadingUser = true
        userLoadError = nil
        
        guard let userId = Auth.auth().currentUser?.uid else {
            self.user = nil
            self.userLoadError = "Not signed in."
            self.isLoadingUser = false
            self.didLoadUserOnce = true
            finishIfBothLoaded()
            return
        }
        
        let db = Firestore.firestore()
        db.collection("users").document(userId).getDocument { document, error in
            defer {
                self.isLoadingUser = false
                self.didLoadUserOnce = true
                self.finishIfBothLoaded()
            }
            
            if let error = error {
                self.user = self.fallbackUserFromAuth()
                self.userLoadError = "Failed to load profile: \(error.localizedDescription)"
                return
            }
            
            guard let document = document, document.exists else {
                self.user = self.fallbackUserFromAuth()
                self.userLoadError = "Profile not found. Using account info."
                return
            }
            
            let data = document.data()
            self.user = UserProfile(
                username: data?["username"] as? String ?? self.fallbackUserFromAuth().username,
                email: data?["email"] as? String ?? self.fallbackUserFromAuth().email,
                profilePictureURL: URL(string: data?["profilePictureURL"] as? String ?? "")
            )
        }
    }
    
    func fetchUserPosts() {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.posts = []
            self.didLoadPostsOnce = true
            self.finishIfBothLoaded()
            return
        }
        let db = Firestore.firestore()
        db.collection("posts").whereField("userID", isEqualTo: userId).getDocuments { snapshot, error in
            defer {
                self.didLoadPostsOnce = true
                self.finishIfBothLoaded()
            }
            if let error = error {
                print("Error fetching posts: \(error.localizedDescription)")
                self.posts = []
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
    
    func logOut() {
        do {
            try Auth.auth().signOut()
            self.user = nil
            self.posts = []
            self.userLoadError = "Not signed in."
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
