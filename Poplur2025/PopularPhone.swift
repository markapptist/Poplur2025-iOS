import SwiftUI
import SpriteKit

/// Full-screen phone interface for placing in-app calls to another user.
/// Observes CallSessionManager and forwards state changes to PhoneScene's LCD.
struct PopularPhone: View {
    let user: FakeUser

    @State private var phoneScene: PhoneScene
    @ObservedObject private var callManager = CallSessionManager.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("poplur_phoneXLMode") private var phoneXLMode: Bool = true
    @State private var selectedColorway = PoplurPhoneColorway.all[0]
    @State private var isLCDActive = false

    init(user: FakeUser) {
        self.user = user
        let scene = PhoneScene(callingUser: user)
        // Apply stored size preference before setupPhone runs in didMove(to:)
        if let stored = UserDefaults.standard.object(forKey: "poplur_phoneXLMode") as? Bool {
            scene.isXLSize = stored
        }
        _phoneScene = State(initialValue: scene)
    }

    var body: some View {
        ZStack {
            SpriteView(scene: phoneScene, options: [.allowsTransparency])
                .background(Color.black)
                .ignoresSafeArea()

            phoneColorSwipeArrows
                .zIndex(10)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .simultaneousGesture(phoneColorSwipeGesture)
        .onChange(of: phoneXLMode) { _, xl in
            phoneScene.applyPhoneSize(xl)
        }
        .onAppear {
            NotificationCenter.default.post(name: .popularPhoneDidPresent, object: nil)
            NotificationCenter.default.post(name: Notification.Name("CubeInteractionDisabled"), object: nil)
            phoneScene.applyPhoneSize(phoneXLMode)
            phoneScene.applyColorway(selectedColorway.bootupSpritesheetName)
            phoneScene.onDismiss = { dismiss() }
            phoneScene.onLCDActivated = { isLCDActive = true }
            phoneScene.onLCDDeactivated = { isLCDActive = false }
            // Wire the centre nav key -> in-app call / hang up when the hardware button is active.
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
            NotificationCenter.default.post(name: Notification.Name("CubeInteractionEnabled"), object: nil)
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

    private var phoneColorSwipeArrows: some View {
        HStack {
            swipeArrow(systemName: "chevron.left")
            Spacer()
            swipeArrow(systemName: "chevron.right")
        }
        .padding(.horizontal, 14)
        .allowsHitTesting(false)
    }

    private func swipeArrow(systemName: String) -> some View {
        Image(systemName: systemName)
            .poplurIconShader()
            .font(.system(size: 34, weight: .black))
            .foregroundStyle(Color.white.opacity(0.38))
            .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 2)
    }

    private var phoneColorSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 44, coordinateSpace: .local)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > 56, abs(horizontal) > abs(vertical) * 1.35 else { return }
                stepPhoneColor(by: horizontal < 0 ? 1 : -1)
            }
    }

    private func stepPhoneColor(by direction: Int) {
        guard let currentIndex = PoplurPhoneColorway.all.firstIndex(of: selectedColorway) else { return }
        let count = PoplurPhoneColorway.all.count
        let nextIndex = (currentIndex + direction + count) % count
        selectedColorway = PoplurPhoneColorway.all[nextIndex]
        phoneScene.applyColorway(selectedColorway.bootupSpritesheetName)
    }
}

struct PoplurPhoneColorway: Identifiable, Equatable {
    let id: String
    let title: String
    let bootupSpritesheetName: String
    let swatch: Color

    static let all: [PoplurPhoneColorway] = [
        PoplurPhoneColorway(id: "silver", title: "Silver", bootupSpritesheetName: "poplur_phone_bootup_silver_diamond", swatch: Color(red: 0.88, green: 0.88, blue: 0.84)),
        PoplurPhoneColorway(id: "gold", title: "Gold", bootupSpritesheetName: "poplur_phone_bootup_champagne_gold", swatch: Color(red: 0.96, green: 0.72, blue: 0.27)),
        PoplurPhoneColorway(id: "rose", title: "Rose", bootupSpritesheetName: "poplur_phone_bootup_rose_gold_pink", swatch: Color(red: 1.0, green: 0.55, blue: 0.63)),
        PoplurPhoneColorway(id: "ruby", title: "Ruby", bootupSpritesheetName: "poplur_phone_bootup_ruby_red", swatch: Color(red: 0.92, green: 0.06, blue: 0.06)),
        PoplurPhoneColorway(id: "sapphire", title: "Blue", bootupSpritesheetName: "poplur_phone_bootup_sapphire_blue", swatch: Color(red: 0.04, green: 0.33, blue: 0.95)),
        PoplurPhoneColorway(id: "emerald", title: "Green", bootupSpritesheetName: "poplur_phone_bootup_emerald_green", swatch: Color(red: 0.0, green: 0.74, blue: 0.25)),
        PoplurPhoneColorway(id: "amethyst", title: "Purple", bootupSpritesheetName: "poplur_phone_bootup_amethyst_purple", swatch: Color(red: 0.56, green: 0.24, blue: 0.92)),
        PoplurPhoneColorway(id: "onyx", title: "Onyx", bootupSpritesheetName: "poplur_phone_bootup_jet_black_onyx", swatch: Color(red: 0.08, green: 0.08, blue: 0.09)),
        PoplurPhoneColorway(id: "aqua", title: "Aqua", bootupSpritesheetName: "poplur_phone_bootup_icy_aqua_turquoise", swatch: Color(red: 0.20, green: 0.92, blue: 0.95)),
        PoplurPhoneColorway(id: "holo", title: "Holo", bootupSpritesheetName: "poplur_phone_bootup_holographic_iridescent", swatch: Color(red: 0.86, green: 0.64, blue: 1.0))
    ]
}

#Preview {
    #if DEBUG
    PopularPhone(user: FakeUser(id: UUID(), name: "Bob Smith"))
        .preferredColorScheme(.dark)
    #else
    EmptyView()
    #endif
}
