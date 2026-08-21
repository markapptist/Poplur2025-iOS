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
    var accountType: PoplurAccountType
    var businessProfile: BusinessProfile?
    var followerCount: Int
    var followingCount: Int
    var verificationTier: PoplurVerificationTier
    var verificationStatus: PoplurVerificationApplicationStatus

    var isBusinessAccount: Bool {
        accountType == .business
    }

    var isVerifiedBusiness: Bool {
        businessProfile?.verificationStatus == .verified
    }

    var isVerifiedAccount: Bool {
        verificationTier == .verified
    }

    var isConfirmedAccount: Bool {
        verificationTier == .confirmed
    }

    var hasAnyVerification: Bool {
        verificationTier != .none || isVerifiedBusiness
    }

    var profileDisplayName: String {
        if let businessName = businessProfile?.businessName.trimmedForProfile, !businessName.isEmpty {
            return businessName
        }
        if let displayName = displayName?.trimmedForProfile, !displayName.isEmpty {
            return displayName
        }
        return username
    }

    init(
        id: String,
        username: String,
        email: String,
        displayName: String? = nil,
        profilePictureURL: URL? = nil,
        accountType: PoplurAccountType = .user,
        businessProfile: BusinessProfile? = nil,
        followerCount: Int = 0,
        followingCount: Int = 0,
        verificationTier: PoplurVerificationTier = .none,
        verificationStatus: PoplurVerificationApplicationStatus = .none
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.displayName = displayName
        self.profilePictureURL = profilePictureURL
        self.accountType = accountType
        self.businessProfile = businessProfile
        self.followerCount = followerCount
        self.followingCount = followingCount
        self.verificationTier = verificationTier
        self.verificationStatus = verificationStatus
    }

    // Convenience initializer from Firestore document
    init?(document: DocumentSnapshot) {
        let data = document.data() ?? [:]
        let username = (data["username"] as? String)
            ?? (data["handle"] as? String)
            ?? (data["email"] as? String)?.components(separatedBy: "@").first
            ?? document.documentID
        let email = data["email"] as? String ?? ""
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

        let rawAccountType = data["accountType"] as? String
        let nestedBusinessProfile = (data["businessProfile"] as? [String: Any]).flatMap(BusinessProfile.init(data:))
        let flatBusinessProfile = BusinessProfile(data: data)
        self.businessProfile = nestedBusinessProfile ?? flatBusinessProfile
        if let rawAccountType, let accountType = PoplurAccountType(rawValue: rawAccountType) {
            self.accountType = accountType
        } else {
            self.accountType = self.businessProfile == nil ? .user : .business
        }
        self.followerCount = data["followerCount"] as? Int ?? 0
        self.followingCount = data["followingCount"] as? Int ?? 0
        self.verificationTier = (data["verificationTier"] as? String).flatMap(PoplurVerificationTier.init(rawValue:)) ?? .none
        self.verificationStatus = (data["verificationStatus"] as? String).flatMap(PoplurVerificationApplicationStatus.init(rawValue:)) ?? .none
    }

    // Helper to serialize for Firestore writes
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "username": username,
            "email": email,
            "accountType": accountType.rawValue
        ]
        if let displayName {
            dict["displayName"] = displayName
        }
        if let url = profilePictureURL {
            dict["profilePictureURL"] = url.absoluteString
        }
        if let businessProfile {
            dict["businessProfile"] = businessProfile.toDictionary()
            dict["isBusinessAccount"] = true
            dict["isVerifiedBusiness"] = businessProfile.verificationStatus == .verified
        }
        if verificationTier != .none {
            dict["verificationTier"] = verificationTier.rawValue
        }
        if verificationStatus != .none {
            dict["verificationStatus"] = verificationStatus.rawValue
        }
        return dict
    }
}

private extension String {
    var trimmedForProfile: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
