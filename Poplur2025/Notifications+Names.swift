import Foundation
import CoreLocation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import UserNotifications
import UIKit

extension Notification.Name {
    // Feed, Map, and Profile loading
    static let LoadFeedNow = Notification.Name("LoadFeedNow")
    static let LoadMapNow = Notification.Name("LoadMapNow")
    static let LoadProfileNow = Notification.Name("LoadProfileNow")
    
    // Tab and navigation
    static let ResetTabToTop = Notification.Name("ResetTabToTop")
    static let RecordTabBecameActive = Notification.Name("RecordTabBecameActive")
    static let StopMapAudio = Notification.Name("StopMapAudio")

    /// Web Settings asking the shell to end the session. The WebView
    /// coordinator has no handle on AuthViewModel, and the app owns it, so the
    /// request travels as a notification rather than a reference.
    static let PoplurSignOutRequested = Notification.Name("PoplurSignOutRequested")
    static let ShowUserProfile = Notification.Name("ShowUserProfile")
    
    // Cube interactions
    static let CubeMotionUpdate = Notification.Name("CubeMotionUpdate")
    static let CubeGlobalDragChanged = Notification.Name("CubeGlobalDragChanged")
    static let CubeGlobalDragEnded = Notification.Name("CubeGlobalDragEnded")
    static let CubeGlobalTap = Notification.Name("CubeGlobalTap")
    static let cubeHoldBegan = Notification.Name("cubeHoldBegan")
    static let cubeHoldMoved = Notification.Name("cubeHoldMoved")
    static let cubeHoldEnded = Notification.Name("cubeHoldEnded")
    static let cameraCubeHoldBegan = Notification.Name("cameraCubeHoldBegan")
    static let cameraCubeHoldEnded = Notification.Name("cameraCubeHoldEnded")
    static let cameraCubeTabViewTapped = Notification.Name("cameraCubeTabViewTapped")
    static let showCameraRollWindow = Notification.Name("ShowCameraRollWindow")
    static let CubeStartFlashing = Notification.Name("CubeStartFlashing")
    static let CubeStopFlashing = Notification.Name("CubeStopFlashing")
    static let CubeProfileIconOverrideChanged = Notification.Name("CubeProfileIconOverrideChanged")
    static let CubeFaceOverrideChanged = Notification.Name("CubeFaceOverrideChanged")
    static let CubeGoBack = Notification.Name("CubeGoBack")
    static let CenterMapOnUser = Notification.Name("CenterMapOnUser")
    
    // Feed and audio
    static let FeedChannelDidChange = Notification.Name("FeedChannelDidChange")
    static let FeedChannelUp = Notification.Name("FeedChannelUp")
    static let FeedChannelDown = Notification.Name("FeedChannelDown")
    static let PauseFeedAudio = Notification.Name("PauseFeedAudio")
    static let ResumeFeedAudio = Notification.Name("ResumeFeedAudio")
    static let PauseGlobalFeedAudio = Notification.Name("PauseGlobalFeedAudio")
    static let ActiveFeedPlayerDidChange = Notification.Name("ActiveFeedPlayerDidChange")
    static let FeedUserInteraction = Notification.Name("FeedUserInteraction")
    static let FeedOpenTVGuide = Notification.Name("FeedOpenTVGuide")
    static let FeedTVGuideBecameVisible = Notification.Name("FeedTVGuideBecameVisible")
    static let FeedTVGuideBecameHidden  = Notification.Name("FeedTVGuideBecameHidden")
    static let FeedOpenNews = Notification.Name("FeedOpenNews")
    static let FeedLikeCurrentPost = Notification.Name("FeedLikeCurrentPost")
    static let FeedOpenCommentComposer = Notification.Name("FeedOpenCommentComposer")
    static let FeedOpenCurrentPostProfile = Notification.Name("FeedOpenCurrentPostProfile")
    static let FeedCommentSubmitted = Notification.Name("FeedCommentSubmitted")
    static let FeedAdvanceOnMediaFailure = Notification.Name("FeedAdvanceOnMediaFailure")
    static let FeedAdvanceToNextPost = Notification.Name("FeedAdvanceToNextPost")
    static let PoplurAIGoToFeedChannel = Notification.Name("PoplurAIGoToFeedChannel")
    
    // Map and location
    static let CenterMapOnUserLocation = Notification.Name("CenterMapOnUserLocation")
    static let SharedRadiusDidChange = Notification.Name("SharedRadiusDidChange")
    static let MapSuggestedRadius = Notification.Name("MapSuggestedRadius")
    static let PoplurAIStartMapPost = Notification.Name("PoplurAIStartMapPost")
    static let PoplurAISetTourActive = Notification.Name("PoplurAISetTourActive")
    
    // Settings and UI
    static let OpenSettingsRequested = Notification.Name("OpenSettingsRequested")
    static let HoldMenuNavigate = Notification.Name("HoldMenuNavigate")
    static let OpenDMsRequested = Notification.Name("OpenDMsRequested")
    static let OpenPoplurStoreRequested = Notification.Name("OpenPoplurStoreRequested")
    static let OpenCreatorRequested = Notification.Name("OpenCreatorRequested")
    static let MainTabChildRouteVisibilityChanged = Notification.Name("MainTabChildRouteVisibilityChanged")
    
    // User stats
    static let UserPostCountDidChange = Notification.Name("UserPostCountDidChange")
    static let PoplurAIProfileSortRequested = Notification.Name("PoplurAIProfileSortRequested")
    static let PoplurAIShowAnalytics = Notification.Name("PoplurAIShowAnalytics")
    
    // Camera roll
    static let CameraRollImageSelected = Notification.Name("CameraRollImageSelected")
    static let CameraRollVideoSelected = Notification.Name("CameraRollVideoSelected")
    
    // Radius bar and capture
    static let currentPostRadiusDidChange = Notification.Name("CurrentPostRadiusDidChange")
    static let showCapturedPreviewRequested = Notification.Name("ShowCapturedPreviewRequested")
    static let capturePreviewDidDismiss = Notification.Name("CapturePreviewDidDismiss")
    static let animateRadiusBarToValue = Notification.Name("AnimateRadiusBarToValue")

    // In-app calling
    static let IncomingCallReceived = Notification.Name("IncomingCallReceived")
    static let popularPhoneDidPresent = Notification.Name("PopularPhoneDidPresent")
}

struct PoplurDeviceNotification: Identifiable, Codable, Hashable {
    enum Kind: String, Codable {
        case radiusGrowth
        case radiusDip
        case areaTakeover
        case dailyInsight
        case engagement
        case dm
        case mention
        case radiusEntry
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let createdAt: Date
    let isUnread: Bool
    let webKind: String?
    let actorHandle: String?
    let postId: String?
    let threadId: String?

    init(
        id: String,
        kind: Kind,
        title: String,
        detail: String,
        createdAt: Date,
        isUnread: Bool,
        webKind: String? = nil,
        actorHandle: String? = nil,
        postId: String? = nil,
        threadId: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.createdAt = createdAt
        self.isUnread = isUnread
        self.webKind = webKind
        self.actorHandle = actorHandle
        self.postId = postId
        self.threadId = threadId
    }
}

enum PoplurNotificationTier {
    case immediate
    case batched
    case digest
}

enum PoplurEngagementPushPref: String {
    case everyBatch = "every"
    case highlightsOnly = "highlights"
    case off = "off"
}

enum PoplurRadiusPushPref: String {
    case daily = "daily"
    case off = "off"
}

struct PoplurNotificationPostSignal {
    let id: String
    let latitude: Double
    let longitude: Double
    let radius: Int
    let viewCount: Int
}

@MainActor
final class PoplurNotificationCenter: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = PoplurNotificationCenter()

    @Published private(set) var notifications: [PoplurDeviceNotification] = []

    private let defaults = UserDefaults.standard
    private let notificationsKey = "poplur.notifications.items.v1"
    private let lastDailyKey = "poplur.notifications.lastDailyDate.v1"
    private let lastRadiusTotalKey = "poplur.notifications.lastRadiusTotal.v1"
    private let notificationIdentifier = "poplur.daily.radius.insight"
    private let serverInboxUIDKey = "poplur.notifications.serverInbox.uid.v1"
    private let serverInboxDocumentIDsKey = "poplur.notifications.serverInbox.documentIds.v1"

    // ── Tier system ─────────────────────────────────────────────────────
    private let prefMessagesKey = "poplur.notifications.pref.messages"
    private let prefEngagementKey = "poplur.notifications.pref.engagement"
    private let prefRadiusKey = "poplur.notifications.pref.radius"
    private let prefSoundsKey = "poplur.notifications.pref.sounds"
    private let lastPushAtKey = "poplur.notifications.lastPushAt"
    private let batchFlushInterval: TimeInterval = 15 * 60   // 15 minutes
    private let pushCooldown: TimeInterval = 5 * 60          // 5 minutes
    private var pendingBatch: [(webKind: String, user: String, detail: String)] = []
    private var flushTimer: Timer?
    private var serverInboxRegistration: ListenerRegistration?
    private var serverInboxAuthHandle: AuthStateDidChangeListenerHandle?
    private var serverInboxOwner: UUID?
    private var serverInboxObservedUID: String?
    private var serverInboxAccountUID: String?
    private var serverInboxDocumentIDs: [String: String] = [:]
    private var serverInboxOnChange: (([PoplurDeviceNotification]) -> Void)?

    var messagesPushEnabled: Bool {
        get { defaults.object(forKey: prefMessagesKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: prefMessagesKey) }
    }
    var engagementPushPref: PoplurEngagementPushPref {
        get {
            guard let raw = defaults.string(forKey: prefEngagementKey) else { return .everyBatch }
            return PoplurEngagementPushPref(rawValue: raw) ?? .everyBatch
        }
        set { defaults.set(newValue.rawValue, forKey: prefEngagementKey) }
    }
    var radiusPushPref: PoplurRadiusPushPref {
        get {
            guard let raw = defaults.string(forKey: prefRadiusKey) else { return .daily }
            return PoplurRadiusPushPref(rawValue: raw) ?? .daily
        }
        set { defaults.set(newValue.rawValue, forKey: prefRadiusKey) }
    }
    var soundsEnabled: Bool {
        get { defaults.object(forKey: prefSoundsKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: prefSoundsKey) }
    }

    private var lastPushAt: Date? {
        get { defaults.object(forKey: lastPushAtKey) as? Date }
        set { defaults.set(newValue, forKey: lastPushAtKey) }
    }

    private override init() {
        super.init()
        loadPersistedNotifications()
        serverInboxAccountUID = defaults.string(forKey: serverInboxUIDKey)
        serverInboxDocumentIDs = defaults.dictionary(forKey: serverInboxDocumentIDsKey) as? [String: String] ?? [:]
        startFlushTimer()
    }

    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    func refreshDailyNotification(from posts: [PoplurNotificationPostSignal]) async {
        // Do NOT ask here. This runs off a background refresh of the daily
        // digest, so Apple's sheet used to appear with no Poplur card in front
        // of it and no relationship to anything the user had just done. The ask
        // belongs to the clay permission card (HomeTwin.tsx →
        // PoplurPermissionRouting.requestNotificationsAfterPrimer).
        //
        // Still undecided means the in-app notification is built and stored,
        // but nothing is scheduled with the OS — scheduling without
        // authorization silently fails anyway.
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional

        let generated = makeNotification(from: posts)
        if shouldCreateDailyNotification() {
            addInAppNotification(generated)
            if authorized && radiusPushPref != .off && !isAppInForeground {
                await scheduleDeviceNotification(generated)
            }
            defaults.set(Date(), forKey: lastDailyKey)
        }

        let totalRadius = posts.reduce(0) { $0 + max(0, $1.radius) }
        defaults.set(totalRadius, forKey: lastRadiusTotalKey)
    }

    func refreshDailyNotificationForCurrentUser() async {
        // Guard against Firebase not being configured yet (Auth.auth() asserts if called before
        // FirebaseApp.configure()). Reachable early via the UI-test auth bypass, which can show
        // authenticatedContent before configuration completes.
        guard FirebaseApp.app() != nil else { return }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snapshot = try await Firestore.firestore()
                .collection("posts")
                .whereField("userID", isEqualTo: uid)
                .limit(to: 30)
                .getDocuments()

            let posts = snapshot.documents.compactMap { document -> PoplurNotificationPostSignal? in
                let data = document.data()
                guard let latitude = (data["latitude"] as? Double) ?? (data["latitude"] as? NSNumber)?.doubleValue,
                      let longitude = (data["longitude"] as? Double) ?? (data["longitude"] as? NSNumber)?.doubleValue else {
                    return nil
                }
                let radius = (data["radius"] as? Int) ?? (data["radius"] as? NSNumber)?.intValue ?? 0
                let viewCount = (data["viewCount"] as? Int) ?? (data["viewCount"] as? NSNumber)?.intValue ?? 0
                return PoplurNotificationPostSignal(
                    id: document.documentID,
                    latitude: latitude,
                    longitude: longitude,
                    radius: radius,
                    viewCount: viewCount
                )
            }

            await refreshDailyNotification(from: posts)
        } catch {
            await refreshDailyNotification(from: [])
        }
    }

    func markAllRead() {
        notifications = notifications.map {
            PoplurDeviceNotification(
                id: $0.id,
                kind: $0.kind,
                title: $0.title,
                detail: $0.detail,
                createdAt: $0.createdAt,
                isUnread: false,
                webKind: $0.webKind,
                actorHandle: $0.actorHandle,
                postId: $0.postId,
                threadId: $0.threadId
            )
        }
        persistNotifications()
        // Reading the list is what clears the badge — same rule the web bell
        // now follows via markEngagementSeen.
        refreshBadge()
        let ids = notifications.filter { serverInboxDocumentIDs[$0.id] != nil }.map(\.id)
        Task { await updateServerNotifications(ids: ids, read: true, dismissed: nil) }
    }

    func markNotificationsRead(ids: [String]) async {
        let selected = Set(ids.filter { !$0.isEmpty })
        guard !selected.isEmpty else { return }
        notifications = notifications.map { item in
            guard selected.contains(item.id), item.isUnread else { return item }
            return PoplurDeviceNotification(
                id: item.id,
                kind: item.kind,
                title: item.title,
                detail: item.detail,
                createdAt: item.createdAt,
                isUnread: false,
                webKind: item.webKind,
                actorHandle: item.actorHandle,
                postId: item.postId,
                threadId: item.threadId
            )
        }
        persistNotifications()
        refreshBadge()
        await updateServerNotifications(ids: Array(selected), read: true, dismissed: nil)
    }

    /// Owns exactly one canonical Firestore subscription for the web
    /// Notifications screen. Calling this again is pull-to-refresh: the old
    /// auth observer and query registration are removed before replacements
    /// are installed, so refresh can never multiply listeners.
    func reconnectServerInboxListener(
        owner: UUID,
        onChange: @escaping ([PoplurDeviceNotification]) -> Void
    ) {
        tearDownServerInboxListener()
        serverInboxOwner = owner
        serverInboxOnChange = onChange
        guard FirebaseApp.app() != nil else {
            onChange(notifications)
            return
        }
        let auth = Auth.auth()
        serverInboxAuthHandle = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                self?.bindServerInbox(uid: user?.uid, owner: owner)
            }
        }
    }

    func stopServerInboxListener(owner: UUID) {
        guard serverInboxOwner == owner else { return }
        tearDownServerInboxListener()
    }

    private func bindServerInbox(uid: String?, owner: UUID) {
        guard serverInboxOwner == owner else { return }
        serverInboxRegistration?.remove()
        serverInboxRegistration = nil

        if serverInboxAccountUID != uid {
            removeObservedServerRows()
            serverInboxAccountUID = uid
            persistServerInboxOwnership()
            serverInboxOnChange?(notifications)
        }
        serverInboxObservedUID = uid
        guard let uid else {
            serverInboxOnChange?(notifications)
            return
        }

        serverInboxRegistration = Firestore.firestore()
            .collection("users").document(uid)
            .collection("notifications")
            .order(by: "createdAt", descending: true)
            .limit(to: 80)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor [weak self] in
                    guard let self,
                          self.serverInboxOwner == owner,
                          self.serverInboxObservedUID == uid else { return }
                    if let error {
                        PoplurDiagLog.append("[PoplurNotifications] inbox listener failed: \(error.localizedDescription)")
                        return
                    }
                    self.applyServerInboxSnapshot(snapshot?.documents ?? [], uid: uid)
                }
            }
    }

    private func applyServerInboxSnapshot(_ documents: [QueryDocumentSnapshot], uid: String) {
        let priorServerIDs = Set(serverInboxDocumentIDs.keys)
        var documentIDs: [String: String] = [:]
        let serverRows = documents.compactMap { document -> PoplurDeviceNotification? in
            let data = document.data()
            let id = (data["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                .flatMap { $0.isEmpty ? nil : $0 } ?? document.documentID
            documentIDs[id] = document.documentID
            if data["isDismissed"] as? Bool == true { return nil }
            let title = (data["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                .flatMap { $0.isEmpty ? nil : $0 } ?? "Poplur"
            let detail = (data["detail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                .flatMap { $0.isEmpty ? nil : $0 } ?? "New activity on Poplur"
            let rawKind = data["kind"] as? String
            return PoplurDeviceNotification(
                id: id,
                kind: resolveKind(rawKind),
                title: title,
                detail: detail,
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date(),
                isUnread: data["isUnread"] as? Bool ?? true,
                webKind: rawKind,
                actorHandle: data["actorHandle"] as? String,
                postId: data["postId"] as? String,
                threadId: data["threadId"] as? String
            )
        }
        let localRows = notifications.filter { !priorServerIDs.contains($0.id) }
        serverInboxAccountUID = uid
        serverInboxDocumentIDs = documentIDs
        var seen = Set<String>()
        notifications = (serverRows + localRows)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.createdAt > $1.createdAt }
        if notifications.count > 80 { notifications = Array(notifications.prefix(80)) }
        persistServerInboxOwnership()
        persistNotifications()
        refreshBadge()
        serverInboxOnChange?(notifications)
    }

    private func removeObservedServerRows() {
        let ids = Set(serverInboxDocumentIDs.keys)
        if !ids.isEmpty { notifications.removeAll { ids.contains($0.id) } }
        serverInboxDocumentIDs = [:]
        persistNotifications()
        refreshBadge()
    }

    private func persistServerInboxOwnership() {
        if let serverInboxAccountUID {
            defaults.set(serverInboxAccountUID, forKey: serverInboxUIDKey)
        } else {
            defaults.removeObject(forKey: serverInboxUIDKey)
        }
        defaults.set(serverInboxDocumentIDs, forKey: serverInboxDocumentIDsKey)
    }

    private func tearDownServerInboxListener() {
        serverInboxRegistration?.remove()
        serverInboxRegistration = nil
        if let handle = serverInboxAuthHandle, FirebaseApp.app() != nil {
            Auth.auth().removeStateDidChangeListener(handle)
        }
        serverInboxAuthHandle = nil
        serverInboxObservedUID = nil
        serverInboxOwner = nil
        serverInboxOnChange = nil
    }

    func dismissNotifications(ids: [String]) async {
        let unique = Array(Set(ids.filter { !$0.isEmpty }))
        guard !unique.isEmpty else { return }
        notifications.removeAll { unique.contains($0.id) }
        persistNotifications()
        refreshBadge()
        await updateServerNotifications(ids: unique, read: nil, dismissed: true)
    }

    private func updateServerNotifications(ids: [String], read: Bool?, dismissed: Bool?) async {
        guard FirebaseApp.app() != nil, let uid = Auth.auth().currentUser?.uid else { return }
        guard serverInboxAccountUID == uid else { return }
        let persistedIds = ids.filter { serverInboxDocumentIDs[$0] != nil }
        guard !persistedIds.isEmpty else { return }
        let firestore = Firestore.firestore()
        let batch = firestore.batch()
        for id in persistedIds {
            guard let documentID = serverInboxDocumentIDs[id] else { continue }
            let reference = firestore.collection("users").document(uid)
                .collection("notifications").document(documentID)
            var fields: [String: Any] = [:]
            if let read {
                fields["isUnread"] = !read
                fields["readAt"] = FieldValue.serverTimestamp()
            }
            if let dismissed {
                fields["isDismissed"] = dismissed
                fields["dismissedAt"] = FieldValue.serverTimestamp()
            }
            batch.updateData(fields, forDocument: reference)
        }
        do {
            try await batch.commit()
        } catch {
            PoplurDiagLog.append("[PoplurNotifications] inbox update failed: \(error.localizedDescription)")
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let content = notification.request.content
        await MainActor.run { Self.shared.recordRemoteNotification(content) }
        let preferences = await MainActor.run {
            (Self.shared.soundsEnabled, Self.shared.messagesPushEnabled)
        }
        if content.userInfo["kind"] as? String == "dm" && !preferences.1 { return [] }
        var opts: UNNotificationPresentationOptions = [.banner, .badge]
        if preferences.0 { opts.insert(.sound) }
        return opts
    }

    /// Handles a tap on a delivered notification.
    ///
    /// This lives here rather than in NotificationsCoordinator because that class
    /// also assigns itself as the UNUserNotificationCenter delegate — from its
    /// init, at module load — while `configure()` runs later from
    /// didFinishLaunching and therefore WINS. Its didReceive has never been
    /// called, so the postFocusRequest it posts has never fired.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        await MainActor.run {
            Self.shared.recordRemoteNotification(content)
            // Accept BOTH spellings. The Cloud Function's data payload uses
            // `postId`; the older local path and NotificationsCoordinator use
            // `postID`. A silent case mismatch here is a tap that does nothing.
            let info = content.userInfo
            let postId = (info["postId"] as? String) ?? (info["postID"] as? String)
            if let postId, !postId.isEmpty {
                NotificationCenter.default.post(
                    name: .postFocusRequest,
                    object: nil,
                    userInfo: ["postID": postId]
                )
            }
            if let threadId = info["threadId"] as? String, !threadId.isEmpty {
                // Keep the route through a cold launch. NotificationCenter is
                // intentionally ephemeral; the post-login WebView may not
                // have installed its observer when the system delivers the tap.
                UserDefaults.standard.set(threadId, forKey: "poplur.pendingDMThreadId")
                NotificationCenter.default.post(
                    name: .OpenDMsRequested,
                    object: nil,
                    userInfo: ["threadId": threadId]
                )
            }
        }
    }

    /// Files an incoming engagement push into the in-app list.
    ///
    /// Keyed on engagementId, so the same push seen first in the foreground and
    /// then again on tap collapses to one row rather than two —
    /// addInAppNotification already replaces by id.
    private func recordRemoteNotification(_ content: UNNotificationContent) {
        let info = content.userInfo
        if info["kind"] as? String == "dm",
           let messageId = info["messageId"] as? String, !messageId.isEmpty {
            let notificationId = (info["notificationId"] as? String) ?? messageId
            addInAppNotification(
                PoplurDeviceNotification(
                    id: notificationId,
                    kind: .dm,
                    title: content.title,
                    detail: content.body,
                    createdAt: Date(),
                    isUnread: true,
                    webKind: "dm",
                    actorHandle: content.title,
                    threadId: info["threadId"] as? String
                )
            )
            refreshBadge()
            return
        }
        guard let engagementId = info["engagementId"] as? String, !engagementId.isEmpty else { return }
        let notificationId = (info["notificationId"] as? String) ?? engagementId
        let rawKind = info["kind"] as? String
        addInAppNotification(
            PoplurDeviceNotification(
                id: notificationId,
                kind: .engagement,
                title: content.title,
                detail: content.body,
                createdAt: Date(),
                isUnread: true,
                webKind: rawKind,
                actorHandle: info["actorHandle"] as? String,
                postId: info["postId"] as? String
            )
        )
        refreshBadge()
    }

    /// Keeps the springboard badge equal to the unread count.
    ///
    /// The daily digest set `content.badge` when SCHEDULING, which cannot be
    /// right for remote pushes — the server has no idea how many unread items
    /// this device holds. Owning it locally means the badge matches the list,
    /// and clearing it is just marking everything read.
    func refreshBadge() {
        let unread = notifications.filter(\.isUnread).count
        UNUserNotificationCenter.current().setBadgeCount(unread) { _ in }
    }

    private func shouldCreateDailyNotification() -> Bool {
        guard let lastDate = defaults.object(forKey: lastDailyKey) as? Date else { return true }
        return !Calendar.current.isDate(lastDate, inSameDayAs: Date())
    }

    private func addInAppNotification(_ notification: PoplurDeviceNotification) {
        notifications.removeAll { $0.id == notification.id }
        notifications.insert(notification, at: 0)
        if notifications.count > 40 {
            notifications = Array(notifications.prefix(40))
        }
        persistNotifications()
    }

    /// Receives a notification from the web layer and routes it through the
    /// tier system. Every event is immediately visible in the in-app list;
    /// push delivery depends on the tier, user preferences, and cooldown.
    func scheduleFromWeb(id: String, title: String, detail: String, kind: String?) async {
        guard !id.isEmpty, !title.isEmpty else { return }
        guard !notifications.contains(where: { $0.id == id }) else { return }

        let resolvedKind = resolveKind(kind)
        let item = PoplurDeviceNotification(
            id: id,
            kind: resolvedKind,
            title: title,
            detail: detail,
            createdAt: Date(),
            isUnread: true,
            webKind: kind,
            actorHandle: title
        )
        addInAppNotification(item)
        refreshBadge()

        let tier = classifyTier(resolvedKind)
        switch tier {
        case .immediate:
            if shouldPushKind(resolvedKind) {
                await schedulePush(id: id, title: title, body: detail, kind: resolvedKind)
            }
        case .batched:
            if engagementPushPref != .off {
                pendingBatch.append((webKind: kind ?? "like", user: title, detail: detail))
            }
        case .digest:
            break // handled by the existing daily refresh
        }
    }

    private func resolveKind(_ raw: String?) -> PoplurDeviceNotification.Kind {
        guard let raw else { return .engagement }
        switch raw {
        case "like", "view", "comment": return .engagement
        case "dm", "message":           return .dm
        case "mention":                 return .mention
        case "radiusEntry":             return .radiusEntry
        default:                        return .engagement
        }
    }

    private func classifyTier(_ kind: PoplurDeviceNotification.Kind) -> PoplurNotificationTier {
        switch kind {
        case .dm, .mention, .radiusEntry:
            return .immediate
        case .engagement:
            return .batched
        case .radiusGrowth, .radiusDip, .areaTakeover, .dailyInsight:
            return .digest
        }
    }

    private func shouldPushKind(_ kind: PoplurDeviceNotification.Kind) -> Bool {
        switch kind {
        case .dm, .mention:       return messagesPushEnabled
        case .radiusEntry:        return true
        case .engagement:         return engagementPushPref != .off
        case .radiusGrowth, .radiusDip, .areaTakeover, .dailyInsight:
            return radiusPushPref != .off
        }
    }

    private var isAppInForeground: Bool {
        UIApplication.shared.applicationState == .active
    }

    private func schedulePush(id: String, title: String, body: String, kind: PoplurDeviceNotification.Kind) async {
        // The in-app list already has this event. If the user is looking at
        // the app right now, a push banner on top is redundant noise.
        guard !isAppInForeground else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = soundsEnabled ? .default : nil
        content.badge = NSNumber(value: max(1, notifications.filter(\.isUnread).count))
        content.userInfo = [
            "poplurNotificationID": id,
            "kind": kind.rawValue
        ]
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
        lastPushAt = Date()
    }

    // ── Batch flush ─────────────────────────────────────────────────────

    private func startFlushTimer() {
        flushTimer = Timer.scheduledTimer(withTimeInterval: batchFlushInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.flushPendingBatch()
            }
        }
    }

    private func flushPendingBatch() async {
        guard !pendingBatch.isEmpty else { return }
        guard engagementPushPref != .off else {
            pendingBatch.removeAll()
            return
        }
        guard !isAppInForeground else {
            // Keep the batch — flush next time if the user has left.
            return
        }

        // Cooldown: if an immediate-tier push fired recently, defer.
        if let last = lastPushAt, Date().timeIntervalSince(last) < pushCooldown {
            return
        }

        let batch = pendingBatch
        pendingBatch.removeAll()

        // Highlights-only: skip small batches.
        if engagementPushPref == .highlightsOnly && batch.count < 5 {
            return
        }

        let (title, body) = composeBatchSummary(batch)
        await schedulePush(
            id: "batch-\(Int(Date().timeIntervalSince1970))",
            title: title,
            body: body,
            kind: .engagement
        )
    }

    private func composeBatchSummary(_ batch: [(webKind: String, user: String, detail: String)]) -> (String, String) {
        let likes = batch.filter { $0.webKind == "like" }.count
        let comments = batch.filter { $0.webKind == "comment" }.count
        let views = batch.filter { $0.webKind == "view" }.count

        var parts: [String] = []
        if likes > 0 { parts.append("\(likes) like\(likes == 1 ? "" : "s")") }
        if comments > 0 { parts.append("\(comments) comment\(comments == 1 ? "" : "s")") }
        if views > 0 { parts.append("\(views) view\(views == 1 ? "" : "s")") }

        let title: String
        if batch.count == 1, let first = batch.first {
            title = first.user
        } else {
            title = "\(batch.count) people interacted with your posts"
        }
        let body = parts.joined(separator: ", ")
        return (title, body.isEmpty ? "New activity on your posts" : body)
    }

    private func scheduleDeviceNotification(_ item: PoplurDeviceNotification) async {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.detail
        content.sound = .default
        content.badge = NSNumber(value: max(1, notifications.filter(\.isUnread).count))
        content.userInfo = [
            "poplurNotificationID": item.id,
            "kind": item.kind.rawValue
        ]

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])

        let request = UNNotificationRequest(
            identifier: notificationIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func makeNotification(from posts: [PoplurNotificationPostSignal]) -> PoplurDeviceNotification {
        let totalRadius = posts.reduce(0) { $0 + max(0, $1.radius) }
        let previousTotal = defaults.integer(forKey: lastRadiusTotalKey)
        let strongestArea = strongestArea(from: posts)
        let createdAt = Date()

        let kind: PoplurDeviceNotification.Kind
        let title: String
        let detail: String

        if let strongestArea, strongestArea.score >= 3 {
            kind = .areaTakeover
            title = "You are taking over \(strongestArea.name)"
            detail = "Your posts are clustering hard around \(strongestArea.name). AI says your radius there is becoming the signal to beat."
        } else if previousTotal > 0, totalRadius > previousTotal {
            let delta = totalRadius - previousTotal
            kind = .radiusGrowth
            title = "Your radius is climbing"
            detail = "AI check-in: you gained \(formatRadius(delta)) since the last scan. Keep posting in the areas that are already pulling reach."
        } else if previousTotal > 0, totalRadius < previousTotal {
            let delta = previousTotal - totalRadius
            kind = .radiusDip
            title = "Your radius cooled off"
            detail = "AI noticed a \(formatRadius(delta)) dip. A fresh post near your strongest area can help recover momentum today."
        } else {
            let random = [
                "AI scan complete: your radius is ready for a push. Post near an active area and watch what catches.",
                "Today’s radius read is steady. One strong local post could turn this into a takeover.",
                "Your map has room to grow today. AI is watching for the next area where your reach starts stacking."
            ].randomElement() ?? "Your radius report is ready."
            kind = .dailyInsight
            title = "Daily radius report"
            detail = strongestArea.map { "\(random) Current strongest area: \($0.name)." } ?? random
        }

        return PoplurDeviceNotification(
            id: "daily-\(Self.dayStamp(for: createdAt))",
            kind: kind,
            title: title,
            detail: detail,
            createdAt: createdAt,
            isUnread: true
        )
    }

    private func strongestArea(from posts: [PoplurNotificationPostSignal]) -> (name: String, score: Int)? {
        guard !posts.isEmpty else { return nil }
        var scores: [String: Int] = [:]

        for post in posts {
            let area = nearestArea(latitude: post.latitude, longitude: post.longitude)
            let radiusBoost = max(1, min(4, post.radius / 25_000))
            let viewBoost = max(0, min(3, post.viewCount / 1_000))
            scores[area, default: 0] += 1 + radiusBoost + viewBoost
        }

        return scores.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

    private func nearestArea(latitude: Double, longitude: Double) -> String {
        let knownAreas: [(String, Double, Double)] = [
            ("Tokyo", 35.6762, 139.6503),
            ("New York", 40.7128, -74.0060),
            ("Los Angeles", 34.0522, -118.2437),
            ("Toronto", 43.6532, -79.3832),
            ("London", 51.5074, -0.1278),
            ("Paris", 48.8566, 2.3522),
            ("Mexico City", 19.4326, -99.1332),
            ("Seoul", 37.5665, 126.9780),
            ("São Paulo", -23.5558, -46.6396),
            ("Sydney", -33.8688, 151.2093)
        ]

        let point = CLLocation(latitude: latitude, longitude: longitude)
        return knownAreas.min {
            point.distance(from: CLLocation(latitude: $0.1, longitude: $0.2)) <
            point.distance(from: CLLocation(latitude: $1.1, longitude: $1.2))
        }?.0 ?? "your area"
    }

    private func loadPersistedNotifications() {
        guard let data = defaults.data(forKey: notificationsKey),
              let decoded = try? JSONDecoder().decode([PoplurDeviceNotification].self, from: data) else {
            notifications = []
            return
        }
        notifications = decoded
    }

    private func persistNotifications() {
        guard let data = try? JSONEncoder().encode(notifications) else { return }
        defaults.set(data, forKey: notificationsKey)
    }

    private func formatRadius(_ meters: Int) -> String {
        if meters >= 1_000_000 {
            return String(format: "%.1fk km", Double(meters) / 1_000_000)
        }
        if meters >= 1_000 {
            return "\(meters / 1_000) km"
        }
        return "\(meters) m"
    }

    private static func dayStamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
