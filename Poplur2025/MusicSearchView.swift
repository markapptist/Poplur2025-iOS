import SwiftUI
import Foundation

enum MusicProvider: String, CaseIterable, Identifiable, Hashable {
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case tidal = "TIDAL"
    case soundCloud = "SoundCloud"
    case youtubeMusic = "YouTube Music"
    case deezer = "Deezer"
    case amazonMusic = "Amazon Music"
    case bandcamp = "Bandcamp"
    case audiomack = "Audiomack"

    var id: String { rawValue }

    var accent: Color {
        switch self {
        case .appleMusic: return Color(red: 1.0, green: 0.18, blue: 0.36)
        case .spotify: return Color(red: 0.12, green: 0.84, blue: 0.38)
        case .tidal: return .white
        case .soundCloud: return Color(red: 1.0, green: 0.43, blue: 0.0)
        case .youtubeMusic: return Color(red: 1.0, green: 0.0, blue: 0.0)
        case .deezer: return Color(red: 0.55, green: 0.35, blue: 1.0)
        case .amazonMusic: return Color(red: 0.0, green: 0.78, blue: 1.0)
        case .bandcamp: return Color(red: 0.38, green: 0.76, blue: 0.82)
        case .audiomack: return Color(red: 1.0, green: 0.81, blue: 0.11)
        }
    }
}

struct MusicSearchTrack: Identifiable, Hashable {
    let id: String
    let provider: MusicProvider
    let title: String
    let artist: String
    let album: String
    let artworkURL: URL?
    let previewURL: URL?
    let externalURL: URL?
    let durationText: String
}

enum MusicSearchCatalog {
    static func search(_ query: String, provider: MusicProvider?) -> [MusicSearchTrack] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = seedTracks.filter { provider == nil || $0.provider == provider }

        guard !trimmed.isEmpty else {
            return Array(base.prefix(18))
        }

        let needle = trimmed.localizedCaseInsensitiveContains("poplur")
            ? ""
            : trimmed.lowercased()

        guard !needle.isEmpty else { return Array(base.prefix(18)) }

        return base.filter {
            $0.title.lowercased().contains(needle)
            || $0.artist.lowercased().contains(needle)
            || $0.album.lowercased().contains(needle)
            || $0.provider.rawValue.lowercased().contains(needle)
        }
    }

    private static let seedTracks: [MusicSearchTrack] = [
        track(.appleMusic, "City Signal", "Poplur Radio", "Radius Nights", "3:04", "https://music.apple.com/search?term=city%20signal"),
        track(.spotify, "Post It Where It Matters", "Poplur Creative", "Local Discovery", "2:38", "https://open.spotify.com/search/post%20it%20where%20it%20matters"),
        track(.tidal, "Live Radius", "The Signal Team", "Neighborhood Energy", "2:51", "https://listen.tidal.com/search?q=live%20radius"),
        track(.soundCloud, "Poplur Street Loop", "Radius FM", "Street Clips", "1:47", "https://soundcloud.com/search?q=poplur%20street%20loop"),
        track(.youtubeMusic, "Channel 101 Intro", "Poplur TV", "Broadcast Pack", "0:45", "https://music.youtube.com/search?q=channel%20101%20intro"),
        track(.deezer, "Mall Sale Sweep", "Local Signal", "Shopping Breaks", "2:13", "https://www.deezer.com/search/mall%20sale%20sweep"),
        track(.amazonMusic, "Game Day Cut", "Stadium Pulse", "Sports Radius", "2:25", "https://music.amazon.com/search/game%20day%20cut"),
        track(.bandcamp, "Late Feed Glow", "Independent Poplur", "Creator Bumps", "3:19", "https://bandcamp.com/search?q=late%20feed%20glow"),
        track(.audiomack, "City Camera Roll", "Poplur Uploads", "Creator Cuts", "2:07", "https://audiomack.com/search?q=city%20camera%20roll"),
        track(.appleMusic, "Food Channel Bounce", "CH 101", "Live Channels", "1:58", "https://music.apple.com/search?term=food%20channel%20bounce"),
        track(.spotify, "Beauty Channel Flash", "CH 103", "Live Channels", "2:09", "https://open.spotify.com/search/beauty%20channel%20flash"),
        track(.soundCloud, "Tech Late Feed", "CH 108", "Live Channels", "2:42", "https://soundcloud.com/search?q=tech%20late%20feed")
    ]

    private static func track(
        _ provider: MusicProvider,
        _ title: String,
        _ artist: String,
        _ album: String,
        _ duration: String,
        _ external: String
    ) -> MusicSearchTrack {
        MusicSearchTrack(
            id: "\(provider.rawValue)-\(title)-\(artist)".lowercased().replacingOccurrences(of: " ", with: "-"),
            provider: provider,
            title: title,
            artist: artist,
            album: album,
            artworkURL: nil,
            previewURL: nil,
            externalURL: URL(string: external),
            durationText: duration
        )
    }
}

struct MusicSearchSheet: View {
    let selectedTrack: MusicSearchTrack?
    let onSelect: (MusicSearchTrack) -> Void
    let onUseLocalFile: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedProvider: MusicProvider? = nil

    private var results: [MusicSearchTrack] {
        MusicSearchCatalog.search(query, provider: selectedProvider)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 14) {
                    searchField
                    providerStrip
                    localFileButton
                    resultList
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
            }
            .navigationTitle("Add music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.55))
            TextField("Search songs, artists, sounds", text: $query)
                .textInputAutocapitalization(.never)
                .foregroundStyle(.white)
                .submitLabel(.search)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var providerStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                providerChip(title: "All", provider: nil)
                ForEach(MusicProvider.allCases) { provider in
                    providerChip(title: provider.rawValue, provider: provider)
                }
            }
        }
    }

    private func providerChip(title: String, provider: MusicProvider?) -> some View {
        let isSelected = selectedProvider == provider
        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                selectedProvider = provider
            }
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isSelected ? Color.white : Color.white.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var localFileButton: some View {
        Button {
            onUseLocalFile()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder.badge.plus")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Use local audio/video file")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                    Text("This is the current path for burning music into uploads.")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var resultList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(results) { track in
                    MusicSearchTrackRow(
                        track: track,
                        isSelected: track.id == selectedTrack?.id
                    ) {
                        onSelect(track)
                        dismiss()
                    }
                }
            }
            .padding(.bottom, 24)
        }
    }
}

private struct MusicSearchTrackRow: View {
    let track: MusicSearchTrack
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [track.provider.accent.opacity(0.95), Color.white.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 20, weight: .black))
                            .foregroundStyle(.black.opacity(track.provider == .tidal ? 0.75 : 0.95))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("\(track.artist) • \(track.album)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                    Text(track.provider.rawValue)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(track.provider.accent)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(track.durationText)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(isSelected ? Color(red: 0.3, green: 1.0, blue: 0.45) : .white.opacity(0.45))
                }
            }
            .padding(12)
            .background(Color.white.opacity(isSelected ? 0.16 : 0.075), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? Color(red: 0.3, green: 1.0, blue: 0.45) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
