import Foundation
import AVFoundation

internal struct PoplurTourStop {
    let cityName: String
    let storefront: String
}

@MainActor
final class CityTourMusicPlayerService: ObservableObject {
    @Published var currentTrack: CityMusicTrack? = nil
    @Published var isPlaying = false
    @Published var playbackProgress: Double = 0 // from 0 to 1
    
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    
    func play(track: CityMusicTrack) {
        guard let url = track.previewURL else {
            print("No preview URL available for track \(track.trackName)")
            return
        }
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        addPeriodicTimeObserver()
        player?.play()
        currentTrack = track
        isPlaying = true
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        playbackProgress = 0
        currentTrack = nil
        removePeriodicTimeObserver()
    }
    
    private func addPeriodicTimeObserver() {
        guard let player = player else { return }
        
        // Notify every 0.5 seconds
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC)), queue: .main) { [weak self] time in
            guard let self = self, let currentItem = player.currentItem else { return }
            let duration = currentItem.duration.seconds
            if duration.isFinite && duration > 0 {
                self.playbackProgress = time.seconds / duration
            } else {
                self.playbackProgress = 0
            }
        }
    }
    
    private func removePeriodicTimeObserver() {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }
    
    deinit {
        removePeriodicTimeObserver()
    }
}

struct CityMusicTrack: Identifiable, Equatable {
    let id = UUID()
    let artistName: String
    let trackName: String
    let previewURL: URL?
    let assetURI: String? // for uniqueness cache key
    
    init(artistName: String, trackName: String, previewURL: URL?, assetURI: String? = nil) {
        self.artistName = artistName
        self.trackName = trackName
        self.previewURL = previewURL
        self.assetURI = assetURI
    }
}

// Constants
let musicLookupTimeout: TimeInterval = 8.0

let musicTopTrackChoices = 8

// Fallback data dictionaries for music tracks keyed by storefront

let FallbackCityMusicTracks: [String: [CityMusicTrack]] = [
    // Example fallback for "us"
    "us": [
        CityMusicTrack(artistName: "The Beatles", trackName: "Come Together", previewURL: URL(string: "https://example.com/beatles.mp3")),
        CityMusicTrack(artistName: "Nirvana", trackName: "Smells Like Teen Spirit", previewURL: URL(string: "https://example.com/nirvana.mp3"))
    ]
    // Add other storefronts as needed
]

let DefaultFallbackCityMusicTrack = CityMusicTrack(artistName: "Unknown Artist", trackName: "Unknown Track", previewURL: nil)

let FallbackCityRadioTracks: [String: [CityMusicTrack]] = [
    // Example fallback data keyed by storefront
    "us": [
        CityMusicTrack(artistName: "Classic Hits Radio", trackName: "Top Hits", previewURL: URL(string: "https://example.com/classichits.mp3"))
    ]
    // Add other storefronts as needed
]

let FallbackCitySportsRadioTracks: [String: [CityMusicTrack]] = [
    // Example fallback data keyed by storefront
    "us": [
        CityMusicTrack(artistName: "Sports Radio", trackName: "Live Coverage", previewURL: URL(string: "https://example.com/sportsradio.mp3"))
    ]
    // Add other storefronts as needed
]

// MARK: - Helper functions for music queries and data resolving

func fetchText(from url: URL) async throws -> String {
    let (data, _) = try await URLSession.shared.data(from: url)
    guard let text = String(data: data, encoding: .utf8) else {
        throw URLError(.cannotDecodeContentData)
    }
    return text
}

@MainActor
func resolveTopCountryMusicTracks(for storefront: String) async -> [CityMusicTrack] {
    // Placeholder resolving logic, in real case it would fetch data from some API
    if let fallback = FallbackCityMusicTracks[storefront] {
        return fallback.uniquedByAssetURI()
    }
    return [DefaultFallbackCityMusicTrack]
}

@MainActor
func resolveTopCityRadioTracks(for storefront: String) async -> [CityMusicTrack] {
    if let fallback = FallbackCityRadioTracks[storefront] {
        return fallback.uniquedByAssetURI()
    }
    return []
}

@MainActor
func resolveTopCitySportsRadioTracks(for storefront: String) async -> [CityMusicTrack] {
    if let fallback = FallbackCitySportsRadioTracks[storefront] {
        return fallback.uniquedByAssetURI()
    }
    return []
}

// Query radio tracks from a provided URL endpoint returning JSON data
func queryRadioTracks(from url: URL) async throws -> [CityMusicTrack] {
    let (data, _) = try await URLSession.shared.data(from: url)
    guard
        let json = try? JSONSerialization.jsonObject(with: data, options: []),
        let dict = json as? [String: Any],
        let tracksArray = dict["tracks"] as? [[String: Any]]
    else {
        return []
    }
    var tracks: [CityMusicTrack] = []
    for trackDict in tracksArray {
        if let artist = trackDict["artistName"] as? String,
           let trackName = trackDict["trackName"] as? String,
           let previewStr = trackDict["previewURL"] as? String,
           let previewURL = URL(string: previewStr) {
            let assetURI = trackDict["assetURI"] as? String
            tracks.append(CityMusicTrack(artistName: artist, trackName: trackName, previewURL: previewURL, assetURI: assetURI))
        }
    }
    return tracks.uniquedByAssetURI()
}

// Lookup preview URL from iTunes API for a given artist and track
func lookupITunesPreviewURL(artistName: String, trackName: String, storefront: String) async -> URL? {
    let query = "\(artistName) \(trackName)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    let urlStr = "https://itunes.apple.com/search?term=\(query)&country=\(storefront)&media=music&limit=1"
    guard let url = URL(string: urlStr) else { return nil }
    do {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard
            let json = try? JSONSerialization.jsonObject(with: data, options: []),
            let dict = json as? [String: Any],
            let results = dict["results"] as? [[String: Any]],
            let first = results.first,
            let previewUrlStr = first["previewUrl"] as? String,
            let previewURL = URL(string: previewUrlStr)
        else {
            return nil
        }
        return previewURL
    } catch {
        return nil
    }
}

// MARK: - Array extensions

extension Array where Element == CityMusicTrack {
    func uniquedByAssetURI() -> [CityMusicTrack] {
        var seen: Set<String> = []
        var result: [CityMusicTrack] = []
        for track in self {
            if let uri = track.assetURI {
                if !seen.contains(uri) {
                    seen.insert(uri)
                    result.append(track)
                }
            } else {
                // If assetURI is missing, include the track anyway
                result.append(track)
            }
        }
        return result
    }
}
