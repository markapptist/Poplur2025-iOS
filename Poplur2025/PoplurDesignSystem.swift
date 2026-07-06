import SwiftUI

// MARK: - Poplur Design System
// Central design tokens for the soft, rounded, pink UI language.

enum DS {

    // MARK: Colors
    enum Color {
        /// Soft pink-blush app background
        static let background = SwiftUI.Color(red: 1.0, green: 0.925, blue: 0.955)
        /// Pure white card surface
        static let card = SwiftUI.Color.white
        /// Soft pink card used for hero/featured areas
        static let pinkCard = SwiftUI.Color(red: 1.0, green: 0.88, blue: 0.93)
        /// Soft lavender card for secondary sections
        static let lavenderCard = SwiftUI.Color(red: 0.91, green: 0.87, blue: 1.0)
        /// Brand pink accent #FF2D96
        static let accent = SwiftUI.Color(red: 1.0, green: 0.176, blue: 0.588)
        /// Near-black primary text
        static let textPrimary = SwiftUI.Color(red: 0.08, green: 0.08, blue: 0.10)
        /// Medium-gray secondary text
        static let textSecondary = SwiftUI.Color(red: 0.54, green: 0.54, blue: 0.58)
        /// Hairline separator / border
        static let border = SwiftUI.Color(red: 0.92, green: 0.86, blue: 0.90)
        /// Light fill for inputs and toggle tracks
        static let fill = SwiftUI.Color(red: 0.97, green: 0.92, blue: 0.95)
        /// Stronger fill for grouped rows
        static let fillStrong = SwiftUI.Color(red: 0.94, green: 0.89, blue: 0.92)
    }

    // MARK: Corner Radius
    enum Radius {
        static let card: CGFloat    = 22
        static let button: CGFloat  = 50
        static let icon: CGFloat    = 16
        static let small: CGFloat   = 12
        static let input: CGFloat   = 14
        static let avatar: CGFloat  = 20
    }

    // MARK: Shadow
    enum Shadow {
        static let card   = (color: SwiftUI.Color.black.opacity(0.06), radius: 14.0, x: 0.0, y: 6.0)
        static let hero   = (color: SwiftUI.Color.black.opacity(0.10), radius: 20.0, x: 0.0, y: 8.0)
        static let button = (color: SwiftUI.Color.black.opacity(0.12), radius: 10.0, x: 0.0, y: 5.0)
    }

    // MARK: Typography
    enum Font {
        static func title(_ size: CGFloat = 28) -> SwiftUI.Font {
            .system(size: size, weight: .black, design: .rounded)
        }
        static func heading(_ size: CGFloat = 20) -> SwiftUI.Font {
            .system(size: size, weight: .heavy, design: .rounded)
        }
        static func body(_ size: CGFloat = 16) -> SwiftUI.Font {
            .system(size: size, weight: .semibold, design: .rounded)
        }
        static func label(_ size: CGFloat = 14) -> SwiftUI.Font {
            .system(size: size, weight: .bold, design: .rounded)
        }
        static func caption(_ size: CGFloat = 13) -> SwiftUI.Font {
            .system(size: size, weight: .medium, design: .rounded)
        }
    }
}

// MARK: - View Modifiers

struct PoplurCardModifier: ViewModifier {
    var fill: Color
    init(fill: Color = DS.Color.card) { self.fill = fill }
    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .shadow(color: DS.Shadow.card.color, radius: DS.Shadow.card.radius, x: DS.Shadow.card.x, y: DS.Shadow.card.y)
    }
}

struct PoplurHeroCardModifier: ViewModifier {
    var fill: Color
    init(fill: Color = DS.Color.pinkCard) { self.fill = fill }
    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
            .shadow(color: DS.Shadow.hero.color, radius: DS.Shadow.hero.radius, x: DS.Shadow.hero.x, y: DS.Shadow.hero.y)
    }
}

struct PoplurPrimaryButtonModifier: ViewModifier {
    var color: Color
    init(color: Color = DS.Color.accent) { self.color = color }
    func body(content: Content) -> some View {
        content
            .font(DS.Font.body())
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(color, in: Capsule())
            .shadow(color: color.opacity(0.30), radius: DS.Shadow.button.radius, x: DS.Shadow.button.x, y: DS.Shadow.button.y)
    }
}

struct PoplurSecondaryButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DS.Font.body())
            .foregroundColor(DS.Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(DS.Color.fill, in: Capsule())
    }
}

struct PoplurInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DS.Font.body())
            .foregroundColor(DS.Color.textPrimary)
            .tint(DS.Color.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(DS.Color.fill, in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                    .stroke(DS.Color.border, lineWidth: 1)
            )
    }
}

struct PoplurSearchFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DS.Font.body(15))
            .foregroundColor(DS.Color.textPrimary)
            .tint(DS.Color.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(DS.Color.card, in: Capsule())
            .shadow(color: DS.Shadow.card.color, radius: 10, x: 0, y: 4)
    }
}

struct PoplurBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.background(DS.Color.background.ignoresSafeArea())
    }
}

// MARK: - Sparkle Background

struct PoplurSparkleBackground: View {
    private struct Speck: Identifiable {
        let id: Int
        let x: CGFloat   // 0–1 of width
        let y: CGFloat   // 0–1 of height
        let size: CGFloat
        let isStar: Bool  // star shape vs circle dot
        let baseOpacity: CGFloat
        let pulsePhase: CGFloat  // 0–2π
    }

    private static let specks: [Speck] = (0..<52).map { i in
        let h = Double(i * 6271 &+ 1234) / Double(UInt32.max) // deterministic pseudo-random
        let h2 = Double(i * 9431 &+ 5678) / Double(UInt32.max)
        let h3 = Double(i * 3719 &+ 9999) / Double(UInt32.max)
        return Speck(
            id: i,
            x: CGFloat((Double(i * 7919) .truncatingRemainder(dividingBy: 1000)) / 1000),
            y: CGFloat((Double(i * 6133) .truncatingRemainder(dividingBy: 1000)) / 1000),
            size: CGFloat(2.0 + h3 * 5.0),
            isStar: i % 3 != 0,
            baseOpacity: CGFloat(0.12 + h2 * 0.20),
            pulsePhase: CGFloat(h * .pi * 2)
        )
    }

    @State private var tick: CGFloat = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            Canvas { context, size in
                let t = CGFloat(ctx.date.timeIntervalSinceReferenceDate)
                for speck in Self.specks {
                    let pulse = 0.5 + 0.5 * sin(t * 0.8 + speck.pulsePhase)
                    let alpha = speck.baseOpacity * (0.55 + 0.45 * pulse)
                    let cx = speck.x * size.width
                    let cy = speck.y * size.height
                    let s = speck.size
                    var path = Path()
                    if speck.isStar {
                        // 4-pointed star
                        let arm: CGFloat = s
                        let inner: CGFloat = s * 0.28
                        for i in 0..<8 {
                            let angle = CGFloat(i) * .pi / 4
                            let r = i.isMultiple(of: 2) ? arm : inner
                            let px = cx + r * cos(angle)
                            let py = cy + r * sin(angle)
                            if i == 0 { path.move(to: CGPoint(x: px, y: py)) }
                            else { path.addLine(to: CGPoint(x: px, y: py)) }
                        }
                        path.closeSubpath()
                    } else {
                        path.addEllipse(in: CGRect(x: cx - s * 0.5, y: cy - s * 0.5, width: s, height: s))
                    }
                    context.fill(path, with: .color(.white.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct PoplurSparkleBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            PoplurSparkleBackground()
                .ignoresSafeArea()
            content
        }
    }
}

// MARK: - Flat Tab Bar

struct PoplurFlatTabBar: View {
    @Binding var selectedTab: AppTab

    private func tabIcon(for tab: AppTab) -> String {
        switch tab {
        case .map:     return "house.fill"
        case .feed:    return "heart.fill"
        case .profile: return "person.fill"
        default:       return tab.systemImage
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // Map
            flatTabButton(icon: "house.fill", tab: .map)
            // Feed
            flatTabButton(icon: "heart.fill", tab: .feed)
            // Record — center raised pink + button
            Button {
                selectedTab = .record
            } label: {
                ZStack {
                    Circle()
                        .fill(DS.Color.accent)
                        .frame(width: 54, height: 54)
                        .shadow(color: DS.Color.accent.opacity(0.38), radius: 12, x: 0, y: 5)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(.white)
                }
                .offset(y: -10)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            // Feed/explore
            flatTabButton(icon: "magnifyingglass", tab: .feed)
            // Profile
            flatTabButton(icon: "person.fill", tab: .profile)
        }
        .frame(height: 56)
        .padding(.bottom, 2)
        .background(
            SwiftUI.Color.white
                .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func flatTabButton(icon: String, tab: AppTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: selectedTab == tab ? .black : .regular))
                .foregroundColor(selectedTab == tab ? DS.Color.accent : SwiftUI.Color(red: 0.62, green: 0.60, blue: 0.64))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile Quick Action Card

struct PoplurQuickActionCard: View {
    let icon: String
    let label: String
    let iconColor: SwiftUI.Color
    let iconBg: SwiftUI.Color
    var isHighlighted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(isHighlighted ? DS.Color.accent : iconBg)
                        .frame(width: 52, height: 52)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(isHighlighted ? .white : iconColor)
                }
                Text(label)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(DS.Color.textPrimary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile Stats Row

struct PoplurProfileStatsRow: View {
    let posts: Int
    let followers: Int
    let following: Int

    var body: some View {
        HStack(spacing: 0) {
            statCell(value: posts, label: "Posts")
            Divider().frame(height: 36)
            statCell(value: followers, label: "Followers")
            Divider().frame(height: 36)
            statCell(value: following, label: "Following")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .poplurCard()
    }

    private func statCell(value: Int, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value >= 1000 ? String(format: "%.1fK", Double(value) / 1000) : "\(value)")
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundColor(DS.Color.textPrimary)
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(DS.Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - View Extensions

extension View {
    func poplurCard(fill: Color = DS.Color.card) -> some View {
        modifier(PoplurCardModifier(fill: fill))
    }

    func poplurHeroCard(fill: Color = DS.Color.pinkCard) -> some View {
        modifier(PoplurHeroCardModifier(fill: fill))
    }

    func poplurPrimaryButton(color: Color = DS.Color.accent) -> some View {
        modifier(PoplurPrimaryButtonModifier(color: color))
    }

    func poplurSecondaryButton() -> some View {
        modifier(PoplurSecondaryButtonModifier())
    }

    func poplurInput() -> some View {
        modifier(PoplurInputModifier())
    }

    func poplurSearchField() -> some View {
        modifier(PoplurSearchFieldModifier())
    }

    func poplurScreenBackground() -> some View {
        modifier(PoplurBackgroundModifier())
    }

    func poplurSparkleBackground() -> some View {
        modifier(PoplurSparkleBackgroundModifier())
    }
}

// MARK: - Reusable Components

struct PoplurSectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(DS.Font.heading())
                .foregroundColor(DS.Color.textPrimary)
            Spacer()
            if let action, let onAction {
                Button(action: onAction) {
                    Text(action)
                        .font(DS.Font.label())
                        .foregroundColor(DS.Color.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct PoplurDivider: View {
    var body: some View {
        Divider()
            .overlay(DS.Color.border)
    }
}

struct PoplurRowSeparator: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle()
            .fill(DS.Color.border)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}
