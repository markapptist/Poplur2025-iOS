import AVFoundation
#if canImport(UIKit)
import UIKit
#endif
import SwiftUI
import CoreLocation
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore

private var isRunningInPreviews: Bool {
    let env = ProcessInfo.processInfo.environment
    return env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || env["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1" || ProcessInfo.processInfo.arguments.contains("-XcodePreviews")
}

class CameraKitController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, RecordPreviewViewControllerProviding, PreviewViewControllerProviding, AVCaptureFileOutputRecordingDelegate, CLLocationManagerDelegate {
    // MARK: - Properties
    let sessionQueue = DispatchQueue(label: "camera.session.queue")
    let captureSession = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    let movieOutput = AVCaptureMovieFileOutput()
    private var isSessionConfigured = false
    
    // Added private flag to allow photo capture
    private var allowPhotoCapture: Bool = true
    
    // MARK: - AR Filter Support
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private let videoOutputQueue = DispatchQueue(label: "camera.video.filter", qos: .userInitiated)
    private var arFilterManager: ARFilterManager?
    private var displayLayer: AVSampleBufferDisplayLayer?
    /// Keep display connection reference
    private var previewConnection: AVCaptureConnection?
    
    /// Provide a default ARFilterManager if none is set
    @MainActor private func ensureDefaultARFilterManager() {
        if self.arFilterManager == nil {
            self.arFilterManager = ARFilterManager()
        }
    }
    
    // MARK: - ML Detection Support
    @Published var isMLDetectionEnabled: Bool = false
    var mlDetectionManager: SimplifiedMLDetectionManager?
    
    // MARK: - User Recognition Support
    var userRecognitionManager: UserRecognitionManager?
    
    // MARK: - Camera State
    @Published var isTorchOn: Bool = false
    @Published var isScreenFlashOn: Bool = false // For front camera "flash"
    @Published var currentCameraPosition: AVCaptureDevice.Position = .back
    @Published var isRecording: Bool = false
    private var currentVideoInput: AVCaptureDeviceInput?
    private var isMovieRecordingRequested = false
    private var shouldStopRecordingWhenStarted = false

    // Added published property for last recorded video URL
    @Published var lastVideoURL: URL? = nil
    
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
        
        // Listen for coordinate override from map long-press
        Foundation.NotificationCenter.default.addObserver(
            forName: Notification.Name("SetCameraCoordinate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let userInfo = notification.userInfo,
                  let latitude = userInfo["latitude"] as? Double,
                  let longitude = userInfo["longitude"] as? Double else {
                return
            }
            
            Task { @MainActor in
                self.overrideCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
        }
        
        // Listen for image upload request from map placement
        Foundation.NotificationCenter.default.addObserver(
            forName: Notification.Name("UploadImageToCurrentCoordinate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let image = notification.object as? UIImage else {
                return
            }
            
            Task { @MainActor in
                self.requestLocationAuthorizationIfNeeded()
                let loc = await self.currentLocation()
                let coord = self.overrideCoordinate ?? loc?.coordinate
                await self.postImage(image, at: coord)
            }
        }
        
        // Listen for video upload request from map placement
        Foundation.NotificationCenter.default.addObserver(
            forName: Notification.Name("UploadVideoToCurrentCoordinate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let videoURL = notification.object as? URL else {
                return
            }
            
            Task { @MainActor in
                self.requestLocationAuthorizationIfNeeded()
                let loc = await self.currentLocation()
                let coord = self.overrideCoordinate ?? loc?.coordinate
                let processedURL = await self.exportCroppedPortrait9x16(inputURL: videoURL) ?? videoURL
                if let url = await self.uploadVideoToStorage(fileURL: processedURL) {
                    await self.writePostDocument(mediaURL: url, coordinate: coord, mediaType: "video")
                }
            }
        }
        
        // Listen for image upload request to profile (no coordinate required)
        Foundation.NotificationCenter.default.addObserver(
            forName: Notification.Name("UploadImageToProfile"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let image = notification.object as? UIImage else {
                return
            }
            Task { @MainActor in
                Foundation.NotificationCenter.default.post(name: Notification.Name("PostUploadStarted"), object: nil)
                if let url = await self.uploadImageToStorage(image) {
                    await self.writePostDocument(mediaURL: url, coordinate: nil, mediaType: "photo_profile")
                } else {
                    Foundation.NotificationCenter.default.post(
                        name: Notification.Name("PostUploadFailed"),
                        object: nil,
                        userInfo: ["error": "Image upload failed"]
                    )
                }
            }
        }
        
        // Listen for video upload request to profile (no coordinate required)
        Foundation.NotificationCenter.default.addObserver(
            forName: Notification.Name("UploadVideoToProfile"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let videoURL = notification.object as? URL else {
                return
            }
            Task { @MainActor in
                Foundation.NotificationCenter.default.post(name: Notification.Name("PostUploadStarted"), object: nil)
                let processedURL = await self.exportCroppedPortrait9x16(inputURL: videoURL) ?? videoURL
                if let url = await self.uploadVideoToStorage(fileURL: processedURL) {
                    await self.writePostDocument(mediaURL: url, coordinate: nil, mediaType: "video_profile")
                } else {
                    Foundation.NotificationCenter.default.post(
                        name: Notification.Name("PostUploadFailed"),
                        object: nil,
                        userInfo: ["error": "Video upload failed"]
                    )
                }
            }
        }

        // Gesture-driven camera controls
        NotificationCenter.default.addObserver(
            forName: Notification.Name("CameraToggleTorchOn"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.toggleTorchOn()
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("CameraToggleTorchOff"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.toggleTorchOff()
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("FlipCameraRequested"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.flipCamera()
        }
        
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ToggleARFilters"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.ensureDefaultARFilterManager()
            if let previewVC = (self.recordPreviewViewController ?? self.previewViewController) as? CameraPreviewViewController,
               let arLayer = previewVC.getARDisplayLayer(),
               let mgr = self.arFilterManager {
                self.sessionQueue.async { [weak self] in
                    guard let self = self else { return }
                    self.setupARFilterSupport(filterManager: mgr, displayLayer: arLayer)
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .cameraCubeTabViewTapped,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleCubeTapCapture()
        }

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
    
    // Override coordinate - set when user long-presses on map
    private var overrideCoordinate: CLLocationCoordinate2D?

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

        captureSession.beginConfiguration()

        // Start with a lighter preset for fastest first frame; ramp up after startRunning
        if captureSession.canSetSessionPreset(.medium) {
            captureSession.sessionPreset = .medium
        } else if captureSession.canSetSessionPreset(.high) {
            captureSession.sessionPreset = .high
        } else if captureSession.canSetSessionPreset(.hd1920x1080) {
            captureSession.sessionPreset = .hd1920x1080
        }

        // Input: back wide-angle camera
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                    currentVideoInput = input // Store reference
                    currentCameraPosition = .back
                }
            } catch {
            }
        }

        // Output: photo output (if not already added)
        if !captureSession.outputs.contains(photoOutput) {
            if captureSession.canAddOutput(photoOutput) {
                captureSession.addOutput(photoOutput)

                // Set orientation to portrait
                if let connection = photoOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
        }

        // Output: movie output (for video recording)
        if !captureSession.outputs.contains(movieOutput) {
            if captureSession.canAddOutput(movieOutput) {
                captureSession.addOutput(movieOutput)

                // Set orientation to portrait
                if let connection = movieOutput.connection(with: .video),
                   connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
            }
        }

        // Input: microphone for video audio
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(audioInput) {
                    captureSession.addInput(audioInput)
                }
            } catch {
            }
        }

        captureSession.commitConfiguration()

        isSessionConfigured = true
    }
    
    // MARK: - Camera Controls
    
    /// Flip between front and back camera
    @objc func flipCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Disable animations for instant flip
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            
            self.captureSession.beginConfiguration()
            
            // Remove current video input
            if let currentInput = self.currentVideoInput {
                self.captureSession.removeInput(currentInput)
            }
            
            // Determine new position
            let newPosition: AVCaptureDevice.Position = self.currentCameraPosition == .back ? .front : .back
            
            // Get new device
            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else {
                // Re-add the old input
                if let currentInput = self.currentVideoInput,
                   self.captureSession.canAddInput(currentInput) {
                    self.captureSession.addInput(currentInput)
                }
                self.captureSession.commitConfiguration()
                CATransaction.commit()
                return
            }
            
            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)
                
                if self.captureSession.canAddInput(newInput) {
                    self.captureSession.addInput(newInput)
                    self.currentVideoInput = newInput
                    
                    // IMPORTANT: Update position synchronously
                    self.currentCameraPosition = newPosition
                    
                    // Also update on MainActor for UI binding
                    Task { @MainActor in
                        self.currentCameraPosition = newPosition
                    }
                    
                    // ⚡️ SET ORIENTATION IMMEDIATELY - don't wait for commit!
                    self.setAllVideoConnectionsToPortrait()
                    
                    // Reattach videoDataOutput if missing from session outputs and refresh connection
                    if let vdo = self.videoDataOutput, !self.captureSession.outputs.contains(where: { $0 == vdo }) {
                        if self.captureSession.canAddOutput(vdo) {
                            self.captureSession.addOutput(vdo)
                        }
                        if let connection = vdo.connection(with: .video) {
                            connection.isEnabled = true
                            if connection.isVideoRotationAngleSupported(90) {
                                connection.videoRotationAngle = 90
                            }
                            if connection.isVideoMirroringSupported {
                                connection.isVideoMirrored = (self.currentCameraPosition == .front)
                            }
                            self.previewConnection = connection
                        }
                    }
                    
                } else {
                    // Re-add the old input
                    if let currentInput = self.currentVideoInput,
                       self.captureSession.canAddInput(currentInput) {
                        self.captureSession.addInput(currentInput)
                    }
                    self.captureSession.commitConfiguration()
                    CATransaction.commit()
                    return
                }
            } catch {
                // Re-add the old input
                if let currentInput = self.currentVideoInput,
                   self.captureSession.canAddInput(currentInput) {
                    self.captureSession.addInput(currentInput)
                }
                self.captureSession.commitConfiguration()
                CATransaction.commit()
                return
            }
            
            // Commit configuration
            self.captureSession.commitConfiguration()
            CATransaction.commit()
            
            // After commit, set orientation again for previewConnection
            if let connection = self.previewConnection {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90
                }
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = (self.currentCameraPosition == .front)
                }
            }
            
            // Update display layer transform on main thread without animation
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                
                // Update mirroring based on camera position
                if self.currentCameraPosition == .front {
                    self.displayLayer?.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
                } else {
                    self.displayLayer?.setAffineTransform(.identity)
                }
                
                CATransaction.commit()
                
                NotificationCenter.default.post(name: Notification.Name("CameraFlipped"), object: nil)
            }
        }
    }
    
    /// Alternative name for flip camera
    @objc func switchCamera() {
        flipCamera()
    }
    
    /// Toggle torch/flashlight
    @objc func toggleTorch() {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.currentVideoInput?.device else { return }
            
            guard device.hasTorch, device.isTorchAvailable else {
                return
            }
            
            do {
                try device.lockForConfiguration()
                
                if device.torchMode == .on {
                    device.torchMode = .off
                    Task { @MainActor in
                        self.isTorchOn = false
                    }
                } else {
                    try device.setTorchModeOn(level: 1.0)
                    Task { @MainActor in
                        self.isTorchOn = true
                    }
                }
                
                device.unlockForConfiguration()
            } catch {
            }
        }
    }
    
    /// Alternative name for toggle torch
    @objc func toggleFlash() {
        toggleTorch()
    }
    
    @MainActor
    func toggleTorchOn() {
        // Front camera uses screen flash
        if currentCameraPosition == .front {
            isScreenFlashOn = true
            NotificationCenter.default.post(name: Notification.Name("ScreenFlashOn"), object: nil)
            return
        }
        
        // Back camera uses LED torch
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentVideoInput?.device, device.hasTorch else {
                return
            }
            do {
                try device.lockForConfiguration()
                try device.setTorchModeOn(level: 1.0)
                device.unlockForConfiguration()
                Task { @MainActor in self.isTorchOn = true }
            } catch {
            }
        }
    }

    @MainActor
    func toggleTorchOff() {
        // Front camera uses screen flash
        if currentCameraPosition == .front {
            isScreenFlashOn = false
            NotificationCenter.default.post(name: Notification.Name("ScreenFlashOff"), object: nil)
            return
        }
        
        // Back camera uses LED torch
        sessionQueue.async { [weak self] in
            guard let self, let device = self.currentVideoInput?.device, device.hasTorch else {
                return
            }
            do {
                try device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
                Task { @MainActor in self.isTorchOn = false }
            } catch {
            }
        }
    }
    
    /// Helper to set all video connections to portrait orientation
    private func setAllVideoConnectionsToPortrait() {
        
        // Set photo output connection
        if let photoConnection = photoOutput.connection(with: .video) {
            if photoConnection.isVideoRotationAngleSupported(90) {
                photoConnection.videoRotationAngle = 90
            }
            // Don't mirror photo output - we want photos to be correct
            if photoConnection.isVideoMirroringSupported {
                photoConnection.isVideoMirrored = false
            }
        }

        // Set movie output connection
        if let movieConnection = movieOutput.connection(with: .video) {
            if movieConnection.isVideoRotationAngleSupported(90) {
                movieConnection.videoRotationAngle = 90
            }
            // Don't mirror video output - we want videos to be correct
            if movieConnection.isVideoMirroringSupported {
                movieConnection.isVideoMirrored = false
            }
        }

        // Set video data output connection (for AR filters / live preview)
        if let videoDataConnection = videoDataOutput?.connection(with: .video) {
            if videoDataConnection.isVideoRotationAngleSupported(90) {
                videoDataConnection.videoRotationAngle = 90
            }
            // Mirror for front camera preview only (display layer handles this)
            if videoDataConnection.isVideoMirroringSupported {
                videoDataConnection.isVideoMirrored = false
            }
        }

        // Update previewConnection if available
        if let previewConnection = self.previewConnection {
            if previewConnection.isVideoRotationAngleSupported(90) {
                previewConnection.videoRotationAngle = 90
            }
            if previewConnection.isVideoMirroringSupported {
                previewConnection.isVideoMirrored = false
            }
        }
    }
    
    @MainActor
    private func requestLocationAuthorizationIfNeeded() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    private func currentLocation() async -> CLLocation? {
        // If override coordinate is set (from map long-press), use it and clear
        if let override = overrideCoordinate {
            let location = CLLocation(latitude: override.latitude, longitude: override.longitude)
            return location
        }
        
        // Otherwise, request current location
        return await withCheckedContinuation { (cont: CheckedContinuation<CLLocation?, Never>) in
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
        #if DEBUG
        if isRunningInPreviews { return }
        #endif
        
        guard let uid = Auth.auth().currentUser?.uid else {
            Foundation.NotificationCenter.default.post(
                name: Notification.Name("PostUploadFailed"),
                object: nil,
                userInfo: ["error": "Not authenticated"]
            )
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
        // Mark profile posts
        if mediaType.hasSuffix("_profile") {
            data["isProfile"] = true
        }
        if let c = coordinate {
            data["latitude"] = c.latitude
            data["longitude"] = c.longitude
        }
        do {
            try await docRef.setData(data)
            
            self.overrideCoordinate = nil
            
            // Post success notification
            Foundation.NotificationCenter.default.post(
                name: Notification.Name("PostUploadSuccess"),
                object: nil,
                userInfo: ["docID": docRef.documentID]
            )
            
            // Trigger profile and map reload
            Foundation.NotificationCenter.default.post(name: .LoadProfileNow, object: nil)
            Foundation.NotificationCenter.default.post(name: .LoadMapNow, object: nil)
        } catch {
            
            // Post failure notification
            Foundation.NotificationCenter.default.post(
                name: Notification.Name("PostUploadFailed"),
                object: nil,
                userInfo: ["error": error.localizedDescription]
            )
        }
    }
    
    
    private func uploadImageToStorage(_ image: UIImage) async -> URL? {
        #if DEBUG
        if isRunningInPreviews { return nil }
        #endif
        
        // Ensure user is authenticated if rules require auth
        guard Auth.auth().currentUser != nil else {
            return nil
        }
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            return nil
        }
        let storage = Storage.storage()
        let bucketRef = storage.reference()

        let path = "posts/\(UUID().uuidString).jpg"
        let ref = bucketRef.child(path)

        // Provide metadata to satisfy any contentType rules
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        do {
            _ = try await ref.putDataAsync(data, metadata: metadata)
            let url = try await ref.downloadURL()
            return url
        } catch {
            return nil
        }
    }

    private func uploadVideoToStorage(fileURL: URL) async -> URL? {
        #if DEBUG
        if isRunningInPreviews { return nil }
        #endif
        
        // Ensure user is authenticated if rules require auth
        guard Auth.auth().currentUser != nil else {
            return nil
        }
        let storage = Storage.storage()
        let bucketRef = storage.reference()

        let path = "posts/\(UUID().uuidString).mp4"
        let ref = bucketRef.child(path)

        // Provide metadata to satisfy any contentType rules
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        do {
            _ = try await ref.putFileAsync(from: fileURL, metadata: metadata)
            let url = try await ref.downloadURL()
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Video Post-Processing (Crop to 9:16 Portrait)
    private func exportCroppedPortrait9x16(inputURL: URL) async -> URL? {
        let asset = AVURLAsset(url: inputURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
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
            return inputURL
        }

        // Build composition
        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            return nil
        }
        do {
            try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: videoTrack, at: .zero)
        } catch {
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
            return nil
        }
        export.shouldOptimizeForNetworkUse = true
        export.videoComposition = videoComposition
        do {
            try await export.export(to: outputURL, as: .mp4)
            return outputURL
        } catch {
            return nil
        }
    }

    // MARK: - Verify Session Integrity
    private func verifySessionIntegrity(context: String) {
        let hasInputs = !captureSession.inputs.isEmpty
        let hasOutputs = !captureSession.outputs.isEmpty
    }

    // MARK: - Preview Fallback
    @MainActor
    private func ensurePreviewFallbackIfNeeded() {
        // If a Snap record VC is not provided, prepare a generic preview VC bound to our session.
        if recordPreviewViewController == nil {
            // Only create once 
            if previewViewController == nil {
                #if canImport(UIKit)
                let previewVC = CameraPreviewViewController()
                // Attach current capture session to preview layer so raw camera shows
                previewVC.setCaptureSession(self.captureSession)
                
                if let arLayer = previewVC.getARDisplayLayer() {
                    self.ensureDefaultARFilterManager()
                    if let mgr = self.arFilterManager {
                        // Call on sessionQueue to avoid blocking main
                        self.sessionQueue.async { [weak self] in
                            guard let self = self else { return }
                            self.setupARFilterSupport(filterManager: mgr, displayLayer: arLayer)
                            
                            // Auto-enable a default filter for live preview
                            Task { @MainActor in
                                mgr.activeFilter = .beautyFilter
                            }
                            
                            // If ARFilterManager supports 3D face overlay, enable it
                            if (mgr as AnyObject).responds(to: Selector(("enableFace3DOverlayIfAvailable"))) {
                                _ = (mgr as AnyObject).perform(Selector(("enableFace3DOverlayIfAvailable")))
                            }
                        }
                    }
                }
                
                self.previewViewController = previewVC
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

    @MainActor
    private func presentCapturePreviewHost(_ host: UIHostingController<CapturePreviewOverlay>) {
        presentCapturePreviewHost(host, attempt: 0)
    }

    @MainActor
    private func presentCapturePreviewHost(_ host: UIHostingController<CapturePreviewOverlay>, attempt: Int) {
        guard let presenter = topMostViewController() else {
            retryPresentCapturePreviewHost(host, attempt: attempt)
            return
        }
        if presenter is UIHostingController<CapturePreviewOverlay> {
            presenter.dismiss(animated: false) { [weak self, weak host] in
                guard let self, let host else { return }
                Task { @MainActor in
                    self.presentCapturePreviewHost(host, attempt: attempt + 1)
                }
            }
            return
        }
        if presenter.presentedViewController == nil {
            presenter.present(host, animated: true)
            print("[CameraKitController] Presented capture preview")
        } else {
            retryPresentCapturePreviewHost(host, attempt: attempt)
        }
    }

    @MainActor
    private func retryPresentCapturePreviewHost(_ host: UIHostingController<CapturePreviewOverlay>, attempt: Int) {
        guard attempt < 8 else {
            print("[CameraKitController] Failed to present capture preview after retries")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self, weak host] in
            guard let self = self, let host = host else { return }
            self.presentCapturePreviewHost(host, attempt: attempt + 1)
        }
    }

    // MARK: - Photo Capture
    func takePhoto() {
        print("[CameraKitController] takePhoto() called")
        // Block photo capture while recording (robust, main-thread check)
        if !self.allowPhotoCapture || self.isRecording || self.movieOutput.isRecording {
            print("[CameraKitController] takePhoto() BLOCKED on main: allowPhotoCapture=\(self.allowPhotoCapture) isRecording=\(self.isRecording) movieRecording=\(self.movieOutput.isRecording)")
            NotificationCenter.default.post(name: Notification.Name("PhotoCaptureBlockedDuringRecording"), object: nil)
            return
        }
        sessionQueue.async { [weak self] in
            guard let self else { return }
            print("[CameraKitController] takePhoto() executing on session queue")
            
            // Double-check on session queue to avoid races
            if !self.allowPhotoCapture || self.isRecording || self.movieOutput.isRecording {
                print("[CameraKitController] takePhoto() BLOCKED on session queue: allowPhotoCapture=\(self.allowPhotoCapture) isRecording=\(self.isRecording) movieRecording=\(self.movieOutput.isRecording)")
                return
            }

            // Ensure session is running
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }

            // Ensure photoOutput is attached
            if !self.captureSession.outputs.contains(self.photoOutput) {
                self.captureSession.beginConfiguration()
                if self.captureSession.canAddOutput(self.photoOutput) {
                    self.captureSession.addOutput(self.photoOutput)
                    self.photoOutput.isHighResolutionCaptureEnabled = true
                }
                self.captureSession.commitConfiguration()
            }

            // Verify running and connection
            guard self.captureSession.isRunning else {
                return
            }

            // Fetch the video connection for photoOutput
            var connection = self.photoOutput.connection(with: .video)
            if connection == nil || (connection?.isEnabled == false) {
                self.captureSession.beginConfiguration()
                // Try to re-add the output to refresh connections
                if self.captureSession.outputs.contains(self.photoOutput) {
                    self.captureSession.removeOutput(self.photoOutput)
                }
                if self.captureSession.canAddOutput(self.photoOutput) {
                    self.captureSession.addOutput(self.photoOutput)
                }
                self.captureSession.commitConfiguration()
                // Re-fetch connection
                connection = self.photoOutput.connection(with: .video)
            }

            guard let videoConnection = connection, videoConnection.isEnabled else {
                return
            }

            // Optionally align orientation if supported
            if videoConnection.isVideoRotationAngleSupported(90) {
                videoConnection.videoRotationAngle = 90
            }

            let settings = AVCapturePhotoSettings()
            
            // NO AUTO FLASH - user controls flash manually with swipe gestures
            settings.flashMode = .off
            
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    /// Handle cube tab tap: capture AR-filtered frame if available; otherwise take a photo
    private func handleCubeTapCapture() {
        print("[CameraKitController] Cube tap received")
        // Block capturing while recording
        if !self.allowPhotoCapture || self.isRecording || self.movieOutput.isRecording {
            print("[CameraKitController] Cube tap BLOCKED: allowPhotoCapture=\(self.allowPhotoCapture) isRecording=\(self.isRecording) movieRecording=\(self.movieOutput.isRecording)")
            NotificationCenter.default.post(name: Notification.Name("PhotoCaptureBlockedDuringRecording"), object: nil)
            return
        }
        self.takePhoto()
    }

    // MARK: - Video Recording
    func startVideoRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.configureSessionIfNeeded()
            // Ensure session is running
            if !self.captureSession.isRunning {
                self.captureSession.startRunning()
            }
            // Start recording to a temp file if not already recording
            if !self.movieOutput.isRecording {
                self.isMovieRecordingRequested = true
                self.shouldStopRecordingWhenStarted = false
                let tempURL = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mov")

                if let connection = self.movieOutput.connection(with: .video) {
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                    if connection.isVideoStabilizationSupported {
                        connection.preferredVideoStabilizationMode = .auto
                    }
                }

                self.movieOutput.startRecording(to: tempURL, recordingDelegate: self)
                print("[CameraKitController] startRecording requested: \(tempURL.path)")
                
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isRecording = true
                    self.allowPhotoCapture = false
                    NotificationCenter.default.post(name: Notification.Name("RecordingStarted"), object: nil)
                    NotificationCenter.default.post(name: Notification.Name("CubeInteractionDisabled"), object: nil)
                    print("[CameraKitController] Recording STARTED: allowPhotoCapture=\(self.allowPhotoCapture)")
                }
            }
        }
    }

    func stopVideoRecording() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.movieOutput.isRecording {
                self.shouldStopRecordingWhenStarted = false
                self.movieOutput.stopRecording()
                print("[CameraKitController] stopRecording requested")
            } else if self.isMovieRecordingRequested {
                self.shouldStopRecordingWhenStarted = true
                print("[CameraKitController] stopRecording queued until movie output starts")
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isRecording = false
                    self.allowPhotoCapture = true
                    NotificationCenter.default.post(name: Notification.Name("RecordingStopped"), object: nil)
                    NotificationCenter.default.post(name: Notification.Name("CubeInteractionEnabled"), object: nil)
                    print("[CameraKitController] stopRecording ignored: movie output was not recording")
                }
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
        // Always (re)attach the running session to the preview layer in case the VC was recreated
        if let previewVC = (self.recordPreviewViewController ?? self.previewViewController) as? CameraPreviewViewController {
            previewVC.setCaptureSession(self.captureSession)
            
            if let arLayer = previewVC.getARDisplayLayer() {
                self.ensureDefaultARFilterManager()
                if let mgr = self.arFilterManager {
                    // Call on sessionQueue to avoid blocking main
                    self.sessionQueue.async { [weak self] in
                        guard let self = self else { return }
                        self.setupARFilterSupport(filterManager: mgr, displayLayer: arLayer)
                        
                        // If ARFilterManager supports 3D face overlay, enable it
                        if (mgr as AnyObject).responds(to: Selector(("enableFace3DOverlayIfAvailable"))) {
                            _ = (mgr as AnyObject).perform(Selector(("enableFace3DOverlayIfAvailable")))
                        }
                    }
                }
            }
        }
        // Mark readiness based on either a record preview, a running session, or configured session
        self.isReady = self.hasRecordPreview || self.captureSession.isRunning || self.isSessionConfigured

        // Reflect cube interaction availability based on allowPhotoCapture
        if self.allowPhotoCapture {
            NotificationCenter.default.post(name: Notification.Name("CubeInteractionEnabled"), object: nil)
        } else {
            NotificationCenter.default.post(name: Notification.Name("CubeInteractionDisabled"), object: nil)
        }
        print("[CameraKitController] preparePreviewIfNeeded cubeEnabled=\(self.allowPhotoCapture)")
    }

    @MainActor
    private func postImage(_ image: UIImage, at coordinate: CLLocationCoordinate2D?) {
        Foundation.NotificationCenter.default.post(name: Notification.Name("PostUploadStarted"), object: nil)
        Task {
            if let url = await uploadImageToStorage(image) {
                await writePostDocument(mediaURL: url, coordinate: coordinate, mediaType: "photo")
            }
        }
    }

    // MARK: - AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let _ = error {
        } else {
            let data = photo.fileDataRepresentation() ?? Data()
            #if canImport(UIKit)
            if var image = UIImage(data: data) {
                
                // CRITICAL FIX: Create correctly oriented image first
                // The image from AVCapturePhoto has orientation metadata but SwiftUI doesn't respect it
                if let cgImage = image.cgImage {
                    // Draw the image in correct orientation to a new context
                    let size = image.size
                    UIGraphicsBeginImageContextWithOptions(size, false, image.scale)
                    image.draw(in: CGRect(origin: .zero, size: size))
                    let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                    
                    if let normalized = normalizedImage {
                        image = normalized
                    }
                }
                
                // Fix orientation - photos from front camera need to be mirrored horizontally
                // and all photos need proper orientation applied
                if currentCameraPosition == .front {
                    // Front camera photos should be mirrored to match what user saw in preview
                    image = image.withHorizontallyFlippedOrientation()
                }
                
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    // Present SwiftUI capture overlay full-screen
                    let overlay = CapturePreviewOverlay(image: image, videoURL: nil)
                    let host = UIHostingController(rootView: overlay)
                    host.modalPresentationStyle = .fullScreen
                    
                    // Notify preview if we have a map-selected coordinate
                    if let coord = self.overrideCoordinate {
                        NotificationCenter.default.post(
                            name: Notification.Name("CapturePreviewFromMapLocation"),
                            object: nil,
                            userInfo: [
                                "latitude": coord.latitude,
                                "longitude": coord.longitude
                            ]
                        )
                    }

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
                            let coord = self.overrideCoordinate ?? loc?.coordinate
                            if let url = await self.uploadImageToStorage(image) {
                                await self.writePostDocument(mediaURL: url, coordinate: coord, mediaType: "photo")
                            }
                            host?.dismiss(animated: true)
                        }
                        if let dismissObserver { NotificationCenter.default.removeObserver(dismissObserver) }
                        if let useObserver { NotificationCenter.default.removeObserver(useObserver) }
                    }

                    self.presentCapturePreviewHost(host)
                }
            }
            #endif
        }
    }
    
    @MainActor
    func start() async {
        #if DEBUG
        if isRunningInPreviews { return }
        #endif
        
        // Request access on main, then configure/start on sessionQueue
        let granted = await requestCameraAccessIfNeeded()
        guard granted else {
            self.isReady = self.hasRecordPreview // allow UI to show fallback if present
            return
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [weak self] in
                guard let self else { cont.resume(); return }
                self.configureSessionIfNeeded()
                if !self.captureSession.isRunning {
                    self.captureSession.startRunning()
                }

                // Ramp preset after initial start for quality
                if self.captureSession.canSetSessionPreset(.hd1920x1080) {
                    // Small delay to ensure first frame displays
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                        guard let self else { return }
                        self.sessionQueue.async {
                            self.captureSession.beginConfiguration()
                            self.captureSession.sessionPreset = .hd1920x1080
                            self.captureSession.commitConfiguration()
                        }
                    }
                }

                cont.resume()
            }
        }
        await MainActor.run {
            if let previewVC = (self.recordPreviewViewController ?? self.previewViewController) as? CameraPreviewViewController {
                previewVC.setCaptureSession(self.captureSession)
                if let arLayer = previewVC.getARDisplayLayer() {
                    self.ensureDefaultARFilterManager()
                    if let mgr = self.arFilterManager {
                        self.sessionQueue.async { [weak self] in
                            guard let self = self else { return }
                            self.setupARFilterSupport(filterManager: mgr, displayLayer: arLayer)
                            
                            // If ARFilterManager supports 3D face overlay, enable it
                            if (mgr as AnyObject).responds(to: Selector(("enableFace3DOverlayIfAvailable"))) {
                                _ = (mgr as AnyObject).perform(Selector(("enableFace3DOverlayIfAvailable")))
                            }
                        }
                    }
                }
            }
        }

        self.ensurePreviewFallbackIfNeeded()
        self.isReady = self.hasRecordPreview || self.captureSession.isRunning || self.isSessionConfigured

        // Reflect cube interaction availability based on allowPhotoCapture
        if self.allowPhotoCapture {
            NotificationCenter.default.post(name: Notification.Name("CubeInteractionEnabled"), object: nil)
        } else {
            NotificationCenter.default.post(name: Notification.Name("CubeInteractionDisabled"), object: nil)
        }
        print("[CameraKitController] start() cubeEnabled=\(self.allowPhotoCapture)")

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
            }
        }
    }

    @MainActor
    func prewarm() async {
        #if DEBUG
        if isRunningInPreviews { return }
        #endif
        
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
        #if DEBUG
        if isRunningInPreviews { return }
        #endif
        
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
                        }
                    }
                }

                cont.resume()
            }
        }
        await MainActor.run {
            if let previewVC = (self.recordPreviewViewController ?? self.previewViewController) as? CameraPreviewViewController {
                previewVC.setCaptureSession(self.captureSession)
            }
        }
        self.ensurePreviewFallbackIfNeeded()
        self.isReady = self.hasRecordPreview || self.captureSession.isRunning || self.isSessionConfigured

        // Reflect cube interaction availability based on allowPhotoCapture
        if self.allowPhotoCapture {
            NotificationCenter.default.post(name: Notification.Name("CubeInteractionEnabled"), object: nil)
        } else {
            NotificationCenter.default.post(name: Notification.Name("CubeInteractionDisabled"), object: nil)
        }
        print("[CameraKitController] startPreview() cubeEnabled=\(self.allowPhotoCapture)")
    }

    @MainActor
    func resumePreviewAfterInterruption() async {
        #if DEBUG
        if isRunningInPreviews { return }
        #endif

        await startPreview()
        if let previewVC = (self.recordPreviewViewController ?? self.previewViewController) as? CameraPreviewViewController,
           let arLayer = previewVC.getARDisplayLayer() {
            arLayer.flushAndRemoveImage()
        }
        preparePreviewIfNeeded()
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraKitController {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.shouldStopRecordingWhenStarted {
                self.shouldStopRecordingWhenStarted = false
                if self.movieOutput.isRecording {
                    self.movieOutput.stopRecording()
                    print("[CameraKitController] queued stop applied after recording started")
                }
            }
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error {
            let nsError = error as NSError
            let finishedSuccessfully = nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false
            let fileExists = FileManager.default.fileExists(atPath: outputFileURL.path)
            if !finishedSuccessfully && !fileExists {
                print("[CameraKitController] Recording failed without output: \(error.localizedDescription)")
                sessionQueue.async { [weak self] in
                    self?.isMovieRecordingRequested = false
                    self?.shouldStopRecordingWhenStarted = false
                }
                return
            }
            print("[CameraKitController] Recording finished with recoverable status: \(error.localizedDescription)")
        }

        sessionQueue.async { [weak self] in
            self?.isMovieRecordingRequested = false
            self?.shouldStopRecordingWhenStarted = false
        }
        
        // Set lastVideoURL on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastVideoURL = outputFileURL
            self.isRecording = false
            self.allowPhotoCapture = true
            NotificationCenter.default.post(name: Notification.Name("CubeInteractionEnabled"), object: nil)
            
            if let coord = self.overrideCoordinate {
                Foundation.NotificationCenter.default.post(
                    name: Notification.Name("CapturePreviewFromMapLocation"),
                    object: nil,
                    userInfo: [
                        "latitude": coord.latitude,
                        "longitude": coord.longitude
                    ]
                )
            }

            NotificationCenter.default.post(
                name: Notification.Name("RecordingOutputReady"),
                object: nil,
                userInfo: ["url": outputFileURL]
            )
            NotificationCenter.default.post(name: Notification.Name("RecordingStopped"), object: nil)
            print("[CameraKitController] Recording output ready: \(outputFileURL.path)")
        }
    }
}

// MARK: - AR Filter Support & AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraKitController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    /// Setup AR filter video processing
    func setupARFilterSupport(filterManager: ARFilterManager, displayLayer: AVSampleBufferDisplayLayer?) {
        self.arFilterManager = filterManager
        self.displayLayer = displayLayer
        
        // Enable default filter immediately on main actor
        Task { @MainActor in
            filterManager.activeFilter = .beautyFilter
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Create video data output
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: self.videoOutputQueue)
            
            // Add to session
            self.captureSession.beginConfiguration()
            
            // Remove existing video output if any
            if let existingOutput = self.videoDataOutput {
                self.captureSession.removeOutput(existingOutput)
            }
            
            // Add new output
            if self.captureSession.canAddOutput(output) {
                self.captureSession.addOutput(output)
                self.videoDataOutput = output
                
                // Configure video orientation
                if let connection = output.connection(with: .video) {
                    connection.isEnabled = true
                    if connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                    if connection.isVideoMirroringSupported {
                        connection.isVideoMirrored = (self.currentCameraPosition == .front)
                    }
                    self.previewConnection = connection
                }
            }
            
            self.captureSession.commitConfiguration()
            
            // Setup displayLayer videoGravity and transform
            DispatchQueue.main.async {
                self.displayLayer?.videoGravity = .resizeAspectFill
                if self.currentCameraPosition == .front {
                    self.displayLayer?.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
                } else {
                    self.displayLayer?.setAffineTransform(.identity)
                }
            }
        }
    }
    
    // Centralized safe enqueue to suppress spurious errors and respect backpressure
    private func safelyEnqueueSampleBuffer(_ sampleBuffer: CMSampleBuffer, to displayLayer: AVSampleBufferDisplayLayer) {
        // Validate buffer
        if !CMSampleBufferIsValid(sampleBuffer) { return }
        if !CMSampleBufferDataIsReady(sampleBuffer) { return }

        // Validate layer status
        let status = displayLayer.status
        if status == .failed {
            displayLayer.flushAndRemoveImage()
            return
        }
        if status == .unknown {
            // Try flushing unknown state and wait for next frame
            displayLayer.flushAndRemoveImage()
            return
        }

        // Respect backpressure; drop frame if not ready
        if !displayLayer.isReadyForMoreMediaData { return }

        // Optionally ensure presentation time is monotonic
        displayLayer.enqueue(sampleBuffer)
    }
    
    // Broadcast radius updates for registered user recognition
    @MainActor
    func publishRegisteredUserRadius(_ radius: Int) {
        NotificationCenter.default.post(name: Notification.Name("RegisteredUserRadiusUpdated"), object: nil, userInfo: ["radius": radius])
    }
    
    // MARK: - Video Sample Buffer Delegate
    
    // CRITICAL: Do NOT use @MainActor here - video frames arrive at 30-60fps
    // Running this on main thread will freeze the UI
    @MainActor func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Process ML detection if enabled
        if isMLDetectionEnabled {
            mlDetectionManager?.processFrame(sampleBuffer)
        }
        
        // Process user recognition (face detection for registered users)
        if let userRecognition = userRecognitionManager,
           let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            userRecognition.detectFaces(in: pixelBuffer)
        }
        
        // If user recognition manager exposes registered-user radius, publish it here
        // Example:
        // if let radius = userRecognition.currentRegisteredUserRadius { Task { @MainActor in self.publishRegisteredUserRadius(radius) } }
        
        // Process AR filters and display frames
        guard let displayLayer = displayLayer else {
            // No display layer setup - AR filters not configured
            return
        }
        
        // Check if we have a filter manager
        guard let filterManager = arFilterManager else {
            // No filter manager - just display raw frames
            DispatchQueue.main.async {
                // Ensure displayLayer transform is correct for front / back
                if self.currentCameraPosition == .front {
                    self.displayLayer?.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
                } else {
                    self.displayLayer?.setAffineTransform(.identity)
                }
                // Recover display layer if it has failed or is unknown
                let status = displayLayer.status
                if status == .failed || status == .unknown {
                    displayLayer.flushAndRemoveImage()
                }
                self.safelyEnqueueSampleBuffer(sampleBuffer, to: displayLayer)
            }
            return
        }
        
        // Track filter processing start time for performance monitoring
        let processingStartTime = CFAbsoluteTimeGetCurrent()
        
        // Process frame with AR filter (the method is nonisolated so it's safe to call from background thread)
        filterManager.applyFilterToVideoFrame(sampleBuffer) { [weak self] filteredBuffer in
            guard let self = self,
                  let displayLayer = self.displayLayer else {
                return
            }
            
            // Calculate processing time
            let processingTime = (CFAbsoluteTimeGetCurrent() - processingStartTime) * 1000 // ms
            
            // Log performance if it takes longer than expected (>33ms for 30fps)
            if processingTime > 33 {
            }
            
            // Display the filtered (or original if filtering failed) frame
            let bufferToDisplay = filteredBuffer ?? sampleBuffer
            
            // Enqueue on main thread as CALayer operations must be on main thread
            DispatchQueue.main.async {
                // Ensure displayLayer transform is correct for front / back
                if self.currentCameraPosition == .front {
                    self.displayLayer?.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
                } else {
                    self.displayLayer?.setAffineTransform(.identity)
                }
                
                // Recover display layer if it has failed or is unknown
                let status = displayLayer.status
                if status == .failed || status == .unknown {
                    displayLayer.flushAndRemoveImage()
                }
                
                self.safelyEnqueueSampleBuffer(bufferToDisplay, to: displayLayer)
            }
        }
    }
    
    // MARK: - ML Detection Helper
    
    /// Enable ML detection with optional callback
    @MainActor
    func enableMLDetection(onDetection: (([DetectedObject]) -> Void)? = nil) {
        if mlDetectionManager == nil {
            mlDetectionManager = SimplifiedMLDetectionManager()
        }
        mlDetectionManager?.isEnabled = true
        mlDetectionManager?.onDetection = onDetection
        isMLDetectionEnabled = true
    }
    
    /// Disable ML detection
    @MainActor
    func disableMLDetection() {
        mlDetectionManager?.isEnabled = false
        isMLDetectionEnabled = false
    }
}

// MARK: - CLLocationManagerDelegate

extension CameraKitController {
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
        locationContinuation?.resume(returning: nil)
        locationContinuation = nil
    }
}

// MARK: - UIImage Orientation Helpers

#if canImport(UIKit)
extension UIImage {
    /// Returns a horizontally flipped version of the image
    func withHorizontallyFlippedOrientation() -> UIImage {
        guard let cgImage = self.cgImage else { return self }
        
        // Create a new image with flipped orientation
        let flippedOrientation: UIImage.Orientation
        switch imageOrientation {
        case .up:
            flippedOrientation = .upMirrored
        case .down:
            flippedOrientation = .downMirrored
        case .left:
            flippedOrientation = .leftMirrored
        case .right:
            flippedOrientation = .rightMirrored
        case .upMirrored:
            flippedOrientation = .up
        case .downMirrored:
            flippedOrientation = .down
        case .leftMirrored:
            flippedOrientation = .left
        case .rightMirrored:
            flippedOrientation = .right
        @unknown default:
            flippedOrientation = .up
        }
        
        return UIImage(cgImage: cgImage, scale: scale, orientation: flippedOrientation)
    }
}
#endif
