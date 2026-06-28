import SwiftUI

@main
struct PoplurWatchApp: App {
    @StateObject private var radiusStore = WatchRadiusStore()

    var body: some Scene {
        WindowGroup {
            RadiusWatchView()
                .environmentObject(radiusStore)
                .background(Color.black.ignoresSafeArea())
                .poplurTextShaderScope(intensity: 0.75)
        }
    }
}
