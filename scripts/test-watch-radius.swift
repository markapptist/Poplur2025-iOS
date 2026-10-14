import Foundation

@main
struct WatchRadiusTests {
    static func main() {
        precondition(WatchRadiusSnapshot.postRadiusMeters(["radiusMeters": 6500]) == 6500)
        precondition(WatchRadiusSnapshot.postRadiusMeters(["radiusMeters": 6500, "radius": 0]) == 6500)
        precondition(WatchRadiusSnapshot.postRadiusMeters(["radius": "1250.5"]) == 1250.5)
        precondition(WatchRadiusSnapshot.postRadiusMeters(["radiusMeters": Double.nan]) == 0)
        precondition(WatchRadiusSnapshot.postRadiusMeters(["radiusMeters": -2]) == 0)
        let largeTotal = [["radiusMeters": 7_000_000], ["radiusMeters": 6_371_000]]
            .reduce(0.0) { $0 + WatchRadiusSnapshot.postRadiusMeters($1) }
        precondition(largeTotal == 12_742_000)
        precondition(WatchRadiusSnapshot(payload: [:]) == nil)
        precondition(WatchRadiusSnapshot(payload: ["pending": true]) == nil)
        precondition(WatchRadiusSnapshot(payload: ["overallRadiusMeters": Double.infinity]) == nil)
        let zero = WatchRadiusSnapshot(payload: ["overallRadiusMeters": 0, "updatedAt": 20])!
        precondition(zero.radiusMeters == 0)
        precondition(zero.shouldReplace(lastUpdatedAt: Date(timeIntervalSince1970: 10)))
        precondition(!zero.shouldReplace(lastUpdatedAt: Date(timeIntervalSince1970: 30)))
        let total = WatchRadiusSnapshot(radiusMeters: largeTotal, postCount: 2, updatedAt: 40)
        let received = WatchRadiusSnapshot(payload: total.payload)!
        precondition(received.radiusMeters == largeTotal && received.postCount == 2)
        precondition(received.shouldReplace(lastUpdatedAt: nil))

        // Reproduce the old inflated count: only the two live public posts
        // contribute. A Pop Message counts even without an image/video URL.
        let documents: [[String: Any]] = [
            ["radiusMeters": 12_000, "seedRadiusMeters": 8_000, "organicRadiusMeters": 4_000,
             "audience": "public", "visibilityStatus": "published"],
            ["radius": "6500", "contentType": "message", "visibilityStatus": " LIVE "],
            ["radiusMeters": 0],
            ["radiusMeters": 9000, "visibilityStatus": "expired"],
            ["radiusMeters": 9000, "status": "draft"],
            ["radiusMeters": 9000, "audience": "private"],
            ["radiusMeters": 9000, "deleted": true],
            ["radiusMeters": 9000, "isDeleted": "TRUE"],
            ["radiusMeters": Double.nan],
            ["radiusMeters": -1],
        ]
        let live = documents.reduce(into: WatchAccountRadiusTotals()) { $0.include($1) }
        precondition(live.postCount == 2, "Expired and unpublished documents must not inflate the Watch count")
        precondition(live.reach == 18_500 && live.earned == 10_500 && live.committed == 3_000)
        let roundTrip = WatchRadiusSnapshot(payload: WatchRadiusSnapshot(
            radiusMeters: live.reach, postCount: live.postCount).payload)!
        precondition(roundTrip.postCount == 2 && roundTrip.radiusMeters == 18_500)
        let empty = WatchAccountRadiusTotals()
        precondition(empty.postCount == 0 && empty.reach == 0)
        var expired = WatchAccountRadiusTotals()
        expired.include(["radiusMeters": 7000, "status": "expired"])
        precondition(expired.postCount == 0 && expired.reach == 0)
        var legacy = WatchAccountRadiusTotals()
        legacy.include(["organicRadiusMeters": 900])
        precondition(legacy.postCount == 1 && legacy.reach == 900)

        // Page boundaries must not limit the count or drop earlier live posts.
        var paged = WatchAccountRadiusTotals()
        for _ in 0..<205 { paged.include(["radiusMeters": 100]) }
        for _ in 0..<100 { paged.include(["radiusMeters": 0, "visibilityStatus": "expired"]) }
        precondition(paged.postCount == 205 && paged.reach == 20_500)
        print("PASS: Watch live post counts, expired/private/deleted filtering, message/legacy posts, pagination, radius totals and snapshot ordering")
    }
}
