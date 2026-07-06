import SwiftUI
import MapKit

// MARK: - Animated radius pulse annotation

/// Drop this inside a Map Annotation at the post coordinate to show an animated themed pulse.
/// Keep the existing MapCircle for geographic accuracy — this adds beauty on top.
struct PoplurRadiusPulseAnnotation: View {
    let skin: CubeSkin
    var size: CGFloat = 80

    @State private var phase: Double = 0

    private var theme: PoplurMapThemeData { skin.poplurTheme.mapThemeData }
    private var colors: [Color] { theme.radiusColors }
    private var accent: Color { colors.first ?? skin.appTheme.accent }

    var body: some View {
        ZStack {
            switch theme.radiusStyle {
            case .pulse:    pulseRings
            case .ripple:   rippleRings
            case .glow:     glowRings
            case .softBlur: softBlurRings
            case .sparkle:  sparkleRings
            }

            // Center dot
            Circle()
                .fill(accent)
                .frame(width: size * 0.14, height: size * 0.14)
                .shadow(color: accent.opacity(0.9), radius: 6)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 2.4)
                .repeatForever(autoreverses: false)
            ) {
                phase = 1
            }
        }
    }

    // MARK: Pulse — three rings expanding outward

    @ViewBuilder
    private var pulseRings: some View {
        ForEach(0..<3) { i in
            let delay = Double(i) / 3.0
            let t = (phase + delay).truncatingRemainder(dividingBy: 1.0)
            Circle()
                .stroke(ringColor(index: i), lineWidth: 2.5 - Double(i) * 0.5)
                .scaleEffect(0.3 + t * 0.7)
                .opacity(Double(1.0 - t) * 0.85)
        }
    }

    // MARK: Ripple — concentric rings with stagger

    @ViewBuilder
    private var rippleRings: some View {
        ForEach(0..<4) { i in
            let delay = Double(i) / 4.0
            let t = (phase + delay).truncatingRemainder(dividingBy: 1.0)
            Circle()
                .stroke(ringColor(index: i), lineWidth: 1.8)
                .scaleEffect(0.2 + t * 0.8)
                .opacity(Double((1.0 - t) * 0.7))
        }
    }

    // MARK: Glow — single soft glowing ring

    @ViewBuilder
    private var glowRings: some View {
        let t = phase.truncatingRemainder(dividingBy: 1.0)
        let pulseFactor = 0.85 + sin(phase * .pi * 2) * 0.15
        Circle()
            .fill(
                RadialGradient(
                    colors: [accent.opacity(0.55), accent.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .scaleEffect(pulseFactor)
        Circle()
            .stroke(accent.opacity(0.7 + sin(phase * .pi * 2) * 0.3), lineWidth: 2.5)
            .scaleEffect(pulseFactor)
            .blur(radius: 1.5)
        Circle()
            .stroke(colors.last?.opacity(0.4 - t * 0.4) ?? Color.clear, lineWidth: 1)
            .scaleEffect(0.5 + t * 0.5)
            .opacity(1 - t)
    }

    // MARK: Soft blur — diffuse glowing halo

    @ViewBuilder
    private var softBlurRings: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [accent.opacity(0.38 + sin(phase * .pi * 2) * 0.12), accent.opacity(0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .blur(radius: 6)
        ForEach(0..<2) { i in
            let delay = Double(i) * 0.5
            let t = (phase + delay).truncatingRemainder(dividingBy: 1.0)
            Circle()
                .stroke(accent.opacity(0.5 - t * 0.5), lineWidth: 3)
                .scaleEffect(0.4 + t * 0.6)
                .blur(radius: 3)
        }
    }

    // MARK: Sparkle — rings + twinkling dots

    @ViewBuilder
    private var sparkleRings: some View {
        ForEach(0..<3) { i in
            let delay = Double(i) / 3.0
            let t = (phase + delay).truncatingRemainder(dividingBy: 1.0)
            Circle()
                .stroke(ringColor(index: i), lineWidth: 2)
                .scaleEffect(0.25 + t * 0.75)
                .opacity(Double((1.0 - t) * 0.9))
        }
        // Tiny sparkle dots around perimeter
        ForEach(0..<6) { i in
            let angle = Double(i) / 6.0 * .pi * 2 + phase * .pi * 2
            let r = size * 0.42
            let ox = cos(angle) * r
            let oy = sin(angle) * r
            let twinkle = abs(sin(phase * .pi * 4 + Double(i)))
            Circle()
                .fill(ringColor(index: i % colors.count))
                .frame(width: 4, height: 4)
                .offset(x: ox, y: oy)
                .opacity(twinkle * 0.9)
                .scaleEffect(0.5 + twinkle * 0.8)
        }
    }

    private func ringColor(index: Int) -> Color {
        colors.isEmpty ? skin.appTheme.accent : colors[index % colors.count]
    }
}

// MARK: - Screen-space animated glow layer (used in ZStack outside Map)

/// Renders an animated glow ring at a given screen point — used for selected/shown post coordinate.
struct PoplurRadiusScreenGlow: View {
    let skin: CubeSkin
    let center: CGPoint
    let screenRadius: CGFloat

    @State private var phase: Double = 0

    private var theme: PoplurMapThemeData { skin.poplurTheme.mapThemeData }
    private var accent: Color { theme.radiusColors.first ?? skin.appTheme.accent }

    var body: some View {
        ZStack {
            ForEach(0..<3) { i in
                let delay = Double(i) / 3.0
                let t = (phase + delay).truncatingRemainder(dividingBy: 1.0)
                Circle()
                    .stroke(accent.opacity((1.0 - t) * 0.55), lineWidth: 2)
                    .frame(width: screenRadius * 2, height: screenRadius * 2)
                    .scaleEffect(0.6 + t * 0.4)
                    .position(center)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 3.0).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}
