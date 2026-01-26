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

    @State private var isLongPressingRecord = false
    @State private var didStopViaTapDuringLongPress = false
    
    // Removed keepAudioSessionActiveForPreview per instructions

    @State private var wantsPreviewAfterStop = false

    @State private var lastStopTime: Date? = nil
    private let restartCooldown: TimeInterval = 0.35

    private let carouselHeight: CGFloat = 110
    private let captureButtonSize: CGFloat = 84
    private let rightRailSpacing: CGFloat = 14

    init(controller: CameraKitController? = nil, coordinate: CLLocationCoordinate2D?) {
        self.injectedController = controller
        self.coordinate = coordinate
    }

    var body: some View {
        ZStack {
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

                    // Removed full-screen tap diagnostic overlay & dot rendering

                    if !controller.isReady {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Starting camera…")
                                    .foregroundColor(.white.opacity(0.95))
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                Text("CameraKit configured: \(controller.cameraKitConfigured ? "YES" : "NO")")
                                    .foregroundColor(.white.opacity(0.8))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
                        .padding(.top, 24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .zIndex(50)
                        .allowsHitTesting(false)
                    }

                    bottomStack
                        .padding(.bottom, dynamicBottomInset(in: geo) + 60)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .contentShape(Rectangle())
                        .allowsHitTesting(true)
                        .zIndex(100)

                    // Removed InlineCapturePreview from here, moved to overlay as per instructions
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
                    print("[CameraKitView] onChange lastPhoto: \(String(describing: img))")
                    capturedVideoURL = nil
                    capturedImage = img
                    if img != nil {
                        tapToastMessage = "Saved"
                        withAnimation(.easeInOut(duration: 0.15)) { showTapToast = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.15)) { showTapToast = false }
                        }
                        NotificationCenter.default.post(name: Notification.Name("FeedRefreshRequested"), object: nil)
                        print("[CameraKitView] Will show preview for image (onChange)")
                        withAnimation(.easeInOut(duration: 0.2)) { showPreview = true }
                    }
                }
                // Removed duplicate .onReceive(controller.$lastPhoto) as per instructions

                .onChange(of: controller.lastVideoURL) { url in
                    print("[CameraKitView] onChange lastVideoURL: \(String(describing: url))")
                    capturedImage = nil
                    capturedVideoURL = url
                    if url != nil {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        tapToastMessage = "Saved"
                        withAnimation(.easeInOut(duration: 0.15)) { showTapToast = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.15)) { showTapToast = false }
                        }
                        print("[CameraKitView] Will show preview for videoURL (onChange): \(String(describing: capturedVideoURL))")
                        withAnimation(.easeInOut(duration: 0.2)) { showPreview = true }
                    }
                }
                // Removed duplicate .onReceive(controller.$lastVideoURL) as per instructions

                .onChange(of: controller.isRecording) { rec in
                    print("[CameraKitView] isRecording changed -> \(rec)")
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showRecordingBanner = rec
                    }
                }
                .onDisappear {
                    print("[CameraKitView] Record tab did disappear; keeping AVAudioSession active to avoid churn")
                    NotificationCenter.default.post(name: Notification.Name("RecordTabDidDisappear"), object: nil)
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InlinePreviewDismissRequested"))) { _ in
                    if showPreview {
                        print("[CameraKitView] Received InlinePreviewDismissRequested — hiding preview")
                        withAnimation(.easeInOut(duration: 0.2)) { showPreview = false }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("InlinePreviewUseRequested"))) { _ in
                    if showPreview {
                        print("[CameraKitView] Received InlinePreviewUseRequested — hiding preview")
                        withAnimation(.easeInOut(duration: 0.2)) { showPreview = false }
                    }
                }
                .onChange(of: showPreview) { val in
                    print("[CameraKitView] showPreview changed -> \(val)")
                }
                // Removed InlineCapturePreview here to avoid duplicates
            }
            .ignoresSafeArea()

            // Top-most preview layer
            Group {
                if showPreview {
                    InlineCapturePreview(image: capturedImage, videoURL: capturedVideoURL)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .ignoresSafeArea()
                        .allowsHitTesting(true)
                        .zIndex(1_000_000)
                        .onAppear { print("[CameraKitView] InlineCapturePreview (root overlay) appeared. image? \(capturedImage != nil) video? \(capturedVideoURL != nil)") }
                }
            }
            .zIndex(1_000_000)

            // Temporary debug banner to confirm layering
            Group {
                if showPreview {
                    Text("DEBUG: showPreview == true")
                        .font(.system(size: 12, weight: .bold))
                        .padding(8)
                        .background(Color.red, in: Capsule())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 12)
                }
            }
            .zIndex(1_000_001)
            .allowsHitTesting(false)
        }
    }

    private func canRecordNow() -> Bool {
        // Allow recording attempts regardless of controller readiness; block only when preview is showing
        return !showPreview
    }
    
    private func passedCooldown() -> Bool {
        guard let t = lastStopTime else { return true }
        return Date().timeIntervalSince(t) >= restartCooldown
    }

    private func micAuthorized() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
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

    // Insert new helper functions below

    private func requestStartRecording(reason: String) {
        guard !controller.isRecording else {
            print("[Record] Ignored start — already recording (\(reason))")
            return
        }
        Task { @MainActor in
            await actuallyStartRecording(reason: reason)
        }
    }

    @MainActor
    private func actuallyStartRecording(reason: String) async {
        print("[Record] Start recording (\(reason))")
        withAnimation(.easeInOut(duration: 0.2)) { showRecordingBanner = true }
        controller.mode = .video
        controller.startRecording()
    }

    private func requestStopRecording(reason: String) {
        guard controller.isRecording else {
            print("[Record] Ignored stop — not recording (\(reason))")
            return
        }
        print("[Record] Stop recording (\(reason))")
        lastStopTime = Date()
        withAnimation(.easeInOut(duration: 0.2)) { showRecordingBanner = false }
        Task { @MainActor in controller.stopRecording() }
    }

    private var cameraPreviewWithGestures: some View {
        ZStack {
            if let session = controller.cameraKitSession {
                // TEMP: stripped gestures/rail for tap isolation
                PreviewView(cameraKit: session)
                    .contentShape(Rectangle())
                    .onAppear {
                        print("[CameraKitView] PreviewView attached with cameraKit session")
                        Task { await maybeStartIfAuthorizedAndNotReady() }
                    }
            } else {
                // Fallback disabled to avoid competing capture pipelines; wait for CameraKit session
                Color.black
                    .onAppear {
                        print("[CameraKitView] CameraKit session is nil; suppressing AVFoundation fallback preview to avoid conflicts")
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
                if !(controller.isReady && controller.isTorchAvailable) {
                    print("[UI] Torch tapped while unavailable. isReady=\(controller.isReady) torchAvail=\(controller.isTorchAvailable)")
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
            .disabled(!(controller.isReady && controller.isTorchAvailable))

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

                // Updated gesture logic: replaced simultaneousGesture with highPriorityGesture + gesture
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
                .allowsHitTesting(true)
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .onChanged { _ in
                            print("[UI] LongPress changed. isReady: \(controller.isReady), isRecording: \(controller.isRecording), isLongPressingRecord: \(isLongPressingRecord)")
                            controller.mode = .video
                            if !isLongPressingRecord { isLongPressingRecord = true }
                            guard !didStopViaTapDuringLongPress else { return }
                            requestStartRecording(reason: "longPress")
                        }
                        .onEnded { _ in
                            print("[UI] LongPress ended. isReady: \(controller.isReady), isRecording: \(controller.isRecording)")
                            let wasRecording = controller.isRecording
                            isLongPressingRecord = false
                            didStopViaTapDuringLongPress = false
                            if !canRecordNow() {
                                print("[CameraKitView] LongPress end proceeding even though session may not be ready/running")
                            }
                            if controller.mode == .video, wasRecording {
                                requestStopRecording(reason: "longPress end")
                                wantsPreviewAfterStop = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                    // If controller has already published, capturedVideoURL may be set by onReceive.
                                    let url = capturedVideoURL ?? controller.lastVideoURL
                                    if url != nil {
                                        print("[CameraKitView] Auto-showing preview after long-press stop")
                                        withAnimation(.easeInOut(duration: 0.2)) { showPreview = true }
                                        wantsPreviewAfterStop = false
                                    }
                                }
                                // Removed the second async-after 1.0s warning block per instructions
                            }
                        }
                )
                .gesture(
                    TapGesture()
                        .onEnded {
                            print("[UI] Capture tap. isReady: \(controller.isReady), isRecording: \(controller.isRecording), isLongPressingRecord: \(isLongPressingRecord)")
                            print("[UI] captureSessionRunning: \(controller.captureSessionRunning)")
                            if !canRecordNow() {
                                print("[CameraKitView] TapGesture proceeding even though session may not be ready/running")
                            }
                            // If a long press is active, only allow tap to stop
                            if isLongPressingRecord {
                                if controller.mode == .video && controller.isRecording {
                                    print("[CameraKitView] Tap during long-press: stopping recording")
                                    didStopViaTapDuringLongPress = true
                                    isLongPressingRecord = false
                                    requestStopRecording(reason: "tap during longPress")
                                }
                                return
                            }
                            if controller.mode == .video {
                                print("[CameraKitView] TapGesture in video mode: toggling recording")
                                if controller.isRecording {
                                    requestStopRecording(reason: "tap")
                                    wantsPreviewAfterStop = true // added per instructions
                                } else {
                                    requestStartRecording(reason: "tap")
                                }
                                return
                            }
                            // Photo mode tap
                            print("[CameraKitView] TapGesture: taking photo")
                            showPhotoFlash = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { showPhotoFlash = false }
                            Task { @MainActor in controller.takePhoto() }
                        }
                )
                .buttonStyle(.plain)
                .disabled(false)

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

private struct InlineCapturePreview: View {
    let image: UIImage?
    let videoURL: URL?

    @State private var player: AVPlayer?
    @State private var stabilizedURL: URL?
    @State private var autoDismissWorkItem: DispatchWorkItem?
    @State private var userInteracted: Bool = false
    @State private var appearedAt: Date = .distantPast

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.95)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    let since = Date().timeIntervalSince(appearedAt)
                    if since < 0.25 {
                        print("[InlinePreview] Ignoring tap dismiss during grace (\(since)s)")
                        return
                    }
                    userInteracted = true
                    autoDismissWorkItem?.cancel()
                    NotificationCenter.default.post(name: Notification.Name("InlinePreviewDismissRequested"), object: nil)
                }
                .onAppear { print("[InlinePreview] appeared. image? \(image != nil), video? \(videoURL != nil)") }
                .onAppear {
                    appearedAt = Date()
                    let work = DispatchWorkItem {
                        if !userInteracted {
                            print("[InlinePreview] Auto-dismissing after timeout")
                            NotificationCenter.default.post(name: Notification.Name("InlinePreviewDismissRequested"), object: nil)
                        }
                    }
                    autoDismissWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
                }
                .onDisappear {
                    autoDismissWorkItem?.cancel()
                }

            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else if let url = stabilizedURL ?? videoURL {
                if let player {
                    VideoPlayer(player: player)
                        .onAppear {
                            print("[InlinePreview] Using existing player for URL: \(url)")
                            player.seek(to: .zero)
                            print("[InlinePreview] Player will play")
                            player.play()
                        }
                        .onDisappear {
                            player.pause()
                            player.replaceCurrentItem(with: nil)
                            self.player = nil
                        }
                        .padding()
                } else {
                    Color.clear
                        .onAppear {
                            if self.stabilizedURL == nil { self.stabilizedURL = url }
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 50_000_000)
                                if let finalURL = self.stabilizedURL {
                                    let path = finalURL.path
                                    let exists = FileManager.default.fileExists(atPath: path)
                                    let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue ?? 0
                                    print("[InlinePreview] File exists? \(exists) size=\(size) at path: \(path)")
                                    guard exists && size > 0 else {
                                        print("[InlinePreview] Cannot initialize player: file missing or zero size at \(path)")
                                        return
                                    }
                                    print("[InlinePreview] Initializing player with URL: \(finalURL)")
                                    let p = AVPlayer(url: finalURL)
                                    self.player = p
                                    print("[InlinePreview] Player created, will seek and play")
                                    await p.seek(to: .zero)
                                    p.play()
                                } else {
                                    print("[InlinePreview] Missing URL; cannot init player")
                                }
                            }
                        }
                }
            } else {
                Text("No media")
                    .foregroundColor(.white)
            }

            VStack {
                Spacer()
                HStack(spacing: 16) {
                    Button {
                        let since = Date().timeIntervalSince(appearedAt)
                        if since < 0.25 {
                            print("[InlinePreview] Ignoring Retake tap during grace (\(since)s)")
                            return
                        }
                        userInteracted = true
                        autoDismissWorkItem?.cancel()
                        NotificationCenter.default.post(name: Notification.Name("InlinePreviewDismissRequested"), object: nil)
                    } label: {
                        Text("Retake")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.45), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        let since = Date().timeIntervalSince(appearedAt)
                        if since < 0.25 {
                            print("[InlinePreview] Ignoring Use tap during grace (\(since)s)")
                            return
                        }
                        userInteracted = true
                        autoDismissWorkItem?.cancel()
                        NotificationCenter.default.post(name: Notification.Name("InlinePreviewUseRequested"), object: nil)
                    } label: {
                        Text("Use")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 72)
            }

            VStack {
                Spacer()
                Text("Tap anywhere to close")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.35), in: Capsule())
                    .padding(.bottom, 24)
            }

            // Dismiss button
            VStack {
                HStack {
                    Button {
                        let since = Date().timeIntervalSince(appearedAt)
                        if since < 0.25 {
                            print("[InlinePreview] Ignoring close tap during grace (\(since)s)")
                            return
                        }
                        // Use Notification to ask parent to hide preview
                        NotificationCenter.default.post(name: Notification.Name("InlinePreviewDismissRequested"), object: nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .padding([.top, .leading], 16)
                    Spacer()
                }
                Spacer()
            }
        }
    }
}

private struct CameraKitCapturePreviewView: View {
    let image: UIImage?
    let videoURL: URL?
    let coordinate: CLLocationCoordinate2D?

    @State private var player: AVPlayer?
    @State private var localURL: URL?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else if let url = localURL ?? videoURL {
                if let player {
                    VideoPlayer(player: player)
                        .onAppear {
                            print("[Preview] onAppear with existing player for URL: \(url)")
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
                            // Stabilize local copy of URL for the life of the sheet
                            if self.localURL == nil { self.localURL = url }
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 50_000_000)
                                if let finalURL = self.localURL {
                                    print("[Preview] Initializing AVPlayer with URL: \(finalURL)")
                                    self.player = AVPlayer(url: finalURL)
                                    await self.player?.seek(to: .zero)
                                    self.player?.play()
                                } else {
                                    print("[Preview] Missing URL; cannot initialize player")
                                }
                            }
                        }
                }
            } else {
                Text("No media")
                    .foregroundColor(.white)
            }
        }
    }
}

