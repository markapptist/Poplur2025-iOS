import SwiftUI
import FirebaseFirestore
import SpriteKit
import MapKit
import UIKit

struct ProfileStatsView: View {
    @Environment(\.layoutPreviewMode) private var layoutPreviewMode

    let userID: String

    @State private var posts: [Post] = []
    @State private var isLoading = true
    @State private var animatedProgress: Double = 0
    @State private var animatedRadiusKM: Double = 0

    private var totalRadiusMeters: Int {
        posts.reduce(0) { $0 + $1.radius }
    }

    private var totalRadiusKM: Double {
        Double(totalRadiusMeters) / 1000.0
    }

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
            Color.white.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header

                    if isLoading {
                        ProgressView()
                            .tint(.black)
                            .padding(.top, 90)
                    } else {
                        radiusRing
                        trophyRoom
                        dominanceMap
                        areaBreakdown
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.never)
        }
        .task {
            await loadStats()
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 6) {
            Text("Stats")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.black)
            Text("Radius ownership, city dominance, and trophies")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.black.opacity(0.56))
        }
        .frame(maxWidth: .infinity)
    }

    private var radiusRing: some View {
        VStack(spacing: 16) {
            AnimatedRadiusRing(
                progress: animatedProgress,
                radiusKM: animatedRadiusKM,
                goalKM: ringGoalKM
            )
            .frame(width: 260, height: 260)
            .padding(.top, 8)

            HStack(spacing: 12) {
                statPill(title: "Posts", value: "\(posts.count)", tint: .black)
                statPill(title: "Goal", value: formattedKM(ringGoalKM), tint: .cyan)
            }
        }
    }

    private var trophyRoom: some View {
        let unlockedCount = trophies.filter(\.isUnlocked).count
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Trophy Room")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                    Text("Earn trophies by leveling up on Poplur.")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.5))
                }
                Spacer()
                Text("\(unlockedCount)/\(trophies.count)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Color.yellow.opacity(0.18), in: Capsule())
            }

            ProfileTrophyRoomSpriteView(trophies: trophies)
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.10), lineWidth: 1)
                )
        }
    }

    private var dominanceMap: some View {
        let validPosts = posts.filter { abs($0.latitude) > 0.001 }
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("World Takeover")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                Spacer()
                Text("\(dominanceAreas.count) zones")
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(.black.opacity(0.55))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.06), in: Capsule())
            }

            ProfileDominanceRealMapView(posts: validPosts)
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )

            if validPosts.isEmpty {
                Text("Post from a location to start your world takeover.")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
        }
    }

    private var areaBreakdown: some View {
        VStack(spacing: 10) {
            ForEach(dominanceAreas) { area in
                HStack(spacing: 12) {
                    Circle()
                        .fill(area.color)
                        .frame(width: 13, height: 13)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(area.title)
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(.black)
                        Text("\(area.postCount) posts inside this zone")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.48))
                    }
                    Spacer()
                    Text("\(Int(round(area.percent)))%")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                }
                .padding(14)
                .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            if dominanceAreas.isEmpty {
                Text("No radius areas yet")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.black.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            }
        }
    }

    // MARK: - Helpers

    private func statPill(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black, design: .rounded))
                .foregroundStyle(.black.opacity(0.46))
            Text(value)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

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
            let lw = side * 0.11
            ZStack {
                Circle().stroke(Color.black.opacity(0.08), lineWidth: lw)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(colors: [.cyan, .mint, .yellow, .orange, .pink, .cyan], center: .center),
                        style: StrokeStyle(lineWidth: lw, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .cyan.opacity(0.32), radius: 12, x: 0, y: 6)
                VStack(spacing: 4) {
                    Text(fmt(radiusKM))
                        .font(.system(size: side * 0.18, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .contentTransition(.numericText())
                    Text("ACCUMULATED")
                        .font(.system(size: side * 0.052, weight: .black, design: .rounded))
                        .foregroundStyle(.black.opacity(0.5))
                    Text("\(Int(progress * 100))% of \(fmt(goalKM))")
                        .font(.system(size: side * 0.045, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black.opacity(0.42))
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
    let lockedHint: String
    let emoji: String
    let isUnlocked: Bool
    let displayColor: UIColor
    let tier: Int

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
                lockedHint: "Post from 3 different areas",
                emoji: "✈️",
                isUnlocked: uniqueBuckets.count >= 3,
                displayColor: UIColor(red: 0.12, green: 0.70, blue: 0.95, alpha: 1),
                tier: 2
            ),
        ]
    }
}

// MARK: - Trophy Room SpriteKit (sticker cards)

private struct ProfileTrophyRoomSpriteView: UIViewRepresentable {
    let trophies: [ProfileTrophy]

    func makeUIView(context: Context) -> SKView {
        let v = SKView()
        v.backgroundColor = .clear
        v.isOpaque = false
        v.ignoresSiblingOrder = true
        v.preferredFramesPerSecond = 60
        present(in: v)
        return v
    }

    func updateUIView(_ v: SKView, context: Context) {
        let key = trophies.map { $0.id + ($0.isUnlocked ? "1" : "0") }
        if let cur = v.scene as? ProfileTrophyRoomScene, cur.trophyKey == key { return }
        present(in: v)
    }

    private func present(in v: SKView) {
        let scene = ProfileTrophyRoomScene(trophies: trophies)
        scene.scaleMode = .aspectFill
        v.presentScene(scene)
    }
}

private final class ProfileTrophyRoomScene: SKScene {

    let trophyKey: [String]
    private let trophies: [ProfileTrophy]

    // Layout: 4 cols × 2 rows inside 390 × 420
    private let sceneW: CGFloat = 390
    private let sceneH: CGFloat = 420
    private let cols = 4
    private let cardW: CGFloat = 86
    private let cardH: CGFloat = 178

    // y-up: row 0 (top visually) has higher y
    private var rowY: [CGFloat] { [sceneH - 107, 107] }
    private var colX: [CGFloat] {
        (0..<cols).map { (CGFloat($0) + 0.5) * (sceneW / CGFloat(cols)) }
    }

    init(trophies: [ProfileTrophy]) {
        self.trophies = trophies
        self.trophyKey = trophies.map { $0.id + ($0.isUnlocked ? "1" : "0") }
        super.init(size: CGSize(width: 390, height: 420))
        backgroundColor = .clear
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        addBackground()
        addHeader()
        for (i, trophy) in trophies.enumerated() {
            guard i / cols < rowY.count else { continue }
            let card = makeCard(trophy: trophy, index: i)
            card.position = CGPoint(x: colX[i % cols], y: rowY[i / cols])
            addChild(card)
        }
    }

    // MARK: Background

    private func addBackground() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: sceneW, height: sceneH))
        let img = renderer.image { ctx in
            let c = ctx.cgContext
            let colors = [UIColor(red: 0.07, green: 0.06, blue: 0.13, alpha: 1).cgColor,
                          UIColor(red: 0.03, green: 0.03, blue: 0.07, alpha: 1).cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            c.drawLinearGradient(grad,
                start: CGPoint(x: 0, y: sceneH), end: .zero, options: [])
        }
        let bg = SKSpriteNode(texture: SKTexture(image: img))
        bg.position = CGPoint(x: sceneW / 2, y: sceneH / 2)
        bg.size = CGSize(width: sceneW, height: sceneH)
        bg.zPosition = -20
        addChild(bg)
    }

    private func addHeader() {
        let lbl = SKLabelNode(text: "✦  TROPHY ROOM  ✦")
        lbl.fontName = UIFont.systemFont(ofSize: 1, weight: .heavy).fontName
        lbl.fontSize = 10
        lbl.fontColor = UIColor.white.withAlphaComponent(0.20)
        lbl.horizontalAlignmentMode = .center
        lbl.verticalAlignmentMode = .center
        lbl.position = CGPoint(x: sceneW / 2, y: sceneH - 14)
        lbl.zPosition = 5
        addChild(lbl)
    }

    // MARK: Sticker Card

    private func makeCard(trophy: ProfileTrophy, index: Int) -> SKNode {
        let root = SKNode()
        let on = trophy.isUnlocked
        let tint = on ? trophy.displayColor : UIColor(white: 0.24, alpha: 1)

        // Card background
        let rect = CGRect(x: -cardW / 2, y: -cardH / 2, width: cardW, height: cardH)
        let bg = SKShapeNode(path: UIBezierPath(roundedRect: rect, cornerRadius: 16).cgPath)
        bg.fillColor   = on ? tint.withAlphaComponent(0.12) : UIColor(white: 0.10, alpha: 1)
        bg.strokeColor = on ? tint.withAlphaComponent(0.36) : UIColor(white: 0.20, alpha: 1)
        bg.lineWidth   = 1.5
        bg.zPosition   = 0
        root.addChild(bg)

        // Sticker circle
        let cR: CGFloat = 30
        let cY: CGFloat = cardH / 2 - cR - 14
        let circ = SKShapeNode(circleOfRadius: cR)
        circ.position   = CGPoint(x: 0, y: cY)
        circ.fillColor  = on ? tint.withAlphaComponent(0.17) : UIColor(white: 0.16, alpha: 1)
        circ.strokeColor = on ? tint.withAlphaComponent(0.45) : UIColor(white: 0.28, alpha: 1)
        circ.lineWidth  = 2
        circ.zPosition  = 1
        root.addChild(circ)

        // Emoji sticker — locked shows 🔒
        let emojiLabel = SKLabelNode(text: on ? trophy.emoji : "🔒")
        emojiLabel.fontSize = 28
        emojiLabel.horizontalAlignmentMode = .center
        emojiLabel.verticalAlignmentMode   = .center
        emojiLabel.position  = CGPoint(x: 0, y: cY)
        emojiLabel.zPosition = 2
        emojiLabel.alpha = on ? 1.0 : 0.40
        root.addChild(emojiLabel)

        // Title
        let titleY: CGFloat = cY - cR - 10
        let titleLbl = SKLabelNode(text: trophy.title)
        titleLbl.fontName = UIFont.systemFont(ofSize: 1, weight: .bold).fontName
        titleLbl.fontSize = 9.5
        titleLbl.fontColor = on ? .white : UIColor(white: 0.50, alpha: 1)
        titleLbl.horizontalAlignmentMode = .center
        titleLbl.verticalAlignmentMode   = .top
        titleLbl.position  = CGPoint(x: 0, y: titleY)
        titleLbl.zPosition = 2
        root.addChild(titleLbl)

        // Description / locked hint — multiline
        let descText = on ? trophy.description : trophy.lockedHint
        let descLbl = SKLabelNode(text: descText)
        descLbl.fontName = UIFont.systemFont(ofSize: 1, weight: .regular).fontName
        descLbl.fontSize = 7.5
        descLbl.fontColor = on ? UIColor(white: 0.70, alpha: 1) : UIColor(white: 0.36, alpha: 1)
        descLbl.horizontalAlignmentMode = .center
        descLbl.verticalAlignmentMode   = .top
        descLbl.numberOfLines = 4
        descLbl.preferredMaxLayoutWidth = cardW - 12
        descLbl.position  = CGPoint(x: 0, y: titleY - 13)
        descLbl.zPosition = 2
        root.addChild(descLbl)

        // Unlock indicator dot at bottom of card
        let dot = SKShapeNode(circleOfRadius: 3)
        dot.fillColor   = on ? tint : UIColor(white: 0.28, alpha: 1)
        dot.strokeColor = .clear
        dot.position    = CGPoint(x: 0, y: -cardH / 2 + 10)
        dot.zPosition   = 2
        root.addChild(dot)

        if on {
            // Outer glow ring
            let glow = SKShapeNode(circleOfRadius: cR + 9)
            glow.position    = CGPoint(x: 0, y: cY)
            glow.fillColor   = tint.withAlphaComponent(0.07)
            glow.strokeColor = tint.withAlphaComponent(0.11)
            glow.lineWidth   = 1
            glow.zPosition   = -1
            root.addChild(glow)

            // Floating animation — stagger by index so cards move at different phases
            let offset = Double(index % 4) * 0.30
            let up   = SKAction.moveBy(x: 0, y: 5, duration: 1.5 + Double(index % 3) * 0.12)
            let down = SKAction.moveBy(x: 0, y: -5, duration: 1.5 + Double(index % 3) * 0.12)
            up.timingMode = .easeInEaseOut
            down.timingMode = .easeInEaseOut
            root.run(.sequence([.wait(forDuration: offset), .repeatForever(.sequence([up, down]))]))

            // Sparkle emitter above sticker circle
            let emitter = SKEmitterNode()
            emitter.particleTexture       = Self.sparkleTexture
            emitter.particleBirthRate     = 1.6
            emitter.particleLifetime      = 1.4
            emitter.particleLifetimeRange = 0.5
            emitter.particleSpeed         = 14
            emitter.particleSpeedRange    = 8
            emitter.emissionAngle         = .pi / 2
            emitter.emissionAngleRange    = .pi * 2
            emitter.particleScale         = 0.04
            emitter.particleScaleRange    = 0.02
            emitter.particleScaleSpeed    = -0.025
            emitter.particleAlpha         = 0.85
            emitter.particleAlphaSpeed    = -0.55
            emitter.particleColor              = tint
            emitter.particleColorBlendFactor   = 1.0
            emitter.particleBlendMode          = .add
            emitter.position  = CGPoint(x: 0, y: cY + cR + 4)
            emitter.zPosition = 3
            root.addChild(emitter)
        }

        return root
    }

    // Shared soft-circle particle texture for sparkles
    private static let sparkleTexture: SKTexture = {
        let sz = CGSize(width: 12, height: 12)
        let img = UIGraphicsImageRenderer(size: sz).image { ctx in
            let c = ctx.cgContext
            let colors = [UIColor.white.cgColor,
                          UIColor.white.withAlphaComponent(0).cgColor] as CFArray
            let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                  colors: colors, locations: [0.0, 1.0])!
            c.drawRadialGradient(grad,
                startCenter: CGPoint(x: 6, y: 6), startRadius: 0,
                endCenter:   CGPoint(x: 6, y: 6), endRadius:   6,
                options: [])
        }
        return SKTexture(image: img)
    }()
}

// MARK: - Dominance Area Model

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

// MARK: - Real-World Dominance Map (MapKit)

private struct ProfileDominanceRealMapView: UIViewRepresentable {
    let posts: [Post]

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType          = .standard
        map.isScrollEnabled  = false
        map.isZoomEnabled    = false
        map.isRotateEnabled  = false
        map.isPitchEnabled   = false
        map.showsUserLocation = false
        map.showsCompass     = false
        map.showsScale       = false
        map.delegate = context.coordinator
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        map.removeOverlays(map.overlays)

        guard !posts.isEmpty else {
            // Default world view when no posts yet
            map.setRegion(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 130, longitudeDelta: 200)
            ), animated: false)
            return
        }

        // One circle overlay per post — radius is the post's real radius footprint
        for post in posts {
            let coord  = CLLocationCoordinate2D(latitude: post.latitude, longitude: post.longitude)
            let radius = Double(max(post.radius, 8_000)) // 8 KM minimum to remain visible
            map.addOverlay(MKCircle(center: coord, radius: radius), level: .aboveRoads)
        }

        // Auto-fit the visible rect to encompass every circle with padding
        var rect = MKMapRect.null
        for overlay in map.overlays { rect = rect.union(overlay.boundingMapRect) }
        let pad = 0.38
        map.setVisibleMapRect(
            rect.insetBy(dx: -rect.size.width * pad, dy: -rect.size.height * pad),
            animated: false
        )
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        // Color gradient: more radius → deeper blue; each circle uses indigo fill
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let circle = overlay as? MKCircle else { return MKOverlayRenderer(overlay: overlay) }
            let r = MKCircleRenderer(circle: circle)
            r.fillColor   = UIColor(red: 0.18, green: 0.42, blue: 1.00, alpha: 0.18)
            r.strokeColor = UIColor(red: 0.18, green: 0.42, blue: 1.00, alpha: 0.80)
            r.lineWidth   = 2.5
            return r
        }
    }
}
