import SwiftUI

/// A fraction-style posts display that mirrors the radius fraction layout:
/// - Arrow (green up/red down) as the numerator
/// - 90pt white line as the bar
/// - "N posts" as the denominator
struct PostsFractionDisplay: View {
    let postsCount: Int
    let changeDirection: ChangeDirection

    enum ChangeDirection { case up, down, none }

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            // Numerator: change arrow (centered above the line)
            Group {
                switch changeDirection {
                case .up:
                    Image(systemName: "arrow.up")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.green)
                        .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                case .down:
                    Image(systemName: "arrow.down")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.red)
                        .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                case .none:
                    Image(systemName: "arrow.up")
                        .font(.system(size: 28, weight: .bold))
                        .opacity(0)
                }
            }
            .frame(width: 90) // Match the line width so arrow is centered

            // Bar (aligned parallel to radius display line)
            Rectangle()
                .fill(.white)
                .frame(width: 90, height: 2)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)

            // Denominator: posts count (centered below the line)
            Text("\(postsCount) posts")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .poplurTextShader(intensity: 0.72)
                .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                .frame(width: 90) // Match the line width so text is centered
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack {
            Spacer()
            HStack {
                Spacer()
                PostsFractionDisplay(postsCount: 12, changeDirection: .up)
                    .padding(.trailing, 20)
                    .padding(.bottom, 16)
            }
        }
    }
}
