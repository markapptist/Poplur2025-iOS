import Photos
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
            var uris: [String] = []
            assets.enumerateObjects { asset, _, _ in
                manager.requestImage(
                    for: asset,
                    targetSize: CGSize(width: side, height: side),
                    contentMode: .aspectFill,
                    options: imageOptions
                ) { image, _ in
                    if let data = image?.jpegData(compressionQuality: 0.7) {
                        uris.append("data:image/jpeg;base64,\(data.base64EncodedString())")
                    }
                }
            }

            let items = uris.map { ["kind": "photo", "src": $0] }
            guard let json = try? JSONSerialization.data(withJSONObject: items),
                  let payload = String(data: json, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                webView.evaluateJavaScript("window.poplurCameraRoll && window.poplurCameraRoll(\(payload))")
            }
        }
    }

    private static func deliverDenied(into webView: WKWebView) {
        webView.evaluateJavaScript("window.poplurCameraRoll && window.poplurCameraRoll({denied:true})")
    }
}
