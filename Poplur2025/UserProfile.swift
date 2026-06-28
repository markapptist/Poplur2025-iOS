import Foundation
import FirebaseFirestore

struct UserProfile: Identifiable, Hashable, Codable {
    // Firestore document ID (user's uid)
    var id: String
    var username: String
    var email: String
    var displayName: String?
    // Stored as a string in Firestore; decoded to URL here for AsyncImage
    var profilePictureURL: URL?

    init(id: String, username: String, email: String, displayName: String? = nil, profilePictureURL: URL? = nil) {
        self.id = id
        self.username = username
        self.email = email
        self.displayName = displayName
        self.profilePictureURL = profilePictureURL
    }

    // Convenience initializer from Firestore document
    init?(document: DocumentSnapshot) {
        let data = document.data() ?? [:]
        guard let username = data["username"] as? String,
              let email = data["email"] as? String else {
            return nil
        }
        self.id = document.documentID
        self.username = username
        self.email = email
        self.displayName = (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let urlString = data["profilePictureURL"] as? String,
           let url = URL(string: urlString) {
            self.profilePictureURL = url
        } else {
            self.profilePictureURL = nil
        }
    }

    // Helper to serialize for Firestore writes
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "username": username,
            "email": email
        ]
        if let displayName {
            dict["displayName"] = displayName
        }
        if let url = profilePictureURL {
            dict["profilePictureURL"] = url.absoluteString
        }
        return dict
    }
}
