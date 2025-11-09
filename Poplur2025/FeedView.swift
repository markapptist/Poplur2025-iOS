import SwiftUI
import FirebaseFirestore
import AVKit
import CoreLocation

struct FeedView: View {
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var didSeedIfEmpty = false

    // Pagination
    private let pageSize = 10
    @State private var lastDocument: DocumentSnapshot?
    @State private var isLoadingMore = false
    @State private var reachedEnd = false

    // Current page
    @State private var currentIndex: Int = 0

    // Navigation to profile
    @State private var selectedUserID: String? = nil
    @State private var navigateToProfile = false

    // Username resolution cache (per-view state that consults the global actor)
    @State private var usernames: [String: String] = [:] // uid -> username
    @State private var usernameLoadsInProgress: Set<String> = []

    // Fallback demo video to ensure we always have something to play
    private let fallbackFastVideoURL = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")

    // Computed: current post
    private var currentPost: Post? {
        posts[safe: currentIndex]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if posts.isEmpty {
                    VerticalPager(currentIndex: .constant(0), pageCount: 1) {
                        ZStack {
                            if let url = fallbackFastVideoURL {
                                FullscreenVideoView(url: url, isActive: .constant(true), isMuted: true, shouldLoop: true)
                                    .id(url)
                            } else {
                                Color.black
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .background(Color.black)
                    }
                    .ignoresSafeArea(edges: [.top, .horizontal])
                } else {
                    VerticalPager(currentIndex: $currentIndex, pageCount: posts.count) {
                        ZStack {
                            ForEach(pagesToDisplay, id: \.self) { idx in
                                if let post = posts[safe: idx] {
                                    let resolvedName = displayName(for: post)
                                    FeedFullscreenPage(
                                        post: post,
                                        isActive: Binding(
                                            get: { currentIndex == idx },
                                            set: { _ in }
                                        ),
                                        displayName: resolvedName,
                                        onUserTapped: { userId in
                                            selectedUserID = userId
                                            navigateToProfile = true
                                        }
                                    )
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .position(
                                        x: geo.size.width / 2,
                                        y: (CGFloat(idx) + 0.5) * geo.size.height
                                    )
                                    .animation(.none, value: currentIndex)
                                    .onAppear {
                                        maybeLoadMoreIfNeeded(appearingIndex: idx)
                                        maybeResolveUsername(for: post.userID)
                                    }
                                }
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height * CGFloat(max(posts.count, 1)))
                        .background(Color.black)
                    }
                    .ignoresSafeArea(edges: [.top, .horizontal])
                }

                overlayChrome
                    .zIndex(10)

                NavigationLink(
                    isActive: $navigateToProfile,
                    destination: {
                        if let userId = selectedUserID {
                            AnyView(ProfileView(userID: userId))
                        } else {
                            AnyView(Text("No user selected"))
                        }
                    },
                    label: {
                        EmptyView()
                    }
                )
                .hidden()
            }
            .background(Color.black)
        }
        .task {
            await reload()
            if posts.isEmpty, !didSeedIfEmpty {
                didSeedIfEmpty = true
                await seedAndReload()
            } else {
                prefetchVisibleUsernames()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .LoadFeedNow)) { _ in
            Task { await reload() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ResetTabToTop)) { _ in
            // Jump back to the beginning of the feed
            currentIndex = 0
        }
        .onChange(of: currentIndex) { _ in
            if let uid = currentPost?.userID {
                maybeResolveUsername(for: uid)
            }
        }
    }

    private var pagesToDisplay: [Int] {
        guard !posts.isEmpty else { return [] }
        return Array(Set([
            currentIndex - 1,
            currentIndex,
            currentIndex + 1
        ].filter { $0 >= 0 && $0 < posts.count }))
        .sorted()
    }

    private var overlayChrome: some View {
        ZStack {
            VStack {
                HStack {
                    if isLoading || isLoadingMore {
                        ProgressView().tint(.white)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                Spacer()
            }

            VStack {
                Spacer()
                VStack(spacing: 14) {
                    Button {
                        if !posts.isEmpty {
                            currentIndex = max(0, currentIndex - 1)
                        }
                    } label: {
                        Circle().fill(Color.green).frame(width: 56, height: 56)
                            .overlay(Image(systemName: "arrow.up").foregroundColor(.white))
                    }
                    .buttonStyle(.plain)

                    Button {
                        print("Heart tapped for post: \(currentPost?.id ?? "nil")")
                    } label: {
                        Circle().fill(Color.pink).frame(width: 44, height: 44)
                            .overlay(Image(systemName: "heart.fill").foregroundColor(.white))
                    }
                    .buttonStyle(.plain)

                    Button {
                        if !posts.isEmpty {
                            currentIndex = min(posts.count - 1, currentIndex + 1)
                        }
                    } label: {
                        Circle().fill(Color.blue).frame(width: 56, height: 56)
                            .overlay(Image(systemName: "arrow.down").foregroundColor(.white))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 16)
                .padding(.bottom, 120)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .ignoresSafeArea(edges: [.top, .horizontal])
    }

    private func displayName(for post: Post) -> String {
        if let name = usernames[post.userID], !name.isEmpty {
            return name
        }
        if post.userID.hasPrefix("fake_") || post.userID.hasPrefix("na_user_") || post.userID.hasPrefix("world_user_") {
            return post.userID
        }
        if !post.userID.isEmpty {
            return "@" + String(post.userID.prefix(6))
        }
        return "User"
    }

    private func maybeResolveUsername(for uid: String) {
        guard !uid.isEmpty else { return }
        if usernames[uid] != nil { return }
        if usernameLoadsInProgress.contains(uid) { return }
        usernameLoadsInProgress.insert(uid)
        Task {
            let name = await UsernameCache.shared.username(for: uid)
            await MainActor.run {
                if let name, !name.isEmpty {
                    usernames[uid] = name
                }
                usernameLoadsInProgress.remove(uid)
            }
        }
    }

    private func prefetchVisibleUsernames() {
        for idx in pagesToDisplay {
            if let uid = posts[safe: idx]?.userID {
                maybeResolveUsername(for: uid)
            }
        }
        if let uid = currentPost?.userID {
            maybeResolveUsername(for: uid)
        }
    }

    @MainActor
    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        reachedEnd = false
        lastDocument = nil
        defer { isLoading = false }

        let db = Firestore.firestore()
        let baseQuery = db.collection("posts")
            .order(by: "createdAt", descending: true)
            .limit(to: pageSize)

        if let cacheSnap = try? await baseQuery.getDocuments(source: .cache), !cacheSnap.documents.isEmpty {
            let cached = Self.parsePosts(from: cacheSnap)
            posts = sortForFastestPlayback(cached)
            lastDocument = cacheSnap.documents.last
            currentIndex = 0
        }

        if let serverSnap = try? await baseQuery.getDocuments(source: .server) {
            let fresh = Self.parsePosts(from: serverSnap)
            posts = sortForFastestPlayback(fresh)
            lastDocument = serverSnap.documents.last
            currentIndex = 0
            reachedEnd = serverSnap.documents.count < pageSize
        } else if posts.isEmpty {
            reachedEnd = true
        }

        prefetchVisibleUsernames()
    }

    @MainActor
    private func loadMore() async {
        guard !isLoadingMore, !reachedEnd else { return }
        guard let last = lastDocument else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let db = Firestore.firestore()
        let query = db.collection("posts")
            .order(by: "createdAt", descending: true)
            .start(afterDocument: last)
            .limit(to: pageSize)

        var appended = false

        if let snap = try? await query.getDocuments(source: .server) {
            let newPosts = sortForFastestPlayback(Self.parsePosts(from: snap))
            appended = appendDedup(newPosts)
            lastDocument = snap.documents.last
            reachedEnd = snap.documents.count < pageSize
        } else if let cacheSnap = try? await query.getDocuments(source: .cache), !cacheSnap.documents.isEmpty {
            let newPosts = sortForFastestPlayback(Self.parsePosts(from: cacheSnap))
            appended = appendDedup(newPosts)
            lastDocument = cacheSnap.documents.last
            reachedEnd = cacheSnap.documents.count < pageSize
        }

        if appended {
            prefetchVisibleUsernames()
        }
    }

    @MainActor
    private func appendDedup(_ newPosts: [Post]) -> Bool {
        guard !newPosts.isEmpty else { return false }
        let existingIDs = Set(posts.map { $0.id })
        let filtered = newPosts.filter { !existingIDs.contains($0.id) }
        guard !filtered.isEmpty else { return false }
        posts.append(contentsOf: filtered)
        return true
    }

    private func maybeLoadMoreIfNeeded(appearingIndex idx: Int) {
        let threshold = max(0, posts.count - 3)
        if idx >= threshold {
            Task { await loadMore() }
        }
    }

    private func sortForFastestPlayback(_ items: [Post]) -> [Post] {
        return items.sorted { a, b in
            let aURL = a.mediaURL.lowercased()
            let bURL = b.mediaURL.lowercased()

            let aIsVideo = aURL.hasSuffix(".mp4") || aURL.hasSuffix(".mov")
            let bIsVideo = bURL.hasSuffix(".mp4") || bURL.hasSuffix(".mov")
            if aIsVideo != bIsVideo { return aIsVideo && !bIsVideo }

            if aURL.count != bURL.count { return aURL.count < bURL.count }

            return false
        }
    }

    private static func parsePosts(from snap: QuerySnapshot) -> [Post] {
        var fetched: [Post] = []
        for doc in snap.documents {
            let data = doc.data()
            guard let lat = (data["latitude"] as? Double) ?? (data["latitude"] as? NSNumber)?.doubleValue,
                  let lon = (data["longitude"] as? Double) ?? (data["longitude"] as? NSNumber)?.doubleValue,
                  let mediaURL = data["mediaURL"] as? String else { continue }

            let radius = (data["radius"] as? Int) ?? (data["radius"] as? NSNumber)?.intValue ?? 5000
            let viewCount = (data["viewCount"] as? Int) ?? (data["viewCount"] as? NSNumber)?.intValue ?? 0
            let userID = (data["userID"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "User"
            fetched.append(Post(id: doc.documentID, latitude: lat, longitude: lon, mediaURL: mediaURL, radius: radius, viewCount: viewCount, userID: userID))
        }
        return fetched
    }

    @MainActor
    private func seedAndReload() async {
        await FakePostService.shared.seedCityDemoIfNeeded(countPerCity: 2)
        await FakePostService.shared.seedInitialNorthAmerica(total: 60)
        await reload()
    }
}

private struct FeedFullscreenPage: View {
    let post: Post
    @Binding var isActive: Bool
    let displayName: String
    var onUserTapped: (String) -> Void

    private var isVideo: Bool {
        let lower = post.mediaURL.lowercased()
        return lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.contains("video")
    }

    private var coordinateText: String {
        String(format: "%.4f, %.4f", post.latitude, post.longitude)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Group {
                    if isVideo, let url = URL(string: post.mediaURL) {
                        FullscreenVideoView(url: url, isActive: $isActive, isMuted: true, shouldLoop: true)
                            .allowsHitTesting(false)
                            .id(url)
                    } else if let url = URL(string: post.mediaURL) {
                        AsyncImage(url: url, transaction: Transaction(animation: .none)) { phase in
                            switch phase {
                            case .empty:
                                ZStack { Color.black; ProgressView().tint(.white) }
                            case .success(let img):
                                img
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                            case .failure:
                                ZStack {
                                    Color.black
                                    Image(systemName: "photo")
                                        .font(.system(size: 40, weight: .bold))
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            @unknown default:
                                Color.black
                            }
                        }
                        .allowsHitTesting(false)
                        .id(url)
                    } else {
                        Color.black
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea()
                .zIndex(0)

                VStack(alignment: .trailing, spacing: 6) {
                    Button(action: { onUserTapped(post.userID) }) {
                        Text(displayName.isEmpty ? "User" : displayName)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.65), in: Capsule())
                            .overlay(Capsule().stroke(Color.white.opacity(0.35), lineWidth: 1))
                    }
                    .buttonStyle(.plain)

                    Text(coordinateText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55), in: Capsule())
                }
                .padding(.trailing, 16)
                .padding(.top, geo.safeAreaInsets.top + 40)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topTrailing)
                .zIndex(10)

                VStack {
                    Spacer()
                    VerticalRadiusBar(
                        radius: post.radius,
                        maxRadius: 10_000,
                        width: 10,
                        maxHeight: 220,
                        color: .pink,
                        showsLabel: true,
                        labelFormat: { r in
                            r >= 1000 ? "\(r / 1000) km" : "\(r) m"
                        }
                    )
                    .frame(width: 10, height: 220, alignment: .bottom)
                    .padding(.trailing, 12)
                }
                .padding(.bottom, 45)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .trailing)
                .zIndex(10)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
        }
        .ignoresSafeArea()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
