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
                    .zIndex(100)
                } else {
                    cameraPreviewWithGestures
                        .zIndex(0)
                }

                debugOverlay
                    .padding(.leading, 8)
                    .padding(.top, 8 + topSafeInset(in: geo))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .zIndex(30)

                rightActionRail
                    .padding(.trailing, 12)
                    .padding(.top, 28 + topSafeInset(in: geo))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .zIndex(20)

                bottomStack
                    .padding(.bottom, dynamicBottomInset(in: geo) + 60)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .zIndex(20)
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
                Task { await maybeStartIfAuthorizedAndNotReady() }
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
                if img != nil { showPreview = true }
            }
            .onChange(of: controller.lastVideoURL) { url in
                capturedImage = nil
                capturedVideoURL = url
                if url != nil { showPreview = true }
            }
            .sheet(isPresented: $showPreview) {
                CameraKitCapturePreviewView(
                    image: capturedImage,
                    videoURL: capturedVideoURL,
                    coordinate: coordinate
                )
            }
        }
        .ignoresSafeArea()
    }

    private func maybeStartIfAuthorizedAndNotReady() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .authorized, !controller.isReady {
            await controller.start()
        }
    }

    private var cameraPreviewWithGestures: some View {
        ZStack {
            if let session = controller.cameraKitSession {
                PreviewView(cameraKit: session)
                    .onAppear {
                        currentZoom = 1.0
                        Task { await maybeStartIfAuthorizedAndNotReady() }
                    }
            } else {
                Color.black
                    .onAppear {
                        Task { await maybeStartIfAuthorizedAndNotReady() }
                    }
            }

            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        TapGesture()
                            .onEnded { _ in
                                let point = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                                focusPoint = point
                                showFocusReticle = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                                    showFocusReticle = false
                                }
                                if let pv = controller.previewHostView {
                                    controller.focus(at: point, in: pv)
                                }
                            }
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                let newZoom = baseZoomAtGestureStart * scale
                                currentZoom = max(controller.minZoomFactor, min(newZoom, controller.maxZoomFactor))
                                controller.setZoom(factor: currentZoom)
                            }
                            .onEnded { _ in
                                baseZoomAtGestureStart = currentZoom
                            }
                    )
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

    private var debugOverlay: some View {
        let auth = AVCaptureDevice.authorizationStatus(for: .video)
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        let authText: String
        switch auth {
        case .authorized: authText = "authorized"
        case .notDetermined: authText = "notDetermined"
        case .denied: authText = "denied"
        case .restricted: authText = "restricted"
        @unknown default: authText = "unknown"
        }
        let micText: String
        switch mic {
        case .authorized: micText = "authorized"
        case .notDetermined: micText = "notDetermined"
        case .denied: micText = "denied"
        case .restricted: micText = "restricted"
        @unknown default: micText = "unknown"
        }

        return HStack(spacing: 8) {
            Circle()
                .fill(controller.isReady ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text("Cam: \(authText) | Mic: \(micText) | Ready: \(controller.isReady ? "yes" : "no") | Session: \(controller.captureSessionRunning ? "running" : "stopped")")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.95))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.45), in: Capsule())
        }
        .allowsHitTesting(false)
    }

    private var rightActionRail: some View {
        VStack(spacing: rightRailSpacing) {
            Button {
                controller.switchCamera()
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
                controller.setTorch(on: !controller.flashOn)
            } label: {
                Circle()
                    .fill(Color.black.opacity(controller.isReady ? 0.45 : 0.25))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: controller.flashOn ? "bolt.fill" : "bolt.slash.fill")
                            .foregroundColor(.white.opacity(controller.isReady ? 1.0 : 0.5))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!controller.isReady)

            Button {
                print("[CK][UI] More tapped")
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
        }
    }

    private var bottomStack: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()

                Button {
                    switch controller.mode {
                    case .video:
                        if controller.isRecording {
                            controller.stopRecording()
                        } else {
                            controller.startRecording()
                        }
                    case .photo:
                        controller.takePhoto()
                    }
                } label: {
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
                }
                .buttonStyle(.plain)
                .disabled(!controller.isReady)

                Spacer()
            }
            .padding(.bottom, 6)

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
