//
//  FeedTimelineView.swift
//  Instagram Feed-style Timeline View
//

import SwiftUI
import AVKit

// MARK: - Instagram Feed-style Timeline View

struct FeedTimelineView: View {
    let posts: [FeedPost]
    let displayNameProvider: (FeedPost) -> String
    var onPostTapped: (Int) -> Void
    
    @State private var visiblePosts: [FeedPost] = []
    @State private var isLoadingMore = false
    @State private var currentPage = 0
    private let postsPerPage = 5  // Show 5 posts at a time (Instagram-like)
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(visiblePosts.enumerated()), id: \.element.id) { index, post in
                    FeedStylePostView(
                        post: post,
                        displayName: displayNameProvider(post),
                        postIndex: index,
                        onDismiss: {
                            // Find the original index in the full posts array
                            if let originalIndex = posts.firstIndex(where: { $0.id == post.id }) {
                                onPostTapped(originalIndex)
                            }
                        }
                    )
                    .id(post.id)
                    .onAppear {
                        // Load more when approaching end
                        if index == visiblePosts.count - 2 {
                            loadMorePosts()
                        }
                    }
                    
                    // Divider between posts
                    if index < visiblePosts.count - 1 {
                        Divider()
                            .background(Color.gray.opacity(0.3))
                            .padding(.vertical, 16)
                    }
                }
                
                // Loading indicator at bottom
                if isLoadingMore && visiblePosts.count < posts.count {
                    HStack {
                        Spacer()
                        ProgressView()
                            .padding()
                        Spacer()
                    }
                }
                
                // End of feed indicator
                if visiblePosts.count >= posts.count && posts.count > 0 {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .poplurIconShader()
                                .font(.system(size: 24))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("You're all caught up!")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.gray)
                                .poplurTextShader(intensity: 0.46)
                        }
                        .padding(.vertical, 32)
                        Spacer()
                    }
                }
            }
        }
        .background(Color.white)
        .onAppear {
            // Load initial batch
            if visiblePosts.isEmpty {
                loadInitialPosts()
            }
        }
    }
    
    private func loadInitialPosts() {
        let endIndex = min(postsPerPage, posts.count)
        visiblePosts = Array(posts[0..<endIndex])
        currentPage = 1
    }
    
    private func loadMorePosts() {
        guard !isLoadingMore else { return }
        guard visiblePosts.count < posts.count else { return }
        
        isLoadingMore = true
        
        // Simulate network delay (like real Instagram)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let startIndex = currentPage * postsPerPage
            let endIndex = min(startIndex + postsPerPage, posts.count)
            
            if startIndex < posts.count {
                let newPosts = Array(posts[startIndex..<endIndex])
                visiblePosts.append(contentsOf: newPosts)
                currentPage += 1
            }
            
            isLoadingMore = false
        }
    }
}

// MARK: - Feed-Style Single Post View

struct FeedStylePostView: View {
    let post: FeedPost
    let displayName: String
    let postIndex: Int
    var onDismiss: () -> Void
    
    @State private var player: AVPlayer?
    @State private var videoEndObserver: NSObjectProtocol?
    
    private var isVideo: Bool {
        let url = post.mediaURL.lowercased()
        return url.contains(".mp4") || url.contains(".m3u8") || url.contains("video")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Profile header
            HStack(spacing: 12) {
                // Profile circle
                Circle()
                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 2)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 36, height: 36)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .poplurIconShader()
                                    .font(.system(size: 16))
                                    .foregroundColor(.gray)
                            )
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(displayName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.black)
                            .poplurTextShader(intensity: 0.52)
                        
                        // Verified badge
                        Image(systemName: "checkmark.seal.fill")
                            .poplurIconShader()
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                    }
                    
                    // Location
                    if let city = post.cityName, let country = post.countryName {
                        Text("\(city), \(country)")
                            .font(.system(size: 13))
                            .foregroundColor(.black.opacity(0.6))
                            .poplurTextShader(intensity: 0.44)
                    } else {
                        Text("Approximate map area")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.black.opacity(0.5))
                            .poplurTextShader(intensity: 0.42)
                    }
                }
                
                Spacer()
                
                // More menu
                Button {
                    // More options
                } label: {
                    Image(systemName: "ellipsis")
                        .poplurIconShader()
                        .font(.system(size: 18))
                        .foregroundColor(.black)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Media container (square)
            GeometryReader { geo in
                ZStack {
                    if isVideo {
                        if let player = player {
                            VideoPlayer(player: player)
                                .disabled(true)
                                .frame(width: geo.size.width, height: geo.size.width)
                                .clipped()
                        } else {
                            Color.black
                                .overlay(ProgressView().tint(.white))
                                .frame(width: geo.size.width, height: geo.size.width)
                                .clipped()
                        }
                    } else {
                        AsyncImage(url: URL(string: post.mediaURL)) { phase in
                            switch phase {
                            case .empty:
                                Color.black
                                    .overlay(ProgressView())
                                    .frame(width: geo.size.width, height: geo.size.width)
                                    .clipped()
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width, height: geo.size.width)
                                    .clipped()
                            case .failure:
                                Color.black
                                    .overlay(
                                        Image(systemName: "photo")
                                            .poplurIconShader()
                                            .font(.system(size: 40))
                                            .foregroundColor(.white.opacity(0.85))
                                    )
                                    .frame(width: geo.size.width, height: geo.size.width)
                                    .clipped()
                            @unknown default:
                                Color.black
                                    .frame(width: geo.size.width, height: geo.size.width)
                                    .clipped()
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.width)
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            
            // Action buttons
            HStack(spacing: 16) {
                // Like
                Button {
                    // Like action
                } label: {
                    Image(systemName: "heart")
                        .poplurIconShader()
                        .font(.system(size: 26, weight: .regular))
                        .foregroundColor(.black)
                }
                
                // Comment
                Button {
                    // Comment action
                } label: {
                    Image(systemName: "message")
                        .poplurIconShader()
                        .font(.system(size: 26, weight: .regular))
                        .foregroundColor(.black)
                }
                
                // Share
                Button {
                    // Share action
                } label: {
                    Image(systemName: "paperplane")
                        .poplurIconShader()
                        .font(.system(size: 26, weight: .regular))
                        .foregroundColor(.black)
                }
                
                Spacer()
                
                // Bookmark
                Button {
                    // Bookmark action
                } label: {
                    Image(systemName: "bookmark")
                        .poplurIconShader()
                        .font(.system(size: 26, weight: .regular))
                        .foregroundColor(.black)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // Radius count (instead of likes)
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "circle.fill")
                        .poplurIconShader()
                        .font(.system(size: 8))
                        .foregroundColor(.blue)
                    
                    Text(formatRadiusCount(post.radius))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .poplurTextShader(intensity: 0.5)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            
            // Caption
            HStack(alignment: .top, spacing: 6) {
                Text(displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .poplurTextShader(intensity: 0.5)
                
                (
                    Text("Which is your favorite? ")
                        .font(.system(size: 14))
                        .foregroundColor(.black)
                    +
                    Text("more")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                )
                .poplurTextShader(intensity: 0.42)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            
            // View all comments
            HStack {
                Text("View all 255 comments")
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .poplurTextShader(intensity: 0.42)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            
            // Timestamp
            HStack {
                Text("7 hours ago")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .poplurTextShader(intensity: 0.38)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .background(Color.white)
        .onAppear {
            if isVideo {
                setupVideoPlayer()
            }
        }
        .onDisappear {
            teardownVideoPlayer()
        }
        .onTapGesture {
            onDismiss()
        }
    }
    
    private func setupVideoPlayer() {
        guard let url = URL(string: post.mediaURL) else { return }
        teardownVideoPlayer()
        let player = AVPlayer(url: url)
        player.isMuted = true
        self.player = player
        player.play()
        
        // Loop video
        videoEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
    }

    private func teardownVideoPlayer() {
        if let videoEndObserver {
            NotificationCenter.default.removeObserver(videoEndObserver)
            self.videoEndObserver = nil
        }
        player?.pause()
        player = nil
    }
    
    private func formatRadiusCount(_ radius: Double) -> String {
        // Format like "100.0k m" similar to "7,264 likes"
        if radius >= 1_000_000 {
            return String(format: "%.1fM m", radius / 1_000_000)
        } else if radius >= 1_000 {
            return String(format: "%.1fk m", radius / 1_000)
        } else {
            return String(format: "%.0f m", radius)
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
    // MARK: - Preview
    
    #Preview {
        let samplePosts = [
            FeedPost(
                id: "1",
                latitude: 25.7617,
                longitude: -80.1918,
                mediaURL: "https://picsum.photos/1080/1920",
                radius: 100_000,
                viewCount: 7264,
                userID: "user1",
                cityName: "Tokyo",
                countryName: "Japan",
                countryFlag: "🇯🇵"
            )
        ]
        
        FeedTimelineView(
            posts: samplePosts,
            displayNameProvider: { _ in "User food_u" },
            onPostTapped: { _ in }
        )
    }
}
