import Foundation

/// A reusable class to manage launch timing with a hard cap.
///
/// `LaunchGate` allows scheduling work to run after a specified launch cap time has elapsed.
/// It manages a start time marking the beginning of the launch period and ensures work is
/// executed on the main actor after the cap duration.
///
/// - Note: This class is designed to be used from main actor contexts ergonomically,
///   but it is not itself marked `@MainActor`.
final class LaunchGate {
    /// The optional start time of the launch period.
    private var launchStart: CFAbsoluteTime?
    /// The maximum allowed duration for the launch period.
    private let capSeconds: Double
    /// Serial queue to synchronize access to `launchStart`.
    private let queue = DispatchQueue(label: "LaunchGate.queue")

    /// Initialize a new LaunchGate with an optional cap in seconds.
    ///
    /// - Parameter capSeconds: The launch cap duration in seconds. Defaults to 10.0.
    init(capSeconds: Double = 10.0) {
        self.capSeconds = capSeconds
    }

    /// Mark the start of the launch timing.
    ///
    /// If the start time is already set, calling this method has no effect.
    func start() {
        queue.sync {
            if launchStart == nil {
                launchStart = CFAbsoluteTimeGetCurrent()
            }
        }
    }

    /// Whether the gate is open, i.e., the cap duration has elapsed since start.
    var isOpen: Bool {
        queue.sync {
            guard let start = launchStart else { return false }
            return CFAbsoluteTimeGetCurrent() - start >= capSeconds
        }
    }

    /// Schedules the given work to run on the main actor after the remaining time to the cap elapses.
    ///
    /// If `start()` was never called, this method implicitly starts the gate at the time of first call.
    ///
    /// - Parameter work: An async closure to execute after the gate opens.
    func afterGate(_ work: @escaping @Sendable () async -> Void) {
        var delaySeconds: Double = 0

        queue.sync {
            if launchStart == nil {
                launchStart = CFAbsoluteTimeGetCurrent()
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - (launchStart ?? 0)
            delaySeconds = max(0, capSeconds - elapsed)
        }

        Task.detached { @MainActor in
            if delaySeconds > 0 {
                let nanoseconds = UInt64(delaySeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            await work()
        }
    }

    /// Returns the remaining time in seconds until the gate opens.
    ///
    /// Returns zero if the gate is open or has not been started yet.
    ///
    /// - Returns: The remaining time in seconds.
    func remainingTime() -> Double {
        queue.sync {
            guard let start = launchStart else { return capSeconds }
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            return max(0, capSeconds - elapsed)
        }
    }

    /// A shared convenience instance of `LaunchGate` with the default cap of 10 seconds.
    static let shared = LaunchGate()
}
