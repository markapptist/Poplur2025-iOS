import SwiftUI
import Foundation

struct FeedPost: Identifiable, Hashable, Sendable {
    let id: String
    let latitude: Double
    let longitude: Double
    let mediaURL: String
    let radius: Double
    let viewCount: Int
    let userID: String
    
    // Location metadata for enhanced map display
    var cityName: String? = nil
    var countryName: String? = nil
    var countryFlag: String? = nil
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // Equatable conformance
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

struct FeedFullscreenPage: View {
    let post: FeedPost
    let displayName: String
    let onUserTapped: (String) -> Void

    var body: some View {
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
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 10) {
                Button {
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
}

#Preview {
    let sample = FeedPost(
        id: "demo",
        latitude: 37.3349,
        longitude: -122.0090,
        mediaURL: "https://picsum.photos/800/1200",
        radius: 3000,
        viewCount: 42,
        userID: "user_123",
        cityName: "San Jose",
        countryName: "USA",
        countryFlag: "🇺🇸"
    )
    return FeedFullscreenPage(post: sample, displayName: "Sample User") { _ in }
}
