import SwiftUI

// MARK: - Map pin for a user-placed AI game
//
// A neon arcade-style marker used on the map for games created in the Game Maker.
// Tapping it (handled by the caller) launches the game.

struct PoplurGamePinMarker: View {
    let config: PoplurGameConfig

    @State private var pulse = false

    private var accent: Color { Color(uiColor: config.accentUIColor) }
    private var sky: Color { Color(uiColor: config.skyUIColor) }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.28))
                    .frame(width: 58, height: 58)
                    .scaleEffect(pulse ? 1.15 : 0.9)
                    .opacity(pulse ? 0.0 : 0.7)

                Circle()
                    .fill(
                        LinearGradient(colors: [sky, accent],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 40, height: 40)
                    .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
                    .shadow(color: accent.opacity(0.6), radius: 6)

                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 17, weight: .black))
                    .foregroundStyle(.white)
            }

            Text(config.gameName)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.black.opacity(0.55), in: Capsule())
        }
        .frame(width: 96, height: 74)
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}
