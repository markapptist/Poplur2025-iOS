import SwiftUI

// iPhone tab bar host used by HomeView.
// Bridges AppTab selection to a SwiftUI TabView and renders five tabs via content closures.
struct TabBarControllerHost<MapContent: View,
                            RecordContent: View,
                            FeedContent: View,
                            ProfileContent: View,
                            SettingsContent: View>: View {

    @Binding var selection: AppTab

    // Readiness flags (currently unused inside but kept for future UI tweaks like badges/disabled states)
    let mapReady: Bool
    let feedReady: Bool
    let profileReady: Bool
    let settingsReady: Bool

    // Content builders for each tab
    @ViewBuilder var map: () -> MapContent
    @ViewBuilder var record: () -> RecordContent
    @ViewBuilder var feed: () -> FeedContent
    @ViewBuilder var profile: () -> ProfileContent
    @ViewBuilder var settings: () -> SettingsContent

    var body: some View {
        TabView(selection: $selection) {
            map()
                .tabItem {
                    Label(AppTab.map.title, systemImage: AppTab.map.systemImage)
                }
                .tag(AppTab.map)

            record()
                .tabItem {
                    Label(AppTab.record.title, systemImage: AppTab.record.systemImage)
                }
                .tag(AppTab.record)

            feed()
                .tabItem {
                    Label(AppTab.feed.title, systemImage: AppTab.feed.systemImage)
                }
                .tag(AppTab.feed)

            profile()
                .tabItem {
                    Label(AppTab.profile.title, systemImage: AppTab.profile.systemImage)
                }
                .tag(AppTab.profile)

            settings()
                .tabItem {
                    Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage)
                }
                .tag(AppTab.settings)
        }
        // You can optionally use the readiness booleans to disable tabs until ready:
        // .onAppear / .onChange to apply badges or other UI if needed.
    }
}
