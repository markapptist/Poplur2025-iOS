import SwiftUI

/// Full-screen incoming call UI — shown when another user calls you.
struct IncomingCallView: View {
    let callerName: String
    let channelId: String
    let documentId: String

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Avatar pulse ring
                ZStack {
                    Circle()
                        .stroke(Color.green.opacity(0.25), lineWidth: 2)
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseScale)
                        .opacity(2 - pulseScale)

                    Circle()
                        .fill(Color(white: 0.18))
                        .frame(width: 96, height: 96)

                    Text(String(callerName.prefix(1)).uppercased())
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                        pulseScale = 1.55
                    }
                }

                Spacer().frame(height: 28)

                Text(callerName)
                    .font(.title.bold())
                    .foregroundColor(.white)

                Text("Poplur Call")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.55))
                    .padding(.top, 6)

                Spacer()

                // Action buttons
                HStack(spacing: 64) {
                    CallActionButton(
                        icon: "phone.down.fill",
                        label: "Decline",
                        tint: .red
                    ) {
                        Task { await CallSessionManager.shared.declineCall(documentId: documentId) }
                    }

                    CallActionButton(
                        icon: "phone.fill",
                        label: "Accept",
                        tint: .green
                    ) {
                        Task {
                            await CallSessionManager.shared.acceptCall(
                                channelId: channelId,
                                documentId: documentId,
                                callerName: callerName
                            )
                        }
                    }
                }
                .padding(.bottom, 64)
            }
        }
    }
}

private struct CallActionButton: View {
    let icon: String
    let label: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 70, height: 70)
                    .background(tint)
                    .clipShape(Circle())
                Text(label)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .buttonStyle(.plain)
    }
}
