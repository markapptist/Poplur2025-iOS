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

    @State private var pageIndex: Int = 0
    @State private var isPrivateAccount = false
    @State private var notificationsEnabled = true

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

    private let brandPink = Color(red: 255.0/255.0, green: 255.0/255.0, blue: 255.0/255.0)

    init(initialPageIndex: Int = 0) {
        _pageIndex = State(initialValue: initialPageIndex)
    }

    var body: some View {
        ZStack {
            brandPink.ignoresSafeArea()

            VStack(spacing: 0) {
                // Start content at the very top – no top Spacer
                ScrollViewReader { proxy in
                    TicketCard(
                        pageIndex: $pageIndex,
                        isPrivateAccount: $isPrivateAccount,
                        notificationsEnabled: $notificationsEnabled,
                        isLoadingStats: $isLoadingStats,
                        statsHeaderTitle: "Statistics",
                        settingsHeaderTitle: "Settings",
                        statsPage: { statsPage.id("top") },
                        settingsPage: { settingsPage.id("top") },
                        brandPink: brandPink
                    )
                    .frame(width: ticketWidth, height: ticketHeight)
                    .onReceive(NotificationCenter.default.publisher(for: .ResetTabToTop)) { _ in
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo("top", anchor: .top)
                        }
                    }
                }
            }
        }
        .task {
            if layoutPreviewMode {
                applyPreviewStats()
            } else {
                await loadStats()
            }
            maxDurationDisplay = SettingsStore.shared.maxVideoDurationSeconds
        }
        .onAppear {
            if layoutPreviewMode {
                applyPreviewStats()
            } else {
                Task { await loadStats() }
            }
            maxDurationDisplay = SettingsStore.shared.maxVideoDurationSeconds
        }
    }

    // MARK: - Pages

    private var statsPage: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 20) {
                // Title
                Text("Average Radius")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity, alignment: .center)

                if isLoadingStats {
                    HStack {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.black)
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
                            accentColor: .black,
                            trackColor: .black.opacity(0.15),
                            lineWidthFactor: 0.12
                        )
                        .frame(height: 260)
                        .padding(.top, 35)
                        Spacer()
                    }
                    Text("Posts counted: \(posts.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(.black.opacity(0.6))
                    .padding(.bottom, 44)
                }

                VStack(alignment: .center, spacing: 8) {
                    Text("Accumulated Radius")
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .center)

                    if isLoadingStats {
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.black)
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    } else {
                        Text("You’ve reached")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.black.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text(formattedKM(totalRadius))
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Text("in total")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.black.opacity(0.9))
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
                    .foregroundColor(.black)
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Settings rows group
                VStack(spacing: 14) {
                    settingsToggleRow(title: "Private Account", isOn: $isPrivateAccount)
                    settingsToggleRow(title: "Notifications", isOn: $notificationsEnabled)
                    settingsToggleRow(
                        title: "HUD Sleep Timer",
                        isOn: Binding(
                            get: { SettingsStore.shared.hudSleepTimerEnabled },
                            set: { SettingsStore.shared.hudSleepTimerEnabled = $0 }
                        )
                    )
                    settingsNavRow(title: "Email Address") { /* push email editor */ }
                    settingsNavRow(title: "Password") { /* push password editor */ }
                }
                .frame(maxWidth: .infinity)

                // Video duration quick action
                VStack(alignment: .center, spacing: 8) {
                    Button {
                        SettingsStore.shared.maxVideoDurationSeconds = 10.0
                        maxDurationDisplay = 10.0
                    } label: {
                        Text("Limit videos to 10 seconds")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white, in: Capsule())
                    }

                    Text("Current limit: \(Int(maxDurationDisplay))s")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.black.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                // Dev actions (optional)
                VStack(spacing: 12) {
                    Button {
                        Task { await FakePostService.shared.seedInitialNorthAmerica(total: 1000) }
                    } label: {
                        Text("Seed NA (1000)")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white, in: Capsule())
                    }

                    Button {
                        FakePostService.shared.startWorldSimulator(devDailySeconds: 120)
                    } label: {
                        Text("Start Simulator (dev: 120s/day)")
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white, in: Capsule())
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

                // Sign out
                Button(action: signOut) {
                    Text("Sign Out")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white, in: Capsule())
                        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
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

    private func settingsToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.black)
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: Color(.systemIndigo)))
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func settingsNavRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                Text(title)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
                Spacer(minLength: 12)
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(.systemIndigo))
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
