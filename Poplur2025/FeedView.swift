import SwiftUI
import AVKit
import AVFoundation
import FirebaseFirestore

struct FeedView: View {
    @State private var posts: [Post] = []
    @State private var selection: Int = 0
    // Readiness for HomeView’s preloader
    @State private var feedReady = false

    // New readiness gates
    @State private var didFinishFirestore = false
    @State private var didPrepareFirstMedia = false
    @State private var wiredFirstPageCallbackForLoad = false

    // Fixed page size to avoid rotation/safe-area rounding mismatches
    private var screenSize: CGSize {
        UIScreen.main.bounds.size
    }
    private var pageWidth: CGFloat { screenSize.width }
    private var pageHeight: CGFloat { screenSize.height }

    var body: some View {
        ZStack {
            if posts.isEmpty && !didFinishFirestore {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        Color.black
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    )
                    .allowsHitTesting(false)
            } else {
                // Vertical paging using rotation trick (pages are locked to full-screen size)
                TabView(selection: $selection) {
                    ForEach(Array(posts.indices), id: \.self) { (idx: Int) in
                        FullScreenPostView(
                            post: posts[idx],
                            isActive: selection == idx,
                            didPrepareMedia: (idx == 0 ? firstMediaPrepared : nil),
                            pageSize: CGSize(width: pageHeight, height: pageWidth) // rotated content size
                        )
                        .tag(idx)
                        .rotationEffect(.degrees(90))
                        .frame(width: pageHeight, height: pageWidth) // match rotated page exactly
                        .background(
                            Color.black
                                .allowsHitTesting(false)
                        )
                        .ignoresSafeArea()
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .rotationEffect(.degrees(-90))
                .frame(width: pageWidth, height: pageHeight) // match device screen exactly
                .background(
                    Color.black
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                )
                .ignoresSafeArea()

                // Floating Up/Down buttons
                VStack(spacing: 18) {
                    Button { pageUp() } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 64, height: 64)
                            .background(Color.green, in: Circle())
                            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 6)
                    }
                    .disabled(posts.isEmpty)

                    Button { pageDown() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 64, height: 64)
                            .background(Color.blue, in: Circle())
                            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 6)
                    }
                    .disabled(posts.isEmpty)
                }
                .padding(.leading, 24)
                .padding(.bottom, 112) // keep above tab bar comfortably
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(true) // buttons stay interactive
                .ignoresSafeArea(edges: [.top])
            }
        }
        .onAppear {
            if !wiredFirstPageCallbackForLoad {
                wiredFirstPageCallbackForLoad = true
                loadPosts()
            }
        }
        .background(
            Color.black
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
        .ignoresSafeArea()
        .navigationBarHidden(true)
        .preference(key: FeedReadyPreferenceKey.self, value: feedReady)
    }

    private func pageUp() {
        guard !posts.isEmpty else { return }
        let newIndex = max(0, selection - 1)
        if newIndex != selection { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        selection = newIndex
        incrementViewCountIfNeeded(for: selection)
    }

    private func pageDown() {
        guard !posts.isEmpty else { return }
        let newIndex = min(posts.count - 1, selection + 1)
        if newIndex != selection { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        selection = newIndex
        incrementViewCountIfNeeded(for: selection)
    }

    private func incrementViewCountIfNeeded(for index: Int) {
        guard posts.indices.contains(index) else { return }
        let post = posts[index]
        incrementViewCount(postID: post.id)
    }

    // MARK: - Readiness plumbing

    private func firstMediaPrepared() {
        if !didPrepareFirstMedia {
            didPrepareFirstMedia = true
            evaluateFeedReady()
        }
    }

    private func evaluateFeedReady() {
        // If no posts came back, consider ready once Firestore finished (avoid blocking)
        if didFinishFirestore && (didPrepareFirstMedia || posts.isEmpty) && !feedReady {
            feedReady = true
        }
    }

    // Existing Firestore loading
    func loadPosts() {
        let db = Firestore.firestore()
        db.collection("posts").getDocuments { snapshot, error in
            if let error = error {
                print("Error loading posts: \(error.localizedDescription)")
                self.posts = []
                self.didFinishFirestore = true
                self.evaluateFeedReady()
                return
            }
            guard let snapshot = snapshot else {
                self.posts = []
                self.didFinishFirestore = true
                self.evaluateFeedReady()
                return
            }

            let newPosts: [Post] = snapshot.documents.compactMap { document in
                let data = document.data()

                let latitude = (data["latitude"] as? Double)
                    ?? (data["latitude"] as? NSNumber)?.doubleValue
                let longitude = (data["longitude"] as? Double)
                    ?? (data["longitude"] as? NSNumber)?.doubleValue
                let radius = (data["radius"] as? Int)
                    ?? (data["radius"] as? NSNumber)?.intValue
                let viewCount = (data["viewCount"] as? Int)
                    ?? (data["viewCount"] as? NSNumber)?.intValue
                let mediaURL = data["mediaURL"] as? String ?? ""

                guard let lat = latitude, let lon = longitude else { return nil }

                return Post(
                    id: document.documentID,
                    latitude: lat,
                    longitude: lon,
                    mediaURL: mediaURL,
                    radius: radius ?? 0,
                    viewCount: viewCount ?? 0
                )
            }
            self.posts = newPosts
            // Reset to first when reloading
            self.selection = 0
            incrementViewCountIfNeeded(for: 0)

            // Firestore finished
            self.didFinishFirestore = true
            // If there are no posts, we can mark ready immediately
            // If there are posts, we will wait for the first media to prepare
            self.evaluateFeedReady()
        }
    }

    func incrementViewCount(postID: String) {
        let db = FirebaseFirestore.Firestore.firestore()
        let postRef = db.collection("posts").document(postID)

        postRef.updateData([
            "viewCount": FieldValue.increment(Int64(1))
        ]) { error in
            if let error = error {
                print("Failed to increment view count: \(error.localizedDescription)")
                return
            }
            checkAndIncreaseRadius(postRef: postRef)
        }
    }

    func checkAndIncreaseRadius(postRef: DocumentReference) {
        postRef.getDocument { document, error in
            if let error = error {
                print("Failed to fetch post for radius check: \(error.localizedDescription)")
                return
            }
            guard let document = document, document.exists, let data = document.data() else { return }

            let viewCount = (data["viewCount"] as? Int)
                ?? (data["viewCount"] as? NSNumber)?.intValue
                ?? 0
            var radius = (data["radius"] as? Int)
                ?? (data["radius"] as? NSNumber)?.intValue
                ?? 0

            if viewCount % 10 == 0 {
                radius += 1000
                postRef.updateData(["radius": radius]) { error in
                    if let error = error {
                        print("Failed to update radius: \(error.localizedDescription)")
                    } else {
                        // optional: update local state if you want to reflect radius changes
                    }
                }
            }
        }
    }
}

private struct FullScreenPostView: View {
    let post: Post
    let isActive: Bool
    // Optional readiness callback (only provided for the first page)
    var didPrepareMedia: (() -> Void)?
    // The size this rotated page should occupy (already swapped w/h by caller)
    let pageSize: CGSize

    var body: some View {
        ZStack {
            if isVideo(urlString: post.mediaURL) {
                VideoPage(urlString: post.mediaURL, play: isActive, onReady: didPrepareMedia)
                    .frame(width: pageSize.width, height: pageSize.height)
                    .clipped()
            } else {
                ImagePage(urlString: post.mediaURL, onReady: didPrepareMedia)
                    .frame(width: pageSize.width, height: pageSize.height)
                    .clipped()
            }
        }
        .frame(width: pageSize.width, height: pageSize.height)
        .background(Color.black.allowsHitTesting(false))
        .contentShape(Rectangle())
        .ignoresSafeArea()
        .allowsHitTesting(false) // page content isn't interactive; avoids stealing tab bar taps
    }

    private func isVideo(urlString: String) -> Bool {
        let lower = urlString.lowercased()
        return lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.contains("video")
    }
}

private struct ImagePage: View {
    let urlString: String
    var onReady: (() -> Void)?

    var body: some View {
        ZStack {
            if let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Color.black
                            .overlay(ProgressView().tint(.white))
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .ignoresSafeArea()
                            .onAppear { onReady?() }
                            .allowsHitTesting(false)
                    case .failure:
                        Color.black
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                            )
                            .ignoresSafeArea()
                            .onAppear { onReady?() }
                            .allowsHitTesting(false)
                    @unknown default:
                        Color.black
                            .ignoresSafeArea()
                            .onAppear { onReady?() }
                            .allowsHitTesting(false)
                    }
                }
                .allowsHitTesting(false)
            } else {
                Color.black
                    .ignoresSafeArea()
                    .onAppear { onReady?() }
                    .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - AVPlayerLayer-backed video view that fills (no letterboxing)

private struct ResizingVideoPlayer: UIViewRepresentable {
    final class PlayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var player: AVPlayer? {
            get { playerLayer.player }
            set { playerLayer.player = newValue }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
            playerLayer.videoGravity = .resizeAspectFill // critical: fill without letterboxing
        }
    }

    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let v = PlayerView()
        v.backgroundColor = .black
        v.playerLayer.videoGravity = .resizeAspectFill
        v.player = player
        return v
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        if uiView.player !== player {
            uiView.player = player
        }
        uiView.playerLayer.videoGravity = .resizeAspectFill
    }
}

private struct VideoPage: View {
    let urlString: String
    let play: Bool
    var onReady: (() -> Void)?

    @State private var player: AVPlayer?
    @State private var statusObserver: NSKeyValueObservation?

    var body: some View {
        ZStack {
            if let player {
                ResizingVideoPlayer(player: player)
                    .background(Color.black)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            } else {
                Color.black
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            // Do not prepare here; we defer to when play becomes true
            updatePlayback()
        }
        .onChange(of: play) { newValue in
            // Prepare player only when this page becomes active
            if newValue {
                preparePlayerIfNeeded()
            }
            updatePlayback()
        }
        .onDisappear {
            player?.pause()
            statusObserver?.invalidate()
            statusObserver = nil
        }
        .allowsHitTesting(false)
    }

    private func preparePlayerIfNeeded() {
        guard player == nil else { return }
        guard let url = URL(string: urlString) else {
            onReady?()
            return
        }
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer

        statusObserver = item.observe(\.status, options: [.initial, .new]) { _, _ in
            if item.status == .readyToPlay {
                onReady?()
                statusObserver?.invalidate()
                statusObserver = nil
            } else if item.status == .failed {
                onReady?()
                statusObserver?.invalidate()
                statusObserver = nil
            }
        }
    }

    private func updatePlayback() {
        if play {
            if player == nil {
                // Prepare JIT if needed
                preparePlayerIfNeeded()
            }
            player?.play()
        } else {
            player?.pause()
        }
    }
}

// MARK: - Readiness PreferenceKey for FeedView

struct FeedReadyPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
