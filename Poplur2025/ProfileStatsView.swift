import SwiftUI
import FirebaseFirestore
import UIKit

// MARK: - Design palette (sampled from the Stats mockup)

private enum StatsC {
    static let pageBG      = Color(red: 253/255, green: 237/255, blue: 243/255) // #FDEDF3
    static let title       = Color(red: 18/255,  green: 19/255,  blue: 26/255)
    static let subtitle    = Color(red: 124/255, green: 122/255, blue: 133/255)
    static let accent      = Color(red: 255/255, green: 45/255,  blue: 130/255) // #FF2D82
    static let ringTrack   = Color(red: 246/255, green: 222/255, blue: 233/255) // #F6DEE9
    static let postsCard   = Color(red: 254/255, green: 239/255, blue: 246/255) // #FEEFF6
    static let goalCard    = Color(red: 242/255, green: 242/255, blue: 254/255) // #F2F2FE
    static let goalLabel   = Color(red: 91/255,  green: 91/255,  blue: 214/255) // indigo
    static let panelBG     = Color(red: 14/255,  green: 16/255,  blue: 20/255)  // #0E1014
    static let cardBG      = Color(red: 28/255,  green: 31/255,  blue: 40/255)  // #1C1F28
    static let badgePill   = Color(red: 255/255, green: 227/255, blue: 172/255) // #FFE3AC
    static let trophyNote  = Color(red: 156/255, green: 129/255, blue: 137/255)
}

struct ProfileStatsView: View {
    @Environment(\.layoutPreviewMode) private var layoutPreviewMode

    let userID: String

    @State private var posts: [Post] = []
    @State private var isLoading = true
    @State private var animatedProgress: Double = 0
    @State private var animatedRadiusKM: Double = 0

    private var totalRadiusMeters: Int { posts.reduce(0) { $0 + $1.radius } }
    private var totalRadiusKM: Double { Double(totalRadiusMeters) / 1000.0 }

    private var ringGoalKM: Double {
        max(10_000, ceil(max(totalRadiusKM, 1) / 5_000) * 5_000)
    }

    private var dominanceAreas: [ProfileDominanceArea] {
        ProfileDominanceArea.make(from: posts)
    }

    private var trophies: [ProfileTrophy] {
        ProfileTrophy.make(posts: posts, dominanceAreas: dominanceAreas, totalRadiusKM: totalRadiusKM)
    }

    var body: some View {
        ZStack {
            StatsC.pageBG.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    header

                    if isLoading {
                        ProgressView()
                            .tint(StatsC.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 90)
                    } else {
                        radiusRing
                            .frame(maxWidth: .infinity)
                        statCards
                        trophyRoom
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.never)
        }
        .task { await loadStats() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    // Same icon shown in the hold-menu wheel that opens this screen.
                    HoldMenuIconBadge(icon: HoldMenuIcons.stats, size: 44)
                    Text("Stats")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(StatsC.title)
                }
                Text("Radius ownership,\ncity dominance,\nand trophies")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(StatsC.subtitle)
                    .lineSpacing(3)
            }
            Spacer(minLength: 8)
            Image("stats_sphere")
                .resizable()
                .scaledToFit()
                .frame(width: 130, height: 130)
                .offset(y: -6)
        }
    }

    // MARK: - Ring

    private var radiusRing: some View {
        AnimatedRadiusRing(
            progress: animatedProgress,
            radiusKM: animatedRadiusKM,
            goalKM: ringGoalKM
        )
        .frame(width: 290, height: 290)
    }

    // MARK: - Posts / Goal cards

    private var statCards: some View {
        HStack(spacing: 14) {
            statCard(
                icon: "stats_ic_posts",
                label: "POSTS",
                labelColor: StatsC.accent,
                value: "\(posts.count)",
                background: StatsC.postsCard
            )
            statCard(
                icon: "stats_ic_goal",
                label: "GOAL",
                labelColor: StatsC.goalLabel,
                value: formattedKM(ringGoalKM),
                background: StatsC.goalCard
            )
        }
    }

    private func statCard(
        icon: String,
        label: String,
        labelColor: Color,
        value: String,
        background: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(labelColor)
                Text(value)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(StatsC.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Trophy room

    private var trophyRoom: some View {
        let unlockedCount = trophies.filter(\.isUnlocked).count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("Trophy Room")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(StatsC.title)
                Spacer()
                Text("\(unlockedCount)/\(trophies.count)")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(StatsC.title)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(StatsC.badgePill, in: Capsule())
            }

            Text("Earn trophies by leveling up on Poplur.")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(StatsC.trophyNote)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(trophies) { trophy in
                        trophyCard(trophy)
                    }
                }
                .padding(14)
            }
            .background(StatsC.panelBG, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func trophyCard(_ trophy: ProfileTrophy) -> some View {
        let tint = Color(trophy.displayColor)
        let on = trophy.isUnlocked
        let accentColor = on ? tint : Color(white: 0.42)

        return VStack(spacing: 12) {
            trophyIcon(trophy)
                .frame(width: 84, height: 84)

            Text(trophy.title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(on ? .white : Color(white: 0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(on ? trophy.shortDescription : trophy.lockedHint)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Color(white: on ? 0.78 : 0.5))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(height: 36, alignment: .top)

            Circle()
                .fill(accentColor)
                .frame(width: 9, height: 9)
                .padding(.top, 2)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 10)
        .frame(width: 152)
        .background(StatsC.cardBG, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accentColor.opacity(on ? 0.85 : 0.35), lineWidth: 1.5)
        )
    }

    /// Locked trophies always show the padlock art from the mockup.
    /// Unlocked trophies use their own extracted art where one exists,
    /// otherwise fall back to the trophy's tinted circle + emoji.
    @ViewBuilder
    private func trophyIcon(_ trophy: ProfileTrophy) -> some View {
        if !trophy.isUnlocked {
            Image("stats_tr_city").resizable().scaledToFit()
        } else if let asset = trophy.unlockedIconAsset {
            Image(asset).resizable().scaledToFit()
        } else {
            ZStack {
                Circle().fill(Color(trophy.displayColor))
                Text(trophy.emoji).font(.system(size: 34))
            }
        }
    }

    // MARK: - Data

    private func loadStats() async {
        await MainActor.run {
            isLoading = true
            animatedProgress = 0
            animatedRadiusKM = 0
        }

        let fetched: [Post] = layoutPreviewMode ? Self.previewPosts : await fetchUserPosts()

        await MainActor.run {
            posts = fetched
            isLoading = false
            withAnimation(.easeOut(duration: 1.2)) {
                animatedProgress = min(1, totalRadiusKM / ringGoalKM)
                animatedRadiusKM = totalRadiusKM
            }
        }
    }

    private func fetchUserPosts() async -> [Post] {
        await withCheckedContinuation { continuation in
            Firestore.firestore()
                .collection("posts")
                .whereField("userID", isEqualTo: userID)
                .getDocuments { snapshot, error in
                    if let error {
                        print("Profile stats fetch error: \(error.localizedDescription)")
                        continuation.resume(returning: [])
                        return
                    }
                    let posts = snapshot?.documents.map { doc -> Post in
                        let data = doc.data()
                        let lat = (data["latitude"] as? Double) ?? (data["latitude"] as? NSNumber)?.doubleValue ?? 0
                        let lon = (data["longitude"] as? Double) ?? (data["longitude"] as? NSNumber)?.doubleValue ?? 0
                        let radius = (data["radius"] as? Int) ?? (data["radius"] as? NSNumber)?.intValue ?? 0
                        let viewCount = (data["viewCount"] as? Int) ?? (data["viewCount"] as? NSNumber)?.intValue ?? 0
                        return Post(
                            id: doc.documentID,
                            latitude: lat,
                            longitude: lon,
                            mediaURL: data["mediaURL"] as? String ?? "",
                            radius: radius,
                            viewCount: viewCount,
                            userID: userID,
                            posterURL: data["posterURL"] as? String
                        )
                    } ?? []
                    let unique = Dictionary(grouping: posts, by: \.id).compactMap { $0.value.first }
                    continuation.resume(returning: unique)
                }
        }
    }

    private func formattedKM(_ km: Double) -> String {
        if km >= 1_000_000 { return String(format: "%.1fM KM", km / 1_000_000) }
        if km >= 1_000 { return String(format: "%.0fK KM", km / 1_000) }
        return String(format: "%.0f KM", km)
    }

    private static let previewPosts: [Post] = [
        Post(id: "s1", latitude: 43.6532, longitude: -79.3832, mediaURL: "", radius: 120_000, viewCount: 180,  userID: "preview"),
        Post(id: "s2", latitude: 43.6608, longitude: -79.3956, mediaURL: "", radius: 340_000, viewCount: 420,  userID: "preview"),
        Post(id: "s3", latitude: 51.5074, longitude: -0.1278,  mediaURL: "", radius: 210_000, viewCount: 1200, userID: "preview"),
        Post(id: "s4", latitude: 40.7128, longitude: -74.0060, mediaURL: "", radius: 480_000, viewCount: 550,  userID: "preview"),
        Post(id: "s5", latitude: 35.6762, longitude: 139.6503, mediaURL: "", radius: 165_000, viewCount: 120,  userID: "preview"),
    ]
}

// MARK: - Animated Radius Ring

private struct AnimatedRadiusRing: View {
    let progress: Double
    let radiusKM: Double
    let goalKM: Double

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let lw = side * 0.135
            ZStack {
                Circle().stroke(StatsC.ringTrack, lineWidth: lw)
                Circle()
                    .trim(from: 0, to: max(progress, 0.0001))
                    .stroke(
                        StatsC.accent,
                        style: StrokeStyle(lineWidth: lw, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: StatsC.accent.opacity(0.28), radius: 10, x: 0, y: 5)

                VStack(spacing: 6) {
                    Text(fmt(radiusKM))
                        .font(.system(size: side * 0.21, weight: .black, design: .rounded))
                        .foregroundStyle(StatsC.title)
                        .contentTransition(.numericText())
                    Text("ACCUMULATED")
                        .font(.system(size: side * 0.058, weight: .black, design: .rounded))
                        .foregroundStyle(StatsC.accent)
                    Text("\(Int(progress * 100))% of \(fmt(goalKM))")
                        .font(.system(size: side * 0.058, weight: .semibold, design: .rounded))
                        .foregroundStyle(StatsC.title.opacity(0.72))
                }
                .minimumScaleFactor(0.7)
            }
        }
    }

    private func fmt(_ km: Double) -> String {
        if km >= 1_000_000 { return String(format: "%.1fM", km / 1_000_000) }
        if km >= 1_000     { return String(format: "%.0fK", km / 1_000) }
        return String(format: "%.0f", km)
    }
}

// MARK: - Trophy Model

private struct ProfileTrophy: Identifiable {
    let id: String
    let title: String
    let description: String
    let shortDescription: String
    let lockedHint: String
    let emoji: String
    let isUnlocked: Bool
    let displayColor: UIColor
    let tier: Int

    /// Art sliced from the Stats mockup, where the design provides it.
    var unlockedIconAsset: String? {
        switch id {
        case "first-post":  return "stats_tr_first"
        case "five-posts":  return "stats_tr_streak"
        case "radius-100":  return "stats_tr_orbit"
        default:            return nil
        }
    }

    static func make(posts: [Post], dominanceAreas: [ProfileDominanceArea], totalRadiusKM: Double) -> [ProfileTrophy] {
        let totalViews = posts.reduce(0) { $0 + $1.viewCount }
        let maxRadius  = posts.map(\.radius).max() ?? 0
        let uniqueBuckets = Set(posts.map {
            "\(Int(($0.latitude  * 10).rounded())):\(Int(($0.longitude * 10).rounded()))"
        })

        return [
            ProfileTrophy(
                id: "first-post",
                title: "First Signal",
                description: "Your first broadcast went out. Someone, somewhere, received it.",
                shortDescription: "Broadcast sent out.",
                lockedHint: "Make your first post",
                emoji: "📡",
                isUnlocked: posts.count >= 1,
                displayColor: UIColor(red: 1.00, green: 0.73, blue: 0.22, alpha: 1),
                tier: 1
            ),
            ProfileTrophy(
                id: "five-posts",
                title: "Creator Streak",
                description: "Five transmissions deep. Your signal is becoming a frequency.",
                shortDescription: "5 transmissions deep.",
                lockedHint: "Post 5 times",
                emoji: "🔥",
                isUnlocked: posts.count >= 5,
                displayColor: UIColor(red: 1.00, green: 0.48, blue: 0.18, alpha: 1),
                tier: 2
            ),
            ProfileTrophy(
                id: "radius-100",
                title: "Orbit Starter",
                description: "100 KM of owned airspace. You have claimed your first real territory.",
                shortDescription: "100 KM of owned space.",
                lockedHint: "Reach 100 KM total radius",
                emoji: "🛸",
                isUnlocked: totalRadiusKM >= 100,
                displayColor: UIColor(red: 0.35, green: 0.78, blue: 1.00, alpha: 1),
                tier: 1
            ),
            ProfileTrophy(
                id: "radius-1000",
                title: "City Builder",
                description: "A thousand kilometers stacked. You are reshaping the map around you.",
                shortDescription: "Reach 1,000 KM total radius.",
                lockedHint: "Reach 1,000 KM total radius",
                emoji: "🏙️",
                isUnlocked: totalRadiusKM >= 1_000,
                displayColor: UIColor(red: 1.00, green: 0.48, blue: 0.78, alpha: 1),
                tier: 3
            ),
            ProfileTrophy(
                id: "views-1000",
                title: "Crowd Pull",
                description: "A thousand eyes on your content. The audience has found you.",
                shortDescription: "1,000 total views.",
                lockedHint: "Get 1,000 total views",
                emoji: "👁️",
                isUnlocked: totalViews >= 1_000,
                displayColor: UIColor(red: 0.74, green: 0.55, blue: 1.00, alpha: 1),
                tier: 2
            ),
            ProfileTrophy(
                id: "wide-radius",
                title: "Wide Reach",
                description: "One post spanning 250 KM. A single transmission, massive coverage.",
                shortDescription: "One post spanning 250 KM.",
                lockedHint: "One post with 250 KM radius",
                emoji: "🌐",
                isUnlocked: maxRadius >= 250_000,
                displayColor: UIColor(red: 0.20, green: 0.82, blue: 0.60, alpha: 1),
                tier: 2
            ),
            ProfileTrophy(
                id: "three-zones",
                title: "Zone Collector",
                description: "Three zones under your control. The map is turning your color.",
                shortDescription: "Dominate 3 map zones.",
                lockedHint: "Dominate 3 map zones",
                emoji: "🗺️",
                isUnlocked: dominanceAreas.count >= 3,
                displayColor: UIColor(red: 0.58, green: 0.92, blue: 0.32, alpha: 1),
                tier: 3
            ),
            ProfileTrophy(
                id: "traveler",
                title: "Map Traveler",
                description: "Posts dropped across the globe. You are always in motion.",
                shortDescription: "Post from 3 areas.",
                lockedHint: "Post from 3 different areas",
                emoji: "✈️",
                isUnlocked: uniqueBuckets.count >= 3,
                displayColor: UIColor(red: 0.12, green: 0.70, blue: 0.95, alpha: 1),
                tier: 2
            ),
        ]
    }
}

// MARK: - Dominance Area Model (still drives the Zone Collector trophy)

private struct ProfileDominanceArea: Identifiable {
    let id: String
    let title: String
    let percent: Double
    let postCount: Int
    let color: Color

    static func make(from posts: [Post]) -> [ProfileDominanceArea] {
        let valid = posts.filter { $0.latitude != 0 || $0.longitude != 0 }
        guard !valid.isEmpty else { return [] }

        let totalWeight = max(1, valid.reduce(0.0) { $0 + Double(max($1.radius, 1)) })
        let minLat = valid.map(\.latitude).min()!
        let maxLat = valid.map(\.latitude).max()!
        let minLon = valid.map(\.longitude).min()!
        let maxLon = valid.map(\.longitude).max()!
        let latSpan = max(maxLat - minLat, 0.0001)
        let lonSpan = max(maxLon - minLon, 0.0001)

        struct Bucket { var weight: Double = 0; var postCount: Int = 0 }
        var buckets: [String: Bucket] = [:]
        for post in valid {
            let nx  = (post.longitude - minLon) / lonSpan
            let ny  = 1 - ((post.latitude - minLat) / latSpan)
            let col = min(2, max(0, Int(nx * 3)))
            let row = min(2, max(0, Int(ny * 3)))
            let key = "\(row)-\(col)"
            let w   = Double(max(post.radius, 1))
            var b   = buckets[key] ?? Bucket()
            b.weight += w; b.postCount += 1
            buckets[key] = b
        }

        let names  = [["Northwest","North","Northeast"],["West","Central","East"],["Southwest","South","Southeast"]]
        let palette: [Color] = [.cyan, .mint, .yellow, .orange, .pink, .indigo, .teal, .purple]

        return buckets.map { key, b in
            let parts = key.split(separator: "-").compactMap { Int($0) }
            let row = parts.first ?? 1; let col = parts.dropFirst().first ?? 1
            return ProfileDominanceArea(
                id: key,
                title: names[row][col],
                percent: (b.weight / totalWeight) * 100,
                postCount: b.postCount,
                color: palette[(row * 3 + col) % palette.count]
            )
        }
        .sorted { $0.percent > $1.percent }
    }
}
