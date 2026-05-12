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
        tabView
            .onReceive(showUserProfilePublisher, perform: handleShowUserProfile)
            .onChange(of: selection, perform: handleSelectionChange)
            .onAppear(perform: triggerBackgroundPreloading)
    }
    
    // MARK: - View Components
    
    private var tabView: some View {
        TabView(selection: $selection) {
            mapTab
            recordTab
            feedTab
            profileTab
            settingsTab
        }
    }
    
    private var mapTab: some View {
        map()
            .tabItem { Label(AppTab.map.title, systemImage: AppTab.map.systemImage) }
            .tag(AppTab.map)
    }
    
    private var recordTab: some View {
        record()
            .tabItem { Label(AppTab.record.title, systemImage: AppTab.record.systemImage) }
            .tag(AppTab.record)
    }
    
    private var feedTab: some View {
        feed()
            .tabItem { Label(AppTab.feed.title, systemImage: AppTab.feed.systemImage) }
            .tag(AppTab.feed)
    }
    
    private var profileTab: some View {
        // Inject routedUserID into the environment so Profile can consume it.
        profile()
            .environment(\.routedUserID, routedUserID)
            .tabItem { Label(AppTab.profile.title, systemImage: AppTab.profile.systemImage) }
            .tag(AppTab.profile)
    }
    
    private var settingsTab: some View {
        settings()
            .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
            .tag(AppTab.settings)
    }
    
    // MARK: - Helper Properties
    
    private var showUserProfilePublisher: NotificationCenter.Publisher {
        let name: Notification.Name = .ShowUserProfile
        return NotificationCenter.default.publisher(for: name)
    }
    
    // MARK: - Helper Methods
    
    private func handleShowUserProfile(_ note: Notification) {
        // Listen for Feed's "show profile" requests
        if let uid = note.object as? String {
            print("🔔 [TabBarController] Received ShowUserProfile for userID: '\(uid)'")
            routedUserID = uid
            selection = .profile
        }
    }
    
    private func handleSelectionChange(_ newTab: AppTab) {
        if newTab != .profile && routedUserID != nil {
            print("🔔 [TabBarController] Clearing routedUserID (switched from profile to \(newTab.title))")
            routedUserID = nil
        }
    }
    
    private func triggerBackgroundPreloading() {
        // Kick background preloading when the tab bar first appears
        // If you added AppPreloader, you can call:
        // AppPreloader.shared.primeAll()
        
        // Or just post the notifications directly:
        let feedName: Notification.Name = .LoadFeedNow
        let mapName: Notification.Name = .LoadMapNow
        let profileName: Notification.Name = .LoadProfileNow
        
        NotificationCenter.default.post(name: feedName, object: nil)
        NotificationCenter.default.post(name: mapName, object: nil)
        NotificationCenter.default.post(name: profileName, object: nil)
    }
}
