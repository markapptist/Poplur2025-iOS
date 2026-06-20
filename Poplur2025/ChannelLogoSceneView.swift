import SwiftUI
import SceneKit
import UIKit

struct ChannelLogoSceneView: UIViewRepresentable {
    let channelId: String
    let name: String
    let emoji: String

    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.isJitteringEnabled = true
        scnView.allowsCameraControl = false
        scnView.autoenablesDefaultLighting = false

        let scene = SCNScene()
        scnView.scene = scene

        // Flat logo plane
        let plane = SCNPlane(width: 1.6, height: 1.6)
        let material = SCNMaterial()
        material.diffuse.contents = makeLogoTexture()
        material.isDoubleSided = true
        material.lightingModel = .constant
        plane.materials = [material]

        let planeNode = SCNNode(geometry: plane)
        planeNode.scale = SCNVector3(0.01, 0.01, 0.01)
        scene.rootNode.addChildNode(planeNode)

        // Pop-in spring: 0.01 → 1.15 → 0.93 → 1.05 → 1.0
        let popIn = SCNAction.sequence([
            SCNAction.scale(to: 1.15, duration: 0.20),
            SCNAction.scale(to: 0.93, duration: 0.12),
            SCNAction.scale(to: 1.05, duration: 0.07),
            SCNAction.scale(to: 1.00, duration: 0.05)
        ])

        // Subtle Y-axis rocking for the 3D sprite feel
        let rockRight = SCNAction.rotateBy(x: 0, y: 0.20, z: 0, duration: 2.0)
        rockRight.timingMode = .easeInEaseOut
        let rockLeft = SCNAction.rotateBy(x: 0, y: -0.20, z: 0, duration: 2.0)
        rockLeft.timingMode = .easeInEaseOut
        let rock = SCNAction.repeatForever(SCNAction.sequence([rockRight, rockLeft]))

        planeNode.runAction(popIn) {
            planeNode.runAction(rock)
        }

        // Camera
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0, 2.5)
        scene.rootNode.addChildNode(cameraNode)

        return scnView
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    // MARK: - Texture generation

    private func makeLogoTexture() -> UIImage {
        if let image = UIImage(named: channelAssetName()) {
            return image
        }

        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            guard let ctx = UIGraphicsGetCurrentContext() else { return }
            let rect = CGRect(origin: .zero, size: size)

            // Clip to rounded rect
            UIBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), cornerRadius: 60).addClip()

            // Gradient background
            let (topColor, botColor) = channelColors()
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [topColor.cgColor, botColor.cgColor] as CFArray,
                locations: [0.0, 1.0]
            ) {
                ctx.drawLinearGradient(gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: [])
            }

            // Subtle inner highlight (top-left shine)
            if let shine = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor.white.withAlphaComponent(0.18).cgColor,
                         UIColor.white.withAlphaComponent(0.00).cgColor] as CFArray,
                locations: [0.0, 1.0]
            ) {
                ctx.drawRadialGradient(shine,
                    startCenter: CGPoint(x: 80, y: 60),
                    startRadius: 0,
                    endCenter: CGPoint(x: 80, y: 60),
                    endRadius: 260,
                    options: [])
            }

            // Inner border ring
            let borderPath = UIBezierPath(roundedRect: rect.insetBy(dx: 8, dy: 8), cornerRadius: 54)
            UIColor.white.withAlphaComponent(0.18).setStroke()
            borderPath.lineWidth = 2.5
            borderPath.stroke()

            // Large emoji
            let emojiAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 148)
            ]
            let emojiStr = NSAttributedString(string: emoji, attributes: emojiAttrs)
            let emojiSz = emojiStr.size()
            emojiStr.draw(at: CGPoint(x: (size.width - emojiSz.width) / 2, y: 58))

            // Channel name
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.55)
            shadow.shadowOffset = CGSize(width: 0, height: 3)
            shadow.shadowBlurRadius = 5
            let nameFontSize: CGFloat = name.count > 7 ? 42 : 50
            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: nameFontSize, weight: .black),
                .foregroundColor: UIColor.white,
                .kern: 2.5,
                .shadow: shadow
            ]
            let nameStr = NSAttributedString(string: name.uppercased(), attributes: nameAttrs)
            let nameSz = nameStr.size()
            nameStr.draw(at: CGPoint(x: (size.width - nameSz.width) / 2, y: 262))

            // "POPLUR TV" bug at bottom
            let tvAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.60),
                .kern: 3.5
            ]
            let tvStr = NSAttributedString(string: "POPLUR TV", attributes: tvAttrs)
            let tvSz = tvStr.size()
            tvStr.draw(at: CGPoint(x: (size.width - tvSz.width) / 2, y: 354))
        }
    }

    private func channelAssetName() -> String {
        switch channelId {
        case "food":      return "poplur_channel_101_food"
        case "beauty":    return "poplur_channel_103_beauty"
        case "sports":    return "poplur_channel_104_sports"
        case "modelling": return "poplur_channel_105_modelling"
        case "fashion":   return "poplur_channel_106_fashion"
        case "music":     return "poplur_channel_107_music"
        case "tech":      return "poplur_channel_108_tech"
        case "news":      return "poplur_channel_109_news"
        case "french":    return "poplur_channel_110_french"
        case "spanish":   return "poplur_channel_111_spanish"
        default:          return "poplur_channel_101_food"
        }
    }

    private func channelColors() -> (UIColor, UIColor) {
        switch channelId {
        case "food":      return (.init(red: 1.00, green: 0.45, blue: 0.00, alpha: 1), .init(red: 0.72, green: 0.06, blue: 0.00, alpha: 1))
        case "fitness":   return (.init(red: 0.10, green: 0.82, blue: 0.22, alpha: 1), .init(red: 0.00, green: 0.46, blue: 0.08, alpha: 1))
        case "beauty":    return (.init(red: 1.00, green: 0.18, blue: 0.55, alpha: 1), .init(red: 0.62, green: 0.00, blue: 0.40, alpha: 1))
        case "sports":    return (.init(red: 0.12, green: 0.36, blue: 1.00, alpha: 1), .init(red: 0.00, green: 0.10, blue: 0.62, alpha: 1))
        case "modelling": return (.init(red: 1.00, green: 0.82, blue: 0.00, alpha: 1), .init(red: 0.72, green: 0.38, blue: 0.00, alpha: 1))
        case "fashion":   return (.init(red: 0.62, green: 0.10, blue: 0.96, alpha: 1), .init(red: 0.28, green: 0.00, blue: 0.60, alpha: 1))
        case "music":     return (.init(red: 0.00, green: 0.82, blue: 0.96, alpha: 1), .init(red: 0.00, green: 0.36, blue: 0.70, alpha: 1))
        case "tech":      return (.init(red: 0.16, green: 0.52, blue: 1.00, alpha: 1), .init(red: 0.00, green: 0.18, blue: 0.60, alpha: 1))
        case "news":      return (.init(red: 0.88, green: 0.10, blue: 0.10, alpha: 1), .init(red: 0.44, green: 0.00, blue: 0.00, alpha: 1))
        case "french":    return (.init(red: 0.06, green: 0.22, blue: 0.84, alpha: 1), .init(red: 0.72, green: 0.00, blue: 0.08, alpha: 1))
        case "spanish":   return (.init(red: 0.88, green: 0.66, blue: 0.00, alpha: 1), .init(red: 0.72, green: 0.00, blue: 0.08, alpha: 1))
        default:          return (.init(red: 0.28, green: 0.10, blue: 0.90, alpha: 1), .init(red: 0.10, green: 0.00, blue: 0.50, alpha: 1))
        }
    }
}
