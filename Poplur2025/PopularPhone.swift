import SwiftUI
import SpriteKit

/// Full-screen phone interface for placing in-app calls to another user.
/// Observes CallSessionManager and forwards state changes to PhoneScene's LCD.
struct PopularPhone: View {
    let user: FakeUser

    @State private var phoneScene: PhoneScene
    @ObservedObject private var callManager = CallSessionManager.shared
    @Environment(\.dismiss) private var dismiss

    init(user: FakeUser) {
        self.user = user
        _phoneScene = State(initialValue: PhoneScene(callingUser: user))
    }

    var body: some View {
        SpriteView(scene: phoneScene, options: [.allowsTransparency])
            .background(Color.black)
            .ignoresSafeArea()
            .onAppear {
                NotificationCenter.default.post(name: .popularPhoneDidPresent, object: nil)
                phoneScene.onDismiss = { dismiss() }
                // Wire the centre nav key → in-app call / hang up
                phoneScene.onCallButtonTapped = { [user] in
                    Task {
                        switch CallSessionManager.shared.callState {
                        case .idle:
                            await CallSessionManager.shared.placeCall(to: user)
                        case .outgoing, .connected:
                            await CallSessionManager.shared.endCall()
                        default:
                            break
                        }
                    }
                }
            }
            .onDisappear {
                phoneScene.stopAllSounds()
                Task { await callManager.endCall() }
            }
            // Forward call state to the SpriteKit LCD screen
            .onChange(of: callManager.callState) { _, newState in
                phoneScene.applyCallState(newState, elapsed: callManager.elapsedSeconds)
                // Dismiss automatically once the call has fully ended and state resets
                if case .idle = newState {
                    // Only auto-dismiss if we were in a call (not just opening the phone)
                }
            }
            .onChange(of: callManager.elapsedSeconds) { _, seconds in
                phoneScene.applyCallState(callManager.callState, elapsed: seconds)
            }
    }
}

#Preview {
    #if DEBUG
    PopularPhone(user: FakeUser(id: UUID(), name: "Bob Smith"))
        .preferredColorScheme(.dark)
    #else
    EmptyView()
    #endif
}
