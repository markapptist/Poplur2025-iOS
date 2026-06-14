import SwiftUI

#if DEBUG
@MainActor
struct AppSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AppSettingsView(initialPageIndex: 1)
            .environment(\.layoutPreviewMode, true)
            .previewDisplayName("Settings UI Layout")
            .frame(width: 390, height: 844)
    }
}
#endif
