import SwiftUI
import AVFoundation
import AVKit

/// A full-screen, aspectFill, looping, muted video view.
/// Use `isActive` to control when playback should run (e.g., only on the visible page).
struct FullscreenVideoView: View {
    let url: URL
    @Binding var isActive: Bool
    let isMuted: Bool
    let shouldLoop: Bool

    @State private var player: AVQueuePlayer = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?
    @State private var item: AVPlayerItem?

    init(url: URL, isActive: Binding<Bool>, isMuted: Bool = true, shouldLoop: Bool = true) {
        self.url = url
        self._isActive = isActive
        self.isMuted = isMuted
        self.shouldLoop = shouldLoop
    }

    var body: some View {
        VideoPlayerContainer(player: player)
            .onAppear {
                configurePlayer()
                updatePlayback()
            }
            .onChange(of: isActive) { _ in
                updatePlayback()
            }
            .onDisappear {
                player.pause()
                player.removeAllItems()
                looper = nil
                item = nil
            }
            .ignoresSafeArea()
    }

    private func configurePlayer() {
        // If already configured for this URL, skip
        if let current = item, let asset = current.asset as? AVURLAsset, asset.url == url {
            player.isMuted = isMuted
            return
        }

        let asset = AVURLAsset(url: url)
        let newItem = AVPlayerItem(asset: asset)
        item = newItem

        if shouldLoop {
            let queue = AVQueuePlayer()
            player = queue
            looper = AVPlayerLooper(player: queue, templateItem: newItem)
        } else {
            player.replaceCurrentItem(with: newItem)
        }

        player.isMuted = isMuted
        player.actionAtItemEnd = .none
        player.automaticallyWaitsToMinimizeStalling = true
    }

    private func updatePlayback() {
        if isActive {
            player.play()
        } else {
            player.pause()
        }
    }
}

/// A UIViewControllerRepresentable that hosts an AVPlayerLayer set to aspectFill.
private struct VideoPlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspectFill
        vc.view.backgroundColor = .black
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        vc.player = player
        vc.videoGravity = .resizeAspectFill
    }
}
