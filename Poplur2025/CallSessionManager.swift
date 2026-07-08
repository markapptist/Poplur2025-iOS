import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import Combine

// MARK: - Call state

enum CallState: Equatable {
    case idle
    case outgoing(calleeName: String)
    case incoming(callerName: String, channelId: String, documentId: String)
    case connected(calleeName: String, channelId: String)
    case ended(reason: EndReason)

    enum EndReason: Equatable {
        case hangUp, declined, noAnswer
    }
}

// MARK: - Manager

/// Owns the lifecycle of a single call: Firestore signaling + Agora audio.
///
/// Signaling document path: `calls/{documentId}`
/// Fields: callerId, callerName, calleeId, calleeName, channelId, status, createdAt
///
/// Status transitions:
///   ringing → connected  (callee accepts)
///   ringing → declined   (callee declines)
///   ringing → ended      (caller cancels or timeout)
///   connected → ended    (either party hangs up)
///
/// TODO: replace FakeUser.id.uuidString with the real Firebase Auth UID of each
/// user once real user profiles are wired up in Firestore.
@MainActor
final class CallSessionManager: ObservableObject {
    static let shared = CallSessionManager()

    @Published private(set) var callState: CallState = .idle
    @Published private(set) var elapsedSeconds: Int = 0

    private var callDocumentId: String?
    private var documentListener: ListenerRegistration?
    private var incomingListener: ListenerRegistration?
    private var timerTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    // Lazy, not eager: `.shared` gets touched by HomeView.init (sometimes constructed
    // speculatively by SwiftUI's navigationDestination before the view is really on-screen),
    // which can happen before FirebaseApp.configure() finishes — Firestore.firestore() throws
    // an uncaught exception if called that early. Deferring to first real use avoids the race.
    private lazy var db = Firestore.firestore()

    private init() {}

    // MARK: - Start listening (call once after auth is confirmed)

    func startListeningForIncomingCalls() {
        // HomeView calls this unconditionally from .onAppear — guard against FirebaseApp not
        // being configured yet (e.g. UI-test auth bypass skips the normal wait for Firebase to
        // resolve, so HomeView can appear before FirebaseApp.configure() finishes elsewhere).
        // Auth.auth() itself asserts/crashes if called before configuration.
        guard FirebaseApp.app() != nil else { return }
        let myId = Auth.auth().currentUser?.uid ?? ""
        guard !myId.isEmpty else { return }

        incomingListener?.remove()
        incomingListener = db.collection("calls")
            .whereField("calleeId", isEqualTo: myId)
            .whereField("status", isEqualTo: "ringing")
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let self else { return }
                guard case .idle = self.callState else { return }
                guard let doc = snapshot?.documents.first else { return }

                let data       = doc.data()
                let callerName = data["callerName"] as? String ?? "Unknown"
                let channelId  = data["channelId"]  as? String ?? doc.documentID

                self.callState = .incoming(
                    callerName: callerName,
                    channelId: channelId,
                    documentId: doc.documentID
                )
                NotificationCenter.default.post(
                    name: .IncomingCallReceived,
                    object: nil,
                    userInfo: [
                        "callerName": callerName,
                        "channelId": channelId,
                        "documentId": doc.documentID
                    ]
                )
            }
    }

    // MARK: - Place outgoing call

    func placeCall(to callee: FakeUser) async {
        guard case .idle = callState else { return }

        let myUid      = Auth.auth().currentUser?.uid ?? "anonymous"
        let myName     = Auth.auth().currentUser?.displayName ?? "Poplur User"
        let channelId  = UUID().uuidString
        // TODO: replace callee.id.uuidString with callee's real Firebase Auth UID
        let calleeId   = callee.id.uuidString

        let payload: [String: Any] = [
            "callerId":   myUid,
            "callerName": myName,
            "calleeId":   calleeId,
            "calleeName": callee.name,
            "channelId":  channelId,
            "status":     "ringing",
            "createdAt":  FieldValue.serverTimestamp()
        ]

        guard let ref = try? await db.collection("calls").addDocument(data: payload) else { return }
        callDocumentId = ref.documentID
        callState = .outgoing(calleeName: callee.name)

        listenToDocument(ref.documentID, calleeName: callee.name)
        startNoAnswerTimeout()

        // ── Agora: join channel as broadcaster ──────────────────────────────
        // Uncomment after adding the AgoraRtcKit SPM package and filling
        // CallCredentials.agoraAppId:
        //
        // let engine = AgoraRtcEngineKit.sharedEngine(withAppId: CallCredentials.agoraAppId, delegate: nil)
        // engine.setChannelProfile(.communication)
        // engine.joinChannel(byToken: nil, channelId: channelId, info: nil, uid: 0)
        // ────────────────────────────────────────────────────────────────────
    }

    // MARK: - Accept incoming call

    func acceptCall(channelId: String, documentId: String, callerName: String) async {
        callDocumentId = documentId
        await setStatus("connected")

        callState = .connected(calleeName: callerName, channelId: channelId)
        startElapsedTimer()

        // ── Agora: join channel as audience/broadcaster ──────────────────────
        // let engine = AgoraRtcEngineKit.sharedEngine(withAppId: CallCredentials.agoraAppId, delegate: nil)
        // engine.setChannelProfile(.communication)
        // engine.joinChannel(byToken: nil, channelId: channelId, info: nil, uid: 0)
        // ────────────────────────────────────────────────────────────────────
    }

    // MARK: - Decline incoming call

    func declineCall(documentId: String) async {
        await setStatus("declined", on: documentId)
        reset(to: .idle)
    }

    // MARK: - Hang up / cancel

    func endCall() async {
        timeoutTask?.cancel()
        timerTask?.cancel()
        documentListener?.remove()
        documentListener = nil

        let id = callDocumentId
        reset(to: .ended(reason: .hangUp))

        if let id { await setStatus("ended", on: id) }

        // ── Agora: leave channel ─────────────────────────────────────────────
        // AgoraRtcEngineKit.sharedEngine(withAppId: CallCredentials.agoraAppId, delegate: nil).leaveChannel()
        // ────────────────────────────────────────────────────────────────────

        try? await Task.sleep(for: .seconds(1.8))
        if case .ended = callState { callState = .idle }
    }

    // MARK: - Private helpers

    private func listenToDocument(_ id: String, calleeName: String) {
        documentListener?.remove()
        documentListener = db.collection("calls").document(id)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let data = snap?.data() else { return }
                let status = data["status"] as? String ?? ""
                Task { @MainActor in
                    switch status {
                    case "connected":
                        guard case .outgoing = self.callState else { return }
                        let channelId = data["channelId"] as? String ?? id
                        self.callState = .connected(calleeName: calleeName, channelId: channelId)
                        self.startElapsedTimer()
                    case "declined":
                        self.reset(to: .ended(reason: .declined))
                        try? await Task.sleep(for: .seconds(1.8))
                        if case .ended = self.callState { self.callState = .idle }
                    case "ended":
                        guard case .connected = self.callState else { return }
                        self.reset(to: .ended(reason: .hangUp))
                        try? await Task.sleep(for: .seconds(1.8))
                        if case .ended = self.callState { self.callState = .idle }
                    default:
                        break
                    }
                }
            }
    }

    private func startNoAnswerTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task {
            try? await Task.sleep(for: .seconds(30))
            guard case .outgoing = callState else { return }
            if let id = callDocumentId { await setStatus("ended", on: id) }
            reset(to: .ended(reason: .noAnswer))
            try? await Task.sleep(for: .seconds(1.8))
            if case .ended = callState { callState = .idle }
        }
    }

    private func startElapsedTimer() {
        timerTask?.cancel()
        elapsedSeconds = 0
        timerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                elapsedSeconds += 1
            }
        }
    }

    private func setStatus(_ status: String, on id: String? = nil) async {
        let docId = id ?? callDocumentId
        guard let docId else { return }
        try? await db.collection("calls").document(docId).updateData(["status": status])
    }

    private func reset(to state: CallState) {
        timeoutTask?.cancel()
        timerTask?.cancel()
        documentListener?.remove()
        documentListener = nil
        callDocumentId = nil
        elapsedSeconds = 0
        callState = state
    }
}

// MARK: - Duration formatter

extension CallSessionManager {
    static func formattedDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
