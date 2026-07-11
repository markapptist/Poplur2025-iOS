import Foundation
import CoreGraphics
import ImageIO
import UIKit

// MARK: - PoplurFPS assets
//
// Loads the bundled sprite PNGs (Poplur2025/PoplurFPS/sprites, a folder reference)
// into FPSImage — CGImage plus a decoded ARGB pixel array used by the software
// raycaster for per-column sampling. Pixel layout matches FPSRenderer's buffer:
// premultipliedFirst + byteOrder32Little → UInt32 = 0xAARRGGBB.

struct FPSImage {
    let cg: CGImage
    let w: Int
    let h: Int
    let px: [UInt32]

    @inline(__always) func pixel(_ x: Int, _ y: Int) -> UInt32 {
        if x < 0 || y < 0 || x >= w || y >= h { return 0 }
        return px[y * w + x]
    }
}

final class FPSAssets {
    var tiles: [FPSImage?] = []          // [1..8]=walls, [9]=door, [10]=locked, [11]=pink
    var weapons: [String: FPSImage] = [:]
    var enemies: [String: FPSImage] = [:]
    var pickups: [String: FPSImage] = [:]
    var props: [String: FPSImage] = [:]
    var hud: [String: FPSImage] = [:]
    var menu: [String: FPSImage] = [:]
    var misc: [String: FPSImage] = [:]

    static func decode(_ cg: CGImage) -> [UInt32] {
        let w = cg.width, h = cg.height
        var buf = [UInt32](repeating: 0, count: w * h)
        let cs = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        buf.withUnsafeMutableBytes { raw in
            if let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: w * 4,
                                   space: cs, bitmapInfo: info) {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            }
        }
        return buf
    }

    private static func load(_ relPath: String) -> FPSImage? {
        // relPath e.g. "08_environment_tiles/tile_01.png"
        let parts = relPath.split(separator: "/")
        guard parts.count == 2 else { return nil }
        let dir = "PoplurFPS/sprites/\(parts[0])"
        let file = parts[1]
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: dir)
                ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "PoplurFPS/sprites"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
        else { return nil }
        return FPSImage(cg: cg, w: cg.width, h: cg.height, px: decode(cg))
    }

    /// Synchronous load — sprite set is small (~40 PNGs). Called off the main
    /// thread by the scene; `onProgress` fires 0→1.
    static func loadAll(onProgress: ((Double) -> Void)? = nil) -> FPSAssets {
        let tasks: [(String, String)] = [
            ("t1", "08_environment_tiles/tile_01.png"),
            ("t2", "08_environment_tiles/tile_02.png"),
            ("t3", "08_environment_tiles/tile_03.png"),
            ("t4", "08_environment_tiles/tile_04.png"),
            ("t5", "08_environment_tiles/tile_05.png"),
            ("t6", "08_environment_tiles/tile_06.png"),
            ("t7", "08_environment_tiles/tile_07.png"),
            ("t8", "08_environment_tiles/tile_08.png"),
            ("door_normal", "09_doors_panels/door_panel_01.png"),
            ("door_locked", "09_doors_panels/door_panel_02.png"),
            ("door_pink",   "09_doors_panels/door_panel_03.png"),
            // Midnight Sentinel: 3D GLB pre-rendered to a 9-frame aim strip (left → right).
            ("pistol",  "02_weapons/sentinel_aim.png"),
            ("shotgun", "02_weapons/shotgun.png"),
            ("plasma",  "02_weapons/plasma.png"),
            ("rocket",  "02_weapons/rocket_launcher.png"),
            ("railgun", "02_weapons/railgun.png"),
            ("soldier", "05_enemies/enemy_soldier_sheet.png"),
            ("heavy",   "05_enemies/enemy_heavy_sheet.png"),
            ("drone",   "05_enemies/enemy_drone_sheet.png"),
            ("turret",  "05_enemies/enemy_turret_sheet.png"),
            ("boss",    "05_enemies/enemy_boss_sheet.png"),
            ("health",  "06_pickups/pickup_health.png"),
            ("armor",   "06_pickups/pickup_armor.png"),
            ("ammo",    "06_pickups/pickup_ammo.png"),
            ("key_g",   "06_pickups/key_gold.png"),
            ("key_p",   "06_pickups/key_pink.png"),
            ("barrel",  "07_item_boxes/barrel_pink.png"),
            ("crate",   "07_item_boxes/crate_pink.png"),
            ("sign",    "10_decals_signs/poplur_stay_connected_sign.png"),
            ("torch",   "13_misc/torch.png"),
            ("banner",  "13_misc/poplur_banner.png"),
            ("hud_face",   "11_hud_ui/hud_face.png"),
            ("hud_health", "11_hud_ui/hud_health.png"),
            ("hud_armor",  "11_hud_ui/hud_armor.png"),
            ("hud_ammo",   "11_hud_ui/hud_ammo.png"),
            ("hud_slot",   "11_hud_ui/hud_weapon_slot.png"),
            ("main_menu",  "01_title_screen/main_menu_crt.png"),
            ("logo",         "13_misc/pixel_p_logo.png"),
            ("levelup_sign", "10_decals_signs/level_up_sign.png"),
        ]

        var results: [String: FPSImage] = [:]
        let total = Double(tasks.count)
        for (i, (key, path)) in tasks.enumerated() {
            if let img = load(path) { results[key] = img }
            onProgress?(Double(i + 1) / total)
        }

        let a = FPSAssets()
        a.tiles = [
            nil,
            results["t1"], results["t2"], results["t3"], results["t4"],
            results["t5"], results["t6"], results["t7"], results["t8"],
            results["door_normal"], results["door_locked"], results["door_pink"],
        ]
        a.weapons = compact(results, ["pistol", "shotgun", "plasma", "rocket", "railgun"])
        a.enemies = compact(results, ["soldier", "heavy", "drone", "turret", "boss"])
        a.pickups = compact(results, ["health", "armor", "ammo", "key_g", "key_p"])
        a.props   = compact(results, ["barrel", "crate", "sign", "torch", "banner"])
        a.hud = [
            "face": results["hud_face"], "health": results["hud_health"],
            "armor": results["hud_armor"], "ammo": results["hud_ammo"], "slot": results["hud_slot"],
        ].compactMapValues { $0 }
        a.menu = ["main_menu": results["main_menu"]].compactMapValues { $0 }
        a.misc = ["logo": results["logo"], "levelup_sign": results["levelup_sign"]].compactMapValues { $0 }
        return a
    }

    private static func compact(_ src: [String: FPSImage], _ keys: [String]) -> [String: FPSImage] {
        var out: [String: FPSImage] = [:]
        for k in keys { if let v = src[k] { out[k] = v } }
        return out
    }
}
