import Foundation
import UserNotifications
import SwiftUI

/// Was a second UNUserNotificationCenterDelegate.
///
/// There can only be one, and this one never won: it claimed the delegate from
/// its init at module load, while PoplurNotificationCenter.configure() assigns
/// it again from didFinishLaunching, which runs later. So the tap handler here
/// was never called and the postFocusRequest it posted never fired — a dead
/// path that read as working notification routing.
///
/// The behaviour now lives in PoplurNotificationCenter, which is the delegate
/// that actually receives callbacks. The name below stays because
/// `.postFocusRequest` is declared here and referenced elsewhere.
enum NotificationsCoordinator {}

extension Notification.Name {
    static let postFocusRequest = Notification.Name("postFocusRequest")
}

// The module-load bootstrap is gone with the class it woke. Claiming the
// delegate early was precisely what made this look wired up while
// PoplurNotificationCenter quietly replaced it a moment later.
