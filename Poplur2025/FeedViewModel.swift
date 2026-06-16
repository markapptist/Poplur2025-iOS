import SwiftUI
import CoreLocation
import AVFoundation

@MainActor
final class FeedViewModel: ObservableObject {
    // MARK: - Published UI State
    @Published var posts: [FeedPost] = []
    @Published var isLoading: Bool = false
    @Published var isFeedReady: Bool = false
    @Published var currentIndex: Int = 0
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
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear1/prog_index.m3u8",
        "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/gear1/prog_index.m3u8",
        "https://media.w3.org/2010/05/sintel/trailer.mp4",
        "https://media.w3.org/2010/05/bunny/trailer.mp4",
        "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4",
        "https://download.samplelib.com/mp4/sample-10s.mp4",
        "https://download.samplelib.com/mp4/sample-15s.mp4"
    ]
    private let demoImageIDs: [Int] = [
        10, 20, 28, 37, 42, 58, 64, 82, 96, 102, 103, 106, 119, 128, 133, 164, 175, 184, 190, 1025
    ]
    private let demoUserIDs: [String] = [
        "na_user_alex",
        "na_user_jamie",
        "na_user_riley",
        "na_user_taylor",
        "na_user_casey"
    ]

    // Audio
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
            if popPlayer?.isPlaying != true {
                try session.setActive(false, options: [.notifyOthersOnDeactivation])
            }
        } catch {
            print("[Audio] deactivateAudioSessionIfPossible failed: \(error)")
        }
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
    private func demoImageURL(for index: Int) -> String {
        let imageID = demoImageIDs[index % demoImageIDs.count]
        return "https://picsum.photos/id/\(imageID)/1080/1920"
    }

    /// Keeps demo pages mixed between images, videos, and sponsored slots.
    func injectDemoVideos(into posts: inout [FeedPost]) {
        guard posts.isEmpty == false else { return }
        for i in posts.indices {
            let mediaURL: String
            let userID: String

            switch i % 5 {
            case 1, 4:
                mediaURL = demoVideoURLs[i % demoVideoURLs.count]
                userID = demoUserIDs[i % demoUserIDs.count]
            case 2:
                mediaURL = demoImageURL(for: i + 97)
                userID = "sponsored_ad_\(i)"
            default:
                mediaURL = demoImageURL(for: i)
                userID = posts[i].userID
            }

            posts[i] = FeedPost(
                id: posts[i].id,
                latitude: posts[i].latitude,
                longitude: posts[i].longitude,
                mediaURL: mediaURL,
                radius: posts[i].radius,
                viewCount: posts[i].viewCount,
                userID: userID
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
