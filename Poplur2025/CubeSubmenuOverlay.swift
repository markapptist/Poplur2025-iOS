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
                ZStack {
                    menuPanel(in: proxy.size, layout: settings.holdMenuLayoutPreference)

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

    @ViewBuilder
    private func menuPanel(in size: CGSize, layout: HoldMenuLayoutPreference) -> some View {
        let panelSize = panelSize(in: size, layout: layout)
        let center = panelCenter(in: size, layout: layout)

        RoundedRectangle(cornerRadius: layout == .horizontal ? 34 : 28, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.74),
                        Color(red: 0.07, green: 0.04, blue: 0.16).opacity(0.88),
                        Color.black.opacity(0.78)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: layout == .horizontal ? 34 : 28, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color(red: 0.32, green: 0.24, blue: 1.0).opacity(0.6),
                                Color(red: 1.0, green: 0.1, blue: 0.95).opacity(0.74),
                                Color(red: 0.52, green: 0.35, blue: 1.0).opacity(0.58)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.5
                    )
            )
            .shadow(color: Color(red: 0.62, green: 0.14, blue: 1.0).opacity(0.3), radius: 24, x: 0, y: 0)
            .frame(width: panelSize.width, height: panelSize.height)
            .position(center)
            .scaleEffect(controller.isVisible ? 1 : 0.8)
            .opacity(controller.isVisible ? 1 : 0)
            .animation(.spring(response: 0.34, dampingFraction: 0.74), value: layout)
            .animation(.spring(response: 0.34, dampingFraction: 0.74), value: controller.isVisible)
    }

    private func panelSize(in size: CGSize, layout: HoldMenuLayoutPreference) -> CGSize {
        switch layout {
        case .horizontal:
            return CGSize(width: min(size.width - 28, 560), height: 146)
        case .vertical:
            return CGSize(width: 176, height: min(size.height - 120, 620))
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

    private var tileSize: CGSize {
        switch layout {
        case .horizontal:
            return selected ? CGSize(width: 118, height: 118) : CGSize(width: 88, height: 88)
        case .vertical:
            return selected ? CGSize(width: 152, height: 116) : CGSize(width: 112, height: 96)
        }
    }

    var body: some View {
        VStack(spacing: selected ? 8 : 5) {
            Image(systemName: item.systemImage)
                .font(.system(size: selected ? 38 : 28, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: selected ? Color(red: 1.0, green: 0.45, blue: 1.0).opacity(0.95) : Color(red: 0.72, green: 0.5, blue: 1.0).opacity(0.72), radius: selected ? 9 : 5)

            Text(item.title)
                .font(.system(size: selected ? 17 : 13, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .shadow(color: Color(red: 0.76, green: 0.46, blue: 1.0).opacity(0.85), radius: 5)
        }
        .padding(selected ? 12 : 9)
        .frame(width: tileSize.width, height: tileSize.height)
        .scaleEffect(x: selectionImpulse ? 1.08 : 1, y: selectionImpulse ? 0.94 : 1, anchor: .center)
        .background {
            RoundedRectangle(cornerRadius: selected ? 24 : 18, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.22, green: 0.03, blue: 0.34).opacity(selected ? 0.96 : 0.78),
                            Color(red: 0.02, green: 0.02, blue: 0.06).opacity(0.98)
                        ],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: selected ? 120 : 86
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: selected ? 24 : 18, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.44, green: 0.32, blue: 1.0),
                                    Color(red: 1.0, green: 0.12, blue: 0.95),
                                    Color(red: 0.74, green: 0.46, blue: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: selected ? 3.5 : 2.0
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: selected ? 18 : 13, style: .continuous)
                        .stroke(Color.white.opacity(selected ? 0.26 : 0.18), lineWidth: 1)
                        .padding(6)
                )
                .shadow(color: Color(red: 0.74, green: 0.18, blue: 1.0).opacity(selected ? 0.7 : 0.36), radius: selected ? 22 : 12, x: 0, y: 0)
                .shadow(color: Color(red: 0.16, green: 0.16, blue: 1.0).opacity(selected ? 0.36 : 0.24), radius: selected ? 16 : 9, x: 0, y: 0)
                .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 12)
        }
        .accessibilityLabel(item.title)
    }
}
