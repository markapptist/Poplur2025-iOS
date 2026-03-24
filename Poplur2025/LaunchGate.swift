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
    struct TaskInfo {
        let id: UUID
        let name: String
        let phase: Int
        let submittedAt: CFAbsoluteTime
        var startedAt: CFAbsoluteTime?
        var finishedAt: CFAbsoluteTime?
    }

    enum SubmissionPolicy {
        case immediate
        case deferIfOverCap
    }

    struct AdaptivePolicy {
        var enabled: Bool = true
        var hardEnforcement: Bool = false
        var minPhaseToDefer: Int = 2
        var minDurationToDefer: Double = 1.0 // seconds
        var historyLimit: Int = 20
        // Quiet-period heuristic configuration
        var enableQuietHeuristic: Bool = true
        var quietWindowSeconds: Double = 1.5
    }

    private enum StorageKeys {
        static let historyTotals = "LaunchGate.historyTotals"
        static let historySamples = "LaunchGate.historySamples" // per-task durations by name
    }

    /// The optional start time of the launch period.
    private var launchStart: CFAbsoluteTime?
    /// The maximum allowed duration for the launch period.
    private let capSeconds: Double
    /// Serial queue to synchronize access to `launchStart`.
    private let queue = DispatchQueue(label: "LaunchGate.queue")

    /// Tracked tasks submitted to the gate.
    private var tasks: [UUID: TaskInfo] = [:]
    /// Ordered task ids by submission time
    private var taskOrder: [UUID] = []
    /// Whether countdown logging is active
    private var isCountingDown = false
    /// Handle to the countdown task so we can cancel it when launch completes
    private var countdownTask: Task<Void, Never>? = nil

    /// Tracks last notable activity time (submission/start/finish)
    private var lastActivityTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    /// A passive watcher that stops countdown after a quiet period
    private var quietWatcherTask: Task<Void, Never>? = nil

    /// Adaptive policy configuration
    private var adaptive = AdaptivePolicy()
    /// Cached history of total launch times (seconds)
    private var historyTotals: [Double] = []
    /// Cached history of task durations by name (seconds)
    private var historySamples: [String: [Double]] = [:]

    /// Initialize a new LaunchGate with an optional cap in seconds.
    ///
    /// - Parameter capSeconds: The launch cap duration in seconds. Defaults to 10.0.
    init(capSeconds: Double = 10.0) {
        self.capSeconds = capSeconds
        // Load persisted history
        if let totals = UserDefaults.standard.array(forKey: StorageKeys.historyTotals) as? [Double] {
            self.historyTotals = totals
        }
        if let data = UserDefaults.standard.dictionary(forKey: StorageKeys.historySamples) as? [String: [Double]] {
            self.historySamples = data
        }
    }

    /// Starts a console countdown from 0 up to the cap in seconds.
    private func startCountdownIfNeeded() {
        var shouldStart = false
        queue.sync {
            if !isCountingDown {
                isCountingDown = true
                shouldStart = true
            }
        }
        guard shouldStart else { return }
        countdownTask = Task.detached {
            let startTime = CFAbsoluteTimeGetCurrent()
            var lastPrinted = -1
            while !Task.isCancelled {
                let elapsed = Int(CFAbsoluteTimeGetCurrent() - startTime)
                if elapsed != lastPrinted {
                    lastPrinted = elapsed
                    let overCap = Double(elapsed) - self.capSeconds
                    if overCap >= 0 {
                        print("[LaunchGate] elapsed: \(elapsed)s (\(Int(self.sanitizeSeconds(overCap)))s over cap \(Int(self.capSeconds))s)")
                    } else {
                        print("[LaunchGate] elapsed: \(elapsed)s / \(Int(self.capSeconds))s")
                    }
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        startQuietWatcherIfNeeded()
    }

    /// Starts a passive quiet-period watcher that stops the countdown when the app is quiet.
    private func startQuietWatcherIfNeeded() {
        var shouldStart = false
        queue.sync {
            if adaptive.enableQuietHeuristic && quietWatcherTask == nil {
                shouldStart = true
            }
        }
        guard shouldStart else { return }
        quietWatcherTask = Task.detached { [weak self] in
            guard let self = self else { return }
            while !Task.isCancelled {
                // Read snapshot under lock
                let snapshot: (isCounting: Bool, hasActive: Bool, start: CFAbsoluteTime?, lastActivity: CFAbsoluteTime, quietWindow: Double, gateOpen: Bool) = self.queue.sync {
                    let hasActive = self.tasks.values.contains { $0.finishedAt == nil }
                    return (self.isCountingDown, hasActive, self.launchStart, self.lastActivityTime, self.adaptive.quietWindowSeconds, self.isOpenLocked())
                }
                if snapshot.isCounting {
                    let now = CFAbsoluteTimeGetCurrent()
                    let quietLongEnough = (now - snapshot.lastActivity) >= snapshot.quietWindow
                    // If gate is open OR we never had tasks, and we've been quiet long enough with no active tasks, stop.
                    if quietLongEnough && !snapshot.hasActive {
                        self.stopCounting()
                        break
                    }
                } else {
                    break
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }

    /// Stop the countdown if we detect that launch work has completed.
    /// Heuristic: if the gate is open OR there are no pending/running tasks, we can stop.
    private func stopCountdownIfComplete() {
        var shouldStop = false
        queue.sync {
            // Determine if any tasks are still pending or running
            let hasActiveTasks = tasks.values.contains { $0.finishedAt == nil }
            // If gate is open and there are no active tasks, or if there are zero tasks at all, stop.
            if isCountingDown {
                if (!hasActiveTasks && !tasks.isEmpty) || (launchStart != nil && isOpen && !hasActiveTasks) {
                    shouldStop = true
                }
            }
        }
        guard shouldStop else { return }
        countdownTask?.cancel()
        countdownTask = nil
        queue.sync { 
            isCountingDown = false 
            quietWatcherTask?.cancel()
            quietWatcherTask = nil
        }
    }

    /// Public: Immediately stop the countdown logging, regardless of task state.
    /// Use this if your app knows it's ready and you want the timer to cease.
    public func stopCounting() {
        var wasCounting = false
        queue.sync {
            wasCounting = isCountingDown
        }
        guard wasCounting else { return }
        countdownTask?.cancel()
        countdownTask = nil
        queue.sync { 
            isCountingDown = false 
            quietWatcherTask?.cancel()
            quietWatcherTask = nil
        }
    }

    /// Public: Mark the app as ready/launch complete.
    /// Records launch outcome for history and stops countdown if running.
    public func markReady() {
        recordLaunchOutcome()
        stopCountdownIfComplete()
        // In case there were no tasks to trigger the heuristic, force stop.
        stopCounting()
    }

    private func persistHistory() {
        UserDefaults.standard.set(historyTotals, forKey: StorageKeys.historyTotals)
        UserDefaults.standard.set(historySamples, forKey: StorageKeys.historySamples)
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Clamp/clean seconds for safe logging (avoid NaN/inf/negative)
    private func sanitizeSeconds(_ value: Double) -> Double {
        if value.isNaN || !value.isFinite { return 0 }
        return max(0, value)
    }

    /// Returns true if recent average launch time exceeds cap by >20%
    private func isTrendingOverCap() -> Bool {
        let recent = Array(historyTotals.suffix(min(adaptive.historyLimit, historyTotals.count)))
        guard !recent.isEmpty else { return false }
        let avg = average(recent)
        return avg > capSeconds * 1.2
    }

    /// Mark the start of the launch timing.
    ///
    /// If the start time is already set, calling this method has no effect.
    func start() {
        var didStart = false
        queue.sync {
            if launchStart == nil {
                launchStart = CFAbsoluteTimeGetCurrent()
                lastActivityTime = CFAbsoluteTimeGetCurrent()
                didStart = true
            }
        }
        if didStart { startCountdownIfNeeded() }
    }

    /// Whether the gate is open, i.e., the cap duration has elapsed since start.
    var isOpen: Bool {
        queue.sync { isOpenLocked() }
    }

    /// Non-locking variant; must be called while already on `queue`
    private func isOpenLocked() -> Bool {
        guard let start = launchStart else { return false }
        return CFAbsoluteTimeGetCurrent() - start >= capSeconds
    }

    /// Schedules the given work to run on the main actor after the remaining time to the cap elapses.
    ///
    /// If `start()` was never called, this method implicitly starts the gate at the time of first call.
    ///
    /// - Parameter work: An async closure to execute after the gate opens.
    func afterGate(_ work: @escaping @Sendable () async -> Void) {
        var delaySeconds: Double = 0
        var didStart = false

        queue.sync {
            if launchStart == nil {
                launchStart = CFAbsoluteTimeGetCurrent()
                lastActivityTime = CFAbsoluteTimeGetCurrent()
                didStart = true
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - (launchStart ?? 0)
            delaySeconds = max(0, capSeconds - elapsed)
        }
        if didStart { startCountdownIfNeeded() }

        Task.detached { @MainActor in
            if delaySeconds > 0 {
                let nanoseconds = UInt64(delaySeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
            await work()
        }
    }

    /// Configure adaptive auto-deferral behavior
    func setAutoDeferral(enabled: Bool, hardEnforcement: Bool = false, minPhase: Int, minDuration: TimeInterval) {
        queue.sync {
            adaptive.enabled = enabled
            adaptive.hardEnforcement = hardEnforcement
            adaptive.minPhaseToDefer = minPhase
            adaptive.minDurationToDefer = minDuration
        }
    }

    /// Submit a named task to be executed during launch.
    /// - Parameters:
    ///   - name: A human-readable identifier for logging.
    ///   - phase: Lower numbers indicate higher priority (0 is highest). Default is 1.
    ///   - policy: If `.deferIfOverCap`, the task will be postponed to after the gate opens when the cap has been exceeded.
    ///   - work: The async work closure to perform.
    func submit(name: String, phase: Int = 1, policy: SubmissionPolicy = .deferIfOverCap, work: @escaping @Sendable () async -> Void) {
        var id = UUID()
        var shouldDefer = false
        var delaySeconds: Double = 0
        var didStart = false

        var effectivePolicy = policy
        let suggestion = suggestedPolicy(for: name, phase: phase)
        if adaptive.enabled {
            if adaptive.hardEnforcement && suggestion == .deferIfOverCap {
                effectivePolicy = .deferIfOverCap
                print("[LaunchGate] ENFORCE deferIfOverCap for '\(name)' (phase \(phase)) based on trends/history")
            } else if suggestion == .deferIfOverCap && policy != .deferIfOverCap {
                print("[LaunchGate] SUGGEST deferIfOverCap for '\(name)' (phase \(phase)); caller requested immediate")
            }
        }

        queue.sync {
            if launchStart == nil {
                launchStart = CFAbsoluteTimeGetCurrent()
                didStart = true
            }
            let now = CFAbsoluteTimeGetCurrent()
            lastActivityTime = now
            let elapsed = now - (launchStart ?? now)
            let remaining = max(0, capSeconds - elapsed)
            if remaining == 0 && effectivePolicy == .deferIfOverCap {
                shouldDefer = true
            } else {
                delaySeconds = remaining
            }
            let info = TaskInfo(id: id, name: name, phase: phase, submittedAt: now, startedAt: nil, finishedAt: nil)
            tasks[id] = info
            taskOrder.append(id)
        }
        if didStart { startCountdownIfNeeded() }

        let runTask: @Sendable () async -> Void = { [weak self] in
            guard let self = self else { return }
            var startedAt: CFAbsoluteTime = 0
            self.queue.sync {
                startedAt = CFAbsoluteTimeGetCurrent()
                if var info = self.tasks[id] {
                    info.startedAt = startedAt
                    self.tasks[id] = info
                }
                let startDelta = self.sanitizeSeconds(startedAt - (self.launchStart ?? startedAt))
                print("[LaunchGate] START \(name) (phase \(phase)) at +\(String(format: "%.2f", startDelta))s")
                self.lastActivityTime = startedAt
            }
            await work()
            self.queue.sync {
                let finishedAt = CFAbsoluteTimeGetCurrent()
                if var info = self.tasks[id] {
                    info.finishedAt = finishedAt
                    self.tasks[id] = info
                }
                if let s = self.tasks[id]?.startedAt {
                    let d = finishedAt - s
                    var arr = self.historySamples[name] ?? []
                    arr.append(d)
                    if arr.count > self.adaptive.historyLimit { arr.removeFirst(arr.count - self.adaptive.historyLimit) }
                    self.historySamples[name] = arr
                }
                let rawDuration = (self.tasks[id]?.finishedAt ?? 0) - (self.tasks[id]?.startedAt ?? 0)
                let duration = self.sanitizeSeconds(rawDuration)
                print("[LaunchGate] END   \(name) duration \(String(format: "%.2f", duration))s")
                self.lastActivityTime = finishedAt
            }
            self.stopCountdownIfComplete()
        }

        if shouldDefer {
            // Run after the gate opens on main actor
            afterGate {
                print("[LaunchGate] DEFERRED \(name) until after gate opened")
                await runTask()
            }
        } else {
            // Schedule to align with remaining cap time on main actor
            Task.detached { @MainActor in
                if delaySeconds > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
                }
                await runTask()
            }
        }
    }

    /// Suggest policy for a task based on adaptive trends and history
    private func suggestedPolicy(for name: String, phase: Int) -> SubmissionPolicy {
        return queue.sync {
            guard adaptive.enabled else { return .immediate }
            // If trending over cap, be stricter
            let trending = isTrendingOverCap()
            let samples = historySamples[name] ?? []
            let avgDur = average(samples)
            // Defer if low priority (higher phase) or long-running
            if trending {
                if phase >= adaptive.minPhaseToDefer { return .deferIfOverCap }
                if avgDur >= adaptive.minDurationToDefer { return .deferIfOverCap }
            } else {
                // Even if not trending, very long tasks at low priority can be deferred
                if phase >= (adaptive.minPhaseToDefer + 1) && avgDur >= (adaptive.minDurationToDefer * 1.5) {
                    return .deferIfOverCap
                }
            }
            return .immediate
        }
    }

    /// Computes recommendations for tasks to defer/remove to keep launch under the cap.
    /// Strategy: sort tasks by phase (low priority later), then by duration descending; accumulate until total overage is addressed.
    private func computeRecommendations() -> [TaskInfo] {
        return queue.sync {
            guard let start = launchStart else { return [] }
            // Consider tasks that started during launch window
            let finishedTasks = taskOrder.compactMap { tasks[$0] }.filter { $0.startedAt != nil }
            // Sort by phase (higher number means lower priority) then by duration desc
            let sorted = finishedTasks.sorted { a, b in
                if a.phase != b.phase { return a.phase > b.phase }
                let ad = (a.finishedAt ?? a.startedAt ?? start) - (a.startedAt ?? start)
                let bd = (b.finishedAt ?? b.startedAt ?? start) - (b.startedAt ?? start)
                return ad > bd
            }
            // Compute total elapsed until last finished task
            let lastFinish = finishedTasks.compactMap { $0.finishedAt }.max() ?? CFAbsoluteTimeGetCurrent()
            let totalElapsed = lastFinish - start
            let overage = max(0, totalElapsed - capSeconds)
            guard overage > 0 else { return [] }
            var picked: [TaskInfo] = []
            var accumulated: Double = 0
            for t in sorted {
                let dur = (t.finishedAt ?? t.startedAt ?? start) - (t.startedAt ?? start)
                picked.append(t)
                accumulated += max(0, dur)
                if accumulated >= overage { break }
            }
            return picked
        }
    }

    /// Prints a recommendations section indicating tasks that, if deferred, could reduce launch time under cap.
    func recommendRemovals() {
        let recs = computeRecommendations()
        if recs.isEmpty {
            print("[LaunchGate] No recommendations; launch within cap or insufficient data.")
            return
        }
        print("[LaunchGate] --- Recommendations to reduce launch time ---")
        for r in recs {
            let name = r.name
            let phase = r.phase
            let dur = (r.finishedAt ?? r.startedAt ?? (launchStart ?? CFAbsoluteTimeGetCurrent())) - (r.startedAt ?? (launchStart ?? CFAbsoluteTimeGetCurrent()))
            let durStr = String(format: "%.2f", sanitizeSeconds(dur))
            print("[LaunchGate] • Defer/remove '\(name)' (phase \(phase)), saves ~\(durStr)s")
        }
        print("[LaunchGate] ------------------------------------------------")
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

    /// Call at the end of launch to record totals and persist history.
    /// If you call `report()`, it will also call `recommendRemovals()`; you can call this independently as well.
    func recordLaunchOutcome() {
        queue.sync {
            guard let start = launchStart else { return }
            let end = tasks.values.compactMap { $0.finishedAt }.max() ?? CFAbsoluteTimeGetCurrent()
            let total = max(0, end - start)
            historyTotals.append(total)
            if historyTotals.count > adaptive.historyLimit { historyTotals.removeFirst(historyTotals.count - adaptive.historyLimit) }
            persistHistory()
        }
        stopCountdownIfComplete()
    }

    /// Returns a natural-language summary of recent launch performance and suggestions.
    func summary() -> String {
        return queue.sync {
            var lines: [String] = []
            lines.append("Launch performance summary:")
            let recent = Array(historyTotals.suffix(min(adaptive.historyLimit, historyTotals.count)))
            if recent.isEmpty {
                lines.append("- No historical data yet.")
            } else {
                let avg = average(recent)
                let last = recent.last ?? 0
                let lastStr = String(format: "%.2f", sanitizeSeconds(last))
                let capStr = String(format: "%.2f", capSeconds)
                lines.append("- Last launch: \(lastStr)s (cap \(capStr)s)")
                let avgStr = String(format: "%.2f", sanitizeSeconds(avg))
                lines.append("- Avg of \(recent.count) runs: \(avgStr)s")
                if avg > capSeconds {
                    let overStr = String(format: "%.2f", sanitizeSeconds(avg - capSeconds))
                    lines.append("- Over cap by avg \(overStr)s; considering deferral of low-priority or long tasks.")
                } else {
                    lines.append("- Within cap on average.")
                }
            }
            // Top offenders by average duration
            let offenders = historySamples.map { (name: $0.key, avg: average($0.value)) }.sorted { $0.avg > $1.avg }.prefix(3)
            if !offenders.isEmpty {
                lines.append("Top time-consuming tasks:")
                for o in offenders {
                    let oAvgStr = String(format: "%.2f", sanitizeSeconds(o.avg))
                    lines.append("- \(o.name) ~\(oAvgStr)s avg")
                }
            }
            return lines.joined(separator: "\n")
        }
    }

    /// Prints a summary of tasks and their timings, ordered by submission.
    func report() {
        queue.sync {
            print("[LaunchGate] --- Report ---")
            guard let start = launchStart else {
                print("[LaunchGate] No launch started.")
                return
            }
            for id in taskOrder {
                guard let info = tasks[id] else { continue }
                let submittedDelta = info.submittedAt - start
                let startedDelta = (info.startedAt ?? info.submittedAt) - start
                let duration = (info.finishedAt ?? info.startedAt ?? info.submittedAt) - (info.startedAt ?? info.submittedAt)
                let status: String
                if info.finishedAt != nil {
                    status = "finished"
                } else if info.startedAt != nil {
                    status = "running"
                } else {
                    status = "pending"
                }
                let namePadded = info.name.padding(toLength: max(8, info.name.count), withPad: " ", startingAt: 0)
                let subStr = String(format: "%.2f", sanitizeSeconds(submittedDelta))
                let startStr = String(format: "%.2f", sanitizeSeconds(startedDelta))
                let durStr = String(format: "%.2f", sanitizeSeconds(duration))
                print("[LaunchGate] \(namePadded) phase:\(info.phase) status:\(status) submitted:+\(subStr)s started:+\(startStr)s duration:\(durStr)s")
            }
            let lastFinish = tasks.values.compactMap { $0.finishedAt }.max()
            if let start = launchStart, let end = lastFinish {
                let total = end - start
                let totalStr = String(format: "%.2f", sanitizeSeconds(total))
                let overStr = String(format: "%.2f", sanitizeSeconds(total - capSeconds))
                let capStr = String(format: "%.2f", sanitizeSeconds(capSeconds))
                if total > capSeconds {
                    print("[LaunchGate] Total launch time: \(totalStr)s (over cap by \(overStr)s)")
                } else {
                    print("[LaunchGate] Total launch time: \(totalStr)s (within cap \(capStr)s)")
                }
            }
            print("[LaunchGate] --------------")
        }
        // Also print recommendations based on current data
        recommendRemovals()
        recordLaunchOutcome()
        print(summary())
        stopCountdownIfComplete()
    }

    /// A shared convenience instance of `LaunchGate` with the default cap of 10 seconds.
    static let shared = LaunchGate()
}
