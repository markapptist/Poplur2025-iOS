import SwiftUI
import MapKit

// MARK: - Floating control stack (right side of map)

struct PoplurMapFloatingControlStack: View {
    let skin: CubeSkin
    var onLocation: () -> Void
    var onStreetView: () -> Void
    var onCompass: () -> Void
    var onZoomIn: () -> Void
    var onZoomOut: () -> Void
    var onThemeCycle: () -> Void

    @State private var compassAngle: Double = 0

    private var theme: PoplurMapThemeData { skin.poplurTheme.mapThemeData }
    private var accent: Color { theme.controlAccent }

    var body: some View {
        VStack(spacing: 10) {
            // Location button
            PoplurGlassCircleButton(skin: skin, systemName: "location.fill", size: 48, action: onLocation)
                .poplurGlow(color: accent, radius: 8, opacity: 0.45)

            // Street view
            PoplurGlassCircleButton(skin: skin, systemName: "binoculars.fill", size: 44, action: onStreetView)

            PoplurGlassDivider(skin: skin).frame(width: 36)

            // Zoom in/out
            PoplurGlassCircleButton(skin: skin, systemName: "plus", size: 42, action: onZoomIn)
            PoplurGlassCircleButton(skin: skin, systemName: "minus", size: 42, action: onZoomOut)

            PoplurGlassDivider(skin: skin).frame(width: 36)

            // Compass
            Button(action: onCompass) {
                ZStack {
                    Circle()
                        .fill(theme.controlBackground)
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.55)
                    Circle()
                        .stroke(accent.opacity(0.5), lineWidth: 1.2)
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                        .rotationEffect(.degrees(compassAngle))
                }
                .frame(width: 44, height: 44)
                .shadow(color: skin.appTheme.shadow, radius: 10, x: 0, y: 4)
            }
            .buttonStyle(.plain)

            // Theme cycle
            PoplurGlassCircleButton(skin: skin, systemName: "paintpalette.fill", size: 40, action: onThemeCycle)
                .poplurGlow(color: accent, radius: 6, opacity: 0.3)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(theme.glassTint.opacity(theme.glassOpacity * 0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(skin.appTheme.border.opacity(0.35), lineWidth: 1)
                )
        )
        .shadow(color: skin.appTheme.shadow.opacity(0.45), radius: 16, x: 0, y: 8)
    }
}

// MARK: - Floating search bar

struct PoplurMapFloatingSearchBar: View {
    let skin: CubeSkin
    @Binding var query: String
    @Binding var isActive: Bool
    var onSubmit: () -> Void
    var onCancel: () -> Void

    @FocusState private var isFocused: Bool

    private var theme: PoplurMapThemeData { skin.poplurTheme.mapThemeData }
    private var accent: Color { theme.searchTint }
    private var appTheme: CubeSkinAppTheme { skin.appTheme }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
                .poplurGlow(color: accent, radius: 5, opacity: 0.5)

            TextField("Search Poplur...", text: $query)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(appTheme.primaryText)
                .tint(accent)
                .focused($isFocused)
                .onSubmit(onSubmit)
                .submitLabel(.search)
                .autocorrectionDisabled()

            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(appTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }

            if isActive {
                Button("Cancel", action: {
                    query = ""
                    isActive = false
                    isFocused = false
                    onCancel()
                })
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(theme.glassTint.opacity(theme.glassOpacity))
                .overlay(Capsule().fill(.ultraThinMaterial).opacity(0.6))
                .overlay(Capsule().stroke(accent.opacity(isFocused ? 0.6 : 0.25), lineWidth: isFocused ? 1.5 : 1))
        )
        .shadow(color: appTheme.shadow.opacity(0.45), radius: 14, x: 0, y: 6)
        .animation(.easeInOut(duration: 0.2), value: isActive)
        .animation(.easeInOut(duration: 0.15), value: query.isEmpty)
        .onTapGesture {
            isActive = true
            isFocused = true
        }
    }
}

// MARK: - Floating AI assistant button

struct PoplurAIAssistantButton: View {
    let skin: CubeSkin
    var action: () -> Void

    @State private var glowPhase: Double = 0

    private var accent: Color { skin.poplurTheme.mapThemeData.controlAccent }
    private var glow: Color { skin.poplurTheme.mapThemeData.markerGlow }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer glow rings
                Circle()
                    .fill(accent.opacity(0.15 + glowPhase * 0.08))
                    .frame(width: 72, height: 72)
                    .blur(radius: 6)
                Circle()
                    .fill(accent.opacity(0.10 + glowPhase * 0.05))
                    .frame(width: 86, height: 86)
                    .blur(radius: 12)
                    .scaleEffect(0.9 + glowPhase * 0.1)

                // Glass base
                Circle()
                    .fill(skin.poplurTheme.mapThemeData.controlBackground)
                Circle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.5)
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [accent, glow, accent],
                            center: .center,
                            startAngle: .degrees(glowPhase * 360),
                            endAngle: .degrees(glowPhase * 360 + 360)
                        ),
                        lineWidth: 2
                    )

                VStack(spacing: 2) {
                    Image(systemName: "waveform")
                        .font(.system(size: 18, weight: .black))
                        .scaleEffect(0.92 + glowPhase * 0.08)
                    Text("POPLUR")
                        .font(.system(size: 6.5, weight: .black, design: .rounded))
                        .tracking(1.2)
                }
                .foregroundStyle(accent)
            }
            .frame(width: 60, height: 60)
        }
        .buttonStyle(.plain)
        .poplurGlow(color: accent, radius: 16, opacity: 0.4 + glowPhase * 0.2)
        .onAppear {
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                glowPhase = 1.0
            }
        }
    }
}

// MARK: - Map toolbar (bottom floating bar)

struct PoplurMapToolbar: View {
    let skin: CubeSkin
    var onProfile: () -> Void
    var onSearch: () -> Void
    var onAI: () -> Void
    var onDirections: () -> Void

    private var theme: PoplurMapThemeData { skin.poplurTheme.mapThemeData }
    private var accent: Color { theme.controlAccent }

    var body: some View {
        HStack(spacing: 0) {
            toolbarButton(systemName: "person.circle.fill", label: "Profile", action: onProfile)
            toolbarDivider
            toolbarButton(systemName: "magnifyingglass", label: "Search", action: onSearch)
            toolbarDivider
            toolbarButton(systemName: "sparkles", label: "AI", action: onAI)
            toolbarDivider
            toolbarButton(systemName: "arrow.triangle.turn.up.right.diamond.fill", label: "Directions", action: onDirections)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.glassTint.opacity(theme.glassOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(skin.appTheme.border.opacity(0.4), lineWidth: 1)
                )
        )
        .shadow(color: skin.appTheme.shadow.opacity(0.5), radius: 20, x: 0, y: 8)
    }

    private var toolbarDivider: some View {
        Rectangle()
            .fill(skin.appTheme.border.opacity(0.3))
            .frame(width: 0.5, height: 32)
    }

    @ViewBuilder
    private func toolbarButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(skin.appTheme.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
