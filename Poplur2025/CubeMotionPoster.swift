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
    private var wantsUpdates = false
    private var isRunning = false

    /// Tweak sensitivity if needed. This scales the raw attitude values before posting.
    var rollScale: Double = 1.0
    var pitchScale: Double = 1.0

    private init() {
        queue.qualityOfService = .utility
        queue.maxConcurrentOperationCount = 1
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
    }

    func start() {
        wantsUpdates = true
        startHardwareIfNeeded()
    }

    private func startHardwareIfNeeded() {
        guard wantsUpdates,
              UIApplication.shared.applicationState == .active,
              manager.isDeviceMotionAvailable,
              !isRunning else { return }
        isRunning = true

        // Fifteen samples per second preserves responsive tilt control without
        // running the motion fusion and main-thread bridge at display cadence.
        manager.deviceMotionUpdateInterval = 1.0 / 15.0
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

    }

    func stop() {
        wantsUpdates = false
        stopHardware()
    }

    private func stopHardware() {
        guard isRunning else { return }
        manager.stopDeviceMotionUpdates()
        isRunning = false
    }

    @objc private func appDidBecomeActive() {
        startHardwareIfNeeded()
    }

    @objc private func appWillResignActive() {
        // Preserve the user's tilt preference, but release motion hardware for
        // the entire inactive/background interval.
        stopHardware()
    }
}
