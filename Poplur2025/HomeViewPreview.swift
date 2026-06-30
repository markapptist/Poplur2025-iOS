import SwiftUI

#if DEBUG
@MainActor
struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            RealTabLayoutPreviewShell(tab: .record) {
                RecordPreviewSkeletonForHome()
            }
            .previewDisplayName("Home UI Layout - Record")

            RealTabLayoutPreviewShell(tab: .map) {
                MapPreviewSkeletonForHome()
            }
            .previewDisplayName("Home UI Layout - Map")
        }
        .ignoresSafeArea(.container, edges: [.bottom, .leading, .trailing])
    }
}

private struct RecordPreviewSkeletonForHome: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "camera.viewfinder")
                    .poplurIconShader()
                    .font(.system(size: 54, weight: .semibold))
                Text("Record")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white.opacity(0.76))
        }
    }
}

private struct MapPreviewSkeletonForHome: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.13, blue: 0.12),
                    Color(red: 0.16, green: 0.20, blue: 0.22)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 4) {
                Text("Toronto")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                Text("Map")
                    .font(.system(size: 14, weight: .semibold))
                    .opacity(0.70)
                Spacer()
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 28)
        }
    }
}
#endif
