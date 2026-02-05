import Foundation
import UserNotifications
import SwiftUI

final class NotificationsCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsCoordinator()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // Handle taps on delivered notifications
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let postID = userInfo["postID"] as? String {
            MapView.postFocusRequest(postID: postID)
        }
        completionHandler()
    }

    // Handle notifications while app is in foreground (optional: show banner or system alert)
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show banner/sound in foreground as well if desired
        completionHandler([.banner, .sound])
    }
}

// Ensure the coordinator is initialized early by referencing it from module load time
let _notificationsCoordinatorBootstrap: Void = {
    _ = NotificationsCoordinator.shared
}()
