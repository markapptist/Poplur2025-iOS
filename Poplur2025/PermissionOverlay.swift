import SwiftUI
import UIKit

struct PermissionOverlay: View {
    var title: String = "Camera Access Needed"
    var message: String = "Please enable camera access in Settings to record photos and videos."
    var buttonTitle: String = "Open Settings"
    var onPrimaryAction: (() -> Void)?

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)

                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundColor(.white)

                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white.opacity(0.85))
                    .padding(.horizontal, 24)

                Button {
                    if let onPrimaryAction {
                        onPrimaryAction()
                    } else if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    }
                } label: {
                    Text(buttonTitle)
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(Color.white)
                        .foregroundColor(.black)
                        .clipShape(Capsule())
                }
                .padding(.top, 6)
            }
            .padding(24)
        }
    }
}

#Preview {
    PermissionOverlay()
}
