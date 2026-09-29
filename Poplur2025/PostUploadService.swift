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
        let channelID: String?
        let requestID: String?
        let postID: String
        let audience: String
        let locationVisibility: String
        let usedAI: Bool
        let rightsAttestationVersion: String?
        let photoViewSeconds: Int?
        let contentType: String
        let messageCard: Bool
        /// Carousel slides AFTER the cover, already decoded, in display order.
        /// The cover is `payload` — it keeps the unchanged storage path so an
        /// old client reading mediaURL still finds a perfectly ordinary post.
        let carouselExtras: [Data]

        func isDuplicate(of other: UploadRequest) -> Bool {
            // postID FIRST: it is the stable identity of one user intent, it
            // survives a retry (the composer deliberately resends the same id),
            // and it is identical across a repeated dispatch. Two posts made in
            // quick succession always carry DIFFERENT ids — the composer mints
            // one per mount — so this cannot block legitimate fast posting.
            if postID == other.postID { return true }
            if let requestID, let otherRequestID = other.requestID,
               requestID == otherRequestID {
                return true
            }
            // NOTE: for images this compares ObjectIdentifier(image), a memory
            // address, so two separate decodes of byte-identical media never
            // match. It catches a resend of the SAME UIImage instance and
            // nothing else — which is why it missed the double publish.
            return payload.duplicateKey == other.payload.duplicateKey
        }
    }

    /// The ground every drop is born discoverable on, earned or not.
    ///
    /// The same number by the same name in every shell that publishes a post:
    /// POST_DISCOVERY_SEED_METERS in the React Native shell's services/posts.ts
    /// and in the functions' accountRadius.ts, CLAIM_RADIUS_SEED_KM in
    /// poplur-clay-map's claimRadius.ts, and the 5.0 default Android's
    /// PostLoginWebActivity reads radiusKm with. The Firestore create rule
    /// allows a seed of the account's earned total plus this, so a post
    /// published at exactly the seed is accepted by every account.
    static let postDiscoverySeedMeters = 5_000

    /// Radius and caption arrive with the composer's post but cannot ride on the
    /// image-only notifications, so the sender stages them here immediately
    /// before posting. They apply to the next upload only.
    var nextRadiusMeters: Int?
    var nextCaption: String?
    var nextContentType: String?
    var nextMessageCard: Bool?
    var nextChannelID: String?
    /// Correlates the web composer's pending UI state with its native upload.
    /// Native capture flows do not set this, so their existing notifications
    /// remain unchanged.
    var nextRequestID: String?
    /// Stable across retries. It becomes both the Firestore document ID and
    /// Storage basename, so retrying can replace one attempt but never create
    /// a duplicate post or an unreachable object.
    var nextPostID: String?
    var nextAudience: String?
    var nextLocationVisibility: String?
    var nextUsedAI: Bool?
    var nextRightsAttestationVersion: String?
    var nextPhotoViewSeconds: Int?

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
                let channelID = self.takeChannelID()
                let requestID = self.takeRequestID()
                guard let publishContract = self.takePublishContract(requestID: requestID) else {
                    // No staged id: this dispatch is a repeat of one already
                    // handled. Refuse it instead of publishing a second post.
                    Self.report(
                        success: false,
                        message: "This post was already sent.",
                        requestID: requestID
                    )
                    return
                }
                guard let coordinate = self.resolveCoordinate() else {
                    Self.report(success: false, message: "No location for this post yet.", requestID: requestID)
                    return
                }
                self.enqueue(UploadRequest(
                    payload: .image(image),
                    coordinate: coordinate,
                    radiusMeters: radius,
                    caption: caption,
                    channelID: channelID,
                    requestID: requestID,
                    postID: publishContract.postID,
                    audience: publishContract.audience,
                    locationVisibility: publishContract.locationVisibility,
                    usedAI: publishContract.usedAI,
                    rightsAttestationVersion: publishContract.rightsAttestationVersion,
                    photoViewSeconds: publishContract.photoViewSeconds,
                    contentType: publishContract.contentType,
                    messageCard: publishContract.messageCard,
                    carouselExtras: takeCarouselExtras()
                ))
            }
        })

        observerTokens.append(center.addObserver(forName: Notification.Name("UploadVideoToCurrentCoordinate"), object: nil, queue: .main) { [weak self] note in
            Task { @MainActor [weak self] in
                guard let self, let url = note.object as? URL else { return }
                let radius = self.takeRadius()
                let caption = self.takeCaption()
                let channelID = self.takeChannelID()
                let requestID = self.takeRequestID()
                guard let publishContract = self.takePublishContract(requestID: requestID) else {
                    // No staged id: this dispatch is a repeat of one already
                    // handled. Refuse it instead of publishing a second post.
                    Self.report(
                        success: false,
                        message: "This post was already sent.",
                        requestID: requestID
                    )
                    return
                }
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
                    channelID: channelID,
                    requestID: requestID,
                    postID: publishContract.postID,
                    audience: publishContract.audience,
                    locationVisibility: publishContract.locationVisibility,
                    usedAI: publishContract.usedAI,
                    rightsAttestationVersion: publishContract.rightsAttestationVersion,
                    photoViewSeconds: publishContract.photoViewSeconds,
                    contentType: publishContract.contentType,
                    messageCard: publishContract.messageCard,
                    carouselExtras: takeCarouselExtras()
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
                let channelID = self.takeChannelID()
                let requestID = self.takeRequestID()
                guard let publishContract = self.takePublishContract(requestID: requestID) else {
                    // No staged id: this dispatch is a repeat of one already
                    // handled. Refuse it instead of publishing a second post.
                    Self.report(
                        success: false,
                        message: "This post was already sent.",
                        requestID: requestID
                    )
                    return
                }
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
                        caption: caption, channelID: channelID, requestID: requestID,
                        postID: publishContract.postID, audience: publishContract.audience,
                        locationVisibility: publishContract.locationVisibility,
                        usedAI: publishContract.usedAI,
                        rightsAttestationVersion: publishContract.rightsAttestationVersion,
                        photoViewSeconds: publishContract.photoViewSeconds,
                        contentType: publishContract.contentType,
                        messageCard: publishContract.messageCard,
                        carouselExtras: takeCarouselExtras()
                    ))
                } else if let videoURL = info["videoURL"] as? URL {
                    self.enqueue(UploadRequest(
                        payload: .video(videoURL), coordinate: coordinate, radiusMeters: radius,
                        caption: caption, channelID: channelID, requestID: requestID,
                        postID: publishContract.postID, audience: publishContract.audience,
                        locationVisibility: publishContract.locationVisibility,
                        usedAI: publishContract.usedAI,
                        rightsAttestationVersion: publishContract.rightsAttestationVersion,
                        photoViewSeconds: publishContract.photoViewSeconds,
                        contentType: publishContract.contentType,
                        messageCard: publishContract.messageCard,
                        carouselExtras: takeCarouselExtras()
                    ))
                } else {
                    Self.report(success: false, message: "That post had no media to upload.", requestID: requestID)
                }
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
        Self.reportProgress(0.02, phase: "QUEUED", requestID: request.requestID)
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
            guard Auth.auth().currentUser != nil else {
                throw NSError(
                    domain: "PostUploadService",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "Please sign in again before uploading."]
                )
            }
            // A retry after a lost success acknowledgement must not replace
            // an already-published Storage object (or its download token).
            let existingPost = try await Firestore.firestore().collection("posts")
                .document(request.postID).getDocument(source: .server)
            if existingPost.exists {
                guard existingPost.data()?["userID"] as? String == Auth.auth().currentUser?.uid else {
                    throw NSError(domain: "PostUploadService", code: 6,
                        userInfo: [NSLocalizedDescriptionKey: "This post ID is already in use. Please start a new post."])
                }
                Self.reportProgress(1, phase: "POSTED", requestID: request.requestID)
                Self.report(success: true, message: nil, requestID: request.requestID)
                return
            }
            Self.reportProgress(0.06, phase: "PREPARING", requestID: request.requestID)
            switch request.payload {
            case .image(let image):
                try await upload(
                    image: image,
                    at: request.coordinate,
                    radiusMeters: request.radiusMeters,
                    caption: request.caption,
                    channelID: request.channelID,
                    requestID: request.requestID,
                    postID: request.postID,
                    audience: request.audience,
                    locationVisibility: request.locationVisibility,
                    usedAI: request.usedAI,
                    rightsAttestationVersion: request.rightsAttestationVersion,
                    photoViewSeconds: request.photoViewSeconds,
                    contentType: request.contentType,
                    messageCard: request.messageCard,
                    carouselExtras: request.carouselExtras
                )
            case .video(let url):
                try await upload(
                    videoURL: url,
                    at: request.coordinate,
                    radiusMeters: request.radiusMeters,
                    caption: request.caption,
                    channelID: request.channelID,
                    requestID: request.requestID,
                    postID: request.postID,
                    audience: request.audience,
                    locationVisibility: request.locationVisibility,
                    usedAI: request.usedAI,
                    rightsAttestationVersion: request.rightsAttestationVersion,
                    photoViewSeconds: request.photoViewSeconds,
                    contentType: request.contentType,
                    messageCard: request.messageCard
                )
            }
            try Task.checkCancellation()
            Self.reportProgress(1, phase: "POSTED", requestID: request.requestID)
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
        // The discovery seed, never less. This defaulted to 0 because 5000
        // used to be a fabricated figure: a publish arriving with the contract
        // already drained invented 5 km of reach the account had not earned,
        // and since radiusDecay only considers posts with radius > 0, that
        // invented reach then GREW on engagement.
        //
        // The seed is not invented any more (user-ordered 6 Sep). Every drop
        // is born discoverable at 5 km, and every metre of it is declared as
        // seedRadiusMeters with organicRadiusMeters at 0 — spent reach that
        // never counts toward what the account may claim next, and that decay
        // never touches because decay shrinks the earned pool alone. Defaulting
        // to 0 was the worse failure of the two: a post at 0 m is intercepted
        // by nobody, so it cannot be seen, cannot be engaged with, and cannot
        // earn its way out of being invisible.
        //
        // A staged value BELOW the seed is floored for the same reason — a
        // shell running an older web bundle can still stage 2 km, and the
        // account holds the seed unconditionally either way. The React Native
        // shell already floors both cases this way (services/posts.ts); iOS
        // was the one publisher that still defaulted to nothing.
        return max(Self.postDiscoverySeedMeters, nextRadiusMeters ?? 0)
    }

    /// Set by WebPostPublisher from the one publishPost message, drained by the
    /// upload that follows. Never accumulates across posts: a failed decode must
    /// not leak this post's extra slides onto the next capture.
    var nextCarouselExtras: [Data] = []
    private func takeCarouselExtras() -> [Data] {
        let extras = nextCarouselExtras
        nextCarouselExtras = []
        return extras
    }

    private func takeCaption() -> String? {
        defer { nextCaption = nil }
        return nextCaption
    }

    private func takeChannelID() -> String? {
        defer { nextChannelID = nil }
        return nextChannelID
    }

    private func takeRequestID() -> String? {
        defer { nextRequestID = nil }
        return nextRequestID
    }

    /// nil when no post id was staged. A publish with no id is a publish that
    /// has already been consumed — minting a fresh one here is what turned a
    /// repeated dispatch into a SECOND post instead of an overwrite of the
    /// first, since both the document path and posts/<uid>/<postID>.jpg are
    /// keyed by this id.
    private func takePublishContract(requestID: String?) -> (
        postID: String,
        audience: String,
        locationVisibility: String,
        usedAI: Bool,
        rightsAttestationVersion: String?,
        photoViewSeconds: Int?,
        contentType: String,
        messageCard: Bool
    )? {
        defer {
            nextPostID = nil
            nextAudience = nil
            nextLocationVisibility = nil
            nextUsedAI = nil
            nextRightsAttestationVersion = nil
            nextPhotoViewSeconds = nil
            nextContentType = nil
            nextMessageCard = nil
        }
        let candidate = nextPostID ?? requestID
        guard let postID = Self.boundedPostID(candidate) else { return nil }
        return (
            postID,
            "public",
            nextLocationVisibility == "hidden" ? "hidden" : "approximate",
            nextUsedAI == true,
            nextRightsAttestationVersion,
            nextPhotoViewSeconds,
            nextContentType == "message" ? "message" : "post",
            nextContentType == "message" && nextMessageCard == true
        )
    }

    private static func boundedPostID(_ value: String?) -> String? {
        guard let value,
              value.hasPrefix("post-"),
              value.utf8.count >= 21,
              value.utf8.count <= 101,
              value.unicodeScalars.allSatisfy({ scalar in
                  (scalar.value >= 48 && scalar.value <= 57)
                      || (scalar.value >= 65 && scalar.value <= 90)
                      || (scalar.value >= 97 && scalar.value <= 122)
                      || scalar == "-"
              }) else { return nil }
        return value
    }

    /// The coordinate the flow set, else the device's last known fix. A post
    /// with no location at all is refused rather than filed at (0, 0).
    private func resolveCoordinate() -> CLLocationCoordinate2D? {
        if let pending = pendingCoordinate { return pending }
        return locationManager.location?.coordinate
    }

    // MARK: - Upload

    private func upload(
        image: UIImage,
        at coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        caption: String?,
        channelID: String?,
        requestID: String?,
        postID: String,
        audience: String,
        locationVisibility: String,
        usedAI: Bool,
        rightsAttestationVersion: String?,
        photoViewSeconds: Int?,
        contentType: String,
        messageCard: Bool,
        carouselExtras: [Data] = []
    ) async throws {
        guard let data = image.poplur4KJPEGData() else {
            throw NSError(
                domain: "PostUploadService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "That photo could not be prepared."]
            )
        }
        try Task.checkCancellation()
        Self.reportProgress(0.10, phase: "PREPARING", requestID: requestID)
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "PostUploadService",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Please sign in again before uploading."]
            )
        }
        let storagePath = "posts/\(uid)/\(postID).jpg"
        let reference = Storage.storage().reference().child(storagePath)
        try await uploadData(
            data,
            to: reference,
            metadata: Self.storageMetadata(contentType: "image/jpeg"),
            requestID: requestID,
            progressRange: 0.12...0.84
        )
        try Task.checkCancellation()
        Self.reportProgress(0.88, phase: "FINALIZING", requestID: requestID)
        let mediaURL = try await reference.downloadURL().absoluteString
        // Carousel slides after the cover. Sequential on purpose: the progress
        // reporter is a single 0...1 track, and a partial carousel is worse
        // than a slower one - if any slide fails the whole post fails and
        // nothing is written, rather than publishing a post missing slide 3.
        var mediaURLs: [String] = [mediaURL]
        for (offset, extra) in carouselExtras.enumerated() {
            try Task.checkCancellation()
            let index = offset + 1
            let extraPath = "posts/\(uid)/\(postID)-\(index).jpg"
            let extraReference = Storage.storage().reference().child(extraPath)
            try await uploadData(
                extra,
                to: extraReference,
                metadata: Self.storageMetadata(contentType: "image/jpeg"),
                requestID: requestID,
                progressRange: 0.88...0.92
            )
            mediaURLs.append(try await extraReference.downloadURL().absoluteString)
        }
        Self.reportProgress(0.94, phase: "SAVING POST", requestID: requestID)
        do {
            try await savePost(
                postID: postID,
                mediaURL: mediaURL,
                mediaURLs: mediaURLs,
                mediaStoragePath: storagePath,
                posterURL: nil,
                posterStoragePath: nil,
                mediaType: "photo",
                at: coordinate,
                radiusMeters: radiusMeters,
                caption: caption,
                channelID: channelID,
                audience: audience,
                locationVisibility: locationVisibility,
                usedAI: usedAI,
                rightsAttestationVersion: rightsAttestationVersion,
                photoViewSeconds: photoViewSeconds,
                contentType: contentType,
                messageCard: messageCard
            )
        } catch {
            // A timeout can lose the acknowledgement after a successful save.
            // Delete media only when the server confirms no post references it.
            if let saved = try? await Firestore.firestore().collection("posts")
                .document(postID).getDocument(source: .server), !saved.exists {
                try? await reference.delete()
            }
            throw error
        }
    }

    private func upload(
        videoURL: URL,
        at coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        caption: String?,
        channelID: String?,
        requestID: String?,
        postID: String,
        audience: String,
        locationVisibility: String,
        usedAI: Bool,
        rightsAttestationVersion: String?,
        photoViewSeconds: Int?,
        contentType: String,
        messageCard: Bool
    ) async throws {
        try Task.checkCancellation()
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "PostUploadService",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Please sign in again before uploading."]
            )
        }
        let storagePath = "posts/\(uid)/\(postID).mp4"
        let reference = Storage.storage().reference().child(storagePath)
        try await uploadFile(
            videoURL,
            to: reference,
            metadata: Self.storageMetadata(contentType: "video/mp4"),
            requestID: requestID,
            progressRange: 0.10...0.80
        )
        try Task.checkCancellation()
        Self.reportProgress(0.84, phase: "FINALIZING", requestID: requestID)
        let mediaURL = try await reference.downloadURL().absoluteString

        // A poster frame keeps the feed from showing a black tile before the
        // clip decodes, matching what the picker upload stores.
        var posterURL: String?
        var posterStoragePath: String?
        var posterReference: StorageReference?
        if let poster = Self.posterJPEG(for: videoURL) {
            Self.reportProgress(0.88, phase: "MAKING PREVIEW", requestID: requestID)
            let posterPath = "posts/\(uid)/\(postID)-poster.jpg"
            let posterRef = Storage.storage().reference().child(posterPath)
            _ = try? await posterRef.putDataAsync(
                poster,
                metadata: Self.storageMetadata(contentType: "image/jpeg")
            )
            posterURL = try? await posterRef.downloadURL().absoluteString
            if posterURL != nil {
                posterStoragePath = posterPath
                posterReference = posterRef
            }
        }

        try Task.checkCancellation()
        Self.reportProgress(0.94, phase: "SAVING POST", requestID: requestID)
        do {
            try await savePost(
                postID: postID,
                mediaURL: mediaURL,
                mediaStoragePath: storagePath,
                posterURL: posterURL,
                posterStoragePath: posterStoragePath,
                mediaType: "video",
                at: coordinate,
                radiusMeters: radiusMeters,
                caption: caption,
                channelID: channelID,
                audience: audience,
                locationVisibility: locationVisibility,
                usedAI: usedAI,
                rightsAttestationVersion: rightsAttestationVersion,
                photoViewSeconds: photoViewSeconds,
                contentType: contentType,
                messageCard: messageCard
            )
        } catch {
            if let saved = try? await Firestore.firestore().collection("posts")
                .document(postID).getDocument(source: .server), !saved.exists {
                try? await reference.delete()
                if let posterReference { try? await posterReference.delete() }
            }
            throw error
        }
    }

    /// Firebase exposes byte progress only on the callback upload tasks, not on
    /// `putDataAsync` / `putFileAsync`. Bridge those callbacks into async/await
    /// while forwarding the real `Progress.fractionCompleted` to the composer.
    private func uploadData(
        _ data: Data,
        to reference: StorageReference,
        metadata: StorageMetadata,
        requestID: String?,
        progressRange: ClosedRange<Double>
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            var task: StorageUploadTask?
            var progressHandle: String?
            task = reference.putData(data, metadata: metadata) { _, error in
                if let progressHandle { task?.removeObserver(withHandle: progressHandle) }
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
            progressHandle = task?.observe(.progress) { snapshot in
                guard let fraction = snapshot.progress?.fractionCompleted else { return }
                Self.reportProgress(
                    progressRange.lowerBound
                        + (progressRange.upperBound - progressRange.lowerBound) * fraction,
                    phase: "UPLOADING",
                    requestID: requestID
                )
            }
        }
    }

    private func uploadFile(
        _ fileURL: URL,
        to reference: StorageReference,
        metadata: StorageMetadata,
        requestID: String?,
        progressRange: ClosedRange<Double>
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            var task: StorageUploadTask?
            var progressHandle: String?
            task = reference.putFile(from: fileURL, metadata: metadata) { _, error in
                if let progressHandle { task?.removeObserver(withHandle: progressHandle) }
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
            progressHandle = task?.observe(.progress) { snapshot in
                guard let fraction = snapshot.progress?.fractionCompleted else { return }
                Self.reportProgress(
                    progressRange.lowerBound
                        + (progressRange.upperBound - progressRange.lowerBound) * fraction,
                    phase: "UPLOADING",
                    requestID: requestID
                )
            }
        }
    }

    /// Same document shape `MediaPickerView.savePostToFirestore` writes, so both
    /// paths produce identical posts.
    private func savePost(
        postID: String,
        mediaURL: String,
        mediaURLs: [String] = [],
        mediaStoragePath: String,
        posterURL: String?,
        posterStoragePath: String?,
        mediaType: String,
        at coordinate: CLLocationCoordinate2D,
        radiusMeters: Int,
        caption: String?,
        channelID: String?,
        audience: String,
        locationVisibility: String,
        usedAI: Bool,
        rightsAttestationVersion: String?,
        photoViewSeconds: Int?,
        contentType: String,
        messageCard: Bool
    ) async throws {
        var post: [String: Any] = [
            "mediaURL": mediaURL,
            "mediaType": mediaType,
            "contentType": contentType,
            "messageCard": contentType == "message" && messageCard,
            "radius": radiusMeters,
            // Every metre a post is BORN with is a seed — the discovery
            // default and any ground claimed on top of it from the account's
            // earned total — so it is spent reach, never earned. Declared
            // outright, with the earned pool at zero, because a post that
            // leaves either unsaid is read by the engagement functions as
            // radius earned from nowhere on its first like.
            "seedRadiusMeters": radiusMeters,
            "organicRadiusMeters": 0,
            "viewCount": 0,
            "audience": audience,
            "locationVisibility": locationVisibility,
            "mediaStoragePath": mediaStoragePath,
            "playbackURL": mediaURL,
            "processingStatus": "ready",
            "status": "published",
            "schemaVersion": 2,
            "createdAt": FieldValue.serverTimestamp(),
            "createdAtMillis": Int64(Date().timeIntervalSince1970 * 1000)
        ]
        // Only a real carousel writes these. mediaURL above stays the cover and
        // keeps its original storage path, so a client that knows nothing about
        // mediaURLs reads it and renders an ordinary single-photo post.
        if mediaURLs.count > 1 {
            post["mediaURLs"] = mediaURLs
            post["mediaCount"] = mediaURLs.count
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "PostUploadService",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Your sign-in expired before the post was saved."]
            )
        }
        post["userID"] = uid
        if mediaType == "photo", let seconds = photoViewSeconds, seconds > 0 {
            post["photoViewSeconds"] = min(60, seconds)
        }
        let accountSnapshot = try? await Firestore.firestore()
            .collection("users").document(uid).getDocument()
        let account = accountSnapshot?.data()
        let accountHidesOrigin = account?["privateAccount"] as? Bool == true
            || account?["ghostMode"] as? Bool == true
        let effectiveVisibility = accountHidesOrigin ? "hidden" : locationVisibility
        post["locationVisibility"] = effectiveVisibility
        if effectiveVisibility == "approximate" {
            let latitudeCell = Int((coordinate.latitude * 1_000).rounded())
            let longitudeCell = Int((coordinate.longitude * 1_000).rounded())
            post["latitude"] = Double(latitudeCell) / 1_000
            post["longitude"] = Double(longitudeCell) / 1_000
            post["latitudeCell"] = latitudeCell
            post["longitudeCell"] = longitudeCell
        }
        // The handle comes from the PROFILE, with the Auth display name only as a
        // fallback. Nothing on iOS ever calls createProfileChangeRequest, so
        // displayName is empty for anyone who signed up here — which meant every
        // post this app has ever written carried no username at all, and the map
        // showed them all under one anonymous placeholder. The username the
        // person actually chose has been sitting in users/{uid} the whole time.
        let authDisplayName = Auth.auth().currentUser?.displayName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let profileUsername = await UsernameCache.shared.username(for: uid)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let handle = [profileUsername, authDisplayName]
            .compactMap({ $0 })
            .first(where: { !$0.isEmpty }) {
            post["username"] = handle
        }
        if let posterURL, !posterURL.isEmpty { post["posterURL"] = posterURL }
        if let posterStoragePath, !posterStoragePath.isEmpty {
            post["posterStoragePath"] = posterStoragePath
        }
        if let caption, !caption.isEmpty { post["caption"] = caption }
        if let channelID, !channelID.isEmpty { post["channelId"] = channelID }
        Self.applyAIMetadata(usedAI, to: &post)
        if let rightsAttestationVersion, !rightsAttestationVersion.isEmpty {
            post["rightsAttestationVersion"] = rightsAttestationVersion
            post["rightsAttestedAtMillis"] = Int64(Date().timeIntervalSince1970 * 1000)
        }

        let database = Firestore.firestore()
        let postRef = database.collection("posts").document(postID)
        let accountRef = database.collection("users").document(uid)
        let admissionRef = database.collection("postAdmissions").document(uid)
        let proposedPost = post
        // Read the allowance inside the same transaction as publication: decay
        // can lower it while a draft is open, even after the picker was correct.
        try await database.runTransaction { transaction, errorPointer in
            do {
                let existing = try transaction.getDocument(postRef)
                if existing.exists {
                    guard existing.data()?["userID"] as? String == uid,
                          existing.data()?["mediaStoragePath"] as? String == mediaStoragePath else {
                        throw NSError(domain: "PostUploadService", code: 6,
                            userInfo: [NSLocalizedDescriptionKey: "This post ID is already in use. Please start a new post."])
                    }
                    // A lost acknowledgement is a successful retry, never an
                    // overwrite of a published post's server-owned engagement.
                    return nil
                }
                let freshAccount = try transaction.getDocument(accountRef).data() ?? [:]
                // Server rules require this slot and the post in ONE commit.
                // Read before any writes so concurrent publishes retry against
                // the winner's slot. An existing post returned above costs none.
                let admission = try transaction.getDocument(admissionRef).data()
                let syntheticActor = uid.hasPrefix("sim-") || uid.hasPrefix("synthetic-")
                let nextAdmission = syntheticActor ? nil : try Self.postAdmissionData(
                    previous: admission, account: freshAccount, postID: postID)
                // Match the already-deployed seed rule when refreshing a
                // draft. The profile's displayed total is not an allowance.
                let earned = max(0, (freshAccount["earnedClaimMeters"] as? NSNumber)?.intValue ?? 0)
                let committed = max(0, (freshAccount["committedClaimMeters"] as? NSNumber)?.intValue ?? 0)
                let allowed = min(6_371_000, max(0, earned - committed) + 5_000)
                let seed = min(max(0, radiusMeters), allowed)
                var finalPost = proposedPost
                finalPost["radius"] = seed
                finalPost["seedRadiusMeters"] = seed
                if freshAccount["privateAccount"] as? Bool == true || freshAccount["ghostMode"] as? Bool == true {
                    finalPost["locationVisibility"] = "hidden"
                    for key in ["latitude", "longitude", "latitudeCell", "longitudeCell"] { finalPost.removeValue(forKey: key) }
                }
                transaction.setData(finalPost, forDocument: postRef)
                if let nextAdmission { transaction.setData(nextAdmission, forDocument: admissionRef) }
                transaction.setData([
                    "latitude": coordinate.latitude,
                    "longitude": coordinate.longitude,
                    "createdAt": FieldValue.serverTimestamp(),
                    "source": "post-upload"
                ], forDocument: accountRef.collection("postLocations").document(postID), merge: true)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    /// The phone proposes the transition for friendly errors; Firestore rules
    /// independently enforce its exact count and server timestamps at commit.
    static func postAdmissionData(previous: [String: Any]?, account: [String: Any], postID: String) throws -> [String: Any] {
        let now = Date().timeIntervalSince1970 * 1_000
        let last = (previous?["lastPostAt"] as? Timestamp).map { $0.dateValue().timeIntervalSince1970 * 1_000 }
            ?? (account["lastPostAtMillis"] as? NSNumber)?.doubleValue ?? 0
        let start = (previous?["windowStartedAt"] as? Timestamp)
            ?? (account["postWindowStartMillis"] as? NSNumber).map {
                // Preserve exact milliseconds when migrating the legacy
                // counter; Double/Date rounding can lose a millisecond.
                let millis = max(0, $0.int64Value)
                return Timestamp(seconds: millis / 1_000, nanoseconds: Int32((millis % 1_000) * 1_000_000))
            }
        let count = max(0, ((previous ?? account)["postsInWindow"] as? NSNumber)?.intValue ?? 0)
        let active = start.map { $0.dateValue().timeIntervalSince1970 > 0 && now - $0.dateValue().timeIntervalSince1970 * 1_000 < 86_400_000 } ?? false
        if last > 0 && now - last < 60_000 {
            throw NSError(domain: "PostUploadService", code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Wait a minute between posts. Your draft is saved."])
        }
        if active && count >= 30 {
            throw NSError(domain: "PostUploadService", code: 8,
                userInfo: [NSLocalizedDescriptionKey: "You've reached 30 posts in this 24-hour window. Your draft is saved."])
        }
        return [
            "postId": postID,
            "lastPostAt": FieldValue.serverTimestamp(),
            "windowStartedAt": active ? start! as Any : FieldValue.serverTimestamp(),
            "postsInWindow": active ? count + 1 : 1
        ]
    }

    static func applyAIMetadata(_ usedAI: Bool, to post: inout [String: Any]) {
        if usedAI { post["usedAI"] = true }
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

    private static func storageMetadata(contentType: String) -> StorageMetadata {
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        if let uid = Auth.auth().currentUser?.uid {
            metadata.customMetadata = ["ownerUID": uid]
        }
        return metadata
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

    private static func reportProgress(
        _ fraction: Double,
        phase: String,
        requestID: String?
    ) {
        guard let requestID else { return }
        let bounded = min(1, max(0, fraction))
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: Notification.Name("PostUploadProgress"),
                object: nil,
                userInfo: [
                    "requestId": requestID,
                    "fraction": bounded,
                    "phase": phase
                ]
            )
        }
    }
}
