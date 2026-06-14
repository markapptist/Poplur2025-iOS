import SwiftUI

#if DEBUG
@MainActor
struct FeedView_Previews: PreviewProvider {
    static var previews: some View {
        RealTabLayoutPreviewShell(tab: .feed) {
            FeedView()
        }
        .previewDisplayName("Feed UI Layout")
    }
}
#endif
