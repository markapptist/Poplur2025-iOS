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
        print("PASS: Watch radius canonical fields, legacy values, account totals, payload validation and stale updates")
    }
}
