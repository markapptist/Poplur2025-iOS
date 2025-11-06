import SwiftUI
import FirebaseFirestore
import FirebaseAuth

struct BitmojiAvatarView: View {
    let userID: String?
    let fallbackURL: URL?
    let size: CGFloat

    @State private var bitmojiURL: URL?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let url = bitmojiURL ?? fallbackURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image.resizable().scaledToFill()
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
        .onAppear { loadURL() }
    }

    private var placeholder: some View {
        Circle().fill(Color.gray.opacity(0.3))
    }

    private func loadURL() {
        guard let uid = userID else {
            isLoading = false
            return
        }
        Task {
            if let u = await BitmojiAuthManager.shared.fetchUserBitmojiURL(uid: uid) {
                await MainActor.run {
                    self.bitmojiURL = u
                    self.isLoading = false
                }
            } else {
                await MainActor.run { self.isLoading = false }
            }
        }
    }
}
