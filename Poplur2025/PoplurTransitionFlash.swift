import SwiftUI
import AVFoundation

// MARK: – Duration constant shared with FeedView
let kCommercialTransitionDuration: TimeInterval = 0.45

// MARK: – Channel/video-change transition (no static video)
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
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            // Channel logo centered briefly during the change
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

// MARK: – Looping TV static (shown while a feed video buffers)

struct TVStaticLoopingView: UIViewRepresentable {
    var isMuted: Bool = true
    var volume: Float = 1.0

    func makeUIView(context: Context) -> TVStaticLoopingUIView {
        TVStaticLoopingUIView(isMuted: isMuted, volume: volume)
    }

    func updateUIView(_ uiView: TVStaticLoopingUIView, context: Context) {
        uiView.configure(isMuted: isMuted, volume: volume)
    }
}

final class TVStaticLoopingUIView: UIView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    init(isMuted: Bool = true, volume: Float = 1.0) {
        super.init(frame: .zero)
        backgroundColor = .black
        // Prefer the logo-free cut: the original tv_static.mp4 bursts a Poplur
        // "P" mid-clip, which doubles up with the channel identity drawn over it.
        guard let url = Bundle.main.url(forResource: "tv_static_clean", withExtension: "mp4")
            ?? Bundle.main.url(forResource: "tv_static", withExtension: "mp4") else {
            print("[TVStaticLooping] tv_static.mp4 not found in bundle")
            return
        }
        let item = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = isMuted
        queuePlayer.volume = volume
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

    func configure(isMuted: Bool, volume: Float) {
        player?.isMuted = isMuted
        player?.volume = volume
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = bounds
    }

    deinit { player?.pause() }
}
