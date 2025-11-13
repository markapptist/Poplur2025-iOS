import SwiftUI
import FirebaseFirestore
import AVKit
import CoreLocation

struct FeedView: View {
    @State private var posts: [Post] = []
    @State private var isLoading = false
    @State private var didSeedIfEmpty = false

    // Pagination
    private let pageSize = 5
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

    // Gate: only render the current page at first, then widen to neighbors after first user scroll
    @State private var hasUserScrolledOnce = false

    // Debounce fast index changes to avoid rapid player start/stop thrash
    @State private var debouncedIndex: Int = 0

    // Computed: current post
    private var currentPost: Post? {
        posts[safe: debouncedIndex]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                feedContent(in: geo.size)
                overlayChrome
                    .zIndex(10)
                profileNavigationLink
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
            currentIndex = 0
        }
        .onChange(of: currentIndex) { newIndex in
            // Debounce rapid changes to avoid player thrash
            let target = newIndex
            Task {
                try? await Task.sleep(nanoseconds: 80_000_000) // 80ms debounce
                await MainActor.run {
                    debouncedIndex = target
                }
            }

            if let uid = posts[safe: newIndex]?.userID {
                maybeResolveUsername(for: uid)
            }
            if !hasUserScrolledOnce, !posts.isEmpty {
                hasUserScrolledOnce = true
            }
        }
        .onAppear {
            debouncedIndex = currentIndex
        }
    }

    // MARK: - Split content to ease type-checking

    @ViewBuilder
    private func feedContent(in size: CGSize) -> some View {
        if posts.isEmpty {
            emptyFeedView(in: size)
                .ignoresSafeArea()
        } else {
            populatedFeedView(in: size)
                .ignoresSafeArea()
        }
    }

    private func emptyFeedView(in size: CGSize) -> some View {
        VerticalPager(currentIndex: .constant(0), pageCount: 1) {
            ZStack {
                if let url = fallbackFastVideoURL {
                    FullscreenVideoView(url: url,
                                        shouldPlay: .constant(true),
                                        isMuted: false,
                                        shouldLoop: true)
                        .id(url)
                } else {
                    Color.black
                }
            }
            .frame(width: size.width, height: size.height)
            .background(Color.black)
        }
    }

    private func populatedFeedView(in size: CGSize) -> some View {
        VerticalPager(currentIndex: $currentIndex, pageCount: posts.count) {
            ZStack {
                let pageIndices: [Int] = pagesToDisplay
                ForEach(pageIndices, id: \.self) { idx in
                    if let post = posts[safe: idx] {
                        let isActive: Bool = (debouncedIndex == idx)
                        let shouldPlay: Bool = isActive
                        let isMuted: Bool = !isActive
                        let resolvedName: String = displayName(for: post)

                        FeedFullscreenPage(
                            post: post,
                            isActive: Binding(
                                get: { isActive },
                                set: { _ in }
                            ),
                            displayName: resolvedName,
                            onUserTapped: { userId in
                                selectedUserID = userId
                                navigateToProfile = true
                            },
                            shouldPlay: shouldPlay,
                            isMuted: isMuted
                        )
                        .frame(width: size.width, height: size.height)
                        .position(
                            x: size.width / 2,
                            y: (CGFloat(idx) + 0.5) * size.height
                        )
                        .animation(.none, value: debouncedIndex)
                        .onAppear {
                            maybeLoadMoreIfNeeded(appearingIndex: idx)
                            maybeResolveUsername(for: post.userID)
                        }
                    }
                }
            }
            .frame(width: size.width, height: size.height * CGFloat(max(posts.count, 1)))
            .background(Color.black)
        }
    }

    private var profileNavigationLink: some View {
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

    private var pagesToDisplay: [Int] {
        guard !posts.isEmpty else { return [] }
        if !hasUserScrolledOnce {
            return [debouncedIndex].filter { $0 >= 0 && $0 < posts.count }
        }
        return Array(Set([
            debouncedIndex - 1,
            debouncedIndex,
            debouncedIndex + 1
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
        .ignoresSafeArea()
    }

    // MARK: - Username helpers

    private func displayName(for post: Post) -> String {
        if let name = usernames[post.userID], !name.isEmpty {
            return name
        }
        // Fallback: a readable form of userID
        if post.userID.hasPrefix("fake_") || post.userID.hasPrefix("na_user_") || post.userID.hasPrefix("world_user_") {
            return post.userID.replacingOccurrences(of: "_", with: " ").uppercased()
        }
        // Shorten generic uid
        let short = post.userID.prefix(6)
        return "User \(short)"
    }

    private func maybeResolveUsername(for uid: String) {
        // Avoid duplicate fetches per-view
        if usernames[uid] != nil || usernameLoadsInProgress.contains(uid) { return }
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
    }

    // MARK: - Data loading stubs (fill in with your real logic)

    private func reload() async {
        // TODO: Implement your Firestore loading and pagination reset here.
        // Keep a simple no-op to compile for now.
    }

    private func seedAndReload() async {
        // TODO: Implement your seeding logic, then call reload().
    }

    private func maybeLoadMoreIfNeeded(appearingIndex idx: Int) {
        // TODO: Implement pagination trigger when nearing end of list.
        // Keep a simple no-op to compile for now.
    }
}

private struct FeedFullscreenPage: View {
    let post: Post
    @Binding var isActive: Bool
    let displayName: String
    var onUserTapped: (String) -> Void

    let shouldPlay: Bool
    let isMuted: Bool

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
                if let poster = post.posterURL, let posterURL = URL(string: poster) {
                    AsyncImage(url: posterURL, transaction: Transaction(animation: .none)) { phase in
                        switch phase {
                        case .empty:
                            Color.black
                        case .success(let img):
                            img
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        case .failure:
                            Color.black
                        @unknown default:
                            Color.black
                        }
                    }
                    .allowsHitTesting(false)
                } else {
                    Color.black
                        .allowsHitTesting(false)
                }

                Group {
                    if isVideo, let url = URL(string: post.mediaURL) {
                        if shouldPlay {
                            FullscreenVideoView(url: url,
                                                shouldPlay: .constant(true),
                                                isMuted: isMuted,
                                                shouldLoop: true)
                                .allowsHitTesting(false)
                        } else {
                            EmptyView()
                        }
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
