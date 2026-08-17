import SwiftUI
import UIKit
import FirebaseAuth
@preconcurrency import FirebaseFirestore
import UserNotifications
import ARKit

// ProfileView listens for:
// - OpenUserDetailForUser: ["userID": String, "currentPostID": String] to show a specific user's profile
// - LastTappedUserChanged: ["userID": String, "radius": Double, "currentPostID": String] to reflect current feed context (radius bar)
// - PostCreated: ["id": String, "userID": String, "latitude": Double, "longitude": Double, "mediaURL": String, "radius": Double, "viewCount": Int] to insert newly published posts immediately
// Long-press on a post will emit OpenCameraAtCoordinate with both coordinate and lat/lon for map navigation.

private func animateRadius(to meters: Double, duration: Double) {
    NotificationCenter.default.post(
        name: .animateRadiusBarToValue,
        object: nil,
        userInfo: ["radius": meters, "duration": duration]
    )
}

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
        case .engagement:
            // A like or comment on your post — the heart is literally what this
            // row means, where the other three borrow it.
            self = .like
        }
    }
}

private struct HeyPoplurProfileTutorialView: View {
    let accent: Color
    let onDismiss: () -> Void

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Text("Say \"Hey Poplur\"")
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("The edges light up in your theme color. Then tell Poplur what to do.")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)

                Button(action: onDismiss) {
                    Text("Got it")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            .frame(maxWidth: 330)
            .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(accent.opacity(0.9), lineWidth: 1.5)
            )
            .shadow(color: accent.opacity(0.62), radius: 22)
            .padding(.horizontal, 24)
            .padding(.bottom, 146)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ProfileView: View {
    @Environment(\.layoutPreviewMode) private var layoutPreviewMode
    @EnvironmentObject private var auth: AuthViewModel
    @ObservedObject private var cubeSkinStore = CubeSkinStore.shared
    @ObservedObject private var profileThemeStore = ProfileThemeStore.shared
    @GestureState private var isInteractingWithCube: Bool = false
    @State private var isScrollDisabled = false
    
    // Injected userID from tab bar when navigating from feed
    @Environment(\.routedUserID) private var routedUserID
    
    // Track if we're viewing own profile or another user's
    private var myPostsTotalRadiusKM: Double {
        Double(evictedPostRadius + myPosts.reduce(0) { $0 + $1.radius }) / 1000.0
    }

    private var profileTotalRadiusMeters: Int {
        evictedPostRadius + myPosts.reduce(0) { $0 + $1.radius }
    }

    private var loadedPostCount: Int { evictedPostCount + myPosts.count }

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

    @AppStorage("poplur_profileAvatarIs3D") private var profileAvatarIs3D = true
    @AppStorage("poplur_profileAvatarModeInitialized.v1") private var profileAvatarModeInitialized = false
    @AppStorage("poplur.profile.heyPoplurTutorialSeen.v1") private var hasSeenHeyPoplurProfileTutorial = false
    @State private var showHeyPoplurProfileTutorial = false
    @State private var myPosts: [Post] = []
    // Preview-only images. Production tiles load lazily through the global,
    // byte-bounded ImageCache instead of retaining every decoded profile image.
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var evictedPostRadius = 0
    @State private var evictedPostCount = 0
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @State private var expandedPost: Post? = nil
    @State private var profileImage: UIImage? = nil
    @State private var profileImageURL: URL? = nil
    @State private var showSettings = false
    @State private var navigateToMessages = false
    @State private var showPopularPhone = false
    @State private var showNotifications = false
    @State private var showNotificationBanner = false
    @State private var showStats = false
    @State private var showCreatorDashboard = false
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
    @StateObject private var headCycler = ProfileHeadCycler()

    @State private var isLoadingMore = false
    @State private var canLoadMore = true
    @State private var lastDocument: QueryDocumentSnapshot? = nil
    private let pageSize = 18
    private static let maximumRetainedPostCount = 108
    private static let maximumProfileCacheFileCount = 12
    private static let maximumProfileCacheFileBytes = 2_000_000

    private enum ProfileSubmenuRoute {
        case mail
        case settings
        case notifications
        case phone
        case store
        case stats
        case creator
    }

    private var isShowingMainTabChildRoute: Bool {
        showSettings || navigateToMessages || showNotifications || showRadiusStore || showStats || navigateToScanner || navigateToViewer || showCreatorDashboard
    }

    @ViewBuilder
    private var profileStatsOverlay: some View {
        if showStats {
            ProfileStatsView(userID: effectiveUserID ?? Auth.auth().currentUser?.uid ?? "")
                .transition(.opacity)
                .zIndex(50)
        }
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
        } else if showStats {
            postProfileCubeIconOverride(forSubmenuID: "stats")
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
        showStats = route == .stats
        showCreatorDashboard = route == .creator

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
        showStats = false
        navigateToScanner = false
        navigateToViewer = false
        showCreatorDashboard = false
    }

    private var cubeSubmenuItems: [CubeSubmenuItem] {
        [
            CubeSubmenuItem(id: "mail",     icon: HoldMenuIcons.mail)     { openProfileSubmenuRoute(.mail) },
            CubeSubmenuItem(id: "settings", icon: HoldMenuIcons.settings) { openProfileSubmenuRoute(.settings) },
            CubeSubmenuItem(id: "stats",    icon: HoldMenuIcons.stats)    { openProfileSubmenuRoute(.stats) },
            CubeSubmenuItem(id: "phone",    icon: HoldMenuIcons.phone)    { openProfileSubmenuRoute(.phone) },
            CubeSubmenuItem(id: "store",    icon: HoldMenuIcons.store)    { openProfileSubmenuRoute(.store) },
            CubeSubmenuItem(id: "creator",  icon: HoldMenuIcons.credits)  { openProfileSubmenuRoute(.creator) }
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
                    getProfilePictureURL: { profile.profilePictureURL },
                    getAccountType: { profile.accountType },
                    getBusinessProfile: { profile.businessProfile },
                    setBusinessProfile: { _ in } // Will be handled in the setter
                )
            },
            set: { newValue in
                if let newValue = newValue, var profile = userProfile {
                    profile.username = newValue.username
                    profile.email = newValue.email
                    profile.businessProfile = newValue.businessProfile
                    userProfile = profile
                }
            }
        )
    }

    enum DisplayMode: String, CaseIterable, Identifiable {
        case media
        case messages
        case saved
        var id: String { rawValue }
    }
    @State private var mode: DisplayMode = .media
    @State private var radiusSortOrder: PoplurAIProfileSortOrder?

    private var displayedPosts: [Post] {
        switch radiusSortOrder {
        case .mostRadius:
            return myPosts.sorted { $0.radius > $1.radius }
        case .leastRadius:
            return myPosts.sorted { $0.radius < $1.radius }
        case nil:
            return myPosts
        }
    }

    private let tileSpacing: CGFloat = 10
    private let profileGridMaxWidth: CGFloat = 520
    private let profileGridHorizontalPadding: CGFloat = 18

    private var skinTheme: CubeSkinAppTheme {
        cubeSkinStore.current.appTheme
    }

    private var profileTheme: ProfileTheme {
        profileThemeStore.selectedTheme
    }

    private var profileForeground: Color {
        profileTheme == .default ? .black : profileTheme.foreground
    }

    private var profileAccent: Color {
        profileTheme == .default ? skinTheme.accent : profileTheme.primaryAccent
    }

    private var profileTextShadow: Color {
        guard profileTheme != .default else { return .clear }
        switch profileTheme.statusBarAppearance {
        case .darkContent: return .white.opacity(0.34)
        case .lightContent: return .black.opacity(0.58)
        case .inherited: return .clear
        }
    }

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
        let posterURL: String?
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
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = attributes[.size] as? NSNumber,
               fileSize.intValue > Self.maximumProfileCacheFileBytes {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            let data = try Data(contentsOf: url)
            let cached = try JSONDecoder().decode([CachedPost].self, from: data)
            return cached.prefix(Self.maximumRetainedPostCount).map {
                Post(id: $0.id, latitude: $0.latitude, longitude: $0.longitude, mediaURL: $0.mediaURL, radius: $0.radius, viewCount: $0.viewCount, userID: $0.userID, posterURL: $0.posterURL)
            }
        } catch {
            print("Profile cache: failed to read -> \(error.localizedDescription)")
            return nil
        }
    }

    private func savePostsToCache(_ posts: [Post], for uid: String) {
        let url = cacheFileURL(for: uid)
        let toCache = posts.prefix(Self.maximumRetainedPostCount).map {
            CachedPost(id: $0.id, latitude: $0.latitude, longitude: $0.longitude, mediaURL: $0.mediaURL, posterURL: $0.posterURL, radius: $0.radius, viewCount: $0.viewCount, userID: $0.userID)
        }
        do {
            let data = try JSONEncoder().encode(toCache)
            try data.write(to: url, options: .atomic)
            pruneProfilePostCacheFiles()
        } catch {
            print("Profile cache: failed to write -> \(error.localizedDescription)")
        }
    }

    private func pruneProfilePostCacheFiles() {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return }

        let cacheFiles = urls.filter {
            $0.lastPathComponent.hasPrefix("profile_posts_") && $0.pathExtension == "json"
        }.sorted {
            let lhs = (try? $0.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            let rhs = (try? $1.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            if lhs != rhs { return lhs > rhs }
            return $0.lastPathComponent < $1.lastPathComponent
        }

        for staleURL in cacheFiles.dropFirst(Self.maximumProfileCacheFileCount) {
            try? FileManager.default.removeItem(at: staleURL)
        }
    }

    @ViewBuilder
    private var profileImagePickerSheet: some View {
        ImagePickerView(
            selectedImage: profileImageSelectionBinding,
            selectedVideoURL: .constant(nil)
        )
    }

    private var profileImageSelectionBinding: Binding<UIImage?> {
        Binding(
            get: { profileImage },
            set: { handleSelectedProfileImage($0) }
        )
    }

    private func handleSelectedProfileImage(_ newImage: UIImage?) {
        guard let image = newImage else { return }
        profileImage = image
        if let url = try? saveProfileImage(image) {
            profileImageURL = url
            saveFaceForRecognition(image: image)
        }
        NotificationCenter.default.post(name: Notification.Name("ProfilePhotoUpdated"), object: image)
    }

    private func handleHeadScannerResult(_ result: Swift.Result<HSOutput, HSError>) {
        switch result {
        case .success(let output):
            if let image = output.previewImage {
                handleSelectedProfileImage(image)
            }
            lastHeadModelURL = output.usdzURL
            if output.usdzURL != nil {
                navigateToViewer = true
            }
        case .failure:
            break
        }
    }

    private var profileMainStack: some View {
        VStack(spacing: 0) {
            profileHeader
            profileScrollableContent
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                avatarRow
                usernameRow
                businessIdentityRow

            }
            .padding(.top, 12)
            .padding(.bottom, 12)

            modeSwitcher
        }
    }

    private var profileTopAppBar: some View {
        HStack {
            // Small profile avatar top-left
            Button {
                showProfilePhotoOptions = true
            } label: {
                ZStack {
                    if let img = profileImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Color.accent)
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(Circle())
                .overlay(Circle().stroke(DS.Color.accent, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .opacity(isOwnProfile ? 1 : 0)

            Spacer()

            Text("Poplur")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundColor(DS.Color.textPrimary)

            Spacer()

            // Notification bell
            Button {
                if showNotificationBanner {
                    dismissNotificationBanner()
                } else {
                    presentNotificationBanner()
                }
            } label: {
                ZStack(alignment: .topTrailing) {
                    Text("🔔")
                        .font(.system(size: 22))
                        .shadow(color: .black.opacity(0.55), radius: 0, x: 1.5, y: 2.5)
                        .shadow(color: .black.opacity(0.25), radius: 3, x: 2, y: 4)
                    if hasUncheckedNotifications {
                        Circle()
                            .fill(DS.Color.accent)
                            .frame(width: 10, height: 10)
                            .offset(x: 3, y: -2)
                    }
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
    }

    private var profileQuickActions: some View {
        HStack(spacing: 12) {
            PoplurQuickActionCard(
                icon: "star.fill",
                label: "My Posts",
                iconColor: .orange,
                iconBg: Color(red: 1.0, green: 0.94, blue: 0.88)
            ) {
                mode = .media
            }
            PoplurQuickActionCard(
                icon: "bookmark.fill",
                label: "Saved",
                iconColor: Color(red: 0.95, green: 0.26, blue: 0.35),
                iconBg: Color(red: 1.0, green: 0.90, blue: 0.92)
            ) { }
            PoplurQuickActionCard(
                icon: "bubble.left.fill",
                label: "Messages",
                iconColor: Color(red: 0.18, green: 0.55, blue: 0.96),
                iconBg: Color(red: 0.88, green: 0.94, blue: 1.0)
            ) {
                openProfileSubmenuRoute(.mail)
            }
            PoplurQuickActionCard(
                icon: "gift.fill",
                label: "Gifts",
                iconColor: Color(red: 0.55, green: 0.28, blue: 0.92),
                iconBg: Color(red: 0.94, green: 0.88, blue: 1.0),
                isHighlighted: false
            ) {
                openProfileSubmenuRoute(.store)
            }
        }
    }

    private var profileScrollableContent: some View {
        ScrollViewReader { proxy in
            profileScrollStateContent
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ResetTabToTop"))) { _ in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
        }
    }

    @ViewBuilder
    private var profileScrollStateContent: some View {
        if isLoading || !hasLoadedOnce {
            loadingPostsView
        } else if myPosts.isEmpty {
            emptyPostsView
        } else {
            profileLoadedContent
        }
    }

    private var loadingPostsView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading posts")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(profileTheme == .default ? .black.opacity(0.58) : profileForeground.opacity(0.82))
                .poplurTextShader(intensity: 0.58)
                .shadow(color: profileTextShadow, radius: 3, x: 0, y: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id("top")
    }

    private var emptyPostsView: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.stack.3d.up.slash")
                .poplurIconShader()
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(profileTheme == .default ? .black.opacity(0.55) : profileForeground.opacity(0.78))
            Text("No posts yet.")
                .foregroundColor(profileTheme == .default ? .black.opacity(0.58) : profileForeground.opacity(0.82))
                .poplurTextShader(intensity: 0.58)
                .shadow(color: profileTextShadow, radius: 3, x: 0, y: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id("top")
    }

    @ViewBuilder
    private var profileLoadedContent: some View {
        switch mode {
        case .media:
            mediaPostsScroll
        case .messages:
            messagesScroll
        case .saved:
            savedPostsScroll
        }
    }

    private var mediaPostsScroll: some View {
        GeometryReader { proxy in
            let availableWidth = max(1, proxy.size.width - profileGridHorizontalPadding * 2)
            let gridWidth = min(availableWidth, profileGridMaxWidth)
            let tileSize = max(1, floor((gridWidth - tileSpacing * 2) / 3))
            let resolvedGridWidth = tileSize * 3 + tileSpacing * 2
            let columns = Array(
                repeating: GridItem(.fixed(tileSize), spacing: tileSpacing),
                count: 3
            )

            ScrollView {
                VStack(spacing: 0) {
                    PoplurRefreshHeader().frame(height: 0)
                    Color.clear.frame(height: 0).id("top")
                    LazyVGrid(columns: columns, spacing: tileSpacing) {
                        ForEach(displayedPosts) { post in
                            profileGridTileView(post: post, tileSize: tileSize)
                        }
                        Color.clear.frame(height: 1).onAppear {
                            loadMoreIfNeeded(currentItem: displayedPosts.last)
                        }
                    }
                    .frame(width: resolvedGridWidth)
                    .frame(maxWidth: .infinity)
                    if isLoadingMore {
                        ProgressView().padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, profileGridHorizontalPadding)
                .padding(.top, 8)
                .padding(.bottom, 260)
            }
            .scrollDisabled(isScrollDisabled)
            .refreshable {
                await loadMyPosts()
            }
        }
    }

    private func profileGridTileView(post: Post, tileSize: CGFloat) -> some View {
        ProfileGridTile(
            post: post,
            preloadedImage: loadedImages[post.id]
        )
        .frame(width: tileSize, height: tileSize)
        .onTapGesture {
            expandPost(post)
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            handlePostLongPress(post)
        }
    }

    private var messagesScroll: some View {
        ScrollView {
            VStack(spacing: 0) {
                PoplurRefreshHeader().frame(height: 0)
                Color.clear.frame(height: 0).id("top")
                VStack(spacing: 18) {
                    VStack(spacing: 12) {
                        Image(systemName: "message.fill")
                            .poplurIconShader()
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundColor(skinTheme.secondaryText)
                        Text("Messages")
                            .font(.headline)
                            .foregroundColor(profileForeground)
                            .poplurTextShader(intensity: 0.78)
                            .shadow(color: profileTextShadow, radius: 3, x: 0, y: 1)
                        Text("Your uploaded messages will appear here")
                            .font(.subheadline)
                            .foregroundColor(profileTheme == .default ? .black.opacity(0.58) : profileForeground.opacity(0.82))
                            .poplurTextShader(intensity: 0.52)
                            .shadow(color: profileTextShadow, radius: 3, x: 0, y: 1)
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

    private var savedPostsScroll: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear.frame(height: 0).id("top")
                VStack(spacing: 18) {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark.fill")
                            .poplurIconShader()
                            .font(.system(size: 48, weight: .semibold))
                            .foregroundColor(skinTheme.secondaryText)
                        Text("Saved")
                            .font(.headline)
                            .foregroundColor(profileForeground)
                            .poplurTextShader(intensity: 0.78)
                            .shadow(color: profileTextShadow, radius: 3, x: 0, y: 1)
                        Text("Posts you save will appear here")
                            .font(.subheadline)
                            .foregroundColor(profileTheme == .default ? .black.opacity(0.58) : profileForeground.opacity(0.82))
                            .poplurTextShader(intensity: 0.52)
                            .shadow(color: profileTextShadow, radius: 3, x: 0, y: 1)
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
    }

    @ViewBuilder
    private var expandedPostOverlay: some View {
        if let post = expandedPost {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .transition(.opacity)

                FeedFullscreenPage(
                    post: feedPost(from: post),
                    displayName: "",
                    onUserTapped: { _ in }
                )
                .transition(.scale.combined(with: .opacity))
                .onAppear {
                    handleExpandedPostAppear(post)
                }
                .onDisappear {
                    NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
                }
                .overlay(alignment: .topLeading) {
                    expandedPostDeleteButton
                }
                .overlay(alignment: .bottomLeading) {
                    expandedPostRadiusBadge(post)
                }
            }
            .zIndex(10)
        }
    }

    @ViewBuilder
    private var expandedPostDeleteButton: some View {
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

    private func expandedPostRadiusBadge(_ post: Post) -> some View {
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

    @ViewBuilder
    private var profileTransientOverlays: some View {
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

        profilePhotoOptionsOverlay

        if showHeyPoplurProfileTutorial {
            HeyPoplurProfileTutorialView(
                accent: cubeSkinStore.current.appTheme.accent,
                onDismiss: dismissHeyPoplurProfileTutorial
            )
            .transition(.scale(scale: 0.96).combined(with: .opacity))
            .zIndex(60)
        }
    }

    @ViewBuilder
    private var profilePhotoOptionsOverlay: some View {
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
    }

    @ViewBuilder
    private var profileRouteOverlays: some View {
        if showSettings {
            AppSettingsView()
                .transition(.opacity)
                .zIndex(50)
        }

        profileStatsOverlay

        if navigateToMessages {
            MessagesRootView()
                .transition(.opacity)
                .zIndex(51)
        }

        if showNotificationBanner {
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissNotificationBanner()
                }
                .zIndex(9_999)

            VStack {
                ProfileNotificationBanner(notifications: profileNotifications)
                    .transition(
                        .asymmetric(
                            insertion: .offset(y: -520).combined(with: .opacity),
                            removal: .offset(y: -520).combined(with: .opacity)
                        )
                    )
                    .zIndex(10_000)
                Spacer()
            }
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .zIndex(10_000)
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
            HeadScannerView(onComplete: handleHeadScannerResult)
                .transition(.opacity)
                .zIndex(54)
        }

        if navigateToViewer {
            profileViewerOverlay
        }

        if showCreatorDashboard {
            ZStack(alignment: .topLeading) {
                PoplurAICreateView()

                Button {
                    showCreatorDashboard = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.45), in: Circle())
                }
                .padding(.leading, 18)
                .padding(.top, 56)
            }
            .transition(.opacity)
            .zIndex(56)
        }
    }

    @ViewBuilder
    private var profileViewerOverlay: some View {
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

    private func feedPost(from post: Post) -> FeedPost {
        FeedPost(
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
        )
    }

    private func expandPost(_ post: Post) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            expandedPost = post
            NotificationCenter.default.post(
                name: Notification.Name("currentPostRadiusDidChange"),
                object: nil,
                userInfo: ["radius": Double(post.radius)]
            )
        }
    }

    private func handleExpandedPostAppear(_ post: Post) {
        NotificationCenter.default.post(
            name: Notification.Name("currentPostRadiusDidChange"),
            object: nil,
            userInfo: ["radius": Double(post.radius)]
        )
        NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
    }

    private func handlePostLongPress(_ post: Post) {
        let coordinate = CLLocationCoordinate2D(latitude: post.latitude, longitude: post.longitude)
        let latitude = coordinate.latitude
        let longitude = coordinate.longitude
        let postRadius = post.radius
        print("📍 [ProfileView Grid] Long press - showing post location: \(latitude), \(longitude)")
        print("   Post radius: \(postRadius)m")

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let profileURL: String? = post.posterURL ?? userProfile?.profilePictureURL?.absoluteString

        print("📍 [ProfileView Grid] Setting pending post location in MapStateManager")
        MapStateManager.shared.setPendingPostLocation(
            coordinate,
            userID: post.userID,
            username: displayUsername,
            profileImageURL: profileURL,
            radius: Double(post.radius)
        )

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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(
                name: Notification.Name("SwitchToMapTab"),
                object: nil
            )
        }
    }

    var body: some View {
        profileScene
#if DEBUG
            .overlay(alignment: .top) {
                if UITestHooks.isEnabled {
                    VStack(spacing: 2) {
                        UITestScreenMarker(name: "Profile")
                        UITestActionStrip(prefix: "UITestWheel", submenuItems: cubeSubmenuItems)
                    }
                }
            }
#endif
    }

    private var profileRootScene: some View {
        ZStack {
            profileBackground

            profileMainStack
                .zIndex(1)

            expandedPostOverlay
            profileTransientOverlays
            profileRouteOverlays
                .zIndex(showNotificationBanner ? 10_000 : 0)
        }
    }

    @ViewBuilder
    private var profileBackground: some View {
        if profileTheme == .default {
            // Preserve the existing default profile background exactly.
            DS.Color.background.ignoresSafeArea()
            PoplurSparkleBackground().ignoresSafeArea()
        } else if let assetName = profileTheme.backgroundAssetName,
                  UIImage(named: assetName) != nil {
            GeometryReader { proxy in
                Image(assetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            profileTheme.overlayColor
                .opacity(profileTheme.overlayOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else {
            // Defensive fallback if an asset is removed from the bundle.
            DS.Color.background.ignoresSafeArea()
            PoplurSparkleBackground().ignoresSafeArea()
        }
    }

    private func presentNotificationBanner() {
        withAnimation(.spring(duration: 1.06, bounce: 0.62)) {
            showNotificationBanner = true
            hasUncheckedNotifications = false
            notificationCenter.markAllRead()
        }
    }

    private func dismissNotificationBanner() {
        withAnimation(.spring(duration: 0.84, bounce: 0.34)) {
            showNotificationBanner = false
        }
    }

    private var profileSheetScene: AnyView {
        AnyView(
            profileRootScene
                .sheet(isPresented: $showImagePicker) {
                    profileImagePickerSheet
                }
        )
    }

    private var profileLifecycleScene: AnyView {
        AnyView(
            profileSheetScene
                .task { await runInitialProfileTask() }
                .onAppear(perform: handleProfileAppear)
                .task(id: isHoldingCube) { await updateCubeHoldProgress() }
                .onDisappear(perform: handleProfileDisappear)
        )
    }

    private var profileNotificationScene: AnyView {
        AnyView(
            profileLifecycleScene
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ProfileRemovePost")), perform: handleProfileRemovePost)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenUserDetailForUser")), perform: handleOpenUserDetailForUser)
                .onReceive(NotificationCenter.default.publisher(for: .OpenSettingsRequested), perform: handleOpenSettingsRequested)
                .onReceive(NotificationCenter.default.publisher(for: .OpenDMsRequested), perform: handleOpenDMsRequested)
                .onReceive(NotificationCenter.default.publisher(for: .OpenPoplurStoreRequested), perform: handleOpenStoreRequested)
                .onReceive(NotificationCenter.default.publisher(for: .OpenCreatorRequested), perform: handleOpenCreatorRequested)
                .onReceive(NotificationCenter.default.publisher(for: .PoplurAIShowAnalytics), perform: handlePoplurAIShowAnalytics)
                .onReceive(NotificationCenter.default.publisher(for: .PoplurAIProfileSortRequested), perform: handlePoplurAIProfileSortRequested)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LastTappedUserChanged")), perform: handleLastTappedUserChanged)
        )
    }

    private var profilePostNotificationScene: AnyView {
        AnyView(
            profileNotificationScene
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ProfileShowUserContext")), perform: handleProfileShowUserContext)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RefreshProfileAfterUpload")), perform: handleRefreshProfileAfterUpload)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PostCreated")), perform: handlePostCreated)
                .onReceive(NotificationCenter.default.publisher(for: .cubeHoldBegan), perform: handleCubeHoldBegan)
                .onReceive(NotificationCenter.default.publisher(for: .cubeHoldMoved), perform: handleCubeHoldMoved)
                .onReceive(NotificationCenter.default.publisher(for: .cubeHoldEnded), perform: handleCubeHoldEnded)
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RecordTabBecameActive")), perform: handleRecordTabBecameActive)
                .onReceive(NotificationCenter.default.publisher(for: .CubeGlobalTap), perform: handleCubeGlobalTap)
                .onReceive(NotificationCenter.default.publisher(for: .CubeGoBack)) { _ in
                    if isShowingMainTabChildRoute {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            closeProfileSubroutes()
                        }
                    }
                }
        )
    }

    private var profileScene: AnyView {
        AnyView(
            profilePostNotificationScene
                .onChange(of: cubeMenuWheel.selectedIndex) { _, _ in handleCubeSelectedIndexChanged() }
                .onChange(of: showSettings) { _, _ in handleProfileChildRouteChanged() }
                .onChange(of: showStats) { _, _ in handleProfileChildRouteChanged() }
                .onChange(of: navigateToMessages) { _, _ in handleProfileChildRouteChanged() }
                .onChange(of: showNotifications) { _, _ in handleProfileChildRouteChanged() }
                .onChange(of: showRadiusStore) { _, _ in handleProfileChildRouteChanged() }
                .onChange(of: showCreatorDashboard) { _, _ in handleProfileChildRouteChanged() }
                .onChange(of: showPopularPhone) { _, _ in syncProfileCubeIconToActiveRoute() }
                .onChange(of: navigateToScanner) { _, _ in handleProfileChildRouteChanged() }
                .onChange(of: navigateToViewer) { _, _ in postMainTabChildRouteVisibility() }
                .onChange(of: routedUserID) { _, newUserID in handleRoutedUserIDChanged(newUserID) }
                .preferredColorScheme(profileTheme.preferredColorScheme)
                .toolbar(.hidden, for: .navigationBar)
                .id(viewID)
        )
    }

    private func runInitialProfileTask() async {
        if !isRunningInPreviews {
            print("📊 [ProfileView] Initial .task running for userID: \(userID ?? "nil")")
            // NO bare requestAuthorization here. Opening Profile used to raise
            // Apple's notification sheet cold, with no Poplur card in front of
            // it — the one "outside" alert left in the app. The ask now belongs
            // to the clay permission card in HomeTwin.tsx, which fires the
            // system sheet through PoplurPermissionRouting only after Allow.
            if let uid = effectiveUserID {
                await loadUserProfile(for: uid)
            }
            await loadMyPosts()
            await MainActor.run {
                self.averageRadius = Double(self.averagePostRadius())
                self.hasLoadedOnce = true

                if self.averageRadius > 0 {
                    print("📊 [ProfileView] Posts loaded, animating radius bar to total: \(self.averageRadius)m")
                    animateRadius(to: self.averageRadius, duration: 1.2)
                } else {
                    print("📊 [ProfileView] No posts loaded, radius stays at 0")
                }
                self.refreshDailyNotificationsFromCurrentPosts()
            }

            if isOwnProfile {
                await loadPersistedProfileImageIfNeeded()
            }
        } else {
            await MainActor.run {
                self.applyPreviewProfileData()
            }
        }
    }

    private func handleProfileAppear() {
        print("👀 [ProfileView] onAppear isOwnProfile=\(isOwnProfile) effectiveUserID=\(effectiveUserID ?? "nil")")
        initializeProfileHeadModeIfNeeded()
        NotificationCenter.default.post(name: Notification.Name("PauseGlobalFeedAudio"), object: nil)
        postMainTabChildRouteVisibility()
        showHeyPoplurProfileTutorialIfNeeded()

        print("📊 [ProfileView] onAppear - setting radius to 0")
        animateRadius(to: 0, duration: 0.3)

        print("📊 [ProfileView] onAppear - reloading posts for userID: \(effectiveUserID ?? "nil")")
        Task {
            await loadMyPosts()

            await MainActor.run {
                self.averageRadius = Double(self.averagePostRadius())
                if self.averageRadius > 0 {
                    print("📊 [ProfileView] onAppear - posts loaded, animating radius bar to: \(self.averageRadius)m")
                    animateRadius(to: self.averageRadius, duration: 1.2)
                } else {
                    print("📊 [ProfileView] onAppear - no posts, keeping radius at 0")
                    animateRadius(to: 0, duration: 0.3)
                }
                self.refreshDailyNotificationsFromCurrentPosts()
            }
        }
    }

    private func initializeProfileHeadModeIfNeeded() {
        guard isOwnProfile else { return }
        if !profileAvatarIs3D {
            profileAvatarIs3D = true
        }
        if !profileAvatarModeInitialized {
            profileAvatarModeInitialized = true
        }
    }

    private func showHeyPoplurProfileTutorialIfNeeded() {
        guard !hasSeenHeyPoplurProfileTutorial else { return }
        hasSeenHeyPoplurProfileTutorial = true
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showHeyPoplurProfileTutorial = true
        }
        NotificationCenter.default.post(name: .PoplurAIShowWakeTutorial, object: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.0) {
            dismissHeyPoplurProfileTutorial()
        }
    }

    private func dismissHeyPoplurProfileTutorial() {
        withAnimation(.easeOut(duration: 0.2)) {
            showHeyPoplurProfileTutorial = false
        }
    }

    private func handleProfileRemovePost(_ notification: Notification) {
        if let id = notification.object as? String {
            myPosts.removeAll { $0.id == id }
            averageRadius = Double(averagePostRadius())
        }
    }

    private func resetDisplayedProfileState() {
        displayUsername = nil
        userProfile = nil
        profileImage = nil
        profileImageURL = nil
        replaceRetainedPosts(with: [])
        hasLoadedOnce = false
        averageRadius = 0
        animateRadius(to: 0, duration: 0.3)
    }

    private func replaceRetainedPosts(with posts: [Post]) {
        myPosts = Array(posts.prefix(Self.maximumRetainedPostCount))
        let evicted = posts.dropFirst(Self.maximumRetainedPostCount)
        evictedPostRadius = evicted.reduce(0) { $0 + $1.radius }
        evictedPostCount = evicted.count
        let retainedIDs = Set(myPosts.map(\.id))
        loadedImages = loadedImages.filter { retainedIDs.contains($0.key) }
    }

    private func appendRetainedPage(_ posts: [Post]) {
        let retainedIDs = Set(myPosts.map(\.id))
        myPosts.append(contentsOf: posts.filter { !retainedIDs.contains($0.id) })
        let overflow = myPosts.count - Self.maximumRetainedPostCount
        if overflow > 0 {
            let evicted = myPosts.prefix(overflow)
            evictedPostCount += evicted.count
            evictedPostRadius += evicted.reduce(0) { $0 + $1.radius }
            let evictedIDs = Set(evicted.map(\.id))
            myPosts.removeFirst(overflow)
            loadedImages = loadedImages.filter { !evictedIDs.contains($0.key) }
        }
    }

    private func insertNewestRetainedPost(_ post: Post) {
        myPosts.insert(post, at: 0)
        let overflow = myPosts.count - Self.maximumRetainedPostCount
        if overflow > 0 {
            let evicted = myPosts.suffix(overflow)
            evictedPostCount += evicted.count
            evictedPostRadius += evicted.reduce(0) { $0 + $1.radius }
            let evictedIDs = Set(evicted.map(\.id))
            myPosts.removeLast(overflow)
            loadedImages = loadedImages.filter { !evictedIDs.contains($0.key) }
        }
    }

    private func handleOpenUserDetailForUser(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let uid = userInfo["userID"] as? String else { return }

        if uid != effectiveUserID {
            print("👤 [ProfileView] OpenUserDetailForUser received for uid=\(uid). Reloading profile locally.")
            resetDisplayedProfileState()
            Task {
                await loadPostsForSpecificUser(uid)
            }
        }
    }

    private func handleOpenSettingsRequested(_ notification: Notification) {
        guard isOwnProfile else { return }
        openProfileSubmenuRoute(.settings)
    }

    private func handleOpenDMsRequested(_ notification: Notification) {
        guard isOwnProfile else { return }
        openProfileSubmenuRoute(.mail)
    }

    private func handleOpenStoreRequested(_ notification: Notification) {
        guard isOwnProfile else { return }
        openProfileSubmenuRoute(.store)
    }

    private func handleOpenCreatorRequested(_ notification: Notification) {
        guard isOwnProfile else { return }
        openProfileSubmenuRoute(.creator)
    }

    private func handlePoplurAIShowAnalytics(_ notification: Notification) {
        openProfileSubmenuRoute(.stats)
    }

    private func handlePoplurAIProfileSortRequested(_ notification: Notification) {
        guard isOwnProfile else { return }
        let raw = notification.userInfo?["order"] as? String
        radiusSortOrder = raw.flatMap(PoplurAIProfileSortOrder.init(rawValue:)) ?? .mostRadius
        mode = .media
        closeProfileSubroutes()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func handleLastTappedUserChanged(_ notification: Notification) {
        guard let info = notification.userInfo,
              let uid = info["userID"] as? String,
              let radius = info["radius"] as? Double else { return }
        if uid == effectiveUserID {
            print("📏 [ProfileView] Updating radius bar for current user to \(radius)m from feed context")
            animateRadius(to: radius, duration: 0.6)
        }
    }

    private func handleProfileShowUserContext(_ notification: Notification) {
        guard let info = notification.userInfo,
              let uid = info["userID"] as? String else { return }
        let radius = info["radius"] as? Double
        let currentPostID = info["currentPostID"] as? String

        print("👤 [ProfileView] ProfileShowUserContext for uid=\(uid) radius=\(radius.map { String($0) } ?? "nil") currentPostID=\(currentPostID ?? "nil")")

        if uid != effectiveUserID {
            resetDisplayedProfileState()
            Task { await loadPostsForSpecificUser(uid) }
        }

        if let radius, uid == effectiveUserID {
            animateRadius(to: radius, duration: 0.6)
        }

        if let postID = currentPostID {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if let match = myPosts.first(where: { $0.id == postID }) {
                    expandPost(match)
                }
            }
        }
    }

    private func handleRefreshProfileAfterUpload(_ notification: Notification) {
        print("🔄 [ProfileView] RefreshProfileAfterUpload received - reloading posts")
        Task {
            await loadMyPosts()
            await MainActor.run {
                if let newest = myPosts.first {
                    expandPost(newest)
                }
            }
        }
    }

    private func handlePostCreated(_ notification: Notification) {
        guard let info = notification.userInfo,
              let id = info["id"] as? String,
              let uid = info["userID"] as? String,
              let lat = info["latitude"] as? Double,
              let lon = info["longitude"] as? Double,
              let mediaURL = info["mediaURL"] as? String,
              let rawRadiusDouble = info["radius"] as? Double ?? (info["radius"] as? Int).map(Double.init) else {
            print("⚠️ [ProfileView] PostCreated missing fields; ignoring")
            return
        }
        let viewCount = (info["viewCount"] as? Int) ?? 0
        guard uid == effectiveUserID else { return }

        let newPost = Post(
            id: id,
            latitude: lat,
            longitude: lon,
            mediaURL: mediaURL,
            radius: Int(rawRadiusDouble),
            viewCount: viewCount,
            userID: uid,
            posterURL: nil
        )
        if myPosts.contains(where: { $0.id == id }) { return }
        insertNewestRetainedPost(newPost)
        savePostsToCache(myPosts, for: uid)
        averageRadius = Double(averagePostRadius())
        animateRadius(to: averageRadius, duration: 0.8)
        refreshDailyNotificationsFromCurrentPosts()
    }

    private func handleCubeHoldBegan(_ notification: Notification) {
        print("🎯 [ProfileView] Received cubeHoldBegan - isOwnProfile: \(isOwnProfile)")
        guard !isRunningInPreviews else { return }
        isHoldingCube = true

        if isOwnProfile {
            print("✅ [ProfileView] Showing cube menu wheel")
            let backItem = CubeSubmenuItem(
                id: "back",
                title: "BACK",
                iconImageName: "HoldMenu_Back",
                systemImage: "arrow.backward",
                tint: .white
            ) {
                closeProfileSubroutes()
            }
            if showPopularPhone {
                cubeMenuWheel.beginHold(items: [backItem])
            } else if isShowingMainTabChildRoute {
                cubeMenuWheel.beginHold(items: [backItem] + cubeSubmenuItems)
            } else {
                cubeMenuWheel.beginHold(items: cubeSubmenuItems)
            }
            postProfileCubeIconOverride(cubeMenuWheel.selectedItem)
        } else {
            print("⚠️ [ProfileView] Not showing cube menu wheel - not own profile")
        }
    }

    private func handleCubeHoldEnded(_ notification: Notification) {
        guard !isRunningInPreviews else { return }
        isHoldingCube = false
        if isOwnProfile {
            postProfileCubeIconOverride(cubeMenuWheel.selectedItem)
            cubeMenuWheel.endHold(activateSelected: true)
        }
    }

    private func handleCubeHoldMoved(_ notification: Notification) {
        guard !isRunningInPreviews else { return }
        guard isOwnProfile, isHoldingCube else { return }
        cubeMenuWheel.scrub(with: notification)
        postProfileCubeIconOverride(cubeMenuWheel.selectedItem)
    }

    private func updateCubeHoldProgress() async {
        if isRunningInPreviews { return }
        guard isHoldingCube else { return }

        var current = barHeightFactor
        let incrementPerTick: CGFloat = 0.03
        while isHoldingCube && current < 1.0 {
            let fps = await MainActor.run { PoplurPerformanceManager.shared.targetFPS }
            try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 / max(1, fps)))
            current = min(1.0, current + incrementPerTick)
            await MainActor.run { barHeightFactor = current }
        }
    }

    private func handleRecordTabBecameActive(_ notification: Notification) {
        barHeightFactor = 0.0
    }

    private func handleCubeGlobalTap(_ notification: Notification) {
        print("🎯 [ProfileView] Received CubeGlobalTap - isOwnProfile: \(isOwnProfile)")
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

    private func handleProfileDisappear() {
        print("📊 [ProfileView] onDisappear - notifying to restore feed radius")
        cubeMenuWheel.endHold(activateSelected: false)
        headCycler.stop()
        postProfileCubeIconOverride(nil)
        NotificationCenter.default.post(name: Notification.Name("ProfileViewDismissed"), object: nil)
        NotificationCenter.default.post(name: .MainTabChildRouteVisibilityChanged, object: false)
    }

    private func handleCubeSelectedIndexChanged() {
        if cubeMenuWheel.isVisible {
            postProfileCubeIconOverride(cubeMenuWheel.selectedItem)
        }
    }

    private func handleProfileChildRouteChanged() {
        postMainTabChildRouteVisibility()
        syncProfileCubeIconToActiveRoute()
    }

    private func handleRoutedUserIDChanged(_ newUserID: String?) {
        print("🔄 [ProfileView] routedUserID changed to: \(newUserID ?? "nil")")
        resetDisplayedProfileState()

        Task {
            if let uid = effectiveUserID {
                await loadUserProfile(for: uid)
            }

            await loadMyPosts()

            if let uid = effectiveUserID {
                displayUsername = await UsernameCache.shared.username(for: uid)
            }

            if isOwnProfile {
                await loadPersistedProfileImageIfNeeded()
            }

            await MainActor.run {
                self.averageRadius = Double(self.averagePostRadius())
                if self.averageRadius > 0 {
                    print("📊 [ProfileView] User switched, animating radius bar to: \(self.averageRadius)m")
                    animateRadius(to: self.averageRadius, duration: 1.2)
                } else {
                    print("📊 [ProfileView] User switched, no posts - keeping radius at 0")
                    animateRadius(to: 0, duration: 0.3)
                }
            }
        }
    }

    private var avatarRow: some View {
        Group {
            if isOwnProfile {
                ZStack {
                    // Bell to the left of the head in 3D space
                    HStack {
                        Button {
                            withAnimation(.spring(response: 0.40, dampingFraction: 0.78)) {
                                showNotificationBanner.toggle()
                                if showNotificationBanner { hasUncheckedNotifications = false; notificationCenter.markAllRead() }
                            }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Text("🔔")
                                    .font(.system(size: 28))
                                    .shadow(color: .black.opacity(0.6), radius: 0, x: 1.5, y: 2.5)
                                    .shadow(color: .black.opacity(0.28), radius: 4, x: 2, y: 4)
                                    .frame(width: 44, height: 44)
                                if hasUncheckedNotifications {
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 10, height: 10)
                                        .offset(x: 4, y: -2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 20)
                        .padding(.top, 20)
                        Spacer()
                    }

                    // Avatar centered
                    Button {
                        showProfilePhotoOptions = true
                    } label: {
                        avatarContent
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            } else {
                avatarContent
            }
        }
    }
    
    private var avatarContent: some View {
        let size: CGFloat = isOwnProfile ? 180 : 96

        return ZStack {
            if isOwnProfile {
                // Animated speaking avatar. In 3D mode this is always the bundled Mark head.
                ProfileAvatarSpeakerView(
                    profileImage: profileImage,
                    profileImageURL: profileImageURL ?? userProfile?.profilePictureURL,
                    totalRadiusKM: myPostsTotalRadiusKM,
                    postCount: loadedPostCount,
                    size: size,
                    skin: cubeSkinStore.current
                )
            } else {
                photoAvatar
                    .clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
        .shadow(color: skinTheme.shadow, radius: 10, x: 0, y: 6)
        .animation(.spring(response: 0.55, dampingFraction: 0.72), value: isOwnProfile)
        .overlay(alignment: .bottomTrailing) {
            if lastHeadModelURL != nil && isOwnProfile {
                Button {
                    navigateToViewer = true
                } label: {
                    Image(systemName: "eye.fill")
                        .poplurIconShader()
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Circle().fill(skinTheme.badgeFill))
                }
                .buttonStyle(.plain)
                .padding(4)
            }
        }
    }

    private var photoAvatar: some View {
        ZStack {
            if let localImage = profileImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
            } else if let url = profileImageURL,
                      let data = try? Data(contentsOf: url),
                      let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else if let url = userProfile?.profilePictureURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Circle().fill(skinTheme.surfaceStrong)
                            .overlay(ProgressView().tint(skinTheme.accent))
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        Circle().fill(skinTheme.surfaceStrong)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .poplurIconShader()
                                    .foregroundColor(skinTheme.primaryText)
                            )
                    @unknown default:
                        Circle().fill(skinTheme.surfaceStrong)
                    }
                }
            } else if isOwnProfile, let email = auth.currentUser?.email,
                      let initials = initialsFrom(email: email) {
                Circle()
                    .fill(skinTheme.surfaceStrong)
                    .overlay(Text(initials).font(.system(size: 24, weight: .bold)))
            } else {
                Circle()
                    .fill(skinTheme.surfaceStrong)
                    .overlay(
                        Image(systemName: "person.fill")
                            .poplurIconShader()
                            .foregroundColor(skinTheme.primaryText)
                    )
            }
        }
    }

    private var usernameRow: some View {
        Text(profileTitleText)
            .font(.system(size: 22, weight: .heavy, design: .rounded))
            .foregroundColor(profileForeground)
            .poplurTextShader(intensity: 0.9)
            .shadow(color: profileTextShadow, radius: 3, x: 0, y: 1)
            .padding(.top, 4)
            .task(id: effectiveUserID) {
                // Fetch username for the profile being viewed (re-runs when effectiveUserID changes)
                if let uid = effectiveUserID ?? Auth.auth().currentUser?.uid {
                    displayUsername = await UsernameCache.shared.username(for: uid)
                }
            }
            .onChange(of: userProfile) { _, _ in
                headCycler.stop()
            }
    }

    private var profileTitleText: String {
        if let userProfile, userProfile.isBusinessAccount {
            return userProfile.profileDisplayName.uppercased()
        }
        return displayUsername ?? (isOwnProfile ? (auth.currentUser?.email?.components(separatedBy: "@").first?.uppercased() ?? "USERNAME") : usernameForDemoUser())
    }

    @ViewBuilder
    private var businessIdentityRow: some View {
        if let businessProfile = userProfile?.businessProfile, userProfile?.isBusinessAccount == true {
            VStack(spacing: 6) {
                HStack(spacing: 7) {
                    Image(systemName: businessProfile.verificationStatus == .verified ? "checkmark.seal.fill" : "building.2.crop.circle.fill")
                        .poplurIconShader()
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(businessStatusColor(businessProfile.verificationStatus))
                    Text(businessProfile.verificationStatus == .verified ? "Verified Business" : businessProfile.verificationStatus.title)
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(profileForeground)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Capsule().fill(businessStatusColor(businessProfile.verificationStatus).opacity(0.16)))
                .overlay(Capsule().stroke(businessStatusColor(businessProfile.verificationStatus).opacity(0.48), lineWidth: 1))

                if !businessProfile.category.isEmpty || !businessProfile.address.isEmpty {
                    Text([businessProfile.category, businessProfile.address].filter { !$0.isEmpty }.joined(separator: " - "))
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(profileTheme == .default ? .black.opacity(0.56) : profileForeground.opacity(0.80))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .padding(.horizontal, 24)
                }
            }
        }
    }

    private var profileStatsSummaryRow: some View {
        HStack(spacing: 10) {
            profileStatChip(
                title: "Radius",
                value: formattedProfileRadius(profileTotalRadiusMeters),
                systemImage: "dot.radiowaves.left.and.right"
            )
            profileStatChip(
                title: "Posts",
                value: "\(loadedPostCount)",
                systemImage: "square.grid.3x3.fill"
            )
        }
        .padding(.horizontal, 22)
        .frame(maxWidth: 380)
    }

    private func profileStatChip(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .poplurIconShader()
                .font(.system(size: 12, weight: .black))
                .foregroundColor(skinTheme.accent)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .black, design: .rounded))
                    .foregroundColor(skinTheme.secondaryText)
                    .poplurTextShader(intensity: 0.48)
                Text(value)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundColor(skinTheme.primaryText)
                    .poplurTextShader(intensity: 0.68)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 46)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(skinTheme.surface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(skinTheme.accent.opacity(0.36), lineWidth: 1)
        )
    }

    private func formattedProfileRadius(_ meters: Int) -> String {
        guard meters > 0 else { return "0 KM" }
        if meters >= 1_000_000 {
            let km = Double(meters) / 1000.0
            return String(format: "%.1fK KM", km / 1000.0)
        }
        if meters >= 1000 {
            let km = Double(meters) / 1000.0
            if meters % 1000 == 0 {
                return "\(Int(km)) KM"
            }
            return String(format: "%.1f KM", km)
        }
        return "\(meters) M"
    }

    private func businessStatusColor(_ status: BusinessVerificationStatus) -> Color {
        switch status {
        case .notVerified: return .gray
        case .pendingReview: return .orange
        case .verified: return .green
        case .rejected: return .red
        case .needsMoreInfo: return .blue
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
        HStack(spacing: 28) {
            modeButton(title: "Media", isSelected: mode == .media) {
                mode = .media
            }
            modeButton(title: "Messages", isSelected: mode == .messages) {
                mode = .messages
            }
            modeButton(title: "Saved", isSelected: mode == .saved) {
                mode = .saved
            }
        }
        .padding(.top, 2)
    }

    private func modeButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(
                        profileTheme == .default
                            ? (isSelected ? .black : .black.opacity(0.72))
                            : profileForeground.opacity(isSelected ? 1 : 0.78)
                    )
                    .poplurTextShader(intensity: isSelected ? 0.86 : 0.58)
                    .shadow(color: profileTextShadow, radius: 3, x: 0, y: 1)
                    .padding(8)
            }
            .buttonStyle(.plain)

            Capsule()
                .fill(isSelected ? profileAccent : Color.clear)
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
        replaceRetainedPosts(with: previewPosts)
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
                replaceRetainedPosts(with: [])
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
                self.replaceRetainedPosts(with: convertedPosts)
                self.hasLoadedOnce = true
                self.canLoadMore = false
                self.averageRadius = Double(self.averagePostRadius())
                self.isLoading = false
                self.refreshDailyNotificationsFromCurrentPosts()
            }
            
            return
        }
        
        // Try to show cached posts immediately for better perceived performance
        if let cached = loadPostsFromCache(for: targetUID), !cached.isEmpty {
            await MainActor.run {
                self.replaceRetainedPosts(with: cached)
                self.hasLoadedOnce = true
                self.averageRadius = Double(self.averagePostRadius())
                self.refreshDailyNotificationsFromCurrentPosts()
            }
        } else {
            await MainActor.run {
                self.averageRadius = 0
            }
            animateRadius(to:0, duration: 0.3)
        }

        await MainActor.run {
            isLoading = true
            canLoadMore = true
            lastDocument = nil
            replaceRetainedPosts(with: [])
        }
        defer { Task { @MainActor in isLoading = false } }

        do {
            let page = try await fetchPostsPage(for: targetUID, after: nil, limit: pageSize)
            await MainActor.run {
                self.replaceRetainedPosts(with: page.posts)
                self.lastDocument = page.lastDoc
                self.canLoadMore = page.posts.count >= pageSize && page.lastDoc != nil
                self.averageRadius = Double(self.averagePostRadius())
                self.hasLoadedOnce = true
                self.refreshDailyNotificationsFromCurrentPosts()
            }
            // Persist latest posts to cache
            savePostsToCache(page.posts, for: targetUID)
            
            if page.posts.isEmpty {
                await MainActor.run {
                    self.averageRadius = 0
                    animateRadius(to:0, duration: 0.3)
                }
            }
        } catch {
            print("Profile: failed to load posts -> \(error.localizedDescription)")
            // Fall back to cache if available
            if let cached = loadPostsFromCache(for: targetUID), !cached.isEmpty {
                await MainActor.run {
                    self.replaceRetainedPosts(with: cached)
                    self.hasLoadedOnce = true
                    self.canLoadMore = false
                    self.averageRadius = Double(self.averagePostRadius())
                }
            } else {
                await MainActor.run {
                    self.replaceRetainedPosts(with: [])
                    self.hasLoadedOnce = true
                    self.canLoadMore = false
                    self.averageRadius = 0
                }
                animateRadius(to:0, duration: 0.3)
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
                self.replaceRetainedPosts(with: converted)
                self.hasLoadedOnce = true
                self.canLoadMore = false
                self.averageRadius = Double(self.averagePostRadius())
                self.isLoading = false
                self.refreshDailyNotificationsFromCurrentPosts()
            }
            return
        }

        // Cached posts first
        if let cached = loadPostsFromCache(for: uid), !cached.isEmpty {
            await MainActor.run {
                self.replaceRetainedPosts(with: cached)
                self.hasLoadedOnce = true
                self.averageRadius = Double(self.averagePostRadius())
                self.refreshDailyNotificationsFromCurrentPosts()
            }
        } else {
            await MainActor.run {
                self.averageRadius = 0
            }
            animateRadius(to:0, duration: 0.3)
        }

        await MainActor.run {
            isLoading = true
            canLoadMore = true
            lastDocument = nil
            replaceRetainedPosts(with: [])
        }
        defer { Task { @MainActor in isLoading = false } }

        do {
            let page = try await fetchPostsPage(for: uid, after: nil, limit: pageSize)
            await MainActor.run {
                self.replaceRetainedPosts(with: page.posts)
                self.lastDocument = page.lastDoc
                self.canLoadMore = page.posts.count >= pageSize && page.lastDoc != nil
                self.averageRadius = Double(self.averagePostRadius())
                self.hasLoadedOnce = true
                self.refreshDailyNotificationsFromCurrentPosts()
            }
            savePostsToCache(page.posts, for: uid)
            
            if page.posts.isEmpty {
                await MainActor.run {
                    self.averageRadius = 0
                    animateRadius(to:0, duration: 0.3)
                }
            }
        } catch {
            print("Profile: forced load failed -> \(error.localizedDescription)")
            if let cached = loadPostsFromCache(for: uid), !cached.isEmpty {
                await MainActor.run {
                    self.replaceRetainedPosts(with: cached)
                    self.hasLoadedOnce = true
                    self.canLoadMore = false
                    self.averageRadius = Double(self.averagePostRadius())
                    self.refreshDailyNotificationsFromCurrentPosts()
                }
            } else {
                await MainActor.run {
                    self.replaceRetainedPosts(with: [])
                    self.hasLoadedOnce = true
                    self.canLoadMore = false
                    self.averageRadius = 0
                }
                animateRadius(to:0, duration: 0.3)
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
                self.appendRetainedPage(page.posts)
                self.lastDocument = page.lastDoc
                self.canLoadMore = page.posts.count >= pageSize && page.lastDoc != nil
                self.averageRadius = Double(self.averagePostRadius())
            }
            // Update cache with appended posts
            savePostsToCache(self.myPosts, for: targetUID)
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

    private func loadUserProfile(for uid: String) async {
        guard !uid.isEmpty else { return }
        do {
            let document = try await Firestore.firestore().collection("users").document(uid).getDocument()
            guard let profile = UserProfile(document: document) else { return }
            await MainActor.run {
                self.userProfile = profile
                if profile.isBusinessAccount {
                    self.displayUsername = profile.profileDisplayName.uppercased()
                }
                if self.profileImageURL == nil {
                    self.profileImageURL = profile.profilePictureURL
                }
            }
        } catch {
            print("Profile: failed to load user profile -> \(error.localizedDescription)")
        }
    }

    @discardableResult
    private func saveProfileImage(_ image: UIImage) throws -> URL {
        let url = profileImageFileURL()
        guard let data = image.poplur4KJPEGData() else {
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
        if myPosts.isEmpty && evictedPostCount == 0 { return 0 }
        // Changed to total accumulated radius instead of average
        let total = evictedPostRadius + myPosts.reduce(0) { $0 + $1.radius }
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
        guard let data = image.poplur4KJPEGData() else {
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

private struct ProfileNotificationBanner: View {
    let notifications: [ProfileNotificationItem]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 1.0, green: 0.45, blue: 0.73), Color(red: 0.96, green: 0.15, blue: 0.52)],
                startPoint: .top,
                endPoint: .bottom
            )
            ProfileNotificationDotMap()
                .blendMode(.screen)
                .opacity(0.88)

            VStack(alignment: .leading, spacing: 0) {
                Text("Notifications")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.white)
                    .shadow(color: Color(red: 0.35, green: 0.0, blue: 0.17).opacity(0.4), radius: 2, y: 1)
                    .padding(.horizontal, 20)
                    .padding(.top, 56)
                    .padding(.bottom, 14)

                if notifications.isEmpty {
                    Text("No notifications yet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white.opacity(0.82))
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(notifications.prefix(8)) { item in
                                HStack(alignment: .top, spacing: 12) {
                                    ZStack(alignment: .topTrailing) {
                                        Circle()
                                            .fill(Color.white.opacity(0.2))
                                            .frame(width: 40, height: 40)
                                            .overlay {
                                                Image(systemName: item.kind.iconName)
                                                    .poplurIconShader()
                                                    .font(.system(size: 17, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        if item.isUnchecked {
                                            Circle().fill(Color(red: 1.0, green: 0.82, blue: 0.91)).frame(width: 9, height: 9)
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title)
                                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                                            .foregroundColor(.white)
                                        Text(item.detail)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(.white.opacity(0.84))
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(14)
                                .background(Color(red: 0.52, green: 0.01, blue: 0.26).opacity(0.3), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .frame(maxHeight: 340)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .offset(y: -28))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }
}

private struct ProfileNotificationDotMap: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let land: [[CGPoint]] = [
        [CGPoint(x: 0.02, y: 0.13), CGPoint(x: 0.08, y: 0.08), CGPoint(x: 0.17, y: 0.07), CGPoint(x: 0.25, y: 0.12), CGPoint(x: 0.31, y: 0.20), CGPoint(x: 0.27, y: 0.27), CGPoint(x: 0.23, y: 0.30), CGPoint(x: 0.21, y: 0.38), CGPoint(x: 0.15, y: 0.43), CGPoint(x: 0.10, y: 0.37), CGPoint(x: 0.06, y: 0.34), CGPoint(x: 0.03, y: 0.27)],
        [CGPoint(x: 0.20, y: 0.04), CGPoint(x: 0.27, y: 0.05), CGPoint(x: 0.30, y: 0.11), CGPoint(x: 0.27, y: 0.17), CGPoint(x: 0.22, y: 0.15), CGPoint(x: 0.18, y: 0.09)],
        [CGPoint(x: 0.16, y: 0.39), CGPoint(x: 0.23, y: 0.40), CGPoint(x: 0.29, y: 0.47), CGPoint(x: 0.31, y: 0.57), CGPoint(x: 0.28, y: 0.68), CGPoint(x: 0.25, y: 0.79), CGPoint(x: 0.22, y: 0.91), CGPoint(x: 0.18, y: 0.82), CGPoint(x: 0.16, y: 0.70), CGPoint(x: 0.13, y: 0.56), CGPoint(x: 0.13, y: 0.46)],
        [CGPoint(x: 0.39, y: 0.18), CGPoint(x: 0.45, y: 0.14), CGPoint(x: 0.53, y: 0.16), CGPoint(x: 0.56, y: 0.23), CGPoint(x: 0.52, y: 0.29), CGPoint(x: 0.46, y: 0.28), CGPoint(x: 0.40, y: 0.24)],
        [CGPoint(x: 0.40, y: 0.28), CGPoint(x: 0.51, y: 0.27), CGPoint(x: 0.57, y: 0.36), CGPoint(x: 0.56, y: 0.49), CGPoint(x: 0.52, y: 0.62), CGPoint(x: 0.47, y: 0.72), CGPoint(x: 0.42, y: 0.62), CGPoint(x: 0.38, y: 0.47), CGPoint(x: 0.38, y: 0.35)],
        [CGPoint(x: 0.51, y: 0.14), CGPoint(x: 0.63, y: 0.08), CGPoint(x: 0.76, y: 0.08), CGPoint(x: 0.89, y: 0.14), CGPoint(x: 0.98, y: 0.23), CGPoint(x: 0.95, y: 0.33), CGPoint(x: 0.87, y: 0.36), CGPoint(x: 0.82, y: 0.44), CGPoint(x: 0.73, y: 0.42), CGPoint(x: 0.68, y: 0.37), CGPoint(x: 0.60, y: 0.37), CGPoint(x: 0.54, y: 0.30), CGPoint(x: 0.51, y: 0.23)],
        [CGPoint(x: 0.70, y: 0.65), CGPoint(x: 0.80, y: 0.60), CGPoint(x: 0.90, y: 0.64), CGPoint(x: 0.94, y: 0.74), CGPoint(x: 0.87, y: 0.83), CGPoint(x: 0.76, y: 0.81), CGPoint(x: 0.69, y: 0.73)],
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                let spacing = min(max(size.width / 52, 6.5), 10.0)
                let time = timeline.date.timeIntervalSinceReferenceDate
                for row in stride(from: 0, through: Int(size.height / spacing), by: 1) {
                    for column in stride(from: 0, through: Int(size.width / spacing), by: 1) {
                        let x = (CGFloat(column) + 0.5) * spacing
                        let y = (CGFloat(row) + 0.5) * spacing
                        guard land.contains(where: { contains(CGPoint(x: x / size.width, y: 0.04 + (y / size.height) * 0.88), polygon: $0) }) else { continue }
                        let hash = abs(row * 73 + column * 151 + row * column * 19) % 41
                        guard hash < 9 else { continue }
                        let pulse = reduceMotion ? 0.62 : 0.5 + 0.5 * sin(time / 0.62 + Double(hash) * 0.77 + Double(row) * 0.19 + Double(column) * 0.31)
                        let radius = max(1.55, spacing * 0.21) * (0.86 + CGFloat(pulse) * 0.28)
                        drawDot(context: context, center: CGPoint(x: x, y: y), radius: radius, pulse: CGFloat(pulse))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func drawDot(context: GraphicsContext, center: CGPoint, radius: CGFloat, pulse: CGFloat) {
        func ellipse(_ offset: CGSize, _ scale: CGFloat, _ color: Color) {
            context.fill(Path(ellipseIn: CGRect(x: center.x + offset.width - radius * scale, y: center.y + offset.height - radius * scale, width: radius * scale * 2, height: radius * scale * 2)), with: .color(color))
        }
        ellipse(CGSize(width: 0, height: 1.3), 1, Color(red: 0.47, green: 0.02, blue: 0.24).opacity(0.3 + pulse * 0.22))
        ellipse(CGSize(width: 0, height: -0.8), 1, Color(red: 1.0, green: 0.77, blue: 0.88).opacity(0.3 + pulse * 0.34))
        ellipse(.zero, 0.94, Color(red: 1.0, green: 0.45, blue: 0.68).opacity(0.5 + pulse * 0.4))
    }

    private func contains(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count > 2 else { return false }
        var hit = false
        var previous = polygon[polygon.index(before: polygon.endIndex)]
        for current in polygon {
            if (current.y > point.y) != (previous.y > point.y), point.x < (previous.x - current.x) * (point.y - current.y) / ((previous.y - current.y) == 0 ? 0.000001 : (previous.y - current.y)) + current.x {
                hit.toggle()
            }
            previous = current
        }
        return hit
    }
}

private struct ProfileNotificationsView: View {
    let notifications: [ProfileNotificationItem]
    let onMarkRead: () -> Void

    @ObservedObject private var cubeSkinStore = CubeSkinStore.shared

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()

            profileNotificationsList
        }
        .onAppear(perform: onMarkRead)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var profileNotificationsList: some View {
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
                                        .poplurIconShader()
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
                    .poplurCard()
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }
}

private struct PoplurCreditCardProduct: Identifiable {
    let id: String // Stable cross-platform card ID.
    let name: String
    let modelName: String
    let posterAssetName: String
    let iosProductID: String
    let fallbackPrice: String
    let credits: Int
    let accent: Color
    let kicker: String
    let description: String

    var presentationRotationX: Float {
        id == "swoosh" ? .pi / 2 : 0
    }

    static let catalog: [PoplurCreditCardProduct] = [
        PoplurCreditCardProduct(
            id: "inverted",
            name: "Inverted Card",
            modelName: "poplur_card_inverted",
            posterAssetName: "poplur_store_card_inverted_poster",
            iosProductID: "com.apptist.Poplur2025.card.inverted",
            fallbackPrice: "$2.99",
            credits: 300,
            accent: Color(red: 0.93, green: 0.20, blue: 0.52),
            kicker: "BOLD BY DESIGN",
            description: "A sharp inside-out Poplur finish. Adds 300 Poplur Credits after verification."
        ),
        PoplurCreditCardProduct(
            id: "lens",
            name: "Lens Card",
            modelName: "poplur_card_lens",
            posterAssetName: "poplur_store_card_lens_poster",
            iosProductID: "com.apptist.Poplur2025.card.lens",
            fallbackPrice: "$4.99",
            credits: 550,
            accent: Color(red: 0.10, green: 0.70, blue: 0.92),
            kicker: "FOCUS FORWARD",
            description: "A glossy optical card with a camera-lens core. Adds 550 Poplur Credits after verification."
        ),
        PoplurCreditCardProduct(
            id: "splitDiamond",
            name: "Split Diamond Card",
            modelName: "poplur_card_split_diamond",
            posterAssetName: "poplur_store_card_split_diamond_poster",
            iosProductID: "com.apptist.Poplur2025.card.splitdiamond",
            fallbackPrice: "$6.99",
            credits: 800,
            accent: Color(red: 0.58, green: 0.30, blue: 0.94),
            kicker: "CUT TO STAND OUT",
            description: "A faceted split-diamond card built for standout profiles. Adds 800 Poplur Credits after verification."
        ),
        PoplurCreditCardProduct(
            id: "swoosh",
            name: "Swoosh Card",
            modelName: "poplur_card_swoosh",
            posterAssetName: "poplur_store_card_swoosh_poster",
            iosProductID: "com.apptist.Poplur2025.card.swoosh",
            fallbackPrice: "$9.99",
            credits: 1_200,
            accent: Color(red: 0.12, green: 0.78, blue: 0.68),
            kicker: "MADE TO MOVE",
            description: "A flowing sculpted card with Poplur motion. Adds 1,200 Poplur Credits after verification."
        )
    ]
}

private struct ProfileStoreCreditCardCarousel: View {
    let cards: [PoplurCreditCardProduct]
    let displayPrice: (PoplurCreditCardProduct) -> String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedIndex = 0
    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        let card = cards[selectedIndex]
        VStack(spacing: 14) {
            PoplurStoreCardModelView(
                modelName: card.modelName,
                presentationRotationX: card.presentationRotationX
            )
            .id(card.id)
            .frame(height: 238)
            .background(
                LinearGradient(
                    colors: [Color.black, card.accent.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .accessibilityLabel("\(card.name) rotating 3D preview")

            VStack(spacing: 7) {
                Text(card.kicker)
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(card.accent)
                Text(card.name)
                    .font(.system(size: 29, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                Text(card.description)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 560)
                HStack(spacing: 10) {
                    Text("\(card.credits.formatted()) credits")
                    Text("•")
                    Text(displayPrice(card))
                }
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
            }

            HStack(spacing: 8) {
                ForEach(cards.indices, id: \.self) { index in
                    Button {
                        withAnimation(.easeInOut(duration: 0.28)) { selectedIndex = index }
                    } label: {
                        Capsule()
                            .fill(index == selectedIndex ? card.accent : Color.black.opacity(0.18))
                            .frame(width: index == selectedIndex ? 24 : 8, height: 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(cards[index].name)")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .onReceive(timer) { _ in
            guard !reduceMotion, !cards.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.34)) {
                selectedIndex = (selectedIndex + 1) % cards.count
            }
        }
    }
}

private struct RadiusStoreView: View {
    @Binding var purchasedRadiusMeters: Int
    let userID: String?
    @ObservedObject var purchaseVM: RadiusPurchaseViewModel
    @State private var selectedCardID = PoplurCreditCardProduct.catalog[0].id
    @State private var orderMessage: String?
    @State private var cardPricesByID: [String: String] = [:]
    @State private var isPurchasingCard = false

    private let columns = [
        GridItem(.adaptive(minimum: 168), spacing: 14)
    ]

    private var selectedCard: PoplurCreditCardProduct {
        PoplurCreditCardProduct.catalog.first { $0.id == selectedCardID } ?? PoplurCreditCardProduct.catalog[0]
    }

    var body: some View {
        MockBrowser(urlString: "www.poplurstore.ca") {
            VStack(spacing: 0) {
                profileStoreNavigation

                ProfileStoreCreditCardCarousel(
                    cards: PoplurCreditCardProduct.catalog,
                    displayPrice: displayPrice
                )
                    .padding(.top, 8)

                profileStoreHero

                VStack(alignment: .leading, spacing: 22) {
                    featuredCard

                    finishPicker

                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(PoplurCreditCardProduct.catalog) { card in
                            creditCardTile(card)
                        }
                    }

                    checkoutSummary

                    radiusAddOns
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 36)
                .frame(maxWidth: 1080)
                .frame(maxWidth: .infinity)
                .background(Color(red: 0.965, green: 0.965, blue: 0.975))
            }
            .frame(maxWidth: .infinity)
            .background(Color.white)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            cardPricesByID = await PoplurCardPurchaseService.shared.displayPrices()
            await purchaseVM.loadProducts()
            let delivered = await purchaseVM.finishUndeliveredRadiusPurchases(userID: userID)
            if delivered > 0 {
                purchasedRadiusMeters += delivered
            }
        }
    }

    private func displayPrice(_ card: PoplurCreditCardProduct) -> String {
        cardPricesByID[card.iosProductID] ?? card.fallbackPrice
    }

    private var profileStoreNavigation: some View {
        HStack(spacing: 22) {
            Text("Poplur")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.black)

            if UIDevice.current.userInterfaceIdiom != .phone {
                HStack(spacing: 22) {
                    ForEach(["Store", "Cards", "Radius", "Phone", "Support"], id: \.self) { item in
                        Text(item)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.black.opacity(0.64))
                    }
                }
            }

            Spacer(minLength: 8)

            Image(systemName: "bag")
                .poplurIconShader()
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.black.opacity(0.76))
                .frame(width: 34, height: 34)
        }
        .padding(.horizontal, UIDevice.current.userInterfaceIdiom == .phone ? 18 : 38)
        .frame(height: 54)
        .background(.ultraThinMaterial)
    }

    private var profileStoreHero: some View {
        VStack(spacing: 12) {
            Text("Poplur Store")
                .font(.system(size: 54, weight: .semibold))
                .minimumScaleFactor(0.65)
                .lineLimit(1)
                .foregroundColor(.black)

            Text("Collect a 3D Poplur card and receive verified credits instantly.")
                .font(.system(size: 20, weight: .regular))
                .multilineTextAlignment(.center)
                .foregroundColor(.black.opacity(0.64))
                .frame(maxWidth: 620)
        }
        .padding(.horizontal, 24)
        .padding(.top, 38)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }

    private var storeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Poplur Store")
                    .font(.system(size: 31, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)

                Spacer()

                Image(systemName: "bag.fill")
                    .poplurIconShader()
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
            PoplurStoreCardPosterView(
                assetName: selectedCard.posterAssetName,
                name: selectedCard.name,
                accent: selectedCard.accent
            )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: selectedCard.accent.opacity(0.28), radius: 22, x: 0, y: 12)

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(selectedCard.name)
                        .font(.system(size: 23, weight: .heavy, design: .rounded))
                        .foregroundColor(.black)

                    Text(selectedCard.description)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(displayPrice(selectedCard))
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
            }

            HStack(spacing: 10) {
                storeBadge("3D collectible")
                storeBadge("\(selectedCard.credits.formatted()) credits")
                storeBadge("Server verified")
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
            Text("Choose a card")
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
                                                .poplurIconShader()
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
                PoplurStoreCardPosterView(
                    assetName: card.posterAssetName,
                    name: card.name,
                    accent: card.accent
                )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(card.name)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Text(displayPrice(card))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(.black)
                    Spacer()
                    Image(systemName: selectedCardID == card.id ? "checkmark.circle.fill" : "plus.circle.fill")
                        .poplurIconShader()
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
                PoplurStoreCardPosterView(
                    assetName: selectedCard.posterAssetName,
                    name: selectedCard.name,
                    accent: selectedCard.accent
                )
                .frame(width: 66, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Order summary")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.black)
                    Text("1 Poplur card - \(selectedCard.name)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black.opacity(0.58))
                }

                Spacer()

                Text(displayPrice(selectedCard))
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
            }

            Divider()

            HStack {
                Text("Credit delivery")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black.opacity(0.58))
                Spacer()
                Text("Instant after verification")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.green)
            }

            Button {
                purchaseSelectedCard()
            } label: {
                HStack {
                    if isPurchasingCard {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "apple.logo")
                            .poplurIconShader()
                    }
                    Text(isPurchasingCard ? "Opening App Store…" : "Buy \(selectedCard.name)")
                }
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isPurchasingCard)

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

    private func purchaseSelectedCard() {
        guard !isPurchasingCard else { return }
        let card = selectedCard
        isPurchasingCard = true
        orderMessage = "Opening secure App Store checkout…"
        Task { @MainActor in
            let items: [[String: Any]] = [[
                "cardId": card.id,
                "iosProductId": card.iosProductID,
                "quantity": 1
            ]]
            let result = await PoplurCardPurchaseService.shared.checkout(
                rawItems: items
            ) { pendingResult in
                orderMessage = pendingResult.message
            }
            orderMessage = result.message
            isPurchasingCard = false
        }
    }

    private var radiusAddOns: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Add radius")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
                Spacer()
                Image(systemName: "dot.radiowaves.left.and.right")
                    .poplurIconShader()
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
                                    .poplurIconShader()
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

// Grid and list tiles
private struct ProfileGridTile: View {
    let post: Post
    let preloadedImage: UIImage?
    @State private var loadedImage: UIImage?
    private let corner: CGFloat = 24
    private var isVideo: Bool {
        let lower = post.mediaURL.lowercased()
        return lower.contains(".mp4")
            || lower.contains(".mov")
            || lower.contains(".m4v")
            || lower.contains(".m3u8")
            || lower.contains("video")
    }

    private var imageSource: String? {
        if isVideo {
            let poster = post.posterURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return poster.isEmpty ? nil : poster
        }
        let media = post.mediaURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return media.isEmpty ? nil : media
    }

    private var localImage: UIImage? {
        guard let source = imageSource else { return nil }
        let prefix = "asset://"
        if source.hasPrefix(prefix) {
            let name = String(source.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? nil : UIImage(named: name)
        }
        if let url = URL(string: source), url.isFileURL {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = preloadedImage ?? loadedImage ?? localImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    if isVideo {
                        Image(systemName: "play.fill")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.45), radius: 5)
                    }
                } else {
                    ZStack {
                        Color.gray.opacity(0.22)
                        VStack(spacing: 8) {
                            Image(systemName: isVideo ? "play.fill" : "photo")
                                .font(.system(size: isVideo ? 36 : 22, weight: .bold))
                                .foregroundStyle(Color.white.opacity(0.84))
                            if !isVideo {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                }

                LinearGradient(
                    colors: [
                        .clear,
                        Color.black.opacity(0.16)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                Text("\(max(1, post.radius / 1000)) KM")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .poplurTextShader(intensity: 0.62)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(Color.black.opacity(0.58))
                    )
                    .padding(8)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: imageSource ?? "") {
            guard preloadedImage == nil, loadedImage == nil, let source = imageSource else { return }
            if let localImage {
                loadedImage = localImage
                return
            }
            guard let url = URL(string: source), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
            if let image = await CachedImageLoader.shared.load(url) {
                await MainActor.run { loadedImage = image }
            }
        }
        .onDisappear {
            if preloadedImage == nil {
                loadedImage = nil
            }
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
