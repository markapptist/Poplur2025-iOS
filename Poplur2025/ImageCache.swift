import UIKit
import ImageIO

// Byte- and count-bounded decoded-image cache.
final class ImageCache {
    static let shared = ImageCache()

    private init() {}

    func image(for url: URL, maximumPixelDimension: Int) -> UIImage? {
        PoplurAssetCache.shared.asset(
            forKey: cacheKey(for: url, maximumPixelDimension: maximumPixelDimension),
            category: .decodedImage,
            as: UIImage.self
        )
    }

    func insert(_ image: UIImage, for url: URL, maximumPixelDimension: Int) {
        _ = PoplurAssetCache.shared.insert(
            image,
            forKey: cacheKey(for: url, maximumPixelDimension: maximumPixelDimension),
            category: .decodedImage,
            estimatedByteCost: Self.estimatedDecodedBytes(for: image)
        )
    }

    func remove(for url: URL) {
        PoplurAssetCache.shared.removeAll(category: .decodedImage) {
            $0.hasPrefix("ImageCache:\(url.absoluteString):")
        }
    }

    func clear() {
        PoplurAssetCache.shared.removeAll(category: .decodedImage) { $0.hasPrefix("ImageCache:") }
    }

    private func cacheKey(for url: URL, maximumPixelDimension: Int) -> String {
        "ImageCache:\(url.absoluteString):max=\(maximumPixelDimension)"
    }

    private static func estimatedDecodedBytes(for image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return max(1, cgImage.bytesPerRow * cgImage.height)
        }
        let width = max(1, Int((image.size.width * image.scale).rounded(.up)))
        let height = max(1, Int((image.size.height * image.scale).rounded(.up)))
        return width * height * 4
    }
}

// A small loader that prefers the cache, otherwise fetches and decodes.
actor CachedImageLoader {
    static let shared = CachedImageLoader()

    func load(_ url: URL) async -> UIImage? {
        let maximumPixels = await MainActor.run {
            PoplurPerformanceManager.shared.maximumPreferredTextureResolution
        }
        if let cached = ImageCache.shared.image(for: url, maximumPixelDimension: maximumPixels) {
            return cached
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let img = Self.downsampledImage(data: data, maximumPixelDimension: maximumPixels) {
                ImageCache.shared.insert(img, for: url, maximumPixelDimension: maximumPixels)
                return img
            }
        } catch {
            print("Image load failed: \(error.localizedDescription)")
        }
        return nil
    }

    private static func downsampledImage(data: Data, maximumPixelDimension: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(256, maximumPixelDimension),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

/// Bounds the retained and GPU-uploaded size of image-catalog textures. Asset
/// catalogs do not expose a file URL for ImageIO thumbnail decoding, so this
/// path resamples immediately after catalog lookup. Runtime/network images use
/// the ImageIO path above and avoid decoding the full source in the first place.
@MainActor
enum PoplurTextureLoader {
    static func image(named name: String, maximumPixelDimension: Int? = nil) -> UIImage? {
        let maximumPixels = max(
            256,
            maximumPixelDimension ?? PoplurPerformanceManager.shared.maximumPreferredTextureResolution
        )
        let cacheKey = "CatalogTexture:\(name):max=\(maximumPixels)"
        if let cached: UIImage = PoplurAssetCache.shared.asset(
            forKey: cacheKey,
            category: .texture
        ) {
            return cached
        }
        guard let source = UIImage(named: name) else { return nil }
        let sourceWidth = max(1, Int((source.size.width * source.scale).rounded(.up)))
        let sourceHeight = max(1, Int((source.size.height * source.scale).rounded(.up)))
        let sourceMaximum = max(sourceWidth, sourceHeight)

        let result: UIImage
        if sourceMaximum <= maximumPixels {
            result = source
        } else {
            let ratio = CGFloat(maximumPixels) / CGFloat(sourceMaximum)
            let targetSize = CGSize(
                width: max(1, (CGFloat(sourceWidth) * ratio).rounded()),
                height: max(1, (CGFloat(sourceHeight) * ratio).rounded())
            )
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = false
            result = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
                source.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        }

        _ = PoplurAssetCache.shared.insert(
            result,
            forKey: cacheKey,
            category: .texture,
            estimatedByteCost: Self.estimatedDecodedBytes(for: result)
        )
        return result
    }

    private static func estimatedDecodedBytes(for image: UIImage) -> Int {
        if let cgImage = image.cgImage {
            return max(1, cgImage.bytesPerRow * cgImage.height)
        }
        let width = max(1, Int((image.size.width * image.scale).rounded(.up)))
        let height = max(1, Int((image.size.height * image.scale).rounded(.up)))
        return width * height * 4
    }
}
