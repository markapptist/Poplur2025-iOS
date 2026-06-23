import SwiftUI
import AVKit
import AVFoundation

public struct FeedVideoView: View {
    public let url: URL
    public let aspectRatio: CGFloat? // pass nil to fill container; or provide e.g. 9/16

    @State private var player: AVPlayer?
    @State private var item: AVPlayerItem?
    @State private var ready: Bool = false
    @State private var loadTask: Task<Void, Never>?

    @State private var statusObserver: NSKeyValueObservation?
    @State private var endObserver: Any?

    public init(url: URL, aspectRatio: CGFloat? = nil) {
        self.url = url
        self.aspectRatio = aspectRatio
    }

    public var body: some View {
        ZStack {
            Color.black
            if let player {
                VideoPlayer(player: player)
                    .onAppear { /* playback controlled by FeedAudioManager */ }
                    .onDisappear { player.pause() }
                    .modifier(AspectFillModifier(aspectRatio: aspectRatio))
                    .opacity(ready ? 1 : 0)
                    .animation(.easeIn(duration: 0.18), value: ready)
            }
        }
        .clipped()
        .onAppear { startLoadingIfNeeded() }
        .onDisappear { teardown() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PauseGlobalFeedAudio"))) { _ in
            print("[FeedVideoView] PauseGlobalFeedAudio received — tearing down")
            teardown()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            player?.pause()
        }
    }

    private func startLoadingIfNeeded() {
        guard player == nil else { return }
        loadTask?.cancel()

        let isRemote = (url.scheme?.lowercased().hasPrefix("http") == true)

        loadTask = Task { @MainActor in
            if !isRemote {
                // Local: wait briefly for file to exist and be non-empty
                var attempts = 0
                while attempts < 6 {
                    let exists = FileManager.default.fileExists(atPath: url.path)
                    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
                    if exists && size > 0 { break }
                    attempts += 1
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
            }

            // Build asset with network-friendly options
            let assetOptions: [String: Any] = [
                "AVURLAssetAllowsCellularAccessKey": true,
                "AVURLAssetAllowsConstrainedNetworkAccessKey": true
            ]
            let asset = AVURLAsset(url: url, options: assetOptions)

            // Load keys asynchronously with a timeout
            let keysLoaded = await withTaskGroup(of: Bool.self) { group -> Bool in
                group.addTask {
                    do {
                        let (isPlayable, _, _) = try await asset.load(.isPlayable, .tracks, .duration)
                        return isPlayable
                    } catch {
                        print("[FeedVideoView] asset load failed: \(error)")
                        return false
                    }
                }
                group.addTask {
                    // Timeout after 5 seconds
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    return false
                }
                for await result in group {
                    if result { group.cancelAll(); return true }
                }
                return false
            }

            guard keysLoaded else {
                print("[FeedVideoView] Asset keys not loaded or not playable: \(url)")
                self.handleFailure()
                return
            }

            // Create item/player from the verified asset
            let item = AVPlayerItem(asset: asset)
            self.item = item
            let p = AVPlayer(playerItem: item)
            p.automaticallyWaitsToMinimizeStalling = true
            self.player = p
            FeedAudioManager.shared.register(p)

            // Observe status changes
            self.statusObserver = item.observe(\.status, options: [.initial, .new]) { _, _ in
                DispatchQueue.main.async {
                    self.handleStatusChange(item)
                }
            }

            // Observe failure to play to end
            self.endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { notif in
                let err = (notif.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError)
                print("[FeedVideoView] FailedToPlayToEnd: \(String(describing: err))")
                Task { @MainActor in self.handleFailure() }
            }
        }
    }

    @MainActor
    private func handleStatusChange(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            self.ready = true
            if let p = self.player {
                FeedAudioManager.shared.playExclusively(p)
            }
        case .failed:
            print("[FeedVideoView] Item failed: \(String(describing: item.error))")
            if let underlying = (item.error as NSError?)?.userInfo[NSUnderlyingErrorKey] {
                print("[FeedVideoView] Underlying: \(underlying)")
            }
            self.handleFailure()
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    @MainActor
    private func handleFailure() {
        teardown()
        // Optionally: you can emit a notification or callback here to show a placeholder
    }

    private func teardown() {
        loadTask?.cancel()
        statusObserver?.invalidate()
        statusObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil

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
