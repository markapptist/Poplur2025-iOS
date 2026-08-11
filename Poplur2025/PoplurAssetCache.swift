import Foundation

/// Application-owned cache budget for decoded/renderable assets.
///
/// This is deliberately not described as an operating-system process-memory cap:
/// iOS owns the process working set. Poplur can, however, put strict byte and item
/// limits on the resources it elects to retain for reuse.
final class PoplurAssetCache: @unchecked Sendable {
    static let shared = PoplurAssetCache()

    enum Category: String, CaseIterable, Sendable {
        case model
        case texture
        case scene
        case decodedImage
        case temporary
        case video
        case webAsset
    }

    enum PurgeReason: String, Sendable {
        case manual
        case memoryPressure
        case thermalPressure
        case inactive
        case background
        case budgetReduction
    }

    struct Limits: Sendable, Equatable {
        var byteLimit: Int
        var itemLimit: Int
        var categoryItemLimits: [Category: Int]

        static func deviceDefault() -> Limits {
            // A larger phone must not silently turn into permission to retain
            // hundreds of MB of decoded images, textures and scenes. Apart from
            // memory pressure, those retained objects also keep more GPU-backed
            // resources alive and make Poplur's energy use device-dependent.
            // Keep one small, absolute application-owned working set instead.
            let mebibyte = 1_048_576
            return Limits(
                byteLimit: 64 * mebibyte,
                itemLimit: 64,
                categoryItemLimits: [
                    .model: 6,
                    .texture: 16,
                    .scene: 4,
                    .decodedImage: 24,
                    .temporary: 4,
                    .video: 1,
                    .webAsset: 16,
                ]
            )
        }
    }

    struct Snapshot: Sendable, Equatable {
        let estimatedByteCount: Int
        let byteLimit: Int
        let itemCount: Int
        let itemLimit: Int
        let categoryCounts: [Category: Int]
        let evictionCount: Int
        let rejectionCount: Int
    }

    private struct Entry {
        let asset: AnyObject
        let category: Category
        let estimatedByteCost: Int
        var accessSequence: UInt64
        let onEvict: (() -> Void)?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private var limits: Limits
    private var estimatedByteCount = 0
    private var sequence: UInt64 = 0
    private var evictionCount = 0
    private var rejectionCount = 0

    init(limits: Limits = .deviceDefault()) {
        self.limits = Self.sanitized(limits)
    }

    @discardableResult
    func insert(
        _ asset: AnyObject,
        forKey key: String,
        category: Category,
        estimatedByteCost: Int,
        onEvict: (() -> Void)? = nil
    ) -> Bool {
        let namespacedKey = Self.namespacedKey(key, category: category)
        let cost = max(1, estimatedByteCost)
        var callbacks: [() -> Void] = []
        var inserted = false

        lock.lock()
        if cost > limits.byteLimit || limits.itemLimit == 0 || categoryLimitLocked(category) == 0 {
            rejectionCount += 1
        } else {
            if let replaced = entries.removeValue(forKey: namespacedKey) {
                estimatedByteCount -= replaced.estimatedByteCost
                if let callback = replaced.onEvict { callbacks.append(callback) }
            }

            while mustEvictLocked(incomingCost: cost, incomingCategory: category),
                  let victimKey = evictionVictimKeyLocked(incomingCost: cost, incomingCategory: category) {
                removeLocked(victimKey, callbacks: &callbacks)
            }

            if !mustEvictLocked(incomingCost: cost, incomingCategory: category) {
                sequence &+= 1
                entries[namespacedKey] = Entry(
                    asset: asset,
                    category: category,
                    estimatedByteCost: cost,
                    accessSequence: sequence,
                    onEvict: onEvict
                )
                estimatedByteCount += cost
                inserted = true
            } else {
                rejectionCount += 1
            }
        }
        lock.unlock()

        callbacks.forEach { $0() }
        return inserted
    }

    func asset<T: AnyObject>(forKey key: String, category: Category, as type: T.Type = T.self) -> T? {
        let namespacedKey = Self.namespacedKey(key, category: category)
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[namespacedKey], let asset = entry.asset as? T else { return nil }
        sequence &+= 1
        entry.accessSequence = sequence
        entries[namespacedKey] = entry
        return asset
    }

    func removeValue(forKey key: String, category: Category) {
        let namespacedKey = Self.namespacedKey(key, category: category)
        var callbacks: [() -> Void] = []
        lock.lock()
        removeLocked(namespacedKey, callbacks: &callbacks)
        lock.unlock()
        callbacks.forEach { $0() }
    }

    func removeAll(category: Category, where shouldRemove: ((String) -> Bool)? = nil) {
        var callbacks: [() -> Void] = []
        lock.lock()
        let prefix = "\(category.rawValue)::"
        let keys = entries.keys.filter { namespacedKey in
            guard namespacedKey.hasPrefix(prefix) else { return false }
            guard let shouldRemove else { return true }
            return shouldRemove(String(namespacedKey.dropFirst(prefix.count)))
        }
        for key in keys { removeLocked(key, callbacks: &callbacks) }
        lock.unlock()
        callbacks.forEach { $0() }
    }

    /// Applies a new strict budget and evicts LRU entries before returning.
    func updateLimits(_ newLimits: Limits, reason: PurgeReason = .budgetReduction) {
        var callbacks: [() -> Void] = []
        let sanitized = Self.sanitized(newLimits)
        lock.lock()
        limits = sanitized
        evictUntilWithinLimitsLocked(callbacks: &callbacks)
        lock.unlock()
        callbacks.forEach { $0() }
        debugLog("Limits updated (\(reason.rawValue)): \(Self.megabytes(sanitized.byteLimit)) MB / \(sanitized.itemLimit) items")
    }

    func updateByteLimit(_ byteLimit: Int, reason: PurgeReason = .budgetReduction) {
        var next = currentLimits()
        next.byteLimit = max(0, byteLimit)
        updateLimits(next, reason: reason)
    }

    /// Trims to an absolute byte count while retaining the most recently used entries.
    func trim(toByteCount target: Int, reason: PurgeReason) {
        var callbacks: [() -> Void] = []
        let safeTarget = max(0, min(target, currentLimits().byteLimit))
        lock.lock()
        while estimatedByteCount > safeTarget, let victimKey = leastRecentlyUsedKeyLocked() {
            removeLocked(victimKey, callbacks: &callbacks)
        }
        lock.unlock()
        callbacks.forEach { $0() }
        debugLog("Trimmed for \(reason.rawValue); retained \(Self.megabytes(snapshot().estimatedByteCount)) MB")
    }

    @discardableResult
    func purge(reason: PurgeReason = .manual) -> Int {
        var callbacks: [() -> Void] = []
        lock.lock()
        let releasedBytes = estimatedByteCount
        for key in Array(entries.keys) { removeLocked(key, callbacks: &callbacks) }
        lock.unlock()
        callbacks.forEach { $0() }
        debugLog("Purged \(Self.megabytes(releasedBytes)) MB asset cache (\(reason.rawValue))")
        return releasedBytes
    }

    func currentLimits() -> Limits {
        lock.lock()
        defer { lock.unlock() }
        return limits
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        var categoryCounts: [Category: Int] = [:]
        for entry in entries.values { categoryCounts[entry.category, default: 0] += 1 }
        return Snapshot(
            estimatedByteCount: estimatedByteCount,
            byteLimit: limits.byteLimit,
            itemCount: entries.count,
            itemLimit: limits.itemLimit,
            categoryCounts: categoryCounts,
            evictionCount: evictionCount,
            rejectionCount: rejectionCount
        )
    }

    private static func namespacedKey(_ key: String, category: Category) -> String {
        "\(category.rawValue)::\(key)"
    }

    private static func sanitized(_ limits: Limits) -> Limits {
        var next = limits
        next.byteLimit = max(0, next.byteLimit)
        next.itemLimit = max(0, next.itemLimit)
        for category in Category.allCases {
            next.categoryItemLimits[category] = max(0, next.categoryItemLimits[category] ?? next.itemLimit)
        }
        return next
    }

    private func categoryLimitLocked(_ category: Category) -> Int {
        min(limits.itemLimit, limits.categoryItemLimits[category] ?? limits.itemLimit)
    }

    private func categoryCountLocked(_ category: Category) -> Int {
        entries.values.reduce(into: 0) { count, entry in
            if entry.category == category { count += 1 }
        }
    }

    private func mustEvictLocked(incomingCost: Int, incomingCategory: Category) -> Bool {
        estimatedByteCount + incomingCost > limits.byteLimit
            || entries.count + 1 > limits.itemLimit
            || categoryCountLocked(incomingCategory) + 1 > categoryLimitLocked(incomingCategory)
    }

    private func evictUntilWithinLimitsLocked(callbacks: inout [() -> Void]) {
        while isOverLimitLocked(), let victimKey = overLimitVictimKeyLocked() {
            removeLocked(victimKey, callbacks: &callbacks)
        }
    }

    private func isOverLimitLocked() -> Bool {
        if estimatedByteCount > limits.byteLimit || entries.count > limits.itemLimit { return true }
        return Category.allCases.contains { categoryCountLocked($0) > categoryLimitLocked($0) }
    }

    /// Prefer an entry from the overfull category. This preserves unrelated hot
    /// resources while keeping eviction deterministic for the same access order.
    private func evictionVictimKeyLocked(incomingCost: Int, incomingCategory: Category) -> String? {
        if categoryCountLocked(incomingCategory) + 1 > categoryLimitLocked(incomingCategory) {
            return leastRecentlyUsedKeyLocked(in: incomingCategory)
        }
        return leastRecentlyUsedKeyLocked()
    }

    private func overLimitVictimKeyLocked() -> String? {
        if estimatedByteCount > limits.byteLimit || entries.count > limits.itemLimit {
            return leastRecentlyUsedKeyLocked()
        }
        if let overfullCategory = Category.allCases.first(where: {
            categoryCountLocked($0) > categoryLimitLocked($0)
        }) {
            return leastRecentlyUsedKeyLocked(in: overfullCategory)
        }
        return nil
    }

    private func leastRecentlyUsedKeyLocked(in category: Category? = nil) -> String? {
        entries.lazy.filter { category == nil || $0.value.category == category }.min { lhs, rhs in
            if lhs.value.accessSequence != rhs.value.accessSequence {
                return lhs.value.accessSequence < rhs.value.accessSequence
            }
            return lhs.key < rhs.key
        }?.key
    }

    private func removeLocked(_ key: String, callbacks: inout [() -> Void]) {
        guard let removed = entries.removeValue(forKey: key) else { return }
        estimatedByteCount = max(0, estimatedByteCount - removed.estimatedByteCost)
        evictionCount += 1
        if let callback = removed.onEvict { callbacks.append(callback) }
    }

    private static func megabytes(_ bytes: Int) -> Int {
        Int((Double(bytes) / 1_048_576.0).rounded())
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[PoplurPerformance] \(message)")
        #endif
    }
}
