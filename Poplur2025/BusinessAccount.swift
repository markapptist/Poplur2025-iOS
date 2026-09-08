import Foundation
import FirebaseFirestore

enum PoplurAccountType: String, Codable, Hashable {
    case user
    case business

    var title: String {
        switch self {
        case .user: return "User"
        case .business: return "Business"
        }
    }
}

enum PoplurVerificationTier: String, Codable, Hashable {
    case none
    case confirmed
    case verified
}

enum PoplurVerificationApplicationStatus: String, Codable, Hashable {
    case none
    case pending
    case approved
    case rejected
}

enum PoplurVerificationMethod: String, Codable, Hashable {
    case id
    case phone
    case manual
}

enum BusinessVerificationStatus: String, Codable, CaseIterable, Hashable {
    case notVerified = "not_verified"
    case pendingReview = "pending_review"
    case verified
    case rejected
    case needsMoreInfo = "needs_more_info"

    var title: String {
        switch self {
        case .notVerified: return "Not Verified"
        case .pendingReview: return "Pending Review"
        case .verified: return "Verified"
        case .rejected: return "Rejected"
        case .needsMoreInfo: return "Needs More Info"
        }
    }
}

enum BusinessVerificationMethod: String, Codable, CaseIterable, Identifiable, Hashable {
    case officialEmailDomain = "official_email_domain"
    case businessPhone = "business_phone"
    case businessLicense = "business_license"
    case governmentId = "government_id"
    case utilityOrBankStatement = "utility_or_bank_statement"
    case videoOrInPerson = "video_or_in_person"
    case thirdPartyPartner = "third_party_partner"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .officialEmailDomain: return "Official business email domain"
        case .businessPhone: return "Phone linked to the business"
        case .businessLicense: return "Business license or registration"
        case .governmentId: return "Government ID of owner/admin"
        case .utilityOrBankStatement: return "Utility bill or bank statement"
        case .videoOrInPerson: return "Video or in-person verification"
        case .thirdPartyPartner: return "Third-party partner verification"
        }
    }
}

struct BusinessProfile: Codable, Hashable {
    var businessName: String
    var category: String
    var description: String
    var address: String
    var latitude: Double
    var longitude: Double
    var contactEmail: String
    var contactPhone: String
    var website: String
    var logoPhotoNotes: String
    var verificationStatus: BusinessVerificationStatus
    var verificationMethods: [BusinessVerificationMethod]
    var proofSummary: String
    var rejectionReason: String?
    var requiresReverification: Bool

    static let empty = BusinessProfile(
        businessName: "",
        category: "",
        description: "",
        address: "",
        latitude: 43.6532,
        longitude: -79.3832,
        contactEmail: "",
        contactPhone: "",
        website: "",
        logoPhotoNotes: "",
        verificationStatus: .notVerified,
        verificationMethods: [],
        proofSummary: "",
        rejectionReason: nil,
        requiresReverification: false
    )

    init(
        businessName: String,
        category: String,
        description: String,
        address: String,
        latitude: Double,
        longitude: Double,
        contactEmail: String,
        contactPhone: String,
        website: String,
        logoPhotoNotes: String,
        verificationStatus: BusinessVerificationStatus,
        verificationMethods: [BusinessVerificationMethod],
        proofSummary: String,
        rejectionReason: String?,
        requiresReverification: Bool
    ) {
        self.businessName = businessName
        self.category = category
        self.description = description
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.contactEmail = contactEmail
        self.contactPhone = contactPhone
        self.website = website
        self.logoPhotoNotes = logoPhotoNotes
        self.verificationStatus = verificationStatus
        self.verificationMethods = verificationMethods
        self.proofSummary = proofSummary
        self.rejectionReason = rejectionReason
        self.requiresReverification = requiresReverification
    }

    init?(data: [String: Any]) {
        let name = (data["businessName"] as? String ?? data["name"] as? String ?? "").trimmed
        let category = (data["businessCategory"] as? String ?? data["category"] as? String ?? "").trimmed
        let address = (data["businessAddress"] as? String ?? data["address"] as? String ?? "").trimmed
        guard !name.isEmpty || !category.isEmpty || !address.isEmpty else { return nil }

        let geoPoint = data["location"] as? GeoPoint
        let latitude = (data["latitude"] as? Double)
            ?? (data["latitude"] as? NSNumber)?.doubleValue
            ?? geoPoint?.latitude
            ?? BusinessProfile.empty.latitude
        let longitude = (data["longitude"] as? Double)
            ?? (data["longitude"] as? NSNumber)?.doubleValue
            ?? geoPoint?.longitude
            ?? BusinessProfile.empty.longitude
        let rawStatus = data["verificationStatus"] as? String
        let methods = (data["verificationMethods"] as? [String] ?? [])
            .compactMap(BusinessVerificationMethod.init(rawValue:))

        self.init(
            businessName: name,
            category: category,
            description: data["businessDescription"] as? String ?? data["description"] as? String ?? "",
            address: address,
            latitude: latitude,
            longitude: longitude,
            contactEmail: data["contactEmail"] as? String ?? "",
            contactPhone: data["contactPhone"] as? String ?? "",
            website: data["website"] as? String ?? "",
            logoPhotoNotes: data["logoPhotoNotes"] as? String ?? "",
            verificationStatus: rawStatus.flatMap(BusinessVerificationStatus.init(rawValue:)) ?? .notVerified,
            verificationMethods: methods,
            proofSummary: data["proofSummary"] as? String ?? "",
            rejectionReason: data["rejectionReason"] as? String,
            requiresReverification: data["requiresReverification"] as? Bool ?? false
        )
    }

    var mapLocation: GeoPoint {
        GeoPoint(latitude: latitude, longitude: longitude)
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "businessName": businessName.trimmed,
            "businessCategory": category.trimmed,
            "businessDescription": description.trimmed,
            "businessAddress": address.trimmed,
            "latitude": latitude,
            "longitude": longitude,
            "location": mapLocation,
            "contactEmail": contactEmail.trimmed,
            "contactPhone": contactPhone.trimmed,
            "website": website.trimmed,
            "logoPhotoNotes": logoPhotoNotes.trimmed,
            "verificationStatus": verificationStatus.rawValue,
            "verificationStatusLabel": verificationStatus.title,
            "verificationMethods": verificationMethods.map(\.rawValue),
            "verificationMethodLabels": verificationMethods.map(\.title),
            "proofSummary": proofSummary.trimmed,
            "requiresReverification": requiresReverification,
            "mapVisibility": true,
            "markerType": verificationStatus == .verified ? "verified_business_profile" : "business_profile"
        ]
        if let rejectionReason, !rejectionReason.trimmed.isEmpty {
            dict["rejectionReason"] = rejectionReason.trimmed
        }
        return dict
    }
}

enum BusinessAccountService {
    static func saveAccount(
        uid: String,
        email: String,
        accountType: PoplurAccountType,
        businessProfile: BusinessProfile?,
        dateOfBirth: Date? = nil
    ) async throws {
        let db = Firestore.firestore()
        let username = email.usernameFallback
        var userDocument: [String: Any] = [
            "accountType": accountType.rawValue,
            "email": email.trimmed,
            "username": username,
            "displayName": accountType == .business ? (businessProfile?.businessName.trimmed ?? username) : username,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ]

        if let dateOfBirth {
            userDocument["dateOfBirth"] = Timestamp(date: dateOfBirth)
        }

        if let businessProfile {
            let businessData = businessProfile.toDictionary()
            userDocument["businessProfile"] = businessData
            userDocument["businessName"] = businessProfile.businessName.trimmed
            userDocument["businessCategory"] = businessProfile.category.trimmed
            userDocument["businessAddress"] = businessProfile.address.trimmed
            userDocument["businessLocation"] = businessProfile.mapLocation
            userDocument["isBusinessAccount"] = true
            userDocument["isVerifiedBusiness"] = businessProfile.verificationStatus == .verified
        }

        try await setData(userDocument, at: db.collection("users").document(uid), merge: true)

        guard let businessProfile else { return }
        var businessDocument = businessProfile.toDictionary()
        businessDocument["ownerUserID"] = uid
        businessDocument["ownerUserId"] = uid
        businessDocument.removeValue(forKey: "proofSummary")
        businessDocument.removeValue(forKey: "rejectionReason")
        businessDocument["email"] = email.trimmed
        businessDocument["accountType"] = PoplurAccountType.business.rawValue
        businessDocument["updatedAt"] = FieldValue.serverTimestamp()
        businessDocument["submittedAt"] = FieldValue.serverTimestamp()
        try await setData(businessDocument, at: db.collection("businesses").document(uid), merge: true)
    }

    static func updateBusinessProfile(uid: String, businessProfile: BusinessProfile) async throws {
        let db = Firestore.firestore()
        var businessData = businessProfile.toDictionary()
        businessData["ownerUserID"] = uid
        businessData["accountType"] = PoplurAccountType.business.rawValue
        businessData["updatedAt"] = FieldValue.serverTimestamp()

        let userUpdates: [String: Any] = [
            "accountType": PoplurAccountType.business.rawValue,
            "displayName": businessProfile.businessName.trimmed,
            "businessProfile": businessData,
            "businessName": businessProfile.businessName.trimmed,
            "businessCategory": businessProfile.category.trimmed,
            "businessAddress": businessProfile.address.trimmed,
            "businessLocation": businessProfile.mapLocation,
            "isBusinessAccount": true,
            "isVerifiedBusiness": businessProfile.verificationStatus == .verified,
            "requiresReverification": businessProfile.requiresReverification,
            "updatedAt": FieldValue.serverTimestamp()
        ]

        try await setData(userUpdates, at: db.collection("users").document(uid), merge: true)
        // Ownership proof belongs in the private users document. The public
        // business record uses the collection and owner key enforced by rules.
        businessData["ownerUserId"] = uid
        businessData.removeValue(forKey: "proofSummary")
        businessData.removeValue(forKey: "rejectionReason")
        try await setData(businessData, at: db.collection("businesses").document(uid), merge: true)
    }

    private static func setData(_ data: [String: Any], at document: DocumentReference, merge: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.setData(data, merge: merge) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var usernameFallback: String {
        let localPart = trimmed.components(separatedBy: "@").first ?? trimmed
        let cleaned = localPart
            .replacingOccurrences(of: " ", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }
        return cleaned.isEmpty ? "poplur_user" : cleaned
    }
}
