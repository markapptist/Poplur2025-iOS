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

  // Keep a weak reference to the window to set clear background after scene connects (optional)
  weak var mainWindow: UIWindow?

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
    FirebaseApp.configure()

    // Force transparent Tab Bar at UIKit level
    let tabAppearance = UITabBarAppearance()
    tabAppearance.configureWithTransparentBackground()
    tabAppearance.backgroundEffect = nil
    tabAppearance.backgroundColor = .clear

    UITabBar.appearance().standardAppearance = tabAppearance
    if #available(iOS 15.0, *) {
        UITabBar.appearance().scrollEdgeAppearance = tabAppearance
    }
    UITabBar.appearance().isTranslucent = true
    UITabBar.appearance().barTintColor = .clear
    UITabBar.appearance().backgroundImage = UIImage()
    UITabBar.appearance().shadowImage = UIImage()

    // Force transparent Navigation Bar at UIKit level
    let navAppearance = UINavigationBarAppearance()
    navAppearance.configureWithTransparentBackground()
    navAppearance.backgroundEffect = nil
    navAppearance.backgroundColor = .clear
    navAppearance.shadowColor = .clear

    UINavigationBar.appearance().standardAppearance = navAppearance
    UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    UINavigationBar.appearance().compactAppearance = navAppearance
    UINavigationBar.appearance().isTranslucent = true
    UINavigationBar.appearance().setBackgroundImage(UIImage(), for: .default)
    UINavigationBar.appearance().shadowImage = UIImage()
    UINavigationBar.appearance().barTintColor = .clear

    return true
  }

  // Ensure the window is fully transparent by using a SceneDelegate to set backgroundColor = .clear
  func application(_ application: UIApplication,
                   configurationForConnecting connectingSceneSession: UISceneSession,
                   options: UIScene.ConnectionOptions) -> UISceneConfiguration {
      let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
      config.delegateClass = SceneDelegate.self
      return config
  }
}

// Scene delegate to capture the window and set it transparent
class SceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        // Create a window and set global background to clear.
        // SwiftUI will still manage the root content.
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .clear
        self.window = window

        // Keep a reference in AppDelegate (optional)
        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
            appDelegate.mainWindow = window
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Re-assert clear background on re-activation
        window?.backgroundColor = .clear
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
                Color.clear
                NavigationStack {
                    if auth.isAuthenticated {
                        HomeView()
                    } else {
                        WelcomeView()
                    }
                }
                // Transparent navigation bar area at SwiftUI level
                .toolbarBackground(.clear, for: .navigationBar)
                .toolbar(.visible, for: .navigationBar)
                .background(Color.clear)
            }
            .environmentObject(auth)
            .preferredColorScheme(.light)
            .background(Color.clear)
        }
    }
}
