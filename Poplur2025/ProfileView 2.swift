// ProfileView.swift
// Minimal placeholder to satisfy navigation from FeedView
import SwiftUI

struct ProfileView: View {
    let userID: String

    var body: some View {
        VStack(spacing: 12) {
            Text("Profile")
                .font(.largeTitle).bold()
            Text("User ID: \(userID)")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ProfileView(userID: "user_123456")
    }
}
