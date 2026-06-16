// MARK: - Agora credentials
// 1. Go to console.agora.io → create a project → copy the App ID below.
// 2. Add the AgoraRtcKit SDK via Swift Package Manager:
//    File → Add Package → https://github.com/AgoraIO/AgoraRtcEngine_iOS
//    (choose AgoraRtcKit product)
// 3. Uncomment the Agora lines in CallSessionManager.swift.
// 4. For production: add a token server and set tokenServerURL.

enum CallCredentials {
    static let agoraAppId       = "YOUR_AGORA_APP_ID"   // replace after sign-up
    static let tokenServerURL: String? = nil             // optional – nil = no-token mode (dev only)
}
