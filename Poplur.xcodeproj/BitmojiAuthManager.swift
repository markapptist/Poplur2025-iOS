import Foundation
import FirebaseAuth
import FirebaseFirestore

// If your Snap Kit SPM exposes these modules, import them accordingly:
// import SCSDKLoginKit
// import SCSDKBitmojiKit

@MainActor
final class BitmojiAuthManager: ObservableObject {
    static let shared = BitmojiAuthManager()

    @Published private(set) var isLoggedInToSnap = false
    @Published private(set) var bitmojiAvatarURL: URL?

    private let db = Firestore.firestore()

    private init() { }

    func loginWithSnapchat() async {
        // TODO: Replace with actual Snap Kit Login call for SPM version you installed.
        // Pseudocode:
        // SCSDKLoginClient.login(from: presentingViewController) { success, error in ... }

        // For SwiftUI, you may need a UIKit host to present. Here we show intent; you can build a small UIKit presenter if needed.
        // After success:
        await fetchBitmojiAvatarAndPersist()
        isLoggedInToSnap = true
    }

    func logoutSnapchat() async {
        // TODO: Call Snap Kit logout if available
        isLoggedInToSnap = false
        bitmojiAvatarURL = nil
    }

    func fetchBitmojiAvatarAndPersist() async {
        // TODO: Use Snap Kit Bitmoji API to fetch avatar URL.
        // Pseudocode:
        // SCSDKBitmojiClient.fetchAvatarURL { urlString, error in ... }

        // For now, expect we obtained a string:
        let fetchedURLString: String? = nil // replace with real result

        guard let uid = Auth.auth().currentUser?.uid else { return }

        if let urlString = fetchedURLString, let url = URL(string: urlString) {
            bitmojiAvatarURL = url
            do {
                try await db.collection("users").document(uid).setData(["bitmojiAvatarURL": urlString], merge: true)
            } catch {
                print("Failed to write bitmojiAvatarURL: \(error.localizedDescription)")
            }
        }
    }

    // Utility to read a user's bitmoji URL (used by ProfileView/MapView)
    func fetchUserBitmojiURL(uid: String) async -> URL? {
        do {
            let snap = try await db.collection("users").document(uid).getDocument()
            if let data = snap.data(),
               let s = data["bitmojiAvatarURL"] as? String,
               let u = URL(string: s) {
                return u
            }
        } catch {
            print("fetchUserBitmojiURL error: \(error.localizedDescription)")
        }
        return nil
    }
}
