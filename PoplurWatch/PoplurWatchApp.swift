import FirebaseCore
import SwiftUI

@main
struct PoplurWatchApp: App {
    @StateObject private var radiusStore = WatchRadiusStore()

    init() {
        // The watch is its own Firebase app (PoplurWatch/GoogleService-Info.plist,
        // bundle id …watchkitapp). Configuring it here is what lets Crashlytics
        // report a watch crash; the "Upload Crashlytics dSYMs" phase sends the
        // matching symbols on every build.
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            RadiusWatchView()
                .environmentObject(radiusStore)
        }
    }
}
