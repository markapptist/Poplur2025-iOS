import Foundation

// MARK: - Pet State

struct PetState: Codable {
    enum Stage: String, Codable { case egg, baby, teen, adult }
    enum Mood:  String, Codable { case idle, eating, playing, bathing, sleeping, sick, happy, sad }

    var stage:       Stage  = .egg
    var hunger:      Float  = 80   // 0 = starving, 100 = full
    var happiness:   Float  = 80
    var cleanliness: Float  = 80
    var energy:      Float  = 80
    var health:      Float  = 100
    var isSleeping:  Bool   = false
    var isSick:      Bool   = false
    var hasPoop:     Bool   = false
    var ageSeconds:  Double = 0
    var careScore:   Int    = 100
    var lastUpdated: Date   = Date()

    // MARK: Simulation tick

    mutating func tick(seconds: Double) {
        let mins = Float(seconds / 60.0)
        let dirtyMult: Float = hasPoop ? 3 : 1

        if !isSleeping {
            hunger      = max(0, hunger      - mins * 2)
            happiness   = max(0, happiness   - mins * 1)
            cleanliness = max(0, cleanliness - mins * dirtyMult)
            energy      = max(0, energy      - mins * 1)
        } else {
            hunger      = max(0, hunger      - mins * 1)
            energy      = min(100, energy    + mins * 4)
            cleanliness = max(0, cleanliness - mins * dirtyMult)
        }

        if hunger < 20 || cleanliness < 25 || hasPoop {
            health = max(0, health - mins * 2)
            careScore = max(0, careScore - 1)
        } else if hunger > 50 && cleanliness > 60 && !isSick {
            health = min(100, health + mins * 0.5)
        }

        if health < 35 { isSick = true }
        if health > 65 && isSick { isSick = false }

        ageSeconds  += seconds
        lastUpdated  = Date()
    }

    // MARK: Care actions

    mutating func feed()     { hunger = min(100, hunger + 18); cleanliness = max(0, cleanliness - 2) }
    mutating func snack()    { happiness = min(100, happiness + 10); hunger = min(100, hunger + 5); health = max(0, health - 2) }
    mutating func play()     { happiness = min(100, happiness + 16); energy = max(0, energy - 8); hunger = max(0, hunger - 4) }
    mutating func bath()     { cleanliness = min(100, cleanliness + 25); hasPoop = false }
    mutating func medicine() { health = min(100, health + 30); if health > 50 { isSick = false } }
    mutating func toggleSleep() { isSleeping.toggle() }

    // MARK: Derived mood (priority list per spec)

    var currentMood: Mood {
        if isSick          { return .sick    }
        if isSleeping      { return .sleeping }
        if hasPoop         { return .sad     }
        if hunger     < 25 { return .sad     }
        if energy     < 20 { return .sad     }
        if happiness  < 25 { return .sad     }
        return .idle
    }

    // Which stage should the pet be at now?
    var targetStage: Stage {
        if ageSeconds < 30       { return .egg   }
        if ageSeconds < 5  * 60  { return .baby  }
        if ageSeconds < 20 * 60  { return .teen  }
        return .adult
    }
}

// MARK: - Simulation helpers

enum PetSimulation {
    static let maxOfflineSeconds: Double = 8 * 3600

    static func applyOfflineDecay(to state: inout PetState) {
        let elapsed = min(-state.lastUpdated.timeIntervalSinceNow, maxOfflineSeconds)
        guard elapsed > 1 else { return }
        state.tick(seconds: elapsed)
    }
}

// MARK: - Persistence

enum PetSaveManager {
    private static let key = "poplur.pet.state.v2"

    static func load() -> PetState {
        guard let data  = UserDefaults.standard.data(forKey: key),
              let state = try? JSONDecoder().decode(PetState.self, from: data)
        else { return PetState() }
        return state
    }

    static func save(_ state: PetState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Menu actions

enum PetMenuAction: Int, CaseIterable {
    case meal, snack, play, bath, medicine, sleep, stats

    var label: String {
        switch self {
        case .meal:     "MEAL"
        case .snack:    "SNACK"
        case .play:     "PLAY"
        case .bath:     "BATH"
        case .medicine: "MED"
        case .sleep:    "SLEEP"
        case .stats:    "STATS"
        }
    }
}
