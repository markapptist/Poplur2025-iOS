import SwiftUI
import UIKit
import SpriteKit
import FirebaseAuth
@preconcurrency import FirebaseFirestore
import UserNotifications
import ARKit

// ProfileView listens for:
// - OpenUserDetailForUser: ["userID": String, "currentPostID": String] to show a specific user's profile
// - LastTappedUserChanged: ["userID": String, "radius": Double, "currentPostID": String] to reflect current feed context (radius bar)
// - PostCreated: ["id": String, "userID": String, "latitude": Double, "longitude": Double, "mediaURL": String, "radius": Double, "viewCount": Int] to insert newly published posts immediately
// Long-press on a post will emit OpenCameraAtCoordinate with both coordinate and lat/lon for map navigation.

private var isRunningInPreviews: Bool {
    let env = ProcessInfo.processInfo.environment
    return env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || env["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1"
}

private struct ProfileNotificationItem: Identifiable {
    enum Kind {
        case like
        case postRadius
        case accumulatedRadius

        var iconName: String {
            switch self {
            case .like: return "heart.fill"
            case .postRadius: return "arrow.up.right.circle.fill"
            case .accumulatedRadius: return "arrow.down.right.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .like: return .pink
            case .postRadius: return .green
            case .accumulatedRadius: return .red
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
    let isUnchecked: Bool
}

private extension ProfileNotificationItem.Kind {
    init(deviceKind: PoplurDeviceNotification.Kind) {
        switch deviceKind {
        case .radiusGrowth:
            self = .postRadius
        case .radiusDip:
            self = .accumulatedRadius
        case .areaTakeover, .dailyInsight:
            self = .like
        }
    }
}

struct ProfileView: View {
    @Environment(\.layoutPreviewMode) private var layoutPreviewMode
    @EnvironmentObject private var auth: AuthViewModel
    @GestureState private var isInteractingWithCube: Bool = false
    @State private var isScrollDisabled = false
    
    // Injected userID from tab bar when navigating from feed
    @Environment(\.routedUserID) private var routedUserID
    
    // Track if we're viewing own profile or another user's
    private var isOwnProfile: Bool {
        let targetUserID = effectiveUserID
        if let currentUID = Auth.auth().currentUser?.uid {
            let result = currentUID == targetUserID
            print("🔍 [ProfileView] isOwnProfile check - currentUID: \(currentUID), targetUserID: \(targetUserID ?? "nil"), result: \(result)")
            return result
        }
        print("🔍 [ProfileView] isOwnProfile check - no current user, assuming own profile")
        return true
    }
    
    // The effective userID to display: routedUserID takes precedence over userID parameter, then falls back to current user
    private var effectiveUserID: String? {
        if let routed = routedUserID, !routed.isEmpty {
            return routed
        }
        if let param = userID, !param.isEmpty {
            return param
        }
        // Fall back to current logged-in user
        return Auth.auth().currentUser?.uid
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
    @State private var showPopularPhone = false
    @State private var showNotifications = false
    @State private var hasUncheckedNotifications = true
    @StateObject private var notificationCenter = PoplurNotificationCenter.shared
    @State private var showRadiusStore = false
    @State private var purchasedRadiusMeters: Int = 0
    @StateObject private var radiusPurchaseVM = RadiusPurchaseViewModel()
    @State private var averageRadius: Double = 5000
    @State private var navigateToScanner = false
    @State private var showImagePicker = false
    @State private var showProfilePhotoOptions = false
    
    @State private var lastHeadModelURL: URL? = nil

    @State private var navigateToViewer = false

    @State private var barHeightFactor: CGFloat = 1.0
    @State private var isHoldingCube: Bool = false
    @StateObject private var cubeMenuWheel = CubeMenuWheelController()

    @State private var isLoadingMore = false
    @State private var canLoadMore = true
    @State private var lastDocument: QueryDocumentSnapshot? = nil
    private let pageSize = 18

    private enum ProfileSubmenuRoute {
        case mail
        case settings
        case notifications
        case phone
        case store
    }

    private var isShowingMainTabChildRoute: Bool {
        showSettings || navigateToMessages || showNotifications || showRadiusStore || navigateToScanner || navigateToViewer
    }

    private func postMainTabChildRouteVisibility() {
        NotificationCenter.default.post(
            name: .MainTabChildRouteVisibilityChanged,
            object: isShowingMainTabChildRoute
        )
    }

    private func postProfileCubeIconOverride(_ item: CubeSubmenuItem?) {
        guard isOwnProfile else { return }
        if let item {
            NotificationCenter.default.post(
                name: .CubeProfileIconOverrideChanged,
                object: nil,
                userInfo: [
                    "title": item.title,
                    "systemImage": item.systemImage
                ]
            )
        } else {
            NotificationCenter.default.post(name: .CubeProfileIconOverrideChanged, object: nil)
        }
    }

    private func postProfileCubeIconOverride(forSubmenuID id: String) {
        postProfileCubeIconOverride(cubeSubmenuItems.first { $0.id == id })
    }

    private func syncProfileCubeIconToActiveRoute() {
        guard !cubeMenuWheel.isOnScreen else { return }
        if showPopularPhone {
            postProfileCubeIconOverride(forSubmenuID: "phone")
        } else if navigateToMessages {
            postProfileCubeIconOverride(forSubmenuID: "mail")
        } else if showSettings {
            postProfileCubeIconOverride(forSubmenuID: "settings")
        } else if showNotifications {
            postProfileCubeIconOverride(forSubmenuID: "notifications")
        } else if showRadiusStore {
            postProfileCubeIconOverride(forSubmenuID: "store")
        } else {
            postProfileCubeIconOverride(nil)
        }
    }

    private func openProfileSubmenuRoute(_ route: ProfileSubmenuRoute) {
        navigateToScanner = false
        navigateToViewer = false
        showSettings = route == .settings
        navigateToMessages = route == .mail
        showNotifications = route == .notifications
        showPopularPhone = route == .phone
        showRadiusStore = route == .store

        if route == .notifications {
            hasUncheckedNotifications = false
        }
    }

    private func closeProfileSubroutes() {
        editing = false
        showProfilePhotoOptions = false
        showPopularPhone = false
        showSettings = false
        navigateToMessages = false
        showNotifications = false
        showRadiusStore = false
        navigateToScanner = false
        navigateToViewer = false
    }

    private var cubeSubmenuItems: [CubeSubmenuItem] {
        [
            CubeSubmenuItem(
                id: "mail",
                title: "Mail",
                systemImage: "envelope.fill",
                tint: Color(red: 0.42, green: 1.0, blue: 0.33)
            ) {
                openProfileSubmenuRoute(.mail)
            },
            CubeSubmenuItem(
                id: "settings",
                title: "Settings",
                systemImage: "gearshape.fill",
                tint: .indigo
            ) {
                openProfileSubmenuRoute(.settings)
            },
            CubeSubmenuItem(
                id: "notifications",
                title: "Notifications",
                systemImage: "bell.fill",
                tint: .orange
            ) {
                openProfileSubmenuRoute(.notifications)
            },
            CubeSubmenuItem(
                id: "phone",
                title: "Phone",
                systemImage: "phone.fill",
                tint: .teal
            ) {
                openProfileSubmenuRoute(.phone)
            },
            CubeSubmenuItem(
                id: "store",
                title: "Store",
                systemImage: "cart.fill",
                tint: Color(red: 0.95, green: 0.55, blue: 0.16)
            ) {
                openProfileSubmenuRoute(.store)
            }
        ]
    }
    
    // Helper to create binding for EditProfileView
    private var editableUserProfileBinding: Binding<AnyEditableUserProfile?> {
        Binding(
            get: {
                guard let profile = userProfile else { return nil }
                return AnyEditableUserProfile(
                    getUsername: { profile.username },
                    setUsername: { _ in }, // Will be handled in the setter
                    getEmail: { profile.email },
                    setEmail: { _ in }, // Will be handled in the setter
                    getProfilePictureURL: { profile.profilePictureURL }
                )
            },
            set: { newValue in
                if let newValue = newValue, var profile = userProfile {
                    profile.username = newValue.username
                    profile.email = newValue.email
                    userProfile = profile
                }
            }
        )
    }

    enum DisplayMode: String, CaseIterable, Identifiable {
        case media // Changed from 'list'
        case messages // Changed from 'grid'
        var id: String { rawValue }
    }
    @State private var mode: DisplayMode = .media

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
        let id = effectiveUserID ?? "own-profile"
        // Debug logging to verify view recreation
        print("🆔 [ProfileView] viewID computed as: '\(id)'")
        return id
    }

    init(userID: String? = nil, initialMode: DisplayMode = .media) {
        self.userID = userID
        _mode = State(initialValue: initialMode)
        print("🏗️ [ProfileView] Initialized with userID: \(userID ?? "nil")")
    }

    private var profileNotifications: [ProfileNotificationItem] {
        notificationCenter.notifications.map { item in
            ProfileNotificationItem(
                kind: ProfileNotificationItem.Kind(deviceKind: item.kind),
                title: item.title,
                detail: item.detail,
                isUnchecked: item.isUnread
            )
        }
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

    @ViewBuilder
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        avatarRow
                        usernameRow
                        modeSwitcher
                    }
                    .padding(.top, isOwnProfile ? 8 : 0)
                    .padding(.bottom, 0)

                    // Scrollable content with readers for "scroll to top"
                    ScrollViewReader { proxy in
                        Group {
                            if isLoading || !hasLoadedOnce {
                                VStack(spacing: 12) {
                                    ProgressView()
                                        .controlSize(.regular)
                                    Text("Loading posts")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                case .media:
                                    ScrollView {
                                        VStack(spacing: 0) {
                                            Color.clear.frame(height: 0).id("top")
                                            LazyVGrid(columns: gridCols, spacing: tileSpacing) {
                                                ForEach(myPosts) { post in
                                                    ProfileGridTile(post: post, preloadedImage: loadedImages[post.id])
                                                        .onTapGesture {
                                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                                                expandedPost = post
                                                                // Notify radius change for global radius bar sync
                                                                NotificationCenter.default.post(name: Notification.Name("currentPostRadiusDidChange"), object: nil, userInfo: ["radius": Double(post.radius)])
                                                            }
                                                        }
                                                        .onLongPressGesture(minimumDuration: 0.5) {
                                                            // Long press to show post location on map with user annotation
                                                            let coordinate = CLLocationCoordinate2D(latitude: post.latitude, longitude: post.longitude)
                                                            print("📍 [ProfileView Grid] Long press - showing post location: \(coordinate.latitude), \(coordinate.longitude)")
                                                            print("   Post radius: \(post.radius)m")
                                                            
                                                            // Haptic feedback
                                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                                            
                                                            // Get profile image URL
                                                            let profileURL: String? = post.posterURL ?? userProfile?.profilePictureURL?.absoluteString
                                                            
                                                            print("📍 [ProfileView Grid] Setting pending post location in MapStateManager")
                                                            
                                                            // Store in shared state manager - this persists even when MapView isn't loaded
                                                            MapStateManager.shared.setPendingPostLocation(
                                                                coordinate,
                                                                userID: post.userID,
                                                                username: displayUsername,
                                                                profileImageURL: profileURL,
                                                                radius: Double(post.radius)
                                                            )
                                                            
                                                            // Also post notification for already-loaded MapView instances
                                                            var userInfo: [String: Any] = [
                                                                "coordinate": coordinate,
                                                                "userID": post.userID,
                                                                "radius": Double(post.radius)
                                                            ]
                                                            
                                                            if let username = displayUsername {
                                                                userInfo["username"] = username
                                                            }
                                                            
                                                            if let profileURL = profileURL {
                                                                userInfo["profileImageURL"] = profileURL
                                                            }
                                                            
                                                            NotificationCenter.default.post(
                                                                name: Notification.Name("ShowLocationOnMap"),
                                                                object: nil,
                                                                userInfo: userInfo
                                                            )
                                                            
                                                            // Wait a moment for map to process location before switching tabs
                                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                                                // Then switch to map tab
                                                                NotificationCenter.default.post(
                                                                    name: Notification.Name("SwitchToMapTab"),
                                                                    object: nil
                                                                )
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
                                case .messages:
                                    ScrollView {
                                        VStack(spacing: 0) {
                                            Color.clear.frame(height: 0).id("top")
                                            VStack(spacing: 18) {
                                                // Messages view - placeholder for now
                                                VStack(spacing: 12) {
                                                    Image(systemName: "message.fill")
                                                        .font(.system(size: 48, weight: .semibold))
                                                        .foregroundColor(.secondary)
                                                    Text("Messages")
                                                        .font(.headline)
                                                        .foregroundColor(.primary)
                                                    Text("Your uploaded messages will appear here")
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                        .multilineTextAlignment(.center)
                                                }
                                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                                .padding(.top, 60)
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
                        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ResetTabToTop"))) { _ in
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
                                userID: post.userID,
                                cityName: nil,
                                countryName: nil,
                                countryFlag: nil
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

                if cubeMenuWheel.isOnScreen && isOwnProfile {
                    CubeMenuWheelOverlay(controller: cubeMenuWheel)
                    .transition(.opacity)
                    .zIndex(20)
                }

                if showPopularPhone {
                    PopularPhone(user: FakeUser(id: UUID(), name: "Poplur Phone"))
                        .transition(.opacity)
                        .zIndex(30)
                }

                if editing {
                    EditProfileView(user: editableUserProfileBinding) {
                        editing = false
                    }
                    .transition(.opacity)
                    .zIndex(40)
                }

                if showProfilePhotoOptions {
                    VStack(spacing: 12) {
                        Button("Scan Face (AR)") {
                            showProfilePhotoOptions = false
                            navigateToScanner = true
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Take Photo") {
                            showProfilePhotoOptions = false
                            showImagePicker = true
                        }
                        .buttonStyle(.bordered)

                        if profileImage != nil || profileImageURL != nil {
                            Button("Delete Photo", role: .destructive) {
                                showProfilePhotoOptions = false
                                deleteProfilePhoto()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 28)
                    .transition(.opacity)
                    .zIndex(45)
                }

                if showSettings {
                    AppSettingsView()
                        .transition(.opacity)
                        .zIndex(50)
                }

                if navigateToMessages {
                    MessagesRootView()
                        .transition(.opacity)
                        .zIndex(51)
                }

                if showNotifications {
                    ProfileNotificationsView(
                        notifications: profileNotifications,
                        onMarkRead: {
                            hasUncheckedNotifications = false
                            notificationCenter.markAllRead()
                        }
                    )
                    .transition(.opacity)
                    .zIndex(52)
                }

                if showRadiusStore {
                    RadiusStoreView(
                        purchasedRadiusMeters: $purchasedRadiusMeters,
                        userID: effectiveUserID,
                        purchaseVM: radiusPurchaseVM
                    )
                    .transition(.opacity)
                    .zIndex(53)
                }

                if navigateToScanner {
                    HeadScannerView { result in
                        switch result {
                        case .success(let output):
                            // Save snapshot image for ML face recognition
                            if let image = output.previewImage {
                                self.profileImage = image
                                if let url = try? saveProfileImage(image) {
                                    self.profileImageURL = url
                                    // Save for face recognition ML model
                                    saveFaceForRecognition(image: image)
                                }
                                NotificationCenter.default.post(name: Notification.Name("ProfilePhotoUpdated"), object: image)
                            }
                            // Save 3D model URL if available
                            self.lastHeadModelURL = output.usdzURL
                            if output.usdzURL != nil {
                                self.navigateToViewer = true
                            }
                        case .failure:
                            break
                        }
                    }
                    .transition(.opacity)
                    .zIndex(54)
                }

                if navigateToViewer {
                    if let url = lastHeadModelURL {
                        USDZViewerView(usdzURL: url)
                            .transition(.opacity)
                            .zIndex(55)
                    } else {
                        Text("No model available")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                            .foregroundColor(.white)
                            .transition(.opacity)
                            .zIndex(55)
                    }
                }
            }

            .sheet(isPresented: $showImagePicker) {
                ImagePickerView(
                    selectedImage: Binding(
                        get: { self.profileImage },
                        set: { newImage in
                            if let image = newImage {
                                self.profileImage = image
                                if let url = try? saveProfileImage(image) {
                                    self.profileImageURL = url
                                    // Save for face recognition ML model
                                    saveFaceForRecognition(image: image)
                                }
                                NotificationCenter.default.post(name: Notification.Name("ProfilePhotoUpdated"), object: image)
                            }
                        }
                    ),
                    selectedVideoURL: .constant(nil)
                )
            }

            .task {
                if !isRunningInPreviews {
                    print("📊 [ProfileView] Initial .task running for userID: \(userID ?? "nil")")
                    _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
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
                        self.refreshDailyNotificationsFromCurrentPosts()
                    }
                    
                    // Only load profile image for own profile
                    if isOwnProfile {
                        await loadPersistedProfileImageIfNeeded()
                    }
                } else {
                    await MainActor.run {
                        self.applyPreviewProfileData()
                    }
                }
            }
            .onAppear {
                print("👀 [ProfileView] onAppear isOwnProfile=\(isOwnProfile) effectiveUserID=\(effectiveUserID ?? "nil")")
                NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                
                // Immediately set radius to 0 when profile appears (before posts load)
                print("📊 [ProfileView] onAppear - setting radius to 0")
                RadiusBarAnimator.animate(to: 0, duration: 0.3)
                
                // ALWAYS reload posts when appearing to ensure we show the correct user's posts
                print("📊 [ProfileView] onAppear - reloading posts for userID: \(effectiveUserID ?? "nil")")
                Task {
                    await loadMyPosts()
                    
                    // Update radius bar after posts load
                    await MainActor.run {
                        self.averageRadius = Double(self.averagePostRadius())
                        if self.averageRadius > 0 {
                            print("📊 [ProfileView] onAppear - posts loaded, animating radius bar to: \(self.averageRadius)m")
                            RadiusBarAnimator.animate(to: self.averageRadius, duration: 1.2)
                        } else {
                            print("📊 [ProfileView] onAppear - no posts, keeping radius at 0")
                            // Ensure radius stays at 0 if no posts
                            RadiusBarAnimator.animate(to: 0, duration: 0.3)
                        }
                        self.refreshDailyNotificationsFromCurrentPosts()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ProfileRemovePost"))) { notif in
                if let id = notif.object as? String {
                    myPosts.removeAll { $0.id == id }
                    self.averageRadius = Double(self.averagePostRadius())
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenUserDetailForUser"))) { notif in
                guard let userInfo = notif.userInfo, let uid = userInfo["userID"] as? String else { return }
                // If our routedUserID environment isn't handling this, reload locally for the requested user
                if uid != effectiveUserID {
                    print("👤 [ProfileView] OpenUserDetailForUser received for uid=\(uid). Reloading profile locally.")
                    // Clear and reload for the specified user
                    displayUsername = nil
                    userProfile = nil
                    profileImage = nil
                    profileImageURL = nil
                    myPosts = []
                    loadedImages = [:]
                    hasLoadedOnce = false
                    averageRadius = 0
                    RadiusBarAnimator.animate(to: 0, duration: 0.3)
                    Task {
                        // Temporarily override by using the parameter initializer path
                        // We can't change routedUserID here, so load posts for uid directly
                        await loadPostsForSpecificUser(uid)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LastTappedUserChanged"))) { notif in
                guard let info = notif.userInfo,
                      let uid = info["userID"] as? String,
                      let radius = info["radius"] as? Double else { return }
                if uid == effectiveUserID {
                    print("📏 [ProfileView] Updating radius bar for current user to \(radius)m from feed context")
                    RadiusBarAnimator.animate(to: radius, duration: 0.6)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ProfileShowUserContext"))) { notif in
                guard let info = notif.userInfo,
                      let uid = info["userID"] as? String else { return }
                let radius = info["radius"] as? Double
                let currentPostID = info["currentPostID"] as? String

                print("👤 [ProfileView] ProfileShowUserContext for uid=\(uid) radius=\(radius.map{String($0)} ?? "nil") currentPostID=\(currentPostID ?? "nil")")

                // If this context refers to a different user, reload for that user immediately
                if uid != effectiveUserID {
                    displayUsername = nil
                    userProfile = nil
                    profileImage = nil
                    profileImageURL = nil
                    myPosts = []
                    loadedImages = [:]
                    hasLoadedOnce = false
                    averageRadius = 0
                    RadiusBarAnimator.animate(to: 0, duration: 0.3)
                    Task { await loadPostsForSpecificUser(uid) }
                }

                // Apply incoming radius to the global bar if provided and matches the viewed user
                if let r = radius, uid == effectiveUserID {
                    RadiusBarAnimator.animate(to: r, duration: 0.6)
                }

                // If a current post was specified, try to bring it into view after posts are loaded
                if let pid = currentPostID {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        if let match = myPosts.first(where: { $0.id == pid }) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                expandedPost = match
                                NotificationCenter.default.post(name: Notification.Name("currentPostRadiusDidChange"), object: nil, userInfo: ["radius": Double(match.radius)])
                            }
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RefreshProfileAfterUpload"))) { _ in
                print("🔄 [ProfileView] RefreshProfileAfterUpload received - reloading posts")
                Task {
                    await loadMyPosts()
                    // After reload, scroll to top and open the newest post if available
                    await MainActor.run {
                        if let newest = myPosts.first {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                expandedPost = newest
                                NotificationCenter.default.post(name: Notification.Name("currentPostRadiusDidChange"), object: nil, userInfo: ["radius": Double(newest.radius)])
                            }
                        }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PostCreated"))) { notif in
                guard let info = notif.userInfo,
                      let id = info["id"] as? String,
                      let uid = info["userID"] as? String,
                      let lat = info["latitude"] as? Double,
                      let lon = info["longitude"] as? Double,
                      let mediaURL = info["mediaURL"] as? String,
                      let rawRadiusDouble = info["radius"] as? Double ?? (info["radius"] as? Int).map(Double.init) else {
                    print("⚠️ [ProfileView] PostCreated missing fields; ignoring")
                    return
                }
                let radius = rawRadiusDouble
                let viewCount = (info["viewCount"] as? Int) ?? 0
                // Only insert if the post belongs to the user currently displayed
                guard uid == effectiveUserID else { return }
                let newPost = Post(
                    id: id,
                    latitude: lat,
                    longitude: lon,
                    mediaURL: mediaURL,
                    radius: Int(radius),
                    viewCount: viewCount,
                    userID: uid,
                    posterURL: nil
                )
                // Avoid duplicates
                if myPosts.contains(where: { $0.id == id }) { return }
                // Prepend for recency
                myPosts.insert(newPost, at: 0)
                // Persist cache
                savePostsToCache(myPosts, for: uid)
                // Prefetch image
                Task.detached { await prefetchImages(for: [newPost]) }
                // Update radius bar to reflect new total
                averageRadius = Double(averagePostRadius())
                RadiusBarAnimator.animate(to: averageRadius, duration: 0.8)
                refreshDailyNotificationsFromCurrentPosts()
            }
            .onReceive(NotificationCenter.default.publisher(for: .cubeHoldBegan)) { _ in
                print("🎯 [ProfileView] Received cubeHoldBegan - isOwnProfile: \(isOwnProfile)")
                if !isRunningInPreviews {
                    isHoldingCube = true

                    if isOwnProfile {
                        print("✅ [ProfileView] Showing cube menu wheel")
                        cubeMenuWheel.beginHold(items: cubeSubmenuItems)
                        postProfileCubeIconOverride(cubeMenuWheel.selectedItem)
                    } else {
                        print("⚠️ [ProfileView] Not showing cube menu wheel - not own profile")
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .cubeHoldEnded)) { _ in
                if !isRunningInPreviews {
                    isHoldingCube = false
                    if isOwnProfile {
                        postProfileCubeIconOverride(cubeMenuWheel.selectedItem)
                        cubeMenuWheel.endHold(activateSelected: true)
                    }
                }
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
                if cubeMenuWheel.isOnScreen {
                    print("✅ [ProfileView] Closing cube menu wheel")
                    postProfileCubeIconOverride(nil)
                    cubeMenuWheel.endHold(activateSelected: false)
                    return
                }
                if expandedPost != nil {
                    expandedPost = nil
                    return
                }
                if editing || showProfilePhotoOptions || showPopularPhone || isShowingMainTabChildRoute {
                    closeProfileSubroutes()
                    return
                }
                print("✅ [ProfileView] Opening messages")
                openProfileSubmenuRoute(.mail)
            }
            .onDisappear {
                // Reset radius bar when leaving profile view
                print("📊 [ProfileView] onDisappear - notifying to restore feed radius")
                cubeMenuWheel.endHold(activateSelected: false)
                postProfileCubeIconOverride(nil)
                NotificationCenter.default.post(name: Notification.Name("ProfileViewDismissed"), object: nil)
                NotificationCenter.default.post(name: .MainTabChildRouteVisibilityChanged, object: false)
            }
            .onChange(of: cubeMenuWheel.selectedIndex) { _, _ in
                if cubeMenuWheel.isVisible {
                    postProfileCubeIconOverride(cubeMenuWheel.selectedItem)
                }
            }
            .onChange(of: showSettings) { _, _ in
                postMainTabChildRouteVisibility()
                syncProfileCubeIconToActiveRoute()
            }
            .onChange(of: navigateToMessages) { _, _ in
                postMainTabChildRouteVisibility()
                syncProfileCubeIconToActiveRoute()
            }
            .onChange(of: showNotifications) { _, _ in
                postMainTabChildRouteVisibility()
                syncProfileCubeIconToActiveRoute()
            }
            .onChange(of: showRadiusStore) { _, _ in
                postMainTabChildRouteVisibility()
                syncProfileCubeIconToActiveRoute()
            }
            .onChange(of: showPopularPhone) { _, _ in
                syncProfileCubeIconToActiveRoute()
            }
            .onChange(of: navigateToScanner) { _, _ in
                postMainTabChildRouteVisibility()
                syncProfileCubeIconToActiveRoute()
            }
            .onChange(of: navigateToViewer) { _, _ in
                postMainTabChildRouteVisibility()
            }
            .onChange(of: routedUserID) { _, newUserID in
                print("🔄 [ProfileView] routedUserID changed to: \(newUserID ?? "nil")")
                // Clear all state and reload everything when viewing a different user
                displayUsername = nil
                userProfile = nil
                profileImage = nil
                profileImageURL = nil
                myPosts = []
                loadedImages = [:]
                hasLoadedOnce = false
                averageRadius = 0  // Reset average radius to 0 when switching users
                
                // Reset radius bar to 0 when switching users
                RadiusBarAnimator.animate(to: 0, duration: 0.3)
                
                Task {
                    // Reload posts for the new user
                    await loadMyPosts()
                    
                    // Fetch username for the new user
                    if let uid = effectiveUserID {
                        displayUsername = await UsernameCache.shared.username(for: uid)
                    }
                    
                    // Only load profile image for own profile
                    if isOwnProfile {
                        await loadPersistedProfileImageIfNeeded()
                    }
                    
                    // Update radius bar with new user's total radius
                    await MainActor.run {
                        self.averageRadius = Double(self.averagePostRadius())
                        if self.averageRadius > 0 {
                            print("📊 [ProfileView] User switched, animating radius bar to: \(self.averageRadius)m")
                            RadiusBarAnimator.animate(to: self.averageRadius, duration: 1.2)
                        } else {
                            print("📊 [ProfileView] User switched, no posts - keeping radius at 0")
                            // Ensure radius stays at 0 if no posts
                            RadiusBarAnimator.animate(to: 0, duration: 0.3)
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .id(viewID) // Force recreation when viewing different user
        }

    private var avatarRow: some View {
        Group {
            if isOwnProfile {
                Button {
                    showProfilePhotoOptions = true
                } label: {
                    avatarContent
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
        Text(displayUsername ?? (isOwnProfile ? (auth.currentUser?.email?.components(separatedBy: "@").first?.uppercased() ?? "USERNAME") : usernameForDemoUser()))
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .foregroundColor(.black.opacity(0.95))
            .padding(.top, 4)
            .task(id: effectiveUserID) {
                // Fetch username for the profile being viewed (re-runs when effectiveUserID changes)
                if let uid = effectiveUserID ?? Auth.auth().currentUser?.uid {
                    displayUsername = await UsernameCache.shared.username(for: uid)
                }
            }
    }
    
    // Helper to generate readable username for demo users
    private func usernameForDemoUser() -> String {
        guard let uid = effectiveUserID else { return "USER" }
        
        // Check if this is a demo user
        if uid.contains("_user_") {
            // Extract the channel name from the userID (e.g., "food_user_0" -> "FOOD USER 0")
            let components = uid.split(separator: "_")
            if components.count >= 2 {
                let channelName = String(components[0]).uppercased()
                let userNum = components.count > 2 ? String(components[2]) : "0"
                return "\(channelName) USER \(userNum)"
            }
        }
        
        return "USER"
    }

    private var modeSwitcher: some View {
        HStack(spacing: 36) {
            modeButton(title: "Media", isSelected: mode == .media) {
                mode = .media
            }
            modeButton(title: "Messages", isSelected: mode == .messages) {
                mode = .messages
            }
        }
        .padding(.top, 2)
    }

    private func modeButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black.opacity(0.85))
                    .padding(8)
            }
            .buttonStyle(.plain)

            Capsule()
                .fill(isSelected ? Color.indigo : Color.clear)
                .frame(width: 48, height: 3)
        }
    }

    @MainActor
    private func applyPreviewProfileData() {
        displayUsername = "USERNAME"
        let previewPosts = (0..<12).map { index in
            Post(
                id: "preview-profile-\(index)",
                latitude: 43.6532 + Double(index) * 0.002,
                longitude: -79.3832 - Double(index) * 0.002,
                mediaURL: "",
                radius: (index + 1) * 1_000,
                viewCount: 10 + index,
                userID: "preview-user"
            )
        }
        myPosts = previewPosts
        loadedImages = Dictionary(uniqueKeysWithValues: previewPosts.map { post in
            (post.id, previewProfileImage(seed: post.id.hashValue))
        })
        isLoading = false
        hasLoadedOnce = true
        canLoadMore = false
        isLoadingMore = false
    }

    private func previewProfileImage(seed: Int) -> UIImage {
        let size = CGSize(width: 220, height: 220)
        let colorPairs: [(UIColor, UIColor)] = [
            (.systemIndigo, .systemPink),
            (.systemTeal, .systemBlue),
            (.systemOrange, .systemRed),
            (.systemGreen, .systemMint)
        ]
        let safeSeed = seed == Int.min ? 0 : abs(seed)
        let pair = colorPairs[safeSeed % colorPairs.count]

        return UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size)
            let colors = [pair.0.cgColor, pair.1.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            UIColor.black.withAlphaComponent(0.16).setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: 28, dy: 28), cornerRadius: 32).fill()
        }
    }

    private func loadMyPosts() async {
        if isRunningInPreviews {
            await MainActor.run {
                self.applyPreviewProfileData()
            }
            return
        }

        let targetUID: String
        if let effective = effectiveUserID, !effective.isEmpty {
            targetUID = effective
            print("🔑 [ProfileView] Using effectiveUserID: \(targetUID) (viewing \(isOwnProfile ? "own" : "other") profile)")
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
        
        // Check if this is a demo user (userID contains "user_" pattern)
        let isDemoUser = targetUID.contains("_user_") || targetUID.hasPrefix("food_") || targetUID.hasPrefix("fitness_") || targetUID.hasPrefix("beauty_") || targetUID.hasPrefix("sports_") || targetUID.hasPrefix("modelling_") || targetUID.hasPrefix("fashion_") || targetUID.hasPrefix("music_") || targetUID.hasPrefix("tech_") || targetUID.hasPrefix("news_")
        
        if isDemoUser {
            print("🎭 [ProfileView] Demo user detected, loading from DemoPostStore")
            let demoPosts = DemoPostStore.shared.posts(for: targetUID)
            print("🎭 [ProfileView] Found \(demoPosts.count) demo posts for userID: '\(targetUID)'")
            print("🎭 [ProfileView] Total posts in DemoPostStore: \(DemoPostStore.shared.allPosts().count)")
            
            // Debug: Print all userIDs in the store
            let allUserIDs = Set(DemoPostStore.shared.allPosts().map { $0.userID })
            print("🎭 [ProfileView] Unique userIDs in store: \(allUserIDs.sorted())")
            
            // Convert FeedPost to Post
            let convertedPosts = demoPosts.map { feedPost in
                Post(
                    id: feedPost.id,
                    latitude: feedPost.latitude,
                    longitude: feedPost.longitude,
                    mediaURL: feedPost.mediaURL,
                    radius: Int(feedPost.radius),
                    viewCount: feedPost.viewCount,
                    userID: feedPost.userID,
                    posterURL: nil
                )
            }
            
            await MainActor.run {
                self.myPosts = convertedPosts
                self.hasLoadedOnce = true
                self.canLoadMore = false
                self.averageRadius = Double(self.averagePostRadius())
                self.isLoading = false
                self.refreshDailyNotificationsFromCurrentPosts()
            }
            
            Task.detached { await prefetchImages(for: convertedPosts) }
            return
        }
        
        // Try to show cached posts immediately for better perceived performance
        if let cached = loadPostsFromCache(for: targetUID), !cached.isEmpty {
            await MainActor.run {
                self.myPosts = cached
                self.hasLoadedOnce = true
                self.averageRadius = Double(self.averagePostRadius())
                self.refreshDailyNotificationsFromCurrentPosts()
            }
            // Prefetch images for cached posts
            Task.detached { await prefetchImages(for: cached) }
        } else {
            await MainActor.run {
                self.averageRadius = 0
            }
            RadiusBarAnimator.animate(to: 0, duration: 0.3)
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
                self.refreshDailyNotificationsFromCurrentPosts()
            }
            // Persist latest posts to cache
            savePostsToCache(page.posts, for: targetUID)
            Task.detached { await prefetchImages(for: page.posts) }
            
            if page.posts.isEmpty {
                await MainActor.run {
                    self.averageRadius = 0
                    RadiusBarAnimator.animate(to: 0, duration: 0.3)
                }
            }
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
                    self.averageRadius = 0
                }
                RadiusBarAnimator.animate(to: 0, duration: 0.3)
            }
        }
    }

    private func loadPostsForSpecificUser(_ uid: String) async {
        print("🔑 [ProfileView] Forcing load for specific uid: \(uid)")
        // Demo users: load from DemoPostStore
        let isDemoUser = uid.contains("_user_") || uid.hasPrefix("food_") || uid.hasPrefix("fitness_") || uid.hasPrefix("beauty_") || uid.hasPrefix("sports_") || uid.hasPrefix("modelling_") || uid.hasPrefix("fashion_") || uid.hasPrefix("music_") || uid.hasPrefix("tech_") || uid.hasPrefix("news_")
        if isDemoUser {
            let demoPosts = DemoPostStore.shared.posts(for: uid)
            let converted = demoPosts.map { feedPost in
                Post(id: feedPost.id, latitude: feedPost.latitude, longitude: feedPost.longitude, mediaURL: feedPost.mediaURL, radius: Int(feedPost.radius), viewCount: feedPost.viewCount, userID: feedPost.userID, posterURL: nil)
            }
            await MainActor.run {
                self.myPosts = converted
                self.hasLoadedOnce = true
                self.canLoadMore = false
                self.averageRadius = Double(self.averagePostRadius())
                self.isLoading = false
                self.refreshDailyNotificationsFromCurrentPosts()
            }
            Task.detached { await prefetchImages(for: converted) }
            return
        }

        // Cached posts first
        if let cached = loadPostsFromCache(for: uid), !cached.isEmpty {
            await MainActor.run {
                self.myPosts = cached
                self.hasLoadedOnce = true
                self.averageRadius = Double(self.averagePostRadius())
                self.refreshDailyNotificationsFromCurrentPosts()
            }
            Task.detached { await prefetchImages(for: cached) }
        } else {
            await MainActor.run {
                self.averageRadius = 0
            }
            RadiusBarAnimator.animate(to: 0, duration: 0.3)
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
            let page = try await fetchPostsPage(for: uid, after: nil, limit: pageSize)
            await MainActor.run {
                self.myPosts = page.posts
                self.lastDocument = page.lastDoc
                self.canLoadMore = page.posts.count >= pageSize && page.lastDoc != nil
                self.averageRadius = Double(self.averagePostRadius())
                self.hasLoadedOnce = true
                self.refreshDailyNotificationsFromCurrentPosts()
            }
            savePostsToCache(page.posts, for: uid)
            Task.detached { await prefetchImages(for: page.posts) }
            
            if page.posts.isEmpty {
                await MainActor.run {
                    self.averageRadius = 0
                    RadiusBarAnimator.animate(to: 0, duration: 0.3)
                }
            }
        } catch {
            print("Profile: forced load failed -> \(error.localizedDescription)")
            if let cached = loadPostsFromCache(for: uid), !cached.isEmpty {
                await MainActor.run {
                    self.myPosts = cached
                    self.loadedImages = [:]
                    self.hasLoadedOnce = true
                    self.canLoadMore = false
                    self.averageRadius = Double(self.averagePostRadius())
                    self.refreshDailyNotificationsFromCurrentPosts()
                }
                Task.detached { await prefetchImages(for: cached) }
            } else {
                await MainActor.run {
                    self.myPosts = []
                    self.loadedImages = [:]
                    self.hasLoadedOnce = true
                    self.canLoadMore = false
                    self.averageRadius = 0
                }
                RadiusBarAnimator.animate(to: 0, duration: 0.3)
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
        if let effective = effectiveUserID, !effective.isEmpty {
            targetUID = effective
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
        
        // Guard against empty userID
        guard !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("⚠️ [ProfileView] Empty userID provided, returning empty result")
            return PostsPage(posts: [], lastDoc: nil)
        }
        
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<PostsPage, Error>) in
            let db = Firestore.firestore()
            
            // Start with a simple query that should work for all posts
            var query: Query = db.collection("posts")
                .whereField("userID", isEqualTo: uid)
            
            print("🔎 [ProfileView] Executing Firestore query: posts where userID == '\(uid)'")
            
            // Try to order by createdAt if available, but don't require it
            if last == nil {
                // For the first page, try ordering by createdAt
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
                    var fallbackQuery: Query = db.collection("posts")
                        .whereField("userID", isEqualTo: uid)
                        .limit(to: limit)
                    
                    if let last = last {
                        fallbackQuery = fallbackQuery.start(afterDocument: last)
                    }
                    
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
                            print("💡 [ProfileView] Debug info:")
                            print("   - Make sure the post's userID field matches exactly: '\(uid)'")
                            print("   - Check Firestore console to verify field name (userID vs userId)")
                        } else {
                            print("✅ [ProfileView] Found \(snap2.documents.count) documents, mapping to Post objects...")
                            // Debug: Show first post's userID
                            if let firstDoc = snap2.documents.first {
                                let data = firstDoc.data()
                                let firstUserID = data["userID"] as? String ?? "missing"
                                print("   - First post userID: '\(firstUserID)'")
                                print("   - Searching for: '\(uid)'")
                                print("   - Match: \(firstUserID == uid)")
                            }
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
                    print("   - The userID value doesn't match what's stored ('\(uid)')")
                } else {
                    print("✅ [ProfileView] Found \(snap.documents.count) documents, mapping to Post objects...")
                    // Debug: Show first post's details
                    if let firstDoc = snap.documents.first {
                        let data = firstDoc.data()
                        print("   - Sample post ID: \(firstDoc.documentID)")
                        print("   - Sample userID: '\(data["userID"] as? String ?? "missing")'")
                        print("   - Has mediaURL: \(data["mediaURL"] != nil)")
                        print("   - Has coordinates: \(data["latitude"] != nil && data["longitude"] != nil)")
                    }
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
                            print("   - mediaURL: '\(data["mediaURL"] as? String ?? "missing")'")
                            print("   - latitude: \(data["latitude"] ?? "missing")")
                            print("   - longitude: \(data["longitude"] ?? "missing")")
                            print("   - radius: \(data["radius"] ?? "missing")")
                            print("   - userID: '\(data["userID"] as? String ?? "missing")'")
                            break // Only show first failure to avoid log spam
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

    private func refreshDailyNotificationsFromCurrentPosts() {
        guard isOwnProfile else { return }
        let signals = myPosts.map {
            PoplurNotificationPostSignal(
                id: $0.id,
                latitude: $0.latitude,
                longitude: $0.longitude,
                radius: $0.radius,
                viewCount: $0.viewCount
            )
        }
        Task {
            await notificationCenter.refreshDailyNotification(from: signals)
        }
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
        // Also delete the face recognition image
        let faceURL = faceRecognitionImageURL()
        if FileManager.default.fileExists(atPath: faceURL.path) {
            do { try FileManager.default.removeItem(at: faceURL) } catch {
                print("Failed to remove face recognition image: \(error.localizedDescription)")
            }
        }
        NotificationCenter.default.post(name: Notification.Name("ProfilePhotoUpdated"), object: nil)
    }
    
    // MARK: - Face Recognition ML Helpers
    
    /// Save face image for ML-based face recognition
    private func saveFaceForRecognition(image: UIImage) {
        let url = faceRecognitionImageURL()
        
        // Save full resolution image for better ML accuracy
        guard let data = image.jpegData(compressionQuality: 0.95) else {
            print("❌ Failed to convert face image to JPEG data")
            return
        }
        
        do {
            try data.write(to: url, options: .atomic)
            print("✅ Face image saved for ML recognition at: \(url.path)")
            
            // Notify the ML detection system that a new face is available
            NotificationCenter.default.post(
                name: Notification.Name("FaceImageUpdatedForML"),
                object: nil,
                userInfo: [
                    "imageURL": url,
                    "image": image,
                    "userID": Auth.auth().currentUser?.uid ?? ""
                ]
            )
        } catch {
            print("❌ Failed to save face recognition image: \(error.localizedDescription)")
        }
    }
    
    /// Get the file URL for the face recognition image
    private func faceRecognitionImageURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("face_recognition.jpg")
    }
    
    // Creates a quick demo post for the current user and emits PostCreated so the UI updates immediately.
    private func createDemoPostForCurrentUser() {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("⚠️ [ProfileView] Cannot create demo post: no current user")
            return
        }
        // Generate simple demo content
        let id = UUID().uuidString
        let latitude = 37.7749
        let longitude = -122.4194
        let mediaURL = "https://picsum.photos/seed/\(id)/800/800"
        let radius = 5000
        let viewCount = 0

        // Emit PostCreated so ProfileView inserts it immediately
        NotificationCenter.default.post(
            name: Notification.Name("PostCreated"),
            object: nil,
            userInfo: [
                "id": id,
                "userID": uid,
                "latitude": latitude,
                "longitude": longitude,
                "mediaURL": mediaURL,
                "radius": radius,
                "viewCount": viewCount
            ]
        )

        // Optionally persist a lightweight Firestore document if desired.
        // This is best-effort; the UI already updated via notification above.
        let db = Firestore.firestore()
        let doc: [String: Any] = [
            "userID": uid,
            "latitude": latitude,
            "longitude": longitude,
            "mediaURL": mediaURL,
            "radius": radius,
            "viewCount": viewCount,
            "createdAt": FieldValue.serverTimestamp()
        ]
        db.collection("posts").document(id).setData(doc) { err in
            if let err = err {
                print("❌ [ProfileView] Failed to persist demo post: \(err.localizedDescription)")
            } else {
                print("✅ [ProfileView] Demo post persisted with id=\(id)")
            }
        }
    }
}

private struct ProfileNotificationsView: View {
    let notifications: [ProfileNotificationItem]
    let onMarkRead: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Notifications")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.top, 24)

                ForEach(notifications) { item in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack(alignment: .topTrailing) {
                            Circle()
                                .fill(item.kind.color.opacity(0.14))
                                .frame(width: 48, height: 48)
                                .overlay {
                                    Image(systemName: item.kind.iconName)
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(item.kind.color)
                                }

                            if item.isUnchecked {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 10, height: 10)
                            }
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title)
                                .font(.system(size: 17, weight: .heavy, design: .rounded))
                                .foregroundColor(.black)
                            Text(item.detail)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black.opacity(0.58))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.045))
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color.white.ignoresSafeArea())
        .onAppear(perform: onMarkRead)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PoplurCreditCardProduct: Identifiable {
    let id: String
    let name: String
    let spriteSheetName: String
    let price: String
    let accent: Color
    let material: String
    let delivery: String

    static let catalog: [PoplurCreditCardProduct] = [
        PoplurCreditCardProduct(id: "cosmic-silver", name: "Cosmic Silver", spriteSheetName: "poplur_card_cosmic_silver_spritesheet", price: "$29", accent: Color(red: 0.56, green: 0.58, blue: 0.60), material: "star-polished graphite", delivery: "Ships in 3-5 days"),
        PoplurCreditCardProduct(id: "icy-aqua", name: "Icy Aqua", spriteSheetName: "poplur_card_icy_aqua_spritesheet", price: "$29", accent: Color(red: 0.05, green: 0.66, blue: 0.66), material: "turquoise crystal", delivery: "Ships in 3-5 days"),
        PoplurCreditCardProduct(id: "champagne-gold", name: "Champagne Gold", spriteSheetName: "poplur_card_champagne_gold_spritesheet", price: "$35", accent: Color(red: 0.86, green: 0.55, blue: 0.12), material: "gold glitter resin", delivery: "Ships in 2-4 days"),
        PoplurCreditCardProduct(id: "jet-black", name: "Jet Black Onyx", spriteSheetName: "poplur_card_jet_black_onyx_spritesheet", price: "$35", accent: Color(red: 0.06, green: 0.06, blue: 0.07), material: "black starfield", delivery: "Ships in 2-4 days"),
        PoplurCreditCardProduct(id: "amethyst", name: "Amethyst Purple", spriteSheetName: "poplur_card_amethyst_purple_spritesheet", price: "$39", accent: Color(red: 0.46, green: 0.14, blue: 0.76), material: "faceted crystal", delivery: "Limited finish"),
        PoplurCreditCardProduct(id: "ruby", name: "Ruby Red", spriteSheetName: "poplur_card_ruby_red_spritesheet", price: "$39", accent: Color(red: 0.72, green: 0.02, blue: 0.08), material: "ruby sparkle", delivery: "Limited finish"),
        PoplurCreditCardProduct(id: "emerald", name: "Emerald Green", spriteSheetName: "poplur_card_emerald_green_spritesheet", price: "$39", accent: Color(red: 0.0, green: 0.45, blue: 0.20), material: "emerald glitter", delivery: "Limited finish"),
        PoplurCreditCardProduct(id: "sapphire", name: "Sapphire Blue", spriteSheetName: "poplur_card_sapphire_blue_spritesheet", price: "$39", accent: Color(red: 0.03, green: 0.19, blue: 0.72), material: "sapphire crystal", delivery: "Limited finish")
    ]
}

private final class PoplurCreditCardSpriteScene: SKScene {
    private let sheetName: String
    private let cardSize = CGSize(width: 482, height: 320)
    private var cardNode: SKSpriteNode?

    init(sheetName: String) {
        self.sheetName = sheetName
        super.init(size: cardSize)
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        view.backgroundColor = .clear
        buildSprite()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutSprite()
    }

    private func buildSprite() {
        guard cardNode == nil else { return }

        let node = SKSpriteNode(texture: makeFirstTexture())
        node.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        addChild(node)
        cardNode = node
        layoutSprite()
    }

    private func makeFirstTexture() -> SKTexture {
        let sheet = SKTexture(imageNamed: sheetName)
        let sheetSize = CGSize(width: 1122, height: 1402)
        let origin = CGPoint(x: 62, y: 54)
        let rect = CGRect(
            x: origin.x / sheetSize.width,
            y: (sheetSize.height - origin.y - cardSize.height) / sheetSize.height,
            width: cardSize.width / sheetSize.width,
            height: cardSize.height / sheetSize.height
        )
        let texture = SKTexture(rect: rect, in: sheet)
        texture.filteringMode = .linear
        return texture
    }

    private func layoutSprite() {
        guard let cardNode else { return }
        cardNode.position = CGPoint(x: size.width / 2, y: size.height / 2)

        let aspect = cardSize.width / cardSize.height
        var width = size.width
        var height = width / aspect
        if height > size.height {
            height = size.height
            width = height * aspect
        }
        cardNode.size = CGSize(width: width, height: height)
    }
}

private struct PoplurCreditCardSpriteView: View {
    let card: PoplurCreditCardProduct

    var body: some View {
        SpriteView(
            scene: PoplurCreditCardSpriteScene(sheetName: card.spriteSheetName),
            options: [.allowsTransparency]
        )
        .id(card.id)
        .aspectRatio(482.0 / 320.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct RadiusStoreView: View {
    @Binding var purchasedRadiusMeters: Int
    let userID: String?
    @ObservedObject var purchaseVM: RadiusPurchaseViewModel
    @State private var selectedCardID = PoplurCreditCardProduct.catalog[0].id
    @State private var orderMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var selectedCard: PoplurCreditCardProduct {
        PoplurCreditCardProduct.catalog.first { $0.id == selectedCardID } ?? PoplurCreditCardProduct.catalog[0]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                storeHeader
                    .padding(.top, 24)

                featuredCard

                finishPicker

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(PoplurCreditCardProduct.catalog) { card in
                        creditCardTile(card)
                    }
                }

                checkoutSummary

                radiusAddOns
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await purchaseVM.loadProducts()
            let delivered = await purchaseVM.finishUndeliveredRadiusPurchases(userID: userID)
            if delivered > 0 {
                purchasedRadiusMeters += delivered
            }
        }
    }

    private var storeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Poplur Store")
                    .font(.system(size: 31, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)

                Spacer()

                Image(systemName: "bag.fill")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color.black, in: Circle())
            }

            Text("Shop World Service cards, collectible finishes, and radius boosts.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.black.opacity(0.58))
        }
    }

    private var featuredCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            PoplurCreditCardSpriteView(card: selectedCard)
                .shadow(color: selectedCard.accent.opacity(0.28), radius: 22, x: 0, y: 12)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(selectedCard.name)
                        .font(.system(size: 23, weight: .heavy, design: .rounded))
                        .foregroundColor(.black)

                    Text("Poplur World Service members card in \(selectedCard.material).")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(selectedCard.price)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
            }

            HStack(spacing: 10) {
                storeBadge("Contactless")
                storeBadge("Numbered")
                storeBadge(selectedCard.delivery)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.045))
        )
    }

    private var finishPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a finish")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.black)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PoplurCreditCardProduct.catalog) { card in
                        Button {
                            selectedCardID = card.id
                        } label: {
                            VStack(spacing: 7) {
                                Circle()
                                    .fill(card.accent)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        if selectedCardID == card.id {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .heavy))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .overlay(
                                        Circle()
                                            .stroke(selectedCardID == card.id ? Color.black : Color.clear, lineWidth: 3)
                                            .padding(-4)
                                    )

                                Text(card.name.components(separatedBy: " ").first ?? card.name)
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundColor(.black)
                            }
                            .frame(width: 72)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func creditCardTile(_ card: PoplurCreditCardProduct) -> some View {
        Button {
            selectedCardID = card.id
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                PoplurCreditCardSpriteView(card: card)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(card.name)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text(card.price)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.black)
                    Spacer()
                    Image(systemName: selectedCardID == card.id ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundColor(selectedCardID == card.id ? card.accent : .black.opacity(0.72))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(selectedCardID == card.id ? 0.075 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(selectedCardID == card.id ? card.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var checkoutSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Order summary")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.black)
                    Text("1 Poplur card - \(selectedCard.name)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black.opacity(0.58))
                }

                Spacer()

                Text(selectedCard.price)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
            }

            Divider()

            HStack {
                Text("Estimated shipping")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black.opacity(0.58))
                Spacer()
                Text("Free")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.green)
            }

            Button {
                orderMessage = "\(selectedCard.name) card is ready for checkout."
            } label: {
                HStack {
                    Image(systemName: "creditcard.fill")
                    Text("Buy \(selectedCard.name)")
                }
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            if let orderMessage {
                Text(orderMessage)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundColor(selectedCard.accent)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.045))
        )
    }

    private var radiusAddOns: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Add radius")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
                Spacer()
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundColor(.green)
            }

            Text("Boost your Poplur reach after choosing a card.")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black.opacity(0.58))

                if purchasedRadiusMeters > 0 {
                    Text("Purchased radius: \(formattedRadius(purchasedRadiusMeters))")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundColor(.green)
                        .padding(.vertical, 8)
                }

                if let message = purchaseVM.message {
                    Text(message)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(message.localizedCaseInsensitiveContains("failed") || message.localizedCaseInsensitiveContains("not") ? .red : .green)
                        .padding(.vertical, 6)
                }

                ForEach(RadiusPurchasePackage.allCases) { package in
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color.green.opacity(0.14))
                            .frame(width: 48, height: 48)
                            .overlay {
                                Image(systemName: "dollarsign")
                                    .font(.system(size: 21, weight: .heavy))
                                    .foregroundColor(.green)
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(package.title)
                                .font(.system(size: 17, weight: .heavy, design: .rounded))
                                .foregroundColor(.black)
                            Text("+\(formattedRadius(package.radiusMeters))")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black.opacity(0.58))
                        }

                        Spacer()

                        Button {
                            Task {
                                if let purchased = await purchaseVM.buyRadius(package, userID: userID) {
                                    purchasedRadiusMeters += purchased
                                }
                            }
                        } label: {
                            Group {
                                if purchaseVM.isPurchasing(package) {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text(purchaseVM.displayPrice(for: package))
                                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                                }
                            }
                            .foregroundColor(.white)
                            .frame(minWidth: 64, minHeight: 38)
                            .padding(.horizontal, 12)
                            .background(purchaseVM.productsByID[package.productID] == nil ? Color.gray : Color.black, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(purchaseVM.isPurchasing(package) || purchaseVM.productsByID[package.productID] == nil)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.black.opacity(0.045))
                    )
                }
        }
    }

    private func storeBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundColor(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.88), in: Capsule())
    }

    private func formattedRadius(_ meters: Int) -> String {
        if meters >= 1000 {
            return "\(meters / 1000) km"
        }
        return "\(meters) m"
    }
}

// Grid and list tiles unchanged…
private struct ProfileGridTile: View {
    let post: Post
    let preloadedImage: UIImage?
    private let corner: CGFloat = 18

    var body: some View {
        ZStack {
            if let preloadedImage {
                Image(uiImage: preloadedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.16),
                                Color.black.opacity(0.30)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: post.mediaURL.lowercased().contains(".mp4") ? "play.fill" : "photo")
                                .font(.system(size: 22, weight: .bold))
                            ProgressView()
                                .controlSize(.small)
                        }
                        .foregroundStyle(.white.opacity(0.78))
                    }
            }
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
