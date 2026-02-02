import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthViewModel

    @State private var editing = false
    @State private var userProfile: UserProfile?

    @State private var myPosts: [Post] = []
    @State private var isLoading = false

    enum DisplayMode: String, CaseIterable, Identifiable {
        case list
        case grid
        var id: String { rawValue }
    }
    @State private var mode: DisplayMode = .grid

    private let gridCols = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private let tileCorner: CGFloat = 18
    private let tileSpacing: CGFloat = 12
    private let headerTopPadding: CGFloat = 12

    let userID: String?

    init(userID: String? = nil) {
        self.userID = userID
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 0) {
                    headerBar

                    VStack(spacing: 10) {
                        avatarRow
                        usernameRow
                        modeSwitcher
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)

                    // Scrollable content with readers for "scroll to top"
                    ScrollViewReader { proxy in
                        Group {
                            if isLoading {
                                VStack { Spacer(); ProgressView().tint(.gray); Spacer() }
                                .id("top")
                            } else if myPosts.isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "square.stack.3d.up.slash")
                                        .font(.system(size: 36, weight: .semibold))
                                        .foregroundColor(.secondary)
                                    Text("No posts yet.")
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .id("top")
                            } else {
                                switch mode {
                                case .grid:
                                    ScrollView {
                                        VStack(spacing: 0) {
                                            Color.clear.frame(height: 0).id("top")
                                            LazyVGrid(columns: gridCols, spacing: tileSpacing) {
                                                ForEach(myPosts) { post in
                                                    ProfileGridTile(post: post)
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.top, 8)
                                            .padding(.bottom, 16)
                                        }
                                    }
                                case .list:
                                    ScrollView {
                                        VStack(spacing: 0) {
                                            Color.clear.frame(height: 0).id("top")
                                            VStack(spacing: 18) {
                                                ForEach(myPosts) { post in
                                                    ProfileListCard(post: post)
                                                }
                                            }
                                            .padding(.horizontal, 16)
                                            .padding(.top, 8)
                                            .padding(.bottom, 16)
                                        }
                                    }
                                }
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .ResetTabToTop)) { _ in
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo("top", anchor: .top)
                            }
                        }
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $editing) {
                EditProfileView(user: $userProfile)
            }
            .task {
                await loadMyPosts()
            }
            .onAppear { Task { await loadMyPosts() } }
            .onReceive(NotificationCenter.default.publisher(for: .LoadProfileNow)) { _ in
                Task { await loadMyPosts() }
            }
        }
    }

    private var headerBar: some View {
        HStack {
            Button { } label: {
                VStack(spacing: 4) {
                    Capsule().fill(Color.black.opacity(0.9)).frame(width: 22, height: 3)
                    Capsule().fill(Color.black.opacity(0.9)).frame(width: 16, height: 3)
                    Capsule().fill(Color.black.opacity(0.9)).frame(width: 12, height: 3)
                }
                .padding(8)
            }
            .buttonStyle(.plain)
            Spacer()
            HStack(spacing: 8) {
                // Center map on current location
                Button {
                    NotificationCenter.default.post(name: .CenterMapOnUserLocation, object: nil)
                } label: {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding(8)
                }
                .buttonStyle(.plain)

                // Notifications
                ZStack(alignment: .topTrailing) {
                    Button { Task { await loadMyPosts() } } label: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.black.opacity(0.9))
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, headerTopPadding)
    }

    private var avatarRow: some View {
        Button {
            editing = true
        } label: {
            ZStack {
                if let url = userProfile?.profilePictureURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Circle().fill(Color.gray.opacity(0.2))
                                .overlay(ProgressView().tint(.gray))
                        case .success(let img):
                            img.resizable().scaledToFill()
                        case .failure:
                            Circle().fill(Color.gray.opacity(0.2))
                                .overlay(Image(systemName: "person.fill").foregroundColor(.white))
                        @unknown default:
                            Circle().fill(Color.gray.opacity(0.2))
                        }
                    }
                } else if let email = auth.currentUser?.email,
                          let initials = initialsFrom(email: email) {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(Text(initials).font(.system(size: 24, weight: .bold)))
                } else {
                    Circle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(Image(systemName: "person.fill").foregroundColor(.white))
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    private var usernameRow: some View {
        Text(userProfile?.username ?? (auth.currentUser?.email?.components(separatedBy: "@").first?.uppercased() ?? "USERNAME"))
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .foregroundColor(.black.opacity(0.95))
            .padding(.top, 4)
    }

    private var modeSwitcher: some View {
        HStack(spacing: 36) {
            modeButton(icon: "list.bullet", isSelected: mode == .list) {
                mode = .list
            }
            modeButton(icon: "square.grid.2x2.fill", isSelected: mode == .grid) {
                mode = .grid
            }
        }
        .padding(.top, 2)
    }

    private func modeButton(icon: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black.opacity(0.85))
                    .padding(8)
            }
            .buttonStyle(.plain)

            Capsule()
                .fill(isSelected ? Color.indigo : Color.clear)
                .frame(width: 24, height: 3)
        }
    }

    private func loadMyPosts() async {
        let targetUID: String
        if let provided = userID {
            targetUID = provided
        } else if let current = Auth.auth().currentUser?.uid {
            targetUID = current
        } else {
            await MainActor.run { myPosts = [] }
            return
        }

        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }

        do {
            let posts = try await fetchPosts(for: targetUID)
            await MainActor.run {
                self.myPosts = posts
            }
        } catch {
            print("Profile: failed to load posts -> \(error.localizedDescription)")
            await MainActor.run { self.myPosts = [] }
        }
    }

    private func fetchPosts(for uid: String) async throws -> [Post] {
        try await withCheckedThrowingContinuation { cont in
            let db = Firestore.firestore()
            let base = db.collection("posts").whereField("userID", isEqualTo: uid)

            base.getDocuments { snap, err in
                if let err = err {
                    cont.resume(throwing: err)
                    return
                }
                // Sort client-side by createdAt desc if available
                if let snap = snap {
                    let sortedDocs = snap.documents.sorted { a, b in
                        let ta = a.data()["createdAt"] as? Timestamp
                        let tb = b.data()["createdAt"] as? Timestamp
                        switch (ta, tb) {
                        case let (a?, b?):
                            return a.dateValue() > b.dateValue()
                        case (_?, nil):
                            return true
                        case (nil, _?):
                            return false
                        default:
                            return a.reference.documentID > b.reference.documentID
                        }
                    }
                    let sortedSnap = QuerySnapshotProxy(documents: sortedDocs)
                    cont.resume(returning: Self.mapPosts(from: sortedSnap))
                } else {
                    cont.resume(returning: [])
                }
            }
        }
    }

    private static func mapPosts(from snapshot: QuerySnapshot?) -> [Post] {
        guard let snapshot else { return [] }
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let lat = (data["latitude"] as? Double) ?? (data["latitude"] as? NSNumber)?.doubleValue,
                  let lon = (data["longitude"] as? Double) ?? (data["longitude"] as? NSNumber)?.doubleValue,
                  let mediaURL = data["mediaURL"] as? String
            else { return nil }
            let radius = (data["radius"] as? Int) ?? (data["radius"] as? NSNumber)?.intValue ?? 5000
            let viewCount = (data["viewCount"] as? Int) ?? (data["viewCount"] as? NSNumber)?.intValue ?? 0
            let userID = data["userID"] as? String ?? "unknown"
            return Post(id: doc.documentID, latitude: lat, longitude: lon, mediaURL: mediaURL, radius: radius, viewCount: viewCount, userID: userID)
        }
    }

    private static func mapPosts(from snapshot: QuerySnapshotProxy?) -> [Post] {
        guard let snapshot else { return [] }
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let lat = (data["latitude"] as? Double) ?? (data["latitude"] as? NSNumber)?.doubleValue,
                  let lon = (data["longitude"] as? Double) ?? (data["longitude"] as? NSNumber)?.doubleValue,
                  let mediaURL = data["mediaURL"] as? String
            else { return nil }
            let radius = (data["radius"] as? Int) ?? (data["radius"] as? NSNumber)?.intValue ?? 5000
            let viewCount = (data["viewCount"] as? Int) ?? (data["viewCount"] as? NSNumber)?.intValue ?? 0
            let userID = data["userID"] as? String ?? "unknown"
            return Post(id: doc.documentID, latitude: lat, longitude: lon, mediaURL: mediaURL, radius: radius, viewCount: viewCount, userID: userID)
        }
    }

    private func initialsFrom(email: String) -> String? {
        let base = email.components(separatedBy: "@").first ?? ""
        guard let first = base.first else { return nil }
        return String(first).uppercased()
    }
}

// Grid and list tiles unchanged…
private struct ProfileGridTile: View {
    let post: Post
    private let corner: CGFloat = 18
    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color.gray.opacity(0.15))
                    if isLoading {
                        ProgressView().tint(.gray)
                    } else {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    }
                }
                .task {
                    await loadIfNeeded()
                }
            }
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }

    private func loadIfNeeded() async {
        guard image == nil, let url = URL(string: post.mediaURL) else { return }
        await MainActor.run { isLoading = true }
        let img = await CachedImageLoader.shared.load(url)
        await MainActor.run {
            self.image = img
            self.isLoading = false
        }
    }
}

private struct ProfileListCard: View {
    let post: Post
    private let corner: CGFloat = 22
    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color.gray.opacity(0.15))
                    if isLoading {
                        ProgressView().tint(.gray)
                    } else {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    }
                }
                .task {
                    await loadIfNeeded()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("\(max(1, post.radius / 1000)) KM")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                Text("Lat \(String(format: "%.2f", post.latitude)), Lon \(String(format: "%.2f", post.longitude))")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
            }
            .foregroundColor(.white)
            .padding(14)
            .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 8)
    }

    private func loadIfNeeded() async {
        guard image == nil, let url = URL(string: post.mediaURL) else { return }
        await MainActor.run { isLoading = true }
        let img = await CachedImageLoader.shared.load(url)
        await MainActor.run {
            self.image = img
            self.isLoading = false
        }
    }
}

// A tiny proxy to reuse existing mapPosts(from:) without changing its signature.
private struct QuerySnapshotProxy {
    let documents: [QueryDocumentSnapshot]
}

extension Notification.Name {
    static let LoadProfileNow = Notification.Name("LoadProfileNow")
    static let CenterMapOnUserLocation = Notification.Name("CenterMapOnUserLocation")
}
