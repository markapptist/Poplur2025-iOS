import UIKit

@MainActor
enum FaceTimeLauncher {
    static func startVideoCall(to user: FakeUser) {
        startVideoCall(displayName: user.name, handle: nil)
    }

    static func startVideoCall(to user: DMUser) {
        startVideoCall(displayName: user.displayName, handle: user.handle)
    }

    static func startVideoCall(displayName: String, handle: String?) {
        let address = faceTimeAddress(displayName: displayName, handle: handle)
        guard let url = URL(string: "facetime://\(address)") else { return }
        UIApplication.shared.open(url)
    }

    private static func faceTimeAddress(displayName: String, handle: String?) -> String {
        if let handle, !handle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return sanitized(handle) + "@poplur.local"
        }
        return sanitized(displayName) + "@poplur.local"
    }

    private static func sanitized(_ value: String) -> String {
        let lowercased = value.lowercased()
        let mapped = lowercased.map { char -> Character in
            char.isLetter || char.isNumber ? char : "."
        }
        let collapsed = String(mapped)
            .split(separator: ".")
            .joined(separator: ".")
        return collapsed.isEmpty ? "poplur" : collapsed
    }
}
