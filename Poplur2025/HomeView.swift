import SwiftUI
import CoreLocation
import AVFoundation
import AVKit

private enum AppTab: Hashable {
    case map, record, feed, profile, settings
}

struct HomeView: View {
    @EnvironmentObject private var auth: AuthViewModel

    @State private var selectedTab: AppTab = .record

    // Lazy camera session (created on first Record visit)
    @State private var cameraSession: CameraSession?
    @State private var cameraAuthStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    // Location only when needed
    @StateObject private var locationProvider = LocationProvider()

    // Per-tab readiness reported by child views via PreferenceKeys
    @State private var mapReady = false
    @State private var feedReady = false
    @State private var profileReady = false

    // Tabs that don’t need Firebase preload
    private let recordReady = true
    private let settingsReady = true

    init() {
        // Transparent tab bar look (you can keep or change)
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
        TabView(selection: $selectedTab) {
            // Only insert Map tab once it's ready
            if mapReady {
                MapView()
                    .tag(AppTab.map)
                    .tabItem {
                        Image(systemName: "map")
                        Text("Map")
                    }
            }

            // Record is always available and the initial tab
            ZStack {
                if cameraAuthStatus == .authorized {
                    if let session = cameraSession {
                        PreviewOnlyCamera(session: session.session)
                            .ignoresSafeArea()
                            .background(Color.black)
                        ControlsOverlay(camera: session)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    } else {
                        Color.black.ignoresSafeArea()
                            .task { await ensureCameraSession() }
                    }
                } else if cameraAuthStatus == .denied || cameraAuthStatus == .restricted {
                    PermissionOverlay {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        }
                    }
                    .transition(.opacity)
                } else {
                    Color.black.ignoresSafeArea()
                        .task { await refreshCameraAuthorizationAndStartIfNeeded() }
                }
            }
            .tag(AppTab.record)
            .tabItem {
                Image(systemName: "plus.circle.fill")
                Text("Record")
            }
            .onAppear {
                Task { await ensureCameraSession() }
            }

            // Only insert Feed tab once it's ready
            if feedReady {
                FeedView()
                    .tag(AppTab.feed)
                    .tabItem {
                        Image(systemName: "list.dash")
                        Text("Feed")
                    }
            }

            // Only insert Profile tab once it's ready
            if profileReady {
                ProfileView()
                    .tag(AppTab.profile)
                    .tabItem {
                        Image(systemName: "person.circle")
                        Text("Profile")
                    }
            }

            // Settings is always available
            if settingsReady {
                AppSettingsView()
                    .tag(AppTab.settings)
                    .tabItem {
                        Image(systemName: "gearshape")
                        Text("Settings")
                    }
            }
        }
        .background(Color.clear)
        .toolbarBackground(Color.clear, for: .tabBar)
        .toolbar(.visible, for: .tabBar)
        .onAppear {
            // Force Record tab on entry to HomeView
            selectedTab = .record
            locationProvider.request()
        }
        .onChange(of: auth.isAuthenticated) { authed in
            if authed { selectedTab = .record }
        }
        .onChange(of: selectedTab) { newValue in
            if newValue == .record, cameraAuthStatus == .authorized {
                Task { await cameraSession?.start() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            if cameraAuthStatus == .authorized && selectedTab == .record {
                Task { await cameraSession?.start() }
            }
        }
        // Readiness plumbing from child tabs
        .onPreferenceChange(MapReadyPreferenceKey.self) { ready in
            mapReady = ready
        }
        .onPreferenceChange(FeedReadyPreferenceKey.self) { ready in
            feedReady = ready
        }
        .onPreferenceChange(ProfileReadyPreferenceKey.self) { ready in
            profileReady = ready
        }
        // If camera becomes authorized while on Record, (re)start
        .onChange(of: cameraAuthStatus) { status in
            if status == .authorized, selectedTab == .record {
                Task { await cameraSession?.start() }
            }
        }
    }

    // MARK: - Camera helpers

    private func ensureCameraSession() async {
        if cameraSession == nil {
            let session = CameraSession()
            cameraSession = session
        }
        await refreshCameraAuthorizationAndStartIfNeeded()
    }

    private func refreshCameraAuthorizationAndStartIfNeeded() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraAuthStatus = status
        switch status {
        case .authorized:
            await cameraSession?.start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted, selectedTab == .record {
                        await cameraSession?.start()
                    }
                }
            }
        case .denied, .restricted:
            cameraSession?.stop()
        @unknown default:
            cameraSession?.stop()
        }
    }

    // MARK: - Location provider

    private final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
        @Published var coordinate: CLLocationCoordinate2D?
        private let manager = CLLocationManager()

        override init() {
            super.init()
            manager.delegate = self
        }

        func request() {
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                manager.startUpdatingLocation()
            default:
                break
            }
        }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            coordinate = locations.last?.coordinate
            manager.stopUpdatingLocation()
        }
    }
}

// MARK: - Helper Views

// Preview-only camera layer using the shared AVCaptureSession
private struct PreviewOnlyCamera: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = PreviewContainer()
        view.backgroundColor = .black

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.needsDisplayOnBoundsChange = true
        view.previewLayer = layer
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? PreviewContainer, let layer = view.previewLayer else { return }

        layer.frame = uiView.bounds

        if layer.session !== session {
            layer.session = session
        }

        if let connection = layer.connection, connection.isVideoOrientationSupported {
            let orientation = uiView.window?.windowScene?.interfaceOrientation
            connection.videoOrientation = mapInterfaceOrientation(orientation)
        }
    }

    private func mapInterfaceOrientation(_ io: UIInterfaceOrientation?) -> AVCaptureVideoOrientation {
        switch io {
        case .landscapeLeft:      return .landscapeLeft
        case .landscapeRight:     return .landscapeRight
        case .portraitUpsideDown: return .portraitUpsideDown
        default:                  return .portrait
        }
    }

    private final class PreviewContainer: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer?
        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}

// A lightweight overlay when camera is denied/restricted
private struct PermissionOverlay: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundColor(.white)
            Text("Camera Access Needed")
                .font(.headline)
                .foregroundColor(.white)
            Text("Enable camera permission in Settings to use the Record tab.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Button("Open Settings", action: openSettings)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white)
                .foregroundColor(.black)
                .clipShape(Capsule())
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.65).ignoresSafeArea())
    }
}

// Overlay that contains the capture UI and drives the shared CameraSession
private struct ControlsOverlay: View {
    @ObservedObject var camera: CameraSession
    @State private var showPreview = false
    @State private var capturedImage: UIImage?
    @State private var capturedVideoURL: URL?

    private let tabBarHeight: CGFloat = 88

    var body: some View {
        ZStack {
            Color.clear
                .allowsHitTesting(false)
                .onAppear {
                    Task { await camera.start() }
                }

            // Top-left flash toggle
            VStack {
                HStack {
                    Button {
                        camera.toggleFlash()
                    } label: {
                        Image(systemName: camera.flashMode == .on ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.35), in: Circle())
                    }
                    .padding(.leading, 16)
                    .padding(.top, 56)
                    Spacer()
                }
                Spacer()
            }
            .allowsHitTesting(true)

            // Inline preview overlay
            if showPreview {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea()

                    if let image = capturedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .ignoresSafeArea()
                    } else if let url = capturedVideoURL {
                        InlineVideoPlayer(url: url)
                            .ignoresSafeArea()
                    } else {
                        Text("Nothing captured")
                            .foregroundColor(.white)
                    }

                    VStack {
                        HStack {
                            Button {
                                showPreview = false
                                capturedImage = nil
                                capturedVideoURL = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color.black.opacity(0.35), in: Circle())
                            }
                            .padding(.leading, 16)
                            .padding(.top, 36)
                            Spacer()
                        }
                        Spacer()
                    }
                    .allowsHitTesting(true)
                }
                .transition(.opacity)
                .zIndex(10)
            }

            // Bottom capture controls
            if !showPreview {
                VStack {
                    Spacer()

                    HStack(spacing: 60) {
                        Button {
                            if let img = camera.lastPhoto {
                                capturedImage = img
                                capturedVideoURL = nil
                                showPreview = true
                            } else if let url = camera.lastVideoURL {
                                capturedImage = nil
                                capturedVideoURL = url
                                showPreview = true
                            }
                        } label: {
                            ZStack {
                                if let img = camera.lastPhoto {
                                    Image(uiImage: img)
                                        .resizable()
                                        .scaledToFill()
                                } else if camera.lastVideoURL != nil {
                                    Image(systemName: "video.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .padding(10)
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.3))
                                } else {
                                    Image(systemName: "photo")
                                        .resizable()
                                        .scaledToFit()
                                        .padding(10)
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.3))
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        }

                        Button {
                            switch camera.mode {
                            case .photo:
                                camera.takePhoto()
                            case .video:
                                break
                            }
                        } label: {
                            ZStack {
                                Circle().fill(Color.white.opacity(0.95))
                                Circle().stroke(Color.white, lineWidth: 4)
                                Circle()
                                    .fill(camera.mode == .video ? Color.red : Color.white)
                                    .padding(10)
                                    .scaleEffect(camera.isRecording ? 0.9 : 1.0)
                            }
                            .frame(width: 84, height: 84)
                        }
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.05)
                                .onChanged { _ in
                                    guard camera.mode == .video, !camera.isRecording else { return }
                                    camera.startRecording()
                                }
                                .onEnded { _ in
                                    guard camera.mode == .video else { return }
                                    camera.stopRecording()
                                }
                        )

                        Button {
                            camera.switchCamera()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(18)
                                .background(Color.black.opacity(0.35), in: Circle())
                        }
                    }
                    .padding(.bottom, tabBarHeight)

                    HStack(spacing: 24) {
                        modeLabel("VIDEO", isActive: camera.mode == .video)
                            .onTapGesture { camera.mode = .video }
                        modeLabel("PHOTO", isActive: camera.mode == .photo)
                            .onTapGesture { camera.mode = .photo }
                    }
                    .padding(.bottom, 28 + tabBarHeight)
                }
                .padding(.horizontal)
            }
        }
    }

    private func modeLabel(_ text: String, isActive: Bool) -> some View {
        VStack(spacing: 6) {
            Text(text)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .kerning(0.5)
                .foregroundColor(isActive ? .white : .white.opacity(0.55))
            Rectangle()
                .fill(isActive ? Color.white : Color.clear)
                .frame(width: 24, height: 2)
        }
    }
}

private struct InlineVideoPlayer: View {
    let url: URL
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                player = AVPlayer(url: url)
                player?.play()
            }
            .onDisappear {
                player?.pause()
            }
    }
}
