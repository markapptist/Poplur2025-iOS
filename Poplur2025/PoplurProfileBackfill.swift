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

        func missing(_ key: String) -> Bool {
            let value = existing[key] as? String
            return value == nil || value?.isEmpty == true
        }

        if missing("profileSelfieVideoURL") { await backfillSelfieVideo(uid: uid, users: users) }
        if missing("profilePictureURL") { await backfillPhoto(uid: uid, users: users) }
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
            _ = try await reference.putDataAsync(data)
            let downloadURL = try await reference.downloadURL()
            try await users.setData(["profilePictureURL": downloadURL.absoluteString], merge: true)
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
            _ = try await reference.putDataAsync(data)
            let downloadURL = try await reference.downloadURL()
            try await users.setData(
                ["profileSelfieVideoURL": downloadURL.absoluteString],
                merge: true
            )
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
