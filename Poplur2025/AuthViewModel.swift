// AuthViewModel.swift
import Foundation
import FirebaseAuth

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var currentUser: User?

    private var authHandle: AuthStateDidChangeListenerHandle?

    init() {
        // Seed initial state
        let user = Auth.auth().currentUser
        self.currentUser = user
        self.isAuthenticated = (user != nil)

        // Listen for subsequent changes
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            self.currentUser = user
            self.isAuthenticated = (user != nil)
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
