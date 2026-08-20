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
///
/// "Intercept" is read from `engagements`, because that is the only DURABLE
/// record that a crossing happened. A live geo query would answer "who is in
/// range right now", which is a different question and gone the moment either
/// of you moves; an engagement is the moment a post actually reached someone,
/// and it persists. Both directions count: people who engaged your posts, and
/// people whose posts you engaged.
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
        /// Most recent moment this person showed up, for ordering.
        var lastSeen: Date = .distantPast
    }

    /// Everything the phone needs, newest-first within each tier.
    func contacts() async -> [[String: Any]] {
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

        await fillMissingNames(&byID)

        // Favourites first — that is what favouriting is FOR — then everyone
        // else by how recently they turned up.
        let sorted = byID.values.sorted { a, b in
            if a.favourite != b.favourite { return a.favourite }
            return a.lastSeen > b.lastSeen
        }
        return sorted.map { c in
            [
                "id": c.id,
                "name": c.name,
                "favourite": c.favourite,
                "hasDM": c.hasDM,
                // What to say under the name, most specific reason first.
                "detail": c.favourite ? "favourite"
                    : c.hasDM ? "you have a chat"
                    : c.intercepted ? "crossed your radius"
                    : "on Poplur",
            ]
        }
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
