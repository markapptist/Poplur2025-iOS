import UIKit

// Simple in-memory image cache with thread-safe access.
final class ImageCache {
    static let shared = ImageCache()

    private let lock = NSLock()
    private var images: [URL: UIImage] = [:]
    private let maxEntries = 300

    private init() {}

    func image(for url: URL) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return images[url]
    }

    func insert(_ image: UIImage, for url: URL) {
        lock.lock()
        images[url] = image
        // Simple size control: trim if too many entries
        if images.count > maxEntries {
            images.remove(at: images.startIndex)
        }
        lock.unlock()
    }

    func remove(for url: URL) {
        lock.lock(); defer { lock.unlock() }
        images.removeValue(forKey: url)
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        images.removeAll()
    }
}

// A small loader that prefers the cache, otherwise fetches and decodes.
actor CachedImageLoader {
    static let shared = CachedImageLoader()

    func load(_ url: URL) async -> UIImage? {
        if let cached = ImageCache.shared.image(for: url) {
            return cached
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            // Decode off-main by default; UIImage decoding is not strictly main-only.
            if let img = UIImage(data: data) {
                ImageCache.shared.insert(img, for: url)
                return img
            }
        } catch {
            print("Image load failed: \(error.localizedDescription)")
        }
        return nil
    }
}
