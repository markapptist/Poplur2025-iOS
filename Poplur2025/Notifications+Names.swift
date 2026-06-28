import Foundation
import CoreLocation
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
    static let ShowUserProfile = Notification.Name("ShowUserProfile")
    
    // Cube interactions
    static let CubeMotionUpdate = Notification.Name("CubeMotionUpdate")
    static let CubeGlobalDragChanged = Notification.Name("CubeGlobalDragChanged")
    static let CubeGlobalDragEnded = Notification.Name("CubeGlobalDragEnded")
    static let CubeGlobalTap = Notification.Name("CubeGlobalTap")
    static let cubeHoldBegan = Notification.Name("cubeHoldBegan")
    static let cubeHoldEnded = Notification.Name("cubeHoldEnded")
    static let cameraCubeHoldBegan = Notification.Name("cameraCubeHoldBegan")
    static let cameraCubeHoldEnded = Notification.Name("cameraCubeHoldEnded")
    static let cameraCubeTabViewTapped = Notification.Name("cameraCubeTabViewTapped")
    static let showCameraRollWindow = Notification.Name("ShowCameraRollWindow")
    static let CubeStartFlashing = Notification.Name("CubeStartFlashing")
    static let CubeStopFlashing = Notification.Name("CubeStopFlashing")
    static let CubeProfileIconOverrideChanged = Notification.Name("CubeProfileIconOverrideChanged")
    static let CenterMapOnUser = Notification.Name("CenterMapOnUser")
    
    // Feed and audio
    static let FeedChannelDidChange = Notification.Name("FeedChannelDidChange")
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
    static let OpenDMsRequested = Notification.Name("OpenDMsRequested")
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
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        }

        let generated = makeNotification(from: posts)
        if shouldCreateDailyNotification() {
            addInAppNotification(generated)
            await scheduleDeviceNotification(generated)
            defaults.set(Date(), forKey: lastDailyKey)
        }

        let totalRadius = posts.reduce(0) { $0 + max(0, $1.radius) }
        defaults.set(totalRadius, forKey: lastRadiusTotalKey)
    }

    func refreshDailyNotificationForCurrentUser() async {
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
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
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
