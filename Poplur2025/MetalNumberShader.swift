import SwiftUI

struct MetalNumberShader: ViewModifier {
    var intensity: Float = 1.0

    // Stable epoch so time increases monotonically regardless of view rebuilds
    @State private var epoch = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            // .periodic drives its own 60 fps clock — never stalls under camera/recording load
            TimelineView(.periodic(from: epoch, by: 1.0 / 60.0)) { timeline in
                let time = reduceMotion ? 0 : Float(timeline.date.timeIntervalSince(epoch))

                content
                    .colorEffect(
                        ShaderLibrary.poplurNumberGlow(
                            .float(time),
                            .float(intensity)
                        )
                    )
                    .shadow(color: Color(red: 1.0, green: 0.55, blue: 0.12).opacity(Double(0.28 * intensity)), radius: 8, x: 0, y: 0)
                    .shadow(color: Color(red: 0.18, green: 0.78, blue: 1.0).opacity(Double(0.18 * intensity)), radius: 12, x: 0, y: 0)
            }
        } else {
            content
        }
    }
}

extension View {
    func poplurMetalNumberShader(intensity: Float = 1.0) -> some View {
        modifier(MetalNumberShader(intensity: intensity))
    }
}

struct BrowserMetalGlassShader: ViewModifier {
    var intensity: Float = 1.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            TimelineView(.animation) { timeline in
                let time = reduceMotion ? 0 : Float(timeline.date.timeIntervalSinceReferenceDate)

                content
                    .colorEffect(
                        ShaderLibrary.poplurBrowserGlass(
                            .float(time),
                            .float(intensity)
                        )
                    )
            }
        } else {
            content
        }
    }
}

extension View {
    func poplurBrowserMetalGlass(intensity: Float = 1.0) -> some View {
        modifier(BrowserMetalGlassShader(intensity: intensity))
    }
}
