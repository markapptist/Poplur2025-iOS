import SwiftUI

private enum PoplurShaderPerformance {
    static let frameInterval: TimeInterval = 1.0 / 12.0
    static let browserFrameInterval: TimeInterval = 1.0 / 15.0

    static func adaptiveInterval(base: TimeInterval, targetFPS: Int) -> TimeInterval {
        max(base, 1.0 / Double(max(1, targetFPS)))
    }
}

@available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *)
private struct PoplurShaderTextRenderer: TextRenderer {
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
        context.addFilter(
            .colorShader(
                ShaderLibrary.poplurNumberGlow(
                    .float(Float(time)),
                    .float(Float(intensity))
                )
            )
        )

        for line in layout {
            context.draw(line)
        }
    }
}

struct PoplurTextShaderScope: ViewModifier {
    var intensity: Float = 0.75
    var animated: Bool = false

    @State private var epoch = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var performance = PoplurPerformanceManager.shared

    @ViewBuilder
    func body(content: Content) -> some View {
        if !performance.postProcessingAllowed {
            content
        } else if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
            if animated && !reduceMotion {
                TimelineView(.periodic(from: epoch, by: PoplurShaderPerformance.adaptiveInterval(base: PoplurShaderPerformance.frameInterval, targetFPS: performance.targetFPS))) { timeline in
                    let time = timeline.date.timeIntervalSince(epoch)

                    content
                        .textRenderer(
                            PoplurShaderTextRenderer(
                                time: time,
                                intensity: Double(intensity)
                            )
                        )
                }
            } else {
                content
                    .textRenderer(
                        PoplurShaderTextRenderer(
                            time: 0,
                            intensity: Double(intensity)
                        )
                    )
            }
        } else {
            content
        }
    }
}

private struct PoplurShaderTimeKey: EnvironmentKey {
    static let defaultValue: Float? = nil
}

private struct PoplurShaderIconIntensityKey: EnvironmentKey {
    static let defaultValue: Float = 0.72
}

private extension EnvironmentValues {
    var poplurShaderTime: Float? {
        get { self[PoplurShaderTimeKey.self] }
        set { self[PoplurShaderTimeKey.self] = newValue }
    }

    var poplurShaderIconIntensity: Float {
        get { self[PoplurShaderIconIntensityKey.self] }
        set { self[PoplurShaderIconIntensityKey.self] = newValue }
    }
}

private struct PoplurShaderLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .poplurIconShader()
            configuration.title
        }
    }
}

struct PoplurGlobalShaderScope: ViewModifier {
    var textIntensity: Float = 0.75
    var iconIntensity: Float = 0.72
    var animated: Bool = false

    @State private var epoch = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var performance = PoplurPerformanceManager.shared

    @ViewBuilder
    func body(content: Content) -> some View {
        if !performance.postProcessingAllowed {
            content
        } else if #available(iOS 17.0, macOS 14.0, tvOS 17.0, watchOS 10.0, *) {
            if animated && !reduceMotion {
                TimelineView(.periodic(from: epoch, by: PoplurShaderPerformance.adaptiveInterval(base: PoplurShaderPerformance.frameInterval, targetFPS: performance.targetFPS))) { timeline in
                    let time = Float(timeline.date.timeIntervalSince(epoch))

                    content
                        .environment(\.poplurShaderTime, time)
                        .environment(\.poplurShaderIconIntensity, iconIntensity)
                        .textRenderer(
                            PoplurShaderTextRenderer(
                                time: Double(time),
                                intensity: Double(textIntensity)
                            )
                        )
                        .labelStyle(PoplurShaderLabelStyle())
                }
            } else {
                content
                    .environment(\.poplurShaderTime, 0)
                    .environment(\.poplurShaderIconIntensity, iconIntensity)
                    .textRenderer(
                        PoplurShaderTextRenderer(
                            time: 0,
                            intensity: Double(textIntensity)
                        )
                    )
                    .labelStyle(PoplurShaderLabelStyle())
            }
        } else {
            content
        }
    }
}

struct MetalNumberShader: ViewModifier {
    var intensity: Float = 1.0
    var animated: Bool = false

    // Stable epoch so time increases monotonically regardless of view rebuilds
    @State private var epoch = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var performance = PoplurPerformanceManager.shared

    @ViewBuilder
    func body(content: Content) -> some View {
        if !performance.postProcessingAllowed {
            content
        } else if #available(iOS 17.0, *) {
            if animated && !reduceMotion {
                TimelineView(.periodic(from: epoch, by: PoplurShaderPerformance.adaptiveInterval(base: PoplurShaderPerformance.frameInterval, targetFPS: performance.targetFPS))) { timeline in
                    let time = Float(timeline.date.timeIntervalSince(epoch))
                    shadered(content, time: time)
                }
            } else {
                shadered(content, time: 0)
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private func shadered(_ content: Content, time: Float) -> some View {
        if #available(iOS 17.0, *) {
            content
                .colorEffect(
                    ShaderLibrary.poplurNumberGlow(
                        .float(time),
                        .float(intensity)
                    )
                )
                .shadow(color: Color(red: 1.0, green: 0.55, blue: 0.12).opacity(Double(0.28 * intensity)), radius: 8, x: 0, y: 0)
                .shadow(color: Color(red: 0.18, green: 0.78, blue: 1.0).opacity(Double(0.18 * intensity)), radius: 12, x: 0, y: 0)
        } else {
            content
        }
    }
}

struct PoplurIconShader: ViewModifier {
    var intensity: Float? = nil
    var animated: Bool = false

    @State private var epoch = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.poplurShaderTime) private var sharedTime
    @Environment(\.poplurShaderIconIntensity) private var inheritedIntensity
    @ObservedObject private var performance = PoplurPerformanceManager.shared

    @ViewBuilder
    func body(content: Content) -> some View {
        if !performance.postProcessingAllowed {
            content
        } else if #available(iOS 17.0, *) {
            if let sharedTime {
                shadered(content, time: reduceMotion ? 0 : sharedTime)
            } else if animated && !reduceMotion {
                TimelineView(.periodic(from: epoch, by: PoplurShaderPerformance.adaptiveInterval(base: PoplurShaderPerformance.frameInterval, targetFPS: performance.targetFPS))) { timeline in
                    let time = reduceMotion ? 0 : Float(timeline.date.timeIntervalSince(epoch))
                    shadered(content, time: time)
                }
            } else {
                shadered(content, time: 0)
            }
        } else {
            content
        }
    }

    @ViewBuilder
    private func shadered(_ content: Content, time: Float) -> some View {
        let resolvedIntensity = intensity ?? inheritedIntensity

        content
            .colorEffect(
                ShaderLibrary.poplurNumberGlow(
                    .float(time),
                    .float(resolvedIntensity)
                )
            )
            .shadow(color: Color(red: 0.18, green: 0.78, blue: 1.0).opacity(Double(0.12 * resolvedIntensity)), radius: 4, x: 0, y: 0)
            .shadow(color: Color(red: 1.0, green: 0.55, blue: 0.12).opacity(Double(0.08 * resolvedIntensity)), radius: 6, x: 0, y: 0)
    }
}

extension View {
    func poplurGlobalShaderScope(textIntensity: Float = 0.75, iconIntensity: Float = 0.72, animated: Bool = false) -> some View {
        modifier(PoplurGlobalShaderScope(textIntensity: textIntensity, iconIntensity: iconIntensity, animated: animated))
    }

    func poplurTextShaderScope(intensity: Float = 0.75, animated: Bool = false) -> some View {
        modifier(PoplurTextShaderScope(intensity: intensity, animated: animated))
    }

    func poplurMetalNumberShader(intensity: Float = 1.0, animated: Bool = false) -> some View {
        modifier(MetalNumberShader(intensity: intensity, animated: animated))
    }

    func poplurTextShader(intensity: Float = 1.0, animated: Bool = false) -> some View {
        poplurMetalNumberShader(intensity: intensity, animated: animated)
    }

    func poplurIconShader(intensity: Float? = nil, animated: Bool = false) -> some View {
        modifier(PoplurIconShader(intensity: intensity, animated: animated))
    }
}

struct BrowserMetalGlassShader: ViewModifier {
    var intensity: Float = 1.0

    @State private var epoch = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var performance = PoplurPerformanceManager.shared

    @ViewBuilder
    func body(content: Content) -> some View {
        if !performance.postProcessingAllowed {
            content
        } else if #available(iOS 17.0, *) {
            TimelineView(.periodic(from: epoch, by: PoplurShaderPerformance.adaptiveInterval(base: PoplurShaderPerformance.browserFrameInterval, targetFPS: performance.targetFPS))) { timeline in
                let time = reduceMotion ? 0 : Float(timeline.date.timeIntervalSince(epoch))

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
