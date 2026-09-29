import UIKit
import WebKit
import FirebaseAuth
import FirebaseFunctions

/// Account deletion is reachable from the shipping web Settings, but credentials
/// and the final destructive confirmation stay in the native shell. The dialogs
/// are the house-style PoplurDeletionDialogController (PoplurAccountDeletionDialog.swift).
@MainActor
final class PoplurAccountDeletion {
    static let shared = PoplurAccountDeletion()
    private var presenting = false
    private var pendingResult: (title: String, message: String)?
    private var activationObserver: NSObjectProtocol?

    private init() {
        activationObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.presentPendingResult() }
        }
    }

    func present() {
        guard !presenting, let user = Auth.auth().currentUser,
              let email = user.email, let presenter = Self.presenter else { return }
        presenting = true
        let model = PoplurDeletionDialogModel(phase: .confirm)
        let dialog = PoplurDeletionDialogController(model: model)
        model.onCancel = { [weak self, weak dialog] in
            Task { @MainActor in
                if let dialog { await self?.dismiss(dialog) }
                self?.presenting = false
            }
        }
        model.onConfirm = { [weak self, weak dialog] password in
            guard let self, let dialog else { return }
            Task { @MainActor in await self.delete(user: user, email: email, password: password, dialog: dialog) }
        }
        presenter.present(dialog, animated: true)
    }

    private func delete(user: User, email: String, password: String, dialog: PoplurDeletionDialogController) async {
        let model = dialog.model
        guard !password.isEmpty else {
            model.inlineError = "Enter your password to verify that this is your account."
            return
        }
        // The dialog stays up and turns into its progress state, which blocks
        // settings/session changes while either authentication request is in
        // flight, including a slow token refresh.
        model.inlineError = nil
        model.phase = .working
        do {
            guard Auth.auth().currentUser?.uid == user.uid else { throw DeletionError.accountChanged }
            guard dialog.viewIfLoaded?.window != nil else { throw DeletionError.presentationUnavailable }
            _ = try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: email, password: password))
            guard Auth.auth().currentUser?.uid == user.uid else { throw DeletionError.accountChanged }
            _ = try await user.getIDToken(forcingRefresh: true)
            guard Auth.auth().currentUser?.uid == user.uid else { throw DeletionError.accountChanged }
            let callable = Functions.functions(region: "us-east1").httpsCallable("deleteMyAccount")
            callable.timeoutInterval = 540
            // The server compares this with its authenticated caller. It never
            // uses a client-supplied identity as the deletion target.
            let result = try await callable.call(["confirm": true, "expectedUid": user.uid])
            guard let data = result.data as? [String: Any], data["deleted"] as? Bool == true else {
                throw DeletionError.incomplete
            }
            // A different session must not lose its credentials or local data
            // if it replaced this one while the server request was completing.
            if Auth.auth().currentUser == nil || Auth.auth().currentUser?.uid == user.uid {
                PoplurWebCaptureStore.purge()
                PoplurProfileSelfieStore.remove()
                PoplurKeychain.clearSavedCredentials()
                UserDefaults.standard.removeObject(forKey: NativePreloginDraft.key)
                try? FileManager.default.removeItem(at: NativePreloginDraft.photoURL)
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                try? FileManager.default.removeItem(at: documents.appendingPathComponent("profile.jpg"))
                NotificationCenter.default.post(name: .StopMapAudio, object: nil)
                // Clear embedded per-account caches before another person signs in.
                await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
            }
            await dismiss(dialog)
            // Ending the deleted session cannot depend on a dialog being visible
            // or acknowledged: this can finish while the device is locked.
            if Auth.auth().currentUser?.uid == user.uid {
                NotificationCenter.default.post(name: .PoplurSignOutRequested, object: nil)
            }
            showResult(title: "Account deleted", message: "The Poplur account you confirmed and its personal data have been deleted.")
        } catch {
            let code = (error as NSError).code
            let authError = (error as NSError).domain == AuthErrorDomain
            if authError && [AuthErrorCode.wrongPassword.rawValue, AuthErrorCode.invalidCredential.rawValue].contains(code) {
                // Nothing reached the server: let them try again in place.
                model.inlineError = "That password wasn't accepted. Your account has not been deleted. Try again."
                model.phase = .confirm
                return
            }
            await dismiss(dialog)
            presenting = false
            let message: String
            if error as? DeletionError == .accountChanged {
                message = "The signed-in account changed. Start account deletion again for the account you want to remove."
            } else if error as? DeletionError == .presentationUnavailable {
                message = "Keep Poplur open and try Delete account again. No deletion request was sent."
            } else {
                message = "Deletion could not be confirmed. Some data may already have been removed. Check your connection and retry Delete account to finish."
            }
            showResult(title: "Account deletion", message: message)
        }
    }

    private func dismiss(_ controller: UIViewController) async {
        guard controller.presentingViewController != nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            controller.dismiss(animated: true) { continuation.resume() }
        }
    }

    private func showResult(title: String, message: String) {
        presenting = true
        pendingResult = (title, message)
        // Allow the authentication listener to replace the signed-in surface.
        DispatchQueue.main.async { [weak self] in self?.presentPendingResult() }
    }

    private func presentPendingResult() {
        guard let result = pendingResult, let presenter = Self.presenter else { return }
        guard !presenter.isBeingPresented, !presenter.isBeingDismissed,
              presenter.presentedViewController == nil,
              presenter.viewIfLoaded?.window != nil else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.presentPendingResult() }
            return
        }
        let model = PoplurDeletionDialogModel(phase: .result(title: result.title, message: result.message))
        let dialog = PoplurDeletionDialogController(model: model)
        model.onAcknowledge = { [weak self, weak dialog] in
            Task { @MainActor in
                if let dialog { await self?.dismiss(dialog) }
                self?.presenting = false
            }
        }
        pendingResult = nil
        presenter.present(dialog, animated: true)
    }

    private static var presenter: UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              var controller = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return nil }
        while let next = controller.presentedViewController, !next.isBeingDismissed { controller = next }
        return controller
    }

    private enum DeletionError: Error { case accountChanged, incomplete, presentationUnavailable }
}
