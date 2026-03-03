import Foundation
import CoreMotion
import UIKit

/// CubeMotionPoster
/// A small helper that reads device motion and posts Notification.Name("CubeMotionUpdate")
/// with userInfo keys: "roll" (Double, radians) and "pitch" (Double, radians).
///
/// Start this when the app (or the screen showing the cube) becomes active, and stop it
/// when it resigns active to save power.
final class CubeMotionPoster {
    static let shared = CubeMotionPoster()

    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private var isRunning = false

    /// Tweak sensitivity if needed. This scales the raw attitude values before posting.
    var rollScale: Double = 1.0
    var pitchScale: Double = 1.0

    private init() {
        queue.qualityOfService = .userInteractive
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        // Prefer deviceMotion for fused attitude; adjust interval as needed
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        // Choose a reference frame; xArbitraryZVertical is generally stable for UI tilts
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { motion, error in
            guard let motion = motion else { return }
            let attitude = motion.attitude
            let roll = attitude.roll * self.rollScale
            let pitch = attitude.pitch * self.pitchScale
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: Notification.Name("CubeMotionUpdate"),
                    object: nil,
                    userInfo: [
                        "roll": roll,
                        "pitch": pitch
                    ]
                )
            }
        }

        // Observe app lifecycle to stop when backgrounded
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
    }

    func stop() {
        guard isRunning else { return }
        manager.stopDeviceMotionUpdates()
        isRunning = false
        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
    }

    @objc private func appDidBecomeActive() {
        // Ensure updates continue after returning to foreground
        if isRunning, !manager.isDeviceMotionActive {
            start()
        }
    }

    @objc private func appWillResignActive() {
        // Pause updates to save power; they'll resume on becomeActive
        if isRunning {
            manager.stopDeviceMotionUpdates()
        }
    }
}
