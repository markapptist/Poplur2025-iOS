import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore
import UserNotifications
import ARKit

private var isRunningInPreviews: Bool {
    let env = ProcessInfo.processInfo.environment
    return env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || env["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
}

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @GestureState private var isInteractingWithCube: Bool = false
    @State private var isScrollDisabled = false
    
    // Track if we're viewing own profile or another user's
    private var isOwnProfile: Bool {
        if let userID = userID, !userID.isEmpty {
            let currentUID = Auth.auth().currentUser?.uid
            let result = currentUID == userID
            print("🔍 [ProfileView] isOwnProfile check - currentUID: \(currentUID ?? "nil"), userID: \(userID), result: \(result)")
            return result
        }
        print("🔍 [ProfileView] isOwnProfile check - no userID or empty string, assuming own profile")
        return true // If no userID provided or empty string, assume own profile
    }

    @State private var editing = false
    @State private var displayUsername: String? = nil
    @State private var userProfile: UserProfile?

    @State private var myPosts: [Post] = []
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @State private var expandedPost: Post? = nil
    @State private var profileImage: UIImage? = nil
    @State private var profileImageURL: URL? = nil
    @State private var showSettings = false
    @State private var navigateToMessages = false
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

    let userID: String?
    
    // Use a stable ID to force view recreation when userID changes
    private var viewID: String {
        userID ?? "own-profile"
    }

    init(userID: String? = nil, initialMode: DisplayMode = .grid) {
        self.userID = userID
        _mode = State(initialValue: initialMode)
        print("🏗️ [ProfileView] Initialized with userID: \(userID ?? "nil")")
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
            return cached.map { Post(id: $0.id, latitude: $0.latitude, longitude: $0.longitude, mediaURL: $0.mediaURL, radius: $0.radius, viewCount: $0.viewCount, userID: $0.userID, posterURL: nil) }
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
                    // Explanatory text box at the top
                    VStack(alignment: .leading, spacing: 8) {
                        Text(isOwnProfile ? "Your Profile" : "User Profile")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        
                        Text(isOwnProfile ? "View all your posts in grid or list mode. Tap any post to view fullscreen. Tap the cube to access settings, or long-press for messages." : "View this user's posts in grid or list mode. Tap any post to view fullscreen.")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

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
                                                                // Notify radius change for global radius bar sync
                                                                NotificationCenter.default.post(name: Notification.Name("currentPostRadiusDidChange"), object: nil, userInfo: ["radius": Double(post.radius)])
                                                            }
                                                        }
                                                        .onLongPressGesture(minimumDuration: 0.5) {
                                                            // Long press to show post location on map
                                                            let coordinate = CLLocationCoordinate2D(latitude: post.latitude, longitude: post.longitude)
                                                            print("📍 [ProfileView] Long press - showing post location on map: \(coordinate.latitude), \(coordinate.longitude)")
                                                            NotificationCenter.default.post(
                                                                name: Notification.Name("ShowLocationOnMap"),
                                                                object: nil,
                                                                userInfo: ["coordinate": coordinate]
                                                            )
                                                            // Haptic feedback
                                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
                                                                // Notify radius change for global radius bar sync
                                                                NotificationCenter.default.post(name: Notification.Name("currentPostRadiusDidChange"), object: nil, userInfo: ["radius": Double(post.radius)])
                                                            }
                                                        }
                                                        .onLongPressGesture(minimumDuration: 0.5) {
                                                            // Long press to show post location on map
                                                            let coordinate = CLLocationCoordinate2D(latitude: post.latitude, longitude: post.longitude)
                                                            print("📍 [ProfileView] Long press - showing post location on map: \(coordinate.latitude), \(coordinate.longitude)")
                                                            NotificationCenter.default.post(
                                                                name: Notification.Name("ShowLocationOnMap"),
                                                                object: nil,
                                                                userInfo: ["coordinate": coordinate]
                                                            )
                                                            // Haptic feedback
                                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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

                // REMOVED: Global gesture layer - cube gestures now handled by the cube itself in TabBarControllerHost
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
                            // Notify radius change for global radius bar sync on fullscreen appearance
                            NotificationCenter.default.post(name: Notification.Name("currentPostRadiusDidChange"), object: nil, userInfo: ["radius": Double(post.radius)])
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
                            if isOwnProfile {
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
            
            NavigationLink(isActive: $navigateToMessages) {
                MessagesRootView()
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
                if !isRunningInPreviews {
                    print("📊 [ProfileView] Initial .task running for userID: \(userID ?? "nil")")
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
                    await loadMyPosts()
                    await MainActor.run {
                        self.averageRadius = Double(self.averagePostRadius())
                        self.hasLoadedOnce = true
                        
                        // Animate radius bar to show total accumulated radius after loading
                        if self.averageRadius > 0 {
                            print("📊 [ProfileView] Posts loaded, animating radius bar to total: \(self.averageRadius)m")
                            RadiusBarAnimator.animate(to: self.averageRadius, duration: 1.2)
                        } else {
                            print("📊 [ProfileView] No posts loaded, radius stays at 0")
                        }
                    }
                    
                    // Only load profile image for own profile
                    if isOwnProfile {
                        await loadPersistedProfileImageIfNeeded()
                    }
                } else {
                    await MainActor.run {
                        self.myPosts = []
                        self.loadedImages = [:]
                        self.hasLoadedOnce = true
                        self.canLoadMore = false
                    }
                }
            }
            .onAppear {
                NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                
                // Immediately set radius to 0 when profile appears (before posts load)
                print("📊 [ProfileView] onAppear - setting radius to 0")
                RadiusBarAnimator.animate(to: 0, duration: 0.3)
                
                // Don't load posts here if we're already loading in .task
                // This prevents double-loading
                
                // Animate radius bar to show total accumulated radius (only if already loaded)
                if hasLoadedOnce && averageRadius > 0 {
                    print("📊 [ProfileView] Animating radius bar to total: \(averageRadius)m")
                    RadiusBarAnimator.animate(to: averageRadius, duration: 1.0)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ProfileRemovePost"))) { notif in
                if let id = notif.object as? String {
                    myPosts.removeAll { $0.id == id }
                    self.averageRadius = Double(self.averagePostRadius())
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cubeHoldBegan)) { _ in
                print("🎯 [ProfileView] Received cubeHoldBegan - isOwnProfile: \(isOwnProfile)")
                if !isRunningInPreviews { 
                    isHoldingCube = true
                    
                    // Navigate to messages if viewing own profile (after brief delay to allow hold gesture to complete)
                    if isOwnProfile {
                        print("✅ [ProfileView] Navigating to messages in 0.1s")
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
                            navigateToMessages = true
                        }
                    } else {
                        print("⚠️ [ProfileView] Not navigating to messages - not own profile")
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cubeHoldEnded)) { _ in
                if !isRunningInPreviews { isHoldingCube = false }
            }
            .task(id: isHoldingCube) {
                if isRunningInPreviews { return }
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
            .onReceive(NotificationCenter.default.publisher(for: .CubeGlobalTap)) { _ in
                print("🎯 [ProfileView] Received CubeGlobalTap - isOwnProfile: \(isOwnProfile)")
                // Only respond if we're viewing our own profile
                guard isOwnProfile else { 
                    print("⚠️ [ProfileView] Ignoring CubeGlobalTap - not own profile")
                    return 
                }
                print("✅ [ProfileView] Opening settings")
                showSettings = true
            }
            .onDisappear {
                // Reset radius bar when leaving profile view
                print("📊 [ProfileView] onDisappear - notifying to restore feed radius")
                NotificationCenter.default.post(name: Notification.Name("ProfileViewDismissed"), object: nil)
            }
        }
        .id(viewID) // Force recreation when viewing different user
    }

    private var avatarRow: some View {
        Group {
            if isOwnProfile {
                Button {
                    navigateToScanner = true
                } label: {
                    avatarContent
                }
                .contextMenu {
                    Button(role: .destructive) {
                        deleteProfilePhoto()
                    } label: {
                        Label("Delete Profile Photo", systemImage: "trash")
                    }
                }
                .buttonStyle(.plain)
            } else {
                avatarContent
            }
        }
    }
    
    private var avatarContent: some View {
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
            } else if isOwnProfile, let email = auth.currentUser?.email,
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
            if lastHeadModelURL != nil && isOwnProfile {
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

    private var usernameRow: some View {
        Text(displayUsername ?? (isOwnProfile ? (auth.currentUser?.email?.components(separatedBy: "@").first?.uppercased() ?? "USERNAME") : "USER"))
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .foregroundColor(.black.opacity(0.95))
            .padding(.top, 4)
            .task {
                // Fetch username for the profile being viewed
                if let uid = userID ?? Auth.auth().currentUser?.uid {
                    displayUsername = await UsernameCache.shared.username(for: uid)
                }
            }
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
        if isRunningInPreviews {
            await MainActor.run {
                self.myPosts = []
                self.loadedImages = [:]
                self.hasLoadedOnce = true
                self.canLoadMore = false
            }
            return
        }

        let targetUID: String
        if let provided = userID, !provided.isEmpty {
            targetUID = provided
            print("🔑 [ProfileView] Using provided userID: \(targetUID) (viewing \(isOwnProfile ? "own" : "other") profile)")
        } else if let current = Auth.auth().currentUser?.uid {
            targetUID = current
            print("🔑 [ProfileView] Using current user's UID: \(targetUID) (own profile)")
        } else {
            print("❌ [ProfileView] No user ID available - not logged in?")
            await MainActor.run {
                myPosts = []
                loadedImages = [:]
                hasLoadedOnce = true
                canLoadMore = false
                lastDocument = nil
            }
            return
        }
        
        print("🔍 [ProfileView] About to query posts for userID: '\(targetUID)'")
        print("📊 [ProfileView] isOwnProfile: \(isOwnProfile)")
        
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
        if let provided = userID, !provided.isEmpty {
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
        print("🔍 [ProfileView] Fetching posts for userID: \(uid)")
        print("📄 [ProfileView] Query params - limit: \(limit), after: \(last?.documentID ?? "start")")
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<PostsPage, Error>) in
            let db = Firestore.firestore()
            // Try query with createdAt first, fall back to query without if it fails
            var query: Query = db.collection("posts")
                .whereField("userID", isEqualTo: uid)
            
            print("🔎 [ProfileView] Executing Firestore query: posts where userID == '\(uid)'")
            
            // Only order by createdAt if we're not starting from a cursor
            // This helps with posts that might not have createdAt field
            if last == nil {
                query = query.order(by: "createdAt", descending: true)
                print("🔎 [ProfileView] Adding order by createdAt (descending)")
            }
            
            query = query.limit(to: limit)
            
            if let last = last {
                query = query.start(afterDocument: last)
                print("🔎 [ProfileView] Starting after document: \(last.documentID)")
            }
            
            query.getDocuments { snap, err in
                if let err = err {
                    print("❌ [ProfileView] Error fetching posts: \(err.localizedDescription)")
                    // Try fallback query without createdAt ordering
                    print("🔄 [ProfileView] Trying fallback query without createdAt ordering...")
                    let fallbackQuery = db.collection("posts")
                        .whereField("userID", isEqualTo: uid)
                        .limit(to: limit)
                    
                    fallbackQuery.getDocuments { snap2, err2 in
                        if let err2 = err2 {
                            print("❌ [ProfileView] Fallback query also failed: \(err2.localizedDescription)")
                            cont.resume(throwing: err2)
                            return
                        }
                        guard let snap2 = snap2 else {
                            print("⚠️ [ProfileView] No snapshot returned from fallback")
                            cont.resume(returning: PostsPage(posts: [], lastDoc: nil))
                            return
                        }
                        print("📊 [ProfileView] Fallback received \(snap2.documents.count) documents")
                        if snap2.documents.isEmpty {
                            print("⚠️ [ProfileView] No documents found for userID: '\(uid)'")
                        } else {
                            print("✅ [ProfileView] Found \(snap2.documents.count) documents, mapping to Post objects...")
                        }
                        let posts = Self.mapPosts(from: snap2)
                        print("✅ [ProfileView] Fallback mapped \(posts.count) posts")
                        cont.resume(returning: PostsPage(posts: posts, lastDoc: snap2.documents.last))
                    }
                    return
                }
                guard let snap = snap else {
                    print("⚠️ [ProfileView] No snapshot returned")
                    cont.resume(returning: PostsPage(posts: [], lastDoc: nil))
                    return
                }
                print("📊 [ProfileView] Received \(snap.documents.count) documents from Firebase")
                if snap.documents.isEmpty {
                    print("⚠️ [ProfileView] No documents found for userID: '\(uid)'")
                    print("💡 [ProfileView] This could mean:")
                    print("   - User has not created any posts yet")
                    print("   - UserID field in Firebase uses different casing (userId vs userID)")
                    print("   - Posts are stored under a different collection")
                } else {
                    print("✅ [ProfileView] Found \(snap.documents.count) documents, mapping to Post objects...")
                }
                let posts = Self.mapPosts(from: snap)
                print("✅ [ProfileView] Successfully mapped \(posts.count) posts")
                if posts.count != snap.documents.count {
                    print("⚠️ [ProfileView] Some documents failed to map. Raw count: \(snap.documents.count), Mapped: \(posts.count)")
                    // Debug: print first failed document
                    for doc in snap.documents {
                        let data = doc.data()
                        if !posts.contains(where: { $0.id == doc.documentID }) {
                            print("❌ [ProfileView] Failed to map document \(doc.documentID):")
                            print("   - mediaURL: \(data["mediaURL"] as? String ?? "missing")")
                            print("   - latitude: \(data["latitude"] ?? "missing")")
                            print("   - longitude: \(data["longitude"] ?? "missing")")
                            print("   - radius: \(data["radius"] ?? "missing")")
                            print("   - userID: \(data["userID"] as? String ?? "missing")")
                        }
                    }
                }
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
            let posterURL = data["posterURL"] as? String
            return Post(id: doc.documentID, latitude: lat, longitude: lon, mediaURL: mediaURL, radius: radius, viewCount: viewCount, userID: userID, posterURL: posterURL)
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
            let posterURL = data["posterURL"] as? String
            return Post(id: doc.documentID, latitude: lat, longitude: lon, mediaURL: mediaURL, radius: radius, viewCount: viewCount, userID: userID, posterURL: posterURL)
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
        if myPosts.isEmpty { return 0 }
        // Changed to total accumulated radius instead of average
        let total = myPosts.reduce(0) { $0 + $1.radius }
        return total
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

#if DEBUG
import SwiftUI

#Preview("ProfileView") {
    ProfileView(userID: "preview-user-123", initialMode: .grid)
        .environmentObject(AuthViewModel())
}
#endif

