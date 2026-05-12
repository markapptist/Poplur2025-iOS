import Foundation
import FirebaseFirestore

struct CachedUserProfile: Sendable {
    let uid: String
    let displayName: String?
    let photoURL: URL?
}

actor UsernameCache {
    static let shared = UsernameCache()

    private var cache: [String: String] = [:]          // uid -> username
    private var photoCache: [String: URL] = [:]            // uid -> photoURL
    private var inFlight: [String: Task<String?, Never>] = [:]
    private var profileInFlight: [String: Task<CachedUserProfile?, Never>] = [:]

    func username(for uid: String) async -> String? {
        // Guard against empty UIDs
        guard !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("UsernameCache: attempted to fetch username for empty UID")
            return nil
        }
        
        if let cached = cache[uid] { return cached }
        
        if let task = inFlight[uid] {
            return await task.value
        }

        let task = Task<String?, Never> {
            defer { Task { await self.clearInFlight(for: uid) } }
            do {
                let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
                guard let data = snap.data() else { return nil }
                // Prefer displayName; fall back to username
                let displayName = (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let username = (data["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = (displayName?.isEmpty == false ? displayName : (username?.isEmpty == false ? username : nil))
                if let name {
                    await store(username: name, for: uid)
                }
                // Also cache photoURL if present
                if let photoString = data["photoURL"] as? String, let url = URL(string: photoString) {
                    await store(photoURL: url, for: uid)
                }
                return name
            } catch {
                print("UsernameCache: fetch failed for \(uid): \(error.localizedDescription)")
                return nil
            }
        }
        inFlight[uid] = task
        return await task.value
    }
    
    /// Prefetch usernames for an array of UIDs (call this when posts load)
    func prefetch(uids: [String]) async {
        // Filter out already cached and empty UIDs
        let uncached = uids.filter { uid in
            !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && cache[uid] == nil
        }
        
        guard !uncached.isEmpty else { return }
        
        // Fetch all uncached usernames concurrently
        await withTaskGroup(of: Void.self) { group in
            for uid in uncached {
                group.addTask {
                    _ = await self.username(for: uid)
                }
            }
        }
    }
    
    func profile(for uid: String) async -> CachedUserProfile? {
        // Guard against empty UIDs
        guard !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("UsernameCache: attempted to fetch profile for empty UID")
            return nil
        }

        // Return from caches if available
        let cachedName = cache[uid]
        let cachedPhoto = photoCache[uid]
        if cachedName != nil || cachedPhoto != nil {
            return CachedUserProfile(uid: uid, displayName: cachedName, photoURL: cachedPhoto)
        }

        if let task = profileInFlight[uid] {
            return await task.value
        }

        let task = Task<CachedUserProfile?, Never> {
            defer { Task { await self.clearProfileInFlight(for: uid) } }
            do {
                let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
                guard let data = snap.data() else { return nil }
                let displayName = (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let username = (data["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let name = (displayName?.isEmpty == false ? displayName : (username?.isEmpty == false ? username : nil))
                let photoURL: URL? = {
                    if let photoString = data["photoURL"] as? String, let url = URL(string: photoString) { return url }
                    return nil
                }()
                if let name { await store(username: name, for: uid) }
                if let photoURL { await store(photoURL: photoURL, for: uid) }
                return CachedUserProfile(uid: uid, displayName: name, photoURL: photoURL)
            } catch {
                print("UsernameCache: profile fetch failed for \(uid): \(error.localizedDescription)")
                return nil
            }
        }
        profileInFlight[uid] = task
        return await task.value
    }
    
    func prefetchProfiles(uids: [String]) async {
        let uncached = uids.filter { uid in
            !uid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (cache[uid] == nil || photoCache[uid] == nil)
        }
        guard !uncached.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for uid in uncached {
                group.addTask {
                    _ = await self.profile(for: uid)
                }
            }
        }
    }

    private func store(username: String, for uid: String) {
        cache[uid] = username
    }

    private func store(photoURL: URL, for uid: String) {
        photoCache[uid] = photoURL
    }

    private func clearInFlight(for uid: String) {
        inFlight.removeValue(forKey: uid)
    }

    private func clearProfileInFlight(for uid: String) {
        profileInFlight.removeValue(forKey: uid)
    }
}
