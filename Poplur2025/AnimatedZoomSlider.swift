import SwiftUI
import UIKit

struct AnimatedZoomSlider: View {
    @Binding var zoomLevel: Double
    let onZoomChange: (Double) -> Void

    @State private var isDragging = false
    @State private var lastHapticStep = -1

    private let minZoom: Double = 10
    private let maxZoom: Double = 40_000_000
    private let feedback = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let metrics = ZoomSliderMetrics(size: size)
            let normalized = normalizedZoom(zoomLevel)
            let knobY = metrics.trackTop + CGFloat(normalized) * metrics.trackHeight

            ZStack {
                normalPlate(metrics: metrics)

                VStack(spacing: 0) {
                    sliderIcon(systemName: "plus")
                        .frame(height: metrics.iconBand)

                    Spacer(minLength: 0)

                    sliderIcon(systemName: "minus")
                        .frame(height: metrics.iconBand)
                }
                .frame(width: metrics.plateWidth, height: metrics.plateHeight)
                .allowsHitTesting(false)

                sliderTrack(metrics: metrics)
                    .frame(width: metrics.trackVisualWidth, height: metrics.trackHeight)
                    .position(x: size.width / 2, y: metrics.trackCenterY)
                    .allowsHitTesting(false)

                zoomKnob(isDragging: isDragging)
                    .frame(width: metrics.knobWidth, height: metrics.knobHeight)
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

    private func normalPlate(metrics: ZoomSliderMetrics) -> some View {
        RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
            .fill(Color.black.opacity(isDragging ? 0.72 : 0.58))
            .overlay(
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.32), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.24), radius: 7, x: 0, y: 4)
            .frame(width: metrics.plateWidth, height: metrics.plateHeight)
    }

    private func sliderIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .black, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.96))
            .shadow(color: .black.opacity(0.42), radius: 2, x: 0, y: 1)
            .padding(.top, systemName == "plus" ? 5 : 0)
            .padding(.bottom, systemName == "minus" ? 5 : 0)
            .accessibilityHidden(true)
    }

    private func sliderTrack(metrics: ZoomSliderMetrics) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: metrics.trackVisualWidth / 2, style: .continuous)
                .fill(Color.white.opacity(0.72))
                .frame(width: 4)

            VStack(spacing: metrics.notchSpacing) {
                ForEach(0..<8, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(index.isMultiple(of: 3) ? 0.88 : 0.44))
                        .frame(
                            width: index.isMultiple(of: 3) ? 4 : 2.5,
                            height: index.isMultiple(of: 3) ? 4 : 2.5
                        )
                }
            }
        }
    }

    private func zoomKnob(isDragging: Bool) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(white: 0.32),
                        Color(white: 0.16)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.white.opacity(0.52), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.32), radius: isDragging ? 8 : 4, x: 0, y: 2)
            .scaleEffect(isDragging ? 1.16 : 1)
    }
}

private struct ZoomSliderMetrics {
    let size: CGSize

    var plateHeight: CGFloat { max(144, min(size.height, 176)) }
    var plateWidth: CGFloat { min(size.width, 34) }
    var iconBand: CGFloat { min(38, plateHeight * 0.22) }
    var trackTop: CGFloat { (size.height - plateHeight) / 2 + iconBand + 10 }
    var trackHeight: CGFloat { max(72, plateHeight - iconBand * 2 - 20) }
    var trackCenterY: CGFloat { trackTop + trackHeight / 2 }
    var trackVisualWidth: CGFloat { 16 }
    var notchSpacing: CGFloat { max(8, (trackHeight - 28) / 7) }
    var knobWidth: CGFloat { 28 }
    var knobHeight: CGFloat { 20 }
    var cornerRadius: CGFloat { 12 }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
