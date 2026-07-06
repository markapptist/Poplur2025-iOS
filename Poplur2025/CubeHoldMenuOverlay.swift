import SwiftUI

struct CubeHoldMenuOverlay: View {
    @ObservedObject var controller: CubeMenuWheelController
    @EnvironmentObject private var skinManager: PoplurCubeSkinManager

    init(controller: CubeMenuWheelController) {
        self.controller = controller
    }

    var body: some View {
        let skin = skinManager.current
        ZStack {
            Color.black.opacity(0.50)
                .ignoresSafeArea()
                .onTapGesture {
                    controller.endHold(activateSelected: false)
                }

            // Wheel content — simplified row/grid that adapts to count
            content(for: skin)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(skin.wheelBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(skin.wheelBorder, lineWidth: 1.5)
                        )
                )
                .shadow(color: Color.black.opacity(0.20), radius: 18, x: 0, y: 10)
                .padding(.horizontal, 20)

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
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 22)
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private func content(for skin: PoplurCubeSkin) -> some View {
        let items = controller.items
        if items.count <= 4 {
            HStack(spacing: 18) {
                ForEach(items) { item in
                    wheelItem(item, selected: controller.selectedItem?.id == item.id, skin: skin)
                }
            }
        } else {
            // Wrap into multiple rows for many items
            let rows = Array(items.chunked(into: 4))
            VStack(spacing: 18) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 18) {
                        ForEach(row) { item in
                            wheelItem(item, selected: controller.selectedItem?.id == item.id, skin: skin)
                        }
                    }
                }
            }
        }
    }

    private func wheelItem(_ item: CubeSubmenuItem, selected: Bool, skin: PoplurCubeSkin) -> some View {
        let bg = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button {
            controller.endHold(activateSelected: true)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundColor(selected ? skin.primaryGlow : skin.baseTint)
                Text(item.title)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundColor(selected ? skin.primaryGlow.opacity(0.95) : skin.baseTint.opacity(0.85))
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(minWidth: 72)
            .background(
                ZStack {
                    bg.fill(skin.wheelBackground)
                    if selected {
                        bg.fill(skin.primaryGlow.opacity(min(skin.wheelGlowOpacity, 0.18)))
                        bg.stroke(skin.wheelBorder, lineWidth: 2)
                        bg.stroke(skin.primaryGlow.opacity(0.28), lineWidth: 4)
                    }
                }
            )
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.16), value: selected)
    }
}

// MARK: - Small helpers

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)
        var idx = 0
        while idx < count {
            let end = Swift.min(idx + size, count)
            chunks.append(Array(self[idx..<end]))
            idx = end
        }
        return chunks
    }
}
