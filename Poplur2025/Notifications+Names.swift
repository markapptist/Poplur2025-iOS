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
    static let PoplurAIShowWakeTutorial = Notification.Name("PoplurAIShowWakeTutorial")
    
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
        /// Someone liked or commented on your post. Delivered remotely by the
        /// notifyOnEngagement Cloud Function, not scheduled locally.
        case engagement
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let createdAt: Date
    let isUnread: Bool
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

    private override init() {
        super.init()
        loadPersistedNotifications()
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
            if authorized { await scheduleDeviceNotification(generated) }
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
                isUnread: false
            )
        }
        persistNotifications()
        // Reading the list is what clears the badge — same rule the web bell
        // now follows via markEngagementSeen.
        refreshBadge()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // A push arriving while the app is open must still reach the list, or
        // the banner and the notifications screen disagree about what happened.
        await MainActor.run { Self.shared.recordIfEngagement(notification.request.content) }
        return [.banner, .sound, .badge]
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
            Self.shared.recordIfEngagement(content)
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
        }
    }

    /// Files an incoming engagement push into the in-app list.
    ///
    /// Keyed on engagementId, so the same push seen first in the foreground and
    /// then again on tap collapses to one row rather than two —
    /// addInAppNotification already replaces by id.
    private func recordIfEngagement(_ content: UNNotificationContent) {
        let info = content.userInfo
        guard let engagementId = info["engagementId"] as? String, !engagementId.isEmpty else { return }
        addInAppNotification(
            PoplurDeviceNotification(
                id: engagementId,
                kind: .engagement,
                title: content.title,
                detail: content.body,
                createdAt: Date(),
                isUnread: true
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

    /// Schedule a notification that ORIGINATED IN THE WEB LAYER.
    ///
    /// The outside-app notification and the in-app list were two unrelated
    /// systems. This process only ever scheduled `poplur.daily.radius.insight`
    /// — one recurring daily summary built from Firestore post signals, on a
    /// single reused identifier that each new one removes — while the list you
    /// actually see lives in the web bundle and is driven by the engagement
    /// log. So the push repeated the same line while the screen said something
    /// else entirely.
    ///
    /// `.engagement` was always meant to arrive remotely from the
    /// notifyOnEngagement Cloud Function. Until that backend is live nothing
    /// arrives at all, so the web forwards what it just logged and this
    /// schedules it here.
    ///
    /// Deliberately NOT sharing `notificationIdentifier`: that constant belongs
    /// to the daily insight, where replacing the pending one is correct. These
    /// carry their own ids so several can stand at once — which is the whole
    /// point of matching a LIST.
    func scheduleFromWeb(id: String, title: String, detail: String) async {
        guard !id.isEmpty, !title.isEmpty else { return }
        // Same id twice is the same notification: the web re-sends on reconnect
        // and a resend must not stack a duplicate on the lock screen.
        guard !notifications.contains(where: { $0.id == id }) else { return }

        let item = PoplurDeviceNotification(
            id: id,
            kind: .engagement,
            title: title,
            detail: detail,
            createdAt: Date(),
            isUnread: true
        )
        addInAppNotification(item)

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = detail
        content.sound = .default
        content.badge = NSNumber(value: max(1, notifications.filter(\.isUnread).count))
        content.userInfo = [
            "poplurNotificationID": id,
            "kind": PoplurDeviceNotification.Kind.engagement.rawValue
        ]
        // nil trigger: this already happened. The daily insight's 15s delay is
        // there to batch a summary; an engagement is news and lands now.
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
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
