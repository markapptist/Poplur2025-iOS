import SwiftUI
import Combine

@MainActor
final class CubeTouchConfiguration: ObservableObject {
    // How much a small drag translates to rotation/selection movement. Higher = more responsive.
    @Published var touchSensitivity: CGFloat
    // How springy the cube reacts to touches/gestures. Higher = more bounce.
    @Published var bounce: CGFloat
    // Damping factor for spring animations. Lower = more oscillation.
    @Published var damping: CGFloat
    // Minimum drag distance to start reacting. Lower = reacts to slight touches.
    @Published var minimumDragDistance: CGFloat
    // Multiplier for swipe up gesture to trigger actions easier.
    @Published var swipeUpSensitivity: CGFloat

    init(
        touchSensitivity: CGFloat = 1.8,
        bounce: CGFloat = 0.9,
        damping: CGFloat = 0.55,
        minimumDragDistance: CGFloat = 2,
        swipeUpSensitivity: CGFloat = 1.4
    ) {
        self.touchSensitivity = touchSensitivity
        self.bounce = bounce
        self.damping = damping
        self.minimumDragDistance = minimumDragDistance
        self.swipeUpSensitivity = swipeUpSensitivity
    }
}
