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
final class PostUploadService {
    static let shared = PostUploadService()

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

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        let center = NotificationCenter.default

        // The capture flows announce where the post belongs before handing over
        // the media, so remember it for the upload that follows.
        center.addObserver(forName: Notification.Name("SetCameraCoordinate"), object: nil, queue: .main) { [weak self] note in
            guard let info = note.userInfo,
                  let latitude = info["latitude"] as? Double,
                  let longitude = info["longitude"] as? Double else { return }
            self?.pendingCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        center.addObserver(forName: Notification.Name("UploadImageToCurrentCoordinate"), object: nil, queue: nil) { [weak self] note in
            guard let image = note.object as? UIImage else { return }
            let radius = self?.takeRadius() ?? 5000
            let caption = self?.takeCaption()
            let requestID = self?.takeRequestID()
            guard let coordinate = self?.resolveCoordinate() else {
                Self.report(success: false, message: "No location for this post yet.", requestID: requestID)
                return
            }
            Task { await self?.upload(image: image, at: coordinate, radiusMeters: radius, caption: caption, requestID: requestID) }
        }

        center.addObserver(forName: Notification.Name("UploadVideoToCurrentCoordinate"), object: nil, queue: nil) { [weak self] note in
            guard let url = note.object as? URL else { return }
            let radius = self?.takeRadius() ?? 5000
            let caption = self?.takeCaption()
            let requestID = self?.takeRequestID()
            guard let coordinate = self?.resolveCoordinate() else {
                Self.report(success: false, message: "No location for this post yet.", requestID: requestID)
                return
            }
            Task { await self?.upload(videoURL: url, at: coordinate, radiusMeters: radius, caption: caption, requestID: requestID) }
        }

        // A web-composer post can carry an explicit map coordinate. HomeView is
        // not mounted while the web home is active, so the service must own this
        // canonical route instead of relying on HomeView's old observer.
        center.addObserver(forName: Notification.Name("UploadPostToCoordinate"), object: nil, queue: nil) { [weak self] note in
            guard let self,
                  let info = note.userInfo,
                  let latitude = info["latitude"] as? Double,
                  let longitude = info["longitude"] as? Double else { return }
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            let radius = self.takeRadius()
            let caption = self.takeCaption()
            let requestID = self.takeRequestID()
            if let image = info["image"] as? UIImage {
                Task { await self.upload(image: image, at: coordinate, radiusMeters: radius, caption: caption, requestID: requestID) }
            } else if let videoURL = info["videoURL"] as? URL {
                Task { await self.upload(videoURL: videoURL, at: coordinate, radiusMeters: radius, caption: caption, requestID: requestID) }
            } else {
                Self.report(success: false, message: "That post had no media to upload.", requestID: requestID)
            }
        }
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

    private func upload(image: UIImage, at coordinate: CLLocationCoordinate2D, radiusMeters: Int, caption: String?, requestID: String?) async {
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            Self.report(success: false, message: "That photo could not be prepared.", requestID: requestID)
            return
        }
        do {
            let reference = Storage.storage().reference().child("media/\(UUID().uuidString).jpg")
            _ = try await reference.putDataAsync(data)
            let mediaURL = try await reference.downloadURL().absoluteString
            try await savePost(mediaURL: mediaURL, posterURL: nil, at: coordinate, radiusMeters: radiusMeters, caption: caption)
            Self.report(success: true, message: nil, requestID: requestID)
        } catch {
            Self.report(success: false, message: error.localizedDescription, requestID: requestID)
        }
    }

    private func upload(videoURL: URL, at coordinate: CLLocationCoordinate2D, radiusMeters: Int, caption: String?, requestID: String?) async {
        do {
            let reference = Storage.storage().reference().child("media/\(UUID().uuidString).mp4")
            _ = try await reference.putFileAsync(from: videoURL)
            let mediaURL = try await reference.downloadURL().absoluteString

            // A poster frame keeps the feed from showing a black tile before the
            // clip decodes, matching what the picker upload stores.
            var posterURL: String?
            if let poster = Self.posterJPEG(for: videoURL) {
                let posterRef = Storage.storage().reference().child("media/\(UUID().uuidString)-poster.jpg")
                _ = try? await posterRef.putDataAsync(poster)
                posterURL = try? await posterRef.downloadURL().absoluteString
            }

            try await savePost(mediaURL: mediaURL, posterURL: posterURL, at: coordinate, radiusMeters: radiusMeters, caption: caption)
            Self.report(success: true, message: nil, requestID: requestID)
        } catch {
            Self.report(success: false, message: error.localizedDescription, requestID: requestID)
        }
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
