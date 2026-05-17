//
//  FeedTimelineView.swift
//  Instagram Stories-style Timeline View
//

import SwiftUI
import AVKit

// MARK: - Instagram Stories-style Timeline View

struct FeedTimelineView: View {
    let posts: [FeedPost]
    let displayNameProvider: (FeedPost) -> String
    var onPostTapped: (Int) -> Void
    
    @State private var currentIndex: Int = 0
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Paging carousel of posts
                TabView(selection: $currentIndex) {
                    ForEach(Array(posts.enumerated()), id: \.element.id) { index, post in
                        StoriesStylePostView(
                            post: post,
                            displayName: displayNameProvider(post),
                            currentIndex: index,
                            totalPosts: posts.count,
                            onDismiss: {
                                onPostTapped(index)
                            }
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
                
                // Top progress indicators (Instagram-style)
                VStack(spacing: 0) {
                    HStack(spacing: 4) {
                        ForEach(0..<posts.count, id: \.self) { index in
                            Capsule()
                                .fill(index == currentIndex ? Color.white : Color.white.opacity(0.3))
                                .frame(height: 3)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)
                    
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Stories-Style Single Post View

struct StoriesStylePostView: View {
    let post: FeedPost
    let displayName: String
    let currentIndex: Int
    let totalPosts: Int
    var onDismiss: () -> Void
    
    @State private var player: AVPlayer?
    
    private var isVideo: Bool {
        let url = post.mediaURL.lowercased()
        return url.contains(".mp4") || url.contains(".m3u8") || url.contains("video")
    }
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background media (fullscreen)
                if isVideo {
                    if let player = player {
                        VideoPlayer(player: player)
                            .ignoresSafeArea()
                            .disabled(true)  // Disable controls
                    } else {
                        Color.black
                    }
                } else {
                    // Image
                    AsyncImage(url: URL(string: post.mediaURL)) { phase in
                        switch phase {
                        case .empty:
                            Color.black
                                .overlay(ProgressView().tint(.white))
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geo.size.width, height: geo.size.height)
                                .clipped()
                        case .failure:
                            Color.black
                                .overlay(
                                    Image(systemName: "photo")
                                        .font(.system(size: 60))
                                        .foregroundColor(.white.opacity(0.3))
                                )
                        @unknown default:
                            Color.black
                        }
                    }
                }
                
                // Gradient overlays for readability
                VStack(spacing: 0) {
                    // Top gradient
                    LinearGradient(
                        colors: [Color.black.opacity(0.7), Color.black.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 200)
                    
                    Spacer()
                    
                    // Bottom gradient
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.3), Color.black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 300)
                }
                .ignoresSafeArea()
                
                // Content overlay
                VStack(spacing: 0) {
                    // Top header (profile info)
                    HStack(spacing: 12) {
                        // Profile circle (gradient ring)
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.purple, .pink, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .fill(Color.gray.opacity(0.5))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(.white.opacity(0.7))
                                    )
                            )
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text(displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                // Verified badge
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.blue)
                            }
                            
                            // Location
                            if let city = post.cityName, let country = post.countryName {
                                Text("\(city), \(country)")
                                    .font(.system(size: 13))
                                    .foregroundColor(.white.opacity(0.9))
                            } else {
                                Text(String(format: "%.2f, %.2f", post.latitude, post.longitude))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        
                        Spacer()
                        
                        // Follow button
                        Button {
                            // Follow action
                        } label: {
                            Text("Follow")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(8)
                        }
                        
                        // More menu
                        Button {
                            // More options
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 60)
                    
                    Spacer()
                    
                    // Bottom engagement bar
                    VStack(spacing: 16) {
                        // Engagement metrics
                        HStack(spacing: 24) {
                            // Like
                            HStack(spacing: 6) {
                                Image(systemName: "heart")
                                    .font(.system(size: 26, weight: .regular))
                                Text(formatCount(7264))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            
                            // Comment
                            HStack(spacing: 6) {
                                Image(systemName: "message")
                                    .font(.system(size: 26, weight: .regular))
                                Text(formatCount(255))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            
                            // Share
                            HStack(spacing: 6) {
                                Image(systemName: "paperplane")
                                    .font(.system(size: 26, weight: .regular))
                                Text(formatCount(35))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            
                            // Send
                            HStack(spacing: 6) {
                                Image(systemName: "location")
                                    .font(.system(size: 26, weight: .regular))
                                Text(formatCount(127))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            
                            Spacer()
                            
                            // Bookmark
                            Image(systemName: "bookmark")
                                .font(.system(size: 26, weight: .regular))
                        }
                        .foregroundColor(.white)
                        
                        // Caption
                        HStack(alignment: .top, spacing: 6) {
                            Text(displayName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text("Which is your... ")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.9))
                            +
                            Text("more")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.5))
                            
                            Spacer()
                        }
                        
                        // Timestamp and radius
                        HStack {
                            Text("7 hours ago")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.5))
                            
                            Spacer()
                            
                            // Radius indicator
                            HStack(spacing: 4) {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.blue)
                                
                                Text(formatRadius(post.radius))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 100)
                }
                
                // Tap to dismiss gesture
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onDismiss()
                    }
            }
        }
        .onAppear {
            if isVideo {
                setupVideoPlayer()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    private func setupVideoPlayer() {
        guard let url = URL(string: post.mediaURL) else { return }
        let player = AVPlayer(url: url)
        player.isMuted = true  // Start muted like Instagram
        self.player = player
        player.play()
        
        // Loop video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
    }
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fk", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
    
    private func formatRadius(_ radius: Double) -> String {
        if radius >= 1_000_000 {
            return String(format: "%.1fM m", radius / 1_000_000)
        } else if radius >= 1_000 {
            return String(format: "%.1fk m", radius / 1_000)
        } else {
            return String(format: "%.0f m", radius)
        }
    }
}

// MARK: - Preview

#Preview {
    let samplePosts = [
        FeedPost(
            id: "1",
            latitude: 25.7617,
            longitude: -80.1918,
            mediaURL: "https://picsum.photos/1080/1920",
            radius: 5000,
            viewCount: 7264,
            userID: "user1",
            cityName: "South Beach",
            countryName: "Miami",
            countryFlag: "🇺🇸"
        )
    ]
    
    FeedTimelineView(
        posts: samplePosts,
        displayNameProvider: { _ in "alexisfawxlive" },
        onPostTapped: { _ in }
    )
}
