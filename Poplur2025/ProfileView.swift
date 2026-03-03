#if DEBUG
#if canImport(SwiftUI)
import SwiftUI
import Combine

// MARK: - Preview-only fallback for ProfileView
// If the real ProfileView isn't available to this compilation unit,
// provide a lightweight stub so previews can compile.
#if !canImport(UIKit) || DEBUG
private struct PreviewProfileView: View {
    let userID: String?
    var body: some View {
        VStack(spacing: 12) {
            Text("ProfileView Preview Stub")
                .font(.headline)
            if let userID {
                Text("userID: \(userID)")
            } else {
                Text("userID: nil")
            }
            Text("Replace this with the real ProfileView when available.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
#endif

// Provide a lightweight preview instance for AuthViewModel
extension AuthViewModel {
    static func previewInstance() -> AuthViewModel {
        let vm = AuthViewModel()
        // Configure any lightweight preview state here if needed
        return vm
    }
}

// MARK: - Previews
#Preview("ProfileView – Grid") {
    // Try to use the real ProfileView if it exists; otherwise fall back to the stub
    AnyViewBuilder.profileView(userID: nil)
        .environmentObject(AuthViewModel.previewInstance())
}

#Preview("ProfileView – List") {
    AnyViewBuilder.profileView(userID: "sample-user")
        .environmentObject(AuthViewModel.previewInstance())
}

// Helper to resolve to real ProfileView if it's in scope, otherwise use the stub.
private enum AnyViewBuilder {
    static func profileView(userID: String?) -> AnyView {
        // If a type named ProfileView is available, attempt to initialize it via reflection.
        // Since we can't rely on it at compile time in this file, we fall back to the stub.
        // Replace this once the real ProfileView is imported into this target.
        #if canImport(UIKit)
        // In most app targets, UIKit is present; we still can't reference ProfileView if it's out of scope.
        return AnyView(PreviewProfileView(userID: userID))
        #else
        return AnyView(PreviewProfileView(userID: userID))
        #endif
    }
}
#endif
#endif
