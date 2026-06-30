//
//  FeedTwitterTimelineView.swift
//  Poplur2025
//
//  Poplur Newspaper — AI-powered feed of map events, trending cities,
//  area dominance leaders, and user posts. Replaces the old fake-tweet view.
//

import SwiftUI
import UIKit
import MapKit
import AVFoundation

// MARK: - Article models

struct MapEventArticle: Identifiable {
    let id = UUID()
    let city: String
    let flag: String
    let headline: String
    let detail: String
    let userCount: Int
    let latitude: Double
    let longitude: Double
    let timeAgo: String
}

struct TrendingCityArticle: Identifiable {
    let id = UUID()
    let city: String
    let flag: String
    let headline: String
    let detail: String
    let growthPercent: Int
    let activeUsers: Int
    let latitude: Double
    let longitude: Double
    let timeAgo: String
}

struct DominanceArticle: Identifiable {
    let id = UUID()
    let username: String
    let city: String
    let flag: String
    let headline: String
    let detail: String
    let radiusText: String
    let score: Int
    let latitude: Double
    let longitude: Double
    let timeAgo: String
}

struct UserPostArticle: Identifiable {
    let id = UUID()
    let username: String
    let city: String
    let flag: String
    let headline: String
    let detail: String
    let likes: Int
    let comments: Int
    let latitude: Double
    let longitude: Double
    let timeAgo: String
    let mediaURL: String?
}

enum NewspaperSection {
    case mapEvent(MapEventArticle)
    case trending(TrendingCityArticle)
    case dominance(DominanceArticle)
    case userPost(UserPostArticle)
}

// MARK: - Article narrator (AVSpeechSynthesizer wrapper)

@MainActor
private final class NewsNarrator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var highlightedRange: NSRange? = nil
    @Published private(set) var isSpeaking = false

    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) {
        synth.stopSpeaking(at: .immediate)
        highlightedRange = nil
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.50
        utterance.volume = 1.0
        isSpeaking = true
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        highlightedRange = nil
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        Task { @MainActor in self.highlightedRange = characterRange }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.highlightedRange = nil; self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.highlightedRange = nil; self.isSpeaking = false }
    }
}

// MARK: - Word-level highlight text

private struct HighlightedText: View {
    let text: String
    let textOffset: Int        // byte offset of `text` within the full spoken string
    let highlightedRange: NSRange?
    let font: Font
    let baseColor: Color

    var body: some View {
        Text(attributedString)
            .poplurTextShader(intensity: 0.58)
    }

    private var attributedString: AttributedString {
        var result = AttributedString(text)
        result.font = font
        result.foregroundColor = baseColor

        guard let global = highlightedRange else { return result }

        let localLoc = global.location - textOffset
        guard localLoc >= 0 else { return result }
        let localRange = NSRange(location: localLoc, length: global.length)
        let nsText = text as NSString
        guard localRange.upperBound <= nsText.length else { return result }
        guard let swiftRange = Range(localRange, in: text),
              let lower = AttributedString.Index(swiftRange.lowerBound, within: result),
              let upper = AttributedString.Index(swiftRange.upperBound, within: result)
        else { return result }

        result[lower..<upper].backgroundColor = Color(red: 1.0, green: 0.85, blue: 0.10)
        result[lower..<upper].foregroundColor = .black
        return result
    }
}

// MARK: - Main view (drop-in replacement — same init signature)

struct FeedTwitterTimelineView: View {
    let posts: [FeedPost]
    let displayNameProvider: (FeedPost) -> String
    let onPostTapped: (Int) -> Void

    @State private var articles: [NewspaperSection] = []
    @State private var currentArticleIndex: Int = 0
    @State private var hapticGenerator = UIImpactFeedbackGenerator(style: .rigid)
    @State private var popPlayer: AVAudioPlayer? = nil
    @StateObject private var narrator = NewsNarrator()

    private static let today: String = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f.string(from: Date())
    }()

    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(articles.enumerated()), id: \.offset) { index, article in
                        NewspaperArticleCard(
                            section: article,
                            edition: "No. \(index + 1)",
                            date: Self.today,
                            onLongPress: { showMapForArticle(article) },
                            highlightedRange: index == currentArticleIndex ? narrator.highlightedRange : nil
                        )
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(index)
                        .onAppear {
                            if index == articles.count - 3 { generateMoreArticles() }
                        }
                    }
                }
                .scrollTargetLayout()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: NewspaperScrollOffsetKey.self,
                            value: proxy.frame(in: .named("newsScroll")).origin.y
                        )
                    }
                )
            }
            .coordinateSpace(name: "newsScroll")
            .scrollTargetBehavior(.paging)
            .scrollBounceBehavior(.basedOnSize)
            .onPreferenceChange(NewspaperScrollOffsetKey.self) { offset in
                let newIndex = Int(round(-offset / geometry.size.height))
                guard newIndex != currentArticleIndex,
                      newIndex >= 0, newIndex < articles.count else { return }
                currentArticleIndex = newIndex
                hapticGenerator.impactOccurred(intensity: 0.7)
                playPop()
                narrator.speak(spokenText(for: articles[newIndex]))
            }
            .ignoresSafeArea()
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            hapticGenerator.prepare()
            if articles.isEmpty {
                generateInitialArticles()
                if let first = articles.first {
                    narrator.speak(spokenText(for: first))
                }
            }
        }
        .onDisappear {
            narrator.stop()
        }
    }

    // MARK: - Helpers

    private func spokenText(for section: NewspaperSection) -> String {
        switch section {
        case .mapEvent(let a):   return "\(a.headline). \(a.detail)"
        case .trending(let a):   return "\(a.headline). \(a.detail)"
        case .dominance(let a):  return "\(a.headline). \(a.detail)"
        case .userPost(let a):   return "\(a.headline). \(a.detail)"
        }
    }

    private func showMapForArticle(_ article: NewspaperSection) {
        let (lat, lon): (Double, Double) = {
            switch article {
            case .mapEvent(let a):  return (a.latitude, a.longitude)
            case .trending(let a):  return (a.latitude, a.longitude)
            case .dominance(let a): return (a.latitude, a.longitude)
            case .userPost(let a):  return (a.latitude, a.longitude)
            }
        }()
        Task { @MainActor in
            NotificationCenter.default.post(
                name: Notification.Name("FeedFlyToCoordinate"),
                object: nil,
                userInfo: ["coordinate": CLLocationCoordinate2D(latitude: lat, longitude: lon)]
            )
        }
    }

    private func generateInitialArticles() {
        articles = NewspaperGenerator.generate(
            posts: posts,
            displayNameProvider: displayNameProvider,
            startIndex: 0,
            count: 10
        )
    }

    private func generateMoreArticles() {
        articles.append(contentsOf: NewspaperGenerator.generate(
            posts: posts,
            displayNameProvider: displayNameProvider,
            startIndex: articles.count,
            count: 8
        ))
    }

    private func playPop() {
        guard let url = Bundle.main.url(forResource: "pop", withExtension: "mp3")
                     ?? Bundle.main.url(forResource: "pop", withExtension: "wav") else { return }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.numberOfLoops = 0
        player.volume = 0.9
        player.prepareToPlay()
        player.play()
        popPlayer = player
    }
}

// MARK: - Scroll offset preference key

private struct NewspaperScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Map snapshot helpers

private final class MapSnapshotCache: @unchecked Sendable {
    static let shared = MapSnapshotCache()
    private var dict: [String: UIImage] = [:]
    private let lock = NSLock()

    func get(_ key: String) -> UIImage? { lock.lock(); defer { lock.unlock() }; return dict[key] }
    func set(_ key: String, _ img: UIImage) { lock.lock(); defer { lock.unlock() }; dict[key] = img }
}

private struct MapSnapshotImage: View {
    let latitude: Double
    let longitude: Double
    let mapType: MKMapType
    let tint: Color?

    @State private var snapshot: UIImage?

    var body: some View {
        ZStack {
            if let img = snapshot {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
                if let t = tint { t.opacity(0.28) }
            } else {
                Color(red: 0.06, green: 0.06, blue: 0.12)
                ProgressView().tint(.white.opacity(0.35))
            }
        }
        .task(id: "\(latitude)\(longitude)\(mapType.rawValue)") {
            let key = "\(latitude)_\(longitude)_\(mapType.rawValue)"
            if let cached = MapSnapshotCache.shared.get(key) { snapshot = cached; return }
            let opts = MKMapSnapshotter.Options()
            opts.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            )
            opts.size = CGSize(width: 420, height: 180)
            opts.mapType = mapType
            let img: UIImage? = await withCheckedContinuation { cont in
                MKMapSnapshotter(options: opts).start { r, _ in cont.resume(returning: r?.image) }
            }
            guard let img else { return }
            MapSnapshotCache.shared.set(key, img)
            snapshot = img
        }
    }
}

private enum NewspaperVisualStyle {
    case mapEvent
    case trending
    case dominance
    case userPost
}

private struct NewspaperGeneratedVisual: View {
    let style: NewspaperVisualStyle
    let latitude: Double
    let longitude: Double
    let city: String
    let flag: String
    let headline: String
    let accent: Color
    let username: String?
    let mediaURL: String?

    private var mapType: MKMapType {
        switch style {
        case .mapEvent: return .hybridFlyover
        case .trending: return .standard
        case .dominance: return .satellite
        case .userPost: return .mutedStandard
        }
    }

    private var fallbackTint: Color? {
        switch style {
        case .userPost: return nil
        default: return accent
        }
    }

    private var visualLabel: String {
        switch style {
        case .dominance: return "LIVE MAP CAPTURE"
        case .userPost: return "AI STORY IMAGE"
        default: return "AI GENERATED"
        }
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background

            LinearGradient(
                colors: [.black.opacity(0.05), .black.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )

            NewspaperVisualOverlay(
                style: style,
                seed: "\(headline)-\(city)-\(username ?? "")",
                accent: accent
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    Text(visualLabel)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(style == .dominance ? .white : .black)
                        .poplurTextShader(intensity: 0.56)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(accent)
                        .clipShape(Capsule())

                    Text("\(flag) \(city)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.72))
                        .poplurTextShader(intensity: 0.54)
                }

                if style == .dominance, let username {
                    Text("@\(username) territory lock")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .poplurTextShader(intensity: 0.68)
                        .lineLimit(1)
                } else {
                    Text(headline)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .poplurTextShader(intensity: 0.62)
                        .lineLimit(2)
                }
            }
            .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 3)
            .padding(14)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var background: some View {
        if style == .userPost, let assetName = localAssetName(from: mediaURL), let image = UIImage(named: assetName) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .saturation(1.25)
                .contrast(1.08)
        } else if style == .userPost, let mediaURL, let url = URL(string: mediaURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .saturation(1.25)
                        .contrast(1.08)
                default:
                    MapSnapshotImage(
                        latitude: latitude,
                        longitude: longitude,
                        mapType: mapType,
                        tint: fallbackTint
                    )
                }
            }
        } else {
            MapSnapshotImage(
                latitude: latitude,
                longitude: longitude,
                mapType: mapType,
                tint: fallbackTint
            )
        }
    }

    private func localAssetName(from mediaURL: String?) -> String? {
        let prefix = "asset://"
        guard let mediaURL, mediaURL.hasPrefix(prefix) else { return nil }
        let name = String(mediaURL.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

private struct NewspaperVisualOverlay: View {
    let style: NewspaperVisualStyle
    let seed: String
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let seedValue = NewspaperVisualSeed.value(for: seed)
            let base = min(size.width, size.height)
            drawLightBeams(in: context, size: size, seed: seedValue)

            switch style {
            case .dominance:
                drawTakeoverRings(in: context, size: size, base: base, seed: seedValue)
            case .mapEvent:
                drawSignalCluster(in: context, size: size, base: base, seed: seedValue)
            case .trending:
                drawTrendGrid(in: context, size: size, base: base, seed: seedValue)
            case .userPost:
                drawStoryParticles(in: context, size: size, base: base, seed: seedValue)
            }
        }
    }

    private func drawLightBeams(in context: GraphicsContext, size: CGSize, seed: UInt64) {
        for index in 0..<4 {
            let phase = CGFloat((seed >> UInt64(index * 6)) & 63) / 63
            var path = Path()
            let x = size.width * (0.12 + phase * 0.76)
            path.move(to: CGPoint(x: x, y: -18))
            path.addLine(to: CGPoint(x: x + CGFloat(index - 1) * 38, y: size.height + 24))
            context.stroke(path, with: .color(.white.opacity(0.08)), lineWidth: 1.2)
        }
    }

    private func drawTakeoverRings(in context: GraphicsContext, size: CGSize, base: CGFloat, seed: UInt64) {
        let center = CGPoint(x: size.width * 0.58, y: size.height * 0.46)
        for index in 0..<4 {
            let radius = base * (0.18 + CGFloat(index) * 0.16)
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(accent.opacity(0.95 - Double(index) * 0.16)), lineWidth: index == 0 ? 4 : 2)
        }

        for index in 0..<9 {
            let angle = CGFloat(index) / 9 * .pi * 2 + CGFloat(seed % 29) / 29
            let radius = base * (0.24 + CGFloat((seed >> UInt64(index)) & 7) / 60)
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(.white.opacity(0.75)))
            context.stroke(Path { path in
                path.move(to: center)
                path.addLine(to: point)
            }, with: .color(accent.opacity(0.36)), lineWidth: 1)
        }
    }

    private func drawSignalCluster(in context: GraphicsContext, size: CGSize, base: CGFloat, seed: UInt64) {
        for index in 0..<14 {
            let x = size.width * CGFloat((seed >> UInt64((index % 8) * 7)) & 127) / 127
            let y = size.height * CGFloat((seed >> UInt64((index % 6) * 9)) & 127) / 127
            let radius = base * (0.045 + CGFloat(index % 4) * 0.012)
            context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(accent.opacity(0.16)))
            context.stroke(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(.white.opacity(0.13)), lineWidth: 1)
        }
    }

    private func drawTrendGrid(in context: GraphicsContext, size: CGSize, base: CGFloat, seed: UInt64) {
        let rows = 4
        let cols = 7
        let cellW = size.width / CGFloat(cols)
        let cellH = size.height / CGFloat(rows)
        for row in 0..<rows {
            for col in 0..<cols {
                let mix = CGFloat(((row * cols + col) * 37 + Int(seed % 97)) % 100) / 100
                let rect = CGRect(
                    x: CGFloat(col) * cellW + 4,
                    y: CGFloat(row) * cellH + 4,
                    width: cellW - 8,
                    height: cellH - 8
                )
                context.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(accent.opacity(0.05 + Double(mix) * 0.18)))
            }
        }

        var path = Path()
        for index in 0..<8 {
            let x = CGFloat(index) / 7 * size.width
            let y = size.height * (0.78 - CGFloat(index) * 0.07 + CGFloat((seed >> UInt64(index)) & 3) * 0.018)
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(path, with: .color(accent.opacity(0.92)), lineWidth: 4)
    }

    private func drawStoryParticles(in context: GraphicsContext, size: CGSize, base: CGFloat, seed: UInt64) {
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.5)
        for index in 0..<18 {
            let angle = CGFloat(index) / 18 * .pi * 2 + CGFloat(seed % 31) / 31
            let radius = base * (0.13 + CGFloat(index % 5) * 0.042)
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            context.fill(Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4)), with: .color(.white.opacity(0.7)))
            context.stroke(Path { path in
                path.move(to: center)
                path.addLine(to: point)
            }, with: .color(accent.opacity(0.18)), lineWidth: 1)
        }

        let rect = CGRect(x: center.x - base * 0.24, y: center.y - base * 0.24, width: base * 0.48, height: base * 0.48)
        context.stroke(Path(roundedRect: rect, cornerRadius: 18), with: .color(accent.opacity(0.68)), lineWidth: 2.5)
    }
}

private enum NewspaperVisualSeed {
    static func value(for text: String) -> UInt64 {
        var result: UInt64 = 5_381
        for scalar in text.unicodeScalars {
            result = ((result << 5) &+ result) &+ UInt64(scalar.value)
        }
        return result
    }
}

// MARK: - Full-page article card

private struct NewspaperArticleCard: View {
    let section: NewspaperSection
    let edition: String
    let date: String
    let onLongPress: () -> Void
    let highlightedRange: NSRange?

    // Each article speaks headline + ". " + detail.
    // These offsets map each text block into the full spoken string.
    private var headlineOffset: Int { 0 }
    private var detailOffset: Int {
        switch section {
        case .mapEvent(let a):   return a.headline.count + 2
        case .trending(let a):   return a.headline.count + 2
        case .dominance(let a):  return a.headline.count + 2
        case .userPost(let a):   return a.headline.count + 2
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            VStack(alignment: .leading, spacing: 0) {
                masthead
                articleBody
                Spacer(minLength: 0)
                footer
            }
        }
        .contentShape(Rectangle())
        .gesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onLongPress()
        })
    }

    // MARK: Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                (
                    Text("POPLUR")
                        .font(.system(size: 42, weight: .black, design: .serif))
                        .foregroundStyle(.white)
                    + Text(" DAILY")
                        .font(.system(size: 42, weight: .ultraLight, design: .serif))
                        .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.10))
                )
                .poplurTextShader(intensity: 0.76)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(date)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .poplurTextShader(intensity: 0.46)
                    Text(edition)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.28))
                        .poplurTextShader(intensity: 0.38)
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 54)

            Rectangle().fill(.white.opacity(0.88)).frame(height: 2)
                .padding(.horizontal, 26).padding(.top, 8)
            Rectangle().fill(.white.opacity(0.18)).frame(height: 1)
                .padding(.horizontal, 26).padding(.top, 3)
        }
    }

    // MARK: Article body (switches on section type)

    @ViewBuilder
    private var articleBody: some View {
        switch section {
        case .mapEvent(let a):  mapEventBody(a)
        case .trending(let a):  trendingBody(a)
        case .dominance(let a): dominanceBody(a)
        case .userPost(let a):  userPostBody(a)
        }
    }

    @ViewBuilder
    private func mapEventBody(_ a: MapEventArticle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            categoryRow(label: "MAP EVENT",
                        labelColor: .black,
                        chipColor: Color(red: 1.0, green: 0.85, blue: 0.10),
                        city: a.city, flag: a.flag, timeAgo: a.timeAgo)
            headlineText(a.headline)
            divider
            NewspaperGeneratedVisual(
                style: .mapEvent,
                latitude: a.latitude,
                longitude: a.longitude,
                city: a.city,
                flag: a.flag,
                headline: a.headline,
                accent: Color(red: 1.0, green: 0.85, blue: 0.10),
                username: nil,
                mediaURL: nil
            )
                .frame(height: 172)
                .padding(.horizontal, 26)
                .padding(.top, 12)
            bodyText(a.detail)
            statsRow(
                stat1: (icon: "person.2.fill",   value: briefCount(a.userCount) + " users nearby"),
                stat2: (icon: "mappin.and.ellipse", value: coordStr(a.latitude, a.longitude))
            )
        }
    }

    @ViewBuilder
    private func trendingBody(_ a: TrendingCityArticle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            categoryRow(label: "TRENDING",
                        labelColor: .black,
                        chipColor: Color(red: 0.18, green: 0.90, blue: 0.50),
                        city: a.city, flag: a.flag, timeAgo: a.timeAgo)
            headlineText(a.headline)
            divider
            NewspaperGeneratedVisual(
                style: .trending,
                latitude: a.latitude,
                longitude: a.longitude,
                city: a.city,
                flag: a.flag,
                headline: a.headline,
                accent: Color(red: 0.18, green: 0.90, blue: 0.50),
                username: nil,
                mediaURL: nil
            )
                .frame(height: 172)
                .padding(.horizontal, 26)
                .padding(.top, 12)
            bodyText(a.detail)
            statsRow(
                stat1: (icon: "chart.line.uptrend.xyaxis", value: "+\(a.growthPercent)% engagement"),
                stat2: (icon: "person.fill",               value: briefCount(a.activeUsers) + " active")
            )
        }
    }

    @ViewBuilder
    private func dominanceBody(_ a: DominanceArticle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            categoryRow(label: "DOMINANCE",
                        labelColor: .white,
                        chipColor: Color(red: 0.85, green: 0.10, blue: 0.10),
                        city: a.city, flag: a.flag, timeAgo: a.timeAgo)

            HStack(spacing: 10) {
                Text("👑")
                    .font(.system(size: 32))
                Text("@\(a.username)")
                    .font(.system(size: 28, weight: .black))
                    .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.10))
                    .poplurTextShader(intensity: 0.82)
                    .lineLimit(1)
            }
            .padding(.horizontal, 26)
            .padding(.top, 14)

            headlineText(a.headline, size: 32)
            divider
            NewspaperGeneratedVisual(
                style: .dominance,
                latitude: a.latitude,
                longitude: a.longitude,
                city: a.city,
                flag: a.flag,
                headline: a.headline,
                accent: Color(red: 0.85, green: 0.10, blue: 0.10),
                username: a.username,
                mediaURL: nil
            )
                .frame(height: 172)
                .padding(.horizontal, 26)
                .padding(.top, 12)
            bodyText(a.detail)
            statsRow(
                stat1: (icon: "scope",     value: a.radiusText + " radius"),
                stat2: (icon: "star.fill", value: briefCount(a.score) + " score")
            )
        }
    }

    @ViewBuilder
    private func userPostBody(_ a: UserPostArticle) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            categoryRow(label: "USER POST",
                        labelColor: .black,
                        chipColor: .white,
                        city: a.city, flag: a.flag, timeAgo: a.timeAgo)

            Text("@\(a.username)")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))
                .poplurTextShader(intensity: 0.72)
                .padding(.horizontal, 26)
                .padding(.top, 14)

            headlineText(a.headline)
            divider
            NewspaperGeneratedVisual(
                style: .userPost,
                latitude: a.latitude,
                longitude: a.longitude,
                city: a.city,
                flag: a.flag,
                headline: a.headline,
                accent: .white,
                username: a.username,
                mediaURL: a.mediaURL
            )
                .frame(height: 172)
                .padding(.horizontal, 26)
                .padding(.top, 12)
            bodyText(a.detail)
            statsRow(
                stat1: (icon: "heart.fill",      value: briefCount(a.likes) + " likes"),
                stat2: (icon: "bubble.left.fill", value: "\(a.comments) comments")
            )
        }
    }

    // MARK: Shared sub-views

    @ViewBuilder
    private func categoryRow(
        label: String,
        labelColor: Color,
        chipColor: Color,
        city: String,
        flag: String,
        timeAgo: String
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(labelColor)
                .poplurTextShader(intensity: 0.52)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(chipColor)
                .clipShape(Capsule())

            Text("\(flag) \(city)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
                .poplurTextShader(intensity: 0.48)

            Spacer()

            Text(timeAgo)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.38))
                .poplurTextShader(intensity: 0.38)
        }
        .padding(.horizontal, 26)
        .padding(.top, 22)
    }

    @ViewBuilder
    private func headlineText(_ text: String, size: CGFloat = 36) -> some View {
        HighlightedText(
            text: text,
            textOffset: headlineOffset,
            highlightedRange: highlightedRange,
            font: .system(size: size, weight: .black, design: .serif),
            baseColor: .white
        )
        .lineSpacing(5)
        .padding(.horizontal, 26)
        .padding(.top, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 26)
            .padding(.top, 14)
    }

    @ViewBuilder
    private func bodyText(_ text: String) -> some View {
        HighlightedText(
            text: text,
            textOffset: detailOffset,
            highlightedRange: highlightedRange,
            font: .system(size: 19, weight: .regular),
            baseColor: .white.opacity(0.72)
        )
        .lineSpacing(5)
        .padding(.horizontal, 26)
        .padding(.top, 14)
    }

    @ViewBuilder
    private func statsRow(
        stat1: (icon: String, value: String),
        stat2: (icon: String, value: String)
    ) -> some View {
        HStack(spacing: 20) {
            statItem(icon: stat1.icon, value: stat1.value)
            statItem(icon: stat2.icon, value: stat2.value)
        }
        .padding(.horizontal, 26)
        .padding(.top, 18)
    }

    @ViewBuilder
    private func statItem(icon: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .poplurIconShader()
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .poplurTextShader(intensity: 0.42)
                .lineLimit(1)
        }
    }

    private var footer: some View {
        VStack(spacing: 5) {
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            Text("Hold to view on map  •  Swipe for next story  •  Reading aloud")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.28))
                .poplurTextShader(intensity: 0.34)
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 30)
    }

    // MARK: Formatting

    private func briefCount(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func coordStr(_ lat: Double, _ lon: Double) -> String {
        String(format: "%.3f°%@, %.3f°%@",
               abs(lat), lat >= 0 ? "N" : "S",
               abs(lon), lon >= 0 ? "E" : "W")
    }
}

// MARK: - Content generator

struct NewspaperGenerator {

    private static let cities: [(name: String, flag: String, lat: Double, lon: Double)] = [
        ("Tokyo",       "🇯🇵",  35.6762,  139.6503),
        ("London",      "🇬🇧",  51.5074,   -0.1278),
        ("New York",    "🇺🇸",  40.7128,  -74.0060),
        ("Paris",       "🇫🇷",  48.8566,    2.3522),
        ("Sydney",      "🇦🇺", -33.8688,  151.2093),
        ("Toronto",     "🇨🇦",  43.6532,  -79.3832),
        ("Dubai",       "🇦🇪",  25.2048,   55.2708),
        ("Singapore",   "🇸🇬",   1.3521,  103.8198),
        ("Berlin",      "🇩🇪",  52.5200,   13.4050),
        ("Barcelona",   "🇪🇸",  41.3851,    2.1734),
        ("Seoul",       "🇰🇷",  37.5665,  126.9780),
        ("São Paulo",   "🇧🇷", -23.5505,  -46.6333),
        ("Mumbai",      "🇮🇳",  19.0760,   72.8777),
        ("Bangkok",     "🇹🇭",  13.7563,  100.5018),
        ("Istanbul",    "🇹🇷",  41.0082,   28.9784),
        ("Lagos",       "🇳🇬",   6.5244,    3.3792),
        ("Cairo",       "🇪🇬",  30.0444,   31.2357),
        ("Mexico City", "🇲🇽",  19.4326,  -99.1332),
        ("Jakarta",     "🇮🇩",  -6.2088,  106.8456),
        ("Chicago",     "🇺🇸",  41.8781,  -87.6298)
    ]

    private static let mapEventTemplates: [(String, String)] = [
        (
            "Viral Content Surge Detected Near Central District",
            "Poplur AI flagged an unusual spike in post activity within a 2 km radius. Over 3,200 users captured content here in the last 90 minutes — a 580% jump above the daily baseline."
        ),
        (
            "Midnight Flash Crowd Emerges at the Waterfront",
            "Thermal activity on the Poplur map suggests a spontaneous gathering forming near the harbor district. Real-time post velocity has tripled since 11:40 PM."
        ),
        (
            "Stadium Energy Spikes — Major Event Underway",
            "AI analysis of geotagged post density confirms a live event in this zone. Crowd-sourced signals show peak attendance, with post likes averaging 4.2× higher than non-event posts."
        ),
        (
            "Urban Exploration Trend Sweeps the Old Quarter",
            "A coordinated wave of Poplur users is documenting the historic district tonight. The AI identified a 'discovery cluster' — 14 unique rooftop viewpoints tagged in under 3 hours."
        ),
        (
            "Unofficial Street Festival Detected — Not on Any Calendar",
            "Post clusters, audio snippets, and density heatmaps point to a music gathering near the market district. Poplur AI is classifying this as an 'organic event emergence.'"
        ),
        (
            "Dawn Patrol Runners Form Largest Fitness Cluster of the Week",
            "Riverside park runners generated the highest fitness-category post density seen this week. AI estimates 800+ active users within a 500 m corridor at first light."
        ),
        (
            "Night Market Buzz at Seasonal Record",
            "Poplur's location AI tracked a 12-hour buildup of food and shopping posts converging on this coordinate. Engagement on night market content is 2.9× the platform average."
        ),
    ]

    private static let trendingTemplates: [(String, String, Int, Int)] = [
        (
            "Post Volume Triples — City Breaks into Global Top 10",
            "An unprecedented wave of content creation has catapulted this city into Poplur's weekly global leaderboard. AI trend analysis attributes the surge to weather, a cultural moment, and influencer activity.",
            312, 14_200
        ),
        (
            "City's Engagement Rate Hits All-Time Platform Record",
            "Average post likes-per-view in this metro has surpassed every prior benchmark on Poplur. The AI identifies rising creators in food, street art, and fitness as key drivers.",
            287, 9_800
        ),
        (
            "Overnight Viral Moment Puts City on the Global Map",
            "A single video from this city generated 2.1M views in 8 hours, triggering a cascade of follow-on posts. Poplur AI is classifying this as a 'viral echo event' — rare but powerful.",
            445, 22_500
        ),
        (
            "Longest-Running Trend This Year — Day 4 Continues",
            "This city has maintained trending status for four consecutive days — the longest streak in 2024. Sustained content quality, high radius posts, and active community response keep momentum going.",
            198, 7_400
        ),
        (
            "New Creator Cohort Drives 8× Weekend Engagement Spike",
            "Poplur AI detected an emerging cluster of high-quality creators in this metro. Combined, they drove an 8× spike in city-level engagement over a single weekend.",
            792, 31_000
        ),
    ]

    private static let dominanceNames = [
        "xX_King_Xx", "CityQueen_Riri", "BlazeRunner", "NightOwl_Kai",
        "UrbanHawk", "NovaStar_Lena", "GridLock_Ty", "SkyWatcher_J",
        "PoplurElite99", "StreetKing_Mav", "TowerVault_Em", "CityPulse_Zara"
    ]

    private static let dominanceTemplates: [(String, String)] = [
        (
            "Claims Full Control of Metro District After 72-Hour Push",
            "Through sustained high-radius posts and aggressive engagement, this user has locked down the metro zone. Challengers within 10 km have been pushed entirely off the leaderboard."
        ),
        (
            "Breaks City Record — Largest Radius Ever Logged in Region",
            "A single post blanketed the entire metropolitan area, outranking 340 competing accounts simultaneously. Poplur AI has flagged this as a historic radius achievement."
        ),
        (
            "Retains Crown for Third Consecutive Week",
            "Despite heavy competition from rising challengers, this user has successfully defended their dominant position for three weeks running. AI analysis cites content consistency as the primary factor."
        ),
        (
            "Tactical Late-Night Push Flips City Leaderboard",
            "In a calculated off-peak move at 2:47 AM, this user deployed high-quality posts that flipped the entire city ranking. AI ranked this as one of the top-10 most strategic dominance moves this year."
        ),
        (
            "From Zero to City Champion in Just 11 Days",
            "This account went from newcomer to city champion in a record 11 days. Rapid follower growth, viral content acceleration, and precision radius targeting are cited by AI as the winning formula."
        ),
    ]

    private static let userPostTemplates: [(String, String)] = [
        (
            "Captured Something the City Hasn't Seen Before",
            "This post's unique angle and timing generated immediate traction. Poplur AI flagged it as 'discovery content' — documenting a moment or place with genuine novelty value."
        ),
        (
            "A Moment the Algorithm Loved",
            "High engagement velocity, strong radius, and early reshare activity pushed this post into the trending queue within minutes of upload."
        ),
        (
            "Local Insight. Global Reach.",
            "What started as a personal moment quickly resonated far beyond this creator's immediate circle. The post's radius has expanded three times since it was first published."
        ),
        (
            "Raw. Unfiltered. Trending.",
            "No filters, no production budget — just authentic street-level content that the Poplur community responded to immediately."
        ),
        (
            "This Post Is Why Poplur Exists",
            "A perfectly timed, genuinely local moment — exactly the kind of content that defines what Poplur was built for."
        ),
    ]

    private static let times = ["2m", "5m", "11m", "18m", "27m", "43m", "1h", "2h", "3h", "5h", "8h", "12h"]
    private static let radii = ["500m", "2km", "5km", "12km", "28km", "50km", "100km", "500km"]
    private static let scores = [1_200, 3_400, 7_800, 15_000, 42_000, 88_000, 210_000, 550_000]
    private static let userCounts = [820, 1_240, 2_100, 3_400, 560, 4_800, 720, 9_300]
    private static let fakeLikes = [88, 234, 1_200, 340, 56, 3_100, 780]
    private static let fakeComments = [12, 34, 88, 210, 7, 400, 55]
    private static let fakeHandles = ["MavericK", "SkylineJ", "UrbanLens", "NovaBeat"]

    static func generate(
        posts: [FeedPost],
        displayNameProvider: (FeedPost) -> String,
        startIndex: Int,
        count: Int
    ) -> [NewspaperSection] {
        (0..<count).map { i in
            let gi = startIndex + i
            let city = cities[(gi * 7 + i * 3) % cities.count]
            let timeAgo = times[gi % times.count] + " ago"
            let jitter = { Double.random(in: -0.08...0.08) }
            let slot = gi % 20

            switch slot {
            case 0..<6:
                let t = mapEventTemplates[gi % mapEventTemplates.count]
                return .mapEvent(MapEventArticle(
                    city: city.name, flag: city.flag,
                    headline: t.0, detail: t.1,
                    userCount: userCounts[gi % userCounts.count],
                    latitude: city.lat + jitter(), longitude: city.lon + jitter(),
                    timeAgo: timeAgo
                ))
            case 6..<11:
                let t = trendingTemplates[gi % trendingTemplates.count]
                return .trending(TrendingCityArticle(
                    city: city.name, flag: city.flag,
                    headline: t.0, detail: t.1,
                    growthPercent: t.2, activeUsers: t.3,
                    latitude: city.lat + jitter(), longitude: city.lon + jitter(),
                    timeAgo: timeAgo
                ))
            case 11..<16:
                let t = dominanceTemplates[gi % dominanceTemplates.count]
                return .dominance(DominanceArticle(
                    username: dominanceNames[gi % dominanceNames.count],
                    city: city.name, flag: city.flag,
                    headline: t.0, detail: t.1,
                    radiusText: radii[gi % radii.count],
                    score: scores[gi % scores.count],
                    latitude: city.lat + jitter(), longitude: city.lon + jitter(),
                    timeAgo: timeAgo
                ))
            default:
                let t = userPostTemplates[gi % userPostTemplates.count]
                let realPost = posts.isEmpty ? nil : posts[gi % posts.count]
                let name = realPost.map { displayNameProvider($0) }
                            ?? fakeHandles[gi % fakeHandles.count]
                return .userPost(UserPostArticle(
                    username: name,
                    city: city.name, flag: city.flag,
                    headline: t.0, detail: t.1,
                    likes: realPost?.viewCount ?? fakeLikes[gi % fakeLikes.count],
                    comments: fakeComments[gi % fakeComments.count],
                    latitude: realPost?.latitude ?? (city.lat + jitter()),
                    longitude: realPost?.longitude ?? (city.lon + jitter()),
                    timeAgo: timeAgo,
                    mediaURL: realPost?.mediaURL
                ))
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct FeedTwitterTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        FeedTwitterTimelineView(
            posts: [],
            displayNameProvider: { _ in "demo_user" },
            onPostTapped: { _ in }
        )
        .preferredColorScheme(.dark)
    }
}
#endif
