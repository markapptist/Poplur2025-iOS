import Foundation
import Combine

@MainActor
class DailyQuotaViewModel: ObservableObject {
    @Published var postsUsedToday: Int = 0 {
        didSet { persist() }
    }
    @Published var hasDailyUpgrade: Bool = false {
        didSet { persist() }
    }
    @Published var lastResetDate: Date = Date() {
        didSet { persist() }
    }
    
    private let postsUsedKey = "daily.postsUsedToday"
    private let lastResetDateKey = "daily.lastResetDate"
    private let hasUpgradeKey = "daily.hasUpgrade"
    
    var dailyPostLimit: Int {
        hasDailyUpgrade ? 15 : 10
    }
    
    var remainingPosts: Int {
        max(dailyPostLimit - postsUsedToday, 0)
    }
    
    init() {
        load()
        resetIfNeeded()
    }
    
    func onAppActive() {
        resetIfNeeded()
    }
    
    func canPost() -> Bool {
        resetIfNeeded()
        return postsUsedToday < dailyPostLimit
    }
    
    func recordPost() {
        resetIfNeeded()
        guard postsUsedToday < dailyPostLimit else { return }
        postsUsedToday += 1
    }
    
    func setUpgradePurchased() {
        hasDailyUpgrade = true
    }
    
    private func resetIfNeeded() {
        let now = Date()
        if !Calendar.current.isDate(lastResetDate, inSameDayAs: now) {
            postsUsedToday = 0
            lastResetDate = now
        }
    }
    
    private func load() {
        let defaults = UserDefaults.standard
        
        if let savedDate = defaults.object(forKey: lastResetDateKey) as? Date {
            lastResetDate = savedDate
        } else {
            lastResetDate = Date()
        }
        
        postsUsedToday = defaults.integer(forKey: postsUsedKey)
        hasDailyUpgrade = defaults.bool(forKey: hasUpgradeKey)
    }
    
    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(postsUsedToday, forKey: postsUsedKey)
        defaults.set(lastResetDate, forKey: lastResetDateKey)
        defaults.set(hasDailyUpgrade, forKey: hasUpgradeKey)
    }
}
