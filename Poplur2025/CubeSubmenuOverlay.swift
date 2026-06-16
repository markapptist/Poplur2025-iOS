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

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white
                    .opacity(controller.isVisible ? 0.56 : 0)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.22), value: controller.isVisible)

                ZStack {
                    wheelTrack(in: proxy.size)

                    ForEach(Array(controller.items.enumerated()), id: \.element.id) { index, item in
                        let slot = slotIndex(for: index)
                        let selected = index == controller.selectedIndex

                        CubeMenuWheelItem(item: item, selected: selected)
                            .position(position(forSlot: slot, in: proxy.size))
                            .scaleEffect(controller.isVisible ? (selected ? 1.18 : 0.9) : 0.3)
                            .opacity(controller.isVisible ? opacity(forSlot: slot) : 0)
                            .zIndex(selected ? 3 : Double(2 - abs(slot - centerSlot)))
                            .animation(.spring(response: 0.34, dampingFraction: 0.72), value: controller.selectedIndex)
                            .animation(.spring(response: 0.34, dampingFraction: 0.74), value: controller.isVisible)
                    }
                }
                .rotationEffect(.degrees(controller.isVisible ? 0 : -16), anchor: .bottom)
            }
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
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
        return distance >= 3 ? 0.72 : 1
    }

    private func position(forSlot slot: Int, in size: CGSize) -> CGPoint {
        let count = max(controller.items.count, 1)
        let cubeCenterX = size.width / 2
        let cubeCenterY = size.height - min(max(size.height * 0.16, 158), 210)
        let radius = min(max(size.width * 0.31, 126), 178)
        let arcStart: CGFloat = 214
        let arcEnd: CGFloat = 326
        let progress = count == 1 ? 0.5 : CGFloat(slot) / CGFloat(count - 1)
        let degrees = arcStart + (arcEnd - arcStart) * progress
        let radians = degrees * .pi / 180

        return CGPoint(
            x: cubeCenterX + cos(radians) * radius,
            y: cubeCenterY + sin(radians) * radius
        )
    }

    @ViewBuilder
    private func wheelTrack(in size: CGSize) -> some View {
        let cubeCenterY = size.height - min(max(size.height * 0.16, 158), 210)
        let trackWidth = min(max(size.width * 0.74, 280), 420)
        let trackHeight = min(max(size.width * 0.38, 138), 220)

        ZStack {
            ArcShape(startAngle: .degrees(214), endAngle: .degrees(326))
                .stroke(
                    AngularGradient(
                        colors: [
                            .green,
                            .cyan,
                            .indigo,
                            .orange,
                            .green
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .opacity(controller.isVisible ? 0.85 : 0)
                .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 6)
        }
        .frame(width: trackWidth, height: trackHeight)
        .position(x: size.width / 2, y: cubeCenterY)
        .scaleEffect(controller.isVisible ? 1 : 0.8)
        .animation(.spring(response: 0.34, dampingFraction: 0.74), value: controller.isVisible)
    }
}

private struct CubeMenuWheelItem: View {
    let item: CubeSubmenuItem
    let selected: Bool

    var body: some View {
        Image(systemName: item.systemImage)
            .font(.system(size: selected ? 31 : 25, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: selected ? 82 : 68, height: selected ? 82 : 68)
            .background {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.black.opacity(0.98),
                                Color(red: 0.04, green: 0.05, blue: 0.08).opacity(0.98)
                            ],
                            center: .topLeading,
                            startRadius: 4,
                            endRadius: 66
                        )
                    )
                    .overlay(
                        Circle()
                            .stroke(item.tint, lineWidth: selected ? 5 : 3)
                    )
                    .shadow(color: item.tint.opacity(selected ? 0.52 : 0.3), radius: selected ? 18 : 11, x: 0, y: 7)
                    .shadow(color: .black.opacity(0.22), radius: 16, x: 0, y: 12)
            }
            .overlay(alignment: .bottom) {
                if selected {
                    Text(item.title)
                        .font(.system(size: 10, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(item.tint.opacity(0.94)))
                        .offset(y: 18)
                }
            }
            .accessibilityLabel(item.title)
    }
}

private struct ArcShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}
