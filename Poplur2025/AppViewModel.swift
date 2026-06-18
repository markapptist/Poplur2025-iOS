import SwiftUI
import Combine

// Global app state for overlays and simple back navigation
final class AppViewModel: ObservableObject {
    static let shared = AppViewModel()

    // Phone overlay state
    @Published var isPhoneOverlayActive: Bool = false
    @Published var isHomeInteractionEnabled: Bool = true

    // Simple navigation stack to enable global back button in hold menu
    @Published private(set) var navigationStack: [String] = ["root"]

    func push(route: String) {
        navigationStack.append(route)
    }

    func pop() {
        guard navigationStack.count > 1 else { return }
        _ = navigationStack.popLast()
    }

    var canGoBack: Bool { navigationStack.count > 1 || isPhoneOverlayActive }

    // Helpers to enter/exit phone overlay
    func enterPhoneOverlay() {
        isPhoneOverlayActive = true
        isHomeInteractionEnabled = false
        NotificationCenter.default.post(name: .phoneOverlayDidAppear, object: nil)
    }

    func exitPhoneOverlay() {
        isPhoneOverlayActive = false
        isHomeInteractionEnabled = true
    }
}

