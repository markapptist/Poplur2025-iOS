//
//  FeedTwitterTimelineView.swift
//  Poplur2025
//
//  Twitter-style vertical scrolling timeline for feed posts
//

import SwiftUI

struct FeedTwitterTimelineView: View {
    let posts: [FeedPost]
    let displayNameProvider: (FeedPost) -> String
    let onPostTapped: (Int) -> Void
    
    @State private var fakeTweets: [FakeTweet] = []
    @State private var isLoadingMore: Bool = false
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                // Show fake tweets at the top
                ForEach(fakeTweets) { tweet in
                    FakeTweetCard(tweet: tweet)
                    
                    Divider()
                        .background(Color.white.opacity(0.2))
                }
                
                // Then show actual posts
                ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                    TwitterPostCard(
                        post: post,
                        displayName: displayNameProvider(post),
                        onTap: {
                            onPostTapped(index)
                        }
                    )
                    
                    // Divider between posts
                    if index < posts.count - 1 {
                        Divider()
                            .background(Color.white.opacity(0.2))
                    }
                }
                
                // Loading indicator at bottom for infinite scroll
                if isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                            .padding(.vertical, 20)
                        Spacer()
                    }
                } else {
                    // Invisible view to trigger loading more
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            loadMoreTweets()
                        }
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            if fakeTweets.isEmpty {
                generateInitialTweets()
            }
        }
    }
    
    private func generateInitialTweets() {
        fakeTweets = FakeTweetGenerator.generate(count: 20)
    }
    
    private func loadMoreTweets() {
        guard !isLoadingMore else { return }
        
        isLoadingMore = true
        
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let newTweets = FakeTweetGenerator.generate(count: 10)
            fakeTweets.append(contentsOf: newTweets)
            isLoadingMore = false
        }
    }
}

// MARK: - Twitter-Style Post Card

private struct TwitterPostCard: View {
    let post: FeedPost
    let displayName: String
    let onTap: () -> Void
    
    @State private var imageLoaded: Bool = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 16) {
                // Header: Profile + Username + Location
                HStack(spacing: 12) {
                    // Profile circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                        .overlay {
                            Text(displayName.prefix(1).uppercased())
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        
                        if let city = post.cityName, let country = post.countryName {
                            HStack(spacing: 4) {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.6))
                                
                                Text("\(city), \(country) \(post.countryFlag ?? "")")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                    }
                    
                    Spacer()
                }
                
                // Large empty space for better scrolling focus
                // Text placeholder showing this is a real post
                Text("Tap to view full post")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineSpacing(4)
                    .padding(.vertical, 8)
            }
            .padding(20)
            .frame(minHeight: 200) // Make tweet boxes much taller
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Functions
    
    private func formatRadius(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters))m"
        } else if meters < 1_000_000 {
            let km = meters / 1000
            if km < 10 {
                return String(format: "%.1fkm", km)
            } else {
                return "\(Int(km))km"
            }
        } else {
            let megameters = meters / 1_000_000
            return String(format: "%.1fMm", megameters)
        }
    }
    
    private func formatNumber(_ number: Int) -> String {
        if number < 1000 {
            return "\(number)"
        } else if number < 1_000_000 {
            let k = Double(number) / 1000
            return String(format: "%.1fK", k)
        } else {
            let m = Double(number) / 1_000_000
            return String(format: "%.1fM", m)
        }
    }
}

// MARK: - Fake Tweet Card

private struct FakeTweetCard: View {
    let tweet: FakeTweet
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header: Profile + Username + Location
            HStack(spacing: 12) {
                // Profile circle
                Circle()
                    .fill(tweet.profileGradient)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Text(tweet.username.prefix(1).uppercased())
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(tweet.username)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))
                        
                        Text(tweet.location)
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                
                Spacer()
                
                Text(tweet.timeAgo)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }
            
            // Tweet text content - much larger and more prominent
            Text(tweet.content)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white)
                .lineSpacing(4)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
        }
        .padding(20)
        .frame(minHeight: 200) // Make tweet boxes much taller
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
    let profileGradient: LinearGradient
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
        ("Tokyo", "🇯🇵"), ("London", "🇬🇧"), ("New York", "🇺🇸"), ("Paris", "🇫🇷"),
        ("Sydney", "🇦🇺"), ("Toronto", "🇨🇦"), ("Dubai", "🇦🇪"), ("Singapore", "🇸🇬"),
        ("Berlin", "🇩🇪"), ("Amsterdam", "🇳🇱"), ("Barcelona", "🇪🇸"), ("Rome", "🇮🇹"),
        ("Seoul", "🇰🇷"), ("Mexico City", "🇲🇽"), ("São Paulo", "🇧🇷"), ("Mumbai", "🇮🇳"),
        ("Hong Kong", "🇭🇰"), ("Bangkok", "🇹🇭"), ("Istanbul", "🇹🇷"), ("Moscow", "🇷🇺")
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
    
    private static let gradients = [
        LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.purple, .blue], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.teal, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
        LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
    ]
    
    static func generate(count: Int) -> [FakeTweet] {
        var tweets: [FakeTweet] = []
        
        for _ in 0..<count {
            let username = usernames.randomElement()!
            let cityData = cities.randomElement()!
            let content = tweetTemplates.randomElement()!
            let gradient = gradients.randomElement()!
            
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
            let isVideo = Bool.random()
            
            let tweet = FakeTweet(
                username: username,
                location: "\(cityData.0) \(cityData.1)",
                content: content,
                timeAgo: timeAgo,
                radiusText: radiusText,
                likes: likes,
                comments: comments,
                isVideo: isVideo,
                profileGradient: gradient
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
