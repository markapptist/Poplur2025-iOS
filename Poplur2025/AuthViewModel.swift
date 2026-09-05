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
        #if DEBUG
        // UI-test only: render the real signed-out flow deterministically without mutating the
        // simulator's persisted Firebase session. This keeps performance tests on the requested
        // Welcome/Login/Sign Up screens even when a developer is signed in locally.
        if ProcessInfo.processInfo.arguments.contains("-UITestForceSignedOut") {
            self.currentUser = nil
            self.authHandle = nil
            self.isAuthenticated = false
            self.isResolvingAuthState = false
            return
        }

        // UI-test only: skip real Firebase sign-in entirely so screenshot/navigation tests don't
        // depend on account creation succeeding (avoids signup flakiness and the HomeView-eager-
        // construction race in CallSessionManager). Never reachable in a release build.
        if ProcessInfo.processInfo.arguments.contains("-UITestAuthBypass") {
            self.currentUser = nil
            self.authHandle = nil
            // Wait for FirebaseApp.configure() (runs elsewhere at launch) to actually finish before
            // flipping to signed-in — otherwise authenticatedContent mounts early and crashes on
            // unguarded Auth.auth() calls. Deterministic poll, not a fixed sleep.
            Task { @MainActor in
                for _ in 0..<100 where FirebaseApp.app() == nil {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                self.isAuthenticated = true
                self.isResolvingAuthState = false
            }
            return
        }
        #endif
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
                // FCM issues this device's token independently of auth, and on a
                // fresh install it lands FIRST — so the delegate has no uid to
                // attach it to and skips the write. Re-syncing here is what stops
                // the device from staying registered to nobody. This listener
                // also fires once immediately, so a cached session is covered.
                if user != nil { PoplurMessaging.shared.syncTokenForCurrentUser() }
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
            PoplurNativeAnalytics.didSignOut()
        } catch {
            print("AuthViewModel: signOut failed -> \(error.localizedDescription)")
        }
    }
}
