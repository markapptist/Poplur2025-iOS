import SwiftUI
import UIKit

struct AnimatedZoomSlider: View {
    @Binding var zoomLevel: Double
    let onZoomChange: (Double) -> Void

    @ObservedObject private var skinStore = CubeSkinStore.shared
    @State private var isDragging = false
    @State private var lastHapticStep = -1

    private let minZoom: Double = 10
    private let maxZoom: Double = 40_000_000
    private let feedback = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let skin = skinStore.current
            let metrics = ZoomSliderMetrics(size: size)
            let normalized = normalizedZoom(zoomLevel)
            let knobY = metrics.trackTop + CGFloat(normalized) * metrics.trackHeight

            ZStack {
                ThemedSkinPlate(
                    skin: skin,
                    tab: .map,
                    cornerRadius: metrics.cornerRadius(for: skin),
                    isPressed: isDragging,
                    borderWidth: skin == .ice ? 2.8 : 2,
                    glowRadius: metrics.glowRadius(for: skin)
                )
                .frame(width: metrics.plateWidth(for: skin), height: metrics.plateHeight)

                VStack(spacing: 0) {
                    sliderIcon(systemName: "plus", skin: skin)
                        .frame(height: metrics.iconBand)

                    Spacer(minLength: 0)

                    sliderIcon(systemName: "minus", skin: skin)
                        .frame(height: metrics.iconBand)
                }
                .frame(width: metrics.plateWidth(for: skin), height: metrics.plateHeight)
                .allowsHitTesting(false)

                sliderTrack(skin: skin, metrics: metrics)
                    .frame(width: metrics.trackVisualWidth, height: metrics.trackHeight)
                    .position(x: size.width / 2, y: metrics.trackCenterY)
                    .allowsHitTesting(false)

                zoomKnob(skin: skin, isDragging: isDragging)
                    .frame(width: metrics.knobSize(for: skin), height: metrics.knobSize(for: skin))
                    .position(x: size.width / 2, y: knobY)
                    .animation(.spring(response: 0.22, dampingFraction: 0.72), value: zoomLevel)
                    .animation(.spring(response: 0.18, dampingFraction: 0.64), value: isDragging)
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            feedback.prepare()
                        }
                        updateZoom(fromY: value.location.y, metrics: metrics)
                    }
                    .onEnded { _ in
                        isDragging = false
                        lastHapticStep = -1
                    }
            )
        }
    }

    private func updateZoom(fromY y: CGFloat, metrics: ZoomSliderMetrics) {
        let clampedY = min(max(y, metrics.trackTop), metrics.trackTop + metrics.trackHeight)
        let normalized = Double((clampedY - metrics.trackTop) / metrics.trackHeight)
        let newZoom = zoomValue(for: normalized)
        zoomLevel = newZoom
        onZoomChange(newZoom)

        let step = Int((1 - normalized) * 8)
        if step != lastHapticStep {
            lastHapticStep = step
            feedback.impactOccurred(intensity: 0.45)
        }
    }

    private func normalizedZoom(_ zoom: Double) -> Double {
        let minLog = log10(minZoom)
        let maxLog = log10(maxZoom)
        let currentLog = log10(zoom.clamped(to: minZoom...maxZoom))
        return ((currentLog - minLog) / (maxLog - minLog)).clamped(to: 0...1)
    }

    private func zoomValue(for normalized: Double) -> Double {
        let minLog = log10(minZoom)
        let maxLog = log10(maxZoom)
        return pow(10, minLog + normalized.clamped(to: 0...1) * (maxLog - minLog))
    }

    private func sliderIcon(systemName: String, skin: CubeSkin) -> some View {
        return Image(systemName: systemName)
            .font(.system(size: iconSize(for: skin), weight: .black, design: .rounded))
            .foregroundStyle(iconStyle(for: skin))
            .shadow(color: glowColor(for: skin), radius: skin == .camo ? 1 : 6)
            .shadow(color: Color.black.opacity(skin == .toy ? 0.16 : 0.52), radius: 2, x: 0, y: 2)
            .padding(.top, systemName == "plus" ? 6 : 0)
            .padding(.bottom, systemName == "minus" ? 6 : 0)
            .accessibilityHidden(true)
    }

    private func sliderTrack(skin: CubeSkin, metrics: ZoomSliderMetrics) -> some View {
        let theme = skin.appTheme
        return ZStack {
            RoundedRectangle(cornerRadius: metrics.trackVisualWidth / 2, style: .continuous)
                .fill(trackFill(for: skin))
                .frame(width: skin == .camo ? 3 : 5)
                .shadow(color: glowColor(for: skin), radius: skin == .camo ? 0 : 4)

            VStack(spacing: metrics.notchSpacing) {
                ForEach(0..<8, id: \.self) { index in
                    Circle()
                        .fill(index.isMultiple(of: 3) ? theme.primaryText : theme.secondaryText)
                        .frame(width: index.isMultiple(of: 3) ? 5 : 3, height: index.isMultiple(of: 3) ? 5 : 3)
                        .shadow(color: glowColor(for: skin), radius: skin == .camo ? 0 : 3)
                }
            }
        }
    }

    private func zoomKnob(skin: CubeSkin, isDragging: Bool) -> some View {
        let theme = skin.appTheme
        return ZStack {
            if skin == .sparklePink || skin == .rainbow {
                Diamond()
                    .fill(
                        LinearGradient(
                            colors: [theme.accent2, theme.accent, Color.white.opacity(0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: theme.accent, radius: isDragging ? 14 : 9)
            } else if skin == .camo {
                ZStack {
                    Circle()
                        .stroke(theme.primaryText.opacity(0.82), lineWidth: 2)
                    Circle()
                        .fill(theme.surfaceStrong.opacity(0.82))
                        .padding(7)
                    Image(systemName: "scope")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(theme.primaryText)
                }
            } else {
                Circle()
                    .fill(theme.accent)
                    .overlay(Circle().stroke(theme.primaryText.opacity(skin == .ice ? 0.92 : 0.55), lineWidth: 2))
                    .shadow(color: glowColor(for: skin), radius: isDragging ? 16 : 10)
            }
        }
        .scaleEffect(isDragging ? 1.22 : 1)
    }

    private func iconSize(for skin: CubeSkin) -> CGFloat {
        switch skin {
        case .camo, .gold, .chocolate: return 20
        default: return 23
        }
    }

    private func iconStyle(for skin: CubeSkin) -> some ShapeStyle {
        switch skin {
        case .rainbow:
            return AnyShapeStyle(
                LinearGradient(colors: [.yellow, .green, .cyan, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        case .toy:
            return AnyShapeStyle(
                LinearGradient(colors: [Color.red, Color.yellow, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        default:
            return AnyShapeStyle(skin.appTheme.primaryText)
        }
    }

    private func trackFill(for skin: CubeSkin) -> some ShapeStyle {
        let theme = skin.appTheme
        switch skin {
        case .rainbow:
            return AnyShapeStyle(
                LinearGradient(colors: [.yellow, .green, .cyan, .pink], startPoint: .top, endPoint: .bottom)
            )
        case .sparklePink:
            return AnyShapeStyle(
                LinearGradient(colors: [theme.accent2, theme.accent, Color.white.opacity(0.72)], startPoint: .top, endPoint: .bottom)
            )
        case .ice:
            return AnyShapeStyle(Color.white.opacity(0.78))
        default:
            return AnyShapeStyle(theme.primaryText.opacity(skin == .camo ? 0.68 : 0.78))
        }
    }

    private func glowColor(for skin: CubeSkin) -> Color {
        switch skin {
        case .ice: return Color.white.opacity(0.82)
        case .sparklePink, .rainbow, .rubber: return skin.appTheme.accent.opacity(0.86)
        default: return skin.appTheme.shadow
        }
    }
}

private struct ZoomSliderMetrics {
    let size: CGSize

    var plateHeight: CGFloat { max(220, min(size.height, 360)) }
    var iconBand: CGFloat { min(62, plateHeight * 0.19) }
    var trackTop: CGFloat { (size.height - plateHeight) / 2 + iconBand + 12 }
    var trackHeight: CGFloat { max(80, plateHeight - iconBand * 2 - 24) }
    var trackCenterY: CGFloat { trackTop + trackHeight / 2 }
    var trackVisualWidth: CGFloat { 22 }
    var notchSpacing: CGFloat { max(12, (trackHeight - 34) / 7) }

    func plateWidth(for skin: CubeSkin) -> CGFloat {
        switch skin {
        case .camo, .gold, .chocolate: return min(size.width, 54)
        default: return min(size.width, 62)
        }
    }

    func knobSize(for skin: CubeSkin) -> CGFloat {
        switch skin {
        case .sparklePink, .rainbow: return 28
        case .camo: return 30
        case .ice: return 32
        default: return 27
        }
    }

    func cornerRadius(for skin: CubeSkin) -> CGFloat {
        switch skin {
        case .camo, .gold, .chocolate: return 13
        case .ice: return 22
        default: return 24
        }
    }

    func glowRadius(for skin: CubeSkin) -> CGFloat {
        switch skin {
        case .ice: return 20
        case .sparklePink, .rainbow: return 18
        case .camo: return 7
        default: return 11
        }
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
