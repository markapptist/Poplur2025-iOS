import SwiftUI
import UIKit

struct PermissionOverlay: View {
    var openSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .poplurIconShader()
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(.white)

            Text("Camera Permission Needed")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)

            Text("Enable camera access in Settings to record.")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))

            Button(action: openSettings) {
                Text("Open Settings")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundColor(.black)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 20)
                    .background(Capsule().fill(Color.white))
            }
            .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }
}
