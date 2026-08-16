//
//  AppSettingsView.swift
//  Poplur2025
//
//  Created by Maxine Moodie on 2025-10-26.
//  Redesigned to match the provided Settings mockup (sectioned cards + 3D icons).
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// MARK: - Design palette (sampled from the Settings mockup)

private enum SC {
    static let pageBG      = Color(red: 254/255, green: 241/255, blue: 246/255) // #FEF1F6
    static let card        = Color(red: 254/255, green: 247/255, blue: 249/255) // #FEF7F9
    static let sectionLbl  = Color(red: 255/255, green: 30/255,  blue: 126/255) // #FF1E7E
    static let accent      = Color(red: 254/255, green: 45/255,  blue: 138/255) // #FE2D8A
    static let title       = Color(red: 27/255,  green: 24/255,  blue: 40/255)  // near-black
    static let rowTitle    = Color(red: 30/255,  green: 27/255,  blue: 43/255)
    static let subtitle    = Color(red: 150/255, green: 150/255, blue: 162/255)
    static let chevron     = Color(red: 190/255, green: 186/255, blue: 196/255)
    static let signOutBG   = Color(red: 251/255, green: 227/255, blue: 239/255) // #FBE3EF
    static let divider     = Color(red: 235/255, green: 224/255, blue: 232/255)
    static let cardShadow  = Color.black.opacity(0.05)
}

struct AppSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var cubeSkinStore = CubeSkinStore.shared
    @ObservedObject private var profileThemeStore = ProfileThemeStore.shared

    @State private var cacheSizeText: String = "—"
    @State private var infoTitle: String = ""
    @State private var infoBody: String = ""
    @State private var showInfoSheet = false
    @State private var showProfileThemePicker = false
    @State private var isSimulatorRunning = false

    // Skins shown in the design (4 tiles).
    private let displayedSkins: [CubeSkin] = [.standard, .rainbow, .sparklePink, .gold]

    // Kept for call-site compatibility with existing presentation code.
    init(initialPageIndex: Int = 0) {}

    private var limitVideosBinding: Binding<Bool> {
        Binding(
            get: { settings.maxVideoDurationSeconds <= 10.0 },
            set: { settings.maxVideoDurationSeconds = $0 ? 10.0 : 15.0 }
        )
    }

    var body: some View {
        ZStack {
            SC.pageBG.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 26) {
                    header

                    section("VIDEO SETTINGS") {
                        card {
                            iconRow(
                                icon: "settings_ic_film",
                                title: "Limit videos to 10 seconds",
                                subtitle: "Current limit: \(Int(settings.maxVideoDurationSeconds))s"
                            ) {
                                Toggle("", isOn: limitVideosBinding)
                                    .labelsHidden()
                                    .toggleStyle(SwitchToggleStyle(tint: SC.accent))
                            }
                        }
                    }

                    section("FEED DISPLAY") {
                        card {
                            iconRow(
                                icon: "settings_ic_film",
                                title: "Radius Units",
                                subtitle: settings.radiusUnitPreference.label
                            ) {
                                Picker("", selection: Binding(
                                    get: { settings.radiusUnitPreference },
                                    set: { settings.radiusUnitPreference = $0 }
                                )) {
                                    ForEach(RadiusUnitPreference.allCases) { pref in
                                        Text(pref.label).tag(pref)
                                    }
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                                .tint(SC.accent)
                            }
                        }
                    }

                    section("MAP") {
                        card {
                            iconRow(
                                icon: "settings_ic_cloud",
                                title: "3D Poplur Map",
                                subtitle: settings.use3DMap
                                    ? "Full clay 3D map"
                                    : "Faster clay 2D map"
                            ) {
                                Toggle("", isOn: Binding(
                                    get: { settings.use3DMap },
                                    set: { settings.use3DMap = $0 }
                                ))
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: SC.accent))
                            }
                        }
                    }

                    section("SIMULATOR") {
                        card {
                            navRow(icon: "settings_ic_flask", title: "Seed NA (1000)") {
                                Task { await FakePostService.shared.seedInitialNorthAmerica(total: 1000) }
                            }
                            rowDivider
                            navRow(
                                icon: "settings_ic_play",
                                title: "Start Simulator",
                                subtitle: "Dev mode: 120s/day"
                            ) {
                                FakePostService.shared.startWorldSimulator(devDailySeconds: 120)
                                isSimulatorRunning = true
                            }
                        }
                        stopSimulatorButton
                    }

                    section("ACCOUNT & DATA") {
                        card {
                            navRow(icon: "settings_ic_wrench", title: "Fix Empty UserIDs") {
                                Task { await fixEmptyUserIDs() }
                            }
                            rowDivider
                            navRow(icon: "settings_ic_cloud", title: "Back Up Data") {
                                backUpData()
                            }
                            rowDivider
                            navRow(
                                icon: "settings_ic_trash",
                                title: "Clear Cache",
                                trailingText: cacheSizeText
                            ) {
                                clearCache()
                            }
                        }
                    }

                    section("CUBE SKIN") {
                        HStack(spacing: 14) {
                            ForEach(displayedSkins) { skin in
                                skinTile(skin)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    section("PROFILE THEME") {
                        card {
                            navRow(
                                icon: "settings_ic_play",
                                title: "Profile Background",
                                subtitle: profileThemeStore.selectedTheme.displayName
                            ) {
                                showProfileThemePicker = true
                            }
                        }
                    }

                    section("ABOUT") {
                        card {
                            navRow(icon: "settings_ic_info", title: "About Poplur") {
                                infoTitle = "About Poplur"
                                infoBody = "Poplur — share moments pinned to the world around you.\n\nVersion \(appVersion)"
                                showInfoSheet = true
                            }
                            rowDivider
                            navRow(icon: "settings_ic_doc", title: "Terms of Service") {
                                infoTitle = "Terms of Service"
                                infoBody = "By using Poplur you agree to our Terms of Service and Privacy Policy."
                                showInfoSheet = true
                            }
                        }
                    }

                    signOutButton
                        .padding(.top, 4)

                    Spacer(minLength: 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { refreshCacheSize() }
        .sheet(isPresented: $showInfoSheet) {
            infoSheet
        }
        .sheet(isPresented: $showProfileThemePicker) {
            ProfileThemePickerView(store: profileThemeStore)
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            Text("Settings")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundColor(SC.title)

            HStack {
                // Same icon shown in the hold-menu wheel that opens this screen.
                HoldMenuIconBadge(icon: HoldMenuIcons.settings, size: 46)
                Spacer()
            }

            HStack {
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image("settings_ic_bell")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 58, height: 58)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Section scaffold

    private func section<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .foregroundColor(SC.sectionLbl)
                .padding(.leading, 6)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(SC.card)
            )
            .shadow(color: SC.cardShadow, radius: 12, x: 0, y: 6)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(SC.divider)
            .frame(height: 1)
            .padding(.leading, 84)
    }

    // MARK: - Rows

    private func iconRow<Trailing: View>(
        icon: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 14) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(SC.rowTitle)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(SC.subtitle)
                }
            }

            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func navRow(
        icon: String,
        title: String,
        subtitle: String? = nil,
        trailingText: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            iconRow(icon: icon, title: title, subtitle: subtitle) {
                HStack(spacing: 10) {
                    if let trailingText {
                        Text(trailingText)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(SC.subtitle)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(SC.chevron)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var stopSimulatorButton: some View {
        Button(role: .destructive) {
            FakePostService.shared.stopWorldSimulator()
            isSimulatorRunning = false
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                Text("Stop Simulator")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(SC.accent)
            )
            .shadow(color: SC.accent.opacity(0.35), radius: 12, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    // MARK: - Cube skin tile

    private func skinTile(_ skin: CubeSkin) -> some View {
        let isSelected = cubeSkinStore.current == skin
        return Button {
            cubeSkinStore.apply(skin)
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(skin.appIconPreviewAssetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 74, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(isSelected ? SC.accent : Color.clear, lineWidth: 3)
                        )
                        .padding(3)
                        .background(
                            RoundedRectangle(cornerRadius: 21, style: .continuous)
                                .fill(SC.card)
                        )
                        .shadow(color: SC.cardShadow, radius: 8, x: 0, y: 4)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Circle().fill(SC.accent))
                            .offset(x: 6, y: -6)
                    }
                }

                Text(skin.displayName)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(isSelected ? SC.accent : SC.subtitle)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sign out

    private var signOutButton: some View {
        Button(action: signOut) {
            HStack(spacing: 14) {
                Image("settings_ic_signout")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
                Text("Sign Out")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(SC.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(SC.signOutBG)
            )
            .shadow(color: SC.cardShadow, radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Info sheet

    private var infoSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(infoTitle)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundColor(SC.title)
                .padding(.top, 8)
            Text(infoBody)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(SC.rowTitle)
            Spacer()
            Button("Close") { showInfoSheet = false }
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(SC.accent)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .presentationDetents([.medium])
        .background(SC.pageBG.ignoresSafeArea())
    }

    // MARK: - Actions & helpers

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func refreshCacheSize() {
        let bytes = URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage
        let mb = Double(bytes) / (1024 * 1024)
        cacheSizeText = mb < 0.1 ? "0 MB" : String(format: "%.1f MB", mb)
    }

    private func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        PoplurTemporaryFileOwnership.deleteAllOwned()
        refreshCacheSize()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func backUpData() {
        // Lightweight touch: nudge the auth token so cached Firestore writes flush.
        Auth.auth().currentUser?.getIDTokenForcingRefresh(true) { _, _ in }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func signOut() {
        do { try Auth.auth().signOut() } catch {
            print("Sign out failed: \(error.localizedDescription)")
        }
    }

    /// DEBUG utility: assign the current user's UID to posts that were saved with an empty userID.
    private func fixEmptyUserIDs() async {
        guard let currentUID = Auth.auth().currentUser?.uid else {
            print("❌ Cannot fix userIDs - not logged in")
            return
        }
        let db = Firestore.firestore()
        do {
            let snapshot = try await db.collection("posts")
                .whereField("userID", isEqualTo: "")
                .getDocuments()
            for doc in snapshot.documents {
                try await doc.reference.updateData(["userID": currentUID])
            }
            print("🎉 Fixed \(snapshot.documents.count) posts with empty userID")
        } catch {
            print("❌ Error fixing userIDs: \(error)")
        }
    }
}
