import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

/// Lifts a device-local profile up to the account.
///
/// The profile selfie is written to the Documents directory first and uploaded
/// second, and the upload only ever ran at the MOMENT of setting. So a selfie
/// set before the upload worked — or while the Storage rules still denied
/// `profile_selfies/`, which they did until 2026-08-20 — stayed on that one
/// phone forever. It looked correct on the device that captured it and was
/// simply absent everywhere else, because it had never left.
///
/// This closes that gap on every launch: if the device holds a selfie and the
/// account does not, send it up. Cheap to run, and it self-heals rather than
/// depending on somebody remembering to re-record.
/// What an upload must declare about itself.
///
/// Storage labels an unlabelled upload `application/octet-stream`, and the
/// Storage rules gate `profile_pictures` on `image/.*` and `profile_selfies` on
/// `video/.*`. So an upload with no metadata is refused no matter who is signed
/// in — which is why opening these paths in the rules did not, on its own, make
/// a profile picture or selfie reach the account.
enum PoplurProfileUpload {
    static func imageMetadata() -> StorageMetadata {
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        return metadata
    }

    static func videoMetadata(forExtension ext: String) -> StorageMetadata {
        let metadata = StorageMetadata()
        // Keyed off the extension the store actually persisted, so a .mov is
        // not mislabelled as mp4 to whoever plays it back.
        switch ext.lowercased() {
        case "mov": metadata.contentType = "video/quicktime"
        case "m4v": metadata.contentType = "video/x-m4v"
        default: metadata.contentType = "video/mp4"
        }
        return metadata
    }
}

enum PoplurProfileBackfill {
    /// Guards against a second pass inside one app run — the launch path can
    /// fire more than once, and the upload is not free.
    private static var ranThisLaunch = false

    static func run() {
        guard !ranThisLaunch else { return }
        ranThisLaunch = true
        Task {
            // One document read serves both, and neither should block the
            // other: a phone can easily have a photo synced and a video not.
            await backfill()
        }
    }

    private static func backfill() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let users = Firestore.firestore().collection("users").document(uid)
        let existing = (try? await users.getDocument())?.data() ?? [:]

        guard existing["profileMediaRemoved"] as? Bool != true else { return }

        func missing(_ key: String) -> Bool {
            let value = existing[key] as? String
            return value == nil || value?.isEmpty == true
        }

        if missing("profileSelfieVideoURL") { await backfillSelfieVideo(uid: uid, users: users) }
        if missing("profilePictureURL") { await backfillPhoto(uid: uid, users: users) }
    }

    private static func saveUnlessRemoved(users: DocumentReference, field: String, url: String) async throws {
        _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let data = try transaction.getDocument(users).data() ?? [:]
                guard data["profileMediaRemoved"] as? Bool != true,
                      (data[field] as? String)?.isEmpty != false else { return nil }
                transaction.setData([field: url], forDocument: users, merge: true)
            } catch { errorPointer?.pointee = error as NSError }
            return nil
        }
    }

    /// The profile photo has the identical shape to the selfie: written to
    /// Documents first, uploaded second, so one set before the upload worked
    /// never left the device either.
    private static func backfillPhoto(uid: String, users: DocumentReference) async {
        let localURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile.jpg")
        guard FileManager.default.fileExists(atPath: localURL.path) else { return }
        do {
            let data = try Data(contentsOf: localURL)
            guard !data.isEmpty else { return }
            let reference = Storage.storage().reference().child("profile_pictures/\(uid).jpg")
            _ = try await reference.putDataAsync(data, metadata: PoplurProfileUpload.imageMetadata())
            let downloadURL = try await reference.downloadURL()
            try await saveUnlessRemoved(users: users, field: "profilePictureURL", url: downloadURL.absoluteString)
            PoplurDiagLog.append("[PoplurProfile] backfilled photo for \(uid.prefix(8))")
        } catch {
            PoplurDiagLog.append("[PoplurProfile] photo backfill FAILED: \(error.localizedDescription)")
        }
    }

    private static func backfillSelfieVideo(uid: String, users: DocumentReference) async {
        // Nothing local to lift.
        guard let ext = PoplurProfileSelfieStore.extensionForPersistedVideo() else { return }
        let localURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("profile-selfie.\(ext)")
        guard FileManager.default.fileExists(atPath: localURL.path) else { return }

        do {
            let data = try Data(contentsOf: localURL)
            guard !data.isEmpty else { return }
            let reference = Storage.storage().reference()
                .child("profile_selfies/\(uid).\(ext)")
            _ = try await reference.putDataAsync(
                data,
                metadata: PoplurProfileUpload.videoMetadata(forExtension: ext)
            )
            let downloadURL = try await reference.downloadURL()
            try await saveUnlessRemoved(users: users, field: "profileSelfieVideoURL", url: downloadURL.absoluteString)
            // Written to the diag log, not `print`: the original upload failed
            // silently for weeks precisely because its only report went to
            // stdout, where a device pull never sees it.
            PoplurDiagLog.append("[PoplurProfile] backfilled selfie video for \(uid.prefix(8))")
        } catch {
            PoplurDiagLog.append(
                "[PoplurProfile] selfie backfill FAILED: \(error.localizedDescription)"
            )
        }
    }
}
