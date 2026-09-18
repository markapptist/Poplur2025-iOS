import SwiftUI

// Compatibility name for existing call sites. Both cold launch and the auth
// handoff now use the same native AVFoundation splash, with no WebView host.
struct PostLoginLoadingWebView: View {
    var onFinished: () -> Void = {}
    var body: some View { NativePreloginSplash(onFinished: onFinished) }
}
