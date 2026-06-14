import SwiftUI

#if DEBUG
@MainActor
struct ProfileView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileView()
            .environmentObject(AuthViewModel(previewAuthenticated: true))
            .previewDisplayName("Profile (Lightweight Preview)")
    }
}
#endif
