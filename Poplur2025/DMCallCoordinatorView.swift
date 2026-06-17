import SwiftUI
import SpriteKit

/// Shown when a DM phone or video call button is tapped.
/// Displays the Poplur phone UI with the callee's name on the LCD + ringtone,
/// then transitions to InAppVideoCallView when the call connects (video mode)
/// or remains on the phone showing call duration (audio mode).
struct DMCallCoordinatorView: View {
    let calleeName: String
    let isVideo: Bool
    let onDismiss: () -> Void

    @State private var phoneScene: PhoneScene
    @State private var showVideoCall = false
    @State private var elapsed = 0
    @State private var connectTask: Task<Void, Never>?
    @State private var timerTask: Task<Void, Never>?

    init(calleeName: String, isVideo: Bool, onDismiss: @escaping () -> Void) {
        self.calleeName = calleeName
        self.isVideo = isVideo
        self.onDismiss = onDismiss
        _phoneScene = State(initialValue: PhoneScene(callingUser: FakeUser(id: UUID(), name: calleeName)))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            SpriteView(scene: phoneScene, options: [.allowsTransparency])
                .ignoresSafeArea()

            // Hang-up button
            VStack {
                Spacer()
                Button(action: endCall) {
                    Image(systemName: "phone.down.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(Color.red, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 56)
            }

            // Video overlay when connected
            if showVideoCall {
                InAppVideoCallView(calleeName: calleeName, onEnd: endCall)
            }
        }
        .statusBarHidden()
        .onAppear {
            phoneScene.applyCallState(.outgoing(calleeName: calleeName), elapsed: 0)
            connectTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                phoneScene.applyCallState(.connected(calleeName: calleeName, channelId: ""), elapsed: 0)
                if isVideo {
                    showVideoCall = true
                } else {
                    startDurationTimer()
                }
            }
        }
        .onDisappear {
            connectTask?.cancel()
            timerTask?.cancel()
            phoneScene.stopAllSounds()
        }
    }

    private func startDurationTimer() {
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsed += 1
                phoneScene.applyCallState(.connected(calleeName: calleeName, channelId: ""), elapsed: elapsed)
            }
        }
    }

    private func endCall() {
        connectTask?.cancel()
        timerTask?.cancel()
        phoneScene.applyCallState(.ended(reason: .hangUp), elapsed: elapsed)
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            onDismiss()
        }
    }
}
