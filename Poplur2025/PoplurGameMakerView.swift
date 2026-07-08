import SwiftUI

// MARK: - Game Maker (AI stack)
//
// Lets the user describe a game, generate it with the AI game service, save it to
// "My Games", and then play it or place it anywhere on the map.

struct PoplurGameMakerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = PoplurSavedGamesStore.shared

    @State private var prompt = ""
    @State private var generating = false
    @State private var generated: PoplurGameConfig?
    @State private var launching: PoplurSavedGame?
    @State private var placementInfo: PoplurSavedGame?

    private let bg = Color(red: 0.06, green: 0.06, blue: 0.10)
    private let card = Color(red: 0.11, green: 0.11, blue: 0.17)
    private let pink = Color(red: 1.0, green: 0.30, blue: 0.72)
    private let gold = Color(red: 1.0, green: 0.84, blue: 0.0)

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        makerCard
                        if let cfg = generated { previewCard(cfg) }
                        myGamesSection
                    }
                    .padding(20)
                }
                .scrollIndicators(.never)
            }
            .navigationTitle("Game Maker")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(.white)
                }
            }
            .toolbarBackground(bg, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .fullScreenCover(item: $launching) { g in
            PoplurGameLaunchView(presetConfig: g.config)
                .environmentObject(DeviceVolumeObserver())
        }
        .alert("Place on the Map",
               isPresented: Binding(get: { placementInfo != nil }, set: { if !$0 { placementInfo = nil } })) {
            Button("Got it", role: .cancel) { dismiss() }
        } message: {
            Text("Switch to the Map tab and tap the spot where you want \"\(placementInfo?.config.gameName ?? "your game")\" to appear.")
        }
    }

    // MARK: Maker input

    private var makerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "gamecontroller.fill").foregroundStyle(gold)
                Text("Describe your game")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            Text("Tell the AI what kind of game you want. It picks the type, theme, colors and mechanics.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))

            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("e.g. a fast neon jungle runner with double jumps and laser vines")
                        .font(.system(size: 15, design: .rounded))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.horizontal, 12).padding(.vertical, 12)
                }
                TextEditor(text: $prompt)
                    .scrollContentBackground(.hidden)
                    .frame(height: 92)
                    .padding(6)
                    .foregroundStyle(.white)
                    .font(.system(size: 15, design: .rounded))
            }
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))

            Button {
                Task { await generate() }
            } label: {
                HStack {
                    if generating { ProgressView().tint(.black) }
                    else { Image(systemName: "sparkles") }
                    Text(generating ? "Generating…" : "Generate Game")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(gold, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(generating)
        }
        .padding(18)
        .background(card, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Generated preview

    private func previewCard(_ cfg: PoplurGameConfig) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LinearGradient(colors: [cfg.skyUIColor.swiftUI, cfg.accentUIColor.swiftUI],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 96)
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cfg.gameName)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                        Text("\(cfg.game.displayName) · \(cfg.theme) · \(cfg.difficulty.capitalized)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14))

            Text("Special: \(cfg.specialMechanic)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.65))

            HStack(spacing: 10) {
                Button {
                    store.add(cfg)
                    generated = nil
                    prompt = ""
                } label: {
                    Label("Save to My Games", systemImage: "square.and.arrow.down.fill")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(pink, in: RoundedRectangle(cornerRadius: 12))
                }
                Button {
                    Task { await generate() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(14)
        .background(card, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Saved list

    private var myGamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("My Games")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            if store.games.isEmpty {
                Text("Games you make will show up here.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.vertical, 8)
            } else {
                ForEach(store.games) { g in savedRow(g) }
            }
        }
    }

    private func savedRow(_ g: PoplurSavedGame) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [g.config.skyUIColor.swiftUI, g.config.accentUIColor.swiftUI],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(g.config.gameName)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(g.config.game.displayName)
                    if g.isPlaced {
                        Label("On map", systemImage: "mappin.circle.fill").foregroundStyle(gold)
                    }
                }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()

            Button { launching = g } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(.black)
                    .frame(width: 38, height: 38)
                    .background(gold, in: Circle())
            }

            Menu {
                Button {
                    store.pendingPlacement = g
                    placementInfo = g
                } label: { Label(g.isPlaced ? "Move on Map" : "Place on Map", systemImage: "mappin.and.ellipse") }
                if g.isPlaced {
                    Button { store.unplace(g) } label: { Label("Remove from Map", systemImage: "mappin.slash") }
                }
                Button(role: .destructive) { store.remove(g) } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
        }
        .padding(10)
        .background(card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Actions

    private func generate() async {
        generating = true
        let cfg = await PoplurGameService.shared.generateConfig(userPrompt: prompt)
        await MainActor.run {
            generated = cfg
            generating = false
        }
    }
}

private extension UIColor {
    var swiftUI: Color { Color(uiColor: self) }
}
