import SwiftUI
import UIKit

@MainActor
struct ProfileThemePickerView: View {
    @ObservedObject var store: ProfileThemeStore
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    init(store: ProfileThemeStore = .shared) {
        self.store = store
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(ProfileTheme.allCases) { theme in
                        themeButton(theme)
                    }
                }
                .padding(18)
            }
            .background(DS.Color.background.ignoresSafeArea())
            .navigationTitle("Profile Theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
        .accessibilityIdentifier("ProfileThemePicker")
    }

    private func themeButton(_ theme: ProfileTheme) -> some View {
        let isSelected = store.selectedTheme == theme
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            store.select(theme)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                ProfileThemeThumbnail(theme: theme)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.78, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(isSelected ? theme.primaryAccent : Color.white.opacity(0.72), lineWidth: isSelected ? 4 : 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(theme.primaryAccent, in: Circle())
                                .padding(9)
                                .accessibilityHidden(true)
                        }
                    }

                HStack(spacing: 7) {
                    Circle()
                        .fill(theme.primaryAccent)
                        .frame(width: 10, height: 10)
                    Text(theme.displayName)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(DS.Color.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            .padding(8)
            .background(Color.white.opacity(isSelected ? 0.98 : 0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("ProfileThemeTile_\(theme.rawValue)")
        .accessibilityLabel(theme.displayName)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ProfileThemeThumbnail: View {
    let theme: ProfileTheme

    var body: some View {
        ZStack {
            if theme == .default {
                DS.Color.background
                Image(systemName: "sparkles")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
                    .shadow(color: DS.Color.accent.opacity(0.35), radius: 12)
            } else if let thumbnailAssetName = theme.thumbnailAssetName,
                      UIImage(named: thumbnailAssetName) != nil {
                Image(thumbnailAssetName)
                    .resizable()
                    .scaledToFill()
                theme.overlayColor.opacity(theme.overlayOpacity)
            } else {
                LinearGradient(
                    colors: [theme.primaryAccent, theme.secondaryAccent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(theme.foreground)
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

#if DEBUG
@MainActor
struct ProfileThemePickerView_Previews: PreviewProvider {
    static var previews: some View {
        ProfileThemePickerView()
            .frame(width: 390, height: 844)
    }
}
#endif
