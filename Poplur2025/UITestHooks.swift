import SwiftUI

#if DEBUG
/// Test-only navigation scaffolding: exposes the same actions the 3D cube's tab-switch and
/// long-press wheel menus trigger, as ordinary accessibility-identified buttons, so UI tests can
/// drive navigation directly instead of simulating gestures against a native, non-accessible
/// SceneKit view. Only renders when the app is launched with `-UITestHooks`; inert otherwise, and
/// compiled out of release builds entirely.
enum UITestHooks {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-UITestHooks")
}

/// A near-invisible (but genuinely hit-testable) strip of buttons, one per action. Each button's
/// accessibility identifier is `"\(prefix)_\(id)"`.
struct UITestActionStrip: View {
    let prefix: String
    let items: [(id: String, action: () -> Void)]

    var body: some View {
        if UITestHooks.isEnabled {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(items, id: \.id) { entry in
                        Button(entry.id) { entry.action() }
                            .frame(minWidth: 32, minHeight: 32)
                            .accessibilityIdentifier("\(prefix)_\(entry.id)")
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(height: 36)
            .opacity(0.02)
        }
    }
}

extension UITestActionStrip {
    /// Convenience for wiring straight from an existing `[CubeSubmenuItem]` array (Profile/Map's
    /// wheel items), reusing their `id`/`action` so this stays in sync with the real wheel content.
    init(prefix: String, submenuItems: [CubeSubmenuItem]) {
        self.init(prefix: prefix, items: submenuItems.map { ($0.id, $0.action) })
    }
}

/// A tiny, accessibility-readable text marker so tests can confirm which screen/tab is actually
/// on-screen without needing OCR or fragile content-based heuristics.
struct UITestScreenMarker: View {
    let name: String
    var body: some View {
        if UITestHooks.isEnabled {
            Text(name)
                .font(.system(size: 1))
                .opacity(0.02)
                .accessibilityIdentifier("UITestCurrentScreen_\(name)")
        }
    }
}
#endif
