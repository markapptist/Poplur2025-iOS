//
//  CommentSectionView.swift
//  Poplur2025
//
//  Comment section overlay for feed posts
//

import SwiftUI

// MARK: - Comment Model

struct PostComment: Identifiable {
    let id: String
    let userID: String
    let username: String
    let text: String
    let timestamp: Date
    var likeCount: Int
    var isLikedByCurrentUser: Bool
    
    init(id: String = UUID().uuidString, userID: String, username: String, text: String, timestamp: Date = Date(), likeCount: Int = 0, isLikedByCurrentUser: Bool = false) {
        self.id = id
        self.userID = userID
        self.username = username
        self.text = text
        self.timestamp = timestamp
        self.likeCount = likeCount
        self.isLikedByCurrentUser = isLikedByCurrentUser
    }
}

// MARK: - Comment Section View

struct CommentSectionView: View {
    let postID: String
    let onDismiss: () -> Void
    
    @State private var comments: [PostComment] = []
    @State private var newCommentText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    // Demo users for fake comments
    private let demoUsers = [
        ("user1", "Sarah Johnson"),
        ("user2", "Mike Chen"),
        ("user3", "Emma Davis"),
        ("user4", "Alex Rivera"),
        ("user5", "Jessica Martinez"),
        ("user6", "David Kim"),
        ("user7", "Rachel Green"),
        ("user8", "Chris Taylor"),
        ("user9", "Maya Patel"),
        ("user10", "Jordan Blake")
    ]
    
    private let demoCommentTexts = [
        "This is amazing! 😍",
        "Great shot!",
        "Love this! 🔥",
        "Incredible view",
        "How did you get there?",
        "Beautiful!",
        "This is so cool!",
        "Wow! 🤩",
        "Stunning!",
        "Need to visit this place",
        "Goals 🙌",
        "Perfect timing!",
        "This is breathtaking",
        "Absolutely beautiful",
        "Can't believe this is real",
        "What camera did you use?",
        "This is insane! 🤯",
        "Added to my bucket list",
        "Dream location",
        "Spectacular!"
    ]
    
    var body: some View {
        ZStack {
            // Dimmed background - tap to dismiss
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    // Haptic feedback on dismiss
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                }
            
            // Position card at bottom, then animate to center
            VStack {
                Spacer()
                
                // Comment section card
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Comments")
                            .font(DS.Font.heading())
                            .foregroundStyle(DS.Color.textPrimary)

                        Spacer()

                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(DS.Color.card)

                    PoplurRowSeparator()

                    // Comments list
                    if comments.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 44))
                                .foregroundStyle(DS.Color.textSecondary.opacity(0.5))

                            Text("No comments yet")
                                .font(DS.Font.body())
                                .foregroundStyle(DS.Color.textSecondary)

                            Text("Be the first to comment!")
                                .font(DS.Font.caption())
                                .foregroundStyle(DS.Color.textSecondary.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DS.Color.background)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(comments) { comment in
                                    CommentRowView(
                                        comment: comment,
                                        onLike: { toggleLike(for: comment.id) },
                                        onUsernameTap: {
                                            NotificationCenter.default.post(
                                                name: .ShowUserProfile,
                                                object: comment.userID
                                            )
                                            onDismiss()
                                        }
                                    )
                                }
                            }
                            .padding()
                        }
                        .background(DS.Color.background)
                    }

                    PoplurRowSeparator()

                    // Comment input
                    HStack(spacing: 12) {
                        TextField("Add a comment...", text: $newCommentText)
                            .textFieldStyle(.plain)
                            .font(DS.Font.body(15))
                            .foregroundStyle(DS.Color.textPrimary)
                            .tint(DS.Color.accent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(DS.Color.fill, in: Capsule())
                            .focused($isTextFieldFocused)

                        Button(action: {
                            if !newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                newCommentText = ""
                                isTextFieldFocused = false
                            }
                        }) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(newCommentText.isEmpty ? DS.Color.textSecondary : DS.Color.accent)
                                .frame(width: 44, height: 44)
                        }
                        .disabled(newCommentText.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(DS.Color.card)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 500)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                .shadow(color: DS.Shadow.hero.color, radius: DS.Shadow.hero.radius, x: DS.Shadow.hero.x, y: DS.Shadow.hero.y)
                .padding(.horizontal, 16)
                .padding(.bottom, 60)
                
                Spacer()
                    .frame(height: 40)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            generateFakeComments()
            // Haptic feedback when appearing
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
    
    // MARK: - Helper Functions
    
    private func generateFakeComments() {
        // Generate 3-8 fake comments for demo
        let commentCount = Int.random(in: 3...8)
        var generatedComments: [PostComment] = []
        
        for _ in 0..<commentCount {
            let user = demoUsers.randomElement() ?? demoUsers[0]
            let text = demoCommentTexts.randomElement() ?? "Nice!"
            let timestamp = Date().addingTimeInterval(-Double.random(in: 60...86400)) // Random time in last day
            let likeCount = Int.random(in: 0...50)
            
            let comment = PostComment(
                userID: user.0,
                username: user.1,
                text: text,
                timestamp: timestamp,
                likeCount: likeCount,
                isLikedByCurrentUser: Bool.random()
            )
            
            generatedComments.append(comment)
        }
        
        // Sort by timestamp (newest first)
        comments = generatedComments.sorted { $0.timestamp > $1.timestamp }
    }
    
    private func toggleLike(for commentID: String) {
        guard let index = comments.firstIndex(where: { $0.id == commentID }) else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            comments[index].isLikedByCurrentUser.toggle()
            if comments[index].isLikedByCurrentUser {
                comments[index].likeCount += 1
            } else {
                comments[index].likeCount = max(0, comments[index].likeCount - 1)
            }
        }
        
        // Haptic feedback
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    
    private func timeAgoString(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(seconds / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Comment Row View

private struct CommentRowView: View {
    let comment: PostComment
    let onLike: () -> Void
    let onUsernameTap: () -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Profile image placeholder
            Circle()
                .fill(DS.Color.pinkCard)
                .frame(width: 36, height: 36)
                .overlay {
                    Text(comment.username.prefix(1).uppercased())
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Color.accent)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Button(action: onUsernameTap) {
                        Text(comment.username)
                            .font(DS.Font.label())
                            .foregroundStyle(DS.Color.textPrimary)
                    }

                    Text(timeAgoString(from: comment.timestamp))
                        .font(DS.Font.caption(12))
                        .foregroundStyle(DS.Color.textSecondary)

                    Spacer()
                }

                Text(comment.text)
                    .font(DS.Font.body(15))
                    .foregroundStyle(DS.Color.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onLike) {
                    HStack(spacing: 4) {
                        Image(systemName: comment.isLikedByCurrentUser ? "heart.fill" : "heart")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(comment.isLikedByCurrentUser ? DS.Color.accent : DS.Color.textSecondary)

                        if comment.likeCount > 0 {
                            Text("\(comment.likeCount)")
                                .font(DS.Font.caption(12))
                                .foregroundStyle(DS.Color.textSecondary)
                        }
                    }
                }
                .padding(.top, 4)
            }
            
            Spacer()
        }
    }
    
    private func timeAgoString(from date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h"
        } else {
            let days = Int(seconds / 86400)
            return "\(days)d"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CommentSectionView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            CommentSectionView(
                postID: "demo-post-1",
                onDismiss: { print("Dismissed") }
            )
        }
    }
}
#endif
