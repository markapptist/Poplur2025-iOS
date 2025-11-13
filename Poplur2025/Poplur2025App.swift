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
                    HomeView(cameraController: cameraController)
                        .environmentObject(auth)
                        .task {
                            await prewarmCameraIfAllowed()
                        }
                } else {
                    WelcomeView()
                        .environmentObject(auth)
                        .task {
                            await prewarmCameraIfAllowed()
                        }
                }
            }
            .onAppear {
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
        }
    }

    // MARK: - Camera + Microphone prewarm

    private func prewarmCameraIfAllowed() async {
        // Request camera first
        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        var cameraGranted = (camStatus == .authorized)

        if camStatus == .notDetermined {
            cameraGranted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .video) { ok in
                    cont.resume(returning: ok)
                }
            }
        }

        guard cameraGranted else { return }

        // Request microphone for video recording with audio
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        var micGranted = (micStatus == .authorized)
        if micStatus == .notDetermined {
            micGranted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .audio) { ok in
                    cont.resume(returning: ok)
                }
            }
        }
        // Even if mic is denied, we can still start the camera; recording may be silent.

        await cameraController.start()
    }
}
