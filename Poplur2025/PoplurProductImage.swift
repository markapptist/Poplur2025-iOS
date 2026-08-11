import Foundation
import UIKit
import WebKit

/// Fetches an advertiser's own hero image for a product page and hands it to
/// the web layer as a data URI.
///
/// WHY THIS IS NATIVE. The commerce card lives in a WKWebView serving a custom
/// scheme, so a cross-origin fetch of `apple.com` is blocked by CORS, and any
/// API key shipped inside that bundle is public the moment it ships. The shell
/// is the only side that can make this request.
///
/// WHY og:image AND NOT AN IMAGE SEARCH. A search returns arbitrary
/// third-party photographs. Putting one inside a card reading "Shop drinkware ·
/// SHOP NOW" makes it ADVERTISING CREATIVE, which we hold no licence to do. The
/// `og:image` an advertiser publishes is the picture they intend to be used
/// exactly this way, so the rights arrive with it.
enum PoplurProductImage {

    /// Answered requests, so a repeat detection costs nothing. The web side
    /// caches too; this covers the same page being asked for by several cards
    /// before any of them has stored an answer.
    private static var inFlight: Set<String> = []

    /// Refuse anything that is not a plain https product page. The URL comes
    /// from our own offer table today, but this is the boundary where a fetch
    /// actually happens — it should not widen just because a caller changes.
    private static func permitted(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard let host = url.host?.lowercased(), host.contains(".") else { return false }
        return true
    }

    static func handle(urlString: String, webView: WKWebView) {
        guard let url = URL(string: urlString), permitted(url) else {
            deliver(urlString: urlString, dataURI: nil, webView: webView)
            return
        }
        if let hit: NSString = PoplurAssetCache.shared.asset(
            forKey: "ProductImage:\(urlString)",
            category: .webAsset
        ) {
            deliver(urlString: urlString, dataURI: hit as String, webView: webView)
            return
        }
        guard !inFlight.contains(urlString) else { return }
        inFlight.insert(urlString)

        Task.detached(priority: .utility) {
            let found = await resolve(url)
            await MainActor.run {
                inFlight.remove(urlString)
                if let found {
                    _ = PoplurAssetCache.shared.insert(
                        found as NSString,
                        forKey: "ProductImage:\(urlString)",
                        category: .webAsset,
                        estimatedByteCost: max(1, found.utf8.count)
                    )
                }
                deliver(urlString: urlString, dataURI: found, webView: webView)
            }
        }
    }

    private static func resolve(_ page: URL) async -> String? {
        // 1. the page, capped — a product page's <head> is in the first bytes,
        //    and some of these are multi-megabyte documents.
        var request = URLRequest(url: page, timeoutInterval: 8)
        request.setValue("Poplur/1.0", forHTTPHeaderField: "User-Agent")
        guard let (html, _) = try? await URLSession.shared.data(for: request),
              let text = String(data: html.prefix(400_000), encoding: .utf8),
              let imageURL = ogImage(in: text, relativeTo: page)
        else { return nil }

        // 2. the image itself, downscaled. The card is a few hundred points
        //    wide; shipping a 3000px hero across the bridge as base64 would be
        //    megabytes of main-thread string for no visible gain.
        var imageRequest = URLRequest(url: imageURL, timeoutInterval: 8)
        imageRequest.setValue("Poplur/1.0", forHTTPHeaderField: "User-Agent")
        guard let (bytes, _) = try? await URLSession.shared.data(for: imageRequest),
              let source = UIImage(data: bytes),
              let shrunk = downscaled(source, maxEdge: 720),
              let jpeg = shrunk.jpegData(compressionQuality: 0.82)
        else { return nil }

        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }

    /// `og:image` first, then Twitter's equivalent. Deliberately a regex over
    /// the head rather than a full HTML parse: this reads one attribute, and
    /// pulling a parser in for that is more surface than the job needs. Two
    /// patterns because `content` legally sits on either side of `property`.
    private static func ogImage(in html: String, relativeTo page: URL) -> URL? {
        let names = "og:image:secure_url|og:image|twitter:image"
        let patterns = [
            "(?:property|name)=[\"'](?:\(names))[\"'][^>]*?content=[\"']([^\"']+)[\"']",
            "content=[\"']([^\"']+)[\"'][^>]*?(?:property|name)=[\"'](?:\(names))[\"']"
        ]
        let span = NSRange(html.startIndex..<html.endIndex, in: html)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: html, options: [], range: span),
                  match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: html)
            else { continue }

            let value = String(html[captured]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { continue }
            if let absolute = URL(string: value, relativeTo: page)?.absoluteURL,
               absolute.scheme?.lowercased() == "https" {
                return absolute
            }
        }
        return nil
    }

    private static func downscaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage? {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else { return image }
        let scale = maxEdge / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// Always answers, even on failure — the web side holds the card on its
    /// bundled poster until it hears back, so silence would leave it waiting.
    private static func deliver(urlString: String, dataURI: String?, webView: WKWebView) {
        let payload: [String: Any] = [
            "url": urlString,
            "image": dataURI as Any
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: json, encoding: .utf8) else { return }
        webView.evaluateJavaScript(
            "window.poplurProductImage && window.poplurProductImage(\(text)); true;"
        )
    }
}
