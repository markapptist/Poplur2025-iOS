import SwiftUI

final class RenderingConfig: ObservableObject {
    @Published var enable3DRendering: Bool
    init(enable3DRendering: Bool = true) { self.enable3DRendering = enable3DRendering }
}

private struct RenderingConfigKey: EnvironmentKey {
    static let defaultValue: RenderingConfig = RenderingConfig()
}

extension EnvironmentValues {
    var renderingConfig: RenderingConfig {
        get { self[RenderingConfigKey.self] }
        set { self[RenderingConfigKey.self] = newValue }
    }
}
