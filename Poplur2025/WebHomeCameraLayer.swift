import SwiftUI
import FirebaseAuth
import FirebaseFunctions
import CoreImage
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
//                  { type: "cameraControl", control } "flash" | "flip" |
//                                                    "recordStart" | "recordStop"
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
    /// Invalidates an activation that is suspended in an async permission,
    /// capture-configuration, or recognition preload when Camera leaves the
    /// foreground. A stale task may finish, but it can never reclaim capture.
    private var cameraActivationGeneration: UInt64 = 0
    private var webReportsLiveCamera = false
    private var webWantsDetection = false
    private var latestVisionBoxes: [VisionBoxDetector.Box] = []
    private var latestClassifications: [DetectedObject] = []
    private var latestCloudClassifications: [DetectedObject] = []
    private var latestARFace: (bounds: CGRect, confidence: Float, roll: CGFloat, yaw: CGFloat)?
    private var cloudScanRequested = false
    private var cloudScanInFlight = false
    private var recognitionObserver: NSObjectProtocol?
    var isCameraTab: Bool { activeTab == "post" && liveCameraVisible }

    init() {
        // The approved Home starts on Map/Feed, not on a live lens. Close the
        // singleton announcer immediately so a late result from another camera
        // session cannot speak over this surface.
        CameraAIAnnouncer.shared.setLiveCameraActive(false)
        recognitionObserver = NotificationCenter.default.addObserver(
            forName: .UserRecognizedInCamera,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.publishCombinedDetections() }
        }
    }

    deinit {
        phoneBootHaptics?.cancel()
        phoneBootPlayer?.stop()
        if let recognitionObserver {
            NotificationCenter.default.removeObserver(recognitionObserver)
        }
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
        controller.onColdBudgetStateChange = { [weak self] update in
            PostLoginHomeWebView.sendCameraBudgetState(update)
            if update.state == .running, self?.isCameraTab == true {
                CameraAIAnnouncer.shared.setLiveCameraActive(true)
            } else {
                // A face request that was already inside Vision may complete
                // after capture parks. Keep that result silent and clear any
                // recognition it managed to publish before its completion edge.
                CameraAIAnnouncer.shared.setLiveCameraActive(false)
                if update.state == .parked {
                    self?.recognitionManager?.clearRecognition()
                }
            }
        }
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
        controller.arFilterManager?.onFaceTrack = { [weak self, weak controller] bounds, confidence, roll, yaw in
            guard let self, controller?.acceptsAnalysisResults == true else { return }
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
        controller.enableMLDetection { [weak self, weak controller] objects in
            guard let self,
                  self.isCameraTab,
                  controller?.acceptsAnalysisResults == true else { return }
            NotificationCenter.default.post(
                name: NSNotification.Name("MLObjectsDetected"),
                object: nil,
                userInfo: ["objects": objects]
            )
            self.receiveClassifications(objects)
        }
        controller.mlDetectionManager?.onFrameProcessed = { [weak self, weak controller] pixelBuffer, objects in
            guard let self,
                  self.isCameraTab,
                  controller?.acceptsAnalysisResults == true else { return }
            // Settings → CAMERA → "AI voice". The announcer is the only thing
            // in the app that talks unprompted, so it needs a switch; the
            // readout and the boxes are unaffected.
            if UserDefaults.standard.object(forKey: "poplur.cameraAiVoice") as? String != "0" {
                CameraAIAnnouncer.shared.announceMLObjects(objects)
            }
            self.recognitionManager?.processDetectedObjects(objects, from: pixelBuffer)
            self.submitCloudSceneScanIfRequested(pixelBuffer)
        }
    }

    /// One explicit Scan activation may upload one reduced still. The callable
    /// carries Firebase Auth/App Check automatically; no API key or live stream
    /// ever enters the app bundle.
    private func submitCloudSceneScanIfRequested(_ pixelBuffer: CVPixelBuffer) {
        guard cloudScanRequested, !cloudScanInFlight, isCameraTab else { return }
        cloudScanRequested = false
        cloudScanInFlight = true

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = image.extent
        let scale = min(1, 640 / max(extent.width, extent.height))
        let reduced = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cgImage = context.createCGImage(reduced, from: reduced.extent),
              let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.68) else {
            cloudScanInFlight = false
            return
        }

        Functions.functions(region: "us-central1").httpsCallable("cameraSceneScan").call([
            "imageBase64": jpeg.base64EncodedString()
        ]) { [weak self] result, _ in
            Task { @MainActor in
                guard let self else { return }
                self.cloudScanInFlight = false
                guard self.isCameraTab, self.webWantsDetection,
                      let data = result?.data as? [String: Any],
                      let primary = data["primary"] as? String,
                      !primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let confidence = (data["confidence"] as? NSNumber)?.floatValue ?? 0.7
                let context = (data["context"] as? [String] ?? []).prefix(3)
                self.latestCloudClassifications = [DetectedObject(identifier: primary, confidence: confidence)]
                    + context.map { DetectedObject(identifier: $0, confidence: max(0.45, confidence - 0.12)) }
                self.publishCombinedDetections()
            }
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
        let recognized = recognitionManager?.recognizedUser
        let recognizedBounds = recognitionManager?.recognizedFaceBounds
        if let face = latestARFace {
            var facePayload: [String: Any] = [
                "id": "face",
                "x": Double(face.bounds.minX),
                "y": Double(1 - face.bounds.minY - face.bounds.height),
                "w": Double(face.bounds.width),
                "h": Double(face.bounds.height),
                "label": "face",
                "confidence": Double(face.confidence),
                "roll": Double(face.roll),
                "yaw": Double(face.yaw)
            ]
            if let recognized, recognized.isRecent {
                facePayload["user"] = [
                    "handle": "@\(recognized.profile.username)",
                    "name": recognized.nameForSpeech,
                    "radiusKm": recognized.radiusMeters / 1000
                ]
                facePayload["isUser"] = true
            }
            payload.append(facePayload)
        } else if let bounds = recognizedBounds, let recognized, recognized.isRecent {
            payload.append([
                "id": "face",
                "x": Double(bounds.minX),
                "y": Double(1 - bounds.minY - bounds.height),
                "w": Double(bounds.width),
                "h": Double(bounds.height),
                "label": "face",
                "confidence": Double(recognized.confidence),
                "user": [
                    "handle": "@\(recognized.profile.username)",
                    "name": recognized.nameForSpeech,
                    "radiusKm": recognized.radiusMeters / 1000
                ],
                "isUser": true
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
        var emittedPrimaryClassification = false

        // The web view owns the single shader readout, and it picks its own
        // winner (most confident `whole`), so the runners-up no longer compete
        // for the line — DetectionOverlay filters `whole` out entirely, so they
        // cannot draw pills either. That was the reason for the old prefix(1),
        // and it cost more than the readout: the web grows the scan radius from
        // the labels it RECEIVES, so capping this at one meant a frame with six
        // recognised things scored the same as a frame with one.
        let presentedClassifications = latestCloudClassifications.isEmpty
            ? latestClassifications
            : latestCloudClassifications
        for (index, object) in presentedClassifications.prefix(6).enumerated() {
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
                // SimplifiedMLDetectionManager orders a stable, semantically
                // useful reading first. Preserve that decision explicitly;
                // the web must not undo it by sorting raw confidence again.
                "primary": !emittedPrimaryClassification,
                "label": label,
                "confidence": Double(object.confidence)
            ])
            emittedPrimaryClassification = true
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
        latestCloudClassifications = []
        PostLoginHomeWebView.sendDetections("[]")
    }

    private var phoneBootHaptics: Task<Void, Never>?
    private var phoneBootPlayer: AVAudioPlayer?

    private func playPhoneBootSound() {
        phoneBootPlayer?.stop()
        phoneBootPlayer = nil
        guard let url = Bundle.main.url(
            forResource: "popular_phone_bootup",
            withExtension: "mp3"
        ) else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = 0
            player.volume = 1
            player.prepareToPlay()
            player.play()
            phoneBootPlayer = player
        } catch {
            print("[WebHomeCameraModel] phone boot sound failed: \(error.localizedDescription)")
        }
    }

    private func runPhoneBootEffects(playBootSound: Bool = true) {
        if playBootSound {
            playPhoneBootSound()
        } else {
            // A theme change has its own short Pop. Do not let the longer boot
            // cue from screen entry mask it if the user changes finishes fast.
            phoneBootPlayer?.stop()
            phoneBootPlayer = nil
        }
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
        case "phoneThemeEffects":
            runPhoneBootEffects(playBootSound: false)
        case "tabChanged":
            if let tab = body["tab"] as? String {
                activeTab = tab
                liveCameraVisible = tab == "post" && webReportsLiveCamera
                if !liveCameraVisible {
                    if tab != "post" { webReportsLiveCamera = false }
                    CameraAIAnnouncer.shared.setLiveCameraActive(false)
                }
                if tab != "post", tab != "holdmenu" {
                    // This is a real destination change, even if a hold-menu
                    // overlay already removed WebHomeCameraLayer and therefore
                    // no second onDisappear will arrive to reset entry budget.
                    controllerStorage?.suspendCapture(resetEntryBudget: true)
                }
            }
        case "cameraLiveVisibilityChanged":
            let visible = (body["visible"] as? Bool) == true
            // The web Camera is deliberately unmounted while its document is
            // backgrounded. Do not mistake that lifecycle cleanup for leaving
            // the post tab: foregrounding must be able to restart the same
            // native preview before React paints its HUD again.
            if !visible,
               (body["lifecycleHidden"] as? Bool) == true {
                return
            }
            webReportsLiveCamera = visible
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
            guard let control = body["control"] as? String else { return }
            // Cleanup is intentionally valid after visibility has fallen. The
            // web sends this while a menu/composer transition is removing the
            // live surface; rejecting it behind `isCameraTab` can leave a
            // recording running until SwiftUI eventually delivers onDisappear.
            if control == "recordStop" || control == "record" {
                if controllerStorage?.isRecording == true {
                    controllerStorage?.endRecording()
                }
                return
            }
            guard isCameraTab else { return }
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
            case "recordStart":
                let controller = resolveController()
                if !controller.isRecording {
                    controller.beginRecording()
                }
            case "resumePreview":
                // A parked preview can only reopen from this explicit bridge
                // message, sent by a deliberate tap on the visible affordance.
                // Visibility changes and timers never call this path.
                Task { [weak self] in
                    guard let self, self.isCameraTab else { return }
                    await self.resolveController().resumePreviewFromUserGesture()
                }
            case "detect":
                // ML detection ships on — activateCamera turns it on every time
                // the camera tab opens — but the DETECT toggle lives in the web
                // hold menu and had no way to reach the native detector, so
                // turning it off did nothing on a device. `on` is optional so a
                // plain toggle still works.
                let controller = resolveController()
                let wantsOn = (body["on"] as? Bool) ?? (controller.mlDetectionManager == nil)
                webWantsDetection = wantsOn
                if wantsOn {
                    latestClassifications = []
                    latestCloudClassifications = []
                    cloudScanRequested = true
                    let recognition = recognitionManager ?? UserRecognitionManager()
                    recognitionManager = recognition
                    controller.userRecognitionManager = recognition
                    Task { await recognition.startRecognitionSession() }
                    enableClassificationBridge(on: controller)
                    controller.startVideoFrameDelivery()
                    if controller.visionBoxDetector == nil {
                        let boxes = VisionBoxDetector()
                        boxes.onBoxes = { [weak self, weak controller] found in
                            guard controller?.acceptsAnalysisResults == true else { return }
                            self?.receiveVisionBoxes(found)
                        }
                        controller.visionBoxDetector = boxes
                    }
                } else {
                    controller.disableMLDetection()
                    controller.visionBoxDetector = nil
                    if (controller.arFilterManager?.activeFilter ?? ARFilterManager.ARFilter.none) == ARFilterManager.ARFilter.none {
                        controller.stopVideoFrameDelivery()
                    }
                    cloudScanRequested = false
                    latestClassifications = []
                    latestCloudClassifications = []
                    latestVisionBoxes = []
                    controller.userRecognitionManager = nil
                    recognitionManager?.clearRecognition()
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
        cameraActivationGeneration &+= 1
        let activationGeneration = cameraActivationGeneration
        guard isCameraTab, UIApplication.shared.applicationState == .active else { return }
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
        guard cameraActivationGeneration == activationGeneration,
              isCameraTab,
              UIApplication.shared.applicationState == .active else { return }
        await controller.resumePreviewAfterInterruption()
        guard cameraActivationGeneration == activationGeneration,
              isCameraTab,
              UIApplication.shared.applicationState == .active else {
            // A newer activation owns the controller, or deactivateCamera()
            // already won this generation. Never let this stale continuation
            // stop a newer visible Camera session.
            if cameraActivationGeneration == activationGeneration {
                controller.suspendCapture()
            }
            return
        }

        CameraAIAnnouncer.shared.setLiveCameraActive(true)

        // Preview quality is independent from ML. Normally this is off; retain
        // a Scan tap that landed during camera permission/session startup.
        if webWantsDetection {
            latestClassifications = []
            latestCloudClassifications = []
            cloudScanRequested = true
            let recognition = recognitionManager ?? UserRecognitionManager()
            recognitionManager = recognition
            controller.userRecognitionManager = recognition
            enableClassificationBridge(on: controller)
            controller.startVideoFrameDelivery()
            if controller.visionBoxDetector == nil {
                let boxes = VisionBoxDetector()
                boxes.onBoxes = { [weak self, weak controller] found in
                    guard controller?.acceptsAnalysisResults == true else { return }
                    self?.receiveVisionBoxes(found)
                }
                controller.visionBoxDetector = boxes
            }
            await recognition.startRecognitionSession()
        } else {
            controller.disableMLDetection()
            controller.visionBoxDetector = nil
            controller.stopVideoFrameDelivery()
        }
        UserDefaults.standard.set(webWantsDetection, forKey: "CameraObjectDetectionEnabled")
    }

    /// Mirrors HomeView.recordTabContent.onDisappear.
    func deactivateCamera() {
        cameraActivationGeneration &+= 1
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
        // Clear any boxes left painted over a camera that is no longer running.
        clearWebDetections()
        controllerStorage?.suspendCapture(
            resetEntryBudget: activeTab != "post" && activeTab != "holdmenu"
        )

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
            // Detection text is rendered once by Camera.tsx. Mounting the
            // native MLCameraShaderOverlay here as well produced a second
            // shader label plus its runner-up chips over the same live frame.
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
    @ObservedObject private var profileThemeStore = ProfileThemeStore.shared
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
                    if type == "notificationsRead" {
                        // The web notifications panel replaced the native
                        // ProfileView's, and markAllRead() was only ever called
                        // from that native screen -- so reading your
                        // notifications cleared the in-app dot and left the app
                        // icon badge lit with nothing unread behind it.
                        Task { @MainActor in PoplurNotificationCenter.shared.markAllRead() }
                    }
                    if type == "requestVoiceAssistant" {
                        // This message can only come from the explicit HEY
                        // POPLUR profile button. It is therefore the permission
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
        .preferredColorScheme(
            camera.activeTab == "profile"
                ? profileThemeStore.selectedTheme.preferredColorScheme
                : nil
        )
        // NOT started on appear any more. Arming the recognizer just because Home
        // mounted is what made "Hey Poplur" always-on, and always-on cost a live
        // AVAudioEngine + a continuous mic tap + a speech recognizer for the
        // entire session. Measured on device: turning it off took the feed video
        // from 0.52x real time / ~13fps to 1.0x / 28-38fps and stopped the phone
        // overheating. It had also parked the audio session in `.measurement`,
        // silencing all playback.
        //
        // The way in is now the PROFILE rail's HEY POPLUR button, which the web
        // bridges as `requestVoiceAssistant` -> requestPermissionAndStartCommand()
        // (see onWebEvent above). Stopping is still unconditional: backgrounding or
        // leaving Home must never leave the microphone open.
        .onDisappear { poplurAI.stop() }
        .onChange(of: scenePhase) { _, phase in
            // Calls, Control Center and permission sheets may make SwiftUI's
            // scene `.inactive` while Poplur remains fully visible behind the
            // system UI. Treating that as a background transition unmounted the
            // web screen tree and left only the native status/HUD chrome on a
            // black surface. Only a real background transition tears down the
            // camera or tells the web layer it is hidden.
            if phase == .background {
                PostLoginHomeWebView.setApplicationActive(false)
                poplurAI.stop()
                camera.deactivateCamera()
            } else {
                PostLoginHomeWebView.setApplicationActive(true)
                if camera.isCameraTab {
                    Task { await camera.activateCamera() }
                }
            }
        }
        .onChange(of: camera.presentsCreator) { _, isPresented in
            (PostLoginHomeWebView.liveWebView as? PoplurManagedWebView)?
                .setHostOccluded(isPresented)
            if isPresented {
                poplurAI.stop()
                camera.deactivateCamera()
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
