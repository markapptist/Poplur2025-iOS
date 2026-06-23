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

    private override init() {
        super.init()
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        configureWatchConnectivity()
        registerObservers()
        refreshAndSendRadius()
    }

    func refreshAndSendRadius() {
        guard let userID = Auth.auth().currentUser?.uid, !userID.isEmpty else {
            send(radiusMeters: 0, postCount: 0)
            return
        }

        db.collection("posts")
            .whereField("userID", isEqualTo: userID)
            .getDocuments { [weak self] snapshot, error in
                if let error {
                    print("[WatchRadiusSync] Could not fetch radius: \(error.localizedDescription)")
                    return
                }

                let uniqueDocuments = Dictionary(grouping: snapshot?.documents ?? [], by: \.documentID)
                    .compactMap { $0.value.first }
                let totalRadius = uniqueDocuments.reduce(0) { partial, document in
                    partial + Self.radiusValue(from: document.data())
                }

                Task { @MainActor in
                    self?.send(radiusMeters: totalRadius, postCount: uniqueDocuments.count)
                }
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
