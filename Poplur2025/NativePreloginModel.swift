import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import MapKit
import UIKit

struct NativePreloginDraft: Codable {
    var email: String
    var accountType: PoplurAccountType
    var birthday: Date
    var gender: String
    var name: String?
    var address: String?
    var latitude: Double?
    var longitude: Double?
    var category: String
    var phone: String
    var proof: String
    static let key = "poplur.nativeOnboarding.pending"
    static var saved: Self? { UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(Self.self, from: $0) } }
    static func isPending(email: String?) -> Bool { guard let email, let draft = saved else { return false }; return draft.email.lowercased() == email.lowercased() }
    static var photoURL: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("native-onboarding-photo.jpg") }
}

/// One owner for the signed-out flow. Firebase's early auth notification must not
/// reveal Home until all selected onboarding data has been saved successfully.
@MainActor
final class NativePreloginModel: ObservableObject {
    enum Step: String { case welcome, signIn, account, intro, credentials, business, verification, review, photo, gender }
    @Published var step: Step = .welcome
    @Published var accountType: PoplurAccountType = .user
    @Published var email = ""
    @Published var password = ""
    @Published var confirmation = ""
    @Published var birthday = Calendar.current.date(byAdding: .year, value: -18, to: Date())!
    @Published var birthdayChosen = false
    @Published var agreed = false
    @Published var photo: UIImage?
    @Published var gender = ""
    @Published var query = ""
    @Published var places: [MKMapItem] = []
    @Published var place: MKMapItem?
    @Published var businessCategory = ""
    @Published var contactPhone = ""
    @Published var proof = ""
    @Published var error: String?
    @Published var notice: String?
    @Published var busy = false
    @Published var searching = false
    private var createdUID: String?
    private var search: MKLocalSearch?
    var hasCreatedAccount: Bool { createdUID != nil }

    init(restorePendingAccount: Bool = true) {
        guard restorePendingAccount, !ProcessInfo.processInfo.arguments.contains("-UITestForceSignedOut") else { return }
        resumePendingAccount()
    }
    @discardableResult
    private func resumePendingAccount() -> Bool {
        guard FirebaseApp.app() != nil, let user = Auth.auth().currentUser, NativePreloginDraft.isPending(email: user.email), let draft = NativePreloginDraft.saved else { return false }
        restore(draft: draft, uid: user.uid)
        return true
    }
    func restore(draft: NativePreloginDraft, uid: String) {
        createdUID = uid; email = draft.email; accountType = draft.accountType
        birthday = draft.birthday; birthdayChosen = true; agreed = true; gender = draft.gender
        businessCategory = draft.category; contactPhone = draft.phone; proof = draft.proof
        if let latitude = draft.latitude, let longitude = draft.longitude {
            place = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), addressDictionary: ["FormattedAddressLines": [draft.address ?? ""]]))
            place?.name = draft.name
        }
        photo = UIImage(contentsOfFile: NativePreloginDraft.photoURL.path)
        step = accountType == .business ? .review : .gender
        error = "Finish saving your profile to continue to Poplur."
    }
    private func saveDraft() throws {
        let draft = NativePreloginDraft(email: email.trimmingCharacters(in: .whitespacesAndNewlines), accountType: accountType, birthday: birthday, gender: gender, name: place?.name, address: place?.placemark.title, latitude: place?.placemark.coordinate.latitude, longitude: place?.placemark.coordinate.longitude, category: businessCategory, phone: contactPhone, proof: proof)
        if let data = photo?.jpegData(compressionQuality: 0.82) { try data.write(to: NativePreloginDraft.photoURL, options: .atomic) } else { try? FileManager.default.removeItem(at: NativePreloginDraft.photoURL) }
        UserDefaults.standard.set(try JSONEncoder().encode(draft), forKey: NativePreloginDraft.key)
    }

    func go(_ next: Step) { guard !busy && createdUID == nil else { return }; error = nil; step = next }
    func back() {
        guard !busy && createdUID == nil else { return }
        let previous: Step
        switch step {
        case .welcome: return
        case .signIn, .account: previous = .welcome
        case .intro: previous = .account
        case .credentials: previous = .intro
        case .business, .photo: previous = .credentials
        case .verification: previous = .business
        case .review: previous = .verification
        case .gender: previous = .photo
        }
        go(previous)
    }
    static func credentialsError(email: String, password: String, confirmation: String, birthday: Date?, agreed: Bool, now: Date = Date(), calendar: Calendar = .current) -> String? {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, options: .regularExpression) == nil { return "Enter a valid email address." }
        if password.count < 6 { return "Use a password with at least 6 characters." }
        if password != confirmation { return "Your passwords do not match." }
        guard let birthday else { return "Choose your date of birth." }
        if birthday > now || (calendar.dateComponents([.year], from: birthday, to: now).year ?? 0) < 13 { return "You must be at least 13 years old to use Poplur." }
        if !agreed { return "Please agree to the Terms of Service to continue." }
        return nil
    }
    func advanceCredentials() {
        error = Self.credentialsError(email: email, password: password, confirmation: confirmation, birthday: birthdayChosen ? birthday : nil, agreed: agreed)
        if error == nil { go(accountType == .business ? .business : .photo) }
    }
    func searchPlaces() async {
        search?.cancel()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { places = []; return }
        searching = true; error = nil
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        let current = MKLocalSearch(request: request); search = current
        do { let response = try await current.start(); if search === current { places = response.mapItems; searching = false; if places.isEmpty { error = "No places found. Try the business name and city." } } }
        catch { if search === current { searching = false; self.error = error.localizedDescription } }
    }
    func signIn(auth: AuthViewModel, saveBiometricCredentials: Bool = false) async {
        guard !busy else { return }
        guard !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !password.isEmpty else { error = "Enter your email and password."; return }
        guard FirebaseApp.app() != nil else { error = "Sign-in is unavailable. Please reopen Poplur."; return }
        busy = true; error = nil; auth.isCompletingOnboarding = true
        defer { busy = false; auth.isCompletingOnboarding = NativePreloginDraft.isPending(email: Auth.auth().currentUser?.email) }
        do {
            let result = try await Auth.auth().signIn(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            PoplurNativeAnalytics.didLogin(uid: result.user.uid)
            if resumePendingAccount() { password = ""; confirmation = ""; return }
            if saveBiometricCredentials { _ = PoplurKeychain.saveCredentials(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password) }
            password = ""; confirmation = ""
        } catch { self.error = error.localizedDescription }
    }
    func resetPassword() async {
        guard !busy else { return }
        guard email.contains("@") else { error = "Enter your email address first."; return }
        guard FirebaseApp.app() != nil else { error = "Sign-in is unavailable. Please reopen Poplur."; return }
        busy = true; error = nil; defer { busy = false }
        do { try await Auth.auth().sendPasswordReset(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines)); notice = "If this email has an account, a password reset link will arrive shortly." }
        catch { self.error = error.localizedDescription }
    }
    func submit(auth: AuthViewModel) async {
        guard !busy else { return }
        if createdUID == nil {
            error = Self.credentialsError(email: email, password: password, confirmation: confirmation, birthday: birthdayChosen ? birthday : nil, agreed: agreed)
            guard error == nil else { return }
        }
        // The photo is OPTIONAL, and the save below already treats it that way
        // (`if let photo` at the upload). Requiring one here made a device with an
        // empty photo library unable to create an account at all - the picker is
        // the only source, there is no camera path and there was no skip. App
        // Review runs on exactly such a device, and could not get past this screen.
        if accountType == .user && !["male", "female"].contains(gender) { error = "Pick the clay head your cube wears."; return }
        if accountType == .business && (place == nil || businessCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || proof.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { error = "Choose your business, category, and verification details."; return }
        guard FirebaseApp.app() != nil else { error = "Sign-up is unavailable. Please reopen Poplur."; return }
        busy = true; error = nil; auth.isCompletingOnboarding = true
        defer { busy = false }
        do {
            try saveDraft()
            let uid: String
            if let createdUID { uid = createdUID }
            else {
                let result = try await Auth.auth().createUser(withEmail: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
                uid = result.user.uid; createdUID = uid
                PoplurNativeAnalytics.didSignUp(uid: uid)
            }
            var business: BusinessProfile?
            if accountType == .business, let place {
                var profile = BusinessProfile.empty
                profile.businessName = place.name ?? query
                profile.address = place.placemark.title ?? query
                profile.latitude = place.placemark.coordinate.latitude; profile.longitude = place.placemark.coordinate.longitude
                profile.category = businessCategory; profile.contactEmail = email; profile.contactPhone = contactPhone
                profile.website = place.url?.absoluteString ?? ""; profile.proofSummary = proof
                profile.verificationStatus = .pendingReview; profile.verificationMethods = [.officialEmailDomain]
                business = profile
            }
            try await BusinessAccountService.saveAccount(uid: uid, email: email, accountType: accountType, businessProfile: business, dateOfBirth: birthday)
            if let photo {
                let size = photo.size; let scale = min(1, 1024 / max(size.width, size.height))
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let normalized = UIGraphicsImageRenderer(size: CGSize(width: size.width * scale, height: size.height * scale), format: format).image { _ in photo.draw(in: CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)) }
                guard let data = normalized.jpegData(compressionQuality: 0.82), let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: documents.appendingPathComponent("profile.jpg"), options: .atomic)
                let reference = Storage.storage().reference().child("profile_pictures/\(uid).jpg")
                let metadata = StorageMetadata(); metadata.contentType = "image/jpeg"
                _ = try await reference.putDataAsync(data, metadata: metadata)
                let photoURL = try await reference.downloadURL()
                var updates = ["profilePictureURL": photoURL.absoluteString]
                if accountType == .user {
                    updates["profileGender"] = gender
                    UserDefaults.standard.set(gender, forKey: "poplur.nativeOnboarding.gender")
                    UserDefaults.standard.set(uid, forKey: "poplur.nativeOnboarding.uid")
                }
                try await Firestore.firestore().collection("users").document(uid).setData(updates, merge: true)
            }
            UserDefaults.standard.removeObject(forKey: NativePreloginDraft.key)
            try? FileManager.default.removeItem(at: NativePreloginDraft.photoURL)
            password = ""; confirmation = ""; auth.didSignUp = true
            auth.isCompletingOnboarding = false
        } catch {
            // A profile retry reuses the newly created UID, never creates a second
            // Firebase account and never exposes an incompletely saved business.
            self.error = createdUID == nil ? error.localizedDescription : "Your account was created, but your profile could not be saved. Tap Retry to finish. \(error.localizedDescription)"
            if createdUID == nil { UserDefaults.standard.removeObject(forKey: NativePreloginDraft.key); try? FileManager.default.removeItem(at: NativePreloginDraft.photoURL); auth.isCompletingOnboarding = false }
        }
    }
}
