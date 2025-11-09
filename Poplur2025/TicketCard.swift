import SwiftUI

struct TicketCard<Stats: View, Settings: View>: View {
    @Binding var pageIndex: Int
    @Binding var isPrivateAccount: Bool
    @Binding var notificationsEnabled: Bool
    @Binding var isLoadingStats: Bool

    let statsHeaderTitle: String
    let settingsHeaderTitle: String
    let statsPage: () -> Stats
    let settingsPage: () -> Settings
    let brandPink: Color

    private let corner: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            // Header with two segments
            headerBar

            // Content area
            ZStack {
                if pageIndex == 0 {
                    statsPage()
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                } else {
                    settingsPage()
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.0))
        }
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.white.opacity(0.18))
        )
        .overlay(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: 12)
    }

    private var headerBar: some View {
        HStack(spacing: 8) {
            segmentButton(title: statsHeaderTitle, index: 0)
            segmentButton(title: settingsHeaderTitle, index: 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(brandPink.opacity(0.15))
        )
    }

    private func segmentButton(title: String, index: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                pageIndex = index
            }
        } label: {
            Text(title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(index == pageIndex ? Color.black : Color.white.opacity(0.9))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(index == pageIndex ? Color.white : Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}

