import Foundation
import CoreLocation

// MARK: - User-created AI games (saved list + map placement)
//
// A PoplurSavedGame wraps an AI-generated PoplurGameConfig the user chose to keep.
// The store persists the list to UserDefaults and tracks an optional map location so
// a game can be "placed anywhere on the map" and launched from its pin.

struct PoplurSavedGame: Identifiable, Codable, Equatable {
    let id: UUID
    var config: PoplurGameConfig
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date

    init(config: PoplurGameConfig, latitude: Double? = nil, longitude: Double? = nil) {
        self.id = UUID()
        self.config = config
        self.latitude = latitude
        self.longitude = longitude
        self.createdAt = Date()
    }

    var isPlaced: Bool { latitude != nil && longitude != nil }

    var coordinate: CLLocationCoordinate2D? {
        guard let la = latitude, let lo = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: lo)
    }

    static func == (lhs: PoplurSavedGame, rhs: PoplurSavedGame) -> Bool {
        lhs.id == rhs.id && lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

@MainActor
final class PoplurSavedGamesStore: ObservableObject {
    static let shared = PoplurSavedGamesStore()

    /// All AI-made games, newest first.
    @Published private(set) var games: [PoplurSavedGame] = []
    /// When non-nil the map is waiting for the user to tap a spot to place this game.
    @Published var pendingPlacement: PoplurSavedGame? = nil

    private let key = "poplur_saved_games_v1"

    private init() { load() }

    var placedGames: [PoplurSavedGame] { games.filter { $0.isPlaced } }

    @discardableResult
    func add(_ config: PoplurGameConfig) -> PoplurSavedGame {
        let g = PoplurSavedGame(config: config)
        games.insert(g, at: 0)
        save()
        return g
    }

    func remove(_ game: PoplurSavedGame) {
        games.removeAll { $0.id == game.id }
        if pendingPlacement?.id == game.id { pendingPlacement = nil }
        save()
    }

    func place(_ game: PoplurSavedGame, latitude: Double, longitude: Double) {
        guard let i = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[i].latitude = latitude
        games[i].longitude = longitude
        save()
    }

    func unplace(_ game: PoplurSavedGame) {
        guard let i = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[i].latitude = nil
        games[i].longitude = nil
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let arr = try? JSONDecoder().decode([PoplurSavedGame].self, from: data) else { return }
        games = arr
    }

    private func save() {
        if let data = try? JSONEncoder().encode(games) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
