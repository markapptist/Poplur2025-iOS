import SwiftUI
import CoreLocation
import AVFoundation

final class FeedViewModel: ObservableObject {
    // MARK: - Published UI State
    @Published var posts: [FeedPost] = []
    @Published var isLoading: Bool = false
    @Published var isFeedReady: Bool = false
    @Published var currentIndex: Int = 0
    @Published var showStatic: Bool = false
    @Published var navigateToProfile: Bool = false
    @Published var selectedUserID: String? = nil
    @Published var usernames: [String: String] = [:]

    // Pagination
    @Published var lastDocument: Any? = nil // Placeholder to avoid Firestore dependency here
    @Published var isLoadingMore: Bool = false
    @Published var reachedEnd: Bool = false

    // Country paging
    @Published var selectedCountryIndex: Int = 0
    let countries: [(code: String, name: String, flag: String)]

    // Services
    // Demo content
    private let demoVideoURLs: [String] = [
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
        "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4"
    ]
    private let demoUserIDs: [String] = [
        "na_user_alex",
        "na_user_jamie",
        "na_user_riley",
        "na_user_taylor",
        "na_user_casey"
    ]

    // Audio
    private var staticPlayer: AVAudioPlayer? = nil
    private var popPlayer: AVAudioPlayer? = nil

    // Caches
    private var usernameLoadsInProgress: Set<String> = []

    // Config
    let pageSize: Int = 5

    init(countries: [(code: String, name: String, flag: String)], ) {
        self.countries = countries
       
    }
}

// MARK: - Audio helpers
extension FeedViewModel {
    func activateAmbientAudioSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            if session.isOtherAudioPlaying == false {
                try session.setActive(true, options: [])
            }
        } catch {
            print("[Audio] activateAmbientAudioSessionIfNeeded failed: \(error)")
        }
    }

    func deactivateAudioSessionIfPossible() {
        let session = AVAudioSession.sharedInstance()
        do {
            if (staticPlayer?.isPlaying != true) && (popPlayer?.isPlaying != true) {
                try session.setActive(false, options: [.notifyOthersOnDeactivation])
            }
        } catch {
            print("[Audio] deactivateAudioSessionIfPossible failed: \(error)")
        }
    }

    func playStaticSound() {
        activateAmbientAudioSessionIfNeeded()
        guard staticPlayer == nil || staticPlayer?.isPlaying == false else { return }
        guard let url = Bundle.main.url(forResource: "pop", withExtension: "mp3") ?? Bundle.main.url(forResource: "pop", withExtension: "wav") else {
            print("[StaticSound] pop.(mp3|wav) not found in bundle")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0.8
            player.prepareToPlay()
            player.play()
            staticPlayer = player
            try? AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[StaticSound] Failed to play: \(error)")
        }
    }

    func stopStaticSound() {
        staticPlayer?.stop()
        staticPlayer = nil
        deactivateAudioSessionIfPossible()
    }

    func playOneShotPop() {
        activateAmbientAudioSessionIfNeeded()
        guard let url = Bundle.main.url(forResource: "pop", withExtension: "mp3") ?? Bundle.main.url(forResource: "pop", withExtension: "wav") else {
            print("[PopSound] pop.(mp3|wav) not found in bundle")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.volume = 0.9
            player.prepareToPlay()
            player.play()
            popPlayer = player
            try? AVAudioSession.sharedInstance().setActive(true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.popPlayer?.stop()
                self?.popPlayer = nil
                self?.deactivateAudioSessionIfPossible()
            }
        } catch {
            print("[PopSound] Failed to play: \(error)")
        }
    }
}


// MARK: - Username helpers
extension FeedViewModel {
    func displayName(for post: FeedPost) -> String {
        if let name = usernames[post.userID], !name.isEmpty { return name }
        if post.userID.hasPrefix("fake_") || post.userID.hasPrefix("na_user_") || post.userID.hasPrefix("world_user_") {
            return post.userID.replacingOccurrences(of: "_", with: " ").uppercased()
        }
        let short = post.userID.prefix(6)
        return "User \(short)"
    }

    func maybeResolveUsername(for uid: String) {
        if usernames[uid] != nil || usernameLoadsInProgress.contains(uid) { return }
        usernameLoadsInProgress.insert(uid)
        Task {
            let name = await UsernameCache.shared.username(for: uid)
            await MainActor.run {
                if let name, !name.isEmpty { self.usernames[uid] = name }
                self.usernameLoadsInProgress.remove(uid)
            }
        }
    }

    func prefetchVisibleUsernames() {
        if posts.indices.contains(currentIndex) {
            let uid = posts[currentIndex].userID
            maybeResolveUsername(for: uid)
        }
    }
}

// MARK: - Demo video injection
extension FeedViewModel {
    /// Mutates a subset of posts to use demo video URLs and plausible social-style user IDs.
    func injectDemoVideos(into posts: inout [FeedPost]) {
        guard posts.isEmpty == false else { return }
        // Choose every 2nd post as a demo video to keep a mixed feed look.
        for i in posts.indices where i % 2 == 0 {
            guard let url = demoVideoURLs.randomElement() else { continue }
            let user = demoUserIDs.randomElement() ?? posts[i].userID
            posts[i] = FeedPost(
                id: posts[i].id,
                latitude: posts[i].latitude,
                longitude: posts[i].longitude,
                mediaURL: url,
                radius: posts[i].radius,
                viewCount: posts[i].viewCount,
                userID: user
            )
        }
    }
}

// MARK: - Loading posts (local demo logic)
extension FeedViewModel {
    func reload(generate: (Int, Int) -> [FeedPost]) async {
        await MainActor.run {
            isLoading = true
            reachedEnd = false
            lastDocument = nil
            posts.removeAll()
            currentIndex = 0
        }

        // Simulate a short delay for loading
        try? await Task.sleep(nanoseconds: 250_000_000)
        var mixed = generate(0, pageSize)
        injectDemoVideos(into: &mixed)

        await MainActor.run {
            posts = mixed
            isLoading = false
            reachedEnd = mixed.isEmpty
            prefetchVisibleUsernames()
        }
    }
}
