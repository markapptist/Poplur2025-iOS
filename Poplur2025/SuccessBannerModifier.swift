import SwiftUI

struct SuccessBanner: ViewModifier {
    @Binding var message: String?
    @State private var isVisible = false
    @State private var hideWorkItem: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isVisible, let message = message {
                        bannerView(message: message)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .animation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0), value: isVisible)
                    }
                }
                .frame(maxWidth: .infinity)
                .ignoresSafeArea(edges: .top)
                , alignment: .top
            )
            .onChange(of: message) { newValue in
                if let _ = newValue {
                    showBanner()
                } else {
                    hideBanner()
                }
            }
    }

    private func showBanner() {
        hideWorkItem?.cancel()
        isVisible = true

        let workItem = DispatchWorkItem {
            withAnimation {
                isVisible = false
                message = nil
            }
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: workItem)
    }

    private func hideBanner() {
        hideWorkItem?.cancel()
        withAnimation {
            isVisible = false
        }
    }

    private func bannerView(message: String) -> some View {
        Text(message)
            .font(.callout.bold())
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 20)
            .frame(maxWidth: 600)
            .background(
                Capsule()
                    .fill(Color.green.opacity(0.95))
                    .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 2)
            )
            .padding(.horizontal)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityHint("Success message")
    }
}

extension View {
    func successBanner(_ message: Binding<String?>) -> some View {
        modifier(SuccessBanner(message: message))
    }
}
