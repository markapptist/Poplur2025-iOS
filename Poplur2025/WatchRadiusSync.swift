import Foundation
import FirebaseAuth
import FirebaseFirestore
@preconcurrency import WatchConnectivity
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class WatchRadiusSync: NSObject {
    static let shared = WatchRadiusSync()

    private var didStart = false
    private var observerTokens: [NSObjectProtocol] = []
    private let db = Firestore.firestore()
    private let pageSize = 100
    private var refreshTask: Task<Void, Never>?
    private var refreshToken: UUID?
    private var refreshRequested = false
    private var authListener: AuthStateDidChangeListenerHandle?
    private var latestSnapshot: WatchRadiusSnapshot?
    private var latestUserID: String?
    private var accountSnapshotRevision = UUID()

    private override init() {
        super.init()
    }

    deinit {
        observerTokens.forEach { NotificationCenter.default.removeObserver($0) }
        refreshTask?.cancel()
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        configureWatchConnectivity()
        registerObservers()
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor in self?.refreshAndSendRadius() }
        }
        refreshAndSendRadius()
    }

    /// Reuse the exact live account total forwarded to the reachable web home.
    func publishAccountRadius(radiusMeters: Double, postCount: Int, userID: String) {
        guard userID == Auth.auth().currentUser?.uid, radiusMeters.isFinite else { return }
        accountSnapshotRevision = UUID()
        send(radiusMeters: radiusMeters, postCount: postCount)
    }

    func refreshAndSendRadius() {
        refreshRequested = true
        guard refreshTask == nil else { return }
        let token = UUID()
        refreshToken = token
        refreshTask = Task { @MainActor [weak self] in
            await self?.drainRefreshRequests(token: token)
        }
    }

    /// Collapse launch/auth/post-change/foreground bursts into one active query
    /// and, at most, one trailing refresh. The old callback path could retain
    /// several complete post collections at the same time.
    private func drainRefreshRequests(token: UUID) async {
        while refreshRequested, !Task.isCancelled {
            refreshRequested = false
            await fetchAndSendRadiusPaged()
        }
        if refreshToken == token {
            refreshTask = nil
            refreshToken = nil
        }
    }

    /// Walk the user's posts a page at a time. This preserves the exact total
    /// without retaining an unbounded Firestore snapshot or grouping copy.
    private func fetchAndSendRadiusPaged() async {
        guard let userID = Auth.auth().currentUser?.uid, !userID.isEmpty else {
            send(radiusMeters: 0, postCount: 0)
            return
        }

        do {
            let revision = accountSnapshotRevision
            var lastDocument: QueryDocumentSnapshot?
            var totals = WatchAccountRadiusTotals()

            while !Task.isCancelled {
                var query: Query = db.collection("posts")
                    .whereField("userID", isEqualTo: userID)
                    .limit(to: pageSize)
                if let lastDocument {
                    query = query.start(afterDocument: lastDocument)
                }

                let snapshot = try await query.getDocuments()
                try Task.checkCancellation()
                for document in snapshot.documents {
                    totals.include(document.data())
                }

                guard snapshot.documents.count == pageSize,
                      let last = snapshot.documents.last else { break }
                lastDocument = last
                await Task.yield()
            }

            try Task.checkCancellation()
            guard Auth.auth().currentUser?.uid == userID else {
                refreshRequested = true
                return
            }
            // A live post-change snapshot can arrive while these pages load.
            // Never stamp the older query with a newer time and replace it.
            guard revision == accountSnapshotRevision else { return }
            send(radiusMeters: totals.reach, postCount: totals.postCount)
        } catch is CancellationError {
            return
        } catch {
            PoplurDiagLog.append("[WatchRadiusSync] fetch FAILED: \(error.localizedDescription)")
        }
    }

    private func configureWatchConnectivity() {
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func registerObservers() {
        let notificationNames: [Notification.Name] = [
            .SharedRadiusDidChange,
            Notification.Name("PostCreated"),
            Notification.Name("ProfileRemovePost"),
            Notification.Name("RefreshProfileAfterUpload")
        ]

        observerTokens = notificationNames.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshAndSendRadius()
                }
            }
        }

        #if canImport(UIKit)
        let activeToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAndSendRadius()
            }
        }
        observerTokens.append(activeToken)

        let backgroundToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshTask?.cancel()
                self?.refreshTask = nil
                self?.refreshToken = nil
                self?.refreshRequested = false
            }
        }
        observerTokens.append(backgroundToken)
        #endif
    }

    private func send(radiusMeters: Double, postCount: Int) {
        guard WCSession.isSupported() else { return }
        latestSnapshot = WatchRadiusSnapshot(radiusMeters: radiusMeters, postCount: postCount)
        latestUserID = Auth.auth().currentUser?.uid
        sendLatestSnapshot()
    }

    private func sendLatestSnapshot() {
        let session = WCSession.default
        guard session.activationState == .activated,
              latestUserID == Auth.auth().currentUser?.uid,
              let payload = latestSnapshot?.payload else {
            PoplurDiagLog.append("[WatchRadiusSync] send skipped: state=\(session.activationState.rawValue) snapshot=\(latestSnapshot != nil) userMatch=\(latestUserID == Auth.auth().currentUser?.uid)")
            return
        }
        do {
            try session.updateApplicationContext(payload)
            PoplurDiagLog.append("[WatchRadiusSync] context sent \(Int(latestSnapshot?.radiusMeters ?? 0)) m / \(latestSnapshot?.postCount ?? 0) posts reachable=\(session.isReachable) watchAppInstalled=\(session.isWatchAppInstalled)")
        } catch {
            PoplurDiagLog.append("[WatchRadiusSync] context FAILED: \(error.localizedDescription)")
        }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                PoplurDiagLog.append("[WatchRadiusSync] live message FAILED: \(error.localizedDescription)")
            }
        }
    }

}

extension WatchRadiusSync: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        PoplurDiagLog.append("[WatchRadiusSync] activation state=\(activationState.rawValue) paired=\(session.isPaired) watchAppInstalled=\(session.isWatchAppInstalled) reachable=\(session.isReachable) error=\(error?.localizedDescription ?? "none")")
        Task { @MainActor in
            self.sendLatestSnapshot()
            self.refreshAndSendRadius()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        PoplurDiagLog.append("[WatchRadiusSync] reachability changed reachable=\(session.isReachable) watchAppInstalled=\(session.isWatchAppInstalled)")
        guard session.isReachable else { return }
        Task { @MainActor in self.refreshAndSendRadius() }
    }

    /// watchOS installs from Xcode/devicectl flip this without a reachability
    /// change; the context must be re-sent or the new app starts with "—".
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        PoplurDiagLog.append("[WatchRadiusSync] watch state changed paired=\(session.isPaired) watchAppInstalled=\(session.isWatchAppInstalled) reachable=\(session.isReachable)")
        Task { @MainActor in
            self.sendLatestSnapshot()
            self.refreshAndSendRadius()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                            replyHandler: @escaping ([String: Any]) -> Void) {
        guard message["request"] as? String == "radiusSnapshot" else {
            PoplurDiagLog.append("[WatchRadiusSync] unknown watch message keys=\(message.keys.sorted())")
            replyHandler(["pending": true])
            return
        }
        Task { @MainActor in
            self.refreshAndSendRadius()
            let snapshot = self.latestUserID == Auth.auth().currentUser?.uid ? self.latestSnapshot : nil
            PoplurDiagLog.append("[WatchRadiusSync] watch requested snapshot; replying \(snapshot.map { "\(Int($0.radiusMeters)) m / \($0.postCount) posts" } ?? "pending (no snapshot yet)")")
            replyHandler(snapshot?.payload ?? ["pending": true])
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
