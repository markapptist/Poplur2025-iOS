import SwiftUI
import AVKit
import FirebaseFirestore

struct FeedView: View {
    @State private var posts: [Post] = []
    @State private var selection: Int = 0
    // Readiness for HomeView’s preloader
    @State private var feedReady = false

    var body: some View {
        ZStack {
            if posts.isEmpty {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.ignoresSafeArea())
            } else {
                // Vertical paging using rotation trick (works back to iOS 16)
                TabView(selection: $selection) {
                    ForEach(posts.indices, id: \.self) { idx in
                        FullScreenPostView(post: posts[idx], isActive: selection == idx)
                            .tag(idx)
                            .rotationEffect(.degrees(90))  // rotate content
                            .frame(width: UIScreen.main.bounds.height, height: UIScreen.main.bounds.width)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .rotationEffect(.degrees(-90)) // rotate the TabView to make it vertical
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
                .background(Color.black)
                .ignoresSafeArea()

                // Floating Up/Down buttons
                VStack(spacing: 18) {
                    Button {
                        pageUp()
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 64, height: 64)
                            .background(Color.green, in: Circle())
                            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 6)
                    }
                    .disabled(posts.isEmpty)

                    Button {
                        pageDown()
                    } label: {
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
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .allowsHitTesting(true)
            }
        }
        .onAppear {
            loadPosts()
        }
        .background(Color.black)                // keep the whole tab dark/transparent-friendly
        .toolbarBackground(.hidden, for: .tabBar)
        .toolbar(.visible, for: .tabBar)
        // Publish readiness once loading has completed (success or failure)
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

    // Existing Firestore loading
    func loadPosts() {
        let db = Firestore.firestore()
        db.collection("posts").getDocuments { snapshot, error in
            defer {
                // Signal readiness regardless of success/failure to avoid blocking
                feedReady = true
            }

            if let error = error {
                print("Error loading posts: \(error.localizedDescription)")
                return
            }
            guard let snapshot = snapshot else {
                self.posts = []
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
        }
    }

    func incrementViewCount(postID: String) {
        let db = Firestore.firestore()
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
                        // optional: you could update local state if you need to reflect radius changes in UI
                    }
                }
            }
        }
    }
}

private struct FullScreenPostView: View {
    let post: Post
    let isActive: Bool

    var body: some View {
        ZStack {
            if isVideo(urlString: post.mediaURL) {
                VideoPage(urlString: post.mediaURL, play: isActive)
            } else {
                ImagePage(urlString: post.mediaURL)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
    }

    private func isVideo(urlString: String) -> Bool {
        let lower = urlString.lowercased()
        return lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.contains("video")
    }
}

private struct ImagePage: View {
    let urlString: String

    var body: some View {
        GeometryReader { geo in
            if let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        Color.black
                            .overlay(ProgressView().tint(.white))
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    case .failure:
                        Color.black
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(.white.opacity(0.6))
                            )
                    @unknown default:
                        Color.black
                    }
                }
            } else {
                Color.black
            }
        }
        .ignoresSafeArea()
    }
}

private struct VideoPage: View {
    let urlString: String
    let play: Bool
    @State private var player: AVPlayer?

    var body: some View {
        GeometryReader { geo in
            VideoPlayer(player: player)
                .onAppear {
                    if player == nil, let url = URL(string: urlString) {
                        player = AVPlayer(url: url)
                    }
                    if play { player?.play() } else { player?.pause() }
                }
                .onChange(of: play) { newValue in
                    if newValue { player?.play() } else { player?.pause() }
                }
                .onDisappear {
                    player?.pause()
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}
