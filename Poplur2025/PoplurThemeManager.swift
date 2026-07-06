import SwiftUI
import Combine

// MARK: - PoplurThemeManager

@MainActor
final class PoplurThemeManager: ObservableObject {
    static let shared = PoplurThemeManager()

    @Published private(set) var current: PoplurTheme = .default
    @Published private(set) var isTransitioning: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private let storageKey = "poplur_map_theme_v1"

    private init() {
        loadSaved()
        CubeSkinStore.shared.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] skin in
                guard let self else { return }
                let incoming = skin.poplurTheme
                if incoming != self.current {
                    self.current = incoming
                }
            }
            .store(in: &cancellables)
    }

    func apply(_ theme: PoplurTheme, animated: Bool = true) {
        guard theme != current else { return }
        if animated {
            withAnimation(.easeInOut(duration: theme.animationDuration)) {
                isTransitioning = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + theme.animationDuration) { [weak self] in
                self?.isTransitioning = false
            }
        }
        current = theme
        CubeSkinStore.shared.apply(theme.cubeSkin)
        persist(theme)
    }

    func cycle() {
        let all = PoplurTheme.allCases
        let idx = all.firstIndex(of: current) ?? 0
        apply(all[(idx + 1) % all.count])
    }

    // MARK: - Persistence

    private func persist(_ theme: PoplurTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: storageKey)
    }

    private func loadSaved() {
        guard let raw = UserDefaults.standard.string(forKey: storageKey),
              let theme = PoplurTheme(rawValue: raw) else { return }
        current = theme
    }
}
