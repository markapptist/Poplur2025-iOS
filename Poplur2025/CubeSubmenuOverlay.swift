import SwiftUI
import AudioToolbox

struct CubeSubmenuItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
}

@MainActor
final class CubeMenuWheelController: ObservableObject {
    @Published private(set) var items: [CubeSubmenuItem] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var isVisible = false
    @Published private(set) var isClosing = false
    @Published private(set) var tickCount = 0

    private var tickTimer: Timer?
    private let tickInterval: TimeInterval = 0.62

    var isOnScreen: Bool {
        isVisible || isClosing
    }

    var selectedItem: CubeSubmenuItem? {
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    func beginHold(items: [CubeSubmenuItem]) {
        guard !items.isEmpty else { return }
        tickTimer?.invalidate()
        self.items = items
        selectedIndex = 0
        tickCount = 0
        isClosing = false

        withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) {
            isVisible = true
        }

        playPop()
        tickTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.advanceSelection()
            }
        }
    }

    func endHold(activateSelected: Bool) {
        tickTimer?.invalidate()
        tickTimer = nil

        let action = activateSelected ? selectedItem?.action : nil

        withAnimation(.easeInOut(duration: 0.2)) {
            isClosing = true
            isVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            Task { @MainActor in
                self?.finishClosing()
                action?()
            }
        }
    }

    private func advanceSelection() {
        guard isVisible, !items.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % items.count
        tickCount += 1
        playPop()
    }

    private func finishClosing() {
        isClosing = false
    }

    private func playPop() {
        AudioServicesPlaySystemSound(1104)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

struct CubeMenuWheelOverlay: View {
    @ObservedObject var controller: CubeMenuWheelController
    @ObservedObject private var settings = SettingsStore.shared
    @State private var selectionImpulse = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(controller.items.enumerated()), id: \.element.id) { index, item in
                    let slot = slotIndex(for: index)
                    let selected = index == controller.selectedIndex

                    CubeMenuWheelItem(
                        item: item,
                        selected: selected,
                        layout: settings.holdMenuLayoutPreference,
                        selectionImpulse: selected && selectionImpulse
                    )
                        .position(position(forSlot: slot, in: proxy.size, layout: settings.holdMenuLayoutPreference))
                        .scaleEffect(controller.isVisible ? 1 : 0.3)
                        .modifier(
                            HoldMenuTransitionMotion(
                                slot: slot,
                                centerSlot: centerSlot,
                                layout: settings.holdMenuLayoutPreference,
                                style: settings.transitionStylePreference,
                                selectionImpulse: selected && selectionImpulse
                            )
                        )
                        .opacity(controller.isVisible ? opacity(forSlot: slot) : 0)
                        .zIndex(selected ? 3 : Double(3 - abs(slot - centerSlot)))
                        .animation(selectionSpring, value: controller.selectedIndex)
                        .animation(selectionSpring, value: selectionImpulse)
                        .animation(entranceSpring, value: controller.isVisible)
                }
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .onChange(of: controller.tickCount) { _, _ in
            triggerSelectionImpulse()
        }
        .onChange(of: controller.isVisible) { _, isVisible in
            if isVisible {
                triggerSelectionImpulse()
            }
        }
    }

    private var entranceSpring: Animation {
        .interpolatingSpring(mass: 0.82, stiffness: 190, damping: 16, initialVelocity: 2.2)
    }

    private var selectionSpring: Animation {
        .interpolatingSpring(mass: 0.72, stiffness: 230, damping: 13, initialVelocity: 6.0)
    }

    private var centerSlot: Int {
        max(0, controller.items.count / 2)
    }

    private func slotIndex(for itemIndex: Int) -> Int {
        guard !controller.items.isEmpty else { return 0 }
        let count = controller.items.count
        return (itemIndex - controller.selectedIndex + centerSlot + count * 4) % count
    }

    private func opacity(forSlot slot: Int) -> Double {
        let distance = abs(slot - centerSlot)
        guard distance <= 2 else { return 0 }
        return distance == 2 ? 0.72 : 1
    }

    private func position(forSlot slot: Int, in size: CGSize, layout: HoldMenuLayoutPreference) -> CGPoint {
        let center = panelCenter(in: size, layout: layout)
        let relativeSlot = slot - centerSlot

        switch layout {
        case .horizontal:
            let spacing = min(max(size.width * 0.23, 86), 112)
            return CGPoint(x: center.x + CGFloat(relativeSlot) * spacing, y: center.y)
        case .vertical:
            let spacing = min(max(size.height * 0.11, 92), 118)
            return CGPoint(x: center.x, y: center.y + CGFloat(relativeSlot) * spacing)
        }
    }

    private func triggerSelectionImpulse() {
        guard controller.isVisible else { return }
        let settleSpring = selectionSpring
        withAnimation(.interpolatingSpring(mass: 0.6, stiffness: 280, damping: 11, initialVelocity: 8)) {
            selectionImpulse = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            withAnimation(settleSpring) {
                selectionImpulse = false
            }
        }
    }

    private func panelCenter(in size: CGSize, layout: HoldMenuLayoutPreference) -> CGPoint {
        switch layout {
        case .horizontal:
            return CGPoint(x: size.width / 2, y: size.height - min(max(size.height * 0.24, 226), 292))
        case .vertical:
            return CGPoint(x: size.width / 2, y: size.height / 2)
        }
    }
}

private struct HoldMenuTransitionMotion: ViewModifier {
    let slot: Int
    let centerSlot: Int
    let layout: HoldMenuLayoutPreference
    let style: TransitionStylePreference
    let selectionImpulse: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        switch style {
        case .twoD:
            content
                .offset(twoDOffset)
                .rotationEffect(.degrees(twoDRotation))
        case .threeD:
            content
                .offset(threeDOffset)
                .rotation3DEffect(
                    .degrees(threeDRotation),
                    axis: threeDAxis,
                    anchor: .center,
                    perspective: 0.72
                )
                .scaleEffect(threeDDepthScale)
        }
    }

    private var relativeSlot: Int {
        slot - centerSlot
    }

    private var twoDOffset: CGSize {
        let distance = abs(relativeSlot)
        let impulse: CGFloat = selectionImpulse && relativeSlot == 0 ? -9 : 0
        let lag = CGFloat(relativeSlot) * CGFloat(distance) * 1.4

        switch layout {
        case .horizontal:
            return CGSize(width: 0, height: impulse + lag)
        case .vertical:
            return CGSize(width: -impulse + lag, height: 0)
        }
    }

    private var twoDRotation: Double {
        guard relativeSlot != 0 else { return selectionImpulse ? -1.2 : 0 }
        let direction = Double(relativeSlot.signum())
        let magnitude = min(Double(abs(relativeSlot)) * 4.5, 9)
        return layout == .horizontal ? direction * magnitude : -direction * magnitude
    }

    private var threeDOffset: CGSize {
        let impulse: CGFloat = selectionImpulse && relativeSlot == 0 ? -12 : 0
        let depthLag = CGFloat(relativeSlot) * CGFloat(abs(relativeSlot)) * 2.0

        switch layout {
        case .horizontal:
            return CGSize(width: 0, height: impulse + depthLag)
        case .vertical:
            return CGSize(width: -depthLag, height: impulse)
        }
    }

    private var threeDRotation: Double {
        guard relativeSlot != 0 else { return selectionImpulse ? -5 : 0 }
        let direction = Double(relativeSlot.signum())
        let magnitude = min(Double(abs(relativeSlot)) * 13, 26)
        return layout == .horizontal ? -direction * magnitude : direction * magnitude
    }

    private var threeDAxis: (x: CGFloat, y: CGFloat, z: CGFloat) {
        switch layout {
        case .horizontal:
            return (x: 0, y: 1, z: 0)
        case .vertical:
            return (x: 1, y: 0, z: 0)
        }
    }

    private var threeDDepthScale: CGFloat {
        let distance = min(CGFloat(abs(relativeSlot)), 2)
        let base = max(0.88, 1 - distance * 0.055)
        return selectionImpulse && relativeSlot == 0 ? base * 1.04 : base
    }
}

private struct CubeMenuWheelItem: View {
    let item: CubeSubmenuItem
    let selected: Bool
    let layout: HoldMenuLayoutPreference
    let selectionImpulse: Bool

    @ObservedObject private var skinStore = CubeSkinStore.shared

    private var skin: CubeSkin { skinStore.current }

    private var accent: Color {
        selected ? Color(uiColor: skin.borderAccentColor) : item.tint
    }

    private var iconColor: Color {
        switch skin {
        case .rubber, .toy:
            return item.tint
        default:
            return Color(uiColor: skin.iconFillColor)
        }
    }

    private var tileSize: CGSize {
        switch layout {
        case .horizontal:
            return selected ? CGSize(width: 132, height: 132) : CGSize(width: 98, height: 98)
        case .vertical:
            return selected ? CGSize(width: 166, height: 128) : CGSize(width: 124, height: 104)
        }
    }

    var body: some View {
        VStack(spacing: selected ? 8 : 5) {
            menuIcon
                .shadow(color: accent.opacity(selected ? 0.95 : 0.72), radius: selected ? 9 : 5)

            Text(item.title)
                .font(.system(size: selected ? 17 : 13, weight: .heavy, design: .rounded))
                .foregroundColor(iconColor)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .shadow(color: accent.opacity(0.85), radius: 5)
        }
        .padding(selected ? 12 : 9)
        .frame(width: tileSize.width, height: tileSize.height)
        .scaleEffect(x: selectionImpulse ? 1.08 : 1, y: selectionImpulse ? 0.94 : 1, anchor: .center)
        .background {
            HoldMenuDesignedTile(
                skin: skin,
                textureTab: textureTab,
                accent: accent,
                selected: selected,
                cornerRadius: selected ? 24 : 18
            )
        }
        .accessibilityLabel(item.title)
    }

    @ViewBuilder
    private var menuIcon: some View {
        if item.id == "camera-object-detection" {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: selected ? 38 : 28, weight: .semibold))
                    .foregroundStyle(iconColor)
                Image(systemName: "eye.fill")
                    .font(.system(size: selected ? 17 : 13, weight: .bold))
                    .foregroundStyle(iconColor)
                    .padding(2)
                    .background(.black.opacity(0.35), in: Circle())
                    .offset(x: selected ? 6 : 5, y: selected ? 6 : 5)
            }
            .frame(width: selected ? 44 : 34, height: selected ? 44 : 34)
        } else {
            Image(systemName: item.systemImage)
                .font(.system(size: selected ? 38 : 28, weight: .semibold))
                .foregroundStyle(iconColor)
        }
    }

    private var textureTab: AppTab {
        let key = "\(item.id) \(item.title)".lowercased()
        if key.contains("feed") || key.contains("like") || key.contains("comment") || key.contains("news") || key.contains("tv") || key.contains("caption") {
            return .feed
        }
        if key.contains("profile") || key.contains("mail") || key.contains("settings") || key.contains("stats") || key.contains("notification") || key.contains("phone") || key.contains("store") || key.contains("back") {
            return .settings
        }
        if key.contains("map") || key.contains("search") || key.contains("location") || key.contains("tour") {
            return .map
        }
        if key.contains("camera") || key.contains("photo") || key.contains("video") || key.contains("live") || key.contains("post") || key.contains("ar") {
            return .record
        }
        return .profile
    }
}

private struct HoldMenuDesignedTile: View {
    let skin: CubeSkin
    let textureTab: AppTab
    let accent: Color
    let selected: Bool
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        Image(uiImage: skin.makeTexture(tab: textureTab))
            .resizable()
            .scaledToFill()
            .clipShape(shape)
            .overlay {
                shape
                    .fill(tileSheen)
                    .blendMode(.screen)
                    .opacity(selected ? 0.34 : 0.22)
            }
            .overlay {
                shape
                    .stroke(borderGradient, lineWidth: selected ? 3.5 : 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: max(cornerRadius - 6, 8), style: .continuous)
                    .stroke(Color.white.opacity(selected ? 0.32 : 0.18), lineWidth: 1)
                    .padding(6)
            }
            .shadow(color: accent.opacity(selected ? 0.78 : 0.38), radius: selected ? 24 : 13, x: 0, y: 0)
            .shadow(color: accent.opacity(selected ? 0.32 : 0.16), radius: selected ? 16 : 8, x: 0, y: 0)
            .shadow(color: Color.black.opacity(selected ? 0.24 : 0.14), radius: selected ? 14 : 9, x: 0, y: 8)
    }

    private var tileSheen: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.55),
                Color.white.opacity(0.08),
                accent.opacity(0.16),
                Color.clear
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(selected ? 0.52 : 0.28),
                accent.opacity(selected ? 1.0 : 0.78),
                Color.white.opacity(selected ? 0.38 : 0.18),
                accent.opacity(selected ? 0.92 : 0.62)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
