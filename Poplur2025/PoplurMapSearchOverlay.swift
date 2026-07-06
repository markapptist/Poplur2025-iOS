import SwiftUI
import MapKit

// MARK: - Full search overlay

struct PoplurMapSearchOverlay: View {
    let skin: CubeSkin
    @Binding var query: String
    @Binding var results: [MKMapItem]
    @Binding var isSearching: Bool
    var onSelectResult: (MKMapItem) -> Void
    var onDismiss: () -> Void

    @FocusState private var fieldFocused: Bool
    @State private var appear = false

    private var theme: PoplurMapThemeData { skin.poplurTheme.mapThemeData }
    private var appTheme: CubeSkinAppTheme { skin.appTheme }
    private var accent: Color { theme.searchTint }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar header
            PoplurGlassCard(skin: skin, cornerRadius: 20) {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(accent)
                            .poplurGlow(color: accent, radius: 6, opacity: 0.5)

                        TextField("Search places, people, vibes...", text: $query)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(appTheme.primaryText)
                            .tint(accent)
                            .focused($fieldFocused)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onSubmit { performSearch() }
                            .submitLabel(.search)

                        if !query.isEmpty {
                            Button(action: { query = ""; results = [] }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(appTheme.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.easeInOut(duration: 0.15), value: query.isEmpty)

                    // AI suggestion chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(suggestionChips, id: \.self) { chip in
                                suggestionButton(chip)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                }
                .padding(16)
            }

            if !results.isEmpty || isSearching {
                Spacer().frame(height: 10)

                // Results list
                PoplurGlassCard(skin: skin, cornerRadius: 20) {
                    VStack(spacing: 0) {
                        if isSearching {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(accent)
                                Text("Searching...")
                                    .font(.system(size: 14))
                                    .foregroundStyle(appTheme.secondaryText)
                            }
                            .padding(16)
                        } else {
                            ForEach(results.indices, id: \.self) { i in
                                resultRow(results[i])
                                if i < results.count - 1 {
                                    PoplurGlassDivider(skin: skin).padding(.horizontal, 16)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Spacer()

            // Cancel button at bottom
            Button(action: {
                query = ""
                results = []
                fieldFocused = false
                withAnimation(.easeInOut(duration: 0.22)) { appear = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { onDismiss() }
            }) {
                Text("Cancel")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(appTheme.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule()
                            .fill(theme.controlBackground.opacity(0.8))
                            .overlay(Capsule().fill(.ultraThinMaterial).opacity(0.5))
                    )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .scaleEffect(appear ? 1 : 0.96)
        .opacity(appear ? 1 : 0)
        .onAppear {
            fieldFocused = true
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                appear = true
            }
        }
        .onChange(of: query) { performSearch() }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func suggestionButton(_ text: String) -> some View {
        Button(action: {
            query = text
            performSearch()
        }) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(accent.opacity(0.14))
                    .overlay(Capsule().stroke(accent.opacity(0.3), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func resultRow(_ item: MKMapItem) -> some View {
        Button(action: { onSelectResult(item) }) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: iconForCategory(item.pointOfInterestCategory))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name ?? "Unknown")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(appTheme.primaryText)
                        .lineLimit(1)
                    if let addr = item.placemark.thoroughfare {
                        Text(addr)
                            .font(.system(size: 12))
                            .foregroundStyle(appTheme.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(appTheme.secondaryText.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var suggestionChips: [String] {
        ["Nearby vibes", "Coffee spots", "Rooftops", "Live music", "Night market"]
    }

    private func performSearch() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }
        isSearching = true
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        MKLocalSearch(request: request).start { response, _ in
            DispatchQueue.main.async {
                isSearching = false
                results = response?.mapItems.prefix(8).map { $0 } ?? []
            }
        }
    }

    private func iconForCategory(_ category: MKPointOfInterestCategory?) -> String {
        guard let category else { return "mappin.circle.fill" }
        switch category {
        case .restaurant, .cafe, .bakery, .foodMarket, .brewery: return "fork.knife"
        case .hotel:                   return "bed.double.fill"
        case .hospital, .pharmacy:     return "cross.fill"
        case .park, .nationalPark:     return "leaf.fill"
        case .museum, .theater, .movieTheater: return "star.fill"
        case .gasStation:              return "car.fill"
        case .store:                   return "bag.fill"
        case .nightlife:               return "music.mic"
        case .school, .university:     return "book.fill"
        case .airport:                 return "airplane"
        default:                       return "mappin.circle.fill"
        }
    }
}

// MARK: - Recent search pill

struct PoplurRecentSearchRow: View {
    let skin: CubeSkin
    let text: String
    var onTap: (String) -> Void
    var onRemove: (String) -> Void

    private var appTheme: CubeSkinAppTheme { skin.appTheme }
    private var accent: Color { skin.poplurTheme.mapThemeData.searchTint }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 14))
                .foregroundStyle(appTheme.secondaryText)
            Button(action: { onTap(text) }) {
                Text(text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(appTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            Button(action: { onRemove(text) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundStyle(appTheme.secondaryText.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}
