import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

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
                let threads = (snapshot?.documents ?? []).compactMap { doc -> [String: Any]? in
                    let data = doc.data()
                    let others = (data["participants"] as? [String] ?? []).filter { $0 != uid }
                    let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
                        .timeIntervalSince1970 ?? 0
                    let readAt = ((data["readAtBy"] as? [String: Timestamp])?[uid])?
                        .dateValue().timeIntervalSince1970 ?? 0
                    let hiddenAt = ((data["hiddenAtBy"] as? [String: Timestamp])?[uid])?
                        .dateValue().timeIntervalSince1970 ?? 0
                    if hiddenAt >= updatedAt { return nil }
                    let unread = ((data["unreadBy"] as? [String: NSNumber])?[uid])?.intValue
                        ?? ((data["lastSenderId"] as? String) != uid && updatedAt > readAt ? 1 : 0)
                    return [
                        "id": doc.documentID,
                        "otherId": others.first ?? "",
                        "title": self.displayName(for: others.first, data: data),
                        "initials": Self.initials(self.displayName(for: others.first, data: data)),
                        "preview": data["lastMessage"] as? String ?? "No messages yet",
                        "unread": max(0, unread),
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
                    var result: [String: Any] = [
                        "id": doc.documentID,
                        // The page only needs to know which side to draw it on.
                        "from": (data["senderId"] as? String) == uid ? "me" : "them",
                        "text": data["text"] as? String ?? "",
                        "createdAtMillis": createdAtMillis,
                        "pending": doc.metadata.hasPendingWrites,
                    ]
                    if let kind = data["kind"] as? String { result["kind"] = kind }
                    if let mediaURL = data["mediaURL"] as? String { result["mediaURL"] = mediaURL }
                    if let mimeType = data["mimeType"] as? String { result["mimeType"] = mimeType }
                    if let duration = data["durationMillis"] as? NSNumber {
                        result["durationMillis"] = duration
                    }
                    return result
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
    /// The parent and message are committed in one atomic batch. getAfter() in
    /// the rules sees a first-time parent, and the stable id makes uncertain
    /// network retries idempotent instead of duplicating a bubble.
    @discardableResult
    func send(to otherUID: String, text: String, clientMessageID: String) async -> Bool {
        guard let uid, !otherUID.isEmpty, otherUID != uid else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 2000,
              Self.validMessageID(clientMessageID) else { return false }

        return await commitMessage(
            to: otherUID,
            clientMessageID: clientMessageID,
            preview: trimmed,
            fields: ["text": trimmed, "kind": "text"]
        )
    }

    func sendAttachment(
        to otherUID: String,
        threadID: String,
        source: String,
        kind: String,
        clientMessageID: String,
        durationMillis: Int?
    ) async -> Bool {
        guard let uid, otherUID != uid,
              threadID == Self.threadID(uid, otherUID),
              Self.validMessageID(clientMessageID),
              ["image", "video", "audio"].contains(kind),
              let item = Self.captureItem(source) else { return false }
        let mime = item.mimeType.lowercased()
        guard mime.hasPrefix("\(kind)/"), Self.acceptedSize(item, kind: kind) else { return false }
        let ext = Self.fileExtension(mime)
        let reference = Storage.storage().reference()
            .child("dmMedia/\(threadID)/\(uid)/\(clientMessageID).\(ext)")
        let metadata = StorageMetadata()
        metadata.contentType = mime
        do {
            if let data = item.data {
                _ = try await reference.putDataAsync(data, metadata: metadata)
            } else if let fileURL = item.fileURL {
                _ = try await reference.putFileAsync(from: fileURL, metadata: metadata)
            } else {
                return false
            }
            let url = try await reference.downloadURL()
            let label = kind == "image" ? "Photo" : kind == "video" ? "Video" : "Voice message"
            var fields: [String: Any] = [
                "text": label,
                "kind": kind,
                "mediaURL": url.absoluteString,
                "mimeType": mime,
            ]
            if kind == "audio", let durationMillis {
                fields["durationMillis"] = min(60_000, max(0, durationMillis))
            }
            let committed = await commitMessage(
                to: otherUID,
                clientMessageID: clientMessageID,
                preview: label,
                fields: fields
            )
            if !committed { try? await reference.delete() }
            return committed
        } catch {
            print("[PoplurDM] attachment send failed: \(error.localizedDescription)")
            try? await reference.delete()
            return false
        }
    }

    func hideThread(_ threadID: String) async -> Bool {
        guard let uid, !threadID.isEmpty, threadID.count <= 200 else { return false }
        do {
            try await db.collection("dmThreads").document(threadID).updateData([
                FieldPath(["hiddenAtBy", uid]): FieldValue.serverTimestamp(),
                FieldPath(["unreadBy", uid]): 0,
            ])
            if openThreadID == threadID { closeThread() }
            return true
        } catch {
            print("[PoplurDM] hide failed: \(error.localizedDescription)")
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
                .updateData([
                    FieldPath(["readAtBy", uid]): FieldValue.serverTimestamp(),
                    FieldPath(["unreadBy", uid]): 0,
                ])
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

    private func commitMessage(
        to otherUID: String,
        clientMessageID: String,
        preview: String,
        fields: [String: Any]
    ) async -> Bool {
        guard let uid else { return false }
        let id = Self.threadID(uid, otherUID)
        let threadRef = db.collection("dmThreads").document(id)
        let messageRef = threadRef.collection("messages").document(clientMessageID)
        do {
            if try await messageRef.getDocument().exists { return true }
            let batch = db.batch()
            batch.setData([
                "participants": [uid, otherUID].sorted(),
                "lastMessage": preview,
                "lastSenderId": uid,
                "updatedAt": FieldValue.serverTimestamp(),
                "unreadBy": [uid: 0, otherUID: FieldValue.increment(Int64(1))],
            ], forDocument: threadRef, merge: true)
            var message = fields
            message["senderId"] = uid
            message["clientMessageId"] = clientMessageID
            message["createdAt"] = FieldValue.serverTimestamp()
            batch.setData(message, forDocument: messageRef)
            try await batch.commit()
            return true
        } catch {
            print("[PoplurDM] send failed: \(error.localizedDescription)")
            return false
        }
    }

    private static func captureItem(_ source: String) -> PoplurWebCaptureStore.Item? {
        if source.hasPrefix("data:"),
           let comma = source.firstIndex(of: ","),
           source[..<comma].hasSuffix(";base64"),
           let data = Data(base64Encoded: String(source[source.index(after: comma)...])) {
            let header = String(source[source.index(source.startIndex, offsetBy: 5)..<comma])
            let mime = header.replacingOccurrences(of: ";base64", with: "")
            return PoplurWebCaptureStore.Item(data: data, fileURL: nil, mimeType: mime)
        }
        guard let url = URL(string: source),
              url.scheme == PoplurClayWebMap.scheme,
              url.host == PoplurClayWebMap.host,
              url.pathComponents.contains("captures") else { return nil }
        return PoplurWebCaptureStore.item(for: url.lastPathComponent)
    }

    private static func acceptedSize(_ item: PoplurWebCaptureStore.Item, kind: String) -> Bool {
        let limit = kind == "image" ? 12 * 1_024 * 1_024
            : kind == "audio" ? 8 * 1_024 * 1_024
            : 40 * 1_024 * 1_024
        if let data = item.data { return data.count > 0 && data.count < limit }
        guard let fileURL = item.fileURL,
              let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return false }
        return size > 0 && size < limit
    }

    private static func fileExtension(_ mime: String) -> String {
        if mime.contains("png") { return "png" }
        if mime.contains("webm") { return "webm" }
        if mime.contains("quicktime") { return "mov" }
        if mime.hasPrefix("audio/") { return "m4a" }
        if mime.hasPrefix("video/") { return "mp4" }
        return "jpg"
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
