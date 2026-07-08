import SwiftUI
import UIKit
import QuartzCore

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

    /// Continuous wheel position in item units; the item at index == round(wheelOffset)
    /// sits at center. Published so the overlay tracks the spin frame-by-frame.
    @Published private(set) var wheelOffset: CGFloat = 0

    private let pointsPerItem: CGFloat = 62   // drag sensitivity: finger travel per item (lower = more sensitive)
    private let friction: CGFloat = 0.955     // per-tick velocity decay — the wheel-of-fortune glide
    private let maxVelocity: CGFloat = 16     // items/sec cap so a hard flick stays controllable
    private let snapVelocity: CGFloat = 0.9   // below this the wheel eases to the nearest item

    private var velocity: CGFloat = 0         // items/sec, drives momentum after a flick
    private var lastScrubTime: CFTimeInterval = 0
    private var lastNotchIndex = 0
    private var momentumTimer: Timer?
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
        wheelOffset = 0
        velocity = 0
        lastNotchIndex = 0
        lastScrubTime = CACurrentMediaTime()
        isClosing = false
        selectionFeedback.prepare()
        PoplurEQSync.shared.begin(.holdMenu)
        startMomentum()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.70)) {
            isVisible = true
        }
    }

    func endHold(activateSelected: Bool) {
        stopMomentum()
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

        let now = CACurrentMediaTime()
        let dt = max(now - lastScrubTime, 1.0 / 120.0)
        lastScrubTime = now

        // 1:1 finger tracking, then feed the flick speed into the spin velocity.
        let slotDelta = primary / pointsPerItem
        let instantaneous = (slotDelta / CGFloat(dt)).clampedMagnitude(to: maxVelocity)
        velocity = (velocity * 0.35 + instantaneous * 0.65).clampedMagnitude(to: maxVelocity)

        applyOffsetDelta(slotDelta)
    }

    // MARK: Momentum (wheel-of-fortune inertia)

    private func startMomentum() {
        momentumTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.stepMomentum() }
        }
        RunLoop.main.add(timer, forMode: .common)
        momentumTimer = timer
    }

    private func stopMomentum() {
        momentumTimer?.invalidate()
        momentumTimer = nil
        velocity = 0
    }

    private func stepMomentum() {
        guard isVisible, items.count > 1 else { return }
        // Let the finger own the wheel while it's actively moving; inertia takes
        // over only once the drag pauses (or the finger is held still).
        guard CACurrentMediaTime() - lastScrubTime > 0.032 else { return }
        let dt: CGFloat = 1.0 / 60.0

        if abs(velocity) > snapVelocity {
            applyOffsetDelta(velocity * dt)
            velocity *= friction
        } else if velocity != 0 || wheelOffset != wheelOffset.rounded() {
            // Below spin threshold: ease to the nearest item and settle.
            velocity = 0
            let target = wheelOffset.rounded()
            let remaining = target - wheelOffset
            applyOffsetDelta(abs(remaining) < 0.001 ? remaining : remaining * 0.22)
        }
    }

    /// Advance the continuous wheel position, keep it normalized, refresh the
    /// selected index, and fire a haptic/pop each time a new item passes center.
    private func applyOffsetDelta(_ delta: CGFloat) {
        guard !items.isEmpty else { return }
        let count = CGFloat(items.count)
        var offset = (wheelOffset + delta).truncatingRemainder(dividingBy: count)
        if offset < 0 { offset += count }
        wheelOffset = offset

        let notch = ((Int(offset.rounded()) % items.count) + items.count) % items.count
        if notch != lastNotchIndex {
            lastNotchIndex = notch
            selectionFeedback.selectionChanged()
            selectionFeedback.prepare()
            PoplurSoundPlayer.shared.playPop(minimumInterval: 0.045)
        }
        if selectedIndex != notch { selectedIndex = notch }
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
        let count = controller.items.count

        ForEach(Array(controller.items.enumerated()), id: \.element.id) { index, item in
            let column   = wrappedColumn(for: index, count: count)
            let distance = abs(column)
            if distance <= 2.4 {
                let selected  = index == controller.selectedIndex
                let tileScale = max(0.78, 1 - distance * 0.13)
                let tileX     = center.x + pow(distance, 1.5) * arcDepth
                let tileY     = center.y + column * slotSpacing
                let tileAlpha = max(0.0, min(1.0, 1.4 - distance * 0.42))
                holdMenuWheelTile(item: item, selected: selected)
                    .rotationEffect(.degrees(Double(column) * 5))
                    .scaleEffect(tileScale)
                    .position(x: tileX, y: tileY)
                    .opacity(tileAlpha)
                    .zIndex(3 - Double(distance))
            }
        }
    }

    /// Continuous signed column of `index` relative to the live wheel position,
    /// wrapped so the wheel is circular (…-2, -1, 0, +1, +2…). Driving the layout
    /// off `wheelOffset` (not the rounded index) is what makes the spin smooth.
    private func wrappedColumn(for index: Int, count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let n = CGFloat(count)
        var c = (CGFloat(index) - controller.wheelOffset).truncatingRemainder(dividingBy: n)
        if c > n / 2 { c -= n }
        if c <= -n / 2 { c += n }
        return c
    }

    @ViewBuilder
    private func holdMenuWheelTile(item: CubeSubmenuItem, selected: Bool) -> some View {
        let tileSize: CGFloat = selected ? 104 : 88

        VStack(spacing: 7) {
            ZStack {
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

private extension CGFloat {
    /// Clamp to ±limit while preserving sign.
    func clampedMagnitude(to limit: CGFloat) -> CGFloat {
        Swift.min(Swift.max(self, -limit), limit)
    }
}
