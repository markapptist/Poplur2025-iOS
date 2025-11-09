import Foundation
import FirebaseFirestore

actor UsernameCache {
    static let shared = UsernameCache()

    private var cache: [String: String] = [:]          // uid -> username
    private var inFlight: [String: Task<String?, Never>] = [:]

    func username(for uid: String) async -> String? {
        if let cached = cache[uid] { return cached }
        if let task = inFlight[uid] {
            return await task.value
        }

        let task = Task<String?, Never> {
            defer { Task { await self.clearInFlight(for: uid) } }
            do {
                let snap = try await Firestore.firestore().collection("users").document(uid).getDocument()
                guard let data = snap.data(),
                      let username = data["username"] as? String,
                      !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }
                await store(username: username, for: uid)
                return username
            } catch {
                print("UsernameCache: fetch failed for \(uid): \(error.localizedDescription)")
                return nil
            }
        }
        inFlight[uid] = task
        return await task.value
    }

    private func store(username: String, for uid: String) {
        cache[uid] = username
    }

    private func clearInFlight(for uid: String) {
        inFlight.removeValue(forKey: uid)
    }
}
