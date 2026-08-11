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
        refreshAndSendRadius()
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
            var lastDocument: QueryDocumentSnapshot?
            var totalRadius = 0
            var postCount = 0

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
                    totalRadius += Self.radiusValue(from: document.data())
                    postCount += 1
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
            send(radiusMeters: totalRadius, postCount: postCount)
        } catch is CancellationError {
            return
        } catch {
            print("[WatchRadiusSync] Could not fetch radius: \(error.localizedDescription)")
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

    private func send(radiusMeters: Int, postCount: Int) {
        guard WCSession.isSupported() else { return }

        let payload: [String: Any] = [
            "overallRadiusMeters": max(0, radiusMeters),
            "postCount": max(0, postCount),
            "updatedAt": Date().timeIntervalSince1970
        ]

        let session = WCSession.default
        do {
            try session.updateApplicationContext(payload)
        } catch {
            print("[WatchRadiusSync] Could not update watch context: \(error.localizedDescription)")
        }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("[WatchRadiusSync] Could not send live watch message: \(error.localizedDescription)")
            }
        }
    }

    private static func radiusValue(from data: [String: Any]) -> Int {
        if let value = data["radius"] as? Int { return value }
        if let value = data["radius"] as? Double { return Int(value) }
        if let value = data["radius"] as? NSNumber { return value.intValue }
        if let value = data["radius"] as? String { return Int(value) ?? 0 }
        return 0
    }
}

extension WatchRadiusSync: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            WatchRadiusSync.shared.refreshAndSendRadius()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
