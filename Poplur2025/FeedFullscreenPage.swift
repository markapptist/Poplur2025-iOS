import SwiftUI
import Foundation
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
        guard let url = URL(string: post.mediaURL) else { return nil }
        let lower = url.absoluteString.lowercased()
        let videoHints = [".mp4", ".m3u8", "/prog_index.m3u8", "video.mp4", "format=mp4", "format=hls", "type=video"]
        return videoHints.contains { lower.contains($0) } ? url : nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let videoURL = directVideoURL {
                FeedInlineVideoPlayer(url: videoURL)
                    .ignoresSafeArea()
            } else if let url = URL(string: post.mediaURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Color.black
                            ProgressView()
                                .tint(.white)
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
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
                            Image(systemName: "person.fill")
                                .foregroundStyle(.white)
                        )
                }
                .buttonStyle(.plain)

                Text(displayName.isEmpty ? "" : displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(16)
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
}

private struct FeedInlineVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var endObserver: Any?

    var body: some View {
        ZStack {
            Color.black
            ProgressView()
                .tint(.white)
            VideoPlayer(player: player)
        }
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
