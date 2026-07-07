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
            let spacing = min(max(size.height * 0.17, 148), 188)
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

    private var tileSize: CGSize {
        switch layout {
        case .horizontal:
            return selected ? CGSize(width: 132, height: 132) : CGSize(width: 98, height: 98)
        case .vertical:
            return selected ? CGSize(width: 262, height: 152) : CGSize(width: 222, height: 120)
        }
    }

    var body: some View {
        VStack(spacing: selected ? 10 : 6) {
            menuIcon
            Text(item.title)
                .font(.system(size: selected ? 20 : 15, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .shadow(color: .black.opacity(0.30), radius: 3, x: 0, y: 1)
        }
        .padding(selected ? 14 : 10)
        .frame(width: tileSize.width, height: tileSize.height)
        .background {
            HoldMenuDesignedTile(selected: selected, cornerRadius: selected ? 28 : 22)
        }
        .accessibilityLabel(item.title)
    }

    @ViewBuilder
    private var menuIcon: some View {
        if item.id == "camera-object-detection" {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: selected ? 42 : 32, weight: .semibold))
                    .foregroundStyle(Color.white)
                Image(systemName: "eye.fill")
                    .font(.system(size: selected ? 18 : 14, weight: .bold))
                    .foregroundStyle(Color.white)
                    .padding(2)
                    .background(.black.opacity(0.35), in: Circle())
                    .offset(x: selected ? 7 : 5, y: selected ? 7 : 5)
            }
            .frame(width: selected ? 48 : 36, height: selected ? 48 : 36)
        } else if item.id == "notifications" {
            Text("🔔")
                .font(.system(size: selected ? 42 : 32))
                .shadow(color: .black.opacity(0.6), radius: 0, x: 2, y: 3)
                .shadow(color: .black.opacity(0.3), radius: 4, x: 3, y: 5)
        } else {
            Image(systemName: item.systemImage)
                .font(.system(size: selected ? 42 : 32, weight: .semibold))
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.22), radius: 4, x: 0, y: 2)
        }
    }
}

private struct HoldMenuDesignedTile: View {
    let selected: Bool
    let cornerRadius: CGFloat

    // Fixed sparkle positions: (x%, y%, radius pt)
    private let sparkles: [(CGFloat, CGFloat, CGFloat)] = [
        (0.10, 0.16, 2.5), (0.88, 0.11, 2.0), (0.24, 0.84, 3.0),
        (0.78, 0.78, 2.5), (0.50, 0.18, 2.0), (0.93, 0.54, 2.5),
        (0.06, 0.60, 2.0), (0.55, 0.93, 2.5), (0.34, 0.46, 1.5),
        (0.72, 0.30, 2.0), (0.17, 0.90, 2.5), (0.62, 0.08, 2.0),
        (0.42, 0.66, 1.5), (0.83, 0.63, 2.0), (0.28, 0.32, 1.5)
    ]

    private static let hotPink   = Color(red: 0.97, green: 0.13, blue: 0.53)
    private static let deepPink  = Color(red: 0.83, green: 0.04, blue: 0.40)
    private static let lightPink = Color(red: 1.00, green: 0.44, blue: 0.72)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            // Pink gradient base
            shape.fill(
                LinearGradient(
                    colors: [Self.lightPink, Self.hotPink, Self.deepPink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )

            // Sheen
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(selected ? 0.30 : 0.18),
                        Color.clear,
                        Self.deepPink.opacity(0.15)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .blendMode(.screen)

            // Sparkle dots
            Canvas { ctx, size in
                let opacity: CGFloat = selected ? 0.90 : 0.65
                for (nx, ny, r) in sparkles {
                    ctx.fill(
                        Path(ellipseIn: CGRect(
                            x: nx * size.width - r,
                            y: ny * size.height - r,
                            width: r * 2, height: r * 2
                        )),
                        with: .color(.white.opacity(opacity))
                    )
                }
            }
            .allowsHitTesting(false)

            // Outer border
            shape.stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(selected ? 0.68 : 0.38),
                        Self.hotPink.opacity(0.5),
                        Color.white.opacity(selected ? 0.48 : 0.28)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: selected ? 2.5 : 1.5
            )

            // Inner highlight ring
            RoundedRectangle(cornerRadius: max(cornerRadius - 5, 8), style: .continuous)
                .stroke(Color.white.opacity(selected ? 0.30 : 0.16), lineWidth: 1)
                .padding(5)
        }
        .shadow(color: Self.hotPink.opacity(selected ? 0.60 : 0.28), radius: selected ? 18 : 8, x: 0, y: 0)
        .shadow(color: .black.opacity(selected ? 0.28 : 0.14), radius: selected ? 10 : 5, x: 0, y: 6)
    }
}
