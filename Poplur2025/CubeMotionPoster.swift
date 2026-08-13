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
    private var owners: Set<String> = []
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

    func start(owner: String = "legacy") {
        owners.insert(owner)
        startHardwareIfNeeded()
    }

    private func startHardwareIfNeeded() {
        // `isRunning` is our bookkeeping; `isDeviceMotionActive` is Core
        // Motion's truth. Recover if iOS invalidated the stream while the
        // visible Home owner remained alive.
        if isRunning && !manager.isDeviceMotionActive { isRunning = false }
        guard !owners.isEmpty,
              UIApplication.shared.applicationState == .active,
              manager.isDeviceMotionAvailable,
              !isRunning else { return }
        isRunning = true

        // Thirty sensor samples, interpolated by the navigator's 60fps canvas,
        // read as continuous motion without paying for 60 native→JS bridge
        // evaluations per second. Hardware still stops when the app is inactive.
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
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

    func stop(owner: String = "legacy") {
        owners.remove(owner)
        if owners.isEmpty { stopHardware() }
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
        // Preserve every owner's lease, but release motion hardware for
        // the entire inactive/background interval.
        stopHardware()
    }
}
