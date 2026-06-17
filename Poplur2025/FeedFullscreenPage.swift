import SwiftUI
import Foundation
import AVFoundation
import AVKit

struct FeedPost: Identifiable, Hashable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    let mediaURL: String
    let radius: Double
    let viewCount: Int
    let userID: String
    
    // Location metadata for enhanced map display
    var cityName: String? = nil
    var countryName: String? = nil
    var countryFlag: String? = nil

    // Poplur-owned creative slots. These are rendered like posts so generated
    // video URLs can drop into the feed without a separate ad surface.
    var isPoplurAd: Bool = false
    var adHeadline: String? = nil
    var adBody: String? = nil
    var adCallToAction: String? = nil
    var adCreativeKind: String? = nil
    var adStorageProvider: String? = nil
    var adDriveFileID: String? = nil
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Equatable conformance
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

struct FeedFullscreenPage: View {
    let post: FeedPost
    let displayName: String
    let onUserTapped: (String) -> Void

    private var directVideoURL: URL? {
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

            if let videoURL = directVideoURL {
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
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ZStack {
                                Color.black
                                ProgressView()
                                    .tint(.white)
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        case .failure:
                            placeholder
                                .frame(width: geo.size.width, height: geo.size.height)
                        @unknown default:
                            placeholder
                                .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
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
                                .foregroundStyle(.white)
                        )
                }
                .buttonStyle(.plain)

                Text(post.isPoplurAd ? "Poplur Ad" : (displayName.isEmpty ? "" : displayName))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
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
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private var poplurAdCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.adCreativeKind?.uppercased() ?? "AI CREATIVE")
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))

            Text(post.adHeadline ?? "See what is happening nearby")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)

            if let body = post.adBody, !body.isEmpty {
                Text(body)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(3)
            }

            Text(post.adCallToAction ?? "Open Poplur")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Color.white, in: Capsule())
                .padding(.top, 4)
        }
        .shadow(color: .black.opacity(0.55), radius: 10, x: 0, y: 4)
        .allowsHitTesting(false)
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
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
            .clipped()
            .onAppear {
                let nextPlayer = AVPlayer(url: url)
                nextPlayer.actionAtItemEnd = .none
                player = nextPlayer
                endObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: nextPlayer.currentItem,
                    queue: .main
                ) { _ in
                    nextPlayer.seek(to: .zero)
                    nextPlayer.play()
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
