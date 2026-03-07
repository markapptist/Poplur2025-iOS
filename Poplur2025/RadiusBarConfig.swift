import SwiftUI
import SceneKit

public struct RadiusBarConfig {
    public let baseColor: Color
    public let tintColor: Color
    public let maxSceneHeight: Double
    public let uiScale: CGFloat
    public let growthSpeed: Double
    public let useNormalMap: Bool
    public let lightingModel: SCNMaterial.LightingModel
    public let autoLoop: Bool
    public let maxRuntimeRadius: Double

    public init(baseColor: Color,
                tintColor: Color,
                maxSceneHeight: Double,
                uiScale: CGFloat,
                growthSpeed: Double,
                useNormalMap: Bool,
                lightingModel: SCNMaterial.LightingModel,
                autoLoop: Bool,
                maxRuntimeRadius: Double) {
        self.baseColor = baseColor
        self.tintColor = tintColor
        self.maxSceneHeight = maxSceneHeight
        self.uiScale = uiScale
        self.growthSpeed = growthSpeed
        self.useNormalMap = useNormalMap
        self.lightingModel = lightingModel
        self.autoLoop = autoLoop
        self.maxRuntimeRadius = maxRuntimeRadius
    }
}

extension RadiusBarConfig {
    // Adaptive colors and defaults derived from the IsometricRadiusBar preview
    static func forTab(_ tab: AppTab, colorScheme: ColorScheme) -> RadiusBarConfig {
        // Adaptive base color: darker in dark mode, slightly lighter in light mode
        let base: Color = {
            switch colorScheme {
            case .dark: return Color(white: 0.15)
            default:    return Color(white: 0.2)
            }
        }()
        // Adaptive tint per tab; keep same hues but allow minor brightness shift in dark mode
        func tint(for tab: AppTab) -> Color {
            switch tab {
            case .record:  return colorScheme == .dark ? Color.indigo.opacity(0.95) : .indigo
            case .feed:    return colorScheme == .dark ? Color.teal.opacity(0.95) : .teal
            case .profile: return colorScheme == .dark ? Color.pink.opacity(0.95) : .pink
            case .map:     return colorScheme == .dark ? Color.green.opacity(0.95) : .green
            default:    return colorScheme == .dark ? Color.accentColor.opacity(0.95) : .accentColor
            }
        }
        return RadiusBarConfig(
            baseColor: base,
            tintColor: tint(for: tab),
            maxSceneHeight: 1.8,
            uiScale: 1.5,
            growthSpeed: 1.5,
            useNormalMap: true,
            lightingModel: .physicallyBased,
            autoLoop: false,
            maxRuntimeRadius: 3_323_000.0
        )
    }
}

public struct ConfiguredRadiusBar: View {
    @Binding var radius: Double
    let tab: AppTab

    @Environment(\.colorScheme) private var colorScheme

    init(radius: Binding<Double>, tab: AppTab) {
        self._radius = radius
        self.tab = tab
    }

    public var body: some View {
        let cfg = RadiusBarConfig.forTab(tab, colorScheme: colorScheme)
        var bar = IsometricRadiusBar(
            radius: $radius,
            baseColor: cfg.baseColor,
            tintColor: cfg.tintColor,
            growthSpeed: cfg.growthSpeed,
            maxSceneHeight: cfg.maxSceneHeight,
            uiScale: cfg.uiScale,
            maxRuntimeRadius: cfg.maxRuntimeRadius
        )
        bar.useNormalMap = cfg.useNormalMap
        bar.lightingModel = cfg.lightingModel
        bar.autoLoop = cfg.autoLoop
        return bar
    }
}

#Preview("Configured Radius Bars") {
    VStack(spacing: 24) {
        StateWrapper(initial: 0.0) { $r in
            VStack {
                Text("Record").font(.caption)
                ConfiguredRadiusBar(radius: $r, tab: .record).frame(height: 220)
            }
        }
        StateWrapper(initial: 0.0) { $r in
            VStack {
                Text("Feed").font(.caption)
                ConfiguredRadiusBar(radius: $r, tab: .feed).frame(height: 220)
            }
        }
        StateWrapper(initial: 0.0) { $r in
            VStack {
                Text("Profile").font(.caption)
                ConfiguredRadiusBar(radius: $r, tab: .profile).frame(height: 220)
            }
        }
        StateWrapper(initial: 0.0) { $r in
            VStack {
                Text("Map").font(.caption)
                ConfiguredRadiusBar(radius: $r, tab: .map).frame(height: 220)
            }
        }
    }
    .padding()
}

// Small helper to create local @State in previews for multiple instances
private struct StateWrapper<Value, Content: View>: View {
    @State private var value: Value
    let content: (Binding<Value>) -> Content
    init(initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }
    var body: some View { content($value) }
}

