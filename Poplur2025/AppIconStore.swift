import SwiftUI
import UIKit

enum PoplurAppIcon: String, CaseIterable, Identifiable, Sendable {
    case defaultClay = "default"
    case pastel = "pastel"
    case neonBlue = "neonBlue"
    case roseGold = "roseGold"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .defaultClay: return "Default Clay"
        case .pastel: return "Pastel Clay"
        case .neonBlue: return "Neon Blue"
        case .roseGold: return "Rose Gold"
        }
    }

    var alternateIconName: String? {
        switch self {
        case .defaultClay: return nil
        case .pastel: return "AppIconPastel"
        case .neonBlue: return "AppIconNeonBlue"
        case .roseGold: return "AppIconRoseGold"
        }
    }

    var previewAssetName: String { "app_icon_preview_\(rawValue)" }

    static func resolve(alternateIconName: String?) -> PoplurAppIcon {
        allCases.first { $0.alternateIconName == alternateIconName } ?? .defaultClay
    }
}

@MainActor
final class AppIconStore: ObservableObject {
    static let shared = AppIconStore()

    @Published private(set) var selectedIcon: PoplurAppIcon
    @Published private(set) var isApplying = false
    @Published private(set) var errorMessage: String?

    private let defaultsKey = "poplur.appIcon.v1"

    private init() {
        let application = UIApplication.shared
        selectedIcon = PoplurAppIcon.resolve(alternateIconName: application.alternateIconName)
        UserDefaults.standard.set(selectedIcon.rawValue, forKey: defaultsKey)
    }

    func refreshFromSystem() {
        let application = UIApplication.shared
        selectedIcon = PoplurAppIcon.resolve(alternateIconName: application.alternateIconName)
        UserDefaults.standard.set(selectedIcon.rawValue, forKey: defaultsKey)
    }

    func apply(
        _ icon: PoplurAppIcon,
        completion: ((Bool, String?) -> Void)? = nil
    ) {
        let application = UIApplication.shared
        guard application.supportsAlternateIcons else {
            let message = "App icon switching is not supported on this device."
            errorMessage = message
            completion?(false, message)
            return
        }
        guard !isApplying else {
            completion?(false, "Another icon change is already in progress.")
            return
        }
        guard application.alternateIconName != icon.alternateIconName else {
            selectedIcon = icon
            errorMessage = nil
            completion?(true, nil)
            return
        }

        isApplying = true
        errorMessage = nil
        application.setAlternateIconName(icon.alternateIconName) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.isApplying = false
                if let error {
                    let message = error.localizedDescription
                    self.errorMessage = message
                    completion?(false, message)
                    return
                }
                self.selectedIcon = icon
                UserDefaults.standard.set(icon.rawValue, forKey: self.defaultsKey)
                completion?(true, nil)
            }
        }
    }
}

private struct AppIconOptionView: View {
    let icon: PoplurAppIcon
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Image(icon.previewAssetName)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(isSelected ? Color.pink : Color.clear, lineWidth: 3)
                    }
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 25, weight: .bold))
                        .foregroundStyle(.white, Color.pink)
                        .offset(x: 5, y: -5)
                }
            }
            Text(icon.displayName)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}

struct AppIconPickerView: View {
    @ObservedObject var store: AppIconStore
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 92, maximum: 118), spacing: 14)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(PoplurAppIcon.allCases) { icon in
                        Button {
                            store.apply(icon)
                        } label: {
                            AppIconOptionView(
                                icon: icon,
                                isSelected: store.selectedIcon == icon
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(store.isApplying)
                        .accessibilityLabel(icon.displayName)
                        .accessibilityAddTraits(store.selectedIcon == icon ? .isSelected : [])
                    }
                }
                .padding(20)

                if let error = store.errorMessage {
                    Text(error)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                }
            }
            .navigationTitle("App Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { store.refreshFromSystem() }
    }
}
