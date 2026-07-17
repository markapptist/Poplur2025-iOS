import SwiftUI
import UIKit

enum PoplurPermissionKind: Equatable {
    case camera
    case location

    var title: String {
        switch self {
        case .camera: return "Allow Poplur to use your camera?"
        case .location: return "Allow Poplur to use your location?"
        }
    }

    var message: String {
        switch self {
        case .camera:
            return "Capture photos and videos to share with people inside your radius."
        case .location:
            return "Your location powers nearby posts, map positioning, and the radius around you."
        }
    }

    var symbolName: String {
        switch self {
        case .camera: return "camera.fill"
        case .location: return "location.fill"
        }
    }
}

enum PoplurPermissionDecision {
    case allow
    case deny
}

struct PoplurPermissionRequest: Identifiable {
    let id = UUID()
    let kind: PoplurPermissionKind
    let systemRequestAllowed: Bool
}

@MainActor
final class PoplurPermissionCenter: ObservableObject {
    static let shared = PoplurPermissionCenter()

    @Published private(set) var request: PoplurPermissionRequest?
    private var continuation: CheckedContinuation<PoplurPermissionDecision, Never>?

    func ask(kind: PoplurPermissionKind, systemRequestAllowed: Bool) async -> PoplurPermissionDecision {
        guard request == nil, continuation == nil else { return .deny }
        request = PoplurPermissionRequest(kind: kind, systemRequestAllowed: systemRequestAllowed)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resolve(_ decision: PoplurPermissionDecision) {
        let pending = continuation
        continuation = nil
        request = nil
        pending?.resume(returning: decision)
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
}

struct PermissionOverlay: View {
    let request: PoplurPermissionRequest
    let onAllow: () -> Void
    let onDeny: () -> Void

    var body: some View {
        ZStack {
            Image("slideup_alt1")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.18).ignoresSafeArea())

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 0) {
                    VStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(red: 0.96, green: 0.16, blue: 0.54))
                                .frame(width: 68, height: 52)
                                .shadow(color: Color(red: 0.72, green: 0.05, blue: 0.32).opacity(0.35), radius: 8, y: 5)
                            Image(systemName: request.kind.symbolName)
                                .font(.system(size: 26, weight: .heavy))
                                .foregroundColor(.white)
                                .poplurIconShader()
                        }

                        Text(request.kind.title)
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(red: 0.64, green: 0.14, blue: 0.39))
                            .poplurTextShader(intensity: 0.92, animated: true)

                        Text(request.kind.message)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color(red: 0.74, green: 0.24, blue: 0.51))
                            .lineSpacing(3)
                            .poplurTextShader(intensity: 0.65, animated: true)
                            .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 24)

                    Divider().overlay(Color.black.opacity(0.12))

                    if request.kind == .location && request.systemRequestAllowed {
                        permissionRow("Allow Once", action: onAllow)
                        Divider().overlay(Color.black.opacity(0.12))
                        permissionRow("Allow While Using App", action: onAllow)
                        Divider().overlay(Color.black.opacity(0.12))
                        permissionRow("Don't Allow", action: onDeny)
                    } else {
                        HStack(spacing: 0) {
                            permissionButton("Don't Allow", action: onDeny)
                            Divider().overlay(Color.black.opacity(0.12))
                            permissionButton(request.systemRequestAllowed ? "Allow" : "Open Settings", action: onAllow)
                        }
                        .frame(height: 58)
                    }
                }
                .background(Color(red: 1.0, green: 0.95, blue: 0.98))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.28), radius: 24, y: 12)
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(request.kind.title)
    }

    private func permissionRow(_ title: String, action: @escaping () -> Void) -> some View {
        permissionButton(title, action: action)
            .frame(height: 58)
    }

    private func permissionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(Color(red: 0.88, green: 0.06, blue: 0.45))
                .poplurTextShader(intensity: 0.72, animated: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PoplurPermissionGate: View {
    @ObservedObject var center: PoplurPermissionCenter

    var body: some View {
        Group {
            if let request = center.request {
                PermissionOverlay(
                    request: request,
                    onAllow: { center.resolve(.allow) },
                    onDeny: { center.resolve(.deny) }
                )
                .transition(.opacity)
                .zIndex(20_000)
            }
        }
        .animation(.easeOut(duration: 0.22), value: center.request?.id)
    }
}
