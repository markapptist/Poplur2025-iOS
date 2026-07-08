import SwiftUI
import AVFoundation

// MARK: – Duration constant shared with FeedView
let kCommercialTransitionDuration: TimeInterval = 1.5

// MARK: – Channel/video-change transition (plays commercial_transition.mp4)
struct PoplurTransitionFlash: View {
    let channelNumber: Int
    let channelCategory: String
    var channelIconAssetName: String? = nil
    var channelEmoji: String = "📺"

    init(channelNumber: Int, channelCategory: String = "Poplur TV", channelIconAssetName: String? = nil, channelEmoji: String = "📺") {
        self.channelNumber = channelNumber
        self.channelCategory = channelCategory
        self.channelIconAssetName = channelIconAssetName
        self.channelEmoji = channelEmoji
    }

    var body: some View {
        ZStack {
            CommercialTransitionVideoView()
                .ignoresSafeArea()

            // Channel logo centered on the static
            VStack(spacing: 8) {
                ChannelAssetIcon(
                    assetName: channelIconAssetName,
                    fallbackEmoji: channelEmoji,
                    size: 80,
                    fallbackFontSize: 64
                )
                .shadow(color: .black.opacity(0.7), radius: 12, x: 0, y: 4)

                Text("CH \(channelNumber)")
                    .font(.system(size: 18, weight: .black, design: .monospaced))
                    .foregroundStyle(Color(red: 0.31, green: 1.0, blue: 0.25))
                    .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 2)

                Text(channelCategory.uppercased())
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.7), radius: 4, x: 0, y: 1)
                    .tracking(1.5)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: – Commercial transition video (one-shot, auto-fades)

private struct CommercialTransitionVideoView: UIViewRepresentable {
    func makeUIView(context: Context) -> CommercialTransitionUIView { CommercialTransitionUIView() }
    func updateUIView(_ uiView: CommercialTransitionUIView, context: Context) {}
}

private final class CommercialTransitionUIView: UIView {
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?

    init() {
        super.init(frame: .zero)
        backgroundColor = .black
        // commercial_transition first; fall back to feed_end_transition
        let url = Bundle.main.url(forResource: "commercial_transition", withExtension: "mp4")
               ?? Bundle.main.url(forResource: "feed_end_transition",   withExtension: "mp4")
        guard let url else { return }

        let player = AVPlayer(url: url)
        player.isMuted = false
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        self.player = player
        self.playerLayer = layer
        player.play()

        let fadeDuration: TimeInterval = 0.12
        DispatchQueue.main.asyncAfter(deadline: .now() + kCommercialTransitionDuration - fadeDuration) {
            UIView.animate(withDuration: fadeDuration) { layer.opacity = 0 }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    deinit { player?.pause() }
}

// MARK: – Looping TV static (shown while a feed video buffers)

struct TVStaticLoopingView: UIViewRepresentable {
    func makeUIView(context: Context) -> TVStaticLoopingUIView { TVStaticLoopingUIView() }
    func updateUIView(_ uiView: TVStaticLoopingUIView, context: Context) {}
}

final class TVStaticLoopingUIView: UIView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    init() {
        super.init(frame: .zero)
        backgroundColor = .black
        guard let url = Bundle.main.url(forResource: "tv_static", withExtension: "mp4") else {
            print("[TVStaticLooping] tv_static.mp4 not found in bundle")
            return
        }
        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = true
        let looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        let layer = AVPlayerLayer(player: queuePlayer)
        layer.videoGravity = .resizeAspectFill
        self.layer.addSublayer(layer)
        self.player = queuePlayer
        self.looper = looper
        self.playerLayer = layer
        queuePlayer.play()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    deinit { player?.pause() }
}
