import SwiftUI
import FirebaseCore
import AVFoundation

// AppDelegate: configure SDKs
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        return true
    }
}

// Optional: only needed if you explicitly configured a SceneDelegate in Info.plist.
// If you do not reference this class in UIApplicationSceneManifest, you can delete it.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    // No Snapchat URL handling anymore
}

@main
struct Poplur2025App: App {
    // Attach AppDelegate to SwiftUI lifecycle
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var auth = AuthViewModel()

    // Prewarmed, shared camera controller for fast camera bring-up
    @StateObject private var cameraController = CameraKitController()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                if auth.isAuthenticated {
                    // Inject the shared, prewarmed controller into HomeView
                    HomeView(cameraController: cameraController)
                        .environmentObject(auth)
                        // Prewarm the camera as soon as the app is up
                        .task {
                            await prewarmCameraIfAllowed()
                        }
                } else {
                    WelcomeView()
                        .environmentObject(auth)
                        // Optionally prewarm camera even on welcome to avoid later delay
                        .task {
                            await prewarmCameraIfAllowed()
                        }
                }
            }
            .onAppear {
                // Apply tab bar appearance once at app launch (not per-HomeView init)
                let appearance = UITabBarAppearance()
                appearance.configureWithTransparentBackground()
                appearance.backgroundEffect = nil
                appearance.backgroundColor = .clear
                UITabBar.appearance().standardAppearance = appearance
                if #available(iOS 15.0, *) {
                    UITabBar.appearance().scrollEdgeAppearance = appearance
                }
                UITabBar.appearance().isTranslucent = true
            }
            // If you present CameraKitView somewhere, inject the prewarmed controller:
            // CameraKitView(controller: cameraController, coordinate: ...)
            // Pass `cameraController` down to the presenter as needed (via environment or init).
        }
    }

    // MARK: - Camera prewarm

    private func prewarmCameraIfAllowed() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            await cameraController.start()
        case .notDetermined:
            let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .video) { ok in
                    cont.resume(returning: ok)
                }
            }
            if granted {
                await cameraController.start()
            }
        case .denied, .restricted:
            // Respect user choice; you can prompt to open Settings elsewhere.
            break
        @unknown default:
            break
        }
    }
}
