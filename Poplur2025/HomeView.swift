import SwiftUI
import CoreLocation
import AVFoundation
import AVKit

private enum AppTab: Hashable {
    case map, record, feed, profile, settings
}

struct HomeView: View {
    @State private var selectedTab: AppTab = .record
    @StateObject private var locationProvider = LocationProvider()

    // Single shared camera session
    @StateObject private var cameraSession = CameraSession()

    @State private var cameraAuthStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

    // Preload flags
    @State private var shouldPreloadMap = true
    @State private var shouldPreloadFeed = true
    @State private var shouldPreloadProfile = true

    init() {
        // Transparent tab bar (we will override at runtime until ready)
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

    // When all preloaders are done, UI is "ready"
    private var uiReady: Bool {
        !shouldPreloadMap && !shouldPreloadFeed && !shouldPreloadProfile
    }

    var body: some View {
        ZStack {
            // 1) Background camera for non-record tabs
            if selectedTab != .record && cameraAuthStatus == .authorized {
                CameraView(session: cameraSession, coordinate: locationProvider.coordinate)
                    .ignoresSafeArea()
                    .background(Color.black)
                    .zIndex(0)
                    .accessibilityHidden(true)
            }

            // 1.5) Deterministic preloaders (invisible)
            if shouldPreloadMap {
                PreloadMapView(onReady: { shouldPreloadMap = false })
                    .opacity(0.0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if shouldPreloadFeed {
                PreloadFeedView(onReady: { shouldPreloadFeed = false })
                    .opacity(0.0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if shouldPreloadProfile {
                PreloadProfileView(onReady: { shouldPreloadProfile = false })
                    .opacity(0.0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            // 2) Foreground tabs
            TabView(selection: $selectedTab) {
                // Map tab appears when ready
                if !shouldPreloadMap {
                    MapView()
                        .tag(AppTab.map)
                        .tabItem {
                            Image(systemName: "map")
                            Text("Map")
                        }
                }

                // Record tab
                ZStack {
                    if cameraAuthStatus == .authorized {
                        PreviewOnlyCamera(session: cameraSession.session)
                            .id(cameraSession.isRunning) // ensure preview layer rebuilds after start/stop
                            .ignoresSafeArea()
                            .background(Color.black)
                        ControlsOverlay(camera: cameraSession)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    } else if cameraAuthStatus == .denied || cameraAuthStatus == .restricted {
                        PermissionOverlay {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                            }
                        }.transition(.opacity)
                    } else {
                        Color.black.ignoresSafeArea()
                    }
                }
                .tag(AppTab.record)
                .tabItem {
                    Image(systemName: "plus.circle.fill")
                    Text("Record")
                }

                // Feed tab appears when ready
                if !shouldPreloadFeed {
                    FeedView()
                        .tag(AppTab.feed)
                        .tabItem {
                            Image(systemName: "list.dash")
                            Text("Feed")
                        }
                }

                // Profile tab appears when ready
                if !shouldPreloadProfile {
                    ProfileView()
                        .tag(AppTab.profile)
                        .tabItem {
                            Image(systemName: "person.circle")
                            Text("Profile")
                        }
                }

                // Settings is always available
                SettingsView()
                    .tag(AppTab.settings)
                    .tabItem {
                        Image(systemName: "gearshape")
                        Text("Settings")
                    }
            }
            // While not ready, use a non-clear background so the tab bar doesn’t look “glassy”
            .background(uiReady ? Color.clear : Color(white: 0.05))
            // Switch the tab bar background style depending on readiness:
            // first parameter is a ShapeStyle (Color), second is visibility (.visible/.hidden)
            .toolbarBackground(uiReady ? Color.clear : Color(white: 0.05), for: .tabBar)
            .toolbar(.visible, for: .tabBar)
            .zIndex(1)
        }
        .onAppear {
            locationProvider.request()
            Task { await refreshCameraAuthorizationAndStartIfNeeded() }
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }
        .onChange(of: selectedTab) { newValue in
            // Ensure session is running when returning to Record tab
            if newValue == .record && cameraAuthStatus == .authorized {
                Task { await cameraSession.start() }
            } else {
                Task { await refreshCameraAuthorizationAndStartIfNeeded() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await refreshCameraAuthorizationAndStartIfNeeded() }
        }
    }

    // Estimate a reasonable tab bar height. You can tweak this constant if needed.
    private var tabBarHeight: CGFloat { 88 }

    // MARK: - Permission + session lifecycle

    private func refreshCameraAuthorizationAndStartIfNeeded() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        cameraAuthStatus = status
        print("HomeView: cameraAuthStatus =", status.rawValue)

        switch status {
        case .authorized:
            await cameraSession.start()
            print("HomeView: ensured cameraSession started, isRunning =", cameraSession.isRunning)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    cameraAuthStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    print("HomeView: requestAccess result =", granted, "status =", cameraAuthStatus.rawValue)
                    if granted {
                        await cameraSession.start()
                        print("HomeView: post-permission ensured start, isRunning =", cameraSession.isRunning)
                    }
                }
            }
        case .denied, .restricted:
            if cameraSession.isRunning {
                cameraSession.stop()
                print("HomeView: permission not allowed, stopped session.")
            }
        @unknown default:
            if cameraSession.isRunning {
                cameraSession.stop()
                print("HomeView: unknown status, stopped session.")
            }
        }
    }
}

// MARK: - Preference keys

struct MapReadyPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct FeedReadyPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

struct ProfileReadyPreferenceKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

// MARK: - Invisible preload wrappers

private struct PreloadMapView: View {
    let onReady: () -> Void
    @State private var didSignal = false

    var body: some View {
        MapView()
            .onPreferenceChange(MapReadyPreferenceKey.self) { ready in
                guard ready, !didSignal else { return }
                didSignal = true
                onReady()
            }
    }
}

private struct PreloadFeedView: View {
    let onReady: () -> Void
    @State private var didSignal = false

    var body: some View {
        FeedView()
            .onPreferenceChange(FeedReadyPreferenceKey.self) { ready in
                guard ready, !didSignal else { return }
                didSignal = true
                onReady()
            }
    }
}

private struct PreloadProfileView: View {
    let onReady: () -> Void
    @State private var didSignal = false

    var body: some View {
        ProfileView()
            .onPreferenceChange(ProfileReadyPreferenceKey.self) { ready in
                guard ready, !didSignal else { return }
                didSignal = true
                onReady()
            }
    }
}

// Preview-only camera layer using the shared AVCaptureSession
private struct PreviewOnlyCamera: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = PreviewContainer()
        view.backgroundColor = .clear

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.needsDisplayOnBoundsChange = true
        view.previewLayer = layer
        view.layer.addSublayer(layer

        )
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let view = uiView as? PreviewContainer,
              let layer = view.previewLayer else { return }
        layer.frame = uiView.bounds

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

// Simple location provider for background camera
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

    // Mirror HomeView’s estimate so controls clear the tab bar
    private let tabBarHeight: CGFloat = 88

    var body: some View {
        ZStack {
            Color.clear
                .allowsHitTesting(false)
                .onAppear {
                    // Defensive: ensure session is running when overlay appears
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
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .disabled(!isTorchOrFlashAvailable)
                    .padding(.leading, 16)
                    .padding(.top, 56)

                    Spacer()
                }
                Spacer()
            }
            .allowsHitTesting(true)

            // Inline preview overlay (appears above camera when a capture exists)
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

                    // Close button top-left
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
                                    .background(.ultraThinMaterial, in: Circle())
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

            // Bottom capture controls (hidden when preview is showing)
            if !showPreview {
                VStack {
                    Spacer()

                    // Buttons row (slightly above the mode labels)
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
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }
                    // Place this row slightly above the mode labels by using a larger bottom padding
                    .padding(.bottom, tabBarHeight)

                    // Mode labels row at the bottom
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

    private var isTorchOrFlashAvailable: Bool {
        guard let device = cameraValueDevice else { return false }
        return device.hasTorch || device.isFlashAvailable
    }

    private var cameraValueDevice: AVCaptureDevice? {
        AVCaptureDevice.default(for: .video)
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
