import SwiftUI
import UIKit

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

    private var scrubRemainder: CGFloat = 0
    private let horizontalScrubStep: CGFloat = 34
    private let verticalScrubStep: CGFloat = 38
    private let maxStepsPerScrubUpdate = 4
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private var lastClickTime: TimeInterval = 0

    var isOnScreen: Bool {
        isVisible || isClosing
    }

    var selectedItem: CubeSubmenuItem? {
        guard items.indices.contains(selectedIndex) else { return nil }
        return items[selectedIndex]
    }

    func beginHold(items: [CubeSubmenuItem]) {
        guard !items.isEmpty else { return }
        self.items = items
        selectedIndex = 0
        scrubRemainder = 0
        isClosing = false
        selectionFeedback.prepare()
        PoplurEQSync.shared.begin(.holdMenu)

        withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) {
            isVisible = true
        }
    }

    func endHold(activateSelected: Bool) {
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

    func scrub(with notification: Notification) {
        let deltaX = Self.cgFloat(from: notification.userInfo?["deltaX"])
        let deltaY = Self.cgFloat(from: notification.userInfo?["deltaY"])
        scrub(deltaX: deltaX, deltaY: deltaY)
    }

    func scrub(deltaX: CGFloat, deltaY: CGFloat) {
        guard isVisible, items.count > 1 else { return }
        let layout = SettingsStore.shared.holdMenuLayoutPreference
        let useVerticalScrub = abs(deltaY) >= abs(deltaX)
        let primaryDelta = useVerticalScrub ? deltaY : (layout == .horizontal ? deltaX : deltaY)
        guard abs(primaryDelta) > 0.25 else { return }

        let stepDistance = (useVerticalScrub || layout == .vertical) ? verticalScrubStep : horizontalScrubStep
        scrubRemainder += primaryDelta

        var steps = 0
        while scrubRemainder <= -stepDistance, steps < maxStepsPerScrubUpdate {
            scrubRemainder += stepDistance
            moveSelection(by: 1)
            steps += 1
        }
        while scrubRemainder >= stepDistance, steps < maxStepsPerScrubUpdate {
            scrubRemainder -= stepDistance
            moveSelection(by: -1)
            steps += 1
        }
        if steps == maxStepsPerScrubUpdate, abs(scrubRemainder) > stepDistance {
            scrubRemainder = stepDistance * (scrubRemainder < 0 ? -1 : 1)
        }
    }

    private func moveSelection(by offset: Int) {
        guard isVisible, !items.isEmpty, offset != 0 else { return }
        let count = items.count
        withAnimation(CubeMenuWheelOverlay.selectionSpring) {
            selectedIndex = (selectedIndex + offset + count) % count
        }
        playWheelClick()
    }

    private func finishClosing() {
        isClosing = false
        PoplurEQSync.shared.end(.holdMenu)
    }

    private func playWheelClick() {
        guard PoplurEQSync.shared.shouldPlayMenuClick() else { return }
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastClickTime >= 0.055 else { return }
        lastClickTime = now
        PoplurSoundPlayer.shared.playPop(minimumInterval: 0.055)
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    private static func cgFloat(from value: Any?) -> CGFloat {
        if let value = value as? CGFloat { return value }
        if let value = value as? Double { return CGFloat(value) }
        if let value = value as? Float { return CGFloat(value) }
        if let value = value as? NSNumber { return CGFloat(truncating: value) }
        return 0
    }
}

struct CubeMenuWheelOverlay: View {
    @ObservedObject var controller: CubeMenuWheelController
    @ObservedObject private var skinStore = CubeSkinStore.shared

    private let layout = SettingsStore.shared.holdMenuLayoutPreference
    private let transitionStyle = SettingsStore.shared.transitionStylePreference

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                let skin = skinStore.current
                Color.black
                    .opacity(controller.isVisible ? 0.50 : 0)
                    .ignoresSafeArea()

                HoldMenuScrubHint(layout: layout)
                    .opacity(controller.isVisible ? 1 : 0)
                    .position(scrubHintPosition(in: proxy.size, layout: layout))
                    .zIndex(10)

                ForEach(Array(controller.items.enumerated()), id: \.element.id) { index, item in
                    let slot = slotIndex(for: index)
                    let selected = index == controller.selectedIndex

                    CubeMenuWheelItem(
                        item: item,
                        skin: skin,
                        selected: selected,
                        layout: layout
                    )
                        .equatable()
                        .position(position(forSlot: slot, in: proxy.size, layout: layout))
                        .scaleEffect(controller.isVisible ? 1 : 0.3)
                        .modifier(
                            HoldMenuTransitionMotion(
                                slot: slot,
                                centerSlot: centerSlot,
                                layout: layout,
                                style: transitionStyle
                            )
                        )
                        .opacity(controller.isVisible ? opacity(forSlot: slot) : 0)
                        .zIndex(selected ? 3 : Double(3 - abs(slot - centerSlot)))
                }
            }
            .animation(Self.selectionSpring, value: controller.selectedIndex)
            .animation(entranceSpring, value: controller.isVisible)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }

    private var entranceSpring: Animation {
        .interpolatingSpring(mass: 0.82, stiffness: 190, damping: 16, initialVelocity: 2.2)
    }

    fileprivate static var selectionSpring: Animation {
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
            let spacing = min(max(size.width * 0.30, 122), 158)
            return CGPoint(x: center.x + CGFloat(relativeSlot) * spacing, y: center.y)
        case .vertical:
            let spacing = min(max(size.height * 0.15, 128), 162)
            return CGPoint(x: center.x, y: center.y + CGFloat(relativeSlot) * spacing)
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

    private func scrubHintPosition(in size: CGSize, layout: HoldMenuLayoutPreference) -> CGPoint {
        let center = panelCenter(in: size, layout: layout)
        let x = min(max(size.width - 58, 46), size.width - 42)
        return CGPoint(x: x, y: center.y)
    }
}

private struct HoldMenuScrubHint: View {
    let layout: HoldMenuLayoutPreference

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: "chevron.up")
                .font(.system(size: 18, weight: .black))
            Text("SCRUB")
                .font(.system(size: 10, weight: .black, design: .rounded))
                .rotationEffect(.degrees(-90))
                .fixedSize()
            Image(systemName: "chevron.down")
                .font(.system(size: 18, weight: .black))
        }
        .foregroundStyle(.white)
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(.black.opacity(0.32), in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.35), radius: 10, x: 0, y: 4)
        .accessibilityLabel("Scrub up or down to browse")
    }
}

private struct HoldMenuTransitionMotion: ViewModifier {
    let slot: Int
    let centerSlot: Int
    let layout: HoldMenuLayoutPreference
    let style: TransitionStylePreference

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
        let lag = CGFloat(relativeSlot) * CGFloat(distance) * 1.4

        switch layout {
        case .horizontal:
            return CGSize(width: 0, height: lag)
        case .vertical:
            return CGSize(width: lag, height: 0)
        }
    }

    private var twoDRotation: Double {
        guard relativeSlot != 0 else { return 0 }
        let direction = Double(relativeSlot.signum())
        let magnitude = min(Double(abs(relativeSlot)) * 4.5, 9)
        return layout == .horizontal ? direction * magnitude : -direction * magnitude
    }

    private var threeDOffset: CGSize {
        let depthLag = CGFloat(relativeSlot) * CGFloat(abs(relativeSlot)) * 2.0

        switch layout {
        case .horizontal:
            return CGSize(width: 0, height: depthLag)
        case .vertical:
            return CGSize(width: -depthLag, height: 0)
        }
    }

    private var threeDRotation: Double {
        guard relativeSlot != 0 else { return 0 }
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
        return max(0.88, 1 - distance * 0.055)
    }
}

private struct CubeMenuWheelItem: View, Equatable {
    let item: CubeSubmenuItem
    let skin: CubeSkin
    let selected: Bool
    let layout: HoldMenuLayoutPreference

    static func == (lhs: CubeMenuWheelItem, rhs: CubeMenuWheelItem) -> Bool {
        lhs.item.id == rhs.item.id
        && lhs.item.title == rhs.item.title
        && lhs.item.systemImage == rhs.item.systemImage
        && lhs.skin == rhs.skin
        && lhs.selected == rhs.selected
        && lhs.layout == rhs.layout
    }

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
                .shadow(color: accent.opacity(selected ? 0.45 : 0.24), radius: selected ? 5 : 2)

            Text(item.title)
                .font(.system(size: selected ? 17 : 13, weight: .heavy, design: .rounded))
                .foregroundColor(iconColor)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .shadow(color: accent.opacity(selected ? 0.36 : 0.18), radius: selected ? 3 : 1)
        }
        .padding(selected ? 12 : 9)
        .frame(width: tileSize.width, height: tileSize.height)
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
            .shadow(color: accent.opacity(selected ? 0.42 : 0.18), radius: selected ? 10 : 5, x: 0, y: 0)
            .shadow(color: Color.black.opacity(selected ? 0.20 : 0.10), radius: selected ? 8 : 4, x: 0, y: 5)
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
