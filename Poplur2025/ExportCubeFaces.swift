#if CUBE_FACE_EXPORT
import Foundation
#if canImport(UIKit)
import UIKit
typealias PLColor = UIColor
typealias PLImage = UIImage
typealias PLBezierPath = UIBezierPath
typealias PLFont = UIFont
#elseif canImport(AppKit)
import AppKit
typealias PLColor = NSColor
typealias PLImage = NSImage
typealias PLBezierPath = NSBezierPath
typealias PLFont = NSFont
#endif

// This script generates all cube face images and saves them to the current directory
// Run with: swift ExportCubeFaces.swift
// macOS: swift -D CUBE_FACE_EXPORT ExportCubeFaces.swift
// iOS SDK: xcrun --sdk iphonesimulator swift -D CUBE_FACE_EXPORT ExportCubeFaces.swift

enum ExportTab: String {
    case map = "Map"
    case record = "Record"
    case feed = "Feed"
    case profile = "Profile"
    
    var title: String { rawValue }
    
    var systemImage: String {
        switch self {
        case .map: return "map.fill"
        case .record: return "video.fill"
        case .feed: return "play.rectangle.fill"
        case .profile: return "person.fill"
        }
    }
}

func generateFaceImage(for tab: ExportTab, baseColor: PLColor) -> PLImage {
    let size = CGSize(width: 1024, height: 1024)
#if canImport(UIKit)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
        let rect = CGRect(origin: .zero, size: size)
        PLColor(white: 0.95, alpha: 1).setFill()
        PLBezierPath(roundedRect: rect.insetBy(dx: 27, dy: 27), cornerRadius: 82).fill()

        let symbolName = tab.systemImage
        let pointSize: CGFloat = 273
        let iconWidth: CGFloat = 307
        let iconHeight: CGFloat = 307
        let iconY: CGFloat = 239
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        let imgRect = CGRect(x: (size.width - iconWidth) / 2, y: iconY, width: iconWidth, height: iconHeight)

        let glowConfig = UIImage.SymbolConfiguration(pointSize: pointSize + 34, weight: .bold)
        let glowImage = UIImage(systemName: symbolName, withConfiguration: glowConfig) ?? UIImage()
        let glowRect = imgRect.insetBy(dx: -20, dy: -20)
        PLColor.white.withAlphaComponent(0.25).setFill()
        glowImage.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: glowRect, blendMode: .normal, alpha: 0.25)

        let image = UIImage(systemName: symbolName, withConfiguration: config) ?? UIImage()
        image.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: imgRect)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: PLFont.systemFont(ofSize: 82, weight: .heavy),
            .foregroundColor: PLColor.white,
            .paragraphStyle: paragraph
        ]
        let title = tab.title as NSString
        let titleRect = CGRect(x: 0, y: 614, width: size.width, height: 137)
        let outlineAttrs: [NSAttributedString.Key: Any] = [
            .font: PLFont.systemFont(ofSize: 82, weight: .heavy),
            .foregroundColor: PLColor.white.withAlphaComponent(0.35),
            .strokeColor: PLColor.white.withAlphaComponent(0.35),
            .strokeWidth: -3,
            .paragraphStyle: paragraph
        ]
        title.draw(in: titleRect.offsetBy(dx: 1.7, dy: 1.7), withAttributes: outlineAttrs)
        title.draw(in: titleRect, withAttributes: attrs)
    }
#elseif canImport(AppKit)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = CGRect(origin: .zero, size: size)
    PLColor(white: 0.95, alpha: 1).setFill()
    PLBezierPath(roundedRect: rect.insetBy(dx: 27, dy: 27), xRadius: 82, yRadius: 82).fill()

    let symbolName = tab.systemImage
    let pointSize: CGFloat = 273
    let iconWidth: CGFloat = 307
    let iconHeight: CGFloat = 307
    let iconY: CGFloat = 239
    let imgRect = CGRect(x: (size.width - iconWidth) / 2, y: iconY, width: iconWidth, height: iconHeight)

    if let glow = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
        let glowRect = imgRect.insetBy(dx: -20, dy: -20)
        let tinted = glow.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize + 34, weight: .bold))
        PLColor.white.withAlphaComponent(0.25).set()
        tinted.draw(in: glowRect, from: .zero, operation: .sourceOver, fraction: 0.25)
    }
    if let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
        let tinted = icon.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold))
        PLColor.white.set()
        tinted.draw(in: imgRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: PLFont.systemFont(ofSize: 82, weight: .heavy),
        .foregroundColor: PLColor.white,
        .paragraphStyle: paragraph
    ]
    let title = tab.title as NSString
    let titleRect = CGRect(x: 0, y: 614, width: size.width, height: 137)
    let outlineAttrs: [NSAttributedString.Key: Any] = [
        .font: PLFont.systemFont(ofSize: 82, weight: .heavy),
        .foregroundColor: PLColor.white.withAlphaComponent(0.35),
        .strokeColor: PLColor.white.withAlphaComponent(0.35),
        .strokeWidth: -3,
        .paragraphStyle: paragraph
    ]
    title.draw(in: titleRect.offsetBy(dx: 1.7, dy: 1.7), withAttributes: outlineAttrs)
    title.draw(in: titleRect, withAttributes: attrs)

    return image
#else
    fatalError("Unsupported platform")
#endif
}

func generateEmissionMask(for tab: ExportTab) -> PLImage {
    let size = CGSize(width: 1024, height: 1024)
#if canImport(UIKit)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
        PLColor.clear.setFill()
        UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

        let symbolName = tab.systemImage
        let pointSize: CGFloat = 273
        let iconWidth: CGFloat = 307
        let iconHeight: CGFloat = 307
        let iconY: CGFloat = 239
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .bold)
        let imgRect = CGRect(x: (size.width - iconWidth) / 2, y: iconY, width: iconWidth, height: iconHeight)

        let glowConfig = UIImage.SymbolConfiguration(pointSize: pointSize + 34, weight: .bold)
        let glowImage = UIImage(systemName: symbolName, withConfiguration: glowConfig) ?? UIImage()
        let glowRect = imgRect.insetBy(dx: -20, dy: -20)
        glowImage.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: glowRect, blendMode: .normal, alpha: 0.55)

        let image = UIImage(systemName: symbolName, withConfiguration: config) ?? UIImage()
        image.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: imgRect)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let title = tab.title as NSString
        let titleRect = CGRect(x: 0, y: 614, width: size.width, height: 137)
        let boldAttrs: [NSAttributedString.Key: Any] = [
            .font: PLFont.systemFont(ofSize: 89, weight: .black),
            .foregroundColor: PLColor.white,
            .paragraphStyle: paragraph
        ]
        title.draw(in: titleRect, withAttributes: boldAttrs)
        let regularAttrs: [NSAttributedString.Key: Any] = [
            .font: PLFont.systemFont(ofSize: 82, weight: .heavy),
            .foregroundColor: PLColor.white,
            .paragraphStyle: paragraph
        ]
        title.draw(in: titleRect, withAttributes: regularAttrs)
    }
#elseif canImport(AppKit)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    PLColor.clear.set()
    NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

    let symbolName = tab.systemImage
    let pointSize: CGFloat = 273
    let iconWidth: CGFloat = 307
    let iconHeight: CGFloat = 307
    let iconY: CGFloat = 239
    let imgRect = CGRect(x: (size.width - iconWidth) / 2, y: iconY, width: iconWidth, height: iconHeight)

    if let glow = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
        let glowRect = imgRect.insetBy(dx: -20, dy: -20)
        let tinted = glow.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize + 34, weight: .bold))
        tinted.draw(in: glowRect, from: .zero, operation: .sourceOver, fraction: 0.55)
    }
    if let icon = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
        let tinted = icon.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .bold))
        tinted.draw(in: imgRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let title = tab.title as NSString
    let titleRect = CGRect(x: 0, y: 614, width: size.width, height: 137)
    let boldAttrs: [NSAttributedString.Key: Any] = [
        .font: PLFont.systemFont(ofSize: 89, weight: .black),
        .foregroundColor: PLColor.white,
        .paragraphStyle: paragraph
    ]
    title.draw(in: titleRect, withAttributes: boldAttrs)
    let regularAttrs: [NSAttributedString.Key: Any] = [
        .font: PLFont.systemFont(ofSize: 82, weight: .heavy),
        .foregroundColor: PLColor.white,
        .paragraphStyle: paragraph
    ]
    title.draw(in: titleRect, withAttributes: regularAttrs)

    return image
#else
    fatalError("Unsupported platform")
#endif
}

func generateBackgroundOnly(for tab: ExportTab, baseColor: PLColor) -> PLImage {
    let size = CGSize(width: 1024, height: 1024)
#if canImport(UIKit)
    let renderer = UIGraphicsImageRenderer(size: size)
    return renderer.image { _ in
        baseColor.setFill()
        let rect = CGRect(origin: .zero, size: size)
        PLBezierPath(roundedRect: rect.insetBy(dx: 27, dy: 27), cornerRadius: 82).fill()
    }
#elseif canImport(AppKit)
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    baseColor.set()
    let rect = CGRect(origin: .zero, size: size)
    PLBezierPath(roundedRect: rect.insetBy(dx: 27, dy: 27), xRadius: 82, yRadius: 82).fill()
    return image
#else
    fatalError("Unsupported platform")
#endif
}

@main
struct ExportCubeFaces {
    static func main() {
        let tabs: [ExportTab] = [.map, .record, .feed, .profile]
        let baseColor = PLColor(white: 0.2, alpha: 1.0)
        let currentDir = FileManager.default.currentDirectoryPath

        print("📦 Exporting cube faces to: \(currentDir)")

        for tab in tabs {
            let faceImage = generateFaceImage(for: tab, baseColor: baseColor)
            let emissionImage = generateEmissionMask(for: tab)
            let backgroundImage = generateBackgroundOnly(for: tab, baseColor: baseColor)

            if let faceData = faceImage.pngData() {
                let faceURL = URL(fileURLWithPath: "\(currentDir)/cube_face_\(tab.title).png")
                try? faceData.write(to: faceURL)
                print("✅ Exported: cube_face_\(tab.title).png")
            }

            if let emissionData = emissionImage.pngData() {
                let emissionURL = URL(fileURLWithPath: "\(currentDir)/cube_emission_\(tab.title).png")
                try? emissionData.write(to: emissionURL)
                print("✅ Exported: cube_emission_\(tab.title).png")
            }

            if let bgData = backgroundImage.pngData() {
                let bgURL = URL(fileURLWithPath: "\(currentDir)/cube_background_\(tab.title).png")
                try? bgData.write(to: bgURL)
                print("✅ Exported: cube_background_\(tab.title).png")
            }
        }

        print("🎉 All 12 images exported successfully!")
    }
}

#endif
