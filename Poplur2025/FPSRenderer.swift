import Foundation
import CoreGraphics
import UIKit

// MARK: - PoplurFPS software renderer
//
// Port of the canvas raycaster (PoplurFPS/src/render). A persistent
// CGBitmapContext backs a top-down ARGB buffer (0xAARRGGBB). The context's CTM is
// flipped so drawing uses top-left / y-down coordinates exactly like the old
// canvas — the raycast scene is written raw to the buffer for speed, then weapon
// / HUD / menu overlays are drawn with UIKit into the same buffer. snapshot()
// vends a CGImage the SpriteKit scene turns into an SKTexture each frame.

final class FPSRenderer {
    let w: Int
    let h: Int
    private let buffer: UnsafeMutablePointer<UInt32>
    let ctx: CGContext           // flipped (top-left) bitmap context; used by HUD/menu extensions
    private var zBuffer: [Double]

    init(w: Int = FPSK.screenW, h: Int = FPSK.screenH) {
        self.w = w
        self.h = h
        buffer = UnsafeMutablePointer<UInt32>.allocate(capacity: w * h)
        buffer.initialize(repeating: 0xFF000000, count: w * h)
        zBuffer = [Double](repeating: 0, count: w)

        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ctx = CGContext(data: buffer, width: w, height: h, bitsPerComponent: 8,
                        bytesPerRow: w * 4, space: cs, bitmapInfo: info)!
        // Flip to top-left / y-down (UIKit / canvas-style)
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .none
    }

    deinit { buffer.deallocate() }

    @inline(__always) private static func pack(_ r: Int, _ g: Int, _ b: Int) -> UInt32 {
        0xFF000000 | (UInt32(r & 0xFF) << 16) | (UInt32(g & 0xFF) << 8) | UInt32(b & 0xFF)
    }

    func snapshot() -> CGImage? { ctx.makeImage() }

    // MARK: Scene (raw pixel writes)

    func renderScene(_ player: FPSPlayer, _ level: FPSLevel, _ assets: FPSAssets, _ sprites: [RenderSprite]) {
        drawFloorCeiling()
        drawWalls(player, level, assets)
        drawSprites(player, sprites)
    }

    private func drawFloorCeiling() {
        let half = h / 2
        // Ceiling: #120020 -> #2a0045 (top -> middle)
        for y in 0..<half {
            let t = Double(y) / Double(half)
            let r = Int(0x12 + (0x2a - 0x12) * t)
            let g = Int(0x00 + (0x00 - 0x00) * t)
            let b = Int(0x20 + (0x45 - 0x20) * t)
            let c = FPSRenderer.pack(r, g, b)
            let row = buffer + y * w
            for x in 0..<w { row[x] = c }
        }
        // Floor: #0d0018 -> #050008 (middle -> bottom)
        for y in half..<h {
            let t = Double(y - half) / Double(h - half)
            let r = Int(0x0d + (0x05 - 0x0d) * t)
            let g = Int(0x00 + (0x00 - 0x00) * t)
            let b = Int(0x18 + (0x08 - 0x18) * t)
            let c = FPSRenderer.pack(r, g, b)
            let row = buffer + y * w
            for x in 0..<w { row[x] = c }
        }
    }

    private func drawWalls(_ player: FPSPlayer, _ level: FPSLevel, _ assets: FPSAssets) {
        let posX = player.x, posY = player.y
        let dirX = player.dirX, dirY = player.dirY
        let planeX = player.planeX, planeY = player.planeY
        let H = Double(h), W = Double(w)

        for x in 0..<w {
            let cameraX = 2 * Double(x) / W - 1
            let rayDirX = dirX + planeX * cameraX
            let rayDirY = dirY + planeY * cameraX

            var mapX = Int(floor(posX)), mapY = Int(floor(posY))
            let deltaDistX = rayDirX == 0 ? 1e30 : abs(1 / rayDirX)
            let deltaDistY = rayDirY == 0 ? 1e30 : abs(1 / rayDirY)

            var stepX = 0, stepY = 0
            var sideDistX = 0.0, sideDistY = 0.0
            if rayDirX < 0 { stepX = -1; sideDistX = (posX - Double(mapX)) * deltaDistX }
            else            { stepX = 1;  sideDistX = (Double(mapX) + 1 - posX) * deltaDistX }
            if rayDirY < 0 { stepY = -1; sideDistY = (posY - Double(mapY)) * deltaDistY }
            else            { stepY = 1;  sideDistY = (Double(mapY) + 1 - posY) * deltaDistY }

            var hit = false, side = 0
            var perpWallDist = 0.0
            var wallType = 0
            var wallX = 0.0
            var isDoor = false
            var doorOpenAmt = 0.0

            while !hit {
                if sideDistX < sideDistY { sideDistX += deltaDistX; mapX += stepX; side = 0 }
                else                     { sideDistY += deltaDistY; mapY += stepY; side = 1 }

                let tile = level.getCell(Double(mapX), Double(mapY))
                if tile == 0 { continue }

                if tile == FPSK.wallDoor || tile == FPSK.wallLocked || tile == FPSK.wallPink {
                    let midDist = side == 0 ? sideDistX - deltaDistX * 0.5 : sideDistY - deltaDistY * 0.5
                    var dwx = side == 0 ? posY + midDist * rayDirY : posX + midDist * rayDirX
                    dwx -= floor(dwx)
                    let openAmt = level.getDoor(Double(mapX), Double(mapY))?.open ?? 0
                    if dwx < openAmt { continue }
                    perpWallDist = midDist
                    wallX = dwx
                    wallType = tile
                    isDoor = true
                    doorOpenAmt = openAmt
                    hit = true
                    continue
                }

                perpWallDist = side == 0 ? sideDistX - deltaDistX : sideDistY - deltaDistY
                wallX = side == 0 ? posY + perpWallDist * rayDirY : posX + perpWallDist * rayDirX
                wallX -= floor(wallX)
                if side == 0 && rayDirX > 0 { wallX = 1 - wallX }
                if side == 1 && rayDirY < 0 { wallX = 1 - wallX }
                wallType = tile
                hit = true
            }

            zBuffer[x] = perpWallDist
            if perpWallDist <= 0 { continue }

            let lineH = Int(abs(H / perpWallDist))
            let drawS = max(0, h / 2 - lineH / 2)
            let drawE = min(h - 1, h / 2 + lineH / 2)
            if drawE <= drawS { continue }

            let tex = texture(wallType, isDoor, assets)
            var texX = Int((isDoor ? (wallX - doorOpenAmt) : wallX) * Double(FPSK.texSize))
            texX = max(0, min(FPSK.texSize - 1, texX))

            let fog = min(0.88, perpWallDist / 16)
            let sideDark = side == 1 ? 0.28 : 0.0
            let darken = min(0.95, fog + sideDark)
            let keep = 1 - darken

            let strip = Double(drawE - drawS)
            if let tex = tex {
                // Map texX (0..texSize) into the actual texture width
                let tsx = min(tex.w - 1, texX * tex.w / FPSK.texSize)
                let th = Double(tex.h)
                for yy in drawS...drawE {
                    let ty = Int(Double(yy - drawS) / strip * th)
                    let p = tex.pixel(tsx, min(tex.h - 1, ty))
                    if (p >> 24) == 0 { continue }
                    let r = Int(Double((p >> 16) & 0xFF) * keep)
                    let g = Int(Double((p >> 8) & 0xFF) * keep)
                    let b = Int(Double(p & 0xFF) * keep)
                    buffer[yy * w + x] = FPSRenderer.pack(r, g, b)
                }
            } else {
                let base = wallColor(wallType)
                let r = Int(Double((base >> 16) & 0xFF) * keep)
                let g = Int(Double((base >> 8) & 0xFF) * keep)
                let b = Int(Double(base & 0xFF) * keep)
                let c = FPSRenderer.pack(r, g, b)
                for yy in drawS...drawE { buffer[yy * w + x] = c }
            }
        }
    }

    private func texture(_ wallType: Int, _ isDoor: Bool, _ assets: FPSAssets) -> FPSImage? {
        if isDoor || wallType == FPSK.wallDoor { return assets.tiles[safe: 9] ?? nil }
        if wallType == FPSK.wallLocked { return assets.tiles[safe: 10] ?? nil }
        if wallType == FPSK.wallPink { return assets.tiles[safe: 11] ?? nil }
        return assets.tiles[safe: wallType] ?? nil
    }

    private func wallColor(_ type: Int) -> UInt32 {
        let colors: [UInt32] = [0x000000, 0x4a1060, 0x1a3a6a, 0x6a2040, 0x2a1a5a, 0x5a3010, 0x103a30, 0x8a2060]
        return colors[type % colors.count]
    }

    // MARK: Sprites (billboards, z-buffered raw writes)

    struct RenderSprite {
        var x: Double; var y: Double
        var img: FPSImage?
        var scale: Double = 1
        var bright: Bool = false
        var alpha: Double = 1
    }

    private func drawSprites(_ player: FPSPlayer, _ sprites: [RenderSprite]) {
        let sorted = sprites
            .map { (s: $0, dist: ($0.x - player.x) * ($0.x - player.x) + ($0.y - player.y) * ($0.y - player.y)) }
            .sorted { $0.dist > $1.dist }

        let invDet = 1 / (player.planeX * player.dirY - player.dirX * player.planeY)
        let W = Double(w), H = Double(h)

        for entry in sorted {
            let s = entry.s
            guard let img = s.img, s.alpha > 0 else { continue }

            let sprX = s.x - player.x, sprY = s.y - player.y
            let tx = invDet * (player.dirY * sprX - player.dirX * sprY)
            let ty = invDet * (-player.planeY * sprX + player.planeX * sprY)
            if ty <= 0.05 { continue }

            let sprH = Int(abs(H / ty) * s.scale)
            let sprW = sprH
            let scrX = Int((W / 2) * (1 + tx / ty))
            let startX = max(0, scrX - sprW / 2)
            let endX = min(w - 1, scrX + sprW / 2)
            let startY = max(0, h / 2 - sprH / 2)
            let endY = min(h - 1, h / 2 + sprH / 2)
            if endX <= startX || endY <= startY || sprW <= 0 || sprH <= 0 { continue }

            let iw = img.w, ih = img.h
            let alpha = s.alpha

            for sx in startX..<endX {
                if zBuffer[sx] <= ty { continue }
                let texCol = min(iw - 1, max(0, (sx - (scrX - sprW / 2)) * iw / sprW))
                for sy in startY..<endY {
                    let texRow = min(ih - 1, max(0, (sy - startY) * ih / (endY - startY)))
                    let p = img.pixel(texCol, texRow)
                    let pa = (p >> 24) & 0xFF
                    if pa == 0 { continue }
                    var r = Int((p >> 16) & 0xFF)
                    var g = Int((p >> 8) & 0xFF)
                    var b = Int(p & 0xFF)
                    if s.bright {
                        r = min(255, r + 90); g = min(255, g + 20); b = min(255, b + 20)
                    }
                    let idx = sy * w + sx
                    if alpha < 1 || pa < 255 {
                        let a = alpha * Double(pa) / 255.0
                        let dst = buffer[idx]
                        let dr = Int((dst >> 16) & 0xFF), dg = Int((dst >> 8) & 0xFF), db = Int(dst & 0xFF)
                        r = Int(Double(r) * a + Double(dr) * (1 - a))
                        g = Int(Double(g) * a + Double(dg) * (1 - a))
                        b = Int(Double(b) * a + Double(db) * (1 - a))
                    }
                    buffer[idx] = FPSRenderer.pack(r, g, b)
                }
            }
        }
    }

    // MARK: Overlays (UIKit into the flipped context)

    private func withUIKit(_ body: () -> Void) {
        UIGraphicsPushContext(ctx)
        body()
        UIGraphicsPopContext()
    }

    func fillRect(_ x: CGFloat, _ y: CGFloat, _ ww: CGFloat, _ hh: CGFloat, _ color: UIColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fill(CGRect(x: x, y: y, width: ww, height: hh))
    }

    func drawImage(_ img: FPSImage, _ rect: CGRect, alpha: CGFloat = 1) {
        withUIKit {
            let ui = UIImage(cgImage: img.cg)
            ui.draw(in: rect, blendMode: .normal, alpha: alpha)
        }
    }

    func drawText(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat,
                  color: UIColor, align: NSTextAlignment = .left, weight: UIFont.Weight = .bold) {
        withUIKit {
            let font = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let s = NSAttributedString(string: text, attributes: attrs)
            let bounds = s.size()
            var dx = x
            if align == .center { dx = x - bounds.width / 2 }
            else if align == .right { dx = x - bounds.width }
            // y is treated as the text top (approx canvas baseline - ascent)
            s.draw(at: CGPoint(x: dx, y: y - bounds.height * 0.82))
        }
    }

    func drawWeapon(_ player: FPSPlayer, _ img: FPSImage?) {
        guard let img = img else { return }
        let H = CGFloat(h), W = CGFloat(w)
        let scale = (H * 0.62) / CGFloat(img.h)
        let dw = CGFloat(img.w) * scale, dh = CGFloat(img.h) * scale
        let bobY = CGFloat(sin(player.bobPhase)) * 6
        let bobX = CGFloat(cos(player.bobPhase * 0.5)) * 3
        let kickY = CGFloat(player.weaponKick) * 30
        let dx = W / 2 - dw / 2 + bobX
        let dy = H - dh + bobY + kickY + 8
        drawImage(img, CGRect(x: dx, y: dy, width: dw, height: dh))
    }

    func tintFullScreen(_ color: UIColor, alpha: CGFloat) {
        ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    }
}

// Note: Array's `subscript(safe:)` is defined in FeedViewHelper.swift (module-wide).

// Convenience hex → UIColor
extension UIColor {
    convenience init(fpsHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}
