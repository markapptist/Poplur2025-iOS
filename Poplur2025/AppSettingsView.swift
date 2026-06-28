//
//  AppSettingsView.swift
//  Poplur2025
//
//  Created by Maxine Moodie on 2025-10-26.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct AppSettingsView: View {
    @Environment(\.layoutPreviewMode) private var layoutPreviewMode
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var cubeSkinStore = CubeSkinStore.shared

    @State private var pageIndex: Int = 0
    @State private var isPrivateAccount = false
    @State private var notificationsEnabled = true
    @AppStorage("poplur_use2DMap") private var use2DMap: Bool = false
    @AppStorage("poplur_phoneXLMode") private var phoneXLMode: Bool = true
    @AppStorage("poplur_tvGuideFlipAnimation") private var tvGuideFlipAnimation: Bool = true
    @AppStorage("poplur_feedChannelButtonsSpriteKit2D") private var feedChannelButtonsSpriteKit2D: Bool = false
    @AppStorage("poplur_profileAvatarIs3D") private var profileAvatarIs3D: Bool = false

    @State private var posts: [Post] = []
    @State private var isLoadingStats = true
    @State private var maxDurationDisplay: Double = SettingsStore.shared.maxVideoDurationSeconds

    private var totalRadius: Int {
        posts.reduce(0) { $0 + $1.radius }
    }
    private var averageRadius: Double {
        guard !posts.isEmpty else { return 0 }
        let avgMeters = Double(totalRadius) / Double(posts.count)
        return avgMeters / 1000.0 // KM
    }
    private var ringMax: Double {
        // Choose a max that comfortably contains the average value
        let baseMaxKM = max(1.0, averageRadius * 3.0) // 3x average
        // Round up to the next nice step (power of 10 multiples) and ensure a sensible floor
        let step: Double = 10.0
        let rounded = ceil(baseMaxKM / step) * step
        return max(10.0, rounded) // in KM
    }

    private var screenSize: CGSize { UIScreen.main.bounds.size }
    private var ticketWidth: CGFloat { min(screenSize.width - 24, 700) }
    private var ticketHeight: CGFloat { screenSize.height * 0.78 }

    private var theme: CubeSkinAppTheme {
        cubeSkinStore.current.appTheme
    }

    init(initialPageIndex: Int = 0) {
        _pageIndex = State(initialValue: initialPageIndex)
    }

    var body: some View {
        ZStack {
            CubeSkinThemedBackground(skin: cubeSkinStore.current)

            VStack(spacing: 0) {
                // Start content at the very top – no top Spacer
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        Text("Settings")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(theme.primaryText)
                            .padding(.top, 22)
                            .padding(.bottom, 4)

                        settingsPage.id("top")
                    }
                    .frame(width: ticketWidth, height: ticketHeight)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(theme.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .stroke(theme.border, lineWidth: 1.2)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .shadow(color: theme.shadow, radius: 18, x: 0, y: 12)
                    .onReceive(NotificationCenter.default.publisher(for: .ResetTabToTop)) { _ in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                }
            }
        }
        .task {
            maxDurationDisplay = settings.maxVideoDurationSeconds
        }
        .onAppear {
            maxDurationDisplay = settings.maxVideoDurationSeconds
        }
    }

    // MARK: - Pages

    private var statsPage: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 20) {
                // Title
                Text("Average Radius")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(theme.primaryText)
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity, alignment: .center)

                if isLoadingStats {
                    HStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(theme.accent)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                } else {
                    // Ring centered
                    HStack {
                        Spacer()
                        RingStatView(
                            value: averageRadius,
                            maxValue: ringMax,
                            unit: "KM",
                            accentColor: theme.accent,
                            trackColor: theme.border.opacity(0.24),
                            lineWidthFactor: 0.12
                        )
                        .frame(height: 260)
                        .padding(.top, 35)
                        Spacer()
                    }
                    Text("Posts counted: \(posts.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.secondaryText)
                        .padding(.bottom, 44)
                }

                VStack(alignment: .center, spacing: 8) {
                    Text("Accumulated Radius")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(theme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .center)

                    if isLoadingStats {
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(theme.accent)
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    } else {
                        Text("You’ve reached")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text(formattedKM(totalRadius))
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .foregroundColor(theme.primaryText)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text("in total")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(theme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.never)
    }

    private var settingsPage: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 24) {
                // Title
                Text("Account Options")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(theme.primaryText)
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Settings rows group
                VStack(spacing: 14) {
                    settingsToggleRow(title: "Private Account", isOn: $isPrivateAccount)
                    settingsToggleRow(title: "Notifications", isOn: $notificationsEnabled)
                    settingsToggleRow(title: "2D Map", isOn: $use2DMap)
                    settingsToggleRow(title: "2D Feed Buttons", isOn: $feedChannelButtonsSpriteKit2D)
                    settingsToggleRow(title: "XL Phone", isOn: $phoneXLMode)
                    settingsToggleRow(
                        title: "HUD Sleep Timer",
                        isOn: Binding(
                            get: { settings.hudSleepTimerEnabled },
                            set: { settings.hudSleepTimerEnabled = $0 }
                        )
                    )
                    settingsToggleRow(
                        title: "Closed Captions",
                        isOn: Binding(
                            get: { settings.closedCaptionsEnabled },
                            set: { settings.closedCaptionsEnabled = $0 }
                        )
                    )
                    settingsToggleRow(title: "TV Guide Flip Animation", isOn: $tvGuideFlipAnimation)
                    settingsToggleRow(
                        title: "Tilt Control",
                        isOn: Binding(
                            get: { settings.tiltControlEnabled },
                            set: { settings.tiltControlEnabled = $0 }
                        )
                    )
                    profileHeadModePicker
                    settingsNavRow(title: "Email Address") { /* push email editor */ }
                    settingsNavRow(title: "Password") { /* push password editor */ }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Preferred Language")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(theme.primaryText)

                    Picker(
                        "Preferred Language",
                        selection: Binding(
                            get: { settings.preferredLanguage },
                            set: { settings.preferredLanguage = $0 }
                        )
                    ) {
                        ForEach(PoplurLanguage.allCases) { language in
                            Text("\(language.flag) \(language.shortName)").tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Appearance")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(theme.primaryText)

                    Picker(
                        "Appearance",
                        selection: Binding(
                            get: { settings.colorSchemePreference },
                            set: { settings.colorSchemePreference = $0 }
                        )
                    ) {
                        ForEach(ColorSchemePreference.allCases) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Hold Menu")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(theme.primaryText)

                    Picker(
                        "Hold Menu",
                        selection: Binding(
                            get: { settings.holdMenuLayoutPreference },
                            set: { settings.holdMenuLayoutPreference = $0 }
                        )
                    ) {
                        ForEach(HoldMenuLayoutPreference.allCases) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Transitions")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(theme.primaryText)

                    Picker(
                        "Transitions",
                        selection: Binding(
                            get: { settings.transitionStylePreference },
                            set: { settings.transitionStylePreference = $0 }
                        )
                    ) {
                        ForEach(TransitionStylePreference.allCases) { pref in
                            Text(pref.label).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Video duration quick action
                VStack(alignment: .center, spacing: 8) {
                    Button {
                        settings.maxVideoDurationSeconds = 10.0
                        maxDurationDisplay = 10.0
                    } label: {
                        Text("Limit videos to 10 seconds")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(theme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(theme.controlFill, in: Capsule())
                    }

                    Text("Current limit: \(Int(maxDurationDisplay))s")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                // Dev actions (optional)
                VStack(spacing: 12) {
                    Button {
                        Task { await FakePostService.shared.seedInitialNorthAmerica(total: 1000) }
                    } label: {
                        Text("Seed NA (1000)")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(theme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(theme.controlFill, in: Capsule())
                    }

                    Button {
                        FakePostService.shared.startWorldSimulator(devDailySeconds: 120)
                    } label: {
                        Text("Start Simulator (dev: 120s/day)")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(theme.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(theme.controlFill, in: Capsule())
                    }
                    
                    Button {
                        Task { await fixEmptyUserIDs() }
                    } label: {
                        Text("🔧 Fix Empty UserIDs")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.orange, in: Capsule())
                    }

                    Button(role: .destructive) {
                        FakePostService.shared.stopWorldSimulator()
                    } label: {
                        Text("Stop Simulator")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.red, in: Capsule())
                    }
                    .padding(.top, 4)
                }

                // Cube Skin
                VStack(alignment: .leading, spacing: 12) {
                    Text("Cube Skin")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(theme.primaryText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(CubeSkin.allCases) { skin in
                                Button {
                                    cubeSkinStore.apply(skin)
                                } label: {
                                    CubeSkinPickerTile(
                                        skin: skin,
                                        isSelected: cubeSkinStore.current == skin
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Sign out
                Button(action: signOut) {
                    Text("Sign Out")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(theme.primaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(theme.controlFill, in: Capsule())
                        .shadow(color: theme.shadow, radius: 10, x: 0, y: 6)
                }
                .padding(.top, 8)

                Spacer(minLength: 24) // bottom breathing room above scallops
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .scrollIndicators(.never)
    }

    // MARK: - Row components

    private var profileHeadModePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Profile Head")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(theme.primaryText)

            Picker("Profile Head", selection: $profileAvatarIs3D) {
                Text("2D").tag(false)
                Text("3D").tag(true)
            }
            .pickerStyle(.segmented)

            Text("Choose whether your profile uses the 2D speaking head or the 3D head.")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func settingsToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(theme.primaryText)
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: theme.accent))
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func settingsNavRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(theme.primaryText)
                Spacer(minLength: 12)
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(theme.accent)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    @MainActor
    private func applyPreviewStats() {
        posts = [
            Post(id: "preview-1", latitude: 43.6532, longitude: -79.3832, mediaURL: "", radius: 2_400, viewCount: 12, userID: "preview"),
            Post(id: "preview-2", latitude: 43.6618, longitude: -79.3956, mediaURL: "", radius: 4_800, viewCount: 8, userID: "preview"),
            Post(id: "preview-3", latitude: 43.6426, longitude: -79.3871, mediaURL: "", radius: 1_600, viewCount: 5, userID: "preview")
        ]
        isLoadingStats = false
    }

    private func loadStats() async {
        await MainActor.run { isLoadingStats = true }
        defer { Task { @MainActor in isLoadingStats = false } }

        guard let userId = Auth.auth().currentUser?.uid else {
            await MainActor.run {
                self.posts = []
            }
            return
        }

        do {
            let fetched = try await fetchUserPosts(uid: userId)
            await MainActor.run {
                let unique = Dictionary(grouping: fetched, by: { $0.id }).compactMap { $0.value.first }
                self.posts = unique
            }
        } catch {
            print("Stats fetch error: \(error.localizedDescription)")
            await MainActor.run {
                self.posts = []
            }
        }
    }

    private func fetchUserPosts(uid: String) async throws -> [Post] {
        try await withCheckedThrowingContinuation { cont in
            let db = FirebaseFirestore.Firestore.firestore()
            db.collection("posts").whereField("userID", isEqualTo: uid).getDocuments { snapshot, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard let snapshot else {
                    cont.resume(returning: [])
                    return
                }
                var out: [Post] = []
                out.reserveCapacity(snapshot.documents.count)
                for doc in snapshot.documents {
                    let data = doc.data()
                    let lat = (data["latitude"] as? Double) ?? (data["latitude"] as? NSNumber)?.doubleValue ?? 0
                    let lon = (data["longitude"] as? Double) ?? (data["longitude"] as? NSNumber)?.doubleValue ?? 0
                    let mediaURL = data["mediaURL"] as? String ?? ""
                    let radius = (data["radius"] as? Int) ?? (data["radius"] as? NSNumber)?.intValue ?? 0
                    let viewCount = (data["viewCount"] as? Int) ?? (data["viewCount"] as? NSNumber)?.intValue ?? 0
                    let userID = data["userID"] as? String ?? uid
                    out.append(Post(
                        id: doc.documentID,
                        latitude: lat,
                        longitude: lon,
                        mediaURL: mediaURL,
                        radius: radius,
                        viewCount: viewCount,
                        userID: userID
                    ))
                }
                let unique = Dictionary(grouping: out, by: { $0.id }).compactMap { $0.value.first }
                cont.resume(returning: unique)
            }
        }
    }
    
    /// Fetch up to a maximum number of the current user's posts (use for map display)
    private func fetchMyPostsForMap(maxCount: Int = 10) async throws -> [Post] {
        try await withCheckedThrowingContinuation { cont in
            guard let uid = Auth.auth().currentUser?.uid else {
                cont.resume(returning: [])
                return
            }
            let db = FirebaseFirestore.Firestore.firestore()
            // If you have a createdAt field, you can order by it to get most recent first
            db.collection("posts")
                .whereField("userID", isEqualTo: uid)
                .limit(to: maxCount)
                .getDocuments { snapshot, error in
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    guard let snapshot else {
                        cont.resume(returning: [])
                        return
                    }
                    var out: [Post] = []
                    out.reserveCapacity(snapshot.documents.count)
                    for doc in snapshot.documents {
                        let data = doc.data()
                        let lat = (data["latitude"] as? Double) ?? (data["latitude"] as? NSNumber)?.doubleValue ?? 0
                        let lon = (data["longitude"] as? Double) ?? (data["longitude"] as? NSNumber)?.doubleValue ?? 0
                        let mediaURL = data["mediaURL"] as? String ?? ""
                        let radius = (data["radius"] as? Int) ?? (data["radius"] as? NSNumber)?.intValue ?? 0
                        let viewCount = (data["viewCount"] as? Int) ?? (data["viewCount"] as? NSNumber)?.intValue ?? 0
                        let userID = data["userID"] as? String ?? uid
                        out.append(Post(
                            id: doc.documentID,
                            latitude: lat,
                            longitude: lon,
                            mediaURL: mediaURL,
                            radius: radius,
                            viewCount: viewCount,
                            userID: userID
                        ))
                    }
                    cont.resume(returning: out)
                }
        }
    }
    
    /// Returns true if the user has reached or exceeded the free post cap
    private func hasReachedFreePostCap(cap: Int = 10) async -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        do {
            let db = FirebaseFirestore.Firestore.firestore()
            let snapshot = try await db.collection("posts").whereField("userID", isEqualTo: uid).getDocuments()
            return snapshot.documents.count >= cap
        } catch {
            print("Count fetch error: \(error.localizedDescription)")
            return false
        }
    }

    private func signOut() {
        do { try Auth.auth().signOut() } catch {
            print("Sign out failed: \(error.localizedDescription)")
        }
    }

    private func formattedKM(_ meters: Int) -> String {
        let km = Double(meters) / 1000.0
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 0
        return (nf.string(from: NSNumber(value: km)) ?? "\(Int(km))") + " KM"
    }
    
    /// DEBUG: Fix posts with empty userID - assigns them to current user
    private func fixEmptyUserIDs() async {
        guard let currentUID = Auth.auth().currentUser?.uid else {
            print("❌ Cannot fix userIDs - not logged in")
            return
        }
        
        let db = Firestore.firestore()
        
        do {
            // Find all posts with empty userID
            let snapshot = try await db.collection("posts")
                .whereField("userID", isEqualTo: "")
                .getDocuments()
            
            print("🔧 Found \(snapshot.documents.count) posts with empty userID")
            
            // Update them to current user's UID
            for doc in snapshot.documents {
                try await doc.reference.updateData(["userID": currentUID])
                print("✅ Updated post \(doc.documentID) with userID: \(currentUID)")
            }
            
            print("🎉 Fixed all \(snapshot.documents.count) posts!")
            
            // Reload posts
            await loadStats()
        } catch {
            print("❌ Error fixing userIDs: \(error)")
        }
    }
}

private struct CubeSkinPickerTile: View {
    let skin: CubeSkin
    let isSelected: Bool

    private var theme: CubeSkinAppTheme { skin.appTheme }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Image(skin.appIconPreviewAssetName)
                    .resizable()
                    .scaledToFill()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(theme.badgeText)
                        .padding(8)
                        .background(Circle().fill(theme.badgeFill))
                }
            }
            .frame(width: 62, height: 62)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isSelected ? theme.accent : theme.border.opacity(0.45), lineWidth: isSelected ? 3 : 1)
            )

            Text(skin.displayName)
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundColor(isSelected ? theme.accent : CubeSkinStore.shared.current.appTheme.secondaryText)
                .lineLimit(1)
                .frame(width: 76)
        }
        .padding(.vertical, 4)
    }
}
