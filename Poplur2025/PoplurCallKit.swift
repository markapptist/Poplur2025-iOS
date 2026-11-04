import AVFoundation
import CallKit
import FirebaseAuth
import FirebaseFirestore
import Foundation
import PushKit
import StoreKit
import UIKit

/// Calls that ring a closed or locked iPhone (A7 in .codex/mvp-finish-plan.md,
/// the iPhone half; Android's is IncomingCallNotifier.kt).
///
/// While Poplur is open, PoplurCallSignalling's listener hands the page each
/// incoming call and the page rings it. Suspended, killed or locked, nothing
/// listens. The server's `ringIphoneCalls` (functions/src/callRingApple.ts) then
/// sends a PushKit VoIP push, iOS wakes or launches Poplur in the background,
/// and this reports the call to CallKit, which rings like a phone call, lock
/// screen included.
///
/// Apple's rule for VoIP pushes: every one must be reported to CallKit before
/// the handler finishes, or iOS terminates the app and in time stops
/// delivering them. A push that must not ring (the page is already ringing it,
/// it is for an account not signed in here, it is malformed) is therefore
/// still reported, without a name, and ended at once.
///
/// The call itself still lives in the page (webCall.ts). Answering here holds
/// the answer until Home is ready and in front, then posts `poplurCallAnswer`,
/// the message Android's ringing screen sends. Every call is reported as video:
/// answering a video call on a locked iPhone asks for Face ID and brings the
/// app forward, and the page has to be on screen to use the microphone.
///
/// China: MIIT requires CallKit to be inactive for the China storefront (App
/// Review guideline 5). There, `isAllowedHere` is false: no CXProvider is made
/// and no PushKit registry, so no VoIP push is ever delivered or reported, and
/// any token stored earlier is withdrawn. In-app calls still work through the
/// page while Poplur is open; they just never ring a closed phone.
///
/// Off everywhere for now: `ringsClosedPhones` is false because nothing sends
/// VoIP pushes yet (no APNs key, `ringIphoneCalls` not deployed), and App Review
/// rejected the `voip` background mode with no feature using it (guideline
/// 2.5.4, 3 Nov 2026). To switch on: set it true, restore `voip` under
/// UIBackgroundModes in Info.plist, and send App Review a screen recording.
@MainActor
final class PoplurCallKit: NSObject {
    static let shared = PoplurCallKit()
    /// Posted when a call answered here is waiting for the page.
    static let answerReady = Notification.Name("PoplurCallKitAnswerReady")

    /// The caller gives up after 45 s (webCall.ts OUTGOING_NO_ANSWER_MS).
    private static let ringTimeoutNanoseconds: UInt64 = 45_000_000_000
    // Read by forgetTokenBeforeSignOut, which runs off the main actor.
    nonisolated private static let tokenKey = "poplur.callKit.voipToken"

    /// What the page needs to join an answered call (HomeTwin's poplurCallAnswer).
    struct IncomingCall {
        let callId: String
        let calleeId: String
        let callerId: String
        let callerName: String
        let video: Bool
        let context: String

        init?(_ payload: [AnyHashable: Any]) {
            func text(_ key: String, _ max: Int) -> String {
                ((payload[key] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(max).description
            }
            guard (payload["kind"] as? String) == "incoming_call" else { return nil }
            callId = text("callId", 128)
            calleeId = text("calleeId", 128)
            callerId = text("callerId", 128)
            guard !callId.isEmpty, !calleeId.isEmpty, !callerId.isEmpty, calleeId != callerId else { return nil }
            callerName = text("callerName", 80).isEmpty ? "Someone" : text("callerName", 80)
            video = (payload["video"] as? String) == "true"
            context = text("context", 40).isEmpty ? "default" : text("context", 40)
        }
    }

    private enum Phase { case ringing, answered }

    private struct Presented {
        let call: IncomingCall
        var phase: Phase
        var watcher: ListenerRegistration?
        var timeout: Task<Void, Never>?
    }

    /// Nil where CallKit must stay off (see `isAllowedHere`).
    private let provider: CXProvider?
    private var registry: PKPushRegistry?
    private var calls: [UUID: Presented] = [:]
    private var pendingAnswer: IncomingCall?

    nonisolated private static let ringsClosedPhones = false

    /// False for the mainland China storefront, or a mainland China region
    /// when the storefront is not known yet. Decided once per launch.
    nonisolated static let isAllowedHere: Bool = {
        guard ringsClosedPhones else { return false }
        if let country = SKPaymentQueue.default().storefront?.countryCode {
            return country.uppercased() != "CHN"
        }
        return Locale.current.region?.identifier.uppercased() != "CN"
    }()

    private override init() {
        guard Self.isAllowedHere else {
            provider = nil
            super.init()
            return
        }
        let configuration = CXProviderConfiguration()
        configuration.supportsVideo = true
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        // A Poplur call is not a phone number: keep it out of the Phone app's Recents.
        configuration.includesCallsInRecents = false
        let provider = CXProvider(configuration: configuration)
        self.provider = provider
        super.init()
        provider.setDelegate(self, queue: nil)
    }

    /// At every launch, from didFinishLaunching: a VoIP push that woke a killed
    /// Poplur is delivered only once a registry with a delegate exists.
    func start() {
        guard Self.isAllowedHere else {
            // A token saved before (another storefront) must not ring this phone.
            Self.forgetTokenBeforeSignOut()
            UserDefaults.standard.removeObject(forKey: Self.tokenKey)
            return
        }
        guard registry == nil else { return }
        let registry = PKPushRegistry(queue: .main)
        registry.delegate = self
        registry.desiredPushTypes = [.voIP]
        self.registry = registry
    }

    /// True while CallKit shows this call, so the page does not ring it too.
    func isPresenting(_ callId: String) -> Bool {
        calls.values.contains { $0.call.callId == callId }
    }

    /// The answered call, once; nil when nothing waits. Home takes it when ready.
    func takePendingAnswer() -> IncomingCall? {
        guard let call = pendingAnswer else { return nil }
        pendingAnswer = nil
        // The call screen said "open Poplur"; Poplur is open now.
        if let uuid = calls.first(where: { $0.value.call.callId == call.callId })?.key {
            let update = CXCallUpdate()
            update.localizedCallerName = call.callerName
            provider?.reportCall(with: uuid, updated: update)
        }
        return call
    }

    /// The page ended or declined a call: take CallKit's screen down with it.
    func pageEnded(_ callId: String) {
        guard let uuid = calls.first(where: { $0.value.call.callId == callId })?.key else { return }
        end(uuid, reason: .remoteEnded)
    }

    // MARK: - Token

    /// Writes this phone's VoIP token to the signed-in user. Called when the
    /// token arrives and whenever someone signs in.
    func syncTokenForCurrentUser() {
        guard Self.isAllowedHere, let token = UserDefaults.standard.string(forKey: Self.tokenKey),
              let uid = Auth.auth().currentUser?.uid else { return }
        let environment = Self.apnsEnvironment
        // merge:true keeps the user's other fields and other phones' tokens.
        Firestore.firestore().collection("users").document(uid).setData([
            "voipTokens": [
                token: ["env": environment, "updatedAt": FieldValue.serverTimestamp()]
            ]
        ], merge: true) { error in
            if let error {
                PoplurDiagLog.append("[PoplurCallKit] VoIP token write failed: \(error.localizedDescription)")
            } else {
                PoplurDiagLog.append("[PoplurCallKit] VoIP token \(token.prefix(12))… (\(environment)) registered for \(uid)")
            }
        }
    }

    /// Before signing out, while the credentials still allow it, so the next
    /// account on this phone is not rung for this one. Best effort: a push for
    /// an account no longer signed in is dropped on arrival anyway.
    nonisolated static func forgetTokenBeforeSignOut() {
        guard let token = UserDefaults.standard.string(forKey: tokenKey),
              let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore().collection("users").document(uid)
            .updateData(["voipTokens.\(token)": FieldValue.delete()]) { _ in }
    }

    /// Which APNs a token belongs to. App Store and TestFlight builds carry no
    /// provisioning profile and use production; a development-signed install
    /// says so in its embedded profile, and its tokens work only on the sandbox.
    static let apnsEnvironment: String = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>", range: start.upperBound..<text.endIndex),
              let plistData = String(text[start.lowerBound..<end.upperBound]).data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let environment = entitlements["aps-environment"] as? String
        else { return "production" }
        return environment == "development" ? "development" : "production"
    }()

    // MARK: - Ringing

    private func receive(_ payload: [AnyHashable: Any], completion: @escaping () -> Void) {
        // No registry is made where CallKit is off, so this is never reached there.
        guard let provider else {
            completion()
            return
        }
        let uuid = UUID()
        let update = CXCallUpdate()
        update.hasVideo = true
        update.supportsHolding = false
        update.supportsGrouping = false
        update.supportsUngrouping = false
        update.supportsDTMF = false

        guard let call = IncomingCall(payload), shouldRing(call) else {
            // Reported to satisfy iOS, never shown with a name, ended at once.
            update.remoteHandle = CXHandle(type: .generic, value: "poplur")
            update.localizedCallerName = "Poplur"
            let pageRings = IncomingCall(payload).map { PoplurCallSignalling.shared.pageIsRinging($0.callId) } ?? false
            provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] _ in
                Task { @MainActor in
                    self?.provider?.reportCall(with: uuid, endedAt: nil, reason: pageRings ? .answeredElsewhere : .remoteEnded)
                    completion()
                }
            }
            return
        }

        update.remoteHandle = CXHandle(type: .generic, value: call.callerId)
        update.localizedCallerName = call.callerName
        calls[uuid] = Presented(call: call, phase: .ringing)
        provider.reportNewIncomingCall(with: uuid, update: update) { [weak self] error in
            Task { @MainActor in
                if let error {
                    // Do Not Disturb, a call already up, or CallKit refusing it.
                    PoplurDiagLog.append("[PoplurCallKit] CallKit did not ring \(call.callId): \(error.localizedDescription)")
                    self?.drop(uuid)
                } else {
                    self?.watch(uuid)
                }
                completion()
            }
        }
    }

    /// Ring only a well-formed call for the account signed in here, that the
    /// page is not already ringing. With Home open and listening, the page's
    /// own listener rings it; this push then only has to be reported.
    private func shouldRing(_ call: IncomingCall) -> Bool {
        guard Auth.auth().currentUser?.uid == call.calleeId else { return false }
        guard !isPresenting(call.callId) else { return false }
        let signalling = PoplurCallSignalling.shared
        if signalling.pageIsRinging(call.callId) { return false }
        if UIApplication.shared.applicationState == .active && signalling.isWatchingIncoming { return false }
        return true
    }

    /// While it rings, the call document says when to stop: the caller hung up
    /// or gave up, or it was answered or declined on another device.
    private func watch(_ uuid: UUID) {
        guard var presented = calls[uuid] else { return }
        let callId = presented.call.callId
        presented.watcher = Firestore.firestore().collection("calls").document(callId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in self?.callChanged(uuid, snapshot: snapshot, failed: error != nil) }
            }
        presented.timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.ringTimeoutNanoseconds)
            guard !Task.isCancelled, self?.calls[uuid]?.phase == .ringing else { return }
            self?.end(uuid, reason: .unanswered)
        }
        calls[uuid] = presented
    }

    private func callChanged(_ uuid: UUID, snapshot: DocumentSnapshot?, failed: Bool) {
        guard let presented = calls[uuid], !failed else { return }
        guard let data = snapshot?.data() else {
            end(uuid, reason: .remoteEnded)
            return
        }
        switch data["status"] as? String {
        case "ringing":
            return
        case "connected":
            if presented.phase == .ringing { end(uuid, reason: .answeredElsewhere) }
        case "declined":
            end(uuid, reason: presented.phase == .ringing ? .declinedElsewhere : .remoteEnded)
        default:
            end(uuid, reason: .remoteEnded)
        }
    }

    private func end(_ uuid: UUID, reason: CXCallEndedReason) {
        guard calls[uuid] != nil else { return }
        drop(uuid)
        provider?.reportCall(with: uuid, endedAt: nil, reason: reason)
    }

    private func drop(_ uuid: UUID) {
        guard let presented = calls.removeValue(forKey: uuid) else { return }
        presented.watcher?.remove()
        presented.timeout?.cancel()
        if pendingAnswer?.callId == presented.call.callId { pendingAnswer = nil }
    }
}

// MARK: - PushKit

// Both delegates are called on the main queue (PKPushRegistry(queue: .main),
// setDelegate(_:queue: nil)), so the main-actor isolation holds and is asserted.
extension PoplurCallKit: @preconcurrency PKPushRegistryDelegate {
    func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
        guard type == .voIP else { return }
        let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
        syncTokenForCurrentUser()
    }

    func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
        guard type == .voIP else { return }
        Self.forgetTokenBeforeSignOut()
        UserDefaults.standard.removeObject(forKey: Self.tokenKey)
    }

    func pushRegistry(
        _ registry: PKPushRegistry,
        didReceiveIncomingPushWith payload: PKPushPayload,
        for type: PKPushType,
        completion: @escaping () -> Void
    ) {
        guard type == .voIP else {
            completion()
            return
        }
        receive(payload.dictionaryPayload, completion: completion)
    }
}

// MARK: - CallKit

extension PoplurCallKit: @preconcurrency CXProviderDelegate {
    func providerDidReset(_ provider: CXProvider) {
        Array(calls.keys).forEach(drop)
        pendingAnswer = nil
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard var presented = calls[action.callUUID], presented.phase == .ringing else {
            action.fail()
            return
        }
        presented.phase = .answered
        presented.timeout?.cancel()
        presented.timeout = nil
        calls[action.callUUID] = presented
        // CallKit activates the session it is handed; the page's WebRTC needs
        // to record as well as play.
        try? AVAudioSession.sharedInstance().setCategory(
            .playAndRecord, mode: .default, options: [.allowBluetoothHFP, .defaultToSpeaker]
        )
        pendingAnswer = presented.call
        action.fulfill()
        if UIApplication.shared.applicationState != .active {
            // Answered from the lock screen or a banner: the call connects once
            // Poplur is in front, so the call screen says where to go.
            let update = CXCallUpdate()
            update.localizedCallerName = "\(presented.call.callerName) · open Poplur"
            provider.reportCall(with: action.callUUID, updated: update)
        }
        NotificationCenter.default.post(name: Self.answerReady, object: nil)
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        guard let presented = calls[action.callUUID] else {
            action.fulfill()
            return
        }
        drop(action.callUUID)
        action.fulfill()
        let callId = presented.call.callId
        if presented.phase == .ringing {
            Task { @MainActor in await PoplurCallSignalling.shared.declineCall(callId) }
        } else {
            // Hung up on the iPhone's call screen: end it for both sides, and tell
            // the page, which hears nothing from a call it ended itself.
            PoplurCallSignalling.shared.onEvent?(["type": "poplurCallEnded", "callId": callId, "reason": "ended"])
            Task { @MainActor in await PoplurCallSignalling.shared.endCall(callId) }
        }
    }

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {}

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {}
}
