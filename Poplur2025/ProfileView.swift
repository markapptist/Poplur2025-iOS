import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore
import UserNotifications
import ARKit

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @GestureState private var isInteractingWithCube: Bool = false
    @State private var isScrollDisabled = false

    @State private var editing = false
    @State private var userProfile: UserProfile?

    @State private var myPosts: [Post] = []
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @State private var expandedPost: Post? = nil
    @State private var profileImage: UIImage? = nil
    @State private var profileImageURL: URL? = nil
    @State private var showSettings = false
    @State private var averageRadius: Double = 5000
    @State private var navigateToScanner = false
    
    @State private var lastHeadModelURL: URL? = nil

    @State private var navigateToViewer = false

    @State private var barHeightFactor: CGFloat = 1.0
    @State private var isHoldingCube: Bool = false

    @State private var isLoadingMore = false
    @State private var canLoadMore = true
    @State private var lastDocument: QueryDocumentSnapshot? = nil
    private let pageSize = 18

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

    init(userID: String? = nil, initialMode: DisplayMode = .grid) {
        self.userID = userID
        _mode = State(initialValue: initialMode)
    }
    
    // MARK: - Simple disk cache for posts (per user)
    private struct CachedPost: Codable {
        let id: String
        let latitude: Double
        let longitude: Double
        let mediaURL: String
        let radius: Int
        let viewCount: Int
        let userID: String
    }

    private func cacheFileURL(for uid: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("profile_posts_\(uid).json")
    }

    private func loadPostsFromCache(for uid: String) -> [Post]? {
        let url = cacheFileURL(for: uid)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let cached = try JSONDecoder().decode([CachedPost].self, from: data)
            return cached.map { Post(id: $0.id, latitude: $0.latitude, longitude: $0.longitude, mediaURL: $0.mediaURL, radius: $0.radius, viewCount: $0.viewCount, userID: $0.userID) }
        } catch {
            print("Profile cache: failed to read -> \(error.localizedDescription)")
            return nil
        }
    }

    private func savePostsToCache(_ posts: [Post], for uid: String) {
        let url = cacheFileURL(for: uid)
        let toCache = posts.map { CachedPost(id: $0.id, latitude: $0.latitude, longitude: $0.longitude, mediaURL: $0.mediaURL, radius: $0.radius, viewCount: $0.viewCount, userID: $0.userID) }
        do {
            let data = try JSONEncoder().encode(toCache)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Profile cache: failed to write -> \(error.localizedDescription)")
        }
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
                            if isLoading || !hasLoadedOnce {
                                VStack { Spacer(); Spacer() }
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
                                                ForEach(myPosts.filter { loadedImages[$0.id] != nil }) { post in
                                                    ProfileGridTile(post: post, preloadedImage: loadedImages[post.id]!)
                                                        .onTapGesture {
                                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                                                expandedPost = post
                                                            }
                                                        }
                                                }
                                                Color.clear.frame(height: 1).onAppear {
                                                    loadMoreIfNeeded(currentItem: myPosts.last)
                                                }
                                            }
                                            if isLoadingMore {
                                                ProgressView().padding(.vertical, 12)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                        .padding(.bottom, 16)
                                    }
                                    .scrollDisabled(isScrollDisabled)
                                    .refreshable {
                                        await loadMyPosts()
                                    }
                                case .list:
                                    ScrollView {
                                        VStack(spacing: 0) {
                                            Color.clear.frame(height: 0).id("top")
                                            VStack(spacing: 18) {
                                                ForEach(myPosts.filter { loadedImages[$0.id] != nil }) { post in
                                                    ProfileListCard(post: post, preloadedImage: loadedImages[post.id]!)
                                                        .onTapGesture {
                                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                                                expandedPost = post
                                                            }
                                                        }
                                                }
                                                Color.clear.frame(height: 1).onAppear {
                                                    loadMoreIfNeeded(currentItem: myPosts.last)
                                                }
                                            }
                                            if isLoadingMore {
                                                ProgressView().padding(.vertical, 12)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.top, 8)
                                        .padding(.bottom, 16)
                                    }
                                    .scrollDisabled(isScrollDisabled)
                                    .refreshable {
                                        await loadMyPosts()
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
                .zIndex(1)

                // Removed local IsometricRadiusBar overlay here

                // Global gesture layer for cube interaction (restricted to upper area and non-preemptive)
                GeometryReader { geo in
                    let height = geo.size.height
                    VStack(spacing: 0) {
                        // Leave header + avatar + username + mode switcher tappable
                        Spacer().frame(height: 260)

                        Color.clear
                            .frame(height: height * 0.6)
                            .contentShape(Rectangle())
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 0)
                                    .updating($isInteractingWithCube) { _, isInteracting, _ in
                                        isInteracting = true
                                    }
                                    .onChanged { value in
                                        if !isScrollDisabled { isScrollDisabled = true }
                                        let boost: CGFloat = 1.35
                                        let boosted = CGSize(width: value.translation.width * boost,
                                                             height: value.translation.height * boost)
                                        NotificationCenter.default.post(name: Notification.Name("CubeGlobalDragChanged"), object: nil, userInfo: [
                                            "location": NSValue(cgPoint: value.location),
                                            "translation": NSValue(cgSize: boosted)
                                        ])
                                    }
                                    .onEnded { value in
                                        let boost: CGFloat = 1.35
                                        let boosted = CGSize(width: value.translation.width * boost,
                                                             height: value.translation.height * boost)
                                        NotificationCenter.default.post(name: Notification.Name("CubeGlobalDragEnded"), object: nil, userInfo: [
                                            "location": NSValue(cgPoint: value.location),
                                            "translation": NSValue(cgSize: boosted)
                                        ])
                                        isScrollDisabled = false
                                    }
                            )
                            .simultaneousGesture(
                                TapGesture()
                                    .onEnded {
                                        isScrollDisabled = true
                                        NotificationCenter.default.post(name: Notification.Name("CubeGlobalTap"), object: nil)
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { isScrollDisabled = false }
                                    }
                            )
                        Spacer()
                    }
                    .ignoresSafeArea(edges: .top)
                }
                if let post = expandedPost {
                    ZStack {
                        Color.black.opacity(0.6)
                            .ignoresSafeArea()
                            .transition(.opacity)

                        FeedFullscreenPage(
                            post: FeedPost(
                                id: post.id,
                                latitude: post.latitude,
                                longitude: post.longitude,
                                mediaURL: post.mediaURL,
                                radius: Double(post.radius),
                                viewCount: post.viewCount,
                                userID: post.userID
                            ),
                            displayName: "",
                            onUserTapped: { _ in }
                        )
                        .transition(.scale.combined(with: .opacity))
                        .onAppear {
                            NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                        }
                        .onDisappear {
                            NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                        }
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.easeOut(duration: 0.25)) { expandedPost = nil }
                                NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.95))
                                    .padding(12)
                            }
                            .buttonStyle(.plain)
                        }
                        .overlay(alignment: .topLeading) {
                            Button(role: .destructive) {
                                Task {
                                    await deletePost(expandedPost)
                                    withAnimation(.easeOut(duration: 0.25)) { expandedPost = nil }
                                }
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(10)
                                    .background(
                                        Capsule().fill(Color.red.opacity(0.85))
                                    )
                                    .padding(12)
                            }
                            .buttonStyle(.plain)
                        }
                        .overlay(alignment: .bottomLeading) {
                            Text("\(max(1, Int(post.radius) / 1000)) KM")
                                .font(.system(size: 16, weight: .heavy, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(Color.black.opacity(0.55))
                                )
                                .padding(16)
                        }
                    }
                    .zIndex(10)
                }
            }
            NavigationLink(isActive: $showSettings) {
                AppSettingsView()
            } label: { EmptyView() }
            .hidden()

            NavigationLink(isActive: $navigateToScanner) {
                HeadScannerView { result in
                    switch result {
                    case .success(let output):
                        // For now, use a snapshot image if provided; otherwise ignore
                        if let image = output.previewImage {
                            self.profileImage = image
                            if let url = try? saveProfileImage(image) {
                                self.profileImageURL = url
                            }
                            NotificationCenter.default.post(name: Notification.Name("ProfilePhotoUpdated"), object: image)
                        }
                        self.lastHeadModelURL = output.usdzURL
                        if output.usdzURL != nil {
                            self.navigateToViewer = true
                        }
                    case .failure:
                        break
                    }
                }
            } label: { EmptyView() }
            .hidden()

            NavigationLink(isActive: $navigateToViewer) {
                if let url = lastHeadModelURL {
                    USDZViewerView(usdzURL: url)
                } else {
                    Text("No model available")
                }
            } label: { EmptyView() }
            .hidden()

            .sheet(isPresented: $editing) {
                EditProfileView(user: $userProfile)
            }
            .task {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
                await loadMyPosts()
                await MainActor.run {
                    self.averageRadius = Double(self.averagePostRadius())
                    self.hasLoadedOnce = true
                }
                await loadPersistedProfileImageIfNeeded()
            }
            .onAppear {
                NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                Task { await loadMyPosts() }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ProfileRemovePost"))) { notif in
                if let id = notif.object as? String {
                    myPosts.removeAll { $0.id == id }
                    self.averageRadius = Double(self.averagePostRadius())
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cubeHoldBegan)) { _ in
                // Start rising only on Record tab; HomeView controls selected tab, so we infer via notification usage
                isHoldingCube = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .cubeHoldEnded)) { _ in
                isHoldingCube = false
            }
            .task(id: isHoldingCube) {
                // If holding, increase the bar height factor over time; otherwise, ensure default per current tab
                if isHoldingCube {
                    // Start from current value; rise at ~200pt/sec on a 220pt bar => ~0.9 factor per second
                    let start = barHeightFactor
                    var current = start
                    let incrementPerTick: CGFloat = 0.03 // ~30 FPS * 0.03 ~= 0.9/sec
                    while isHoldingCube && current < 1.0 {
                        try? await Task.sleep(nanoseconds: 33_000_000)
                        current = min(1.0, current + incrementPerTick)
                        await MainActor.run { barHeightFactor = current }
                    }
                } else {
                    // When not holding, keep current value (do not reset)
                    // No action; could reset here if desired.
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RecordTabBecameActive"))) { _ in
                // When record tab becomes active, collapse the bar
                barHeightFactor = 0.0
            }
        }
    }

    private var headerBar: some View {
        HStack {
            // Left: Settings (gear)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black.opacity(0.95))
                    .padding(10)
                    .background(
                        Circle().fill(Color.white)
                            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 4)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            // Right: DMs (envelope)
            NavigationLink {
                MessagesRootView()
            } label: {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.black.opacity(0.95))
                    .padding(10)
                    .background(
                        Circle().fill(Color.white)
                            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 4)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, headerTopPadding)
    }

    private var avatarRow: some View {
        Button {
            navigateToScanner = true
        } label: {
            ZStack {
                if let localImage = profileImage {
                    Image(uiImage: localImage)
                        .resizable()
                        .scaledToFill()
                } else if let url = profileImageURL, // load persisted local file on appear
                          let data = try? Data(contentsOf: url),
                          let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else if let url = userProfile?.profilePictureURL {
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
            .overlay(alignment: .bottomTrailing) {
                if lastHeadModelURL != nil {
                    Button {
                        navigateToViewer = true
                    } label: {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Circle().fill(Color.black.opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                deleteProfilePhoto()
            } label: {
                Label("Delete Profile Photo", systemImage: "trash")
            }
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
            await MainActor.run {
                myPosts = []
                loadedImages = [:]
                hasLoadedOnce = true
                canLoadMore = false
                lastDocument = nil
            }
            return
        }
        
        // Try to show cached posts immediately for better perceived performance
        if let cached = loadPostsFromCache(for: targetUID), !cached.isEmpty {
            await MainActor.run {
                self.myPosts = cached
                self.hasLoadedOnce = true
                self.averageRadius = Double(self.averagePostRadius())
            }
            // Prefetch images for cached posts
            Task.detached { await prefetchImages(for: cached) }
        }

        await MainActor.run {
            isLoading = true
            canLoadMore = true
            lastDocument = nil
            myPosts = []
            loadedImages = [:]
        }
        defer { Task { @MainActor in isLoading = false } }

        do {
            let page = try await fetchPostsPage(for: targetUID, after: nil, limit: pageSize)
            await MainActor.run {
                self.myPosts = page.posts
                self.lastDocument = page.lastDoc
                self.canLoadMore = page.posts.count >= pageSize && page.lastDoc != nil
                self.averageRadius = Double(self.averagePostRadius())
                self.hasLoadedOnce = true
            }
            // Persist latest posts to cache
            savePostsToCache(page.posts, for: targetUID)
            Task.detached { await prefetchImages(for: page.posts) }
        } catch {
            print("Profile: failed to load posts -> \(error.localizedDescription)")
            // Fall back to cache if available
            if let cached = loadPostsFromCache(for: targetUID), !cached.isEmpty {
                await MainActor.run {
                    self.myPosts = cached
                    self.loadedImages = [:]
                    self.hasLoadedOnce = true
                    self.canLoadMore = false
                    self.averageRadius = Double(self.averagePostRadius())
                }
                Task.detached { await prefetchImages(for: cached) }
            } else {
                await MainActor.run {
                    self.myPosts = []
                    self.loadedImages = [:]
                    self.hasLoadedOnce = true
                    self.canLoadMore = false
                }
            }
        }
    }

    private func loadMoreIfNeeded(currentItem post: Post?) {
        guard canLoadMore, !isLoadingMore, !isLoading else { return }
        guard let post = post else { return }
        // Trigger when the current item is within the last 6 items
        let thresholdIndex = myPosts.index(myPosts.endIndex, offsetBy: -6, limitedBy: myPosts.startIndex) ?? myPosts.startIndex
        if let currentIndex = myPosts.firstIndex(where: { $0.id == post.id }), currentIndex >= thresholdIndex {
            Task { await loadNextPage() }
        }
    }

    private func loadNextPage() async {
        guard canLoadMore, !isLoadingMore else { return }
        await MainActor.run { isLoadingMore = true }
        defer { Task { @MainActor in isLoadingMore = false } }
        let targetUID: String
        if let provided = userID {
            targetUID = provided
        } else if let current = Auth.auth().currentUser?.uid {
            targetUID = current
        } else { return }
        do {
            let page = try await fetchPostsPage(for: targetUID, after: lastDocument, limit: pageSize)
            await MainActor.run {
                self.myPosts.append(contentsOf: page.posts)
                self.lastDocument = page.lastDoc
                self.canLoadMore = page.posts.count >= pageSize && page.lastDoc != nil
                self.averageRadius = Double(self.averagePostRadius())
            }
            // Update cache with appended posts
            savePostsToCache(self.myPosts, for: targetUID)
            Task.detached { await prefetchImages(for: page.posts) }
        } catch {
            print("Profile: failed to load more -> \(error.localizedDescription)")
            await MainActor.run { self.canLoadMore = false }
        }
    }

    private struct PostsPage {
        let posts: [Post]
        let lastDoc: QueryDocumentSnapshot?
    }

    private func fetchPostsPage(for uid: String, after last: QueryDocumentSnapshot?, limit: Int) async throws -> PostsPage {
        try await withCheckedThrowingContinuation { cont in
            let db = Firestore.firestore()
            var query: Query = db.collection("posts")
                .whereField("userID", isEqualTo: uid)
                .order(by: "createdAt", descending: true)
                .limit(to: limit)
            if let last = last {
                query = query.start(afterDocument: last)
            }
            query.getDocuments { snap, err in
                if let err = err {
                    cont.resume(throwing: err)
                    return
                }
                guard let snap = snap else {
                    cont.resume(returning: PostsPage(posts: [], lastDoc: nil))
                    return
                }
                let posts = Self.mapPosts(from: snap)
                let lastDoc = snap.documents.last
                cont.resume(returning: PostsPage(posts: posts, lastDoc: lastDoc))
            }
        }
    }

    private static func mapPosts(from snapshot: QuerySnapshot?) -> [Post] {
        guard let snapshot else { return [] }
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            let rawURL = data["mediaURL"] as? String
            let mediaURL = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let lat = (data["latitude"] as? Double) ?? (data["latitude"] as? NSNumber)?.doubleValue,
                  let lon = (data["longitude"] as? Double) ?? (data["longitude"] as? NSNumber)?.doubleValue,
                  let mediaURL = mediaURL, !mediaURL.isEmpty
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
            let rawURL = data["mediaURL"] as? String
            let mediaURL = rawURL?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let lat = (data["latitude"] as? Double) ?? (data["latitude"] as? NSNumber)?.doubleValue,
                  let lon = (data["longitude"] as? Double) ?? (data["longitude"] as? NSNumber)?.doubleValue,
                  let mediaURL = mediaURL, !mediaURL.isEmpty
            else { return nil }
            let radius = (data["radius"] as? Int) ?? (data["radius"] as? NSNumber)?.intValue ?? 5000
            let viewCount = (data["viewCount"] as? Int) ?? (data["viewCount"] as? NSNumber)?.intValue ?? 0
            let userID = data["userID"] as? String ?? "unknown"
            return Post(id: doc.documentID, latitude: lat, longitude: lon, mediaURL: mediaURL, radius: radius, viewCount: viewCount, userID: userID)
        }
    }

    private func loadPersistedProfileImageIfNeeded() async {
        // Try to locate a previously saved profile image and load it into state
        let url = profileImageFileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                await MainActor.run {
                    self.profileImage = img
                    self.profileImageURL = url
                }
            }
        }
    }

    private func prefetchImages(for posts: [Post]) async {
        await withTaskGroup(of: Void.self) { group in
            for post in posts where loadedImages[post.id] == nil {
                group.addTask {
                    await loadImageFor(post: post)
                }
            }
        }
    }

    private func loadImageFor(post: Post) async {
        guard let url = URL(string: post.mediaURL) else { return }
        let image = await CachedImageLoader.shared.load(url)
        if let image = image {
            await MainActor.run {
                self.loadedImages[post.id] = image
            }
        }
    }

    @discardableResult
    private func saveProfileImage(_ image: UIImage) throws -> URL {
        let url = profileImageFileURL()
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "ProfileImage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get JPEG data"]) }
        try data.write(to: url, options: .atomic)
        return url
    }

    private func profileImageFileURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("profile.jpg")
    }

    private func initialsFrom(email: String) -> String? {
        let base = email.components(separatedBy: "@").first ?? ""
        guard let first = base.first else { return nil }
        return String(first).uppercased()
    }
    
    private func averagePostRadius() -> Int {
        if myPosts.isEmpty { return 5000 }
        let total = myPosts.reduce(0) { $0 + $1.radius }
        let avg = total / max(1, myPosts.count)
        return max(1, avg)
    }
    
    private func deletePost(_ post: Post?) async {
        guard let post else { return }
        do {
            let db = Firestore.firestore()
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                db.collection("posts").document(post.id).delete { err in
                    if let err = err {
                        cont.resume(throwing: err)
                    } else {
                        cont.resume()
                    }
                }
            }
            await MainActor.run {
                self.myPosts.removeAll { $0.id == post.id }
                self.loadedImages.removeValue(forKey: post.id)
                self.averageRadius = Double(self.averagePostRadius())
                NotificationCenter.default.post(name: Notification.Name("ProfileRemovePost"), object: post.id)
            }
        } catch {
            print("Failed to delete post: \(error.localizedDescription)")
        }
    }

    private func deleteProfilePhoto() {
        // Clear in-memory state
        self.profileImage = nil
        self.profileImageURL = nil
        // Delete persisted file if present
        let url = profileImageFileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.removeItem(at: url) } catch {
                print("Failed to remove profile photo: \(error.localizedDescription)")
            }
        }
        NotificationCenter.default.post(name: Notification.Name("ProfilePhotoUpdated"), object: nil)
    }
}

// Grid and list tiles unchanged…
private struct ProfileGridTile: View {
    let post: Post
    let preloadedImage: UIImage
    private let corner: CGFloat = 18

    var body: some View {
        ZStack {
            Image(uiImage: preloadedImage)
                .resizable()
                .scaledToFill()
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(alignment: .bottomLeading) {
            Text("\(max(1, post.radius / 1000)) KM")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.black.opacity(0.55))
                )
                .padding(8)
        }
    }
}

private struct ProfileListCard: View {
    let post: Post
    let preloadedImage: UIImage
    private let corner: CGFloat = 22

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: preloadedImage)
                .resizable()
                .scaledToFill()

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
}

// A tiny proxy to reuse existing mapPosts(from:) without changing its signature.
private struct QuerySnapshotProxy {
    let documents: [QueryDocumentSnapshot]
}

extension Notification.Name {
    // Removed the LoadProfileNow static let as per instructions
    static let CenterMapOnUserLocation = Notification.Name("CenterMapOnUserLocation")
    static let OpenSettingsRequested = Notification.Name("OpenSettingsRequested")
    static let OpenDMsRequested = Notification.Name("OpenDMsRequested")
    static let PauseGlobalFeedAudio = Notification.Name("PauseGlobalFeedAudio")
    static let CubeGlobalDragChanged = Notification.Name("CubeGlobalDragChanged")
    static let CubeGlobalDragEnded = Notification.Name("CubeGlobalDragEnded")
    static let CubeGlobalTap = Notification.Name("CubeGlobalTap")

    static let cubeHoldBegan = Notification.Name("cubeHoldBegan")
    static let cubeHoldEnded = Notification.Name("cubeHoldEnded")
    static let RecordTabBecameActive = Notification.Name("RecordTabBecameActive")
}
#if DEBUG
import SwiftUI

#Preview("ProfileView") {
    ProfileView(userID: "preview-user-123", initialMode: .grid)
        .environmentObject(AuthViewModel())
}
#endif

