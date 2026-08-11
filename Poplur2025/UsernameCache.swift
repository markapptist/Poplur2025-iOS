import Foundation
import FirebaseFirestore

struct CachedUserProfile: Sendable {
    let uid: String
    let displayName: String?
    let photoURL: URL?
}

/// A bounded, expiring profile cache. A single entry owns both the name and
/// photo so the two caches cannot independently grow for the lifetime of the
/// process.
actor UsernameCache {
    static let shared = UsernameCache()

    private struct CacheEntry {
        let profile: CachedUserProfile?
        let expiresAt: Date
        var lastAccess: UInt64
    }

    private struct InFlightRequest {
        let id: UUID
        let startedAt: UInt64
        let cacheGeneration: UInt64
        let task: Task<CachedUserProfile?, Never>
    }

    private static let maximumEntryCount = 256
    private static let maximumConcurrentRequests = 6
    private static let entryLifetime: TimeInterval = 30 * 60
    private static let failedLookupLifetime: TimeInterval = 60

    private var entries: [String: CacheEntry] = [:]
    private var inFlight: [String: InFlightRequest] = [:]
    private var accessCounter: UInt64 = 0
    private var requestCounter: UInt64 = 0
    private var cacheGeneration: UInt64 = 0
    private var earliestExpiration = Date.distantFuture

    func username(for uid: String) async -> String? {
        await profile(for: uid)?.displayName
    }

    func profile(for uid: String) async -> CachedUserProfile? {
        let normalizedUID = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUID.isEmpty else {
            print("UsernameCache: attempted to fetch profile for empty UID")
            return nil
        }

        while true {
            let now = Date()
            removeExpiredEntries(at: now)

            if var entry = entries[normalizedUID] {
                entry.lastAccess = nextAccessOrdinal()
                entries[normalizedUID] = entry
                return entry.profile
            }

            if let request = inFlight[normalizedUID] {
                let result = await request.task.value
                finish(request, for: normalizedUID, result: result)
                guard request.cacheGeneration == cacheGeneration else { continue }
                return result
            }

            if inFlight.count < Self.maximumConcurrentRequests {
                let request = makeRequest(for: normalizedUID)
                inFlight[normalizedUID] = request

                let result = await request.task.value
                finish(request, for: normalizedUID, result: result)
                guard request.cacheGeneration == cacheGeneration else { continue }
                return result
            }

            // Help retire the oldest request instead of allocating an
            // unbounded waiter queue. Actor reentrancy lets other completions
            // make progress while this await is suspended.
            guard let oldest = inFlight.min(by: { $0.value.startedAt < $1.value.startedAt }) else {
                continue
            }
            let result = await oldest.value.task.value
            finish(oldest.value, for: oldest.key, result: result)
        }
    }

    /// Prefetches with a bounded task group. The actor also enforces the same
    /// hard Firestore concurrency ceiling for direct callers.
    func prefetch(uids: [String]) async {
        await prefetchProfiles(uids: uids)
    }

    func prefetchProfiles(uids: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            var activeTasks = 0
            for rawUID in uids {
                let uid = rawUID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !uid.isEmpty else { continue }
                removeExpiredEntries(at: Date())
                guard entries[uid] == nil else { continue }

                if activeTasks == Self.maximumConcurrentRequests {
                    _ = await group.next()
                    activeTasks -= 1
                }
                group.addTask { _ = await self.profile(for: uid) }
                activeTasks += 1
            }

            while activeTasks > 0 {
                _ = await group.next()
                activeTasks -= 1
            }
        }
    }

    /// Releases all retained profiles and prevents requests that were already
    /// running from repopulating the cache after the purge.
    func purge() {
        entries.removeAll(keepingCapacity: false)
        earliestExpiration = .distantFuture
        cacheGeneration &+= 1
        // Keep canceled requests registered until their await completes. This
        // guarantees a purge cannot temporarily exceed the hard request cap.
        inFlight.values.forEach { $0.task.cancel() }
    }

    private func makeRequest(for uid: String) -> InFlightRequest {
        requestCounter &+= 1
        let task = Task<CachedUserProfile?, Never> {
            await Self.fetchProfileFromFirestore(uid: uid)
        }
        return InFlightRequest(
            id: UUID(),
            startedAt: requestCounter,
            cacheGeneration: cacheGeneration,
            task: task
        )
    }

    private func finish(
        _ request: InFlightRequest,
        for uid: String,
        result: CachedUserProfile?
    ) {
        guard inFlight[uid]?.id == request.id else { return }
        inFlight.removeValue(forKey: uid)
        guard request.cacheGeneration == cacheGeneration else { return }
        store(result, for: uid)
    }

    private func store(_ profile: CachedUserProfile?, for uid: String) {
        removeExpiredEntries(at: Date())
        if entries[uid] == nil, entries.count >= Self.maximumEntryCount,
           let leastRecent = entries.min(by: { $0.value.lastAccess < $1.value.lastAccess })?.key {
            entries.removeValue(forKey: leastRecent)
        }
        let expiresAt = Date().addingTimeInterval(
            profile == nil ? Self.failedLookupLifetime : Self.entryLifetime
        )
        entries[uid] = CacheEntry(
            profile: profile,
            expiresAt: expiresAt,
            lastAccess: nextAccessOrdinal()
        )
        earliestExpiration = min(earliestExpiration, expiresAt)
    }

    private func removeExpiredEntries(at date: Date) {
        guard date >= earliestExpiration else { return }
        entries = entries.filter { $0.value.expiresAt > date }
        earliestExpiration = entries.values.map(\.expiresAt).min() ?? .distantFuture
    }

    private func nextAccessOrdinal() -> UInt64 {
        accessCounter &+= 1
        return accessCounter
    }

    nonisolated private static func fetchProfileFromFirestore(uid: String) async -> CachedUserProfile? {
        do {
            let snapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
            guard let data = snapshot.data() else { return nil }

            let displayName = (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let username = (data["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = displayName?.isEmpty == false
                ? displayName
                : (username?.isEmpty == false ? username : nil)
            let photoURL = (data["photoURL"] as? String).flatMap(URL.init(string:))
            return CachedUserProfile(uid: uid, displayName: name, photoURL: photoURL)
        } catch {
            print("UsernameCache: profile fetch failed for \(uid): \(error.localizedDescription)")
            return nil
        }
    }
}
