import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI
import CoreLocation
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore

class CameraKitController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, RecordPreviewViewControllerProviding, PreviewViewControllerProviding {
    // MARK: - Properties
    let sessionQueue = DispatchQueue(label: "camera.session.queue")
    let captureSession = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    let movieOutput = AVCaptureMovieFileOutput()
    private var isSessionConfigured = false
    
    // Snap Kit / Record-specific camera VC. Set this from your Snap setup code.
    var recordPreviewViewController: UIViewController?

    // Optional generic preview VC fallback if needed elsewhere.
    var previewViewController: UIViewController?
    
    @Published var isReady: Bool = false
    @Published var hasRecordPreview: Bool = false

    // Integration callbacks (set these from your app)
    // Called when user taps Post in the preview. Provide both image and coordinate for map posting.
    var onPostToMap: ((UIImage, CLLocationCoordinate2D) -> Void)?
    // Called when user taps Post in the preview to add to profile.
    var onPostToProfile: ((UIImage) -> Void)?
    
    override init() {
        super.init()
        #if DEBUG
        // Skip heavy prewarm when running SwiftUI previews (handle both env var and launch arg)
        let isRunningInPreviews = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" ||
                                  ProcessInfo.processInfo.arguments.contains("-XcodePreviews")
        if isRunningInPreviews {
            return
        }
        #endif
        // Prewarm configuration early so first appearance is fast
        Task { [weak self] in
            guard let self else { return }
            // Request camera access if needed but do not block UI
            _ = await self.requestCameraAccessIfNeeded()
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                self.sessionQueue.async { [weak self] in
                    guard let self else { cont.resume(); return }
                    self.configureSessionIfNeeded()
                    cont.resume()
                }
            }
            await MainActor.run {
                // Prepare a preview fallback so the tab has something to display immediately
                self.ensurePreviewFallbackIfNeeded()
                // Mark ready if either we have a Snap record VC installed or our session is configured (even if not running yet)
                self.isReady = self.hasRecordPreview || self.isSessionConfigured
            }
        }
    }

    // MARK: - Location
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

    // MARK: - SnapKit Integration
    @MainActor
    func installSnapRecordPreview(_ viewController: UIViewController) {
        self.recordPreviewViewController = viewController
        self.hasRecordPreview = true
        // Mark ready to allow UI to render immediately
        self.isReady = true
    }
    
    // MARK: - Session Configuration
    private func requestCameraAccessIfNeeded() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func configureSessionIfNeeded() {
        guard !isSessionConfigured else { return }
        print("[CK][Config] Begin configuration")

        captureSession.beginConfiguration()

        // Start with a lighter preset for fastest first frame; ramp up after startRunning
        if captureSession.canSetSessionPreset(.medium) {
            captureSession.sessionPreset = .medium
        } else if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        } else if captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        }
        print("[CK][Config] Session preset: \(captureSession.sessionPreset.rawValue)")

        // Input: back wide-angle camera
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                    print("[CK][Config] Added back camera input")
                } else {
                    print("[CK][Config] Cannot add camera input")
                }
            } catch {
                print("[CK][Config] Error creating camera input: \(error)")
            }
        } else {
            print("[CK][Config] No back camera available")
        }

        // Output: photo output (if not already added)
        if !captureSession.outputs.contains(photoOutput) {
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)
                photoOutput.isHighResolutionCaptureEnabled = true
                print("[CK][Config] Added photo output")
            } else {
                print("[CK][Config] Cannot add photo output")
            }
        }

        // Output: movie output (for video recording)
        if !captureSession.outputs.contains(movieOutput) {
            if captureSession.canAddOutput(movieOutput) {
                captureSession.addOutput(movieOutput)
                print("[CK][Config] Added movie output")
            } else {
                print("[CK][Config] Cannot add movie output")
            }
        }

        // Input: microphone for video audio
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(audioInput) {
                    captureSession.addInput(audioInput)
                    print("[CK][Config] Added audio input")
                } else {
                    print("[CK][Config] Cannot add audio input")
                }
            } catch {
                print("[CK][Config] Error creating audio input: \(error)")
            }
        } else {
            print("[CK][Config] No audio device available")
        }

        print("[CK][Config] Committing configuration")
        captureSession.commitConfiguration()
        print("[CK][Config] Configuration committed")

        isSessionConfigured = true
    }
    
    @MainActor
    private func requestLocationAuthorizationIfNeeded() {
        let status = CLLocationManager.authorizationStatus()
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    private func currentLocation() async -> CLLocation? {
        await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
            DispatchQueue.main.async { [weak self] in
                guard let self else { cont.resume(returning: nil); return }
                self.locationContinuation = cont
                self.locationManager.delegate = self
                self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
                self.locationManager.requestLocation()
            }
        }
    }

    // MARK: - Firebase Helpers
    
    @MainActor
    private func writePostDocument(mediaURL: URL, coordinate: CLLocationCoordinate2D?, mediaType: String) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("[CK][Post] No authenticated user; cannot write post")
            return
        }
        let db = Firestore.firestore()
        let docRef = db.collection("posts").document()
        var data: [String: Any] = [
            "userID": uid,
            "createdAt": FieldValue.serverTimestamp(),
            "mediaURL": mediaURL.absoluteString,
            "viewCount": 0,
            "radius": 5000,
            "mediaType": mediaType
        ]
        if let c = coordinate {
            data["latitude"] = c.latitude
            data["longitude"] = c.longitude
        }
        do {
            try await docRef.setData(data)
            print("[CK][Post] Wrote post doc: \(docRef.documentID)")
            NotificationCenter.default.post(name: .LoadProfileNow, object: nil)
            NotificationCenter.default.post(name: .LoadMapNow, object: nil)
        } catch {
            print("[CK][Post] Failed to write post doc: \(error)")
        }
    }
    
    private func uploadImageToStorage(_ image: UIImage) async -> URL? {
        // Ensure user is authenticated if rules require auth
        guard let user = Auth.auth().currentUser else {
            print("[CK][Upload] No authenticated user; Storage rules may require auth. Aborting image upload.")
            return nil
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            print("[CK][Upload] Could not create JPEG data from image")
            return nil
        }
        let storage = Storage.storage()
        let bucketRef = storage.reference()
        print("[CK][Upload] Using bucket: \(bucketRef.bucket), user: \(user.uid)")

        let path = "posts/\(UUID().uuidString).jpg"
        let ref = bucketRef.child(path)

        // Provide metadata to satisfy any contentType rules
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        do {
            _ = try await ref.putDataAsync(data, metadata: metadata)
            let url = try await ref.downloadURL()
            print("[CK][Upload] Image uploaded to: \(url.absoluteString)")
            return url
        } catch {
            print("[CK][Upload] Image upload failed: \(error)")
            return nil
        }
    }

    private func uploadVideoToStorage(fileURL: URL) async -> URL? {
        // Ensure user is authenticated if rules require auth
        guard let user = Auth.auth().currentUser else {
            print("[CK][Upload] No authenticated user; Storage rules may require auth. Aborting video upload.")
            return nil
        }
        let storage = Storage.storage()
        let bucketRef = storage.reference()
        print("[CK][Upload] Using bucket: \(bucketRef.bucket), user: \(user.uid)")

        let path = "posts/\(UUID().uuidString).mp4"
        let ref = bucketRef.child(path)

        // Provide metadata to satisfy any contentType rules
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        do {
            _ = try await ref.putFileAsync(from: fileURL, metadata: metadata)
            let url = try await ref.downloadURL()
            print("[CK][Upload] Video uploaded to: \(url.absoluteString)")
            return url
        } catch {
            print("[CK][Upload] Video upload failed: \(error)")
            return nil
        }
    }

    // MARK: - Video Post-Processing (Crop to 9:16 Portrait)
    private func exportCroppedPortrait9x16(inputURL: URL) async -> URL? {
        let asset = AVAsset(url: inputURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            print("[CK][Export] No video track found")
            return nil
        }

        // Target 9:16 portrait size based on input height
        let inputSize = videoTrack.naturalSize.applying(videoTrack.preferredTransform)
        let width = abs(inputSize.width)
        let height = abs(inputSize.height)
        // We want portrait 9:16. Compute target width for the given height
        let targetAspect: CGFloat = 9.0/16.0
        let targetWidth = height * targetAspect

        // If the input is already near 9:16 portrait, skip export
        let inputAspect = width / height
        if abs(inputAspect - targetAspect) < 0.01 && height >= width {
            print("[CK][Export] Skipping crop — already near 9:16 portrait")
            return inputURL
        }

        // Build composition
        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            print("[CK][Export] Failed to create composition track")
            return nil
        }
        do {
            try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: videoTrack, at: .zero)
        } catch {
            print("[CK][Export] Insert time range failed: \(error)")
            return nil
        }

        // Orientation & transform
        compVideo.preferredTransform = videoTrack.preferredTransform

        // Video composition for cropping
        let videoComposition = AVMutableVideoComposition()
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(videoTrack.nominalFrameRate > 0 ? videoTrack.nominalFrameRate : 30))
        let renderSize = CGSize(width: targetWidth, height: height)
        videoComposition.renderSize = renderSize

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)

        // Compute scale so that the shorter dimension fills target; then center-crop horizontally
        let naturalSize = videoTrack.naturalSize
        let tx = videoTrack.preferredTransform
        let transformedSize = naturalSize.applying(tx)
        let srcWidth = abs(transformedSize.width)
        let srcHeight = abs(transformedSize.height)

        let scale = max(renderSize.width / srcWidth, renderSize.height / srcHeight)
        let scaledWidth = srcWidth * scale
        let scaledHeight = srcHeight * scale

        // Center horizontally
        let xOffset = (renderSize.width - scaledWidth) / 2.0
        let yOffset = (renderSize.height - scaledHeight) / 2.0

        var transform = tx
        transform = transform.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        transform = transform.concatenating(CGAffineTransform(translationX: xOffset, y: yOffset))

        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // Export
        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            print("[CK][Export] Could not create export session")
            return nil
        }
        export.outputURL = outputURL
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        export.videoComposition = videoComposition

        return await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            export.exportAsynchronously {
                switch export.status {
                case .completed:
                    print("[CK][Export] Export completed: \(outputURL)")
                    cont.resume(returning: outputURL)
                case .failed, .cancelled:
                    print("[CK][Export] Export failed: \(String(describing: export.error))")
                    cont.resume(returning: nil)
                default:
                    // .waiting or .exporting ended unexpectedly
                    print("[CK][Export] Export ended with status: \(export.status)")
                    cont.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Verify Session Integrity
    private func verifySessionIntegrity(context: String) {
        let hasInputs = !captureSession.inputs.isEmpty
        let hasOutputs = !captureSession.outputs.isEmpty
        print("[CK][Verify][\(context)] inputs: \(hasInputs ? captureSession.inputs.count : 0), outputs: \(hasOutputs ? captureSession.outputs.count : 0), isRunning: \(captureSession.isRunning)")
        if !hasInputs { print("[CK][Verify][\(context)] WARNING: No inputs attached") }
        if !hasOutputs { print("[CK][Verify][\(context)] WARNING: No outputs attached") }
    }

    // MARK: - Preview Fallback
    @MainActor
    private func ensurePreviewFallbackIfNeeded() {
        // If a Snap record VC is not provided, prepare a generic preview VC bound to our session.
        if recordPreviewViewController == nil {
            // Only create once
            if previewViewController == nil {
                #if canImport(UIKit)
                let preview = CameraPreviewViewController(session: captureSession)
                preview.onShutter = { [weak self] in self?.takePhoto() }
                preview.onStartVideo = { [weak self] in self?.startVideoRecording() }
                preview.onStopVideo  = { [weak self] in self?.stopVideoRecording() }
                self.previewViewController = preview
                print("[CK][Preview] Created fallback CameraPreviewViewController")
                // Mark ready since we now have a preview to display
                self.isReady = true
                #else
                self.previewViewController = nil
                #endif
            }
        }
    }

    private func topMostViewController() -> UIViewController? {
        #if canImport(UIKit)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first(where: { $0.isKeyWindow }),
           var top = window.rootViewController {
            while let presented = top.presentedViewController {
                top = presented
            }
            return top
        }
        return nil
        #else
        return nil
        #endif
    }

    // MARK: - Photo Capture
    func takePhoto() {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            // Ensure session is running
            if !self.captureSession.isRunning {
                print("[CK][Photo] Session not running — attempting to start before capture")
                self.captureSession.startRunning()
            }

            // Ensure photoOutput is attached
            if !self.captureSession.outputs.contains(self.photoOutput) {
                print("[CK][Photo] photoOutput missing — attempting to attach")
                self.captureSession.beginConfiguration()
                if self.captureSession.canAddOutput(self.photoOutput) {
                    self.captureSession.addOutput(self.photoOutput)
                    self.photoOutput.isHighResolutionCaptureEnabled = true
                } else {
                    print("[CK][Photo] Cannot add photoOutput even after attempt")
                }
                self.captureSession.commitConfiguration()
            }

            // Verify running and connection
            guard self.captureSession.isRunning else {
                print("[CK][Photo] Abort: session still not running")
                return
            }

            // Fetch the video connection for photoOutput
            var connection = self.photoOutput.connection(with: .video)
            if connection == nil || (connection?.isEnabled == false) {
                print("[CK][Photo] No active/enabled video connection — attempting to reconfigure")
                self.captureSession.beginConfiguration()
                // Try to re-add the output to refresh connections
                if self.captureSession.outputs.contains(self.photoOutput) {
                    self.captureSession.removeOutput(self.photoOutput)
                }
                if self.captureSession.canAddOutput(self.photoOutput) {
                    self.captureSession.addOutput(self.photoOutput)
                    self.photoOutput.isHighResolutionCaptureEnabled = true
                }
                self.captureSession.commitConfiguration()
                // Re-fetch connection
                connection = self.photoOutput.connection(with: .video)
            }

            guard let videoConnection = connection, videoConnection.isEnabled else {
                print("[CK][Photo] Abort: No active and enabled video connection after reconfigure")
                return
            }

            // Optionally align orientation if supported
            if videoConnection.isVideoOrientationSupported {
                videoConnection.videoOrientation = .portrait
            }

            let settings = AVCapturePhotoSettings()
            settings.isHighResolutionPhotoEnabled = true
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Video Recording
    func startVideoRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // Ensure session is running
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
            // Start recording to a temp file if not already recording
            if !self.movieOutput.isRecording {
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")

                if let connection = self.movieOutput.connection(with: .video) {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .auto
                    }
                }

                self.movieOutput.startRecording(to: tempURL, recordingDelegate: self)
            }
        }
    }

    func stopVideoRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
        }
    }

    @MainActor
    func beginRecording() {
        self.startVideoRecording()
    }

    @MainActor
    func endRecording() {
        self.stopVideoRecording()
    }
    
    @MainActor
    func preparePreviewIfNeeded() {
        self.ensurePreviewFallbackIfNeeded()
        self.isReady = self.hasRecordPreview || self.captureSession.isRunning || self.isSessionConfigured
    }

    @MainActor
    private func postImage(_ image: UIImage, at coordinate: CLLocationCoordinate2D?) {
        Task {
            if let url = await uploadImageToStorage(image) {
                await writePostDocument(mediaURL: url, coordinate: coordinate, mediaType: "photo")
            } else {
                print("[CK][Post] Skipping post; image upload failed")
            }
        }
    }

    // MARK: - AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("[CK][Photo] Processing error: \(error)")
        } else {
            let data = photo.fileDataRepresentation() ?? Data()
            print("[CK][Photo] Photo captured with \(data.count) bytes")
            #if canImport(UIKit)
            if let image = UIImage(data: data) {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    // Present SwiftUI capture overlay full-screen
                    let overlay = CapturePreviewOverlay(image: image, videoURL: nil)
                    let host = UIHostingController(rootView: overlay)
                    host.modalPresentationStyle = .fullScreen

                    // Observers for overlay actions
                    var dismissObserver: NSObjectProtocol?
                    var useObserver: NSObjectProtocol?

                    dismissObserver = NotificationCenter.default.addObserver(forName: Notification.Name("InlinePreviewDismissRequested"), object: nil, queue: .main) { [weak host] _ in
                        host?.dismiss(animated: true)
                        if let dismissObserver { NotificationCenter.default.removeObserver(dismissObserver) }
                        if let useObserver { NotificationCenter.default.removeObserver(useObserver) }
                    }
                    useObserver = NotificationCenter.default.addObserver(forName: Notification.Name("InlinePreviewUseRequested"), object: nil, queue: .main) { [weak self, weak host] _ in
                        guard let self else { return }
                        Task { @MainActor in
                            self.requestLocationAuthorizationIfNeeded()
                            let loc = await self.currentLocation()
                            let coord = loc?.coordinate
                            self.postImage(image, at: coord)
                            host?.dismiss(animated: true)
                        }
                        if let dismissObserver { NotificationCenter.default.removeObserver(dismissObserver) }
                        if let useObserver { NotificationCenter.default.removeObserver(useObserver) }
                    }

                    let presenter: UIViewController? = self.recordPreviewViewController ?? self.previewViewController ?? self.topMostViewController()
                    presenter?.present(host, animated: true)
                }
            }
            #endif
        }
    }
    
    @MainActor
    func start() async {
        print("[CK][Start] Requesting camera access…")
        // Request access on main, then configure/start on sessionQueue
        let granted = await requestCameraAccessIfNeeded()
        guard granted else {
            print("[CK][Start] Camera access not granted — ready: \(self.isReady)")
            self.isReady = self.hasRecordPreview // allow UI to show fallback if present
            return
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { cont.resume(); return }
                self.configureSessionIfNeeded()
                self.verifySessionIntegrity(context: "after configure")
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }
                print("[CK][Start] startRunning called; isRunning now: \(self.captureSession.isRunning)")

                // Ramp preset after initial start for quality
                if self.captureSession.canSetSessionPreset(.hd1920x1080) {
                    // Small delay to ensure first frame displays
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        guard let self else { return }
                        self.sessionQueue.async {
                            self.captureSession.beginConfiguration()
                            self.captureSession.sessionPreset = .hd1920x1080
                            self.captureSession.commitConfiguration()
                            print("[CK][Start] Ramped preset to 1080p")
                        }
                    }
                }

                cont.resume()
            }
        }

        self.ensurePreviewFallbackIfNeeded()
        self.isReady = self.hasRecordPreview || self.captureSession.isRunning || self.isSessionConfigured
        self.verifySessionIntegrity(context: "post start")
        print("[CK][Start] Ready: \(self.isReady), hasRecordPreview: \(self.hasRecordPreview), isRunning: \(self.captureSession.isRunning)")
        self.requestLocationAuthorizationIfNeeded()
    }

    @MainActor
    func stop() {
        // Stop session asynchronously; update readiness immediately for UI.
        self.isReady = false
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                print("[CK][Stop] stopRunning called")
            }
        }
    }

    @MainActor
    func prewarm() async {
        // Request access if not determined; do not start the session.
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { cont.resume(); return }
                self.configureSessionIfNeeded()
                cont.resume()
            }
        }
    }

    @MainActor
    func startPreview() async {
        // Assume configuration was prewarmed; just start running if not already.
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { cont.resume(); return }
                self.configureSessionIfNeeded()
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }

                // Ramp preset after initial start for quality
                if self.captureSession.canSetSessionPreset(.hd1920x1080) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        guard let self else { return }
                        self.sessionQueue.async {
                            self.captureSession.beginConfiguration()
                            self.captureSession.sessionPreset = .hd1920x1080
                            self.captureSession.commitConfiguration()
                            print("[CK][Preview] Ramped preset to 1080p")
                        }
                    }
                }

                cont.resume()
            }
        }
        self.ensurePreviewFallbackIfNeeded()
        self.isReady = self.hasRecordPreview || self.captureSession.isRunning || self.isSessionConfigured
    }
}

extension CameraKitController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("[CK][Video] Recording error: \(error)")
            return
        }
        print("[CK][Video] Recorded video at: \(outputFileURL)")

        #if canImport(UIKit)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Present SwiftUI capture overlay full-screen for video
            let overlay = CapturePreviewOverlay(image: nil, videoURL: outputFileURL)
            let host = UIHostingController(rootView: overlay)
            host.modalPresentationStyle = .fullScreen

            // Observers for overlay actions
            var dismissObserver: NSObjectProtocol?
            var useObserver: NSObjectProtocol?

            dismissObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name("InlinePreviewDismissRequested"),
                object: nil,
                queue: .main
            ) { [weak host] _ in
                host?.dismiss(animated: true)
                if let dismissObserver { NotificationCenter.default.removeObserver(dismissObserver) }
                if let useObserver { NotificationCenter.default.removeObserver(useObserver) }
            }

            useObserver = NotificationCenter.default.addObserver(
                forName: Notification.Name("InlinePreviewUseRequested"),
                object: nil,
                queue: .main
            ) { [weak self, weak host] _ in
                guard let self else { return }
                Task { @MainActor in
                    // Proceed with crop -> upload -> post
                    self.requestLocationAuthorizationIfNeeded()
                    let loc = await self.currentLocation()
                    let coord = loc?.coordinate
                    let processedURL = await self.exportCroppedPortrait9x16(inputURL: outputFileURL) ?? outputFileURL
                    if let url = await self.uploadVideoToStorage(fileURL: processedURL) {
                        await self.writePostDocument(mediaURL: url, coordinate: coord, mediaType: "video")
                    } else {
                        print("[CK][Post] Skipping post; video upload failed")
                    }
                    host?.dismiss(animated: true)
                }
                if let dismissObserver { NotificationCenter.default.removeObserver(dismissObserver) }
                if let useObserver { NotificationCenter.default.removeObserver(useObserver) }
            }

            let presenter: UIViewController? = self.recordPreviewViewController ?? self.previewViewController ?? self.topMostViewController()
            presenter?.present(host, animated: true)
        }
        #else
        // If UIKit not available, fallback to immediate processing
        Task { @MainActor in
            self.requestLocationAuthorizationIfNeeded()
            let loc = await self.currentLocation()
            let coord = loc?.coordinate
            let processedURL = await self.exportCroppedPortrait9x16(inputURL: outputFileURL) ?? outputFileURL
            if let url = await self.uploadVideoToStorage(fileURL: processedURL) {
                await self.writePostDocument(mediaURL: url, coordinate: coord, mediaType: "video")
            } else {
                print("[CK][Post] Skipping post; video upload failed")
            }
        }
        #endif
    }
}

extension CameraKitController: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Choose the most recent location with good accuracy
        let now = Date()
        let freshLocations = locations.filter { now.timeIntervalSince($0.timestamp) < 10 }
        let best = (freshLocations.isEmpty ? locations : freshLocations)
            .sorted { (a, b) in a.horizontalAccuracy < b.horizontalAccuracy }
            .first
        if let best = best, best.horizontalAccuracy > 0 {
            locationContinuation?.resume(returning: best)
        } else {
            locationContinuation?.resume(returning: locations.last)
        }
        locationContinuation = nil
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[CK][Location] Failed: \(error)")
        locationContinuation?.resume(returning: nil)
        locationContinuation = nil
    }
}
