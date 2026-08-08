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

    // Start on Feed
    @State private var selectedTab: AppTab = .feed

    // Location only when needed
    @StateObject private var locationProvider = LocationProvider()

    // Use injected, shared camera controller (prewarmed in App)
    @ObservedObject var cameraController: CameraKitController

    // One-time flags to avoid doing heavy work repeatedly
    @State private var didWarmAVPlayer = false
    @State private var didTriggerFeedInitialLoad = false
    @State private var didTriggerMapInitialLoad = false
    @State private var didTriggerProfileInitialLoad = false

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
                    CameraKitView(controller: cameraController, coordinate: locationProvider.coordinate)
                        .ignoresSafeArea()
                }
                .tag(AppTab.record)
                .tabItem {
                    Image(systemName: "plus.circle.fill")
                    Text("Record")
                }
                .task {
                    await restartCameraIfNeeded()
                }
                .onAppear {
                    Task { await restartCameraIfNeeded() }
                }

                FeedView()
                    .tag(AppTab.feed)
                    .tabItem {
                        Image(systemName: "list.dash")
                        Text("Feed")
                    }
                    .task {
                        // Lazy: only trigger feed load and AVPlayer warm-up when user visits Feed tab
                        if selectedTab == .feed {
                            if !didTriggerFeedInitialLoad {
                                didTriggerFeedInitialLoad = true
                                NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                            }
                            if !didWarmAVPlayer {
                                didWarmAVPlayer = true
                                await warmAVPlayerPipeline()
                                await activatePlaybackAudioSession()
                            }
                        }
                    }
                    .onAppear {
                        if selectedTab == .feed {
                            if !didTriggerFeedInitialLoad {
                                didTriggerFeedInitialLoad = true
                                NotificationCenter.default.post(name: .LoadFeedNow, object: nil)
                            }
                            Task {
                                if !didWarmAVPlayer {
                                    didWarmAVPlayer = true
                                    await warmAVPlayerPipeline()
                                    await activatePlaybackAudioSession()
                                }
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
                if selectedTab != .feed {
                    NotificationCenter.default.post(name: .PauseAllVideos, object: nil)
                }
                if selectedTab == .record {
                    Task { await restartCameraIfNeeded() }
                }
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
                    if selectedTab == .record {
                        Task { await restartCameraIfNeeded() }
                    }
                case .background, .inactive:
                    cameraController.stop()
                @unknown default:
                    break
                }
            }
        }
    }

    @MainActor
    private func restartCameraIfNeeded() async {
        guard selectedTab == .record else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        if !cameraController.isReady {
            await cameraController.start()
        }
    }

    // Pre-activate playback audio session so first video with sound starts instantly (when feed is opened).
    private func activatePlaybackAudioSession() async {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true, options: [])
        } catch {
            print("[AudioSession] Early activation failed: \(error.localizedDescription)")
        }
    }

    // Optional: warm AVPlayer’s pipeline with a tiny silent item to avoid first-use stall.
    // Now deferred until Feed tab is opened.
    private func warmAVPlayerPipeline() async {
        guard let url = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4") else { return }
        let asset = AVURLAsset(url: url)
        do {
            _ = try await asset.load(.isPlayable)
        } catch {
            return
        }
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.play()
        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s
        player.pause()
    }
}
