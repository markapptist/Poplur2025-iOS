import UIKit

extension UIImage {
    /// Keeps uploads at source resolution up to a 4096 px edge, normalizes
    /// orientation, and avoids the low-quality 1600 px/0.75 JPEG path that made
    /// camera-roll images look soft after posting.
    func poplur4KJPEGData(
        maxPixelDimension: CGFloat = 4_096,
        compressionQuality: CGFloat = 0.95
    ) -> Data? {
        // UIImage.size already reflects orientation. Raw CGImage dimensions do
        // not, and using them would squeeze portrait assets captured with a
        // left/right EXIF orientation into landscape proportions.
        let sourceWidth = size.width * scale
        let sourceHeight = size.height * scale
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let resizeScale = min(1, maxPixelDimension / max(sourceWidth, sourceHeight))
        let targetSize = CGSize(
            width: max(1, (sourceWidth * resizeScale).rounded()),
            height: max(1, (sourceHeight * resizeScale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: compressionQuality)
    }
}
