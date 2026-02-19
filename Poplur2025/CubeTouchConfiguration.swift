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

    // If true, cube tracks touches anywhere on the screen (not just on the cube view)
    @Published var globalTouchTrackingEnabled: Bool
    // Extra radius in points around the cube to consider as interactive area
    @Published var extendedTouchRadius: CGFloat
    // Prefer high priority gesture handling so other views (e.g., ScrollView) are less likely to steal touches
    @Published var prefersHighPriorityGestures: Bool
    // When interacting with the cube, temporarily disable parent ScrollView scrolling
    @Published var disablesParentScrollingWhileInteracting: Bool

    // If false, do not clamp rotation to a limited range; allow full look-around
    @Published var rotationClampEnabled: Bool
    // Optional maximum degrees per gesture update to keep motion controllable (set high for freer motion)
    @Published var maxDegreesPerUpdate: CGFloat
    // Instantly orient cube toward the current touch location as soon as contact begins
    @Published var lookAtOnTouchEnabled: Bool
    // How quickly to interpolate when looking at a touch (0 = instant, higher = smoother)
    @Published var lookAtSmoothing: CGFloat
    // After a swipe, snap to the nearest valid face orientation
    @Published var snapToFaceOnSwipe: Bool
    // Minimum swipe magnitude (points) to trigger a face snap
    @Published var faceSnapSwipeThreshold: CGFloat
    // Spring stiffness for snapping to a face (higher = snappier)
    @Published var faceSnapStiffness: CGFloat
    // Damping for the face snap spring (lower = more bounce)
    @Published var faceSnapDamping: CGFloat

    init(
        touchSensitivity: CGFloat = 2.6,
        bounce: CGFloat = 1.05,
        damping: CGFloat = 0.48,
        minimumDragDistance: CGFloat = 0.8,
        swipeUpSensitivity: CGFloat = 1.9,
        globalTouchTrackingEnabled: Bool = true,
        extendedTouchRadius: CGFloat = 56,
        prefersHighPriorityGestures: Bool = true,
        disablesParentScrollingWhileInteracting: Bool = true,
        rotationClampEnabled: Bool = false,
        maxDegreesPerUpdate: CGFloat = 18,
        lookAtOnTouchEnabled: Bool = true,
        lookAtSmoothing: CGFloat = 0.0,
        snapToFaceOnSwipe: Bool = true,
        faceSnapSwipeThreshold: CGFloat = 24,
        faceSnapStiffness: CGFloat = 900,
        faceSnapDamping: CGFloat = 0.58
    ) {
        self.touchSensitivity = touchSensitivity
        self.bounce = bounce
        self.damping = damping
        self.minimumDragDistance = minimumDragDistance
        self.swipeUpSensitivity = swipeUpSensitivity
        self.globalTouchTrackingEnabled = globalTouchTrackingEnabled
        self.extendedTouchRadius = extendedTouchRadius
        self.prefersHighPriorityGestures = prefersHighPriorityGestures
        self.disablesParentScrollingWhileInteracting = disablesParentScrollingWhileInteracting
        self.rotationClampEnabled = rotationClampEnabled
        self.maxDegreesPerUpdate = maxDegreesPerUpdate
        self.lookAtOnTouchEnabled = lookAtOnTouchEnabled
        self.lookAtSmoothing = lookAtSmoothing
        self.snapToFaceOnSwipe = snapToFaceOnSwipe
        self.faceSnapSwipeThreshold = faceSnapSwipeThreshold
        self.faceSnapStiffness = faceSnapStiffness
        self.faceSnapDamping = faceSnapDamping
    }
}

