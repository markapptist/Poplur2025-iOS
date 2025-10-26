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

  // Keep a weak reference to the window (optional)
  weak var mainWindow: UIWindow?

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()

    // SOLID, NON-TRANSLUCENT TAB BAR
    let tabAppearance = UITabBarAppearance()
    tabAppearance.configureWithOpaqueBackground()
    tabAppearance.backgroundEffect = nil
    tabAppearance.backgroundColor = .systemBackground
    tabAppearance.shadowColor = UIColor.separator

    UITabBar.appearance().standardAppearance = tabAppearance
    if #available(iOS 15.0, *) {
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }
    UITabBar.appearance().isTranslucent = false
    UITabBar.appearance().barTintColor = .systemBackground

    // SOLID, NON-TRANSLUCENT NAV BAR
    let navAppearance = UINavigationBarAppearance()
    navAppearance.configureWithOpaqueBackground()
    navAppearance.backgroundEffect = nil
    navAppearance.backgroundColor = .systemBackground
    navAppearance.shadowColor = UIColor.separator
    navAppearance.titleTextAttributes = [
        .foregroundColor: UIColor.label
    ]
    navAppearance.largeTitleTextAttributes = [
        .foregroundColor: UIColor.label
    ]

    UINavigationBar.appearance().standardAppearance = navAppearance
    UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    UINavigationBar.appearance().compactAppearance = navAppearance
    UINavigationBar.appearance().isTranslucent = false
    UINavigationBar.appearance().barTintColor = .systemBackground

    return true
  }

  // Use SceneDelegate to set a sane, solid background on the window
  func application(_ application: UIApplication,
                   configurationForConnecting connectingSceneSession: UISceneSession,
                   options: UIScene.ConnectionOptions) -> UISceneConfiguration {
      let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
      config.delegateClass = SceneDelegate.self
      return config
  }
}

// Scene delegate: set window background to systemBackground (not clear)
class SceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .systemBackground
        self.window = window

        // Keep a reference in AppDelegate (optional)
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.mainWindow = window
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        window?.backgroundColor = .systemBackground
    }
}

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isAuthenticated: Bool = false
    private var handle: AuthStateDidChangeListenerHandle?

    init() {
        isAuthenticated = Auth.auth().currentUser != nil
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
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
            ZStack {
                // Solid app background
                Color(.systemBackground).ignoresSafeArea()

                NavigationStack {
                    if auth.isAuthenticated {
                        HomeView()
                    } else {
                        WelcomeView()
                    }
                }
                // Use solid nav bar background from appearance
                .toolbarBackground(Color(.systemBackground), for: .navigationBar)
                .toolbar(.visible, for: .navigationBar)
                .background(Color(.systemBackground))
            }
            .environmentObject(auth)
            .preferredColorScheme(.light)
            .background(Color(.systemBackground))
        }
    }
}
