import SwiftUI

struct LoadingOverlayView: View {
    // Controls visibility from parent
    let isPresented: Bool
    // Optional brand color; defaults to pink to match previous design
    var background: Color = .pink
    // Optional logo image name
    var logoName: String? = "logo"

    var body: some View {
        ZStack {
            if isPresented {
                background
                    .ignoresSafeArea()
                    .transition(.opacity)
                Group {
                    if let name = logoName, UIImage(named: name) != nil {
                        Image(name)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 80, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.35), value: isPresented)
    }
}

#Preview {
    LoadingOverlayView(isPresented: true)
}
