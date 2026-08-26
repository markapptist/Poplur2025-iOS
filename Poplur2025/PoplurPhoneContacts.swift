import Foundation
import FirebaseAuth
import FirebaseFirestore

/// The Poplur phone's address book.
///
/// The phone had a hardcoded Contacts menu — "Poplur Phone", "Poplur Support",
/// and "Add contact — coming soon". This assembles the real one from the three
/// sources the phone is meant to draw on:
///
///   1. FAVOURITES — people you chose to keep, so you can call them later.
///   2. DMs — anyone you already have a conversation with.
///   3. INTERCEPTS — people you and your radius have actually crossed.
///   4. REACH — people your radius reaches RIGHT NOW.
///
/// "Intercept" is read from `engagements`, because that is the only DURABLE
/// record that a crossing happened. Both directions count: people who engaged
/// your posts, and people whose posts you engaged.
///
/// Reach is the live half, and it was deliberately left out at first — the
/// argument being that "who is in range right now" is a different question,
/// gone the moment either of you moves. That was wrong about the product: with
/// history alone, two people who have never interacted can never find each
/// other, so a brand new account has an empty phone and no way to fill it. In
/// an app whose whole premise is that radius is what connects people, the one
/// thing the address book must answer is "who can I call from here". So reach
/// is a source now — marked as live, and never confused with the durable
/// tiers, which still sort above it.
@MainActor
final class PoplurPhoneContacts {
    static let shared = PoplurPhoneContacts()

    private let db = Firestore.firestore()
    private var uid: String? { Auth.auth().currentUser?.uid }

    /// One entry per person, however many ways they qualified.
    private struct Contact {
        var id: String
        var name: String
        var favourite = false
        var hasDM = false
        var intercepted = false
        /// Inside your radius as of this read. Live, not durable.
        var inReach = false
        /// Great-circle km from you, when reach put them here.
        var distanceKm: Double?
        /// Most recent moment this person showed up, for ordering.
        var lastSeen: Date = .distantPast
    }

    /// Everything the phone needs, newest-first within each tier.
    func contacts(radiusKm: Double? = nil, latitude: Double? = nil, longitude: Double? = nil) async -> [[String: Any]] {
        guard let uid else { return [] }
        var byID: [String: Contact] = [:]

        func merge(_ id: String, _ name: String?, _ when: Date?, _ apply: (inout Contact) -> Void) {
            guard !id.isEmpty, id != uid else { return }
            var entry = byID[id] ?? Contact(id: id, name: name ?? String(id.prefix(8)))
            // A real handle always beats the uid-prefix placeholder.
            if let name, !name.isEmpty, entry.name.hasPrefix(String(id.prefix(8))) || entry.name.isEmpty {
                entry.name = name
            }
            if let when, when > entry.lastSeen { entry.lastSeen = when }
            apply(&entry)
            byID[id] = entry
        }

        // 1. Favourites.
        if let favs = try? await db.collection("users").document(uid)
            .collection("phoneFavourites").getDocuments() {
            for doc in favs.documents {
                let data = doc.data()
                merge(doc.documentID, data["name"] as? String,
                      (data["addedAt"] as? Timestamp)?.dateValue()) { $0.favourite = true }
            }
        }

        // 2. Anyone you have a thread with.
        if let threads = try? await db.collection("dmThreads")
            .whereField("participants", arrayContains: uid)
            .order(by: "updatedAt", descending: true)
            .limit(to: 50)
            .getDocuments() {
            for doc in threads.documents {
                let data = doc.data()
                let other = (data["participants"] as? [String] ?? []).first { $0 != uid } ?? ""
                let names = data["participantNames"] as? [String: String]
                merge(other, names?[other],
                      (data["updatedAt"] as? Timestamp)?.dateValue()) { $0.hasDM = true }
            }
        }

        // 3a. People who engaged YOUR posts. These carry a denormalised handle,
        //     so this direction names people without a profile read each.
        if let inbound = try? await db.collectionGroup("engagements")
            .whereField("postOwnerUid", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments() {
            for doc in inbound.documents {
                let data = doc.data()
                merge(data["actorUid"] as? String ?? "", data["actorHandle"] as? String,
                      (data["createdAt"] as? Timestamp)?.dateValue()) { $0.intercepted = true }
            }
        }

        // 3b. People whose posts YOU engaged. No handle on this side — the
        //     denormalised one belongs to the actor, which here is you.
        if let outbound = try? await db.collectionGroup("engagements")
            .whereField("actorUid", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 100)
            .getDocuments() {
            for doc in outbound.documents {
                let data = doc.data()
                merge(data["postOwnerUid"] as? String ?? "", nil,
                      (data["createdAt"] as? Timestamp)?.dateValue()) { $0.intercepted = true }
            }
        }

        // 4. REACH — whoever has left a post on ground you can stand and touch
        // from here. Bounded by a lat/lng BOX first because Firestore cannot
        // do a radius, then filtered to the true circle: a box query alone
        // hands you the corners, which are up to 41% further out than the
        // radius you actually have.
        if let radiusKm, radiusKm > 0, let latitude, let longitude {
            let latDelta = radiusKm / 111.32
            // Longitude degrees shrink with latitude; at 60° a degree is half
            // the distance it is at the equator. Clamped so the cosine cannot
            // approach zero near the poles and open the box to the whole world.
            let lngDelta = radiusKm / max(1, 111.32 * cos(latitude * .pi / 180))
            // Only the modern, explicitly-public origin contract participates
            // in live discovery. The old `lat`/`lng` pair had no trustworthy
            // privacy marker, so treating it as a fallback could make a private
            // account discoverable through a pre-migration post.
            if let near = try? await db.collection("posts")
                .whereField("latitude", isGreaterThan: latitude - latDelta)
                .whereField("latitude", isLessThan: latitude + latDelta)
                .limit(to: 200)
                .getDocuments() {
                for doc in near.documents {
                    let data = doc.data()
                    guard hasDiscoverableOrigin(data),
                          let plat = (data["latitude"] as? NSNumber)?.doubleValue,
                          let plng = (data["longitude"] as? NSNumber)?.doubleValue else { continue }
                    guard abs(plng - longitude) <= lngDelta else { continue }
                    let km = haversineKm(latitude, longitude, plat, plng)
                    guard km <= radiusKm else { continue }
                    let owner = (data["userID"] as? String) ?? (data["userId"] as? String) ?? ""
                    merge(owner,
                          data["username"] as? String,
                          (data["createdAt"] as? Timestamp)?.dateValue()) {
                        $0.inReach = true
                        // Nearest post wins: that is how far away they are.
                        if $0.distanceKm == nil || km < ($0.distanceKm ?? .infinity) { $0.distanceKm = km }
                    }
                }
            }
        }

        await fillMissingNames(&byID)

        // Favourites first — that is what favouriting is FOR — then everyone
        // else by how recently they turned up.
        // Favourites first — that is what favouriting is FOR. Then the people
        // you have actually met, newest first. Reach-only contacts come last
        // and are ordered by DISTANCE, because for someone you have never met
        // the only thing you know is how far away they are; among those,
        // nearest is the most callable.
        let sorted = byID.values.sorted { a, b in
            if a.favourite != b.favourite { return a.favourite }
            let aKnown = a.hasDM || a.intercepted
            let bKnown = b.hasDM || b.intercepted
            if aKnown != bKnown { return aKnown }
            if !aKnown && !bKnown {
                return (a.distanceKm ?? .infinity) < (b.distanceKm ?? .infinity)
            }
            return a.lastSeen > b.lastSeen
        }
        return sorted.map { c in
            [
                "id": c.id,
                "name": c.name,
                "favourite": c.favourite,
                "hasDM": c.hasDM,
                // What to say under the name, most specific reason first.
                "inReach": c.inReach,
                "distanceKm": c.distanceKm as Any,
                // What to say under the name, most specific reason first. A
                // reach-only contact gets the distance, because that IS the
                // reason they are callable and it is the thing that will stop
                // being true when either of you moves.
                "detail": c.favourite ? "favourite"
                    : c.hasDM ? "you have a chat"
                    : c.intercepted ? "crossed your radius"
                    : c.inReach ? String(format: "%.1f km away · in your radius", c.distanceKm ?? 0)
                    : "on Poplur",
            ]
        }
    }

    /// Great-circle km. The radius is a circle and the box query is not, so
    /// this is what turns one into the other.
    private func haversineKm(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let radius = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return radius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Reach must fail closed. Current public posts explicitly say
    /// `approximate`; hidden posts and either privacy flag are never enough to
    /// put their owner in somebody else's live House/phone discovery.
    private func hasDiscoverableOrigin(_ data: [String: Any]) -> Bool {
        guard data["locationVisibility"] as? String == "approximate" else { return false }
        for key in [
            "privateAccount", "ghostMode",
            "originHiddenByPrivateAccount", "originHiddenByGhostMode",
        ] {
            guard data[key] != nil else { continue }
            // A malformed privacy marker is not permission to disclose.
            guard let flag = data[key] as? Bool, flag == false else { return false }
        }
        return true
    }

    /// One batched pass for anyone still showing a uid-prefix placeholder,
    /// rather than a read per contact inside the merge loop.
    private func fillMissingNames(_ byID: inout [String: Contact]) async {
        let needing = byID.values
            .filter { $0.name == String($0.id.prefix(8)) }
            .map(\.id)
        guard !needing.isEmpty else { return }
        for id in needing.prefix(30) {
            guard let snapshot = try? await db.collection("users").document(id).getDocument(),
                  let data = snapshot.data() else { continue }
            let name = (data["username"] as? String) ?? (data["displayName"] as? String)
            if let name, !name.isEmpty { byID[id]?.name = name }
        }
    }

    /// Favourite / un-favourite. The doc id IS the other uid, so this is
    /// idempotent and un-favouriting needs no query.
    @discardableResult
    func setFavourite(_ otherUID: String, _ on: Bool, name: String?) async -> Bool {
        guard let uid, !otherUID.isEmpty, otherUID != uid else { return false }
        let ref = db.collection("users").document(uid)
            .collection("phoneFavourites").document(otherUID)
        do {
            if on {
                try await ref.setData([
                    "name": name ?? "",
                    "addedAt": FieldValue.serverTimestamp(),
                ], merge: true)
            } else {
                try await ref.delete()
            }
            return true
        } catch {
            print("[PoplurPhone] favourite write failed: \(error.localizedDescription)")
            return false
        }
    }
}
