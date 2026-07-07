import SwiftUI

struct ErrorBannerView: View {
    let message: String

    private var bannerImage: UIImage? {
        if let image = UIImage(named: "theme_banner_default") {
            return image
        }
        guard let url = Bundle.main.url(
            forResource: "theme_banner_default",
            withExtension: "png",
            subdirectory: "ThemeBanners"
        ) else {
            return nil
        }
        return UIImage(contentsOfFile: url.path)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .bold))
            Text(message)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(Color(red: 1.0, green: 45.0/255.0, blue: 150.0/255.0))
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ErrorBannerModifier: ViewModifier {
    @Binding var message: String?
    var autoDismissNanoseconds: UInt64 = 3_200_000_000

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message {
                ErrorBannerView(message: message)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: autoDismissNanoseconds)
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                            self.message = nil
                        }
                    }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: message)
    }
}

extension View {
    func errorBanner(_ message: Binding<String?>) -> some View {
        modifier(ErrorBannerModifier(message: message))
    }
}
