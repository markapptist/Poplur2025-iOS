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
    static func handle(_ body: [String: Any]) {
        guard let dataUrl = body["data"] as? String,
              let payload = decodeDataURL(dataUrl) else { return }
        let kind = body["kind"] as? String ?? "photo"

        // Radius and caption cannot ride on the image-only upload
        // notifications, so stage them for the upload that follows.
        if let radiusKm = body["radiusKm"] as? Double {
            PostUploadService.shared.nextRadiusMeters = Int(radiusKm * 1000)
        }
        PostUploadService.shared.nextCaption = body["caption"] as? String
        PostUploadService.shared.nextRequestID = body["requestId"] as? String

        var userInfo: [String: Any] = [:]
        if kind == "video" {
            // A recording has to become a file URL for the uploader.
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("poplur-post-\(UUID().uuidString).mp4")
            guard (try? payload.write(to: url)) != nil else { return }
            userInfo["videoURL"] = url
        } else {
            guard let image = UIImage(data: payload) else { return }
            userInfo["image"] = image
        }

        // A post bound to a map spot carries its coordinate; a plain channel
        // post uploads to wherever the user currently is.
        if let latitude = body["latitude"] as? Double,
           let longitude = body["longitude"] as? Double {
            userInfo["latitude"] = latitude
            userInfo["longitude"] = longitude
            NotificationCenter.default.post(
                name: Notification.Name("UploadPostToCoordinate"),
                object: nil,
                userInfo: userInfo
            )
        } else if let image = userInfo["image"] as? UIImage {
            NotificationCenter.default.post(
                name: Notification.Name("UploadImageToCurrentCoordinate"), object: image
            )
        } else if let videoURL = userInfo["videoURL"] as? URL {
            NotificationCenter.default.post(
                name: Notification.Name("UploadVideoToCurrentCoordinate"), object: videoURL
            )
        }
    }

    /// `data:<mime>;base64,<payload>` → raw bytes.
    private static func decodeDataURL(_ value: String) -> Data? {
        guard let comma = value.firstIndex(of: ","), value.hasPrefix("data:") else { return nil }
        let encoded = String(value[value.index(after: comma)...])
        return Data(base64Encoded: encoded, options: .ignoreUnknownCharacters)
    }
}
