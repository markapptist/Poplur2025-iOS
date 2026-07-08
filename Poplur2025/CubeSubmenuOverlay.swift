import SwiftUI
import UIKit

struct CubeSubmenuItem: Identifiable {
    let id: String
    let title: String
    let iconImageName: String?    // asset catalog PNG; nil → use systemImage fallback
    let systemImage: String       // SF Symbol used for cube-face overrides & fallback display
    let tint: Color               // tint for SF Symbol fallback
    let action: () -> Void

    init(
        id: String,
        title: String,
        iconImageName: String? = nil,
        systemImage: String = "circle.fill",
        tint: Color = .white,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.iconImageName = iconImageName
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }
}

@MainActor
final class CubeMenuWheelController: ObservableObject {
    @Published private(set) var items: [CubeSubmenuItem] = []
    @Published private(set) var selectedIndex = 0
    @Published private(set) var isVisible = false
    @Published private(set) var isClosing = false

    private var scrubRemainder: CGFloat = 0
    private let scrubStep: CGFloat = 80
    private let selectionFeedback = UISelectionFeedbackGenerator()

    var isOnScreen: Bool { isVisible || isClosing }
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
        withAnimation(.spring(response: 0.36, dampingFraction: 0.70)) {
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
        let primary = abs(deltaX) >= abs(deltaY) ? deltaX : deltaY
        guard abs(primary) > 0.25 else { return }
        scrubRemainder += primary

        while scrubRemainder >= scrubStep {
            scrubRemainder -= scrubStep
            advanceSelection(by: 1)
        }
        while scrubRemainder <= -scrubStep {
            scrubRemainder += scrubStep
            advanceSelection(by: -1)
        }
    }

    private func advanceSelection(by offset: Int) {
        guard isVisible, !items.isEmpty else { return }
        let count = items.count
        withAnimation(.spring(response: 0.28, dampingFraction: 0.70)) {
            selectedIndex = (selectedIndex + offset + count) % count
        }
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
        PoplurSoundPlayer.shared.playPop(minimumInterval: 0.055)
    }

    private func finishClosing() {
        isClosing = false
        PoplurEQSync.shared.end(.holdMenu)
    }

    private static func cgFloat(from value: Any?) -> CGFloat {
        if let v = value as? CGFloat { return v }
        if let v = value as? Double { return CGFloat(v) }
        if let v = value as? NSNumber { return CGFloat(truncating: v) }
        return 0
    }
}

// MARK: - Overlay
//
// Curved vertical wheel: the selected item sits at center, neighbors recede
// above/below along a gentle arc (offset + rotation + scale falloff), scrubbed
// with the hold gesture. Styled with the neon-pink icon-pack look and the
// spring scale/fade entrance.

struct CubeMenuWheelOverlay: View {
    @ObservedObject var controller: CubeMenuWheelController

    private static let neonPink = Color(red: 1.00, green: 0.08, blue: 0.55)
    private static let cardBg   = Color(red: 0.05, green: 0.03, blue: 0.08)

    private let slotSpacing: CGFloat = 122
    private let arcDepth: CGFloat = 26

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if controller.isOnScreen {
                    // Dark background + radial pink glow
                    Color.black.opacity(0.88).ignoresSafeArea()
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.55, green: 0.02, blue: 0.28).opacity(0.55),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: proxy.size.height * 0.65
                    )
                    .ignoresSafeArea()

                    headerPill
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.10)

                    wheelItems(in: proxy.size)

                    closeButton
                        .position(x: proxy.size.width / 2, y: proxy.size.height * 0.88)
                }
            }
            .scaleEffect(controller.isVisible ? 1 : 0.85)
            .opacity(controller.isVisible ? 1 : 0)
            .animation(.spring(response: 0.36, dampingFraction: 0.70), value: controller.isVisible)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Wheel

    @ViewBuilder
    private func wheelItems(in size: CGSize) -> some View {
        let center = CGPoint(x: size.width / 2, y: size.height * 0.46)

        ForEach(Array(controller.items.enumerated()), id: \.element.id) { index, item in
            let slot = relativeSlot(for: index)
            if abs(slot) <= 2 {
                let selected = index == controller.selectedIndex
                let distance = abs(slot)

                holdMenuWheelTile(item: item, selected: selected)
                    .rotationEffect(.degrees(Double(slot) * -5))
                    .scaleEffect(selected ? 1.0 : max(0.78, 1 - CGFloat(distance) * 0.13))
                    .position(
                        x: center.x - pow(CGFloat(distance), 1.5) * arcDepth,
                        y: center.y + CGFloat(slot) * slotSpacing
                    )
                    .opacity(distance == 2 ? 0.55 : 1)
                    .zIndex(selected ? 3 : Double(3 - distance))
                    .animation(.spring(response: 0.30, dampingFraction: 0.72), value: controller.selectedIndex)
            }
        }
    }

    /// Signed slot offset of `index` from the selected item, wrapped so the
    /// wheel is circular (…-2, -1, 0, +1, +2…).
    private func relativeSlot(for index: Int) -> Int {
        let count = controller.items.count
        guard count > 0 else { return 0 }
        let centerSlot = count / 2
        let slot = (index - controller.selectedIndex + centerSlot + count * 4) % count
        return slot - centerSlot
    }

    @ViewBuilder
    private func holdMenuWheelTile(item: CubeSubmenuItem, selected: Bool) -> some View {
        let tileSize: CGFloat = selected ? 104 : 88

        VStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black)
                    .frame(width: tileSize, height: tileSize)

                if let imageName = item.iconImageName, !imageName.isEmpty {
                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: tileSize, height: tileSize)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    Image(systemName: item.systemImage)
                        .font(.system(size: tileSize * 0.42, weight: .semibold))
                        .foregroundColor(item.tint)
                }

                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(
                        selected ? Self.neonPink : Self.neonPink.opacity(0.35),
                        lineWidth: selected ? 2.5 : 1.5
                    )
                    .frame(width: tileSize, height: tileSize)
            }
            .shadow(color: Self.neonPink.opacity(selected ? 0.65 : 0.18), radius: selected ? 16 : 6, x: 0, y: 0)

            Text(item.title)
                .font(.system(size: selected ? 13 : 11, weight: .black, design: .rounded))
                .foregroundColor(selected ? Self.neonPink : .white)
                .tracking(0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.70)
        }
    }

    // MARK: Header pill

    private var headerPill: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Self.neonPink)
                    .frame(width: 30, height: 30)
                Text("P")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundColor(.white)
            }
            Text("HOLD MENU")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .tracking(1.5)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Self.cardBg, in: Capsule())
        .overlay(Capsule().stroke(Self.neonPink, lineWidth: 2))
    }

    // MARK: Close button

    private var closeButton: some View {
        ZStack {
            Circle()
                .fill(Self.cardBg)
                .frame(width: 56, height: 56)
            Circle()
                .stroke(Self.neonPink, lineWidth: 2)
                .frame(width: 56, height: 56)
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .black))
                .foregroundColor(Self.neonPink)
        }
        .shadow(color: Self.neonPink.opacity(0.50), radius: 14, x: 0, y: 0)
    }

}
