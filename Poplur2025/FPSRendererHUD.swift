import Foundation
import CoreGraphics
import UIKit

// MARK: - PoplurFPS HUD, menu & overlay rendering (port of HUD.ts / Menu.ts)

extension FPSRenderer {
    private var PINK: UIColor  { UIColor(fpsHex: 0xff4db8) }
    private var GOLD: UIColor  { UIColor(fpsHex: 0xffd700) }
    private var GREEN: UIColor { UIColor(fpsHex: 0x00ff88) }
    private var RED: UIColor   { UIColor(fpsHex: 0xff3333) }

    // MARK: HUD

    func renderHUD(_ player: FPSPlayer, _ assets: FPSAssets, _ level: FPSLevel,
                   score: Int, kills: Int, gameTime: Double) {
        let W = CGFloat(w), H = CGFloat(h)
        let barH: CGFloat = 56

        fillRect(0, H - barH, W, barH, UIColor(white: 0.04, alpha: 0.88))
        fillRect(0, H - barH, W, 1.5, PINK)

        // Face
        if let face = assets.hud["face"] {
            let sz: CGFloat = 46
            drawImage(face, CGRect(x: W / 2 - sz / 2, y: H - sz - 6 + 2, width: sz, height: sz))
        }

        // Health
        if let ic = assets.hud["health"] { drawImage(ic, CGRect(x: 8, y: H - barH + 6, width: 18, height: 18)) }
        let hc = player.health > 50 ? GREEN : (player.health > 25 ? UIColor(fpsHex: 0xffaa00) : RED)
        drawText("\(Int(player.health))", x: 30, y: H - barH + 22, size: 22, color: hc)
        fillRect(8, H - barH + 28, 70, 6, UIColor(white: 0.07, alpha: 1))
        fillRect(8, H - barH + 28, 70 * CGFloat(player.health / player.maxHealth), 6, hc)

        // Armor
        let ax: CGFloat = 90
        if let ic = assets.hud["armor"] { drawImage(ic, CGRect(x: ax, y: H - barH + 6, width: 18, height: 18)) }
        drawText("\(Int(player.armor))", x: ax + 22, y: H - barH + 22, size: 22, color: UIColor(fpsHex: 0x88aaff))
        fillRect(ax, H - barH + 28, 70, 6, UIColor(white: 0.07, alpha: 1))
        fillRect(ax, H - barH + 28, 70 * CGFloat(player.armor / player.maxArmor), 6, UIColor(fpsHex: 0x4488ff))

        // Weapon + ammo
        let wDef = FPS_WEAPONS[player.weapon]
        let wx: CGFloat = 175
        if let ic = assets.hud["ammo"] { drawImage(ic, CGRect(x: wx, y: H - barH + 6, width: 18, height: 18)) }
        drawText(wDef.name, x: wx, y: H - barH + 42, size: 14, color: GOLD)
        let ammoLeft = player.ammo[wDef.ammoType]
        drawText("\(ammoLeft)", x: wx + 22, y: H - barH + 22, size: 22, color: ammoLeft > 10 ? GOLD : RED)

        // Weapon slots
        let slotX0 = W - 5 * 38 - 8
        for i in 0..<5 {
            let sx = slotX0 + CGFloat(i) * 38
            let sy = H - 52
            fillRect(sx, sy, 34, 30, i == player.weapon ? UIColor(red: 0.7, green: 0, blue: 0.35, alpha: 0.7)
                                                          : UIColor(red: 0.08, green: 0, blue: 0.16, alpha: 0.6))
            drawText("\(i + 1)", x: sx + 3, y: sy + 12, size: 10, color: i == player.weapon ? GOLD : UIColor(white: 0.53, alpha: 1))
            drawText(String(FPS_WEAPONS[i].name.prefix(4)), x: sx + 2, y: sy + 24, size: 8, color: UIColor(white: 0.67, alpha: 1))
            let a = player.ammo[FPS_WEAPONS[i].ammoType]
            fillRect(sx + 26, sy + 3, 5, 5, a > 0 ? GREEN : RED)
        }

        // Keys
        var kx = W - 5 * 38 - 8 - 28
        if player.hasKey["gold"] == true, let kg = assets.pickups["key_g"] {
            drawImage(kg, CGRect(x: kx, y: H - 50, width: 22, height: 22)); kx -= 26
        }
        if player.hasKey["pink"] == true, let kp = assets.pickups["key_p"] {
            drawImage(kp, CGRect(x: kx, y: H - 50, width: 22, height: 22))
        }

        // Top bar
        fillRect(0, 0, W, 22, UIColor(white: 0.04, alpha: 0.7))
        drawText("SCORE: \(String(format: "%07d", score))", x: 8, y: 15, size: 13, color: GOLD)
        let mm = String(format: "%02d", Int(gameTime / 60))
        let ss = String(format: "%02d", Int(gameTime.truncatingRemainder(dividingBy: 60)))
        drawText("\(mm):\(ss)", x: W / 2 - 20, y: 15, size: 13, color: PINK)
        drawText("KILLS: \(kills)", x: W - 90, y: 15, size: 13, color: UIColor(fpsHex: 0xaaffdd))

        renderMinimap(player, level)

        // Damage flash
        if player.flashAlpha > 0 {
            tintFullScreen(UIColor(red: 0.78, green: 0, blue: 0, alpha: 1), alpha: CGFloat(player.flashAlpha) * 0.35)
        }

        // Crosshair
        let cx = W / 2, cy = H / 2
        fillRect(cx - 8, cy, 16, 1, UIColor(white: 1, alpha: 0.7))
        fillRect(cx, cy - 8, 1, 16, UIColor(white: 1, alpha: 0.7))
        fillRect(cx - 1, cy - 1, 2, 2, UIColor(red: 1, green: 0.4, blue: 0.78, alpha: 0.8))
    }

    private func renderMinimap(_ player: FPSPlayer, _ level: FPSLevel) {
        let W = CGFloat(w)
        let mapSize: CGFloat = 80, tSize: CGFloat = 3
        let mX = W - mapSize - 6, mY: CGFloat = 26
        let pMapX = Int(floor(player.x)), pMapY = Int(floor(player.y))

        fillRect(mX, mY, mapSize, mapSize, UIColor(white: 0.04, alpha: 0.75))
        let tilesVisible = Int(mapSize / tSize)
        let startTX = pMapX - tilesVisible / 2
        let startTY = pMapY - tilesVisible / 2

        for ty in 0..<tilesVisible {
            for tx in 0..<tilesVisible {
                let mx = startTX + tx, my = startTY + ty
                let t = level.getCell(Double(mx), Double(my))
                if t == 0 { continue }
                let door = level.getDoor(Double(mx), Double(my))
                let color: UIColor
                if (door?.open ?? 0) >= 0.5 { color = UIColor(fpsHex: 0x333344) }
                else if t == 7 { color = UIColor(fpsHex: 0xaa6600) }
                else if t == 8 || t == 9 { color = UIColor(fpsHex: 0xff4400) }
                else { color = UIColor(hue: (CGFloat(t) * 40 + 240) / 360, saturation: 0.4, brightness: 0.35, alpha: 1) }
                fillRect(mX + CGFloat(tx) * tSize, mY + CGFloat(ty) * tSize, tSize - 1, tSize - 1, color)
            }
        }
        // Player dot
        let pdx = CGFloat(pMapX - startTX) * tSize + CGFloat(player.x - Double(pMapX)) * tSize
        let pdy = CGFloat(pMapY - startTY) * tSize + CGFloat(player.y - Double(pMapY)) * tSize
        fillRect(mX + pdx - 2, mY + pdy - 2, 4, 4, PINK)
    }

    // MARK: Loading

    func renderLoading(_ progress: Double) {
        let W = CGFloat(w), H = CGFloat(h)
        fillRect(0, 0, W, H, UIColor(fpsHex: 0x0a0018))
        drawText("POPLUR FPS", x: W / 2, y: H / 2 - 30, size: 34, color: GOLD, align: .center)
        drawText("LOADING ASSETS...", x: W / 2, y: H / 2 + 6, size: 14, color: PINK, align: .center)
        let barW: CGFloat = 260, barX = W / 2 - barW / 2, barY = H / 2 + 30
        fillRect(barX, barY, barW, 10, UIColor(white: 0.1, alpha: 1))
        fillRect(barX, barY, barW * CGFloat(progress), 10, PINK)
    }

    // MARK: Arcade cabinet + zoom intro

    private func cabinetLayout() -> (cabL: CGFloat, cabTop: CGFloat, cw: CGFloat, ch: CGFloat,
                                     marqY: CGFloat, marqH: CGFloat,
                                     screenX: CGFloat, screenY: CGFloat, screenW: CGFloat, screenH: CGFloat) {
        let W = CGFloat(w), H = CGFloat(h)
        let cw: CGFloat = W * 0.46
        let cabL = (W - cw) / 2
        let cabTop: CGFloat = H * 0.03
        let ch = H * 0.95
        let marqH: CGFloat = H * 0.14
        let marqY = cabTop + H * 0.02
        let screenW = cw * 0.80
        let screenX = cabL + (cw - screenW) / 2
        let screenY = marqY + marqH + H * 0.05
        let screenH = screenW * 0.82
        return (cabL, cabTop, cw, ch, marqY, marqH, screenX, screenY, screenW, screenH)
    }

    /// t: 0 = full cabinet → 1 = zoomed into the CRT screen.
    func renderMenuCabinet(_ assets: FPSAssets, selected: Int, tick: Double, t: Double) {
        let W = CGFloat(w), H = CGFloat(h)
        let L = cabinetLayout()

        // Dark arcade room
        fillRect(0, 0, W, H, UIColor(fpsHex: 0x08000e))
        radialVignette()

        pushZoom(into: L, t: t) {
            // Cabinet body
            roundRect(L.cabL, L.cabTop + 26, L.cw, L.ch - 26, 12, fill: UIColor(fpsHex: 0x2a0838))
            strokeRound(L.cabL, L.cabTop + 26, L.cw, L.ch - 26, 12, color: UIColor(fpsHex: 0xc8960a), lineWidth: 3)

            // Marquee
            roundRect(L.cabL, L.marqY, L.cw, L.marqH, 10, fill: UIColor(fpsHex: 0x1a0030))
            strokeRound(L.cabL, L.marqY, L.cw, L.marqH, 10, color: GOLD, lineWidth: 2)
            let logoSz: CGFloat = L.marqH * 0.62
            if let logo = assets.misc["logo"] {
                drawImage(logo, CGRect(x: L.cabL + 8, y: L.marqY + (L.marqH - logoSz) / 2, width: logoSz, height: logoSz))
                drawImage(logo, CGRect(x: L.cabL + L.cw - 8 - logoSz, y: L.marqY + (L.marqH - logoSz) / 2, width: logoSz, height: logoSz))
            }
            drawText("poplur", x: L.cabL + L.cw / 2, y: L.marqY + L.marqH * 0.62, size: L.cw * 0.15, color: GOLD, align: .center)

            // Screen bezel + CRT
            let pad: CGFloat = 12
            roundRect(L.screenX - pad, L.screenY - pad, L.screenW + pad * 2, L.screenH + pad * 2, 10, fill: UIColor(fpsHex: 0x0a0012))
            if let menu = assets.menu["main_menu"] {
                drawImage(menu, CGRect(x: L.screenX, y: L.screenY, width: L.screenW, height: L.screenH))
            } else {
                fillRect(L.screenX, L.screenY, L.screenW, L.screenH, UIColor(fpsHex: 0x100030))
                drawText("START GAME", x: L.screenX + L.screenW / 2, y: L.screenY + L.screenH * 0.5, size: L.screenW * 0.11, color: GOLD, align: .center)
            }
            // Blink prompt strip
            if Int(tick * 2) % 2 == 0 {
                fillRect(L.screenX, L.screenY + L.screenH * 0.60, L.screenW, L.screenH * 0.16, UIColor(fpsHex: 0xffd700, alpha: 0.10))
            }

            // Controls bar
            let ctrlY = L.screenY + L.screenH + 22
            let ctrlH: CGFloat = 46
            roundRect(L.cabL + 6, ctrlY, L.cw - 12, ctrlH, 8, fill: UIColor(fpsHex: 0x0d0020))
            // Joystick
            let jx = L.cabL + 34, jy = ctrlY + ctrlH / 2
            fillCircle(jx, jy, 12, UIColor(white: 0.07, alpha: 1))
            fillCircle(jx, jy - 14, 6, UIColor(fpsHex: 0x333333))
            // Buttons
            let btnColors: [UInt32] = [0xffd700, 0xff4db8, 0x00ff88, 0x4488ff, 0xff4db8]
            for (i, c) in btnColors.enumerated() {
                let bx = L.cabL + 76 + CGFloat(i) * 34
                fillCircle(bx, jy, 11, UIColor(fpsHex: c))
            }
        }
    }

    func renderPause() {
        let W = CGFloat(w), H = CGFloat(h)
        tintFullScreen(.black, alpha: 0.6)
        drawText("PAUSED", x: W / 2, y: H / 2, size: 42, color: PINK, align: .center)
        drawText("tap to resume", x: W / 2, y: H / 2 + 40, size: 16, color: .white, align: .center)
    }

    func renderDeath(_ alpha: Double) {
        let W = CGFloat(w), H = CGFloat(h)
        tintFullScreen(UIColor(red: 0.6, green: 0, blue: 0, alpha: 1), alpha: CGFloat(alpha) * 0.65)
        if alpha < 0.7 { return }
        drawText("YOU DIED", x: W / 2, y: H / 2 - 20, size: 52, color: RED, align: .center)
        drawText("TAP TO RESPAWN", x: W / 2, y: H / 2 + 30, size: 18, color: .white, align: .center)
    }

    func renderWin(_ score: Int, _ kills: Int) {
        let W = CGFloat(w), H = CGFloat(h)
        tintFullScreen(.black, alpha: 0.75)
        drawText("LEVEL COMPLETE!", x: W / 2, y: H / 2 - 50, size: 44, color: GOLD, align: .center)
        drawText("SCORE: \(score)", x: W / 2, y: H / 2, size: 22, color: PINK, align: .center)
        drawText("KILLS: \(kills)", x: W / 2, y: H / 2 + 34, size: 22, color: PINK, align: .center)
        drawText("TAP TO CONTINUE", x: W / 2, y: H / 2 + 78, size: 16, color: .white, align: .center)
    }
}
