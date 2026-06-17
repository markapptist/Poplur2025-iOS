import SwiftUI
import SpriteKit

/// Full-screen phone interface for placing in-app calls to another user.
/// Observes CallSessionManager and forwards state changes to PhoneScene's LCD.
struct PopularPhone: View {
    let user: FakeUser

    @State private var phoneScene: PhoneScene
    @StateObject private var colorWheel = CubeMenuWheelController()
    @ObservedObject private var callManager = CallSessionManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedColorway = PoplurPhoneColorway.all[0]
    @State private var isPhoneButtonActive = true
    @State private var holdWorkItem: DispatchWorkItem?
    @State private var isHoldingColorWheel = false

    init(user: FakeUser) {
        self.user = user
        _phoneScene = State(initialValue: PhoneScene(callingUser: user))
    }

    var body: some View {
        ZStack {
            SpriteView(scene: phoneScene, options: [.allowsTransparency])
                .background(Color.black)
                .ignoresSafeArea()

            phoneColorButtonHitArea
                .zIndex(10)

            CubeMenuWheelOverlay(controller: colorWheel)
                .zIndex(12)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .onAppear {
            NotificationCenter.default.post(name: .popularPhoneDidPresent, object: nil)
            NotificationCenter.default.post(name: Notification.Name("CubeInteractionDisabled"), object: nil)
            phoneScene.applyColorway(selectedColorway.bootupSpritesheetName)
            phoneScene.setPhoneButtonActive(isPhoneButtonActive, announce: false)
            phoneScene.onDismiss = { dismiss() }
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
            cancelColorHold()
            colorWheel.endHold(activateSelected: false)
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

    private var phoneColorButtonHitArea: some View {
        GeometryReader { proxy in
            let frame = fittedPhoneFrame(in: proxy.size)
            let button = CGRect(
                x: frame.minX + frame.width * 0.335,
                y: frame.minY + frame.height * 0.485,
                width: frame.width * 0.330,
                height: frame.height * 0.080
            )

            Color.clear
                .frame(width: button.width, height: button.height)
                .position(x: button.midX, y: button.midY)
                .contentShape(Ellipse())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            scheduleColorHold()
                        }
                        .onEnded { _ in
                            finishColorButtonGesture()
                        }
                )
        }
    }

    private func fittedPhoneFrame(in container: CGSize) -> CGRect {
        let aspect = 1024.0 / 1536.0
        let availableWidth = max(1, container.width)
        let availableHeight = max(1, container.height)
        let phoneWidth = min(availableWidth, availableHeight * aspect)
        let phoneHeight = phoneWidth / aspect

        return CGRect(
            x: (container.width - phoneWidth) / 2,
            y: (container.height - phoneHeight) / 2,
            width: phoneWidth,
            height: phoneHeight
        )
    }

    private func scheduleColorHold() {
        guard holdWorkItem == nil, !isHoldingColorWheel else { return }
        let workItem = DispatchWorkItem {
            isHoldingColorWheel = true
            phoneScene.animatePhoneButtonPress("call")
            colorWheel.beginHold(items: colorWheelItems)
        }
        holdWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func finishColorButtonGesture() {
        if isHoldingColorWheel {
            colorWheel.endHold(activateSelected: true)
            isHoldingColorWheel = false
            holdWorkItem = nil
        } else {
            cancelColorHold()
            togglePhoneButtonActive()
        }
    }

    private func cancelColorHold() {
        holdWorkItem?.cancel()
        holdWorkItem = nil
        isHoldingColorWheel = false
    }

    private func togglePhoneButtonActive() {
        phoneScene.animatePhoneButtonPress("call")
        isPhoneButtonActive.toggle()
        phoneScene.setPhoneButtonActive(isPhoneButtonActive)
    }

    private var colorWheelItems: [CubeSubmenuItem] {
        PoplurPhoneColorway.all.map { colorway in
            CubeSubmenuItem(
                id: colorway.bootupSpritesheetName,
                title: colorway.title,
                systemImage: "circle.fill",
                tint: colorway.swatch
            ) {
                selectedColorway = colorway
                phoneScene.applyColorway(colorway.bootupSpritesheetName)
            }
        }
    }
}

private struct PoplurPhoneColorway: Identifiable, Equatable {
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
