import SwiftUI
import SpriteKit

/// Full-screen incoming call UI — shown when another user calls you.
/// Displays the Poplur phone with "INCOMING [CALLER]" on the LCD + ringtone.
struct IncomingCallView: View {
    let callerName: String
    let channelId: String
    let documentId: String

    @State private var phoneScene: PhoneScene

    init(callerName: String, channelId: String, documentId: String) {
        self.callerName = callerName
        self.channelId = channelId
        self.documentId = documentId
        _phoneScene = State(initialValue: PhoneScene(callingUser: FakeUser(id: UUID(), name: callerName)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            SpriteView(scene: phoneScene, options: [.allowsTransparency])
                .ignoresSafeArea()

            // Accept / Decline buttons
            VStack {
                Spacer()
                HStack(spacing: 64) {
                    CallActionButton(icon: "phone.down.fill", label: "Decline", tint: .red) {
                        Task { await CallSessionManager.shared.declineCall(documentId: documentId) }
                    }
                    CallActionButton(icon: "phone.fill", label: "Accept", tint: .green) {
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
        .statusBarHidden()
        .onAppear {
            phoneScene.applyCallState(
                .incoming(callerName: callerName, channelId: channelId, documentId: documentId),
                elapsed: 0
            )
        }
        .onDisappear {
            phoneScene.stopAllSounds()
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
                    .poplurIconShader()
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
