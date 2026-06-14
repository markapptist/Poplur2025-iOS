//
//  FeedTwitterTimelineView.swift
//  Poplur2025
//
//  Twitter-style vertical scrolling timeline for feed posts
//

import SwiftUI
import UIKit
import MapKit
import AVFoundation
import AudioToolbox

struct FeedTwitterTimelineView: View {
    let posts: [FeedPost]
    let displayNameProvider: (FeedPost) -> String
    let onPostTapped: (Int) -> Void
    
    @State private var fakeTweets: [FakeTweet] = []
    @State private var currentTweetIndex: Int = 0
    @State private var hapticGenerator = UIImpactFeedbackGenerator(style: .rigid)
    @State private var lastScrollOffset: CGFloat = 0
    @State private var popPlayer: AVAudioPlayer? = nil
    @State private var scrollPosition: Int? = 0
    
    // Combined array of all items (fake tweets only for now - real posts don't have text content)
    private var allItems: [TimelineItem] {
        fakeTweets.map { .fake($0) }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(allItems.enumerated()), id: \.offset) { index, item in
                        if case .fake(let tweet) = item {
                            FakeTweetCard(
                                tweet: tweet,
                                onLongPress: {
                                    showMapForTweet(tweet)
                                }
                            )
                            .containerRelativeFrame([.horizontal, .vertical])
                            .id(index)
                            .onAppear {
                                updateRadiusForTweet(tweet)
                                // Load more tweets when nearing the end (infinite scroll)
                                if index == allItems.count - 3 {
                                    generateMoreTweets()
                                }
                            }
                        }
                    }
                }
                .scrollTargetLayout()
                .background(
                    GeometryReader { scrollGeo in
                        Color.clear.preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: scrollGeo.frame(in: .named("scroll")).origin.y
                        )
                    }
                )
            }
            .coordinateSpace(name: "scroll")
            .scrollTargetBehavior(.paging)
            .scrollBounceBehavior(.basedOnSize)
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                let pageHeight = geometry.size.height
                let newIndex = Int(round(-offset / pageHeight))
                
                if newIndex != currentTweetIndex && newIndex >= 0 && newIndex < allItems.count {
                    currentTweetIndex = newIndex
                    
                    // Haptic feedback
                    hapticGenerator.impactOccurred(intensity: 0.7)
                    
                    // Pop sound
                    playOneShotPop()
                    
                    // Update radius for new item
                    if case .fake(let tweet) = allItems[newIndex] {
                        updateRadiusForTweet(tweet)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            hapticGenerator.prepare()
            if fakeTweets.isEmpty {
                generateInitialTweets()
            }
        }
    }
    
    private func showMapForTweet(_ tweet: FakeTweet) {
        Task { @MainActor in
            let coordinate = CLLocationCoordinate2D(latitude: tweet.latitude, longitude: tweet.longitude)
            
            // Set pending location in MapStateManager
            MapStateManager.shared.setPendingPostLocation(
                coordinate,
                userID: "fake_\(tweet.id)",
                username: tweet.username,
                profileImageURL: nil,
                radius: parseRadius(from: tweet.radiusText),
                cityName: tweet.location,
                countryName: nil,
                countryFlag: nil
            )
            
            // Post notification to show location on map
            let userInfo: [String: Any] = [
                "coordinate": coordinate,
                "latitude": tweet.latitude,
                "longitude": tweet.longitude,
                "username": tweet.username,
                "radius": parseRadius(from: tweet.radiusText)
            ]

            NotificationCenter.default.post(
                name: Notification.Name("ShowLocationOnMap"),
                object: nil,
                userInfo: userInfo
            )
            
            // Wait briefly, then switch to map tab
            try? await Task.sleep(nanoseconds: 150_000_000)
            
            NotificationCenter.default.post(
                name: Notification.Name("SwitchToMapTab"),
                object: nil
            )
        }
    }
    
    private func showMapForPost(_ post: FeedPost) {
        Task { @MainActor in
            let coordinate = CLLocationCoordinate2D(latitude: post.latitude, longitude: post.longitude)
            
            // Set pending location in MapStateManager
            MapStateManager.shared.setPendingPostLocation(
                coordinate,
                userID: post.userID,
                username: displayNameProvider(post),
                profileImageURL: nil,
                radius: post.radius,
                cityName: post.cityName,
                countryName: post.countryName,
                countryFlag: post.countryFlag
            )
            
            // Post notification to show location on map
            var userInfo: [String: Any] = [
                "coordinate": coordinate,
                "latitude": post.latitude,
                "longitude": post.longitude,
                "userID": post.userID,
                "username": displayNameProvider(post),
                "radius": post.radius
            ]
            
            if let city = post.cityName {
                userInfo["cityName"] = city
            }
            if let country = post.countryName {
                userInfo["countryName"] = country
            }
            if let flag = post.countryFlag {
                userInfo["countryFlag"] = flag
            }
            
            NotificationCenter.default.post(
                name: Notification.Name("ShowLocationOnMap"),
                object: nil,
                userInfo: userInfo
            )
            
            // Wait briefly, then switch to map tab
            try? await Task.sleep(nanoseconds: 150_000_000)
            
            NotificationCenter.default.post(
                name: Notification.Name("SwitchToMapTab"),
                object: nil
            )
        }
    }
    
    private func generateMoreTweets() {
        let newTweets = FakeTweetGenerator.generate(count: 10)
        fakeTweets.append(contentsOf: newTweets)
    }
    
    private func generateInitialTweets() {
        fakeTweets = FakeTweetGenerator.generate(count: 20)
        
        // Update radius for first tweet
        if let firstTweet = fakeTweets.first {
            updateRadiusForTweet(firstTweet)
        }
    }
    
    private func updateRadiusForTweet(_ tweet: FakeTweet) {
        // Parse radius from tweet.radiusText and update global radius
        let radiusMeters = parseRadius(from: tweet.radiusText)
        
        // Update global radius bar with animation
        NotificationCenter.default.post(
            name: .animateRadiusBarToValue,
            object: nil,
            userInfo: ["radius": radiusMeters, "duration": 0.8]
        )
        
        // Update post count (use likes as post count for tweets)
        NotificationCenter.default.post(
            name: Notification.Name("UserPostCountDidChange"),
            object: nil,
            userInfo: ["count": tweet.likes]
        )
        
        print("[Timeline] Updated radius to \(Int(radiusMeters))m, likes: \(tweet.likes)")
    }
    
    private func updateRadiusForPost(_ post: FeedPost) {
        // Update global radius bar with animation
        NotificationCenter.default.post(
            name: .animateRadiusBarToValue,
            object: nil,
            userInfo: ["radius": post.radius, "duration": 0.8]
        )
        
        // Update post count with view count
        NotificationCenter.default.post(
            name: Notification.Name("UserPostCountDidChange"),
            object: nil,
            userInfo: ["count": post.viewCount]
        )
        
        print("[Timeline] Updated radius to \(Int(post.radius))m, views: \(post.viewCount)")
    }
    
    private func parseRadius(from text: String) -> Double {
        // Parse radius text like "5km", "100m", "2.5Mm" back to meters
        let numericPart = text.trimmingCharacters(in: CharacterSet.decimalDigits.inverted)
        guard let value = Double(numericPart.replacingOccurrences(of: ",", with: "")) else {
            return 0
        }
        
        if text.contains("Mm") {
            return value * 1_000_000
        } else if text.contains("km") {
            return value * 1000
        } else {
            return value
        }
    }
    
    private func playOneShotPop() {
        // Try to play the pop sound file
        do {
            let session = AVAudioSession.sharedInstance()
            // Use ambient to avoid errors and allow mixing
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[PopSound] Audio session config failed: \(error)")
        }
        
        if let url = Bundle.main.url(forResource: "pop", withExtension: "mp3") ?? Bundle.main.url(forResource: "pop", withExtension: "wav") {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = 0
                player.volume = 0.9
                player.prepareToPlay()
                player.play()
                popPlayer = player
                print("[PopSound] ✅ Playing pop sound from file")
                // Auto release after it finishes (~0.5s typical)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak popPlayer] in
                    popPlayer?.stop()
                    self.popPlayer = nil
                }
            } catch {
                print("[PopSound] ❌ Failed to create player: \(error)")
                // Fallback to system sound
                AudioServicesPlaySystemSound(1104) // System pop sound
            }
        } else {
            print("[PopSound] ⚠️ pop.(mp3|wav) not found in bundle - using system sound")
            // Fallback to system sound
            AudioServicesPlaySystemSound(1104) // System pop sound
        }
    }
}

// MARK: - Scroll Offset Preference Key

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Timeline Item Enum

private enum TimelineItem {
    case fake(FakeTweet)
}

// MARK: - Fake Tweet Card

private struct FakeTweetCard: View {
    let tweet: FakeTweet
    let onLongPress: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header: Profile + Username + Location
            HStack(spacing: 16) {
                // Profile circle - larger
                Circle()
                    .fill(Color.black)
                    .frame(width: 80, height: 80)
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .overlay {
                        Text(tweet.username.prefix(1).uppercased())
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                    }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(tweet.username)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.7))
                        
                        Text(tweet.location)
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                
                Spacer()
                
                Text(tweet.timeAgo)
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            // Tweet text content - VERY large and prominent
            Text(tweet.content)
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.white)
                .lineSpacing(12)
                .padding(.vertical, 24)
            
            Spacer()
            
            // Coordinates display at bottom
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.6))
                    
                    Text(formatCoordinate(tweet.latitude, tweet.longitude))
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                }
                
                Text("Hold to view on map")
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.5))
                    .italic()
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black)
        .contentShape(Rectangle())
        .gesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    onLongPress()
                }
        )
    }
    
    private func formatCoordinate(_ lat: Double, _ lon: Double) -> String {
        let latDir = lat >= 0 ? "N" : "S"
        let lonDir = lon >= 0 ? "E" : "W"
        return String(format: "%.4f°%@ %.4f°%@", abs(lat), latDir, abs(lon), lonDir)
    }
}

// MARK: - Fake Tweet Model

struct FakeTweet: Identifiable {
    let id = UUID()
    let username: String
    let location: String
    let content: String
    let timeAgo: String
    let radiusText: String
    let likes: Int
    let comments: Int
    let isVideo: Bool
    let latitude: Double
    let longitude: Double
}

// MARK: - Fake Tweet Generator

struct FakeTweetGenerator {
    private static let usernames = [
        "Alex_Chen", "Sarah_M", "Mike_Rodriguez", "Emma_Johnson", "David_Kim",
        "Sophie_Williams", "Lucas_Brown", "Olivia_Davis", "Noah_Martinez", "Ava_Garcia",
        "Ethan_Wilson", "Mia_Anderson", "Mason_Taylor", "Isabella_Thomas", "Logan_Moore",
        "Charlotte_Jackson", "Liam_White", "Amelia_Harris", "Oliver_Martin", "Harper_Lee",
        "Elijah_Clark", "Evelyn_Lewis", "James_Walker", "Abigail_Hall", "Benjamin_Young"
    ]
    
    private static let cities = [
        ("Tokyo", "🇯🇵", 35.6762, 139.6503),
        ("London", "🇬🇧", 51.5074, -0.1278),
        ("New York", "🇺🇸", 40.7128, -74.0060),
        ("Paris", "🇫🇷", 48.8566, 2.3522),
        ("Sydney", "🇦🇺", -33.8688, 151.2093),
        ("Toronto", "🇨🇦", 43.6532, -79.3832),
        ("Dubai", "🇦🇪", 25.2048, 55.2708),
        ("Singapore", "🇸🇬", 1.3521, 103.8198),
        ("Berlin", "🇩🇪", 52.5200, 13.4050),
        ("Amsterdam", "🇳🇱", 52.3676, 4.9041),
        ("Barcelona", "🇪🇸", 41.3851, 2.1734),
        ("Rome", "🇮🇹", 41.9028, 12.4964),
        ("Seoul", "🇰🇷", 37.5665, 126.9780),
        ("Mexico City", "🇲🇽", 19.4326, -99.1332),
        ("São Paulo", "🇧🇷", -23.5505, -46.6333),
        ("Mumbai", "🇮🇳", 19.0760, 72.8777),
        ("Hong Kong", "🇭🇰", 22.3193, 114.1694),
        ("Bangkok", "🇹🇭", 13.7563, 100.5018),
        ("Istanbul", "🇹🇷", 41.0082, 28.9784),
        ("Moscow", "🇷🇺", 55.7558, 37.6173)
    ]
    
    private static let tweetTemplates = [
        "Just captured an amazing moment at the local park! The sunset was incredible 🌅",
        "Can't believe how busy downtown is today. Everyone's out enjoying the weather ☀️",
        "Found this hidden gem of a cafe. Best coffee I've had in months! ☕",
        "The street art scene here is absolutely mind-blowing 🎨",
        "Just witnessed the most beautiful architecture. This city never disappoints 🏛️",
        "Food scene here is next level. Every meal is an adventure 🍜",
        "The energy at the market today was unreal. So many amazing finds! 🛍️",
        "Nothing beats a morning run along the waterfront. Pure bliss 🏃‍♀️",
        "This neighborhood has such a unique vibe. Love exploring new areas 🏘️",
        "Concert vibes tonight were incredible! Music brings people together 🎵",
        "The view from up here is absolutely breathtaking 🏔️",
        "Local festival energy is AMAZING right now! 🎉",
        "Just tried the most incredible dish. My taste buds are dancing 🍽️",
        "The skyline at night here is something else ✨",
        "Beach day perfection. Sun, sand, and good company 🏖️",
        "This hiking trail exceeded all expectations. Nature therapy 🥾",
        "The shopping district here is dangerous for my wallet 😅",
        "Museum visit today was so inspiring. Art really moves you 🖼️",
        "The nightlife here is absolutely electric ⚡",
        "Just experienced the best street performance. Talent everywhere! 🎭",
        "The local produce market is a feast for the senses 🥬",
        "Rain or shine, this city always delivers ☔",
        "The historic quarter is like stepping back in time ⏰",
        "Fitness community here is so welcoming and supportive 💪",
        "The botanical gardens are in full bloom. Absolutely stunning 🌺"
    ]
    
    static func generate(count: Int) -> [FakeTweet] {
        var tweets: [FakeTweet] = []
        
        for _ in 0..<count {
            let username = usernames.randomElement()!
            let cityData = cities.randomElement()!
            let content = tweetTemplates.randomElement()!
            
            // Generate random time ago
            let timeValue = Int.random(in: 1...59)
            let timeUnit = ["s", "m", "h"].randomElement()!
            let timeAgo = "\(timeValue)\(timeUnit)"
            
            // Generate random radius
            let radiusMeters = [100, 500, 1_000, 5_000, 10_000, 50_000, 100_000, 500_000, 1_000_000, 5_000_000].randomElement()!
            let radiusText: String
            if radiusMeters < 1000 {
                radiusText = "\(radiusMeters)m"
            } else if radiusMeters < 1_000_000 {
                let km = Double(radiusMeters) / 1000
                radiusText = km < 10 ? String(format: "%.1fkm", km) : "\(Int(km))km"
            } else {
                let mm = Double(radiusMeters) / 1_000_000
                radiusText = String(format: "%.1fMm", mm)
            }
            
            let likes = Int.random(in: 5...1500)
            let comments = Int.random(in: 0...150)
            let isVideo = Int.random(in: 0..<10) < 8
            
            // Add some random offset to coordinates for variety
            let latOffset = Double.random(in: -0.1...0.1)
            let lonOffset = Double.random(in: -0.1...0.1)
            
            let tweet = FakeTweet(
                username: username,
                location: "\(cityData.0) \(cityData.1)",
                content: content,
                timeAgo: timeAgo,
                radiusText: radiusText,
                likes: likes,
                comments: comments,
                isVideo: isVideo,
                latitude: cityData.2 + latOffset,
                longitude: cityData.3 + lonOffset
            )
            
            tweets.append(tweet)
        }
        
        return tweets
    }
}

// MARK: - Preview

#if DEBUG
struct FeedTwitterTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        let samplePosts = [
            FeedPost(
                id: "1",
                latitude: 40.7128,
                longitude: -74.0060,
                mediaURL: "https://picsum.photos/800/600",
                radius: 5000,
                viewCount: 1250,
                userID: "user1",
                cityName: "New York",
                countryName: "USA",
                countryFlag: "🇺🇸"
            ),
            FeedPost(
                id: "2",
                latitude: 51.5074,
                longitude: -0.1278,
                mediaURL: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_4x3/gear1/prog_index.m3u8",
                radius: 50000,
                viewCount: 8500,
                userID: "user2",
                cityName: "London",
                countryName: "United Kingdom",
                countryFlag: "🇬🇧"
            ),
            FeedPost(
                id: "3",
                latitude: 35.6762,
                longitude: 139.6503,
                mediaURL: "https://picsum.photos/800/600?random=2",
                radius: 500000,
                viewCount: 25000,
                userID: "user3",
                cityName: "Tokyo",
                countryName: "Japan",
                countryFlag: "🇯🇵"
            )
        ]
        
        FeedTwitterTimelineView(
            posts: samplePosts,
            displayNameProvider: { post in "User \(post.userID)" },
            onPostTapped: { index in print("Tapped post \(index)") }
        )
    }
}
#endif
