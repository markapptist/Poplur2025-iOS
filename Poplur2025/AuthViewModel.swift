// AuthViewModel.swift
import Foundation
import FirebaseCore
import FirebaseAuth

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: User?
    /// True while Firebase is still resolving the persisted auth token.
    /// Used to show a neutral splash instead of flashing WelcomeView for returning users.
    @Published var isResolvingAuthState: Bool = true
    /// Set to true by SignUpView on successful account creation. Consumed once by the
    /// app-level transition to play the stripe (not the loading video).
    @Published var didSignUp: Bool = false

    private var authHandle: AuthStateDidChangeListenerHandle?

    init() {
        guard FirebaseApp.app() != nil else {
            print("AuthViewModel: Firebase is not configured yet; starting signed out.")
            isResolvingAuthState = false
            return
        }

        // Optimistically seed from the cached user so returning users go straight to HomeView
        // (Firebase may still need a network round-trip to validate the token).
        let user = Auth.auth().currentUser
        self.currentUser = user
        self.isAuthenticated = (user != nil)

        // Listen for auth state changes (also fires once immediately to confirm cached state).
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                self.currentUser = user
                self.isAuthenticated = (user != nil)
                self.isResolvingAuthState = false
            }
        }
    }

    #if DEBUG
    init(previewAuthenticated: Bool) {
        self.currentUser = nil
        self.isAuthenticated = previewAuthenticated
        self.authHandle = nil
    }
    #endif

    deinit {
        if let handle = authHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            print("AuthViewModel: signOut failed -> \(error.localizedDescription)")
        }
    }
}
