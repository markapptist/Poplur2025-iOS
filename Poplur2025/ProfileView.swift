import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import CoreLocation

private enum ProfileLayout: Hashable {
    case list
    case grid
}

struct ProfileView: View {
    @State private var user: UserProfile?
    @State private var posts: [Post] = []
    @State private var isEditingProfile = false

    // Loading/error states
    @State private var isLoadingUser = true
    @State private var userLoadError: String?

    // Deterministic readiness
    @State private var profileReady = false
    @State private var didLoadUserOnce = false
    @State private var didLoadPostsOnce = false

    // UI state
    @State private var layout: ProfileLayout = .list

    // Config
    private let accumulatedMaxRadius: Int = 50_000

    private var totalRadius: Int {
        posts.reduce(0) { $0 + $1.radius }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                toggleBar

                if isLoadingUser {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .padding(.top, 16)
                } else if let userLoadError {
                    Text(userLoadError)
                        .font(.footnote)
                        .foregroundColor(.red)
                }

                if posts.isEmpty {
                    VStack(spacing: 8) {
                        Text("No Posts Yet")
                            .font(.title3.weight(.semibold))
                            .foregroundColor(.secondary)
                        Text("Upload your first post to see it here.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity)
                } else {
                    switch layout {
                    case .list:
                        listContent
                    case .grid:
                        gridContent
                    }
                }

                // Accumulated radius section
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

                Button(action: { isEditingProfile.toggle() }) {
                    Text("Edit Profile")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                }
                .padding(.top, 8)

                Button(action: { logOut() }) {
                    Text("Log Out")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
                .padding(.top, 4)
            }
            .padding(.vertical, 16)
        }
        .sheet(isPresented: $isEditingProfile) {
            EditProfileView(user: $user)
        }
        .onAppear {
            fetchUserData()
            fetchUserPosts()
        }
        .background(Color.clear)
        .toolbarBackground(.clear, for: .tabBar)
        .toolbar(.visible, for: .tabBar)
        .preference(key: ProfileReadyPreferenceKey.self, value: profileReady)
    }

    // MARK: - Header

    private var header: some View {
        let headerUser = user ?? fallbackUserFromAuth()
        return VStack(spacing: 10) {
            // Avatar
            if let url = headerUser.profilePictureURL {
                AsyncImage(url: url) { image in
                    image.resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                } placeholder: {
                    Circle().fill(Color.gray.opacity(0.3))
                        .frame(width: 96, height: 96)
                }
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 96, height: 96)
            }

            // Username
            Text(headerUser.username.uppercased())
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .kerning(0.8)
                .foregroundColor(.primary)
        }
    }

    // MARK: - Toggle

    private var toggleBar: some View {
        HStack(spacing: 28) {
            toggleItem(system: "list.bullet", isActive: layout == .list) {
                layout = .list
            }
            toggleItem(system: "square.grid.2x2", isActive: layout == .grid) {
                layout = .grid
            }
        }
        .padding(.top, 8)
    }

    private func toggleItem(system: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: system)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.primary.opacity(isActive ? 1.0 : 0.5))
            }
            Rectangle()
                .fill(isActive ? Color.accentColor : Color.clear)
                .frame(width: 28, height: 3)
                .cornerRadius(1.5)
        }
    }

    // MARK: - Grid

    private var gridContent: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        return LazyVGrid(columns: columns, spacing: 12) {
            ForEach(posts) { post in
                GridCell(mediaURL: post.mediaURL)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private struct GridCell: View {
        let mediaURL: String
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.gray.opacity(0.15))
                if let url = URL(string: mediaURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.gray)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Image(systemName: "photo")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.secondary)
                        @unknown default:
                            Color.clear
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }

    // MARK: - List

    private var listContent: some View {
        LazyVStack(spacing: 20) {
            ForEach(posts) { post in
                ListCard(post: post)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.top, 8)
    }

    private struct ListCard: View {
        let post: Post

        private var radiusText: String {
            if post.radius >= 1000 {
                return "\(post.radius / 1000) KM"
            } else {
                return "\(post.radius) M"
            }
        }

        var body: some View {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.gray.opacity(0.15))

                if let url = URL(string: post.mediaURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Color.black.opacity(0.2)
                        @unknown default:
                            Color.black.opacity(0.2)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    Color.black.opacity(0.2)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                // Gradient overlay for legible text
                LinearGradient(
                    colors: [Color.black.opacity(0.55), Color.black.opacity(0.15), .clear],
                    startPoint: .bottom, endPoint: .top
                )
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(radiusText)
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .shadow(radius: 3, y: 2)

                    // Placeholder for location/city line (requires reverse geocoding to be accurate)
                    // For now, show coordinates or "WORLDWIDE"
                    if post.latitude != 0 || post.longitude != 0 {
                        Text("\(String(format: "%.4f", post.latitude)), \(String(format: "%.4f", post.longitude))")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(radius: 3, y: 2)
                    } else {
                        Text("WORLDWIDE")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(radius: 3, y: 2)
                    }
                }
                .padding(16)
            }
            .frame(height: 220)
            .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 8)
        }
    }

    // MARK: - Data + readiness

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

// MARK: - Readiness PreferenceKey for ProfileView

struct ProfileReadyPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
