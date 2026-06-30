import SwiftUI
import Foundation
import AVFoundation
import AVKit
import CoreLocation

struct FeedPost: Identifiable, Hashable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    let mediaURL: String
    let radius: Double
    var viewCount: Int
    let userID: String
    
    // Location metadata for enhanced map display
    var cityName: String? = nil
    var countryName: String? = nil
    var countryFlag: String? = nil
    var sourceLanguageCode: String = PoplurLanguage.english.rawValue

    // Poplur-owned creative slots. These are rendered like posts so generated
    // video URLs can drop into the feed without a separate ad surface.
    var isPoplurAd: Bool = false
    var adHeadline: String? = nil
    var adBody: String? = nil
    var adCallToAction: String? = nil
    var adCreativeKind: String? = nil
    var adStorageProvider: String? = nil
    var adDriveFileID: String? = nil

    // Live broadcasts are feed posts with location/radius metadata. A real backend
    // can replace the demo stream URL while keeping the feed filtering contract.
    var isLiveStream: Bool = false
    var liveLocationName: String? = nil
    var liveStartedAt: Date? = nil
    var liveRadiusMeters: Double? = nil
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Equatable conformance
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

struct LiveBroadcastLocation: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

final class LiveVideoSessionStore: ObservableObject {
    static let shared = LiveVideoSessionStore()

    static let defaultLocationChoices: [LiveBroadcastLocation] = [
        LiveBroadcastLocation(id: "austin", title: "Austin", subtitle: "Downtown live radius", latitude: 30.2672, longitude: -97.7431, radiusMeters: 350_000),
        LiveBroadcastLocation(id: "toronto", title: "Toronto", subtitle: "City center broadcast", latitude: 43.6532, longitude: -79.3832, radiusMeters: 700_000),
        LiveBroadcastLocation(id: "new-york", title: "New York", subtitle: "Metro live channel", latitude: 40.7128, longitude: -74.0060, radiusMeters: 650_000),
        LiveBroadcastLocation(id: "los-angeles", title: "Los Angeles", subtitle: "West coast live channel", latitude: 34.0522, longitude: -118.2437, radiusMeters: 800_000),
        LiveBroadcastLocation(id: "london", title: "London", subtitle: "Central city broadcast", latitude: 51.5074, longitude: -0.1278, radiusMeters: 650_000)
    ]

    @Published private(set) var sessions: [FeedPost]
    private(set) var localSessionID: String?

    private init() {
        sessions = Self.seededSessions
    }

    @discardableResult
    func startLocalSession(at location: LiveBroadcastLocation, viewerCount: Int) -> FeedPost {
        if let localSessionID {
            sessions.removeAll { $0.id == localSessionID }
        }

        let sessionID = "local_live_\(Int(Date().timeIntervalSince1970))"
        let post = FeedPost(
            id: sessionID,
            latitude: location.latitude,
            longitude: location.longitude,
            mediaURL: "live://poplur/local/\(sessionID)",
            radius: location.radiusMeters,
            viewCount: max(viewerCount, 1),
            userID: "demo-live-user",
            cityName: location.title,
            countryName: location.subtitle,
            countryFlag: nil,
            sourceLanguageCode: PoplurLanguage.english.rawValue,
            isLiveStream: true,
            liveLocationName: location.title,
            liveStartedAt: Date(),
            liveRadiusMeters: location.radiusMeters
        )
        localSessionID = sessionID
        sessions.insert(post, at: 0)
        return post
    }

    func stopLocalSession() {
        guard let localSessionID else { return }
        sessions.removeAll { $0.id == localSessionID }
        self.localSessionID = nil
    }

    func updateLocalViewerCount(_ viewerCount: Int) {
        guard let localSessionID,
              let index = sessions.firstIndex(where: { $0.id == localSessionID }) else { return }
        sessions[index].viewCount = max(viewerCount, 1)
    }

    func visibleSessions(
        near coordinate: CLLocationCoordinate2D?,
        viewerRadius: Double,
        start: Int,
        count: Int
    ) -> [FeedPost] {
        guard count > 0 else { return [] }
        let candidates = sessions.filter { post in
            if post.id == localSessionID { return true }
            guard let coordinate else { return true }
            return Self.radiiIntersect(
                firstLatitude: coordinate.latitude,
                firstLongitude: coordinate.longitude,
                firstRadius: max(viewerRadius, 1_000),
                secondLatitude: post.latitude,
                secondLongitude: post.longitude,
                secondRadius: post.liveRadiusMeters ?? post.radius
            )
        }
        let end = min(start + count, candidates.count)
        guard start < end else { return [] }
        return Array(candidates[start..<end])
    }

    private static let seededSessions: [FeedPost] = [
        livePost(id: "seed_live_austin", title: "Austin Live", location: defaultLocationChoices[0], viewers: 214),
        livePost(id: "seed_live_toronto", title: "Toronto Live", location: defaultLocationChoices[1], viewers: 188),
        livePost(id: "seed_live_new_york", title: "New York Live", location: defaultLocationChoices[2], viewers: 241),
        livePost(id: "seed_live_los_angeles", title: "Los Angeles Live", location: defaultLocationChoices[3], viewers: 176)
    ]

    private static func livePost(id: String, title: String, location: LiveBroadcastLocation, viewers: Int) -> FeedPost {
        FeedPost(
            id: id,
            latitude: location.latitude,
            longitude: location.longitude,
            mediaURL: "live://poplur/remote/\(id)",
            radius: location.radiusMeters,
            viewCount: viewers,
            userID: id.replacingOccurrences(of: "seed_", with: ""),
            cityName: location.title,
            countryName: location.subtitle,
            countryFlag: nil,
            sourceLanguageCode: PoplurLanguage.english.rawValue,
            isLiveStream: true,
            liveLocationName: title,
            liveStartedAt: Date().addingTimeInterval(-Double(viewers * 5)),
            liveRadiusMeters: location.radiusMeters
        )
    }

    private static func radiiIntersect(
        firstLatitude: Double,
        firstLongitude: Double,
        firstRadius: Double,
        secondLatitude: Double,
        secondLongitude: Double,
        secondRadius: Double
    ) -> Bool {
        distanceMeters(
            firstLatitude,
            firstLongitude,
            secondLatitude,
            secondLongitude
        ) <= firstRadius + secondRadius
    }

    private static func distanceMeters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

struct FeedFullscreenPage: View {
    let post: FeedPost
    let displayName: String
    let onUserTapped: (String) -> Void

    private var directVideoURL: URL? {
        guard !post.isLiveStream else { return nil }
        guard localAssetName == nil else { return nil }
        guard let url = URL(string: post.mediaURL) else { return nil }
        let lower = url.absoluteString.lowercased()
        if lower.contains("picsum.photos") { return nil }
        let videoHints = [".mp4", ".m3u8", "/prog_index.m3u8", "video.mp4", "format=mp4", "format=hls", "type=video"]
        return videoHints.contains { lower.contains($0) } ? url : nil
    }

    private var localAssetName: String? {
        let prefix = "asset://"
        guard post.mediaURL.hasPrefix(prefix) else { return nil }
        let name = String(post.mediaURL.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if post.isLiveStream {
                FeedLiveStreamCard(post: post, displayName: displayName)
                    .ignoresSafeArea()
            } else if let videoURL = directVideoURL {
                FeedInlineVideoPlayer(url: videoURL)
                    .ignoresSafeArea()
            } else if let assetName = localAssetName, let image = UIImage(named: assetName) {
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
            } else if let url = URL(string: post.mediaURL) {
                GeometryReader { geo in
                    FeedAsyncImage(url: url, size: geo.size, placeholder: placeholder)
                }
            } else {
                placeholder
            }
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 10) {
                Button {
                    onUserTapped(post.userID)
                } label: {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: post.isPoplurAd ? "megaphone.fill" : "person.fill")
                                .poplurIconShader()
                                .foregroundStyle(.white)
                        )
                }
                .buttonStyle(.plain)

                Text(post.isPoplurAd ? "Poplur Ad" : (displayName.isEmpty ? "" : displayName))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .poplurMetalNumberShader(intensity: 0.75)
            }
            .padding(16)
        }
        .overlay(alignment: .bottomLeading) {
            if post.isPoplurAd {
                poplurAdCopy
                    .padding(.horizontal, 22)
                    .padding(.bottom, 118)
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.black
            Image(systemName: directVideoURL != nil ? "play.slash.fill" : "photo")
                .poplurIconShader()
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var poplurAdCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.adCreativeKind?.uppercased() ?? "AI CREATIVE")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .poplurMetalNumberShader(intensity: 0.65)

            Text(post.adHeadline ?? "See what is happening nearby")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .poplurMetalNumberShader(intensity: 1.0)

            if let body = post.adBody, !body.isEmpty {
                Text(body)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(3)
                    .poplurMetalNumberShader(intensity: 0.65)
            }

            Text(post.adCallToAction ?? "Open Poplur")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .poplurMetalNumberShader(intensity: 0.7)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color.white, in: Capsule())
                .padding(.top, 4)
        }
        .shadow(color: .black.opacity(0.55), radius: 10, x: 0, y: 4)
        .allowsHitTesting(false)
    }
}

struct FeedLiveStreamCard: View {
    let post: FeedPost
    let displayName: String
    @State private var pulse = false

    private var radiusText: String {
        let radius = post.liveRadiusMeters ?? post.radius
        if radius >= 1_000_000 {
            return String(format: "%.1fM m radius", radius / 1_000_000)
        }
        if radius >= 1_000 {
            return String(format: "%.0fk m radius", radius / 1_000)
        }
        return "\(Int(radius)) m radius"
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.01, green: 0.02, blue: 0.03),
                    Color(red: 0.09, green: 0.01, blue: 0.03),
                    Color(red: 0.01, green: 0.08, blue: 0.07)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .stroke(Color.red.opacity(0.32 - Double(index) * 0.07), lineWidth: 2)
                    .frame(width: CGFloat(130 + index * 58), height: CGFloat(130 + index * 58))
                    .scaleEffect(pulse ? 1.18 : 0.86)
                    .opacity(pulse ? 0.22 : 0.72)
                    .animation(
                        .easeInOut(duration: 1.25)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.18),
                        value: pulse
                    )
            }

            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 11, height: 11)
                        .shadow(color: .red.opacity(0.9), radius: 10)

                    Text("LIVE")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .poplurMetalNumberShader(intensity: 1.1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.42), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))

                Text(displayName.isEmpty ? post.liveLocationName ?? "Poplur Live" : displayName)
                    .font(.system(size: 38, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: 460)
                    .poplurMetalNumberShader(intensity: 1.05)

                Text(post.cityName ?? post.liveLocationName ?? "Live channel")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .poplurMetalNumberShader(intensity: 0.7)

                Text("\(post.viewCount) watching - \(radiusText)")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                    .foregroundStyle(Color(red: 0.36, green: 1.0, blue: 0.42))
                    .poplurMetalNumberShader(intensity: 0.9)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.36), in: Capsule())
            }
            .padding(.horizontal, 26)
            .shadow(color: .black.opacity(0.55), radius: 18, x: 0, y: 8)
        }
        .onAppear { pulse = true }
    }
}

private struct FeedInlineVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var endObserver: Any?

    var body: some View {
        ZStack {
            Color.black
            if let player {
                AspectFillInlinePlayer(player: player)
                    .transition(.opacity)
            }
        }
        .animation(.easeIn(duration: 0.25), value: player != nil)
            .clipped()
            .onAppear {
                let nextPlayer = AVPlayer(url: url)
                player = nextPlayer
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: nextPlayer.currentItem,
                    queue: .main
                ) { _ in
                    NotificationCenter.default.post(name: .FeedAdvanceToNextPost, object: nil)
                }
                nextPlayer.play()
            }
            .onDisappear {
                if let endObserver {
                    NotificationCenter.default.removeObserver(endObserver)
                    self.endObserver = nil
                }
                player?.pause()
                player = nil
            }
    }
}

private struct AspectFillInlinePlayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> AspectFillInlinePlayerView {
        let view = AspectFillInlinePlayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = .resizeAspectFill
        view.player = player
        return view
    }

    func updateUIView(_ uiView: AspectFillInlinePlayerView, context: Context) {
        uiView.player = player
        uiView.playerLayer.videoGravity = .resizeAspectFill
        uiView.setNeedsLayout()
    }
}

/// Loads a remote image and fades it in over a black background — no spinner.
private struct FeedAsyncImage: View {
    let url: URL
    let size: CGSize
    let placeholder: AnyView

    @State private var loadedImage: UIImage?
    @State private var failed = false

    init(url: URL, size: CGSize, placeholder: some View) {
        self.url = url
        self.size = size
        self.placeholder = AnyView(placeholder)
    }

    var body: some View {
        ZStack {
            Color.black
            if let img = loadedImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .transition(.opacity)
            } else if failed {
                placeholder
                    .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeIn(duration: 0.35), value: loadedImage != nil)
        .task(id: url.absoluteString) {
            loadedImage = nil
            failed = false
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled, let img = UIImage(data: data) else { return }
                await MainActor.run {
                    loadedImage = img
                }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { failed = true }
            }
        }
    }
}

private final class AspectFillInlinePlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        playerLayer.videoGravity = .resizeAspectFill
    }
}

#Preview {
    let sample = FeedPost(
        id: "demo",
        latitude: 37.3349,
        longitude: -122.0090,
        mediaURL: "https://picsum.photos/800/1200",
        radius: 3000,
        viewCount: 42,
        userID: "user_123",
        cityName: "San Jose",
        countryName: "USA",
        countryFlag: "🇺🇸"
    )
    return FeedFullscreenPage(post: sample, displayName: "Sample User") { _ in }
}
