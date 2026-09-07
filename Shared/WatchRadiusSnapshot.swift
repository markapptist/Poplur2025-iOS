import Foundation

/// Metres on the wire; the phone and Watch format the same account-wide reach.
struct WatchRadiusSnapshot {
    let radiusMeters: Double
    let postCount: Int
    let updatedAt: TimeInterval

    init(radiusMeters: Double, postCount: Int, updatedAt: TimeInterval = Date().timeIntervalSince1970) {
        self.radiusMeters = radiusMeters.isFinite ? max(0, radiusMeters) : 0
        self.postCount = max(0, postCount)
        self.updatedAt = updatedAt
    }

    init?(payload: [String: Any]) {
        guard let meters = Self.number(payload["overallRadiusMeters"])
            ?? Self.number(payload["radiusMeters"])
            ?? Self.number(payload["radius"]) else { return nil }
        let count = max(0, Self.number(payload["postCount"]) ?? 0)
        self.init(radiusMeters: meters,
                  postCount: count >= Double(Int.max) ? Int.max : Int(count),
                  updatedAt: Self.number(payload["updatedAt"]) ?? Date().timeIntervalSince1970)
    }

    var payload: [String: Any] {
        ["overallRadiusMeters": radiusMeters, "postCount": postCount, "updatedAt": updatedAt]
    }

    func shouldReplace(lastUpdatedAt: Date?) -> Bool {
        lastUpdatedAt.map { updatedAt >= $0.timeIntervalSince1970 } ?? true
    }

    /// Match the phone's total reach, including each post's discovery seed.
    /// Only individual posts have a planet-size ceiling; account totals do not.
    static func postRadiusMeters(_ data: [String: Any]) -> Double {
        min(6_371_000, max(0, number(data["radiusMeters"]) ?? number(data["radius"]) ?? 0))
    }

    private static func number(_ value: Any?) -> Double? {
        let parsed: Double?
        if let value = value as? NSNumber { parsed = value.doubleValue }
        else if let value = value as? String { parsed = Double(value) }
        else { parsed = nil }
        return parsed.flatMap { $0.isFinite ? $0 : nil }
    }
}
