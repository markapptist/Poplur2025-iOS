import Foundation
import UIKit

/// Decode a `publishPost` bridge message from the web composer and hand it to
/// the native upload path.
///
/// WHY this is a shared helper and not a method on one coordinator: the exact
/// logic lived privately inside `PoplurClayMapView`'s coordinator — the OLD
/// native map host — and nowhere else. The camera composer runs in the web
/// HOME (`PostLoginHomeWebView`), whose message handler had no `publishPost`
/// case at all, so a post finished there went nowhere: no upload started, no
/// `PostUploadSuccess` ever fired, and the composer sat on "Uploading…" until
/// its 90s timeout. Same shape as the ML-detection and AR-filter gaps —
/// capability wired on the old native path and missed when Home became a
/// WebView. One shared implementation ends the game of which-webview-can-post.
enum WebPostPublisher {

    /// Stage and dispatch an upload described by the web composer's message.
    /// The web bundle has no account, so it sends the baked media as a
    /// data: URL; everything authenticated happens on this side.
    @MainActor
    static func handle(_ body: [String: Any]) {
        let requestID = body["requestId"] as? String

        /// Every failure in here must ANSWER the web composer.
        ///
        /// This used to `return` on each bad path without posting anything. The
        /// composer waits for `poplur-upload-result` and has no other way to
        /// learn what happened, so a post that failed to decode looked exactly
        /// like one still in flight: "Uploading…" frozen for the full 90s
        /// timeout, then a generic message, with the real reason visible only
        /// to whoever happened to be reading the device console. A silent
        /// failure path on the far side of a bridge is indistinguishable from a
        /// hang — so there are no bare returns below.
        func fail(_ message: String) {
            print("[WebPostPublisher] publishPost FAILED: \(message) requestId=\(requestID ?? "-")")
            var info: [String: Any] = ["message": message]
            if let requestID { info["requestId"] = requestID }
            NotificationCenter.default.post(
                name: Notification.Name("PostUploadFailed"), object: nil, userInfo: info
            )
        }

        guard body["rightsAttested"] as? Bool == true else {
            fail("Confirm that you have permission to share this media and music.")
            return
        }
        guard let postID = body["postId"] as? String,
              postID.hasPrefix("post-"),
              postID.utf8.count >= 21,
              postID.utf8.count <= 101,
              postID.unicodeScalars.allSatisfy({ scalar in
                  (scalar.value >= 48 && scalar.value <= 57)
                      || (scalar.value >= 65 && scalar.value <= 90)
                      || (scalar.value >= 97 && scalar.value <= 122)
                      || scalar == "-"
              }) else {
            fail("That post identity was invalid.")
            return
        }
        guard let mediaSource = body["data"] as? String else {
            fail("The capture never reached the app.")
            return
        }
        let inlinePayload = decodeDataURL(mediaSource)
        let storedCapture = inlinePayload == nil ? captureItem(from: mediaSource) : nil
        guard inlinePayload != nil || storedCapture != nil else {
            fail("That capture could not be decoded for upload.")
            return
        }
        let kind = body["kind"] as? String ?? "photo"
        let byteCount = inlinePayload?.count
            ?? storedCapture?.data?.count
            ?? storedCapture?.fileURL.flatMap(fileSize)
            ?? 0
        print("[WebPostPublisher] publishPost received: kind=\(kind) bytes=\(byteCount) requestId=\(body["requestId"] as? String ?? "-") coord=\(body["targetLatitude"] != nil)")

        var userInfo: [String: Any] = [:]
        if kind == "video" {
            guard storedCapture == nil
                    || storedCapture?.mimeType.lowercased().hasPrefix("video/") == true else {
                fail("That recording was not a video capture.")
                return
            }

            // A recording has to become a file URL for the uploader. Native
            // captures are already file-backed in PoplurWebCaptureStore; copy
            // that trusted source into an upload-owned staging file instead of
            // reading the whole clip into JavaScript/base64 and back into RAM.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("poplur-post-\(UUID().uuidString).mp4")
            PoplurTemporaryFileOwnership.claim(url)
            do {
                if let sourceURL = storedCapture?.fileURL {
                    try FileManager.default.copyItem(at: sourceURL, to: url)
                } else if let payload = inlinePayload ?? storedCapture?.data {
                    try payload.write(to: url, options: .atomic)
                } else {
                    throw CocoaError(.fileReadNoSuchFile)
                }
            } catch {
                PoplurTemporaryFileOwnership.deleteIfOwned(url)
                fail("The recording could not be staged for upload: \(error.localizedDescription)")
                return
            }
            userInfo["videoURL"] = url
            userInfo[PoplurTemporaryFileOwnership.notificationKey] = true
        } else {
            guard storedCapture == nil
                    || storedCapture?.mimeType.lowercased().hasPrefix("image/") == true else {
                fail("That photo was not an image capture.")
                return
            }
            let payload: Data?
            if let inlinePayload {
                payload = inlinePayload
            } else if let data = storedCapture?.data {
                payload = data
            } else if let sourceURL = storedCapture?.fileURL {
                payload = try? Data(contentsOf: sourceURL, options: .mappedIfSafe)
            } else {
                payload = nil
            }
            guard let payload else {
                fail("That photo could not be read for upload.")
                return
            }
            guard let image = UIImage(data: payload) else {
                fail("That photo could not be read for upload.")
                return
            }
            userInfo["image"] = image
        }

        // Radius and caption cannot ride on the image-only upload
        // notifications, so stage them only after the media is known-good and
        // immediately before the upload notification that consumes them. A
        // decode/staging failure must not leak this post's metadata into the
        // next capture.
        if let radiusKm = body["radiusKm"] as? Double {
            PostUploadService.shared.nextRadiusMeters = Int(radiusKm * 1000)
        }
        let photoSeconds = (body["photoViewSeconds"] as? NSNumber)?.doubleValue
        PostUploadService.shared.nextPhotoViewSeconds = photoSeconds.flatMap {
            $0.isFinite && $0 > 0 ? Int(min(60, max(1, $0.rounded()))) : nil
        }
        PostUploadService.shared.nextCaption = body["caption"] as? String
        PostUploadService.shared.nextChannelID = body["channelId"] as? String
        PostUploadService.shared.nextRequestID = body["requestId"] as? String
        PostUploadService.shared.nextPostID = postID
        PostUploadService.shared.nextAudience = body["audience"] as? String
        PostUploadService.shared.nextLocationVisibility = body["locationVisibility"] as? String
        PostUploadService.shared.nextUsedAI = body["usedAI"] as? Bool
        if body["rightsAttested"] as? Bool == true {
            PostUploadService.shared.nextRightsAttestationVersion =
                body["rightsAttestationVersion"] as? String
        }

        // A post bound to a map spot carries its coordinate; a plain channel
        // post uploads to wherever the user currently is.
        if let latitude = body["targetLatitude"] as? Double,
           let longitude = body["targetLongitude"] as? Double {
            userInfo["latitude"] = latitude
            userInfo["longitude"] = longitude
            print("[WebPostPublisher] dispatch → UploadPostToCoordinate")
            NotificationCenter.default.post(
                name: Notification.Name("UploadPostToCoordinate"),
                object: nil,
                userInfo: userInfo
            )
        } else if let image = userInfo["image"] as? UIImage {
            print("[WebPostPublisher] dispatch → UploadImageToCurrentCoordinate")
            NotificationCenter.default.post(
                name: Notification.Name("UploadImageToCurrentCoordinate"), object: image
            )
        } else if let videoURL = userInfo["videoURL"] as? URL {
            print("[WebPostPublisher] dispatch → UploadVideoToCurrentCoordinate")
            NotificationCenter.default.post(
                name: Notification.Name("UploadVideoToCurrentCoordinate"),
                object: videoURL,
                userInfo: [
                    PoplurTemporaryFileOwnership.notificationKey:
                        PoplurTemporaryFileOwnership.isOwned(videoURL)
                ]
            )
        } else {
            // Unreachable given the guards above, and it stays answered anyway:
            // the one thing this function must never do is end without either
            // dispatching an upload or reporting why it didn't.
            fail("The post had no media to upload.")
        }
    }

    /// `data:<mime>;base64,<payload>` → raw bytes.
    private static func decodeDataURL(_ value: String) -> Data? {
        guard let comma = value.firstIndex(of: ","), value.hasPrefix("data:") else { return nil }
        let encoded = String(value[value.index(after: comma)...])
        return Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
    }

    /// Resolve only capture URLs minted by this app's own WebKit scheme. The
    /// composer uses these URLs for native camera and Camera Roll media so the
    /// preview can stay file/data-backed without allocating a second base64
    /// copy. Arbitrary file/network URLs are deliberately rejected here.
    private static func captureItem(from value: String) -> PoplurWebCaptureStore.Item? {
        guard let url = URL(string: value),
              url.scheme == PoplurClayWebMap.scheme,
              url.host == PoplurClayWebMap.host,
              url.query == nil,
              url.fragment == nil,
              url.path.hasPrefix("/captures/") else { return nil }
        let key = String(url.path.dropFirst("/captures/".count))
        guard !key.isEmpty, !key.contains("/") else { return nil }
        return PoplurWebCaptureStore.item(for: key)
    }

    private static func fileSize(_ url: URL) -> Int? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize
    }
}
