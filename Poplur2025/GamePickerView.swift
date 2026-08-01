import SwiftUI

// MARK: - Game picker — lists all available games

struct GamePickerView: View {
    var onClose: (() -> Void)? = nil

    @State private var showFPS      = false
    @State private var showPet      = false

    private let accent = Color(red: 1.0, green: 0.22, blue: 0.62)

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.05, green: 0.03, blue: 0.10)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // ── Header ───────────────────────────────────────────────────
                HStack {
                    Text("GAMES")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [accent, Color(red: 0.55, green: 0.20, blue: 1.0)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                    Spacer()
                    Button { onClose?() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 60)
                .padding(.bottom, 22)

                // ── Game cards ───────────────────────────────────────────────
                ScrollView {
                    VStack(spacing: 16) {
                        GameCard(
                            title: "Poplurgatchi",
                            subtitle: "Virtual pet — feed, play & grow",
                            previewName: "poplurgatchi_game_preview",
                            pixelated: false,
                            accentColor: Color(red: 1.0, green: 0.22, blue: 0.62)
                        ) { showPet = true }

                        GameCard(
                            title: "FPS Shooter",
                            subtitle: "Raycasting first-person shooter",
                            previewName: "fps_game_preview",
                            pixelated: true,
                            accentColor: Color(red: 0.20, green: 0.80, blue: 1.0)
                        ) { showFPS = true }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 32)
                }
            }
        }
        .fullScreenCover(isPresented: $showFPS)  { PoplurFPSGameSheet()  }
        .fullScreenCover(isPresented: $showPet)  { PoplurPetGameView { showPet = false } }
    }
}

// MARK: - Individual game card

private struct GameCard: View {
    let title:       String
    let subtitle:    String
    let previewName: String
    let pixelated:   Bool
    let accentColor: Color
    let onTap:       () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 18) {
                Image(previewName)
                    .resizable()
                    .interpolation(pixelated ? .none : .high)
                    .scaledToFit()
                    .frame(width: 70, height: 70)
                    .background(accentColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(accentColor.opacity(0.5), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accentColor.opacity(0.8))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(accentColor.opacity(0.28), lineWidth: 1.2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    GamePickerView()
}
