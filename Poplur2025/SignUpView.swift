import SwiftUI
import FirebaseAuth
import MapKit
import PhotosUI
import SceneKit

struct SignUpView: View {
    // Carousel mode: parent manages background, confetti, and AI guide.
    var isCarousel: Bool = false
    var onBack: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var stripeCoordinator: StripeTransitionCoordinator
    @State private var accountType: PoplurAccountType?
    @State private var signupStep: SignupStep = .accountType
    @State private var cubeSpinToken = 0
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""

    @State private var businessName = ""
    @State private var businessCategory = ""
    @State private var businessDescription = ""
    @State private var businessAddress = ""
    @State private var latitudeText = "43.6532"
    @State private var longitudeText = "-79.3832"
    @State private var contactEmail = ""
    @State private var contactPhone = ""
    @State private var website = ""
    @State private var logoPhotoNotes = ""
    @State private var selectedLogoItems: [PhotosPickerItem] = []

    @State private var verificationRequested = false
    @State private var acceptedVerificationTerms = false
    @State private var selectedVerificationMethods: Set<BusinessVerificationMethod> = []
    @State private var proofSummary = ""
    @State private var verificationStatus: BusinessVerificationStatus = .notVerified
    @State private var rejectionReason: String?

    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var isSignedUp = false
    @FocusState private var focusedField: Field?

    private enum SignupStep: Int, CaseIterable {
        case accountType
        case account
        case businessProfile
        case verification
        case review

        var title: String {
            switch self {
            case .accountType: return "Choose Account"
            case .account: return "Create Login"
            case .businessProfile: return "Business Profile"
            case .verification: return "Verify Business"
            case .review: return "Review & Submit"
            }
        }

        var cubeIcon: String {
            switch self {
            case .accountType: return "person.2.fill"
            case .account: return "lock.fill"
            case .businessProfile: return "storefront.fill"
            case .verification: return "checkmark.seal.fill"
            case .review: return "paperplane.fill"
            }
        }
    }

    private enum Field {
        case email
        case password
        case confirmPassword
        case businessName
        case businessCategory
        case businessDescription
        case businessAddress
        case contactEmail
        case contactPhone
        case website
        case logoPhotoNotes
        case proofSummary
    }

    var body: some View {
        if isCarousel {
            signUpContent
        } else {
            NavigationStack {
                signUpContent
                    .navigationDestination(isPresented: $isSignedUp) {
                        HomeView()
                            .toolbar(.hidden, for: .navigationBar)
                            .navigationBarBackButtonHidden(true)
                    }
            }
        }
    }

    @ViewBuilder private var signUpContent: some View {
        ZStack {
            // In carousel mode the parent WelcomeView provides the bg and confetti.
            if !isCarousel {
                Color.white.ignoresSafeArea()
                AuthConfettiBackground()
            }

            if signupStep == .accountType {
                accountTypeCarouselPage
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                        signupCube
                        signupStepContent
                        walkthroughControls
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 28)
                    .padding(.bottom, 44)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .errorBanner($errorMessage)
        .onTapGesture { hideKeyboard() }
        .overlay(alignment: .bottom) {
            // In carousel mode the parent WelcomeView's unified guide handles the greeting.
            if !isCarousel {
                AuthAIGuide(screen: .signUp)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Floating Poplur logo
            HStack {
                Spacer()
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                Spacer()
            }
            .padding(.bottom, 4)

            HStack {
                Button {
                    if let onBack { onBack() } else { dismiss() }
                } label: {
                    Image(systemName: "chevron.left")
                        .poplurIconShader()
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(.black)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(Color.black.opacity(0.06)))
                }
                .buttonStyle(.plain)

                Spacer()
            }

            Text("Create your Poplur account")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .poplurTextShader(intensity: 0.9)

            Text(signupSubtitle)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.black.opacity(0.58))
        }
    }

    private var signupSubtitle: String {
        switch signupStep {
        case .accountType:
            return "Choose a personal user account or a verified business account."
        case .account:
            return accountType == .business ? "Create the login for the business admin account." : "Create your login, then continue with normal user onboarding."
        case .businessProfile:
            return "Attach the business to a real map location and add its public details."
        case .verification:
            return "Request verification and submit proof so Poplur can review the business."
        case .review:
            return accountType == .business ? "Confirm the request before submitting the business for review." : "Create your account."
        }
    }

    /// The first signup step is a single carousel page. The two flexible gaps are peers, so the
    /// account choices remain visually centered between the logo and the navigation cube across
    /// compact and tall phones instead of drifting toward either edge.
    private var accountTypeCarouselPage: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 88, height: 88)
                        .accessibilityLabel("Poplur")

                    Spacer(minLength: 22)

                    accountTypeCarouselUnit

                    Spacer(minLength: 22)

                    accountTypeNavigationCube
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }

    private var accountTypeCarouselUnit: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(0..<SignupStep.allCases.count, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(index == signupStep.rawValue ? Color.white : Color.white.opacity(0.42))
                            .frame(width: index == signupStep.rawValue ? 18 : 7, height: 7)
                    }
                }

                Text("1 / \(SignupStep.allCases.count)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.82))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step 1 of \(SignupStep.allCases.count)")

            Text("Choose Account")
                .font(.system(size: 27, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .poplurTextShader(intensity: 0.9)

            Text("Personal user account, or a verified business account.")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.82))
                .multilineTextAlignment(.center)

            accountTypeSelection
                .padding(.top, 2)
        }
        .frame(maxWidth: 430)
    }

    private var accountTypeNavigationCube: some View {
        LoginCubeView(
            onBack: { if let onBack { onBack() } else { dismiss() } },
            onForward: advanceSignupStep
        )
        .frame(width: 132, height: 132)
        .accessibilityLabel("Swipe between check and back, then tap to continue or go back")
    }

    private var signupCube: some View {
        HStack {
            Spacer()
            LoginCubeView(
                onTap: {
                    switch signupStep {
                    case .accountType:
                        if let onBack { onBack() } else { dismiss() }
                    default:
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                            errorMessage = nil
                            signupStep = previousStep(before: signupStep)
                        }
                    }
                }
            )
            .frame(width: 200, height: 200)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var signupStepContent: some View {
        switch signupStep {
        case .accountType:
            accountTypeSelection
        case .account:
            accountForm
        case .businessProfile:
            businessProfileSection
        case .verification:
            verificationSection
        case .review:
            reviewStatusSection
        }
    }

    private var walkthroughControls: some View {
        HStack(spacing: 12) {
            if signupStep == .accountType {
                Spacer()
                accountTypeNavigationCube
                Spacer()
            } else {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                        errorMessage = nil
                        signupStep = previousStep(before: signupStep)
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.black.opacity(0.72))

                Spacer()

                Button(action: advanceSignupStep) {
                    HStack(spacing: 10) {
                        if isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: nextActionIcon)
                                .poplurIconShader()
                        }
                        Text(nextActionTitle)
                    }
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(DS.Color.accent))
                    .shadow(color: DS.Color.accent.opacity(0.30), radius: 10, x: 0, y: 5)
                }
                .disabled(isLoading)
            }
        }
    }

    private var nextActionTitle: String {
        if signupStep == .review || (signupStep == .account && accountType == .user) {
            return accountType == .business ? "Submit" : "Create"
        }
        return "Continue"
    }

    private var nextActionIcon: String {
        if signupStep == .review || (signupStep == .account && accountType == .user) {
            return accountType == .business ? "checkmark.seal.fill" : "person.crop.circle.badge.plus"
        }
        return "arrow.right.circle.fill"
    }

    private var accountTypeSelection: some View {
        VStack(spacing: 14) {
            accountTypeCard(
                title: "Personal",
                subtitle: "Personal profile, normal onboarding, post as yourself.",
                type: .user
            )
            accountTypeCard(
                title: "Business",
                subtitle: "Business profile, map location, verification, badges, and business-only features.",
                type: .business
            )
        }
    }

    private func accountTypeCard(title: String, subtitle: String, type: PoplurAccountType) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                accountType = type
                if type == .business, contactEmail.isEmpty {
                    contactEmail = email
                }
                errorMessage = nil
                cubeSpinToken += 1
            }
        } label: {
            HStack(spacing: 14) {
                SignupAccount3DIcon(kind: type == .business ? .building : .profile)
                    .frame(width: 52, height: 52)
                    .background(
                        type == .business ? DS.Color.pinkCard : Color(red: 0.87, green: 0.97, blue: 0.88),
                        in: Circle()
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(DS.Font.heading(22))
                        .foregroundStyle(DS.Color.textPrimary)
                        .poplurTextShader(intensity: 0.9)
                    Text(subtitle)
                        .font(DS.Font.caption())
                        .foregroundStyle(DS.Color.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: accountType == type ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(DS.Color.accent)
            }
            .padding(18)
            .poplurCard()
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                    .stroke(
                        accountType == type ? DS.Color.accent.opacity(0.75) : DS.Color.textSecondary.opacity(0.25),
                        lineWidth: accountType == type ? 2 : 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var accountForm: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                    accountType = nil
                    signupStep = .accountType
                    errorMessage = nil
                }
            } label: {
                Label("Change account type", systemImage: "arrow.left")
                    .font(.system(size: 13, weight: .black, design: .rounded))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black.opacity(0.72))

            sectionPanel(title: "Account") {
                formTextField("Email", text: $email, field: .email, keyboardType: .emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                secureField("Password", text: $password, field: .password)
                secureField("Confirm password", text: $confirmPassword, field: .confirmPassword)
            }
        }
    }

    private var businessProfileSection: some View {
        sectionPanel(title: "Create Business Profile") {
            formTextField("Business name", text: $businessName, field: .businessName)
            formTextField("Business category", text: $businessCategory, field: .businessCategory)
            multilineField("Description", text: $businessDescription, field: .businessDescription, minHeight: 92)
            formTextField("Address / location on map", text: $businessAddress, field: .businessAddress)

            HStack(spacing: 10) {
                formTextField("Latitude", text: $latitudeText, field: .businessAddress, keyboardType: .decimalPad)
                formTextField("Longitude", text: $longitudeText, field: .businessAddress, keyboardType: .numbersAndPunctuation)
            }

            businessMapPreview

            formTextField("Contact email", text: $contactEmail, field: .contactEmail, keyboardType: .emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            formTextField("Contact phone", text: $contactPhone, field: .contactPhone, keyboardType: .phonePad)
            formTextField("Website", text: $website, field: .website, keyboardType: .URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            PhotosPicker(selection: $selectedLogoItems, maxSelectionCount: 8, matching: .images) {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .poplurIconShader()
                    Text(selectedLogoItems.isEmpty ? "Add logo/photos" : "\(selectedLogoItems.count) logo/photo item\(selectedLogoItems.count == 1 ? "" : "s") selected")
                    Spacer()
                    Image(systemName: "plus.circle.fill")
                }
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
            }

            multilineField("Logo/photo notes", text: $logoPhotoNotes, field: .logoPhotoNotes, minHeight: 70)
        }
    }

    private var businessMapPreview: some View {
        let coordinate = CLLocationCoordinate2D(
            latitude: latitudeValue ?? BusinessProfile.empty.latitude,
            longitude: longitudeValue ?? BusinessProfile.empty.longitude
        )
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )

        return Map(position: .constant(.region(region))) {
            Marker(businessName.isEmpty ? "Business location" : businessName, coordinate: coordinate)
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 164)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.12), lineWidth: 1)
        )
    }

    private var verificationSection: some View {
        sectionPanel(title: "Request Verification") {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
                    verificationRequested = true
                    verificationStatus = .pendingReview
                }
            } label: {
                Label(verificationRequested ? "Verification Requested" : "Verify My Business", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(DS.Color.accent))
            }
            .buttonStyle(.plain)

            if verificationRequested {
                Toggle(isOn: $acceptedVerificationTerms) {
                    Text("I agree that major changes to name, address, or ownership can trigger re-verification.")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black.opacity(0.68))
                }
                .toggleStyle(.switch)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Choose proof methods")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.black.opacity(0.7))

                    ForEach(BusinessVerificationMethod.allCases) { method in
                        Toggle(isOn: binding(for: method)) {
                            Text(method.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.black)
                        }
                        .toggleStyle(.checkboxLike)
                    }
                }

                multilineField("Submit proof details", text: $proofSummary, field: .proofSummary, minHeight: 110)
            }
        }
    }

    private var reviewStatusSection: some View {
        sectionPanel(title: "Review Process") {
            VStack(alignment: .leading, spacing: 10) {
                FlowLayout(spacing: 8) {
                    ForEach(BusinessVerificationStatus.allCases, id: \.self) { status in
                        Text(status.title)
                            .font(.system(size: 11, weight: .black, design: .rounded))
                            .foregroundStyle(status == verificationStatus ? Color.white : Color.black.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                Capsule()
                                    .fill(status == verificationStatus ? statusColor(status) : Color.black.opacity(0.06))
                            )
                    }
                }

                Text("Approved businesses get a verified badge and business-only features. Rejected submissions show the reason and can be resubmitted.")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.6))

                if verificationStatus == .rejected {
                    Text(rejectionReason ?? "Verification was rejected. Update your proof and resubmit.")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.red)
                }
            }
        }
    }

    private func sectionPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(DS.Font.heading(18))
                .foregroundStyle(DS.Color.textPrimary)
            content()
        }
        .padding(18)
        .poplurCard()
    }

    private func formTextField(
        _ placeholder: String,
        text: Binding<String>,
        field: Field,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        TextField(placeholder, text: text)
            .focused($focusedField, equals: field)
            .keyboardType(keyboardType)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(DS.Color.textPrimary)
            .tint(DS.Color.accent)
            .padding(14)
            .background(DS.Color.fill, in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                    .stroke(DS.Color.border, lineWidth: 1)
            )
    }

    private func secureField(_ placeholder: String, text: Binding<String>, field: Field) -> some View {
        SecureField(placeholder, text: text)
            .focused($focusedField, equals: field)
            .textContentType(.oneTimeCode)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(DS.Color.textPrimary)
            .tint(DS.Color.accent)
            .padding(14)
            .background(DS.Color.fill, in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                    .stroke(DS.Color.border, lineWidth: 1)
            )
    }

    private func multilineField(_ placeholder: String, text: Binding<String>, field: Field, minHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Color.textSecondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
            }
            TextEditor(text: text)
                .focused($focusedField, equals: field)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(DS.Color.textPrimary)
                .tint(DS.Color.accent)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: minHeight)
        }
        .background(DS.Color.fill, in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                .stroke(DS.Color.border, lineWidth: 1)
        )
    }

    private func binding(for method: BusinessVerificationMethod) -> Binding<Bool> {
        Binding {
            selectedVerificationMethods.contains(method)
        } set: { isSelected in
            if isSelected {
                selectedVerificationMethods.insert(method)
            } else {
                selectedVerificationMethods.remove(method)
            }
        }
    }

    private var latitudeValue: Double? {
        Double(latitudeText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var longitudeValue: Double? {
        Double(longitudeText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func submit() {
        hideKeyboard()
        guard let accountType else { return }
        guard validate(accountType: accountType) else { return }

        isLoading = true
        errorMessage = nil

        Auth.auth().createUser(withEmail: email.trimmedForSignup, password: password) { result, error in
            if let error {
                isLoading = false
                errorMessage = error.localizedDescription
                return
            }

            guard let uid = result?.user.uid else {
                isLoading = false
                errorMessage = "Could not create your account. Please try again."
                return
            }

            Task {
                do {
                    try await BusinessAccountService.saveAccount(
                        uid: uid,
                        email: email.trimmedForSignup,
                        accountType: accountType,
                        businessProfile: accountType == .business ? buildBusinessProfile() : nil
                    )
                    await MainActor.run {
                        isLoading = false
                        isSignedUp = true
                        auth.didSignUp = true
                    }
                } catch {
                    await MainActor.run {
                        isLoading = false
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func advanceSignupStep() {
        hideKeyboard()
        guard !isLoading else { return }
        errorMessage = nil

        switch signupStep {
        case .accountType:
            guard accountType != nil else {
                errorMessage = "Choose User or Business to continue."
                return
            }
            animateCubeAdvance(to: .account)
        case .account:
            guard validateAccountFields() else { return }
            if accountType == .business {
                animateCubeAdvance(to: .businessProfile)
            } else {
                submit()
            }
        case .businessProfile:
            guard validateBusinessProfileFields() else { return }
            animateCubeAdvance(to: .verification)
        case .verification:
            guard validateVerificationFields() else { return }
            animateCubeAdvance(to: .review)
        case .review:
            submit()
        }
    }

    private func animateCubeAdvance(to nextStep: SignupStep) {
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            cubeSpinToken += 1
            signupStep = nextStep
        }
    }

    private func previousStep(before step: SignupStep) -> SignupStep {
        switch step {
        case .accountType, .account:
            return .accountType
        case .businessProfile:
            return .account
        case .verification:
            return .businessProfile
        case .review:
            return accountType == .business ? .verification : .account
        }
    }

    private func validate(accountType: PoplurAccountType) -> Bool {
        guard validateAccountFields() else { return false }
        guard accountType == .business else { return true }
        guard validateBusinessProfileFields() else { return false }
        guard validateVerificationFields() else { return false }
        return true
    }

    private func validateAccountFields() -> Bool {
        guard !email.trimmedForSignup.isEmpty, !password.isEmpty else {
            errorMessage = "Enter an email and password."
            return false
        }
        guard password == confirmPassword else {
            errorMessage = "Passwords do not match."
            return false
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return false
        }
        return true
    }

    private func validateBusinessProfileFields() -> Bool {
        guard !businessName.trimmedForSignup.isEmpty,
              !businessCategory.trimmedForSignup.isEmpty,
              !businessAddress.trimmedForSignup.isEmpty else {
            errorMessage = "Add your business name, category, and map address."
            return false
        }
        guard latitudeValue != nil, longitudeValue != nil else {
            errorMessage = "Enter a valid latitude and longitude for the business map location."
            return false
        }
        guard !contactEmail.trimmedForSignup.isEmpty || !contactPhone.trimmedForSignup.isEmpty else {
            errorMessage = "Add a business contact email or phone number."
            return false
        }
        return true
    }

    private func validateVerificationFields() -> Bool {
        guard verificationRequested, acceptedVerificationTerms else {
            errorMessage = "Tap Verify My Business and agree to the verification terms."
            return false
        }
        guard !selectedVerificationMethods.isEmpty else {
            errorMessage = "Choose at least one verification method."
            return false
        }
        guard !proofSummary.trimmedForSignup.isEmpty else {
            errorMessage = "Submit proof details for review."
            return false
        }
        return true
    }

    private func buildBusinessProfile() -> BusinessProfile {
        let photoNote = selectedLogoItems.isEmpty ? logoPhotoNotes : "\(logoPhotoNotes)\nSelected logo/photo items: \(selectedLogoItems.count)"
        return BusinessProfile(
            businessName: businessName.trimmedForSignup,
            category: businessCategory.trimmedForSignup,
            description: businessDescription.trimmedForSignup,
            address: businessAddress.trimmedForSignup,
            latitude: latitudeValue ?? BusinessProfile.empty.latitude,
            longitude: longitudeValue ?? BusinessProfile.empty.longitude,
            contactEmail: contactEmail.trimmedForSignup,
            contactPhone: contactPhone.trimmedForSignup,
            website: website.trimmedForSignup,
            logoPhotoNotes: photoNote.trimmedForSignup,
            verificationStatus: .pendingReview,
            verificationMethods: Array(selectedVerificationMethods),
            proofSummary: proofSummary.trimmedForSignup,
            rejectionReason: rejectionReason,
            requiresReverification: false
        )
    }

    private func statusColor(_ status: BusinessVerificationStatus) -> Color {
        switch status {
        case .notVerified: return .gray
        case .pendingReview: return .orange
        case .verified: return .green
        case .rejected: return .red
        case .needsMoreInfo: return .blue
        }
    }

    private func hideKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct SignupAccount3DIcon: UIViewRepresentable {
    enum Kind { case profile, building }
    let kind: Kind

    func makeUIView(context: Context) -> SCNView {
        let view = PoplurManagedSCNView(performanceName: "SignUpCube3D")
        view.backgroundColor = .clear
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = false
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 35
        camera.position = SCNVector3(0, 0, 3.2)
        scene.rootNode.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 520
        scene.rootNode.addChildNode(ambient)

        let assetName = kind == .profile ? "MarkHead_TalkingRig" : "zoom_buildings"
        let directories = kind == .profile ? ["", "Models"] : ["", "ClayMapWeb", "SignupModels"]
        if let url = RuntimeGLBLoader.bundledURL(named: assetName, candidateSubdirectories: directories),
           let loaded = RuntimeGLBLoader.loadScene(from: url, label: "signup_\(assetName)") {
            let content = SCNNode()
            loaded.rootNode.childNodes.forEach { content.addChildNode($0.clone()) }
            RuntimeGLBLoader.normalize(content, targetExtent: 1.55)
            content.eulerAngles = SCNVector3(-0.12, kind == .building ? -0.55 : 0.2, 0)
            scene.rootNode.addChildNode(content)
        }
        view.scene = scene
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}

private struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content }
            VStack(alignment: .leading, spacing: spacing) { content }
        }
    }
}

private struct CheckboxLikeToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 19, weight: .black))
                    .foregroundStyle(configuration.isOn ? Color.green : Color.black.opacity(0.42))
                configuration.label
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension ToggleStyle where Self == CheckboxLikeToggleStyle {
    static var checkboxLike: CheckboxLikeToggleStyle { CheckboxLikeToggleStyle() }
}

private extension String {
    var trimmedForSignup: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct SignUpView_Previews: PreviewProvider {
    static var previews: some View {
        SignUpView()
    }
}
