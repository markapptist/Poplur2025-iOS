import SwiftUI

struct BitmojiAvatarView: View {
    let userID: String?
    let fallbackURL: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let url = fallbackURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            Circle().fill(Color.gray.opacity(0.2))
                            ProgressView().progressViewStyle(.circular)
                        }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
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
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.black.opacity(0.06), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        .accessibilityLabel("User Avatar")
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(Color.gray.opacity(0.2))
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(.secondary)
        }
    }
}

