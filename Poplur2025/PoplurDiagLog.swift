import Darwin
import Foundation

/// A diagnostics log that does not need a live console attached.
///
/// `devicectl device process launch --console` only works if the phone is
/// UNLOCKED at the moment of attach — it refuses with
/// "the device was not, or could not be, unlocked" otherwise. That made the
/// audio/volume diagnostics unreadable in practice: forty retries over twenty
/// minutes captured nothing, because coordinating an unlock with a remote attach
/// is a race nobody should have to run.
///
/// So the same lines are also appended to a file in the app's Documents
/// container, which can be pulled at any time, long after the fact, with:
///
///   xcrun devicectl device copy from --device <id> \
///     --domain-type appDataContainer --domain-identifier com.apptist.Poplur2025 \
///     --source Documents/poplur-diag.log --destination /tmp/poplur-diag.log
///
/// The user just uses the app normally; nothing has to be timed.
enum PoplurDiagLog {
    private static let queue = DispatchQueue(label: "com.apptist.poplur.diaglog", qos: .utility)
    /// Allocating a formatter per line is wasteful in a loop that runs forever.
    private static let stamp: ISO8601DateFormatter = ISO8601DateFormatter()
    private static let maxBytes = 512 * 1024
    private static let trimTargetBytes = maxBytes / 2

    private static var url: URL? {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("poplur-diag.log")
    }

    /// Fire-and-forget. Never throws into the caller and never blocks the main
    /// thread — a diagnostic that degrades the thing it measures is worthless.
    static func append(_ line: String) {
        queue.async {
            guard let url else { return }
            let stamped = "\(stamp.string(from: Date())) \(line)\n"
            guard let data = stamped.data(using: .utf8) else { return }

            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }

            trimIfNeeded(url)
        }
    }

    /// Keep the log bounded without repeatedly allocating and splitting the
    /// entire file. The previous line-count trim could retain more than the
    /// 512 KB cap, so every later profile report re-read and rewrote the whole
    /// log. Retaining a fixed-size byte tail makes trimming infrequent and
    /// gives the allocator room to settle between diagnostic samples.
    private static func trimIfNeeded(_ url: URL) {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = (attributes[.size] as? NSNumber)?.intValue,
            size > maxBytes,
            let handle = try? FileHandle(forReadingFrom: url)
        else { return }

        defer { try? handle.close() }

        let bytesToKeep = min(trimTargetBytes, size)
        do {
            try handle.seek(toOffset: UInt64(size - bytesToKeep))
            guard var tail = try handle.readToEnd(), !tail.isEmpty else { return }

            // The byte window can begin in the middle of a UTF-8 log line.
            // Discard that fragment so the retained diagnostic file stays
            // valid text without decoding or splitting its full contents.
            if let firstNewline = tail.firstIndex(of: 0x0A) {
                tail.removeSubrange(tail.startIndex...firstNewline)
            }

            var bounded = Data("=== TRIMMED ===\n".utf8)
            bounded.append(tail)
            try bounded.write(to: url, options: .atomic)
        } catch {
            // Diagnostics must never affect app behavior.
        }
    }

    /// Marks a fresh run so old lines are never mistaken for the current build.
    static func markLaunch() {
        append("=== LAUNCH === build=\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")")
    }

    /// Resident memory for the whole process, not merely Poplur's bounded asset
    /// cache. This is intentionally sampled only at lifecycle boundaries (and
    /// at a very low background cadence) so the diagnostic cannot become the
    /// work it is trying to identify.
    static func residentMemoryBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
    }

    static func megabytes(_ bytes: UInt64?) -> String {
        guard let bytes else { return "unknown" }
        return String(format: "%.1f", Double(bytes) / 1_048_576.0)
    }
}
