//
//  HoldMenuIcons.swift
//  Poplur2025
//
//  Single source of truth for the cube hold-menu icons. Every wheel item AND the
//  matching header badge on the destination sub-screen reference the same entry
//  here, so the wheel icon and the screen it opens can never drift apart.
//

import SwiftUI

struct HoldMenuIcon {
    /// Asset-catalog PNG (3D glossy tile). Falls back to `systemImage` if missing.
    let asset: String
    /// Wheel label (also reused as the sub-screen header label where useful).
    let title: String
    /// SF Symbol fallback + cube-face override glyph.
    let systemImage: String
    /// Tint for the SF Symbol fallback.
    let tint: Color
}

enum HoldMenuIcons {
    // Global / shared destinations
    static let home     = HoldMenuIcon(asset: "HoldMenu_Home",     title: "HOME",     systemImage: "house.fill",           tint: Color(red: 1.0, green: 0.30, blue: 0.62))
    static let chat     = HoldMenuIcon(asset: "HoldMenu_Chat",     title: "CHAT",     systemImage: "message.fill",         tint: Color(red: 0.30, green: 0.55, blue: 1.0))
    static let music    = HoldMenuIcon(asset: "HoldMenu_Music",    title: "MUSIC",    systemImage: "music.note",           tint: Color(red: 1.0, green: 0.30, blue: 0.62))
    static let youtube  = HoldMenuIcon(asset: "HoldMenu_YouTube",  title: "YOUTUBE",  systemImage: "play.rectangle.fill",  tint: .red)
    static let store    = HoldMenuIcon(asset: "HoldMenu_Store",    title: "STORE",    systemImage: "bag.fill",             tint: Color(red: 0.62, green: 0.35, blue: 1.0))
    static let settings = HoldMenuIcon(asset: "HoldMenu_Settings", title: "SETTINGS", systemImage: "gearshape.fill",       tint: .gray)
    static let phone    = HoldMenuIcon(asset: "HoldMenu_Phone",    title: "PHONE",    systemImage: "phone.fill",           tint: .teal)

    // Profile sub-screens
    static let stats    = HoldMenuIcon(asset: "HoldMenu_Stats",    title: "STATS",    systemImage: "chart.bar.fill",       tint: .cyan)
    static let credits  = HoldMenuIcon(asset: "HoldMenu_Create",   title: "CREDITS",  systemImage: "bolt.circle.fill",     tint: Color(red: 1.0, green: 0.30, blue: 0.62))

    // Feed sub-screens
    static let tvGuide  = HoldMenuIcon(asset: "HoldMenu_TVGuide",  title: "TV GUIDE", systemImage: "tv.fill",              tint: Color(red: 0.62, green: 0.35, blue: 1.0))
    static let news     = HoldMenuIcon(asset: "HoldMenu_News",     title: "NEWS",     systemImage: "newspaper.fill",       tint: Color(red: 0.20, green: 0.78, blue: 0.45))

    // Camera sub-screens
    static let cameraRoll = HoldMenuIcon(asset: "HoldMenu_CameraRoll", title: "CAMERA ROLL", systemImage: "photo.on.rectangle.fill", tint: Color(red: 0.30, green: 0.55, blue: 1.0))
    static let create     = HoldMenuIcon(asset: "HoldMenu_Create",     title: "CREATE",      systemImage: "plus.circle.fill",        tint: Color(red: 1.0, green: 0.30, blue: 0.62))

    // Map sub-screens
    static let locate   = HoldMenuIcon(asset: "HoldMenu_Search",   title: "LOCATE",   systemImage: "location.fill",        tint: Color(red: 1.0, green: 0.30, blue: 0.62))
    static let post     = HoldMenuIcon(asset: "HoldMenu_Create",   title: "POST",     systemImage: "mappin.and.ellipse",   tint: Color(red: 1.0, green: 0.30, blue: 0.62))
    static let tour     = HoldMenuIcon(asset: "HoldMenu_Tour",     title: "TOUR",     systemImage: "play.circle.fill",     tint: .red)

    // "CHAT" wheel item on the Profile wheel is historically titled/handled as "mail".
    static let mail     = HoldMenuIcon(asset: "HoldMenu_Chat",     title: "CHAT",     systemImage: "envelope.fill",        tint: Color(red: 0.42, green: 1.0, blue: 0.33))
}

extension CubeSubmenuItem {
    /// Build a wheel item straight from a registry entry, so the wheel and the
    /// destination sub-screen always show the same icon.
    init(id: String, icon: HoldMenuIcon, action: @escaping () -> Void) {
        self.init(
            id: id,
            title: icon.title,
            iconImageName: icon.asset,
            systemImage: icon.systemImage,
            tint: icon.tint,
            action: action
        )
    }
}

/// Small header badge that renders a hold-menu icon (used on the sub-screens so
/// the icon a user tapped in the wheel reappears on the screen it opened).
struct HoldMenuIconBadge: View {
    let icon: HoldMenuIcon
    var size: CGFloat = 46

    var body: some View {
        Image(icon.asset)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}
