import Foundation
import UIKit
import CoreLocation
import AVFoundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

/// Performs the actual post upload — the step the capture flows were missing.
///
/// `UploadImageToCurrentCoordinate` / `UploadVideoToCurrentCoordinate` are the
/// app's canonical "now upload this" signals: the native capture overlay
/// (`CapturePreviewOverlay`), the map's `UploadPostToCoordinate` handler in
/// `HomeView`, and the web composer's `publishPost` bridge message all post
/// them. Nothing observed them, so every one of those routes showed an
/// "Uploading your post..." banner and then silently dropped the media — the
/// only code that actually wrote to Storage lived privately inside
/// `MediaPickerView`, reachable only from its own button.
///
/// This service is that missing observer. It mirrors the `MediaPickerView`
/// contract exactly (same Storage layout, same `posts` document shape) so posts
/// made from a capture are indistinguishable from picker uploads, and it posts
/// `PostUploadSuccess` — which `HomeView` already listens for — when a post
/// really has landed.
@MainActor
final class PostUploadService {
    static let shared = PostUploadService()

    private enum UploadPayload {
        case image(UIImage)
        case video(URL)

        var duplicateKey: String {
            switch self {
            case .image(let image):
                return "image:\(ObjectIdentifier(image).hashValue)"
            case .video(let url):
                return "video:\(url.standardizedFileURL.path)"
            }
        }

        var temporaryFileURL: URL? {
            guard case .video(let url) = self else { return nil }
            return PoplurTemporaryFileOwnership.isOwned(url) ? url : nil
        }
    }

    private struct UploadRequest {
        let payload: UploadPayload
        let coordinate: CLLocationCoordinate2D
        let radiusMeters: Int
        let caption: String?
        let requestID: String?

        func isDuplicate(of other: UploadRequest) -> Bool {
            if let requestID, let otherRequestID = other.requestID,
               requestID == otherRequestID {
                return true
            }
            return payload.duplicateKey == other.payload.duplicateKey
        }
    }

    /// Radius and caption arrive with the composer's post but cannot ride on the
    /// image-only notifications, so the sender stages them here immediately
    /// before posting. They apply to the next upload only.
    var nextRadiusMeters: Int?
    var nextCaption: String?
    /// Correlates the web composer's pending UI state with its native upload.
    /// Native capture flows do not set this, so their existing notifications
    /// remain unchanged.
    var nextRequestID: String?

    private var pendingCoordinate: CLLocationCoordinate2D?
    private var started = false
    private let locationManager = CLLocationManager()
    private let queuedUploadLimit = 2
    private var queuedUploads: [UploadRequest] = []
    private var activeUpload: (token: UUID, request: UploadRequest, task: Task<Void, Never>)?
    private var observerTokens: [NSObjectProtocol] = []

    private init() {}

    deinit {
        observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
        activeUpload?.task.cancel()
    }

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default

        // The capture flows announce where the post belongs before handing over
        // the media, so remember it for the upload that follows.
        observerTokens.append(center.addObserver(forName: Notification.Name("SetCameraCoordinate"), object: nil, queue: .main) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let info = note.userInfo,
                      let latitude = info["latitude"] as? Double,
                      let longitude = info["longitude"] as? Double else { return }
                self?.pendingCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
        })

        observerTokens.append(center.addObserver(forName: Notification.Name("UploadImageToCurrentCoordinate"), object: nil, queue: .main) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self, let image = note.object as? UIImage else { return }
                let radius = self.takeRadius()
                let caption = self.takeCaption()
                let requestID = self.takeRequestID()
                guard let coordinate = self.resolveCoordinate() else {
                    Self.report(success: false, message: "No location for this post yet.", requestID: requestID)
                    return
                }
                self.enqueue(UploadRequest(
                    payload: .image(image),
                    coordinate: coordinate,
                    radiusMeters: radius,
                    caption: caption,
                    requestID: requestID
                ))
            }
        })

        observerTokens.append(center.addObserver(forName: Notification.Name("UploadVideoToCurrentCoordinate"), object: nil, queue: .main) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self, let url = note.object as? URL else { return }
                let radius = self.takeRadius()
                let caption = self.takeCaption()
                let requestID = self.takeRequestID()
                guard let coordinate = self.resolveCoordinate() else {
                    PoplurTemporaryFileOwnership.deleteIfOwned(url)
                    Self.report(success: false, message: "No location for this post yet.", requestID: requestID)
                    return
                }
                self.enqueue(UploadRequest(
                    payload: .video(url),
                    coordinate: coordinate,
                    radiusMeters: radius,
                    caption: caption,
                    requestID: requestID
                ))
            }
        })

        // A web-composer post can carry an explicit map coordinate. HomeView is
        // not mounted while the web home is active, so the service must own this
        // canonical route instead of relying on HomeView's old observer.
        observerTokens.append(center.addObserver(forName: Notification.Name("UploadPostToCoordinate"), object: nil, queue: .main) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self, let info = note.userInfo else { return }
                let radius = self.takeRadius()
                let caption = self.takeCaption()
                let requestID = self.takeRequestID()
                guard let latitude = info["latitude"] as? Double,
                      let longitude = info["longitude"] as? Double else {
                    if let videoURL = info["videoURL"] as? URL {
                        PoplurTemporaryFileOwnership.deleteIfOwned(videoURL)
                    }
                    Self.report(
                        success: false,
                        message: "That post did not include a valid location.",
                        requestID: requestID
                    )
                    return
                }
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                if let image = info["image"] as? UIImage {
                    self.enqueue(UploadRequest(
                        payload: .image(image), coordinate: coordinate, radiusMeters: radius,
                        caption: caption, requestID: requestID
                    ))
                } else if let videoURL = info["videoURL"] as? URL {
                    self.enqueue(UploadRequest(
                        payload: .video(videoURL), coordinate: coordinate, radiusMeters: radius,
                        caption: caption, requestID: requestID
                    ))
                } else {
                    Self.report(success: false, message: "That post had no media to upload.", requestID: requestID)
                }
            }
        })

        observerTokens.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelUploads(reason: "Upload paused because Poplur moved to the background.")
            }
        })

        observerTokens.append(center.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.cancelUploads(reason: "Upload stopped to release memory.")
            }
        })
    }

    // MARK: - Strict upload ownership

    private func enqueue(_ request: UploadRequest) {
        let duplicate = activeUpload?.request.isDuplicate(of: request) == true
            ? activeUpload?.request
            : queuedUploads.first(where: { $0.isDuplicate(of: request) })
        if let duplicate {
            if duplicate.payload.temporaryFileURL?.standardizedFileURL
                != request.payload.temporaryFileURL?.standardizedFileURL {
                releaseTemporaryFile(for: request)
            }
            return
        }
        guard queuedUploads.count < queuedUploadLimit else {
            Self.report(
                success: false,
                message: "Two posts are already waiting to upload. Try this one again shortly.",
                requestID: request.requestID
            )
            releaseTemporaryFile(for: request)
            return
        }
        queuedUploads.append(request)
        startNextUploadIfPossible()
    }

    private func startNextUploadIfPossible() {
        guard activeUpload == nil, !queuedUploads.isEmpty else { return }
        let request = queuedUploads.removeFirst()
        let token = UUID()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.perform(request)
            self.finishUpload(token: token)
        }
        activeUpload = (token, request, task)
    }

    private func finishUpload(token: UUID) {
        guard activeUpload?.token == token else { return }
        activeUpload = nil
        startNextUploadIfPossible()
    }

    private func perform(_ request: UploadRequest) async {
        defer { releaseTemporaryFile(for: request) }
        do {
            switch request.payload {
            case .image(let image):
                try await upload(
                    image: image,
                    at: request.coordinate,
                    radiusMeters: request.radiusMeters,
                    caption: request.caption
                )
            case .video(let url):
                try await upload(
                    videoURL: url,
                    at: request.coordinate,
                    radiusMeters: request.radiusMeters,
                    caption: request.caption
                )
            }
            try Task.checkCancellation()
            Self.report(success: true, message: nil, requestID: request.requestID)
        } catch is CancellationError {
            Self.report(success: false, message: "Upload cancelled.", requestID: request.requestID)
        } catch {
            Self.report(success: false, message: error.localizedDescription, requestID: request.requestID)
        }
    }

    private func cancelUploads(reason: String) {
        if let activeUpload {
            activeUpload.task.cancel()
            releaseTemporaryFile(for: activeUpload.request)
            Self.report(success: false, message: reason, requestID: activeUpload.request.requestID)
        }
        queuedUploads.forEach {
            releaseTemporaryFile(for: $0)
            Self.report(success: false, message: reason, requestID: $0.requestID)
        }
        self.activeUpload = nil
        queuedUploads.removeAll()
    }

    private func releaseTemporaryFile(for request: UploadRequest) {
        guard let url = request.payload.temporaryFileURL else { return }
        PoplurTemporaryFileOwnership.deleteIfOwned(url)
    }

    // MARK: - Inputs

    private func takeRadius() -> Int {
        defer { nextRadiusMeters = nil }
        return nextRadiusMeters ?? 5000
    }

    private func takeCaption() -> String? {
        defer { nextCaption = nil }
        return nextCaption
    }

    private func takeRequestID() -> String? {
        defer { nextRequestID = nil }
        return nextRequestID
    }

    /// The coordinate the flow set, else the device's last known fix. A post
    /// with no location at all is refused rather than filed at (0, 0).
    private func resolveCoordinate() -> CLLocationCoordinate2D? {
        if let pending = pendingCoordinate { return pending }
        return locationManager.location?.coordinate
    }

    // MARK: - Upload

    private func upload(image: UIImage, at coordinate: CLLocationCoordinate2D, radiusMeters: Int, caption: String?) async throws {
        guard let data = image.poplur4KJPEGData() else {
            throw NSError(
                domain: "PostUploadService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "That photo could not be prepared."]
            )
        }
        try Task.checkCancellation()
        let reference = Storage.storage().reference().child("media/\(UUID().uuidString).jpg")
        _ = try await reference.putDataAsync(data)
        try Task.checkCancellation()
        let mediaURL = try await reference.downloadURL().absoluteString
        try await savePost(mediaURL: mediaURL, posterURL: nil, at: coordinate, radiusMeters: radiusMeters, caption: caption)
    }

    private func upload(videoURL: URL, at coordinate: CLLocationCoordinate2D, radiusMeters: Int, caption: String?) async throws {
        try Task.checkCancellation()
        let reference = Storage.storage().reference().child("media/\(UUID().uuidString).mp4")
        _ = try await reference.putFileAsync(from: videoURL)
        try Task.checkCancellation()
        let mediaURL = try await reference.downloadURL().absoluteString

        // A poster frame keeps the feed from showing a black tile before the
        // clip decodes, matching what the picker upload stores.
        var posterURL: String?
        if let poster = Self.posterJPEG(for: videoURL) {
            let posterRef = Storage.storage().reference().child("media/\(UUID().uuidString)-poster.jpg")
            _ = try? await posterRef.putDataAsync(poster)
            posterURL = try? await posterRef.downloadURL().absoluteString
        }

        try Task.checkCancellation()
        try await savePost(mediaURL: mediaURL, posterURL: posterURL, at: coordinate, radiusMeters: radiusMeters, caption: caption)
    }

    /// Same document shape `MediaPickerView.savePostToFirestore` writes, so both
    /// paths produce identical posts.
    private func savePost(
        mediaURL: String,
        posterURL: String?,
        at coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        caption: String?
    ) async throws {
        var post: [String: Any] = [
            "latitude": coordinate.latitude,
            "longitude": coordinate.longitude,
            "mediaURL": mediaURL,
            "radius": radiusMeters,
            "viewCount": 0,
            "createdAt": FieldValue.serverTimestamp(),
            "createdAtMillis": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        if let uid = Auth.auth().currentUser?.uid { post["userID"] = uid }
        if let posterURL, !posterURL.isEmpty { post["posterURL"] = posterURL }
        if let caption, !caption.isEmpty { post["caption"] = caption }

        _ = try await Firestore.firestore().collection("posts").addDocument(data: post)
    }

    private static func posterJPEG(for videoURL: URL) -> Data? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        guard let cgImage = try? generator.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
    }

    /// `PostUploadSuccess` is already observed by HomeView, which dismisses the
    /// uploading banner. Failures get their own name so a silent drop can never
    /// look like a success again.
    private static func report(success: Bool, message: String?, requestID: String? = nil) {
        DispatchQueue.main.async {
            var userInfo: [String: Any] = [:]
            if let message { userInfo["message"] = message }
            if let requestID { userInfo["requestId"] = requestID }
            NotificationCenter.default.post(
                name: Notification.Name(success ? "PostUploadSuccess" : "PostUploadFailed"),
                object: nil,
                userInfo: userInfo.isEmpty ? nil : userInfo
            )
        }
    }
}
