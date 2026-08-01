import SwiftUI
import AVFoundation

// MARK: - Web-home native camera (Phase 3.5 — first real tab bridge)
//
// The web home's camera (post) tab used to show the twin's SPOOFED viewfinder.
// This reinstates the REAL camera from the previous native versions — the same
// CameraKitController + ML pipeline HomeView's record tab used (AVCapture
// preview, MLObjectDetectionManager detection, user recognition, AI announcer)
// — rendered BEHIND the transparent WebView while the approved web chrome/icons
// stay on top and drive it over the bridge:
//
//   web → native:  { type: "tabChanged", tab }        mount/unmount this layer
//                  { type: "cameraShutter" }          cube tap = capture (as before)
//                  { type: "cameraControl", control } "flash" | "flip" | "record"
//
// The web side punches the hole via html.camera-live (see poplur-clay-map
// Camera.tsx / index.css); browser + Android keep the spoofed feed.

@MainActor
final class WebHomeCameraModel: ObservableObject {
    /// Front-most web tab (map | feed | post | profile | holdmenu).
    @Published var activeTab: String = "map"
    /// The real Poplur AI chat, asked for by the web hold menu's CREATE tile.
    @Published var presentsCreator = false
    @Published private(set) var recognitionManager: UserRecognitionManager?

    private var controllerStorage: CameraKitController?
    var isCameraTab: Bool { activeTab == "post" }

    /// Lazy like HomeView's LazyHomeCameraControllerHolder: no capture session
    /// exists until the camera tab is first opened.
    func resolveController() -> CameraKitController {
        if let controllerStorage { return controllerStorage }
        let controller = CameraKitController()
        controller.preparePreviewIfNeeded()
        controllerStorage = controller
        return controller
    }

    func handleWebEvent(type: String, body: [String: Any]) {
        switch type {
        case "tabChanged":
            if let tab = body["tab"] as? String { activeTab = tab }
        case "requestCameraPermission":
            // The web alert was answered Allow — now the OS may ask.
            Task { await activateCamera(askIfUndecided: true) }
        case "cameraShutter":
            guard isCameraTab else { return }
            controllerStorage?.triggerShutter()
        case "cameraControl":
            guard isCameraTab, let control = body["control"] as? String else { return }
            switch control {
            case "flash":
                let controller = resolveController()
                if let enabled = body["on"] as? Bool {
                    enabled ? controller.toggleTorchOn() : controller.toggleTorchOff()
                } else {
                    controller.toggleFlash()
                }
            case "flip":  controllerStorage?.flipCamera()
            case "zoom":
                let value = (body["value"] as? NSNumber)?.doubleValue ?? 1
                resolveController().setZoomFactor(CGFloat(value))
            case "record":
                let controller = resolveController()
                if controller.isRecording {
                    controller.endRecording()
                } else {
                    controller.beginRecording()
                }
            case "detect":
                // ML detection ships on — activateCamera turns it on every time
                // the camera tab opens — but the DETECT toggle lives in the web
                // hold menu and had no way to reach the native detector, so
                // turning it off did nothing on a device. `on` is optional so a
                // plain toggle still works.
                let controller = resolveController()
                let wantsOn = (body["on"] as? Bool) ?? (controller.mlDetectionManager == nil)
                if wantsOn {
                    controller.enableMLDetection()
                    controller.mlDetectionManager?.onFrameProcessed = { [weak self] pixelBuffer, objects in
                        CameraAIAnnouncer.shared.announceMLObjects(objects)
                        self?.recognitionManager?.processDetectedObjects(objects, from: pixelBuffer)
                    }
                } else {
                    controller.disableMLDetection()
                }
                UserDefaults.standard.set(wantsOn, forKey: "CameraObjectDetectionEnabled")
            default: break
            }
        case "holdMenuNavigate":
            // The web hold menu asks for a native destination. HomeView's
            // router (handleHoldMenuNavigate) is NOT available here: with the
            // web home enabled, HomeView is never mounted, so posting
            // .HoldMenuNavigate would reach nobody. The surface presents the
            // real screen itself.
            guard let action = body["action"] as? String else { return }
            if action == "create" { presentsCreator = true }
        default:
            break
        }
    }

    /// Mirrors HomeView.recordTabContent.onAppear: resume the preview and wire
    /// ML detection + user recognition (the previous versions' behavior).
    /// `askIfUndecided` is false for the automatic activation that happens when
    /// the camera tab mounts, and true only when the web's own permission alert
    /// has been answered with Allow. The OS prompt is one-shot per install, so
    /// it must not be spent on someone who has not been told what it is for —
    /// a reflexive Don't Allow against a bare system alert costs the camera
    /// permanently. Poplur asks first; this fires only after a yes.
    func activateCamera(askIfUndecided: Bool = false) async {
        let controller = resolveController()
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            break
        case .notDetermined:
            guard askIfUndecided else { return }
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { return }
        default:
            return
        }
        await controller.resumePreviewAfterInterruption()

        let recognition = recognitionManager ?? UserRecognitionManager()
        recognitionManager = recognition
        controller.userRecognitionManager = recognition

        // Camera always opens with detection enabled. DETECT OFF remains a
        // session control, but an old persisted off value must not survive an
        // update/reinstall and silently disable the default on the next visit.
        controller.enableMLDetection()
        controller.mlDetectionManager?.onFrameProcessed = { [weak recognition] pixelBuffer, objects in
            CameraAIAnnouncer.shared.announceMLObjects(objects)
            recognition?.processDetectedObjects(objects, from: pixelBuffer)
        }
        UserDefaults.standard.set(true, forKey: "CameraObjectDetectionEnabled")
        await recognition.startRecognitionSession()
    }

    /// Mirrors HomeView.recordTabContent.onDisappear.
    func deactivateCamera() {
        controllerStorage?.disableMLDetection()
        controllerStorage?.userRecognitionManager = nil
        recognitionManager?.clearRecognition()
        CameraAIAnnouncer.shared.resetSession()
    }
}

/// The real viewfinder + ML overlays, shown behind the transparent web chrome.
struct WebHomeCameraLayer: View {
    @ObservedObject var model: WebHomeCameraModel

    var body: some View {
        ZStack {
            HomeCameraPreviewHost(controller: model.resolveController())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            if let recognitionManager = model.recognitionManager {
                RecognizedFaceBoxOverlay(recognitionManager: recognitionManager)
                    .allowsHitTesting(false)

                if let user = recognitionManager.recognizedUser, user.isRecent {
                    Text("@\(user.profile.username)")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .cyan, .white],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .poplurTextShader(intensity: 1.0)
                        .shadow(color: .cyan.opacity(0.75), radius: 9)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 80)
                        .allowsHitTesting(false)
                }
            }
            MLCameraShaderOverlay(isEnabled: true)
                .allowsHitTesting(false)
        }
        .task { await model.activateCamera() }
        .onDisappear { model.deactivateCamera() }
    }
}

/// The authenticated surface: dark backdrop → native camera (camera tab only)
/// → the transparent web home on top. Drop-in replacement for a bare
/// PostLoginHomeWebView.
struct PostLoginHomeSurface: View {
    let onReady: () -> Void
    @StateObject private var camera = WebHomeCameraModel()
    @StateObject private var poplurAI = PoplurAIAssistantController()
    @Environment(\.scenePhase) private var scenePhase

    init(onReady: @escaping () -> Void = {}) {
        self.onReady = onReady
    }

    var body: some View {
        ZStack {
            // The web home's own dark backdrop, now painted natively so the
            // WebView itself can stay transparent for the camera punch-through.
            Color(red: 5/255, green: 4/255, blue: 7/255).ignoresSafeArea()

            if camera.isCameraTab {
                WebHomeCameraLayer(model: camera)
            }

            PostLoginHomeWebView(
                onReady: onReady,
                onWebEvent: { [weak camera, weak poplurAI] type, body in
                    camera?.handleWebEvent(type: type, body: body)
                    if type == "requestVoiceAssistant" {
                        // This message can only come from the explicit HEY
                        // POPLUR tile. It is therefore the native permission
                        // ask point; mounting Home itself never opens a sheet.
                        poplurAI?.requestPermissionAndStartCommand()
                    }
                },
                nativeVoiceCommandToken: poplurAI.voiceFeedbackToken,
                nativeVoiceCommandJSON: Self.voiceCommandJSON(
                    poplurAI.lastCommand,
                    feedback: poplurAI.voiceFeedback
                )
            )
            .ignoresSafeArea()

            PoplurAIAssistantOverlay(
                controller: poplurAI,
                accent: Color(red: 1.0, green: 0.31, blue: 0.64)
            )
            .allowsHitTesting(false)
        }
        .onAppear { poplurAI.start() }
        .onDisappear { poplurAI.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                poplurAI.start()
            } else {
                // "Always" means while the approved Home is foregrounded.
                // Do not hold the microphone when Poplur is not on screen.
                poplurAI.stop()
            }
        }
        // CREATE in the web hold menu opens the REAL chat — PoplurAIChatView,
        // the one backed by Google AI Studio through poplurAiApi — instead of
        // the Rough Copy capture the browser falls back to.
        .fullScreenCover(isPresented: $camera.presentsCreator) {
            PoplurAIChatView(
                initialImage: nil,
                initialVideoURL: nil,
                onDismiss: { camera.presentsCreator = false }
            )
        }
    }

    private static func voiceCommandJSON(_ command: PoplurAICommand?, feedback: String) -> String? {
        var detail: [String: String] = ["feedback": feedback]
        switch command {
        case .openTab(let tab):
            switch tab {
            case .map: detail["tab"] = "map"
            case .record: detail["tab"] = "post"
            case .feed: detail["tab"] = "feed"
            case .profile: detail["tab"] = "profile"
            case .settings: break
            }
        case .camera:
            detail["tab"] = "post"
        case .goToChannel(let channel):
            detail["tab"] = "feed"
            detail["channel"] = channel
        case .postToLocation:
            detail["tab"] = "post"
        case .sortPosts, .showAnalytics:
            detail["tab"] = "profile"
        case .openPage, .setTourActive, .logout, .unknown:
            break
        case nil:
            break
        }
        guard !feedback.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: detail),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return json
    }
}
