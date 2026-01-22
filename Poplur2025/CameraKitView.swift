import SwiftUI
import AVFoundation
import AVKit
import CoreLocation
import SCSDKCameraKit
import SCSDKCameraKitReferenceUI
import SCSDKCameraKitReferenceSwiftUI

@MainActor
struct CameraKitView: View {
    @StateObject private var ownedController = CameraKitController()
    private var injectedController: CameraKitController?
    var controller: CameraKitController { injectedController ?? ownedController }

    let coordinate: CLLocationCoordinate2D?

    @State private var showPreview = false
    @State private var capturedImage: UIImage?
    @State private var capturedVideoURL: URL?

    @State private var permissionDenied = false
    @State private var permissionNotDetermined = true

    @State private var showFocusReticle = false
    @State private var focusPoint: CGPoint = .zero

    @State private var currentZoom: CGFloat = 1.0
    @State private var baseZoomAtGestureStart: CGFloat = 1.0
    @State private var showTapToast = false
    @State private var tapToastMessage: String = ""

    @State private var showRecordingBanner = false
    @State private var showPhotoFlash = false

    @State private var diagTapPoint: CGPoint = .zero
    @State private var showDiagDot = false

    @State private var isLongPressingRecord = false

    private let carouselHeight: CGFloat = 110
    private let captureButtonSize: CGFloat = 84
    private let rightRailSpacing: CGFloat = 14

    init(controller: CameraKitController? = nil, coordinate: CLLocationCoordinate2D?) {
        self.injectedController = controller
        self.coordinate = coordinate
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if permissionDenied {
                    PermissionOverlay {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        }
                    }
                    .zIndex(40)
                    .allowsHitTesting(false)
                } else {
                    cameraPreviewWithGestures
                        .zIndex(0)
                }

                // Removed debugOverlay as per instructions

                // TEMP: stripped gestures/rail for tap isolation
                rightActionRail
                    .padding(.trailing, 25)
                    .padding(.top, 28 + topSafeInset(in: geo))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .zIndex(101)
                    .allowsHitTesting(true)

                if controller.mode == .video && controller.isRecording {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .shadow(color: .red.opacity(0.6), radius: 3)
                        Text("REC")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.5), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .padding(.leading, 12)
                    .padding(.top, 28 + topSafeInset(in: geo))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .zIndex(40)
                    .allowsHitTesting(false)
                }

                // Removed live HUD showing mode/isRecording/isReady (debug overlay)

                // Temporary toast for tap confirmation
                if showTapToast {
                    Text(tapToastMessage)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.75), in: Capsule())
                        .padding(.bottom, dynamicBottomInset(in: geo) + 120)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .transition(.opacity)
                        .zIndex(40)
                        .allowsHitTesting(false)
                }

                // Visible recording banner at top center
                if showRecordingBanner {
                    HStack(spacing: 8) {
                        Circle().fill(Color.red).frame(width: 8, height: 8)
                        Text("Recording…")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.55), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .padding(.top, 28 + topSafeInset(in: geo))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
                    .zIndex(40)
                    .allowsHitTesting(false)
                }

                // Fullscreen white flash for photo capture
                Color.white
                    .opacity(showPhotoFlash ? 0.85 : 0.0)
                    .ignoresSafeArea()
                    .animation(.easeOut(duration: 0.35), value: showPhotoFlash)
                    .zIndex(40)
                    .allowsHitTesting(false)

                // Full-screen tap diagnostic overlay (does not block bottom controls)
                Color.clear
                    .contentShape(Rectangle())
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            let size = UIScreen.main.bounds.size
                            // Place the dot roughly at the center horizontally and near the bottom third to reflect general area
                            diagTapPoint = CGPoint(x: size.width / 2, y: size.height * 0.75)
                            showDiagDot = true
                            print("[Diag] Top-level tap received")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                showDiagDot = false
                            }
                        }
                    )
                    .allowsHitTesting(false)
                    .zIndex(40)

                // Render diagnostic dot when a tap is detected
                if showDiagDot {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 18, height: 18)
                        .position(diagTapPoint)
                        .transition(.opacity)
                        .zIndex(40)
                        .allowsHitTesting(false)
                }

                bottomStack
                    .padding(.bottom, dynamicBottomInset(in: geo) + 60)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .contentShape(Rectangle())
                    .allowsHitTesting(true)
                    .zIndex(100)
            }
            .background(Color.black)
            .task {
                if injectedController == nil {
                    await ensurePermissionAndStart()
                } else {
                    let status = AVCaptureDevice.authorizationStatus(for: .video)
                    permissionDenied = (status == .denied || status == .restricted)
                    permissionNotDetermined = (status == .notDetermined)
                    if status == .authorized, !controller.isReady {
                        await controller.start()
                    }
                }
            }
            .onAppear {
                print("[CK][UI] CameraKitView appeared")
                print("[CameraKitView] Record tab appearing; will assert camera and audio session")
                NotificationCenter.default.post(name: Notification.Name("RecordTabDidAppear"), object: nil)
                Task { await maybeStartIfAuthorizedAndNotReady() }
            }
            .onAppear {
                print("[CameraKitView] Appeared. isReady: \(controller.isReady)")
                let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
                let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                print("[CameraKitView] Camera permission: \(camStatus.rawValue), Mic permission: \(micStatus.rawValue)")
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playAndRecord, mode: .videoRecording, options: [.defaultToSpeaker, .allowBluetooth])
                    try session.setActive(true, options: .notifyOthersOnDeactivation)
                    print("[CameraKitView] AVAudioSession activated for recording")
                } catch {
                    print("[CameraKitView] Failed to activate AVAudioSession: \(error)")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .ResetTabToTop)) { _ in
                // Reset camera UI state to "beginning"
                currentZoom = 1.0
                baseZoomAtGestureStart = 1.0
                controller.setZoom(factor: 1.0)
                let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                focusPoint = center
                showFocusReticle = false
            }
            .onChange(of: controller.lastPhoto) { img in
                capturedVideoURL = nil
                capturedImage = img
                if img != nil {
                    showPreview = true
                    NotificationCenter.default.post(name: Notification.Name("FeedRefreshRequested"), object: nil)
                }
            }
            .onChange(of: controller.lastVideoURL) { url in
                capturedImage = nil
                capturedVideoURL = url
                if url != nil {
                    showPreview = true
                    NotificationCenter.default.post(name: Notification.Name("FeedRefreshRequested"), object: nil)
                }
            }
            .onChange(of: controller.isRecording) { rec in
                withAnimation(.easeInOut(duration: 0.2)) {
                    showRecordingBanner = rec
                }
            }
            .sheet(isPresented: $showPreview) {
                CameraKitCapturePreviewView(
                    image: capturedImage,
                    videoURL: capturedVideoURL,
                    coordinate: coordinate
                )
            }
            .onDisappear {
                print("[CameraKitView] Record tab did disappear; deactivating audio session")
                do {
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                } catch {
                    print("[CameraKitView] Failed to deactivate AVAudioSession: \(error)")
                }
                NotificationCenter.default.post(name: Notification.Name("RecordTabDidDisappear"), object: nil)
            }
        }
        .ignoresSafeArea()
    }

    private func maybeStartIfAuthorizedAndNotReady() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized, !controller.isReady {
            await controller.start()
        }

        // Lightweight retry in case initial start races with view lifecycle
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            let status2 = AVCaptureDevice.authorizationStatus(for: .video)
            if status2 == .authorized, !controller.isReady {
                await controller.start()
            }
        }
    }

    private var cameraPreviewWithGestures: some View {
        ZStack {
            if let session = controller.cameraKitSession {
                // TEMP: stripped gestures/rail for tap isolation
                PreviewView(cameraKit: session)
                    .contentShape(Rectangle())
                    .onAppear {
                        Task { await maybeStartIfAuthorizedAndNotReady() }
                    }
            } else {
                Color.black
                    .onAppear {
                        Task { await maybeStartIfAuthorizedAndNotReady() }
                    }
            }

            if showFocusReticle {
                Circle()
                    .stroke(Color.yellow, lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .position(focusPoint)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.2), value: showFocusReticle)
            }
        }
    }

    // Removed debugOverlay completely as per instructions

    private var rightActionRail: some View {
        VStack(spacing: rightRailSpacing) {
            /*
            // Removed debug HStack that showed Ready and Cam permission
            HStack(spacing: 8) {
                Text("Ready: \(controller.isReady ? "YES" : "NO")")
                Text("Cam: \(AVCaptureDevice.authorizationStatus(for: .video).rawValue)")
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.6), in: Capsule())
            */

            Button {
                print("[UI] switchCamera tapped. isReady: \(controller.isReady)")
                Task { @MainActor in controller.switchCamera() }
            } label: {
                Circle()
                    .fill(Color.black.opacity(controller.isReady ? 0.45 : 0.25))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .foregroundColor(.white.opacity(controller.isReady ? 1.0 : 0.5))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!controller.isReady)

            Button {
                // Optional: if controller exposes torch availability, log here. Otherwise, this serves as a placeholder for visibility.
                if !controller.flashOn {
                    print("[UI] Attempting to enable torch; ensure active device supports torch.")
                }
                print("[UI] torch tapped. isReady: \(controller.isReady), flashOn: \(controller.flashOn)")
                Task { @MainActor in controller.setTorch(on: !controller.flashOn) }
            } label: {
                Circle()
                    .fill(Color.black.opacity(controller.isReady ? 0.45 : 0.25))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: controller.flashOn ? "bolt.fill" : "bolt.slash.fill")
                            .foregroundColor(
                                .white.opacity((controller.isReady && controller.isTorchAvailable) ? 1.0 : 0.3)
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!controller.isReady || !controller.isTorchAvailable)

            Button {
                // Placeholder for More button action
            } label: {
                Circle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "ellipsis")
                            .foregroundColor(.white)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!controller.isReady)
        }
    }

    private var bottomStack: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()

                // Updated to new gesture logic: simultaneous LongPressGesture + TapGesture
                ZStack {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.8), lineWidth: 6)
                        .frame(width: captureButtonSize, height: captureButtonSize)

                    if controller.mode == .video {
                        if controller.isRecording {
                            Circle()
                                .fill(Color.red)
                                .frame(width: captureButtonSize * 0.5, height: captureButtonSize * 0.5)
                        } else {
                            Circle()
                                .fill(Color.white.opacity(controller.isReady ? 1.0 : 0.5))
                                .frame(width: captureButtonSize * 0.7, height: captureButtonSize * 0.7)
                        }
                    } else {
                        Circle()
                            .fill(Color.white.opacity(controller.isReady ? 1.0 : 0.5))
                            .frame(width: captureButtonSize * 0.7, height: captureButtonSize * 0.7)
                    }
                }
                .contentShape(Rectangle())
                .frame(minWidth: 140, minHeight: 140)
                .allowsHitTesting(controller.isReady)
                .simultaneousGesture(
                    TapGesture()
                        .onEnded {
                            print("[UI] Capture tap. isReady: \(controller.isReady), isRecording: \(controller.isRecording), isLongPressingRecord: \(isLongPressingRecord)")
                            print("[UI] captureSessionRunning: \(controller.captureSessionRunning)")
                            guard controller.isReady, !isLongPressingRecord else {
                                print("[CameraKitView] TapGesture ignored: either not ready or long press active.")
                                return
                            }
                            // Removed guard for cameraKitSession == nil here as per instructions

                            if controller.mode == .video {
                                print("[CameraKitView] TapGesture in video mode: toggling recording")
                                if controller.isRecording {
                                    Task { @MainActor in controller.stopRecording() }
                                } else {
                                    Task { @MainActor in controller.startRecording() }
                                }
                                return
                            }
                            // Tap triggers photo capture; long-press handles video recording.
                            print("[CameraKitView] TapGesture: taking photo")
                            showPhotoFlash = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                showPhotoFlash = false
                            }
                            Task { @MainActor in
                                controller.takePhoto()
                            }
                        }
                )
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .onChanged { _ in
                            print("[UI] LongPress changed. isReady: \(controller.isReady), isRecording: \(controller.isRecording), isLongPressingRecord: \(isLongPressingRecord)")
                            guard controller.isReady, !controller.isRecording, !isLongPressingRecord else { return }
                            controller.mode = .video
                            // Removed guard for cameraKitSession == nil here as per instructions
                            print("[CameraKitView] LongPressGesture began: starting video recording")
                            isLongPressingRecord = true
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showRecordingBanner = true
                            }
                            Task { @MainActor in
                                controller.startRecording()
                            }
                        }
                        .onEnded { _ in
                            print("[UI] LongPress ended. isReady: \(controller.isReady), isRecording: \(controller.isRecording)")
                            guard controller.isReady else {
                                isLongPressingRecord = false
                                return
                            }
                            isLongPressingRecord = false
                            // Removed guard for cameraKitSession == nil here as per instructions
                            guard controller.mode == .video, controller.isRecording else { return }
                            print("[CameraKitView] LongPressGesture ended: stopping video recording")
                            Task { @MainActor in
                                controller.stopRecording()
                            }
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showRecordingBanner = false
                            }
                        }
                )
                .buttonStyle(.plain)
                .disabled(!controller.isReady)

                Spacer()
            }
            .padding(.bottom, 6)
            .contentShape(Rectangle())
            .allowsHitTesting(true)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.25))
                .frame(height: carouselHeight)
                .overlay(
                    Text(controller.isReady ? "Lenses / Gallery" : "Preparing camera…")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                )
        }
    }

    private func topSafeInset(in geo: GeometryProxy) -> CGFloat {
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first {
            return window.safeAreaInsets.top
        }
        if #available(iOS 15.0, *) {
            return geo.safeAreaInsets.top
        }
        return 0
    }

    private func dynamicBottomInset(in geo: GeometryProxy) -> CGFloat {
        var inset: CGFloat = 16
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first {
            inset += window.safeAreaInsets.bottom
        } else if #available(iOS 15.0, *) {
            inset += geo.safeAreaInsets.bottom
        }
        return inset
    }

    private func ensurePermissionAndStart() async {
        // Camera permission
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        var camGranted = (camStatus == .authorized)
        if camStatus == .notDetermined {
            permissionNotDetermined = true
            camGranted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .video) { ok in
                    cont.resume(returning: ok)
                }
            }
            permissionNotDetermined = false
        }
        permissionDenied = !camGranted
        guard camGranted else { return }

        // Microphone permission (for recording with audio)
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
            _ = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    cont.resume(returning: ok)
                }
            }
        }
        // Even if mic denied, we can still start the camera.
        await controller.start()
    }
}

private struct CameraKitCapturePreviewView: View {
    let image: UIImage?
    let videoURL: URL?
    let coordinate: CLLocationCoordinate2D?

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else if let url = videoURL {
                if let player {
                    VideoPlayer(player: player)
                        .onAppear {
                            player.seek(to: .zero)
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                        }
                        .padding()
                } else {
                    Color.black
                        .onAppear {
                            player = AVPlayer(url: url)
                            player?.play()
                        }
                }
            } else {
                Text("No media")
                    .foregroundColor(.white)
            }
        }
    }
}

