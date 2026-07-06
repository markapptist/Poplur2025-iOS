import SwiftUI
import MapKit

// MARK: - MapOverlayManager

/// Central coordinator for all Poplur map overlay layers.
/// Owns visibility toggles and passes them to each overlay view.
@MainActor
final class MapOverlayManager: ObservableObject {
    static let shared = MapOverlayManager()

    @Published var showThemeParticles: Bool = true
    @Published var showRadiusPulse: Bool = true
    @Published var showSpriteOverlay: Bool = false
    @Published var showProfileCard: Bool = false
    @Published var activeCardItem: PoplurMapCardItem? = nil

    private init() {}

    func showCard(_ item: PoplurMapCardItem) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
            activeCardItem = item
            showProfileCard = true
        }
    }

    func dismissCard() {
        withAnimation(.easeOut(duration: 0.22)) {
            showProfileCard = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.activeCardItem = nil
        }
    }

    func toggleParticles() {
        withAnimation { showThemeParticles.toggle() }
    }

    func toggleRadiusPulse() {
        withAnimation { showRadiusPulse.toggle() }
    }
}

// MARK: - Map overlay layer composer

/// Wraps all Poplur-specific overlay layers into a single insertable view.
struct PoplurMapOverlayLayer: View {
    let skin: CubeSkin
    @ObservedObject var manager: MapOverlayManager

    var body: some View {
        ZStack {
            // Theme ambient particles
            if manager.showThemeParticles {
                PoplurThemeParticleOverlay(skin: skin)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // Profile card (shown when a marker is tapped)
            if manager.showProfileCard, let item = manager.activeCardItem {
                VStack {
                    Spacer()
                    PoplurMapProfileCard(
                        skin: skin,
                        item: item,
                        onDismiss: { manager.dismissCard() },
                        onDirections: nil,
                        onProfile: nil
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 120)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: manager.showProfileCard)
        .animation(.easeInOut(duration: 0.25), value: manager.showThemeParticles)
    }
}
