import SwiftUI

/// Transparent broadcast-style overlay rendered on top of captured media.
/// Shows a channel bug (top-left), HD badge (top-right), and animated lower third.
struct TVOverlayView: View {
    let metadata: TVStyleMetadata
    @State private var lowerThirdVisible = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Subtle vignette
                RadialGradient(
                    colors: [.clear, .black.opacity(0.42)],
                    center: .center,
                    startRadius: geo.size.width * 0.18,
                    endRadius: geo.size.width * 1.05
                )

                // Top row: channel bug + HD badge
                VStack {
                    HStack(alignment: .top) {
                        channelBug
                        Spacer()
                        hdBadge
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 56)
                    Spacer()
                }

                // Lower third — slides up on appear
                if lowerThirdVisible {
                    lowerThird
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.78)) {
                    lowerThirdVisible = true
                }
            }
        }
    }

    // MARK: - Sub-views

    private var channelBug: some View {
        HStack(spacing: 5) {
            Text(emoji(for: metadata.channel))
                .font(.system(size: 14))
            Text(metadata.broadcastName.uppercased())
                .font(.system(size: 9, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .tracking(1.2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.black.opacity(0.66),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var hdBadge: some View {
        Text("HD")
            .font(.system(size: 8, weight: .black))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.white.opacity(0.22),
                        in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private var lowerThird: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metadata.caption.uppercased())
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.72), radius: 2, y: 1)
                .lineLimit(2)

            Text(metadata.tagline)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))
                .shadow(color: .black.opacity(0.5), radius: 1)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 22)
        .padding(.vertical, 14)
        .padding(.bottom, 38)
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.80)],
                startPoint: .top, endPoint: .bottom
            )
        )
    }

    // MARK: - Channel emoji map

    private func emoji(for channel: String) -> String {
        switch channel {
        case "food":          return "🍔"
        case "fitness":       return "💪"
        case "sports":        return "⚽"
        case "beauty":        return "💄"
        case "fashion":       return "👗"
        case "music":         return "🎵"
        case "tech":          return "💻"
        case "news":          return "📺"
        case "city":          return "🏙️"
        case "entertainment": return "🎬"
        default:              return "📡"
        }
    }
}
