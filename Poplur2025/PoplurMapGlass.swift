import SwiftUI

// MARK: - Glassmorphism building block

/// A themed glass surface that respects the current cube skin.
struct PoplurGlassCard<Content: View>: View {
    let skin: CubeSkin
    var cornerRadius: CGFloat = 20
    var borderWidth: CGFloat = 1.2
    @ViewBuilder let content: () -> Content

    private var theme: CubeSkinAppTheme { skin.appTheme }
    private var tint: Color { skin.poplurTheme.mapThemeData.glassTint }
    private var blur: CGFloat { skin.poplurTheme.mapThemeData.glassBlur }
    private var opacity: Double { skin.poplurTheme.mapThemeData.glassOpacity }

    var body: some View {
        content()
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint.opacity(opacity))
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.62)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                theme.border.opacity(0.80),
                                theme.accent.opacity(0.40),
                                theme.border.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: borderWidth
                    )
            )
            .shadow(color: theme.shadow, radius: 18, x: 0, y: 8)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: - Glass pill (for small controls)

struct PoplurGlassPill<Content: View>: View {
    let skin: CubeSkin
    @ViewBuilder let content: () -> Content

    private var theme: CubeSkinAppTheme { skin.appTheme }
    private var tint: Color { skin.poplurTheme.mapThemeData.glassTint }
    private var blur: CGFloat { skin.poplurTheme.mapThemeData.glassBlur }
    private var opacity: Double { skin.poplurTheme.mapThemeData.glassOpacity }

    var body: some View {
        content()
            .background(
                ZStack {
                    Capsule()
                        .fill(tint.opacity(opacity))
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .opacity(0.58)
                }
            )
            .overlay(
                Capsule()
                    .stroke(theme.border.opacity(0.56), lineWidth: 1)
            )
            .shadow(color: theme.shadow.opacity(0.5), radius: 10, x: 0, y: 4)
    }
}

// MARK: - Glass circle button

struct PoplurGlassCircleButton: View {
    let skin: CubeSkin
    let systemName: String
    var size: CGFloat = 48
    var action: () -> Void

    @State private var isPressed = false
    private var theme: CubeSkinAppTheme { skin.appTheme }
    private var accent: Color { skin.poplurTheme.mapThemeData.controlAccent }
    private var bg: Color { skin.poplurTheme.mapThemeData.controlBackground }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(bg)
                Circle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.55)
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [accent.opacity(0.7), theme.border.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                Image(systemName: systemName)
                    .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
            }
            .frame(width: size, height: size)
            .scaleEffect(isPressed ? 0.93 : 1.0)
            .shadow(color: theme.shadow, radius: 12, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.12)) { isPressed = pressing }
        }, perform: {})
        .accessibilityLabel(systemName)
    }
}

// MARK: - Glow modifier

struct PoplurGlowModifier: ViewModifier {
    let color: Color
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(opacity), radius: radius)
            .shadow(color: color.opacity(opacity * 0.5), radius: radius * 0.5)
    }
}

extension View {
    func poplurGlow(color: Color, radius: CGFloat = 12, opacity: Double = 0.7) -> some View {
        modifier(PoplurGlowModifier(color: color, radius: radius, opacity: opacity))
    }
}

// MARK: - Themed divider

struct PoplurGlassDivider: View {
    let skin: CubeSkin
    var body: some View {
        Rectangle()
            .fill(skin.appTheme.border.opacity(0.4))
            .frame(height: 0.5)
    }
}
