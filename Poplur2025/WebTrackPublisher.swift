import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

/// Decode a `publishTrack` bridge message from the studio and put the music
/// where the iPod can reach it: the audio in Storage, a row in `tracks/`.
///
/// WHY this is separate from `WebPostPublisher`: a track is not a post. A post
/// goes through PostUploadService with a channel, a caption and a map pin; a
/// track is a file plus the ground it was left on, and it lands in a different
/// collection under different rules. Routing music through the post pipeline
/// would have meant a track carrying a channelId it has no use for and showing
/// up in the feed, which is not where music lives.
///
/// It DOES reuse the post pipeline's three notifications — PostUploadProgress,
/// PostUploadSuccess, PostUploadFailed — because the web side already listens
/// for exactly those and forwards them as `poplur-upload-progress` /
/// `poplur-upload-result`. Inventing a second pair of events would have meant a
/// second forwarder to keep in step for no gain.
enum WebTrackPublisher {

    @MainActor
    static func handle(_ body: [String: Any]) {
        let requestID = body["requestId"] as? String

        /// Every failure must ANSWER the studio. It waits on the result event
        /// and has no other way to learn what happened, so a bare return is
        /// indistinguishable from a hang — the studio would sit on
        /// "Uploading…" until its own timeout and report nothing useful.
        func fail(_ message: String) {
            print("[WebTrackPublisher] publishTrack FAILED: \(message) requestId=\(requestID ?? "-")")
            var info: [String: Any] = ["message": message]
            if let requestID { info["requestId"] = requestID }
            NotificationCenter.default.post(
                name: Notification.Name("PostUploadFailed"), object: nil, userInfo: info
            )
        }

        func progress(_ fraction: Double, _ phase: String) {
            guard let requestID else { return }
            NotificationCenter.default.post(
                name: Notification.Name("PostUploadProgress"), object: nil,
                userInfo: ["requestId": requestID, "fraction": fraction, "phase": phase]
            )
        }

        guard let uid = Auth.auth().currentUser?.uid else {
            fail("Posting music needs you signed in to Poplur.")
            return
        }
        guard let source = body["data"] as? String, let audio = decodeDataURL(source) else {
            fail("That mix never reached the app.")
            return
        }
        // The bucket refuses anything over 25MB (storage.rules). Catching it
        // here means the artist is told why instead of watching an upload run
        // to completion and then be rejected.
        guard audio.count < 25 * 1024 * 1024 else {
            fail("That mix is too long to post — keep it under 25MB.")
            return
        }
        let title = ((body["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            fail("Give the track a name first.")
            return
        }
        guard let lat = body["latitude"] as? Double, let lng = body["longitude"] as? Double else {
            fail("Poplur could not tell where you are, and a track has to be left somewhere.")
            return
        }

        let trackID = UUID().uuidString
        let object = Storage.storage().reference(withPath: "music/\(uid)/\(trackID).wav")
        let meta = StorageMetadata()
        // storage.rules checks contentType on the way in, and the player trusts
        // it on the way out. Setting it explicitly rather than letting the SDK
        // guess from a path is what makes the upload pass its own rule.
        meta.contentType = "audio/wav"

        print("[WebTrackPublisher] publishTrack: \(audio.count) bytes, uid=\(uid), id=\(trackID)")
        progress(0.02, "PREPARING")

        let task = object.putData(audio, metadata: meta) { _, error in
            if let error {
                fail("The upload did not finish: \(error.localizedDescription)")
                return
            }
            progress(1, "SAVING")
            object.downloadURL { url, error in
                guard let url else {
                    fail("The track uploaded but Poplur could not get a link to it: \(error?.localizedDescription ?? "unknown")")
                    return
                }
                var row: [String: Any] = [
                    "userID": uid,
                    "title": title,
                    "audioURL": url.absoluteString,
                    "lat": lat,
                    "lng": lng,
                    // The rules require the SERVER's clock: "newest" must not be
                    // something a client can buy with a lie.
                    "createdAt": FieldValue.serverTimestamp(),
                    "createdAtMillis": Date().timeIntervalSince1970 * 1000,
                    "licence": (body["licence"] as? String) ?? "own-work"
                ]
                row["artist"] = Auth.auth().currentUser?.displayName ?? "Poplur artist"
                row["postedBy"] = uid
                if let genre = body["genre"] as? String, !genre.isEmpty { row["mood"] = genre.uppercased() }
                if let bpm = body["bpm"] as? Double { row["bpm"] = bpm }
                if let duration = body["duration"] as? Double { row["duration"] = duration }
                if let radiusKm = body["radiusKm"] as? Double { row["radiusKm"] = radiusKm }

                Firestore.firestore().collection("tracks").document(trackID).setData(row) { error in
                    if let error {
                        // The audio is in the bucket but nothing points at it.
                        // Take it back out rather than leaving an orphan nobody
                        // can reach and nobody is accounting for.
                        object.delete { _ in }
                        fail("The track could not be posted: \(error.localizedDescription)")
                        return
                    }
                    print("[WebTrackPublisher] posted track \(trackID)")
                    var info: [String: Any] = ["trackId": trackID]
                    if let requestID { info["requestId"] = requestID }
                    NotificationCenter.default.post(
                        name: Notification.Name("PostUploadSuccess"), object: nil, userInfo: info
                    )
                }
            }
        }

        task.observe(.progress) { snapshot in
            guard let p = snapshot.progress, p.totalUnitCount > 0 else { return }
            // Held under 1.0 on purpose: the Firestore write still has to land,
            // and a bar that reads 100% while the row is missing is a lie about
            // whether the track exists.
            let fraction = Double(p.completedUnitCount) / Double(p.totalUnitCount)
            progress(min(0.95, max(0.02, fraction)), "UPLOADING")
        }
    }

    /// `data:audio/wav;base64,...` → bytes.
    private static func decodeDataURL(_ value: String) -> Data? {
        guard let comma = value.firstIndex(of: ","),
              value[..<comma].lowercased().contains("base64") else { return nil }
        return Data(base64Encoded: String(value[value.index(after: comma)...]))
    }
}
