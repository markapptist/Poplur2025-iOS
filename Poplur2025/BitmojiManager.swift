import Foundation
import UIKit
import SCSDKLoginKit
import SCSDKBitmojiKit

@MainActor
final class BitmojiManager: ObservableObject {
    static let shared = BitmojiManager()

    // Your Snap Kit Client ID from developers.snap.com
    private let clientID = "e03c56c8-814b-480b-b910-a99bcd825d04"

    // iOS custom URL scheme for Snap Kit OAuth callback.
    // IMPORTANT: Also register this scheme on developers.snap.com for your iOS app.
    // Example full callback path: sirmulio-snapkit://snap-kit/oauth2
    private let redirectScheme = "sirmulio-snapkit"

    private init() { }

    // Public API: Presents Snapchat login and returns Bitmoji avatar URL if available
    func signInAndFetchAvatarURL(from presentingVC: UIViewController) async throws -> String? {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String?, Error>) in
            // Ensure login client is ready; some SDK versions require configuration.
            // SCSDKLoginClient may read configuration from Info.plist / dashboard.
            SCSDKLoginClient.login(from: presentingVC) { success, error in
                if let error = error {
                    cont.resume(throwing: error)
                    return
                }
                guard success else {
                    cont.resume(returning: nil)
                    return
                }
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
        SCSDKBitmojiClient.fetchAvatarURL { urlString, error in
            completion(urlString, error)
        }
    }

    // Forward OAuth callback from SceneDelegate/AppDelegate
    static func handleOpenURL(_ url: URL) -> Bool {
        return SCSDKLoginClient.application(UIApplication.shared, open: url, options: [:])
    }
}

