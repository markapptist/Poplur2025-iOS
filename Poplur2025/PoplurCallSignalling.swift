import Foundation
import FirebaseAuth
import FirebaseFirestore

/// WebRTC signalling for in-app video calls.
///
/// The split: the WEB owns the peer connection (getUserMedia, RTCPeerConnection,
/// the video elements) because the chat it belongs to is a page in the WebView.
/// NATIVE owns Firestore, because the bundle has no Firebase. So this carries
/// offers, answers and ICE candidates between the two sides and nothing else —
/// no media ever passes through here, that goes peer to peer.
///
/// Nothing about this is a recording. A call doc is a rendezvous and is deleted
/// when the call ends.
@MainActor
final class PoplurCallSignalling {
    static let shared = PoplurCallSignalling()

    private let db = Firestore.firestore()
    private var uid: String? { Auth.auth().currentUser?.uid }

    private var callListener: ListenerRegistration?
    private var candidateListener: ListenerRegistration?
    private var incomingListener: ListenerRegistration?
    private var activeCallID: String?

    /// Fired for everything the page needs to know. One channel keeps the
    /// ordering the page sees identical to the ordering Firestore produced.
    var onEvent: (([String: Any]) -> Void)?

    // MARK: - Placing and answering

    /// Opens a call and starts relaying. The OFFER arrives later, from the page.
    /// `video` is only the receiver's UI/media intent; WebRTC media remains
    /// entirely in the page once the offer is exchanged.
    func startCall(to otherUID: String, callerName: String? = nil, video: Bool = false) async -> String? {
        guard let uid, !otherUID.isEmpty, otherUID != uid else { return nil }
        let ref = db.collection("calls").document()
        let displayName = callerName ?? Auth.auth().currentUser?.displayName ?? "Unknown"
        do {
            try await ref.setData([
                "participants": [uid, otherUID].sorted(),
                "callerId": uid,
                "callerName": displayName,
                "calleeId": otherUID,
                "status": "ringing",
                "video": video,
                "createdAt": FieldValue.serverTimestamp(),
                // Both this WebRTC signaller and the older Agora-based
                // CallSessionManager (iOS and Android) watch the same "calls"
                // collection for calleeId + status:"ringing" with no other
                // filter, so a call placed here used to also trigger the
                // Agora listener on the other side — which would then try to
                // join an Agora channel this call never publishes a token
                // for. This tag lets both Agora listeners recognize and skip
                // a call that was never theirs.
                "provider": "webrtc",
            ])
        } catch {
            print("[PoplurCall] could not open call: \(error.localizedDescription)")
            return nil
        }
        observe(ref.documentID)
        return ref.documentID
    }

    /// The page produced a local description; put it where the other side reads.
    func publishDescription(_ callID: String, type: String, sdp: String) async {
        guard !callID.isEmpty else { return }
        let key = type == "offer" ? "offer" : "answer"
        try? await db.collection("calls").document(callID).setData([
            key: ["type": type, "sdp": sdp],
            // Answering is what turns ringing into a live call.
            "status": key == "answer" ? "connected" : "ringing",
        ], merge: true)
    }

    /// One doc per candidate — they arrive continuously and independently.
    func publishCandidate(_ callID: String, candidate: [String: Any]) async {
        guard let uid, !callID.isEmpty else { return }
        var payload = candidate
        payload["senderId"] = uid
        payload["createdAt"] = FieldValue.serverTimestamp()
        try? await db.collection("calls").document(callID)
            .collection("candidates").addDocument(data: payload)
    }

    /// Ends the call for both sides and clears the rendezvous.
    func endCall(_ callID: String) async {
        guard !callID.isEmpty else { return }
        stopObserving()
        let ref = db.collection("calls").document(callID)
        // Mark ended first: the other side is listening on the doc, and a
        // delete alone can race their listener into "the doc vanished" with no
        // reason attached.
        try? await ref.setData(["status": "ended"], merge: true)
        if let candidates = try? await ref.collection("candidates").getDocuments() {
            for doc in candidates.documents { try? await doc.reference.delete() }
        }
        try? await ref.delete()
    }

    func declineCall(_ callID: String) async {
        guard !callID.isEmpty else { return }
        try? await db.collection("calls").document(callID)
            .setData(["status": "declined"], merge: true)
    }

    func acceptCall(_ callID: String) async {
        guard !callID.isEmpty else { return }
        observe(callID)
        try? await db.collection("calls").document(callID)
            .setData(["status": "connected"], merge: true)
    }

    // MARK: - Listening

    /// Relays the other side's description, their candidates, and the ending.
    func observe(_ callID: String) {
        stopObserving()
        activeCallID = callID
        guard let uid else { return }
        let ref = db.collection("calls").document(callID)

        callListener = ref.addSnapshotListener { [weak self] snapshot, _ in
            guard let self else { return }
            guard let data = snapshot?.data() else {
                // The doc is gone: the other side hung up and cleaned up.
                self.onEvent?(["type": "poplurCallEnded", "callId": callID])
                self.stopObserving()
                return
            }
            let status = data["status"] as? String ?? ""
            if status == "ended" || status == "declined" {
                self.onEvent?(["type": "poplurCallEnded", "callId": callID, "reason": status])
                self.stopObserving()
                return
            }
            let isCaller = (data["callerId"] as? String) == uid
            // Each side needs only the OTHER side's description.
            let wanted = isCaller ? "answer" : "offer"
            if let description = data[wanted] as? [String: Any],
               let sdp = description["sdp"] as? String {
                self.onEvent?([
                    "type": "poplurCallDescription",
                    "callId": callID,
                    "sdpType": description["type"] as? String ?? wanted,
                    "sdp": sdp,
                ])
            }
        }

        candidateListener = ref.collection("candidates")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                for change in snapshot?.documentChanges ?? [] where change.type == .added {
                    var data = change.document.data()
                    // Your own candidates come back on the same listener; feeding
                    // them into your own peer connection is at best wasted work
                    // and at worst a connection that never completes.
                    guard (data["senderId"] as? String) != uid else { continue }
                    data.removeValue(forKey: "senderId")
                    data.removeValue(forKey: "createdAt")
                    self.onEvent?([
                        "type": "poplurCallCandidate",
                        "callId": callID,
                        "candidate": data,
                    ])
                }
            }
    }

    /// Watches for somebody calling YOU while the app is open.
    ///
    /// Foreground only, deliberately: ringing a locked phone needs PushKit and
    /// CallKit, and Apple requires a CallKit report on every VoIP push or it
    /// kills the app. That is its own piece of work, not a flag on this one.
    func observeIncoming() {
        guard let uid else { return }
        incomingListener?.remove()
        incomingListener = db.collection("calls")
            .whereField("calleeId", isEqualTo: uid)
            .whereField("status", isEqualTo: "ringing")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                for change in snapshot?.documentChanges ?? [] where change.type == .added {
                    let data = change.document.data()
                    self.onEvent?([
                        "type": "poplurCallIncoming",
                        "callId": change.document.documentID,
                        "callerId": data["callerId"] as? String ?? "",
                        "callerName": data["callerName"] as? String ?? "Unknown",
                        "video": data["video"] as? Bool ?? false,
                    ])
                }
            }
    }

    func stopObserving() {
        callListener?.remove(); callListener = nil
        candidateListener?.remove(); candidateListener = nil
        activeCallID = nil
    }

    func stopAll() {
        stopObserving()
        incomingListener?.remove(); incomingListener = nil
    }
}
