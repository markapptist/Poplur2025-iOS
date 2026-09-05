import FirebaseAnalytics
import Foundation
import StoreKit

/// Firebase Analytics for the iOS shell.
///
/// Ownership is split exactly once. The WEB page (poplur-clay-map) is the
/// source of `screen_view` and every in-app action event; it posts them over
/// the `poplur` bridge as `{type:"analyticsEvent", name, params}` and
/// `{type:"analyticsUserProperty", name, value}`, and this relay re-validates
/// them before handing them to the SDK. Native owns only `login`, `sign_up`
/// (`PoplurNativeAnalytics` below) plus the SDK's automatic events — including
/// `in_app_purchase`, which GoogleAppMeasurement collects itself from the
/// payment queue (StoreKit 2 purchases reach StoreKit 1 observers too), so no
/// manual `purchase` is logged here: one owner, no doubled revenue.
/// lifecycle events. Automatic screen reporting is OFF in Info.plist
/// (`FirebaseAutomaticScreenReportingEnabled = NO`), so nothing is logged from
/// two places.
enum PoplurAnalyticsRelay {
    static let eventType = "analyticsEvent"
    static let userPropertyType = "analyticsUserProperty"

    // GA4 collection limits. The page sanitises too; the shell never trusts it.
    private static let maxEventNameLength = 40
    private static let maxParamNameLength = 40
    private static let maxParamCount = 25
    private static let maxParamStringLength = 100
    private static let maxUserPropertyNameLength = 24
    private static let maxUserPropertyValueLength = 36
    private static let reservedPrefixes = ["firebase_", "google_", "ga_"]

    /// Names the SDK emits itself or rejects, plus the three native-owned
    /// events the page must never log a second time. `screen_view` is NOT
    /// here: the page is its single owner.
    private static let reservedEventNames: Set<String> = [
        "ad_activeview", "ad_click", "ad_exposure", "ad_query", "ad_reward",
        "adunit_exposure", "app_background", "app_clear_data", "app_exception",
        "app_remove", "app_store_refund", "app_store_subscription_cancel",
        "app_store_subscription_convert", "app_store_subscription_renew",
        "app_update", "app_upgrade", "dynamic_link_app_open",
        "dynamic_link_app_update", "dynamic_link_first_open", "error",
        "first_open", "first_visit", "in_app_purchase", "notification_dismiss",
        "notification_foreground", "notification_open", "notification_receive",
        "os_update", "session_start", "session_start_with_rollout",
        "user_engagement",
        "login", "sign_up", "purchase",
    ]

    private static let reservedUserPropertyNames: Set<String> = [
        "first_open_time", "first_visit_time", "last_deep_link_referrer",
        "user_id", "first_open_after_install", "lifetime_user_engagement",
        "session_number", "session_id", "non_personalized_ads",
    ]

    /// Parameter keys that could only ever carry content or identity. The
    /// taxonomy never uses them, so refusing them keeps a future page bug from
    /// shipping a post id, user id, handle, caption, coordinate, media URL or
    /// message text into Analytics.
    private static let forbiddenParamNames: Set<String> = [
        "id", "post_id", "postid", "pop_id", "popid", "user_id", "userid", "uid",
        "handle", "username", "user_name", "display_name", "email", "phone",
        "caption", "text", "message", "body", "title", "comment", "content",
        "lat", "lng", "lon", "latitude", "longitude", "coords", "location",
        "url", "uri", "media_url", "mediaurl", "playback_url", "thumbnail",
        "other_id", "otherid", "thread_id", "threadid", "client_message_id",
    ]

    static func handles(_ type: String) -> Bool {
        type == eventType || type == userPropertyType
    }

    /// Entry point from the `poplur` message dispatch. `body` is the raw
    /// WKScriptMessage dictionary; anything that fails validation is dropped
    /// here rather than left for the SDK to silently discard.
    static func handle(type: String, body: [String: Any]) {
        switch type {
        case eventType:
            guard let name = validName(body["name"], maxLength: maxEventNameLength),
                  !reservedEventNames.contains(name) else {
                return reject("event", body["name"])
            }
            Analytics.logEvent(name, parameters: sanitizedParams(body["params"]))
        case userPropertyType:
            guard let name = validName(body["name"], maxLength: maxUserPropertyNameLength),
                  !reservedUserPropertyNames.contains(name) else {
                return reject("user property", body["name"])
            }
            let value = scalar(body["value"], maxStringLength: maxUserPropertyValueLength)
                .map { "\($0)" }
            Analytics.setUserProperty(value, forName: name)
        default:
            break
        }
    }

    // MARK: - Validation

    /// `/^[a-z][a-z0-9_]{0,maxLength-1}$/` and no reserved prefix.
    private static func validName(_ raw: Any?, maxLength: Int) -> String? {
        guard let name = raw as? String,
              !name.isEmpty,
              name.count <= maxLength else { return nil }
        for (index, scalar) in name.unicodeScalars.enumerated() {
            let value = scalar.value
            let lower = value >= 0x61 && value <= 0x7A
            let digit = value >= 0x30 && value <= 0x39
            let underscore = value == 0x5F
            if index == 0 {
                guard lower else { return nil }
            } else {
                guard lower || digit || underscore else { return nil }
            }
        }
        for prefix in reservedPrefixes where name.hasPrefix(prefix) {
            return nil
        }
        return name
    }

    private static func sanitizedParams(_ raw: Any?) -> [String: Any]? {
        guard let raw = raw as? [String: Any], !raw.isEmpty else { return nil }
        var params: [String: Any] = [:]
        for key in raw.keys.sorted() {
            guard params.count < maxParamCount else { break }
            guard let name = validName(key, maxLength: maxParamNameLength),
                  !forbiddenParamNames.contains(name),
                  let value = scalar(raw[key], maxStringLength: maxParamStringLength) else {
                continue
            }
            params[name] = value
        }
        return params.isEmpty ? nil : params
    }

    /// JSON -> the two value types Analytics accepts. Booleans become "1"/"0",
    /// finite numbers pass through as NSNumber, strings are truncated, and
    /// anything else (null, arrays, objects, URLs) is dropped.
    private static func scalar(_ raw: Any?, maxStringLength: Int) -> Any? {
        guard let raw, !(raw is NSNull) else { return nil }
        if let number = raw as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "1" : "0"
            }
            guard number.doubleValue.isFinite else { return nil }
            return number
        }
        if let string = raw as? String {
            guard !string.contains("://") else { return nil }
            return String(string.prefix(maxStringLength))
        }
        return nil
    }

    private static func reject(_ what: String, _ raw: Any?) {
        #if DEBUG
        print("[PoplurAnalyticsRelay] dropped \(what) \(String(describing: raw))")
        #endif
    }
}

/// The two events native owns (login, sign_up) and the identity that goes
/// with them. Purchases are the SDK's own `in_app_purchase`; everything
/// else is the page's.
enum PoplurNativeAnalytics {
    static func didLogin(uid: String?) {
        Analytics.setUserID(uid)
        Analytics.logEvent(AnalyticsEventLogin, parameters: [AnalyticsParameterMethod: "password"])
    }

    static func didSignUp(uid: String?) {
        Analytics.setUserID(uid)
        Analytics.logEvent(AnalyticsEventSignUp, parameters: [AnalyticsParameterMethod: "password"])
    }

    static func didSignOut() {
        Analytics.setUserID(nil)
    }
}
