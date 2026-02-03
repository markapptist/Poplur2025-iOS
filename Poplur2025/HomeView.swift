import SwiftUI
import CoreLocation
import AVFoundation

extension Notification.Name {
    static let ResetTabToTop = Notification.Name("ResetTabToTop")
}

struct HomeView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase

    // Start on Feed
    @State private var selectedTab: AppTab = .feed

    // Location only when needed
    @StateObject private var locationProvider = LocationProvider()

    // Use injected, shared camera controller (prewarmed in App)
    @ObservedObject var cameraController: CameraKitController

    // One-time flags to avoid doing heavy work repeatedly
    @State private var didTriggerFeedInitialLoad = false
    @State private var didTriggerMapInitialLoad = false
    @State private var didTriggerProfileInitialLoad = false
    @State private var didStartCameraOnce = false

    init(cameraController: CameraKitController) {
        self.cameraController = cameraController

        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = nil
        appearance.backgroundColor = .clear
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        UITabBar.appearance().isTranslucent = true
    }

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                MapView()
                    .tag(AppTab.map)
                    .tabItem {
                        Image(systemName: "map")
                        Text("Map")
                    }
                    .task {
                        // Lazy: only trigger map load once when user visits Map tab
                        if selectedTab == .map, !didTriggerMapInitialLoad {
                            didTriggerMapInitialLoad = true
                            NotificationCenter.default.post(name: .LoadMapNow, object: nil)
                        }
                    }
                    .onAppear {
                        if selectedTab == .map, !didTriggerMapInitialLoad {
                            didTriggerMapInitialLoad = true
                            NotificationCenter.default.post(name: .LoadMapNow, object: nil)
                        }
                    }

                ZStack {
                    CameraPreviewHost(controller: cameraController, coordinate: locationProvider.coordinate)
                        .ignoresSafeArea()
                }
                .tag(AppTab.record)
                .tabItem {
                    Image(systemName: "plus.circle.fill")
                    Text("Record")
                }
                .task {
                    // Lazy: only start camera once when user visits Record tab
                    Task { @MainActor in
                        guard selectedTab == .record else { return }
                        if !didStartCameraOnce {
                            didStartCameraOnce = true
                            let status = AVCaptureDevice.authorizationStatus(for: .video)
                            if status == .authorized, !cameraController.isReady {
                                await cameraController.start()
                            }
                        }
                    }
                }
                .onAppear {
                    Task { @MainActor in
                        guard selectedTab == .record else { return }
                        if !didStartCameraOnce {
                            didStartCameraOnce = true
                            let status = AVCaptureDevice.authorizationStatus(for: .video)
                            if status == .authorized, !cameraController.isReady {
                                await cameraController.start()
                            }
                        }
                    }
                }

                FeedView()
                    .tag(AppTab.feed)
                    .tabItem {
                        Image(systemName: "list.dash")
                        Text("Feed")
                    }
                    .task {
                        // Lazy: only trigger feed load when user visits Feed tab
                        if selectedTab == .feed {
                            if !didTriggerFeedInitialLoad {
                                didTriggerFeedInitialLoad = true
                                NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                            }
                        }
                    }
                    .onAppear {
                        if selectedTab == .feed {
                            if !didTriggerFeedInitialLoad {
                                didTriggerFeedInitialLoad = true
                                NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                            }
                        }
                    }

                ProfileView()
                    .tag(AppTab.profile)
                    .tabItem {
                        Image(systemName: "person.circle")
                        Text("Profile")
                    }
                    .task {
                        // Lazy: only trigger profile load once when user visits Profile tab
                        if selectedTab == .profile, !didTriggerProfileInitialLoad {
                            didTriggerProfileInitialLoad = true
                            NotificationCenter.default.post(name: .LoadProfileNow, object: nil)
                        }
                    }
                    .onAppear {
                        if selectedTab == .profile, !didTriggerProfileInitialLoad {
                            didTriggerProfileInitialLoad = true
                            NotificationCenter.default.post(name: .LoadProfileNow, object: nil)
                        }
                    }

                AppSettingsView()
                    .tag(AppTab.settings)
                    .tabItem {
                        Image(systemName: "gearshape")
                        Text("Settings")
                    }
            }
            .background(Color.clear)
            .toolbarBackground(Color.clear, for: .tabBar)
            .toolbar(.visible, for: .tabBar)
            .task {
                // Minimal bootstrap: start location early (cheap) and trigger feed load if feed is initial tab
                locationProvider.request()
                if selectedTab == .feed, !didTriggerFeedInitialLoad {
                    didTriggerFeedInitialLoad = true
                    NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                }
            }
            .onAppear {
                // Keep startup minimal; no mass notifications
                locationProvider.request()
                if selectedTab == .feed, !didTriggerFeedInitialLoad {
                    didTriggerFeedInitialLoad = true
                    NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                }
            }
            .onChange(of: selectedTab) { _ in
                // Only reset-to-top on tab changes; no mass loads
                NotificationCenter.default.post(name: .ResetTabToTop, object: nil)
            }
            .onChange(of: auth.isAuthenticated) { authed in
                if authed {
                    selectedTab = .feed
                    if !didTriggerFeedInitialLoad {
                        didTriggerFeedInitialLoad = true
                        NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                    }
                }
            }
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .active:
                    // No-op; we’ll lazily start heavy work when tabs appear
                    break
                case .background, .inactive:
                    cameraController.stop()
                @unknown default:
                    break
                }
            }
        }
    }
}

