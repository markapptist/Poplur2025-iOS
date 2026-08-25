import Foundation
import FirebaseAuth
import FirebaseFirestore

/// Real direct messages, for the web chat screen.
///
/// The chat lives in `poplur-subscreen-twins.js` and had a hardcoded array of
/// two canned messages behind it. The web bundle has no Firebase at all — every
/// piece of real data crosses this bridge — so DMs are read and written here and
/// pushed to the page, the same way profile data already is.
///
/// Thread ids are the two uids sorted and joined, so opening a chat with the
/// same person twice can never fork into two threads and no lookup is needed to
/// find an existing one. The rules enforce that shape too, or a client could
/// create a thread at an id a later pair would also resolve to.
@MainActor
final class PoplurDirectMessages {
    static let shared = PoplurDirectMessages()

    private let db = Firestore.firestore()
    /// One listener per open thread, torn down when the page leaves it. Without
    /// this a listener would survive every thread switch and the page would
    /// keep receiving messages for conversations it had already closed.
    private var threadListener: ListenerRegistration?
    private var threadStateListener: ListenerRegistration?
    private var listListener: ListenerRegistration?
    private var openThreadID: String?

    private var uid: String? { Auth.auth().currentUser?.uid }

    static func threadID(_ a: String, _ b: String) -> String {
        a < b ? "\(a)_\(b)" : "\(b)_\(a)"
    }

    // MARK: - Reading

    /// Live list of this account's threads, newest first. `onChange` fires
    /// again on every update, so the page never has to poll.
    func observeThreads(onChange: @escaping ([[String: Any]]) -> Void) {
        guard let uid else { onChange([]); return }
        listListener?.remove()
        listListener = db.collection("dmThreads")
            .whereField("participants", arrayContains: uid)
            .order(by: "updatedAt", descending: true)
            .limit(to: 50)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self else { return }
                if let error {
                    // A failed index or rule is worth saying out loud: the page
                    // would otherwise just show an empty inbox forever.
                    print("[PoplurDM] thread list failed: \(error.localizedDescription)")
                    onChange([])
                    return
                }
                let threads = (snapshot?.documents ?? []).map { doc -> [String: Any] in
                    let data = doc.data()
                    let others = (data["participants"] as? [String] ?? []).filter { $0 != uid }
                    let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
                        .timeIntervalSince1970 ?? 0
                    let readAt = ((data["readAtBy"] as? [String: Timestamp])?[uid])?
                        .dateValue().timeIntervalSince1970 ?? 0
                    let unread = (data["lastSenderId"] as? String) != uid && updatedAt > readAt
                        ? 1 : 0
                    return [
                        "id": doc.documentID,
                        "otherId": others.first ?? "",
                        "title": self.displayName(for: others.first, data: data),
                        "initials": Self.initials(self.displayName(for: others.first, data: data)),
                        "preview": data["lastMessage"] as? String ?? "No messages yet",
                        "unread": unread,
                        "updatedAtMillis": updatedAt * 1000,
                    ]
                }
                onChange(threads)
            }
    }

    /// Live messages for one thread, oldest first (the order a chat reads in).
    func observeThread(
        _ threadID: String,
        onChange: @escaping ([[String: Any]]) -> Void,
        onState: @escaping ([String: Any]) -> Void
    ) {
        guard let uid else { onChange([]); return }
        threadListener?.remove()
        threadStateListener?.remove()
        openThreadID = threadID
        threadListener = db.collection("dmThreads").document(threadID)
            .collection("messages")
            .order(by: "createdAt")
            .limit(to: 200)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    print("[PoplurDM] thread failed: \(error.localizedDescription)")
                    onChange([])
                    return
                }
                let messages = (snapshot?.documents ?? []).map { doc -> [String: Any] in
                    let data = doc.data()
                    let createdAtMillis = (data["createdAt"] as? Timestamp).map {
                        $0.dateValue().timeIntervalSince1970 * 1000
                    } ?? 0
                    return [
                        "id": doc.documentID,
                        // The page only needs to know which side to draw it on.
                        "from": (data["senderId"] as? String) == uid ? "me" : "them",
                        "text": data["text"] as? String ?? "",
                        "createdAtMillis": createdAtMillis,
                        "pending": doc.metadata.hasPendingWrites,
                    ]
                }
                onChange(messages)
            }

        let threadRef = db.collection("dmThreads").document(threadID)
        threadStateListener = threadRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                print("[PoplurDM] thread state failed: \(error.localizedDescription)")
                return
            }
            guard let data = snapshot?.data(),
                  let participants = data["participants"] as? [String],
                  participants.contains(uid) else { return }
            let otherUID = participants.first { $0 != uid }
            let typingAt = otherUID.flatMap {
                (data["typingBy"] as? [String: Timestamp])?[$0]
            }.map { $0.dateValue().timeIntervalSince1970 * 1000 }
            let otherReadAt = otherUID.flatMap {
                (data["readAtBy"] as? [String: Timestamp])?[$0]
            }.map { $0.dateValue().timeIntervalSince1970 * 1000 }
            var state: [String: Any] = ["threadId": threadID]
            if let typingAt { state["typingAtMillis"] = typingAt }
            if let otherReadAt { state["otherReadAtMillis"] = otherReadAt }
            onState(state)

            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
                .timeIntervalSince1970 ?? 0
            let ownReadAt = ((data["readAtBy"] as? [String: Timestamp])?[uid])?
                .dateValue().timeIntervalSince1970 ?? 0
            if (data["lastSenderId"] as? String) != uid && updatedAt > ownReadAt {
                Task { @MainActor [weak self] in await self?.markRead(threadID) }
            }
        }
    }

    func closeThread() {
        if let openThreadID, let uid {
            db.collection("dmThreads").document(openThreadID).updateData([
                FieldPath(["typingBy", uid]): FieldValue.delete(),
            ]) { error in
                if let error {
                    print("[PoplurDM] typing cleanup failed: \(error.localizedDescription)")
                }
            }
        }
        threadListener?.remove()
        threadListener = nil
        threadStateListener?.remove()
        threadStateListener = nil
        openThreadID = nil
    }

    func stop() {
        closeThread()
        listListener?.remove()
        listListener = nil
    }

    // MARK: - Writing

    /// Sends into a thread, creating it if this is the first message.
    ///
    /// The thread doc is written with merge BEFORE the message so the rules can
    /// see `participants` when the message create is evaluated — a message into
    /// a thread that does not exist yet is denied, because `inThread()` reads
    /// the parent.
    @discardableResult
    func send(to otherUID: String, text: String, clientMessageID: String) async -> Bool {
        guard let uid, !otherUID.isEmpty, otherUID != uid else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2000,
              Self.validMessageID(clientMessageID) else { return false }

        let id = Self.threadID(uid, otherUID)
        let threadRef = db.collection("dmThreads").document(id)
        let messageRef = threadRef.collection("messages").document(clientMessageID)
        do {
            if try await messageRef.getDocument().exists { return true }
            let batch = db.batch()
            batch.setData([
                "participants": [uid, otherUID].sorted(),
                "lastMessage": trimmed,
                "lastSenderId": uid,
                "updatedAt": FieldValue.serverTimestamp(),
            ], forDocument: threadRef, merge: true)
            batch.setData([
                "senderId": uid,
                "text": trimmed,
                "clientMessageId": clientMessageID,
                "createdAt": FieldValue.serverTimestamp(),
            ], forDocument: messageRef)
            try await batch.commit()
            return true
        } catch {
            print("[PoplurDM] send failed: \(error.localizedDescription)")
            return false
        }
    }

    func setTyping(_ threadID: String, typing: Bool) async {
        guard let uid, threadID == openThreadID else { return }
        let value: Any = typing ? FieldValue.serverTimestamp() : FieldValue.delete()
        do {
            try await db.collection("dmThreads").document(threadID)
                .updateData([FieldPath(["typingBy", uid]): value])
        } catch {
            print("[PoplurDM] typing update failed: \(error.localizedDescription)")
        }
    }

    private func markRead(_ threadID: String) async {
        guard let uid, threadID == openThreadID else { return }
        do {
            try await db.collection("dmThreads").document(threadID)
                .updateData([FieldPath(["readAtBy", uid]): FieldValue.serverTimestamp()])
        } catch {
            print("[PoplurDM] read receipt failed: \(error.localizedDescription)")
        }
    }

    private static func validMessageID(_ value: String) -> Bool {
        value.hasPrefix("msg-")
            && value.utf8.count >= 20
            && value.utf8.count <= 100
            && value.unicodeScalars.allSatisfy { scalar in
                (scalar.value >= 48 && scalar.value <= 57)
                    || (scalar.value >= 65 && scalar.value <= 90)
                    || (scalar.value >= 97 && scalar.value <= 122)
                    || scalar == "-"
            }
    }

    // MARK: - Names

    /// Cached so a thread list of 50 does not become 50 profile reads on every
    /// snapshot — the list listener fires on every new message.
    private var nameCache: [String: String] = [:]

    private func displayName(for otherUID: String?, data: [String: Any]) -> String {
        guard let otherUID, !otherUID.isEmpty else { return "Poplur" }
        if let cached = nameCache[otherUID] { return cached }
        // A denormalised name on the thread avoids a read entirely when present.
        if let names = data["participantNames"] as? [String: String],
           let name = names[otherUID], !name.isEmpty {
            nameCache[otherUID] = name
            return name
        }
        Task { [weak self] in
            guard let self else { return }
            let snapshot = try? await self.db.collection("users").document(otherUID).getDocument()
            let profile = snapshot?.data() ?? [:]
            let name = (profile["username"] as? String)
                ?? (profile["displayName"] as? String)
                ?? String(otherUID.prefix(8))
            await MainActor.run { self.nameCache[otherUID] = name }
        }
        return String(otherUID.prefix(8))
    }

    private static func initials(_ name: String) -> String {
        let letters = name
            .replacingOccurrences(of: "@", with: "")
            .split(separator: " ")
            .compactMap { $0.first }
            .prefix(2)
        let joined = String(letters).uppercased()
        return joined.isEmpty ? "P" : joined
    }
}
