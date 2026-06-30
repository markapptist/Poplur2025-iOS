import SwiftUI

#if DEBUG
@MainActor
struct RecordTab_Previews: PreviewProvider {
    static var previews: some View {
        RealTabLayoutPreviewShell(tab: .record) {
            RecordPreviewSkeleton()
        }
        .previewDisplayName("Record UI Layout")
    }
}

private struct RecordPreviewSkeleton: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.06, blue: 0.07),
                    Color(red: 0.12, green: 0.16, blue: 0.19)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .overlay {
                    VStack(spacing: 14) {
                        Image(systemName: "camera.viewfinder")
                            .poplurIconShader()
                            .font(.system(size: 54, weight: .semibold))
                        Text("Record Preview")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .poplurTextShader(intensity: 0.9)
                    }
                    .foregroundStyle(.white.opacity(0.72))
                }

            VStack(spacing: 10) {
                Text("Hold to capture")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .poplurTextShader(intensity: 0.8)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.42), in: Capsule())

                Spacer()

                Circle()
                    .strokeBorder(.white, lineWidth: 5)
                    .background(Circle().fill(.white.opacity(0.16)))
                    .frame(width: 86, height: 86)
                    .padding(.bottom, 36)
            }
            .padding(.top, 62)
            .allowsHitTesting(false)
        }
        .background(Color.black)
    }
}
#endif
