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

            // Keep it bounded: a log that fills the container is its own bug.
            if let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
               size > maxBytes,
               let text = try? String(contentsOf: url, encoding: .utf8) {
                let kept = text.split(separator: "\n").suffix(1500).joined(separator: "\n")
                try? (kept + "\n").data(using: .utf8)?.write(to: url)
            }
        }
    }

    /// Marks a fresh run so old lines are never mistaken for the current build.
    static func markLaunch() {
        append("=== LAUNCH === build=\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")")
    }
}
