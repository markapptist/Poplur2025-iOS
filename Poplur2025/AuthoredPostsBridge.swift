import Foundation
import FirebaseAuth
import FirebaseFirestore
import WebKit

/// Complete author reads for Profile totals and the Conquer landmark wall.
/// Owned by the live web coordinator, never by the dormant SwiftUI screens.
final class AuthoredPostsBridge {
    private struct Entry { let generation: UUID; let registration: ListenerRegistration }
    private var subscriptions: [String: Entry] = [:]

    deinit { stopAll() }

    func stopAll() {
        subscriptions.values.forEach { $0.registration.remove() }
        subscriptions.removeAll()
    }

    @discardableResult
    func handle(_ body: [String: Any], into webView: WKWebView) -> Bool {
        guard let type = body["type"] as? String,
              type == "watchAuthoredPosts" || type == "stopAuthoredPosts" else { return false }
        guard let subscriptionId = body["subscriptionId"] as? String,
              !subscriptionId.isEmpty, subscriptionId.count <= 100 else { return true }
        subscriptions.removeValue(forKey: subscriptionId)?.registration.remove()
        if type == "stopAuthoredPosts" { return true }
        guard let uid = body["userId"] as? String, !uid.isEmpty, uid.count <= 128,
              let viewer = Auth.auth().currentUser?.uid, subscriptions.count < 4 else { return true }
        let generation = UUID()
        let registration = Firestore.firestore().collection("posts")
            .whereField("userID", isEqualTo: uid)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self, weak webView] snapshot, error in
                guard let self, let webView,
                      self.subscriptions[subscriptionId]?.generation == generation,
                      Auth.auth().currentUser?.uid == viewer else { return }
                if snapshot?.metadata.isFromCache == true { return }
                var payload: [String: Any] = ["subscriptionId": subscriptionId, "uid": uid]
                if error != nil || snapshot == nil {
                    payload["error"] = "Could not load this profile's posts."
                } else {
                    payload["documents"] = snapshot!.documents.compactMap { document -> [String: Any]? in
                        guard let row = Self.publicRow(document.data()) else { return nil }
                        return ["id": document.documentID, "row": row]
                    }
                }
                guard let data = try? JSONSerialization.data(withJSONObject: payload),
                      let json = String(data: data, encoding: .utf8) else { return }
                webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent('poplur-authored-posts',{detail:\(json)}));true;", completionHandler: nil)
            }
        subscriptions[subscriptionId] = Entry(generation: generation, registration: registration)
        return true
    }

    /// Match the shared post boundary: no private coordinates or arbitrary
    /// document fields cross into the page, even for legacy documents.
    private static func publicRow(_ data: [String: Any]) -> [String: Any]? {
        func enabled(_ value: Any?) -> Bool {
            if let number = value as? NSNumber { return number.boolValue }
            return (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
        }
        let audience = (data["audience"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let status = ((data["visibilityStatus"] ?? data["status"]) as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (audience.isEmpty || audience == "public"),
              (status.isEmpty || status == "published" || status == "live"),
              !enabled(data["deleted"]), !enabled(data["isDeleted"]) else { return nil }
        let fields = ["userID", "userId", "ownerId", "audience", "visibilityStatus", "status", "deleted", "isDeleted",
            "radiusMeters", "radius", "organicRadiusMeters", "seedRadiusMeters", "boostedRadiusMeters",
            "radiusDecayAnchorMillis", "radiusDecayOrganicPerDay", "radiusDecaySeedPerDay", "radiusDecayBoostPerDay", "playbackURL", "mediaURL",
            "mediaType", "posterURL", "photoViewSeconds", "contentType", "messageCard", "username", "handle", "displayName", "caption", "channelId",
            "profilePictureURL", "avatarURL", "avatarUrl", "photoURL", "viewCount", "likeCount", "upvoteCount",
            "downvoteCount", "dislikeCount", "commentCount", "shareCount", "syntheticJourney", "syntheticBeta", "syntheticCohort"]
        var row: [String: Any] = [:]
        for key in fields {
            if let value = data[key] as? String { row[key] = value }
            else if let value = data[key] as? NSNumber, value.doubleValue.isFinite { row[key] = value }
        }
        if let time = data["createdAt"] as? Timestamp { row["createdAtMillis"] = time.dateValue().timeIntervalSince1970 * 1000 }
        else if let time = data["createdAtMillis"] as? NSNumber, time.doubleValue.isFinite { row["createdAtMillis"] = time }
        let publicOrigin = data["locationVisibility"] as? String == "approximate"
            && !enabled(data["privateAccount"]) && !enabled(data["ghostMode"])
        row["locationVisibility"] = publicOrigin ? "approximate" : "hidden"
        if publicOrigin {
            for key in ["latitude", "longitude", "originLatitude", "originLongitude"] {
                if let value = data[key] as? NSNumber, value.doubleValue.isFinite { row[key] = value }
            }
        }
        return row
    }
}
