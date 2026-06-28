import SwiftUI

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
private struct PoplurWatchShaderTextRenderer: TextRenderer {
    var time: Double
    var intensity: Double

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(time, intensity) }
        set {
            time = newValue.first
            intensity = newValue.second
        }
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let shimmer = Float(sin(time * 3.4) * 0.5 + 0.5)
        let pulse = Float(sin(time * 2.2) * 0.5 + 0.5)
        let strength = Float(intensity)

        var matrix = ColorMatrix()
        matrix.r1 = 1.0 + (0.18 + shimmer * 0.12) * strength
        matrix.g2 = 1.0 + (0.12 + pulse * 0.10) * strength
        matrix.b3 = 1.0 + (0.22 + shimmer * 0.16) * strength
        matrix.r5 = 0.035 * shimmer * strength
        matrix.g5 = 0.025 * pulse * strength
        matrix.b5 = 0.045 * shimmer * strength

        context.addFilter(.colorMatrix(matrix))
        context.addFilter(
            .shadow(
                color: Color(red: 0.18, green: 0.78, blue: 1.0).opacity(0.32 * intensity),
                radius: 3,
                x: 0,
                y: 0
            )
        )

        for line in layout {
            context.draw(line)
        }
    }
}

private struct PoplurWatchTextShaderScope: ViewModifier {
    var intensity: Float = 0.75

    @State private var epoch = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
            TimelineView(.periodic(from: epoch, by: 1.0 / 30.0)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSince(epoch)

                content
                    .textRenderer(
                        PoplurWatchShaderTextRenderer(
                            time: time,
                            intensity: Double(intensity)
                        )
                    )
            }
        } else {
            content
        }
    }
}

extension View {
    func poplurTextShaderScope(intensity: Float = 0.75) -> some View {
        modifier(PoplurWatchTextShaderScope(intensity: intensity))
    }
}
