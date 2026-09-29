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
        min(6_371_000, max(0, number(data["radiusMeters"]) ?? number(data["radius"])
            ?? number(data["organicRadiusMeters"]) ?? 0))
    }

    fileprivate static func number(_ value: Any?) -> Double? {
        let parsed: Double?
        if let value = value as? NSNumber { parsed = value.doubleValue }
        else if let value = value as? String { parsed = Double(value) }
        else { parsed = nil }
        return parsed.flatMap { $0.isFinite ? $0 : nil }
    }
}

/// The phone's live account relay and its paginated Watch refresh must count
/// the same posts as Profile (authoredPosts.ts), including text-only Pops.
/// Counting raw documents included expired, removed and unpublished posts.
struct WatchAccountRadiusTotals {
    private(set) var reach = 0.0
    private(set) var earned = 0.0
    private(set) var committed = 0.0
    private(set) var postCount = 0

    mutating func include(_ data: [String: Any]) {
        func text(_ value: Any?) -> String {
            (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        func enabled(_ value: Any?) -> Bool {
            if let number = value as? NSNumber { return number.boolValue }
            return text(value) == "true"
        }
        let audience = text(data["audience"])
        let status = text(data["visibilityStatus"] ?? data["status"])
        let postReach = WatchRadiusSnapshot.postRadiusMeters(data)
        guard audience.isEmpty || audience == "public",
              status.isEmpty || status == "published" || status == "live",
              !enabled(data["deleted"]), !enabled(data["isDeleted"]),
              postReach > 0 else { return }

        let seed = max(0, WatchRadiusSnapshot.number(data["seedRadiusMeters"]) ?? 0)
        let organic = max(0, WatchRadiusSnapshot.number(data["organicRadiusMeters"]) ?? (postReach - seed))
        reach += postReach
        earned += min(6_371_000, organic)
        committed += max(0, min(seed, postReach) - 5_000)
        postCount += 1
    }
}
