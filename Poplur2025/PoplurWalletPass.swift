import SwiftUI
import PassKit
import FirebaseFunctions

/// "Add to Apple Wallet" for a Poplur card the signed-in user owns.
///
/// The pass is built and SIGNED SERVER-SIDE (`poplurWalletPass`). The Pass Type
/// ID private key must never ship in the app binary — anyone with it can mint
/// passes that look like ours — so the client's whole job is: ask, receive
/// bytes, hand them to PassKit.
@MainActor
final class PoplurWalletPassService: ObservableObject {
    enum State: Equatable {
        case idle
        case working
        /// Carries a message worth showing. The server distinguishes "not
        /// configured yet" from "you do not own that card"; both are useful and
        /// neither should surface as a generic failure.
        case failed(String)
    }

    /// One instance, because the caller is now the WEB BRIDGE rather than a
    /// SwiftUI view that owns its own object. The bridge has no view lifetime
    /// to hang this on.
    static let shared = PoplurWalletPassService()

    /// What the bridge reports back to the page.
    enum Outcome: Equatable {
        case added
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// nil until asked. Distinguishes "not loaded yet" from "owns nothing", so
    /// the button does not flash in and out while the answer is in flight.
    @Published private(set) var ownedCardIDs: Set<String>?

    private lazy var functions = Functions.functions()

    /// Wallet is not on every device (older iPads, some regions), and the add
    /// sheet cannot be presented where it is absent.
    static var isAvailable: Bool {
        PKAddPassesViewController.canAddPasses()
    }

    /// The client cannot read `verifiedStorePurchases` — it is server-only — so
    /// ownership is asked for once and cached. Without it the button had to be
    /// offered on every card and rejected server-side, and a button that fails
    /// is worse than no button.
    func loadOwnedCards() async {
        guard ownedCardIDs == nil else { return }
        do {
            let result = try await functions.httpsCallable("poplurOwnedCards").call()
            let ids = (result.data as? [String: Any])?["cardIds"] as? [String] ?? []
            ownedCardIDs = Set(ids)
        } catch {
            // A failed lookup must not strand the feature: fall back to showing
            // the button and letting the server be the gate, which is exactly
            // the old behaviour rather than a regression.
            ownedCardIDs = nil
        }
    }

    /// Whether to offer Wallet for this card. Unknown ownership means "offer
    /// it" — the server still refuses if they do not own it.
    func canOffer(cardID: String) -> Bool {
        guard let owned = ownedCardIDs else { return true }
        return owned.contains(cardID)
    }

    /// Card ids this account owns, asked fresh. The page decides which buttons
    /// to show from this, and the server still re-checks before it signs.
    func ownedCardIDs() async -> [String] {
        do {
            let result = try await functions.httpsCallable("poplurOwnedCards").call()
            let ids = (result.data as? [String: Any])?["cardIds"] as? [String] ?? []
            ownedCardIDs = Set(ids)
            return ids
        } catch {
            return []
        }
    }

    /// Bridge entry point: sign, present Apple's sheet, and report what happened.
    @discardableResult
    func addToWallet(cardID: String) async -> Outcome {
        await performAdd(cardID: cardID)
        if case .failed(let message) = state { return .failed(message) }
        return .added
    }

    private func performAdd(cardID: String) async {
        state = .working
        do {
            let result = try await functions.httpsCallable("poplurWalletPass")
                .call(["cardId": cardID])
            guard
                let payload = result.data as? [String: Any],
                let base64 = payload["pkpass"] as? String,
                let data = Data(base64Encoded: base64)
            else {
                state = .failed("The server did not return a pass.")
                return
            }
            try present(passData: data)
            state = .idle
        } catch let error as NSError {
            // Callable errors arrive wrapped; the server's message is the useful
            // half ("Wallet passes are not configured yet (missing: …)"), so
            // prefer it over the transport's own description.
            let message = (error.userInfo[FunctionsErrorDetailsKey] as? String)
                ?? error.localizedDescription
            state = .failed(message)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func present(passData: Data) throws {
        let pass = try PKPass(data: passData)
        guard let controller = PKAddPassesViewController(pass: pass) else {
            throw PoplurWalletPassError.couldNotPresent
        }
        guard let presenter = Self.topViewController() else {
            throw PoplurWalletPassError.couldNotPresent
        }
        presenter.present(controller, animated: true)
    }

    /// PassKit needs a real presenter and SwiftUI does not hand one over. Walk
    /// the active foreground scene rather than keeping a stored reference that
    /// can outlive its window.
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

enum PoplurWalletPassError: LocalizedError {
    case couldNotPresent

    var errorDescription: String? {
        switch self {
        case .couldNotPresent: return "Wallet could not be opened."
        }
    }
}

/// The button itself. Apple requires its own artwork for "Add to Apple Wallet";
/// `PKAddPassButton` IS that artwork, so this wraps the real control rather
/// than drawing a lookalike — a hand-rolled one is a guideline violation.
struct AddPoplurCardToWalletButton: UIViewRepresentable {
    var action: () -> Void

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: .black)
        button.addTarget(
            context.coordinator,
            action: #selector(Coordinator.tapped),
            for: .touchUpInside
        )
        return button
    }

    func updateUIView(_ uiView: PKAddPassButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}
