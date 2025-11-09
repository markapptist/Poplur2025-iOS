import SwiftUI
import CoreLocation
import AVFoundation
import AVKit

extension Notification.Name {
    static let ResetTabToTop = Notification.Name("ResetTabToTop")
}

struct HomeView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: AppTab = .settings

    // Location only when needed
    @StateObject private var locationProvider = LocationProvider()

    // Use injected, shared camera controller (prewarmed in App)
    @ObservedObject var cameraController: CameraKitController

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
            // 1) The visible TabView
            TabView(selection: $selectedTab) {
                MapView()
                    .tag(AppTab.map)
                    .tabItem {
                        Image(systemName: "map")
                        Text("Map")
                    }

                // Record tab uses prewarmed controller
                ZStack {
                    CameraKitView(controller: cameraController, coordinate: locationProvider.coordinate)
                        .ignoresSafeArea()
                }
                .tag(AppTab.record)
                .tabItem {
                    Image(systemName: "plus.circle.fill")
                    Text("Record")
                }

                FeedView()
                    .tag(AppTab.feed)
                    .tabItem {
                        Image(systemName: "list.dash")
                        Text("Feed")
                    }

                ProfileView()
                    .tag(AppTab.profile)
                    .tabItem {
                        Image(systemName: "person.circle")
                        Text("Profile")
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
            .onAppear {
                // Start on Settings tab
                selectedTab = .settings

                // Kick off all heavy work in parallel immediately
                parallelBootstrap()

                // Proactively tell tabs to load
                NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                NotificationCenter.default.post(name: .LoadMapNow, object: nil)
                NotificationCenter.default.post(name: .LoadProfileNow, object: nil)

                // Also tell every tab to reset to its "beginning" once at launch
                NotificationCenter.default.post(name: .ResetTabToTop, object: nil)
            }
            .onChange(of: selectedTab) { _ in
                // On every tab switch, ask all tabs to reset to their beginning
                NotificationCenter.default.post(name: .ResetTabToTop, object: nil)
            }
            .onChange(of: auth.isAuthenticated) { authed in
                if authed {
                    selectedTab = .settings
                    // Re-run bootstrap on auth transitions if needed
                    parallelBootstrap()
                    // Reset again after auth transition
                    NotificationCenter.default.post(name: .ResetTabToTop, object: nil)
                }
            }
            .onChange(of: scenePhase) { phase in
                switch phase {
                case .active:
                    // Relaunch all in parallel when returning to foreground
                    parallelBootstrap()
                case .background, .inactive:
                    // Save power when app leaves foreground
                    cameraController.stop()
                @unknown default:
                    break
                }
            }

            // 2) Hidden prewarm layer that forces construction of every tab view at launch.
            //    This ensures their .onAppear/.task run and caches are hot.
            PrewarmLayer(cameraController: cameraController, coordinate: locationProvider.coordinate)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
                .opacity(0) // ensure fully invisible
                .frame(width: 0, height: 0) // keep out of layout
        }
    }

    // Run camera prewarm, location request, and any other startup tasks concurrently
    private func parallelBootstrap() {
        // 1) Location right away (fast, main-safe)
        locationProvider.request()

        // 2) Feed reload nudge (detached)
        Task.detached(priority: .userInitiated) {
            NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
        }

        // 3) Profile load nudge (detached)
        Task.detached(priority: .userInitiated) {
            NotificationCenter.default.post(name: .LoadProfileNow, object: nil)
        }

        // 4) Map load nudge
        Task.detached(priority: .userInitiated) {
            NotificationCenter.default.post(name: .LoadMapNow, object: nil)
        }

        // 5) Explicitly prewarm the camera controller if already authorized
        Task { @MainActor in
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            if status == .authorized, !cameraController.isReady {
                await cameraController.start()
            }
        }
    }
}

// A hidden view that instantiates each tab’s content once to warm it up.
private struct PrewarmLayer: View {
    let cameraController: CameraKitController
    let coordinate: CLLocationCoordinate2D?

    var body: some View {
        VStack(spacing: 0) {
            // Instantiate each tab’s root view once.
            MapView()
                .onAppear {
                    NotificationCenter.default.post(name: .LoadMapNow, object: nil)
                }

            CameraKitView(controller: cameraController, coordinate: coordinate)
                .onAppear {
                    // Camera prewarm is handled by App and HomeView
                }

            FeedView()
                .onAppear {
                    NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                }

            ProfileView()
                .onAppear {
                    NotificationCenter.default.post(name: .LoadProfileNow, object: nil)
                }

            AppSettingsView()
        }
        .hidden() // hide all content
    }
}
