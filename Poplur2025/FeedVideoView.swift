import SwiftUI
import AVKit

public struct FeedVideoView: View {
    public let url: URL
    public let aspectRatio: CGFloat? // pass nil to fill container; or provide e.g. 9/16

    @State private var player: AVPlayer?
    @State private var item: AVPlayerItem?
    @State private var ready: Bool = false
    @State private var loadTask: Task<Void, Never>?

    public init(url: URL, aspectRatio: CGFloat? = nil) {
        self.url = url
        self.aspectRatio = aspectRatio
    }

    public var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
                    .onAppear { if ready { player.play() } }
                    .onDisappear { player.pause() }
                    .modifier(AspectFillModifier(aspectRatio: aspectRatio))
            } else {
                ProgressView().tint(.white)
            }
        }
        .clipped()
        .onAppear { startLoadingIfNeeded() }
        .onDisappear { teardown() }
    }

    private func startLoadingIfNeeded() {
        guard player == nil else { return }
        loadTask?.cancel()
        loadTask = Task { @MainActor in
            // Ensure file exists and is non-empty
            var attempts = 0
            while attempts < 6 {
                let exists = FileManager.default.fileExists(atPath: url.path)
                let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                if exists && size > 0 { break }
                attempts += 1
                try? await Task.sleep(nanoseconds: 150_000_000)
            }

            let item = AVPlayerItem(url: url)
            self.item = item
            let p = AVPlayer(playerItem: item)
            self.player = p

            // Wait for readyToPlay
            var checks = 0
            while checks < 30 && item.status != .readyToPlay {
                try? await Task.sleep(nanoseconds: 50_000_000)
                checks += 1
            }
            self.ready = (item.status == .readyToPlay)
            if self.ready { p.play() }
        }
    }

    private func teardown() {
        loadTask?.cancel()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        item = nil
        ready = false
    }
}

private struct AspectFillModifier: ViewModifier {
    let aspectRatio: CGFloat?
    func body(content: Content) -> some View {
        if let ratio = aspectRatio {
            content
                .aspectRatio(ratio, contentMode: .fill)
        } else {
            content
                .scaledToFill()
        }
    }
}

#Preview {
    FeedVideoView(url: URL(fileURLWithPath: "/path/to/local/video.mp4"), aspectRatio: 9/16)
        .frame(height: 300)
        .background(Color.black)
}
