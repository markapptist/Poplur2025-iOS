import Foundation
import UIKit
import WebKit

/// Reads the phone's own thermal state instead of asking whether it feels hot.
///
/// Every "is it cooler now?" this session has been answered by hand, which made
/// each change a guess: the web probe reports the WebView's main thread and is
/// blind to native audio, camera, sensors and GPU, and headless Chrome is not
/// WebKit. iOS publishes the real answer — `ProcessInfo.thermalState` is the
/// same signal the OS uses to decide when to start throttling.
///
///   nominal  — idle/cool
///   fair     — warm, no throttling yet
///   serious  — the system is already reducing performance
///   critical — aggressive throttling; the device is too hot
///
/// A change is reported the instant it happens (that is the useful event — it
/// names what you were doing when the phone crossed a line) and the current
/// state is sampled periodically so a steady reading is on record too.
///
/// It also reports the native work the web probe cannot see, so a hot reading
/// can be attributed rather than guessed at.
@MainActor
enum PoplurThermalProbe {
    private static var started = false
    private static var lastState: ProcessInfo.ThermalState?

    static func start() {
        guard !started else { return }
        started = true

        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in report(reason: "CHANGED") }
        }

        Timer.scheduledTimer(withTimeInterval: 20.0, repeats: true) { _ in
            Task { @MainActor in report(reason: "sample") }
        }
        report(reason: "start")
    }

    private static func name(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "SERIOUS(throttling)"
        case .critical: return "CRITICAL(throttling hard)"
        @unknown default: return "unknown"
        }
    }

    /// Give each newly-created Home/Map document the current ceiling. Thermal
    /// transitions can happen before WKWebView finishes loading, so relying on
    /// the change notification alone leaves a fresh map assuming full quality
    /// while the OS is already throttling it.
    static func sendCurrent(to webView: WKWebView) {
        sendToWeb(ProcessInfo.processInfo.thermalState, webView: webView)
    }

    private static func sendToWeb(_ state: ProcessInfo.ThermalState, webView: WKWebView) {
        let value: String
        switch state {
        case .nominal: value = "nominal"
        case .fair: value = "fair"
        case .serious: value = "serious"
        case .critical: value = "critical"
        @unknown default: value = "unknown"
        }
        webView.evaluateJavaScript(
            "window.dispatchEvent(new CustomEvent('poplur-native-thermal', { detail: { state: '\(value)' } })); true;"
        )
    }

    private static func report(reason: String) {
        let info = ProcessInfo.processInfo
        let state = info.thermalState
        // A steady sample that has not moved is noise; a transition is the
        // signal. Always print transitions, and keep periodic samples too so a
        // long flat run is still on the record.
        let moved = lastState != state
        lastState = state

        let line = "[PoplurThermal] \(name(state))"
            + (moved && reason != "start" ? " <-- CHANGED" : "")
            + " lowPower=\(info.isLowPowerModeEnabled)"
            + " battery=\(Int(UIDevice.current.batteryLevel * 100))%"
            + " charging=\(UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full)"
            + " uptime=\(Int(info.systemUptime))s reason=\(reason)"
        print(line)
        PoplurDiagLog.append(line)
        if let webView = PostLoginHomeWebView.liveWebView {
            sendToWeb(state, webView: webView)
        }
    }
}
