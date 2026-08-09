import SwiftUI
import AVFoundation
import UIKit

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
    /// The camera tab contains several full-screen pages. Only the actual live
    /// viewfinder may own capture, Vision processing, or ML speech.
    @Published private(set) var liveCameraVisible = false
    /// The real Poplur AI chat, asked for by the web hold menu's CREATE tile.
    @Published var presentsCreator = false
    @Published private(set) var recognitionManager: UserRecognitionManager?

    private var controllerStorage: CameraKitController?
    private var webReportsLiveCamera = false
    private var latestVisionBoxes: [VisionBoxDetector.Box] = []
    private var latestClassifications: [DetectedObject] = []
    private var latestARFace: (bounds: CGRect, confidence: Float, roll: CGFloat, yaw: CGFloat)?
    var isCameraTab: Bool { activeTab == "post" && liveCameraVisible }

    init() {
        // The approved Home starts on Map/Feed, not on a live lens. Close the
        // singleton announcer immediately so a late result from another camera
        // session cannot speak over this surface.
        CameraAIAnnouncer.shared.setLiveCameraActive(false)
    }

    private static let peopleClassificationTerms: Set<String> = [
        "adult", "adults", "baby", "babies", "body", "boy", "boys",
        "child", "children", "crowd", "face", "faces", "girl", "girls",
        "human", "humans", "man", "men", "people", "person", "portrait",
        "selfie", "user", "users", "woman", "women"
    ]

    /// Lazy like HomeView's LazyHomeCameraControllerHolder: no capture session
    /// exists until the camera tab is first opened.
    func resolveController() -> CameraKitController {
        if let controllerStorage { return controllerStorage }
        let controller = CameraKitController()
        controller.preparePreviewIfNeeded()
        controllerStorage = controller
        return controller
    }

    /// Point the native filter pipeline at the filter the web rail selected.
    ///
    /// The Core Image pass runs on every frame, so it is installed lazily and
    /// only while a filter is actually chosen — this app's camera is already a
    /// heat source, and paying for a full-rate filter pass to render "None"
    /// would be paying for nothing. Picking None hands the cheap hardware
    /// preview layer back.
    private func applyARFilter(id: String) {
        let controller = resolveController()
        let filter = ARFilterManager.ARFilter.allCases.first {
            $0.rawValue.caseInsensitiveCompare(id) == .orderedSame
        } ?? .none

        if filter != .none && controller.arFilterManager == nil {
            let manager = ARFilterManager()
            let layer = (controller.previewViewController as? CameraPreviewViewController)?.getARDisplayLayer()
            controller.setupARFilterSupport(filterManager: manager, displayLayer: layer)
        }
        controller.arFilterManager?.onFaceTrack = { [weak self] bounds, confidence, roll, yaw in
            guard let self else { return }
            if let bounds {
                self.latestARFace = (bounds, confidence, roll, yaw)
            } else {
                self.latestARFace = nil
            }
            self.publishCombinedDetections()
        }
        controller.arFilterManager?.activeFilter = filter
        if filter == .none {
            latestARFace = nil
            publishCombinedDetections()
        }

        // CameraPreviewViewController cross-fades between the hardware preview
        // and the filtered display layer off these two notifications; it is the
        // same pair the native selector posts, so both entry points drive the
        // preview through one path.
        NotificationCenter.default.post(
            name: Notification.Name("ARFiltersStateChanged"), object: nil,
            userInfo: ["isShown": filter != .none]
        )
        NotificationCenter.default.post(
            name: Notification.Name("ARFilterChanged"), object: nil,
            userInfo: ["filter": filter.rawValue]
        )
    }

    /// Keep the native banner/AI callbacks intact while also handing the web
    /// the real labels emitted by VNClassifyImageRequest. Classifications are
    /// whole-frame observations, so their bounds are the full frame; attaching
    /// them to an arbitrary Vision box would falsely claim object localisation.
    private func enableClassificationBridge(on controller: CameraKitController) {
        controller.enableMLDetection { [weak self] objects in
            guard let self, self.isCameraTab else { return }
            NotificationCenter.default.post(
                name: NSNotification.Name("MLObjectsDetected"),
                object: nil,
                userInfo: ["objects": objects]
            )
            self.receiveClassifications(objects)
        }
        controller.mlDetectionManager?.onFrameProcessed = { [weak self] pixelBuffer, objects in
            guard let self, self.isCameraTab else { return }
            // Settings → CAMERA → "AI voice". The announcer is the only thing
            // in the app that talks unprompted, so it needs a switch; the
            // readout and the boxes are unaffected.
            if UserDefaults.standard.object(forKey: "poplur.cameraAiVoice") as? String != "0" {
                CameraAIAnnouncer.shared.announceMLObjects(objects)
            }
            self.recognitionManager?.processDetectedObjects(objects, from: pixelBuffer)
        }
    }

    private func receiveClassifications(_ objects: [DetectedObject]) {
        latestClassifications = objects.filter { object in
            let label = object.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { return false }
            let terms = label.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
            return terms.allSatisfy { !Self.peopleClassificationTerms.contains($0) }
        }
        publishCombinedDetections()
    }

    private func receiveVisionBoxes(_ boxes: [VisionBoxDetector.Box]) {
        guard isCameraTab else { return }
        latestVisionBoxes = boxes
        publishCombinedDetections()
    }

    private func publishCombinedDetections() {
        var payload: [[String: Any]] = []
        if let face = latestARFace {
            payload.append([
                "id": "face",
                "x": Double(face.bounds.minX),
                "y": Double(1 - face.bounds.minY - face.bounds.height),
                "w": Double(face.bounds.width),
                "h": Double(face.bounds.height),
                "label": "face",
                "confidence": Double(face.confidence),
                "roll": Double(face.roll),
                "yaw": Double(face.yaw)
            ])
        }
        payload.append(contentsOf: latestVisionBoxes.map { box in
            [
                "id": box.id,
                "x": Double(box.x),
                "y": Double(box.y),
                "w": Double(box.w),
                "h": Double(box.h),
                "label": box.label,
                "confidence": Double(box.confidence)
            ]
        })
        var emittedLabels = Set(latestVisionBoxes.map { $0.label.lowercased() })

        for (index, object) in latestClassifications.enumerated() {
            let label = object.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard emittedLabels.insert(label.lowercased()).inserted else { continue }
            payload.append([
                "id": "classification-\(index)",
                // Whole-frame bounds, because a classification has NO location
                // — VNClassifyImageRequest answers "what is in this picture",
                // not "where". The `whole` flag says so explicitly, so the web
                // draws these as the READOUT and never as a box: full-frame
                // rectangles were rendering as label pills across the top,
                // which is why three answers were on screen at once.
                "x": 0.0,
                "y": 0.0,
                "w": 1.0,
                "h": 1.0,
                "whole": true,
                "label": label,
                "confidence": Double(object.confidence)
            ])
        }

        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else {
            print("[WebHomeCameraModel] failed to encode native detections")
            return
        }
        PostLoginHomeWebView.sendDetections(json)
    }

    private func clearWebDetections() {
        latestARFace = nil
        latestVisionBoxes = []
        latestClassifications = []
        PostLoginHomeWebView.sendDetections("[]")
    }

    private var phoneBootHaptics: Task<Void, Never>?

    private func runPhoneBootEffects() {
        phoneBootHaptics?.cancel()
        phoneBootHaptics = Task { @MainActor in
            let beats: [(UIImpactFeedbackGenerator.FeedbackStyle, UInt64, CGFloat)] = [
                (.heavy, 80_000_000, 1), (.heavy, 130_000_000, 1),
                (.medium, 220_000_000, 0.72), (.medium, 220_000_000, 0.72),
                (.medium, 220_000_000, 0.72), (.light, 0, 0.5)
            ]
            for (style, delay, intensity) in beats {
                guard !Task.isCancelled else { return }
                let generator = UIImpactFeedbackGenerator(style: style)
                generator.prepare()
                generator.impactOccurred(intensity: intensity)
                if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            }
        }

        guard let device = AVCaptureDevice.default(for: .video),
              device.hasTorch, device.isTorchAvailable else { return }
        Task.detached(priority: .userInitiated) {
            let pulses: [(on: UInt64, off: UInt64)] = [
                (90_000_000, 130_000_000),
                (70_000_000, 0)
            ]
            for (index, pulse) in pulses.enumerated() {
                try? device.lockForConfiguration()
                try? device.setTorchModeOn(level: 1)
                device.unlockForConfiguration()
                try? await Task.sleep(nanoseconds: pulse.on)
                try? device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
                if index < pulses.count - 1 { try? await Task.sleep(nanoseconds: pulse.off) }
            }
        }
    }

    func handleWebEvent(type: String, body: [String: Any]) {
        switch type {
        case "phoneBootEffects":
            runPhoneBootEffects()
        case "tabChanged":
            if let tab = body["tab"] as? String {
                activeTab = tab
                liveCameraVisible = tab == "post" && webReportsLiveCamera
                if !liveCameraVisible {
                    if tab != "post" { webReportsLiveCamera = false }
                    CameraAIAnnouncer.shared.setLiveCameraActive(false)
                }
            }
        case "cameraLiveVisibilityChanged":
            webReportsLiveCamera = (body["visible"] as? Bool) == true
            liveCameraVisible = webReportsLiveCamera && activeTab == "post"
            if !liveCameraVisible {
                // Do not wait for SwiftUI's removal transaction before stopping
                // speech; Camera Roll/composer must be silent immediately.
                CameraAIAnnouncer.shared.setLiveCameraActive(false)
            }
        case "requestCameraPermission":
            // The web alert was answered Allow — now the OS may ask.
            guard isCameraTab else { return }
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
                    latestClassifications = []
                    enableClassificationBridge(on: controller)
                } else {
                    controller.disableMLDetection()
                    latestClassifications = []
                    publishCombinedDetections()
                }
                UserDefaults.standard.set(wantsOn, forKey: "CameraObjectDetectionEnabled")
            case "filter":
                // AR filters were the SAME bug as ML detection, one layer along:
                // a capability wired only on the old native path and missed when
                // Home became a WebView.
                //
                // The web rail sets a CSS `filter` on its <video>. On iOS that
                // element is never rendered at all — the preview is native behind
                // a transparent WebView — so the rail was styling nothing. And
                // even with a message to carry the choice there was no pipeline
                // to receive it: the Core Image pass and the display layer are
                // installed by setupARFilterSupport(), which only HomeView ever
                // called. Selecting a filter changed a label and nothing else.
                applyARFilter(id: (body["id"] as? String) ?? "none")
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
        guard isCameraTab else { return }
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
        // Permission may have put up an OS sheet while the user/page moved on.
        guard isCameraTab else { return }
        await controller.resumePreviewAfterInterruption()
        guard isCameraTab else {
            controller.suspendCapture()
            return
        }
        // Pairs with the suspendCapture() in deactivateCamera(). Without this the
        // camera would come back dead after the first time you leave the tab.
        controller.resumeCapture()

        let recognition = recognitionManager ?? UserRecognitionManager()
        recognitionManager = recognition
        controller.userRecognitionManager = recognition
        CameraAIAnnouncer.shared.setLiveCameraActive(true)

        // Camera always opens with detection enabled. DETECT OFF remains a
        // session control, but an old persisted off value must not survive an
        // update/reinstall and silently disable the default on the next visit.
        enableClassificationBridge(on: controller)
        // enableMLDetection() only says detection is WANTED. Frames are what make
        // it happen, and on this path nothing was attaching a video data output —
        // that lived solely inside setupARFilterSupport(), which only HomeView
        // called. So the classifier and face detector sat armed and idle: no
        // green boxes, no announcements, and no error to say why.
        controller.startVideoFrameDelivery()

        // Real boxes for the web overlay. The web's own detector
        // (poplur-clay-map/src/mlDetect.ts) is explicitly a SIMULATION — it
        // clusters a frame-difference map and labels the blobs from a plausible
        // list — and it cannot run here anyway, because on iOS the camera is
        // native behind a transparent WebView so the page's <video> is empty.
        // Vision's built-in detectors genuinely locate what they name, so the
        // boxes on screen mean something.
        let boxes = controller.visionBoxDetector ?? VisionBoxDetector()
        controller.visionBoxDetector = boxes
        boxes.onBoxes = { [weak self] found in self?.receiveVisionBoxes(found) }
        UserDefaults.standard.set(true, forKey: "CameraObjectDetectionEnabled")
        await recognition.startRecognitionSession()
    }

    /// Mirrors HomeView.recordTabContent.onDisappear.
    func deactivateCamera() {
        CameraAIAnnouncer.shared.setLiveCameraActive(false)
        controllerStorage?.disableMLDetection()
        controllerStorage?.userRecognitionManager = nil
        recognitionManager?.clearRecognition()

        // ACTUALLY STOP THE CAMERA.
        //
        // This used to only switch ML off, so the AVCaptureSession — sensor, ISP,
        // `.high` preset, back dual-wide — kept running from the first time the
        // camera tab was opened until the app was backgrounded or killed. Leaving
        // the camera tab did nothing: the sensor stayed hot on Feed, Map and
        // Profile. That is on the order of 400-900 mW sustained, and it is the
        // largest remaining native contributor to the phone heating up.
        //
        // It survived because the controller lives in
        // `WebHomeCameraModel.controllerStorage`, held by a @StateObject on
        // PostLoginHomeSurface, so unmounting the camera layer never released it.
        // `suspendCapture()`/`resumeCapture()` already existed and were already
        // paired — only HomeView called them, and HomeView is not mounted when
        // PoplurWebHome.isEnabled.
        controllerStorage?.visionBoxDetector?.onBoxes = nil
        controllerStorage?.visionBoxDetector = nil
        // Clear any boxes left painted over a camera that is no longer running.
        clearWebDetections()
        controllerStorage?.suspendCapture()

        // And kill the torch. Nothing else clears it: flipCamera() only clears it
        // when switching TO the front camera, and the implicit clear from stopping
        // the session never happened because the session was never stopped. A
        // forgotten LED is 1-3 W heating the camera bump directly, for as long as
        // the app is open.
        controllerStorage?.toggleTorchOff()
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

                // NO LiveMLDetectionOverlay here. It rendered a SECOND readout of
                // the same detections — a primary card plus an "Also seeing"
                // chip row — on top of MLCameraShaderOverlay's shader banner
                // below, so every scan showed twice. The shader banner is the
                // approved one; this one is the duplicate.

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
    let initialTab: AppTab
    let onReady: () -> Void
    @StateObject private var camera = WebHomeCameraModel()
    @StateObject private var poplurAI = PoplurAIAssistantController()
    @Environment(\.scenePhase) private var scenePhase

    init(initialTab: AppTab = .feed, onReady: @escaping () -> Void = {}) {
        self.initialTab = initialTab
        self.onReady = onReady
    }

    private var initialWebView: String {
        switch initialTab {
        case .map: return "map"
        case .record: return "camera"
        case .profile: return "profile"
        case .feed, .settings: return "home"
        }
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
                initialView: initialWebView,
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
        // NOT started on appear any more. Arming the recognizer just because Home
        // mounted is what made "Hey Poplur" always-on, and always-on cost a live
        // AVAudioEngine + a continuous mic tap + a speech recognizer for the
        // entire session. Measured on device: turning it off took the feed video
        // from 0.52x real time / ~13fps to 1.0x / 28-38fps and stopped the phone
        // overheating. It had also parked the audio session in `.measurement`,
        // silencing all playback.
        //
        // The way in is now the PROFILE hold menu's HEY POPLUR tile, which the web
        // already bridges as `requestVoiceAssistant` -> requestPermissionAndStartCommand()
        // (see onWebEvent above). Stopping is still unconditional: backgrounding or
        // leaving Home must never leave the microphone open.
        .onDisappear { poplurAI.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { poplurAI.stop() }
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
