import Photos
import ImageIO
import UIKit
import WebKit

// MARK: - Web camera-roll provider (Phase 3.5 bridge)
//
// The web home's Camera Roll page shows the REAL device photo library: the web
// posts { type: "requestCameraRoll" } (its clay permission card's Allow), this
// requests the real OS photo permission, then pushes the most recent photo
// thumbnails into the page as data URIs via window.poplurCameraRoll([...]).
// A denial pushes { denied: true } so the web flips back to the live camera —
// mirroring the twin's own deny flow.
enum WebCameraRollProvider {
    private static let itemLimit = 24
    private static let thumbSide: CGFloat = 240
    private static let maximumSourcePixelSize = 4096

    static func push(into webView: WKWebView) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            fetchAndDeliver(into: webView)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { newStatus in
                DispatchQueue.main.async {
                    if newStatus == .authorized || newStatus == .limited {
                        fetchAndDeliver(into: webView)
                    } else {
                        deliverDenied(into: webView)
                    }
                }
            }
        default:
            deliverDenied(into: webView)
        }
    }

    /// Deliver only when Photos is already authorized. The startup clay primer
    /// uses this path so it never summons an Apple permission sheet.
    static func pushAuthorized(into webView: WKWebView) {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            deliverDenied(into: webView)
            return
        }
        fetchAndDeliver(into: webView)
    }

    private static func fetchAndDeliver(into webView: WKWebView) {
        DispatchQueue.global(qos: .userInitiated).async {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = itemLimit
            let assets = PHAsset.fetchAssets(with: .image, options: options)

            let imageOptions = PHImageRequestOptions()
            imageOptions.isSynchronous = true
            imageOptions.deliveryMode = .fastFormat
            imageOptions.resizeMode = .fast
            imageOptions.isNetworkAccessAllowed = false

            let manager = PHImageManager.default()
            let side = thumbSide * UIScreen.main.scale / 2
            var items: [[String: Any]] = []
            assets.enumerateObjects { asset, _, _ in
                manager.requestImage(
                    for: asset,
                    targetSize: CGSize(width: side, height: side),
                    contentMode: .aspectFill,
                    options: imageOptions
                ) { image, _ in
                    if let data = image?.jpegData(compressionQuality: 0.7) {
                        items.append([
                            "kind": "photo",
                            "src": "data:image/jpeg;base64,\(data.base64EncodedString())",
                            // The grid deliberately carries only a small thumbnail.
                            // Selection uses this stable identifier to request the
                            // source separately instead of stretching 240 px over
                            // the full-screen composer.
                            "assetId": asset.localIdentifier,
                        ])
                    }
                }
            }

            guard let json = try? JSONSerialization.data(withJSONObject: items),
                  let payload = String(data: json, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                webView.evaluateJavaScript("window.poplurCameraRoll && window.poplurCameraRoll(\(payload))")
            }
        }
    }

    /// Resolve one selected grid item at source quality. The longest edge is
    /// bounded to the caller's request and to 4096 pixels so a 48 MP library
    /// image cannot exhaust the WebView, while a smaller source is never enlarged.
    /// iCloud access is allowed here because this is an explicit user selection,
    /// not speculative thumbnail prefetching.
    static func pushAsset(
        requestId: String,
        assetId: String,
        maxPixelSize requestedMaxPixelSize: Int?,
        into webView: WKWebView
    ) {
        guard !requestId.isEmpty, requestId.count <= 128,
              !assetId.isEmpty, assetId.count <= 1024 else {
            deliverAssetError(
                requestId: requestId,
                assetId: assetId,
                message: "invalid_request",
                into: webView
            )
            return
        }

        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else {
            deliverAssetError(
                requestId: requestId,
                assetId: assetId,
                message: "photo_access_denied",
                into: webView
            )
            return
        }

        let results = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = results.firstObject else {
            deliverAssetError(
                requestId: requestId,
                assetId: assetId,
                message: "asset_not_found",
                into: webView
            )
            return
        }

        let requested = requestedMaxPixelSize ?? maximumSourcePixelSize
        let ceiling = min(max(requested, 1), maximumSourcePixelSize)
        let sourceLongestEdge = max(asset.pixelWidth, asset.pixelHeight)
        let targetLongestEdge = sourceLongestEdge > 0
            ? min(sourceLongestEdge, ceiling)
            : ceiling

        let options = PHImageRequestOptions()
        options.version = .current
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none
        options.isNetworkAccessAllowed = true

        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) {
            data, _, _, info in
            if (info?[PHImageCancelledKey] as? Bool) == true {
                deliverAssetError(
                    requestId: requestId,
                    assetId: assetId,
                    message: "request_cancelled",
                    into: webView
                )
                return
            }
            if let error = info?[PHImageErrorKey] as? Error {
                print("[WebCameraRollProvider] Source fetch failed: \(error)")
            }
            guard let data,
                  let rendered = sourceJPEG(from: data, maxPixelSize: targetLongestEdge) else {
                deliverAssetError(
                    requestId: requestId,
                    assetId: assetId,
                    message: "source_unavailable",
                    into: webView
                )
                return
            }

            let key = PoplurWebCaptureStore.registerCameraRollAsset(
                data: rendered.data,
                mimeType: "image/jpeg"
            )
            let source = "\(PoplurClayWebMap.scheme)://\(PoplurClayWebMap.host)/captures/\(key)"
            let payload: [String: Any] = [
                "requestId": requestId,
                "assetId": assetId,
                "kind": "photo",
                "src": source,
                "pixelWidth": rendered.width,
                "pixelHeight": rendered.height,
            ]
            deliverAssetPayload(payload, into: webView)
        }
    }

    /// ImageIO applies EXIF/HEIC orientation while decoding, so the returned JPEG
    /// is upright rather than relying on metadata that a canvas filter may drop.
    private static func sourceJPEG(
        from data: Data,
        maxPixelSize: Int
    ) -> (data: Data, width: Int, height: Int)? {
        guard maxPixelSize > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let jpeg = UIImage(cgImage: image, scale: 1, orientation: .up)
                .jpegData(compressionQuality: 0.95) else { return nil }
        return (jpeg, image.width, image.height)
    }

    private static func deliverAssetError(
        requestId: String,
        assetId: String,
        message: String,
        into webView: WKWebView
    ) {
        deliverAssetPayload(
            ["requestId": requestId, "assetId": assetId, "error": message],
            into: webView
        )
    }

    private static func deliverAssetPayload(_ payload: [String: Any], into webView: WKWebView) {
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let value = String(data: json, encoding: .utf8) else { return }
        DispatchQueue.main.async {
            webView.evaluateJavaScript(
                "window.poplurCameraRollAsset && window.poplurCameraRollAsset(\(value))"
            )
        }
    }

    private static func deliverDenied(into webView: WKWebView) {
        webView.evaluateJavaScript("window.poplurCameraRoll && window.poplurCameraRoll({denied:true})")
    }
}
