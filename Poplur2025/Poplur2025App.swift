//
//  Poplur2025App.swift
//  Poplur2025
//
//  Created by Apptist Inc. on 2025-08-03.
//

import SwiftUI
import FirebaseCore
import FirebaseAuth

class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()
    return true
  }
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = false
    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        isAuthenticated = Auth.auth().currentUser != nil
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            // Ensure mutation happens on the main actor
            Task { @MainActor in
                let authed = (user != nil)
                print("Auth state changed. User:", user?.uid ?? "nil", " -> isAuthenticated:", authed)
                self?.isAuthenticated = authed
            }
        }
    }

    deinit {
        if let handle = handle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }
}

@main
struct MediaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var auth = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if auth.isAuthenticated {
                    HomeView()
                } else {
                    WelcomeView() // Show welcome screen first
                }
            }
            .environmentObject(auth)
            .preferredColorScheme(.light)
        }
    }
}
