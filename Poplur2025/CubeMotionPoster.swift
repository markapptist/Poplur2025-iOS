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
    private var streamGeneration: UInt64 = 0
    private var lastSampleUptime: TimeInterval = 0
    private var lastRestartUptime: TimeInterval = 0
    private var healthWorkItem: DispatchWorkItem?
    private(set) var latestSample: (roll: Double, pitch: Double)?

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
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.start(owner: owner) }
            return
        }
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
        streamGeneration &+= 1
        let generation = streamGeneration
        lastSampleUptime = ProcessInfo.processInfo.systemUptime

        // The visible navigator renders at 60fps. Thirty sensor updates left
        // the interpolation a frame behind the hand, which is invisible on a
        // clay cube leaning in its case and very visible on the camcorder,
        // which is aimed — it should point where the handset points, not
        // where it pointed 33ms ago. Matching the display rate removes that
        // lag at the source. Hidden/background owners still stop hardware,
        // which is where this stream's power actually goes.
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        // Choose a reference frame; xArbitraryZVertical is generally stable for UI tilts
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, error in
            guard let self else { return }
            guard let motion else {
                if error != nil {
                    DispatchQueue.main.async { [weak self] in
                        self?.restartIfCurrent(generation: generation, reason: "core-motion-error")
                    }
                }
                return
            }
            let attitude = motion.attitude
            let roll = attitude.roll * self.rollScale
            let pitch = attitude.pitch * self.pitchScale
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.isRunning,
                      self.streamGeneration == generation else { return }
                self.lastSampleUptime = ProcessInfo.processInfo.systemUptime
                self.latestSample = (roll, pitch)
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
        scheduleHealthCheck()
    }

    func stop(owner: String = "legacy") {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.stop(owner: owner) }
            return
        }
        owners.remove(owner)
        if owners.isEmpty { stopHardware() }
    }

    private func stopHardware() {
        healthWorkItem?.cancel()
        healthWorkItem = nil
        streamGeneration &+= 1
        guard isRunning || manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
        isRunning = false
    }

    /// Core Motion can remain nominally active after an interruption while no
    /// longer delivering samples. A foreground-only heartbeat repairs that
    /// silent state; it never runs while Poplur is hidden or backgrounded.
    private func scheduleHealthCheck() {
        healthWorkItem?.cancel()
        guard isRunning,
              !owners.isEmpty,
              UIApplication.shared.applicationState == .active else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if !self.manager.isDeviceMotionActive || now - self.lastSampleUptime > 1.25 {
                self.restartHardware(reason: "sample-timeout")
            } else {
                self.scheduleHealthCheck()
            }
        }
        healthWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func restartIfCurrent(generation: UInt64, reason: String) {
        guard isRunning, streamGeneration == generation else { return }
        restartHardware(reason: reason)
    }

    private func restartHardware(reason: String) {
        guard !owners.isEmpty,
              UIApplication.shared.applicationState == .active else {
            stopHardware()
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastRestartUptime >= 0.5 else {
            scheduleHealthCheck()
            return
        }
        lastRestartUptime = now
        PoplurDiagLog.append("[CubeMotion] restarting reason=\(reason) owners=\(owners.sorted().joined(separator: ","))")
        stopHardware()
        startHardwareIfNeeded()
    }

    @objc private func appDidBecomeActive() {
        // Always reconcile against Core Motion's real state on return. The
        // owners intentionally survive background so the visible navigator can
        // resume without waiting for SwiftUI to rebuild its WebView.
        startHardwareIfNeeded()
    }

    @objc private func appWillResignActive() {
        // Preserve every owner's lease, but release motion hardware for
        // the entire inactive/background interval.
        stopHardware()
    }
}
