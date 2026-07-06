import SwiftUI
import MapKit

// MARK: - Map Profile Card

/// Beautiful card that appears when a map marker is selected.
struct PoplurMapProfileCard: View {
    let skin: CubeSkin
    let item: PoplurMapCardItem
    var onDismiss: () -> Void
    var onDirections: (() -> Void)? = nil
    var onProfile: (() -> Void)? = nil

    @State private var appear = false

    private var theme: PoplurMapThemeData { skin.poplurTheme.mapThemeData }
    private var appTheme: CubeSkinAppTheme { skin.appTheme }
    private var accent: Color { theme.controlAccent }

    var body: some View {
        PoplurGlassCard(skin: skin, cornerRadius: 24) {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    avatarView
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundStyle(appTheme.primaryText)
                            .lineLimit(1)
                        if let subtitle = item.subtitle {
                            Text(subtitle)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(appTheme.secondaryText)
                                .lineLimit(1)
                        }
                        if let distance = item.distanceLabel {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(accent)
                                Text(distance)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(accent)
                            }
                        }
                    }
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(appTheme.secondaryText.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, item.stats.isEmpty ? 16 : 12)

                // Stats row
                if !item.stats.isEmpty {
                    PoplurGlassDivider(skin: skin)
                    HStack(spacing: 0) {
                        ForEach(item.stats.indices, id: \.self) { i in
                            statCell(item.stats[i])
                            if i < item.stats.count - 1 {
                                Rectangle()
                                    .fill(appTheme.border.opacity(0.35))
                                    .frame(width: 0.5, height: 32)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    PoplurGlassDivider(skin: skin)
                }

                // Radius badge
                if let radius = item.radiusLabel {
                    HStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(accent.opacity(0.15))
                                .frame(width: 28, height: 28)
                            Image(systemName: "circle.dashed")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(accent)
                        }
                        Text("Radius: \(radius)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(appTheme.secondaryText)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    PoplurGlassDivider(skin: skin)
                }

                // Action buttons
                HStack(spacing: 12) {
                    if let directionsAction = onDirections {
                        actionButton(
                            label: "Directions",
                            icon: "arrow.triangle.turn.up.right.diamond.fill",
                            style: .primary,
                            action: directionsAction
                        )
                    }
                    if let profileAction = onProfile {
                        actionButton(
                            label: "View",
                            icon: "person.circle.fill",
                            style: .secondary,
                            action: profileAction
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .scaleEffect(appear ? 1 : 0.85)
        .opacity(appear ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                appear = true
            }
        }
    }

    // MARK: Sub-views

    @ViewBuilder
    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.18))
                .frame(width: 54, height: 54)
            if let avatarURL = item.avatarURL, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    defaultAvatar
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                defaultAvatar
            }
        }
        .overlay(
            Circle()
                .stroke(
                    LinearGradient(colors: [accent, accent.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 2
                )
        )
        .poplurGlow(color: accent, radius: 8, opacity: 0.3)
    }

    private var defaultAvatar: some View {
        Image(systemName: item.avatarSystemName ?? "person.fill")
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(accent)
    }

    private func statCell(_ stat: PoplurMapCardStat) -> some View {
        VStack(spacing: 3) {
            Text(stat.value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(appTheme.primaryText)
            Text(stat.label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(appTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private enum ActionStyle { case primary, secondary }

    private func actionButton(label: String, icon: String, style: ActionStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                style == .primary
                    ? AnyView(Capsule().fill(accent))
                    : AnyView(Capsule().fill(appTheme.controlFill))
            )
            .foregroundStyle(style == .primary ? Color.white : appTheme.primaryText)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card data model

struct PoplurMapCardItem {
    let title: String
    var subtitle: String? = nil
    var avatarURL: String? = nil
    var avatarSystemName: String? = "mappin.circle.fill"
    var distanceLabel: String? = nil
    var radiusLabel: String? = nil
    var stats: [PoplurMapCardStat] = []

    static func from(username: String?, city: String?, country: String?, flag: String?, radius: Double?) -> PoplurMapCardItem {
        var stats: [PoplurMapCardStat] = []
        if let city { stats.append(PoplurMapCardStat(value: city, label: "City")) }
        if let flag { stats.append(PoplurMapCardStat(value: flag, label: "Country")) }
        let radiusLabel: String? = radius.map { r in
            r >= 1000 ? String(format: "%.1f km", r / 1000) : String(format: "%.0f m", r)
        }
        return PoplurMapCardItem(
            title: username ?? "Poplur User",
            subtitle: [city, country].compactMap { $0 }.joined(separator: ", "),
            avatarSystemName: "person.circle.fill",
            radiusLabel: radiusLabel,
            stats: stats
        )
    }
}

struct PoplurMapCardStat {
    let value: String
    let label: String
}
