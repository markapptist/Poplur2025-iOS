import Foundation
import UIKit

// Replace these with real Snap Kit imports once your SPM package is added.
// If your package uses different product names, adjust the imports accordingly.
import SCSDKLoginKit
import SCSDKBitmojiKit

@MainActor
final class BitmojiManager: ObservableObject {
    static let shared = BitmojiManager()

    // TODO: Replace with your real Client ID from developers.snap.com
    private let clientID = "SNAP_CLIENT_ID_PLACEHOLDER"

    // TODO: Replace with your real redirect scheme registered in your Info.plist URL Types
    // Example: "com.your.bundle.snapkit"
    private let redirectScheme = "snapkit-placeholder-redirect"

    private init() { }

    // Public API: Presents Snapchat login and returns Bitmoji avatar URL if available
    func signInAndFetchAvatarURL(from presentingVC: UIViewController) async throws -> String? {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String?, Error>) in
            SCSDKLoginClient.login(from: presentingVC) { success, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                guard success else {
                    cont.resume(returning: nil)
                    return
                }
                // Logged in, fetch user data with Bitmoji
                self.fetchBitmojiAvatarURL { urlString, fetchError in
                    if let fetchError = fetchError {
                        cont.resume(throwing: fetchError)
                    } else {
                        cont.resume(returning: urlString)
                    }
                }
            }
        }
    }

    // Fetch Bitmoji avatar URL via Bitmoji Kit
    private func fetchBitmojiAvatarURL(completion: @escaping (String?, Error?) -> Void) {
        // The Bitmoji SDK provides fetchers for avatar URLs. Depending on the SDK version, this may vary.
        // Example approach using SCSDKBitmojiClient to fetch a 2D avatar URL:
        SCSDKBitmojiClient.fetchAvatarURL { urlString, error in
            completion(urlString, error)
        }
    }

    // Optional: call this from SceneDelegate/AppDelegate openURL to let Snap Kit handle callback
    static func handleOpenURL(_ url: URL) -> Bool {
        return SCSDKLoginClient.application(UIApplication.shared, open: url, options: [:])
    }
}

