import SwiftUI

#if DEBUG
@MainActor
struct MapView_Previews: PreviewProvider {
    static var previews: some View {
        RealTabLayoutPreviewShell(tab: .map) {
            MapViewProduction(layoutPreviewOnly: true)
        }
        .previewDisplayName("Map UI Layout")
    }
}
#endif
