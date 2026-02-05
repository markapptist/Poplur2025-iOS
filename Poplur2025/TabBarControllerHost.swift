import SwiftUI

// MARK: - Environment key to pass routed profile userID down the tree, if desired
private struct RoutedUserIDKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var routedUserID: String? {
        get { self[RoutedUserIDKey.self] }
        set { self[RoutedUserIDKey.self] = newValue }
    }
}

// MARK: - Notification names used for routing and preloading
extension Notification.Name {
    static let ShowUserProfile = Notification.Name("ShowUserProfile")
}

struct TabBarControllerHost<MapContent: View, RecordContent: View, FeedContent: View, ProfileContent: View, SettingsContent: View>: View {
    @Binding var selection: AppTab

    let mapReady: Bool
    let feedReady: Bool
    let profileReady: Bool
    let settingsReady: Bool

    let map: () -> MapContent
    let record: () -> RecordContent
    let feed: () -> FeedContent
    let profile: () -> ProfileContent
    let settings: () -> SettingsContent

    // Routed user id when tapping on a username in Feed
    @State private var routedUserID: String? = nil

    init(selection: Binding<AppTab>,
         mapReady: Bool,
         feedReady: Bool,
         profileReady: Bool,
         settingsReady: Bool,
         @ViewBuilder map: @escaping () -> MapContent,
         @ViewBuilder record: @escaping () -> RecordContent,
         @ViewBuilder feed: @escaping () -> FeedContent,
         @ViewBuilder profile: @escaping () -> ProfileContent,
         @ViewBuilder settings: @escaping () -> SettingsContent) {
        _selection = selection
        self.mapReady = mapReady
        self.feedReady = feedReady
        self.profileReady = profileReady
        self.settingsReady = settingsReady
        self.map = map
        self.record = record
        self.feed = feed
        self.profile = profile
        self.settings = settings
    }

    var body: some View {
        TabView(selection: $selection) {
            map()
                .tabItem { Label(AppTab.map.title, systemImage: AppTab.map.systemImage) }
                .tag(AppTab.map)

            record()
                .tabItem { Label(AppTab.record.title, systemImage: AppTab.record.systemImage) }
                .tag(AppTab.record)

            feed()
                .tabItem { Label(AppTab.feed.title, systemImage: AppTab.feed.systemImage) }
                .tag(AppTab.feed)

            // Inject routedUserID into the environment so Profile can consume it.
            profile()
                .environment(\.routedUserID, routedUserID)
                .tabItem { Label(AppTab.profile.title, systemImage: AppTab.profile.systemImage) }
                .tag(AppTab.profile)

            settings()
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
                .tag(AppTab.settings)
        }
        // Listen for Feed’s “show profile” requests
        .onReceive(NotificationCenter.default.publisher(for: .ShowUserProfile)) { note in
            if let uid = note.object as? String {
                routedUserID = uid
                selection = .profile
            }
        }
        // Kick background preloading when the tab bar first appears
        .onAppear {
            // If you added AppPreloader, you can call:
            // AppPreloader.shared.primeAll()

            // Or just post the notifications directly:
            NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
            NotificationCenter.default.post(name: .LoadMapNow, object: nil)
            NotificationCenter.default.post(name: .LoadProfileNow, object: nil)
        }
    }
}
