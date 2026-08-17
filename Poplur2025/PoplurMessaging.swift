import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseMessaging
import UIKit

/// Phase 1 of engagement push notifications on iOS: get this device a token and
/// keep it on the user's document. Nothing here sends or displays anything — the
/// sender is a Firestore trigger (phase 3) and display lands in phase 4.
///
/// Schema matches Android exactly, so one Cloud Function serves both:
///
///     users/{uid}.fcmTokens = { "<token>": { platform: "ios", updatedAt: <ts> } }
///
/// Keyed by token rather than an array so a token FCM reports unregistered can be
/// deleted with `FieldValue.delete()` — no read, and no two-devices-clobber race.
///
/// ## This does not make iOS delivery work on its own
/// An **APNs authentication key (.p8) must be created in the Apple Developer
/// account and uploaded to the Firebase console** (Cloud Messaging → iOS app
/// configuration). Until then this registers tokens perfectly and every send
/// fails silently, which is a genuinely misleading state to debug — hence the
/// explicit log below when a token is obtained without one.
@MainActor
final class PoplurMessaging: NSObject, MessagingDelegate {
    static let shared = PoplurMessaging()

    private override init() { super.init() }

    /// Wires the FCM delegate and asks iOS for an APNs token.
    ///
    /// Deliberately does NOT request notification authorization. That ask belongs
    /// to the clay primer card via
    /// `PoplurPermissionRouting.requestNotificationsAfterPrimer()` — the comment
    /// in Notifications+Names.swift is explicit that Apple's sheet must never
    /// appear off a background path with no Poplur card in front of it.
    /// `registerForRemoteNotifications()` itself shows no UI, so it is safe here:
    /// it yields an APNs token, while whether a banner may be DISPLAYED stays
    /// governed by the authorization the primer obtains.
    func start() {
        guard FirebaseApp.app() != nil else {
            PoplurDiagLog.append("[PoplurMessaging] start skipped — Firebase not configured")
            return
        }
        Messaging.messaging().delegate = self
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// Writes the current token to the signed-in user, if there is one.
    ///
    /// Safe to call repeatedly. Resolves the token itself so callers need not care
    /// whether `messaging(_:didReceiveRegistrationToken:)` has already fired —
    /// which matters because on a fresh install the token arrives BEFORE sign-in,
    /// and that ordering is exactly how a device ends up registered to nobody.
    func syncTokenForCurrentUser() {
        guard FirebaseApp.app() != nil else { return }
        guard Auth.auth().currentUser?.uid != nil else {
            // Not an error: expected on a fresh install. Called again after sign-in.
            PoplurDiagLog.append("[PoplurMessaging] no signed-in user yet — deferring token write")
            return
        }
        guard Messaging.messaging().apnsToken != nil else {
            // Expected, not a fault: the auth listener can run before iOS has
            // handed us an APNs token, and FCM will not mint a token without one.
            // didRegisterForRemoteNotificationsWithDeviceToken calls back here as
            // soon as it arrives, so this is a wait rather than a failure — it
            // used to surface as an alarming "could not get FCM token" on every
            // single launch.
            PoplurDiagLog.append("[PoplurMessaging] waiting for APNs token before requesting an FCM token")
            return
        }
        Messaging.messaging().token { [weak self] token, error in
            if let error {
                PoplurDiagLog.append("[PoplurMessaging] could not get FCM token: \(error.localizedDescription)")
                return
            }
            guard let token, !token.isEmpty else {
                PoplurDiagLog.append("[PoplurMessaging] FCM returned an empty token")
                return
            }
            Task { @MainActor in self?.write(token: token) }
        }
    }

    private func write(token: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        // merge:true — the user document also holds profilePictureURL and
        // profileSelfieVideoURL, so a plain setData would delete the profile.
        Firestore.firestore().collection("users").document(uid).setData([
            "fcmTokens": [
                token: [
                    "platform": "ios",
                    "updatedAt": FieldValue.serverTimestamp()
                ]
            ]
        ], merge: true) { error in
            if let error {
                PoplurDiagLog.append("[PoplurMessaging] token write failed: \(error.localizedDescription)")
            } else {
                PoplurDiagLog.append("[PoplurMessaging] registered token \(token.prefix(12))… for \(uid)")
            }
        }
    }

    // MARK: - MessagingDelegate

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        // FCM rotates tokens on reinstall and restore-to-new-device, so this must
        // write through rather than treat the first registration as permanent.
        guard let fcmToken, !fcmToken.isEmpty else { return }
        if Messaging.messaging().apnsToken == nil {
            // The state worth naming: an FCM token exists, but without an APNs
            // token underneath it nothing can be delivered. Usually means the
            // Push Notifications capability or the APNs .p8 key is missing.
            PoplurDiagLog.append("[PoplurMessaging] FCM token but NO APNs token — delivery will fail (check aps-environment + APNs key in Firebase)")
        }
        Task { @MainActor in
            guard Auth.auth().currentUser?.uid != nil else {
                PoplurDiagLog.append("[PoplurMessaging] token arrived before sign-in — will sync after")
                return
            }
            self.write(token: fcmToken)
        }
    }
}
