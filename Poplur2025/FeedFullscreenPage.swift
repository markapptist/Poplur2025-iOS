import SwiftUI
import Foundation

struct FeedPost: Identifiable {
    let id: String
    let latitude: Double
    let longitude: Double
    let mediaURL: String
    let radius: Double
    let viewCount: Int
    let userID: String
}

struct FeedFullscreenPage: View {
    let post: FeedPost
    let displayName: String
    let onUserTapped: (String) -> Void

    @State private var radiusDelta: Double = 0
    @State private var voteFeedback: VoteFeedback?
    @State private var didCountView = false

    private enum VoteFeedback {
        case up
        case down

        var icon: String {
            switch self {
            case .up: return "hand.thumbsup.fill"
            case .down: return "hand.thumbsdown.fill"
            }
        }

        var alignment: Alignment {
            switch self {
            case .up: return .centerLeading
            case .down: return .centerTrailing
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
            Color.black.ignoresSafeArea()

            if let url = URL(string: post.mediaURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }

            inlineAdSlot(size: geo.size)
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { applyVote(.up) }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { applyVote(.down) }
            }
        }
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 10) {
                Button {
                    addRadius(1, reason: "profile_open_after_view")
                    onUserTapped(post.userID)
                } label: {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "person.fill")
                                .foregroundStyle(.white)
                        )
                }
                .buttonStyle(.plain)

                Text(displayName.isEmpty ? "" : displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(16)
        }
        .overlay(alignment: .topTrailing) {
            Text("\(String(format: "%.0f", max(0, post.radius + radiusDelta))) km")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.46), in: Capsule())
                .padding(16)
        }
        .overlay(alignment: voteFeedback?.alignment ?? .center) {
            if let voteFeedback {
                Image(systemName: voteFeedback.icon)
                    .font(.system(size: 72, weight: .black))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 18)
                    .padding(.horizontal, 44)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .task {
            guard !didCountView else { return }
            didCountView = true
            addRadius(1, reason: "video_view")
            scheduleNoViewDecayIfNeeded()
        }
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 40, weight: .regular))
                .foregroundStyle(.white.opacity(0.9))
            Text("Unable to load media")
                .foregroundStyle(.white.opacity(0.8))
                .font(.system(size: 14))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func inlineAdSlot(size: CGSize) -> some View {
        if size.width >= 700 {
            PoplurInlineAdFallback()
                .frame(width: min(360, size.width * 0.32))
                .padding(.trailing, 28)
                .padding(.bottom, 228)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        } else {
            PoplurInlineAdFallback()
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 18)
                .padding(.bottom, 168)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func applyVote(_ vote: VoteFeedback) {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.7)) {
            voteFeedback = vote
        }
        addRadius(vote == .up ? 1 : -1, reason: vote == .up ? "like" : "downvote")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            withAnimation(.easeOut(duration: 0.2)) {
                voteFeedback = nil
            }
        }
    }

    private func addRadius(_ amount: Double, reason: String) {
        radiusDelta += amount
        NotificationCenter.default.post(
            name: Notification.Name("PoplurRadiusEngagementDelta"),
            object: post.id,
            userInfo: ["delta": amount, "reason": reason, "postID": post.id]
        )
    }

    private func scheduleNoViewDecayIfNeeded() {
        guard post.viewCount <= 0 else { return }
        Task {
            try? await Task.sleep(nanoseconds: 3_600_000_000_000)
            await MainActor.run {
                addRadius(-1, reason: "no_view_after_one_hour")
            }
        }
    }
}

private struct PoplurInlineAdFallback: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles.tv.fill")
                .font(.system(size: 20, weight: .black))
            VStack(alignment: .leading, spacing: 2) {
                Text("POPLUR AD")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                Text("Real Google slots appear here when production AdMob IDs are configured.")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .lineLimit(2)
            }
            Spacer()
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

#Preview {
    let sample = FeedPost(
        id: "demo",
        latitude: 37.3349,
        longitude: -122.0090,
        mediaURL: "https://picsum.photos/800/1200",
        radius: 3000,
        viewCount: 42,
        userID: "user_123"
    )
    return FeedFullscreenPage(post: sample, displayName: "Sample User") { _ in }
}
