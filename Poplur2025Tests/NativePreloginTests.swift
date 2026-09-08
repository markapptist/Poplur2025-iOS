import Foundation
import Testing
@testable import Poplur2025

@MainActor
struct NativePreloginTests {
    let calendar = Calendar(identifier: .gregorian)
    func date(_ year: Int, _ month: Int = 9, _ day: Int = 8) -> Date { calendar.date(from: DateComponents(year: year, month: month, day: day))! }
    @Test func ageBoundaryAndRequiredConsent() {
        let now = date(2026)
        func check(_ birth: Date?, agreed: Bool = true) -> String? { NativePreloginModel.credentialsError(email: " person@example.com ", password: "secret1", confirmation: "secret1", birthday: birth, agreed: agreed, now: now, calendar: calendar) }
        #expect(check(date(2013)) == nil)
        #expect(check(date(2013, 9, 9)) != nil)
        #expect(check(nil) != nil)
        #expect(check(date(2000), agreed: false) != nil)
        #expect(check(date(2027)) != nil)
    }
    @Test func validationAndBackNavigation() {
        #expect(NativePreloginModel.credentialsError(email: "not-an-email", password: "secret", confirmation: "secret", birthday: date(2000), agreed: true) != nil)
        #expect(NativePreloginModel.credentialsError(email: "a@b.com", password: "secret", confirmation: "different", birthday: date(2000), agreed: true) != nil)
        let model = NativePreloginModel(restorePendingAccount: false)
        model.go(.photo); model.back(); #expect(model.step == .credentials)
        model.go(.review); model.back(); #expect(model.step == .verification)
        model.go(.intro); model.back(); #expect(model.step == .account)
        model.busy = true; model.back(); #expect(model.step == .account)
    }
    @Test func interruptedSignupResumesItsExistingAccount() {
        let model = NativePreloginModel(restorePendingAccount: false)
        let draft = NativePreloginDraft(email: "owner@example.com", accountType: .business, birthday: date(2000), gender: "", name: "Cafe", address: "Toronto", latitude: 43.65, longitude: -79.38, category: "Cafe", phone: "", proof: "Owner")
        model.restore(draft: draft, uid: "existing-account")
        #expect(model.hasCreatedAccount)
        #expect(model.step == .review)
        #expect(model.email == "owner@example.com")
        model.back()
        #expect(model.step == .review)
    }
    @Test func homeWaitsForProfileCompletion() {
        let auth = AuthViewModel(previewAuthenticated: true)
        #expect(auth.canEnterHome)
        auth.isCompletingOnboarding = true
        #expect(!auth.canEnterHome)
        auth.isCompletingOnboarding = false
        #expect(auth.canEnterHome)
    }
}
