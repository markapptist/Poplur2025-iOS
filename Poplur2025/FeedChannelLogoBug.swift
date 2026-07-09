import SwiftUI

/// "TV channel logo" bug: periodically swoops the 3D Poplur (clay) logo in from the
/// right, settles it centered on the video, holds ~1.5s, then drifts up and fades.
/// Purely decorative overlay — never intercepts touches.
struct FeedChannelLogoBug: View {
    /// Seconds between appearances.
    var intervalSeconds: Double = 9

    @State private var alpha: Double = 0
    @State private var scale: CGFloat = 1.7
    @State private var offX: CGFloat = 1.1   // fraction of width; + = right of center
    @State private var rot: Double = -12

    var body: some View {
        GeometryReader { geo in
            Image("logo_clay")
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width * 0.40)
                .rotationEffect(.degrees(rot))
                .scaleEffect(scale)
                .opacity(alpha)
                .offset(x: offX * geo.size.width * 0.72)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                .allowsHitTesting(false)
                .task { await runLoop() }
        }
        .allowsHitTesting(false)
    }

    private func runLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(intervalSeconds * 1_000_000_000))
            if Task.isCancelled { return }
            // reset off-screen right, small-far, tilted
            alpha = 0; scale = 1.7; offX = 1.1; rot = -12
            // swoop in from the right + settle with a little spring
            withAnimation(.easeOut(duration: 0.6)) { offX = 0; rot = 0; alpha = 1 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { scale = 1.0 }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            // hold done — drift up, grow slightly, fade out like a channel bug
            withAnimation(.easeIn(duration: 0.45)) { alpha = 0; scale = 1.15; rot = 7 }
        }
    }
}
