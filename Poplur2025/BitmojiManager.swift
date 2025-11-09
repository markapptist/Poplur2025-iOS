import Foundation
import UIKit
import SCSDKLoginKit

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

    // Public API: Presents Snapchat login and (formerly) Bitmoji avatar URL.
    // Since SCSDKBitmojiKit is deprecated/removed, we now just perform login and return nil.
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
                // No Bitmoji API available. Return nil to indicate no avatar fetched.
                cont.resume(returning: nil)
            }
        }
    }

    // Forward OAuth callback from SceneDelegate/AppDelegate
    static func handleOpenURL(_ url: URL) -> Bool {
        return SCSDKLoginClient.application(UIApplication.shared, open: url, options: [:])
    }
}
