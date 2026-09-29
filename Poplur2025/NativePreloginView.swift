import SwiftUI
import PhotosUI
import LocalAuthentication
import ImageIO

struct NativePreloginView: View {
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var music: PreLoginMusicPlayer
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var model = NativePreloginModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var lastInteraction = Date()
    @State private var awake = true
    @State private var useFaceID = false
    @State private var hueIndex = 0
    @State private var formPosition = ScrollPosition(edge: .top)
    private let pinks: [Color] = [Color(red: 1, green: 0.176, blue: 0.588), Color(red: 0.96, green: 0.24, blue: 0.63), Color(red: 0.90, green: 0.16, blue: 0.49)]
    private let cream = Color(red: 1, green: 0.957, blue: 0.89)
    private var biometricName: String {
        let context = LAContext(); _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .touchID ? "Touch ID" : context.biometryType == .faceID ? "Face ID" : "biometrics"
    }
    private var motionActive: Bool { awake && !reduceMotion && scenePhase == .active }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                NativePreloginBackdrop(color: pinks[hueIndex], awake: motionActive)
                if model.step == .welcome { welcome(size: geometry.size) }
                else { form(size: geometry.size) }
                VStack {
                    HStack {
                        PoplurMuteButton(music: music)
                        Spacer()
                        Button { hueIndex = (hueIndex + 1) % pinks.count; wake() } label: {
                            Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                                .overlay(Circle().fill(pinks[hueIndex]).padding(8)).overlay(Circle().stroke(.white.opacity(0.65), lineWidth: 2))
                                .frame(width: 34, height: 34).shadow(color: .black.opacity(0.3), radius: 3, y: 3)
                        }.accessibilityLabel("Change background colour")
                    }.padding(.horizontal, 18).padding(.top, max(geometry.safeAreaInsets.top, windowTopInset) + 10)
                    Spacer()
                }.ignoresSafeArea(.container)
            }
            .simultaneousGesture(TapGesture().onEnded { wake() })
            .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in wake() })
        }
        .preferredColorScheme(.light)
        .accessibilityIdentifier("nativePrelogin")
        .onChange(of: model.step) { _, _ in formPosition.scrollTo(edge: .top); wake() }
        .onChange(of: model.accountType) { _, _ in model.photo = nil; model.gender = "" }
        .onChange(of: photoItem) { _, item in
            Task {
                do {
                    guard let data = try await item?.loadTransferable(type: Data.self),
                          let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return }
                    model.photo = UIImage(cgImage: thumbnail)
                } catch { model.error = "This photo could not be opened. Please choose another." }
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Date().timeIntervalSince(lastInteraction) >= 20 { awake = false }
            }
        }
        .alert("Poplur", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) { Button("OK") { model.notice = nil } } message: { Text(model.notice ?? "") }
    }
    private var windowTopInset: CGFloat {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets.top ?? 0
    }
    private func wake() { lastInteraction = Date(); awake = true }

    private func welcome(size: CGSize) -> some View {
        let logoTop = max(58, min(92, size.height * 0.08))
        let logoHeight: CGFloat = 132
        let cubeHeight: CGFloat = size.height > 760 ? 132 : 103
        let buttonBottom = max(60, min(132, size.height * 0.12))
        let buttonsTop = size.height - buttonBottom - 144
        let gap = max(14, (buttonsTop - logoTop - logoHeight - cubeHeight - 133) / 3)
        return ZStack(alignment: .top) {
            Image("NativePreloginLogo").resizable().scaledToFit().frame(width: logoHeight, height: logoHeight).position(x: size.width / 2, y: logoTop + logoHeight / 2)
            NativePreloginCube(welcome: true, awake: motionActive, back: {}).frame(width: cubeHeight, height: cubeHeight).position(x: size.width / 2, y: logoTop + logoHeight + gap + cubeHeight / 2)
            VStack(spacing: 8) {
                heading("Welcome to Poplur!")
                Text("Post. Explore. Connect.\nExpand your world.").font(.custom("AvenirNext-Heavy", size: 17))
                Text(music.currentAIScript).font(.custom("AvenirNext-Heavy", size: 13)).padding(.top, 2)
            }.foregroundStyle(cream).multilineTextAlignment(.center).shadow(color: .black.opacity(0.3), radius: 1, y: 2)
                .frame(width: min(size.width - 32, 380)).position(x: size.width / 2, y: logoTop + logoHeight + gap * 2 + cubeHeight + 66)
            VStack(spacing: 28) {
                clayButton("Sign In", id: "welcomeSignIn") { model.go(.signIn) }
                clayButton("Sign Up", id: "welcomeSignUp") { model.go(.account) }
            }.position(x: size.width / 2, y: buttonsTop + 72)
        }.frame(width: size.width, height: size.height).ignoresSafeArea(.container)
    }
    private func form(size: CGSize) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if model.step != .intro { Image("NativePreloginLogo").resizable().scaledToFit().frame(width: 112, height: 112).accessibilityHidden(true) }
                NativePreloginCube(welcome: false, awake: scenePhase == .active, back: model.back)
                    .frame(width: model.step == .intro ? 74 : 103, height: model.step == .intro ? 74 : 103)
                    .accessibilityElement().accessibilityLabel("Back").accessibilityAddTraits(.isButton).accessibilityAction { model.back() }
                    .accessibilityIdentifier("preloginBack")
                VStack(spacing: 16) {
                    formContents
                    if let error = model.error { Text(error).font(.system(size: 14, weight: .bold)).foregroundStyle(.white).padding(12).frame(maxWidth: .infinity).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("preloginError") }
                    if model.busy { ProgressView("Please wait…").tint(.white).foregroundStyle(.white) }
                }.disabled(model.busy || model.hasCreatedAccount)
                // The retry is outside the disabled form: saved credentials and
                // the selected account cannot change after Firebase creates it.
                if model.hasCreatedAccount && !model.busy { clayButton("Retry", id: "retryOnboarding") { Task { await model.submit(auth: auth) } } }
            }.frame(maxWidth: 330).padding(.horizontal, 24).padding(.top, 64).padding(.bottom, 40).frame(maxWidth: .infinity)
        }.scrollPosition($formPosition).scrollDismissesKeyboard(.interactively).safeAreaPadding(.bottom, 10)
    }
    @ViewBuilder private var formContents: some View {
        switch model.step {
        case .welcome: EmptyView()
        case .signIn:
            heading("Sign in")
            clayButton("Sign in with \(biometricName)", id: "faceIDSignIn") { Task { await biometricSignIn() } }
            subtitle("or sign in with email")
            emailField
            SecureField("Password", text: $model.password).textContentType(.password).nativePreloginField().accessibilityIdentifier("signInPassword")
            Button("FORGOT") { Task { await model.resetPassword() } }.font(.system(size: 12, weight: .heavy)).tint(cream).frame(maxWidth: .infinity, alignment: .trailing)
            Toggle("Enable \(biometricName) on this device", isOn: $useFaceID).font(.system(size: 13, weight: .semibold)).tint(.pink).foregroundStyle(cream)
            clayButton("Sign In", id: "submitSignIn") { Task { await model.signIn(auth: auth, saveBiometricCredentials: useFaceID) } }
            link("New here? Create an account") { model.go(.account) }
        case .account:
            heading("Create your Poplur"); subtitle("Choose your account type.")
            choice("Personal", detail: "Share with friends inside your radius", asset: "MarkHead_TalkingRig", selected: model.accountType == .user) { model.accountType = .user }
            choice("Business", detail: "Reach locals and promote your spot", asset: "zoom_buildings", selected: model.accountType == .business) { model.accountType = .business }
            clayButton("Create account", id: "chooseAccount") { model.go(.intro) }
            link("Have an account? Sign in") { model.go(.signIn) }
        case .intro:
            thumbnail(model.accountType == .business ? "zoom_buildings" : "MarkHead_TalkingRig", size: 96)
            heading(model.accountType == .business ? "Business" : "Personal")
            subtitle("What a \(model.accountType == .business ? "business" : "personal") account does.")
            ForEach(introLines, id: \.self) { line in HStack(alignment: .top, spacing: 12) { Text("•"); Text(line) }.font(.system(size: 15, weight: .semibold)).foregroundStyle(cream).frame(maxWidth: .infinity, alignment: .leading) }
            clayButton("Next", id: "introNext") { model.go(.credentials) }
        case .credentials:
            heading("Create login"); subtitle("Then continue with onboarding.")
            emailField
            SecureField("Password", text: $model.password).textContentType(.newPassword).nativePreloginField().accessibilityIdentifier("signupPassword")
            SecureField("Confirm password", text: $model.confirmation).textContentType(.newPassword).nativePreloginField().accessibilityIdentifier("confirmPassword")
            DatePicker("Date of birth", selection: $model.birthday, in: ...Date(), displayedComponents: .date).datePickerStyle(.compact).tint(.pink).nativePreloginField().onChange(of: model.birthday) { _, _ in model.birthdayChosen = true }
            if !model.birthdayChosen { Button("Use \(model.birthday.formatted(date: .abbreviated, time: .omitted))") { model.birthdayChosen = true }.font(.system(size: 13, weight: .bold)).foregroundStyle(cream) }
            Toggle("I agree to the Terms of Service", isOn: $model.agreed).tint(.pink).font(.system(size: 13, weight: .semibold)).foregroundStyle(cream).accessibilityIdentifier("agreeTerms")
            clayButton("Create account", id: "credentialsNext", action: model.advanceCredentials)
        case .photo:
            heading("Add a profile photo"); subtitle("Show your radius who you are. You can add one later in Settings · Profile.")
            PhotosPicker(selection: $photoItem, matching: .images) {
                Group { if let image = model.photo { Image(uiImage: image).resizable().scaledToFill() } else { Image(systemName: "plus").font(.system(size: 44, weight: .heavy)).foregroundStyle(.pink).frame(maxWidth: .infinity, maxHeight: .infinity).background(cream) } }.frame(width: 120, height: 120).clipShape(Circle()).overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 5, y: 4)
            }.accessibilityLabel("Upload photo")
            subtitle("Upload photo")
            // One control, and it says which of the two things it is doing. A hard
            // "Add a profile photo to continue." here was a dead end on any device
            // with an empty photo library, because the picker above is the only way
            // to supply one.
            clayButton(model.photo == nil ? "Skip for now" : "Continue", id: "photoNext") { model.go(.gender) }
        case .gender:
            heading("Is your cube male or female?"); subtitle("Pick the clay head your profile cube wears.")
            choice("Male", detail: "The original mark head", asset: "poplur_mark_head_navigator", selected: model.gender == "male") { model.gender = "male"; Task { await model.submit(auth: auth) } }
            choice("Female", detail: "The female head", asset: "poplur_female_head_navigator", selected: model.gender == "female") { model.gender = "female"; Task { await model.submit(auth: auth) } }
            subtitle("You can change this any time in Settings · Profile.")
        case .business:
            heading("Find your business"); subtitle("Search the map and select your spot.")
            HStack { TextField("Business name and city", text: $model.query).submitLabel(.search).onSubmit { Task { await model.searchPlaces() } }; Button("Search") { Task { await model.searchPlaces() } } }.nativePreloginField()
            if model.searching { ProgressView().tint(.white) }
            ForEach(Array(model.places.enumerated()), id: \.offset) { _, item in
                Button { model.place = item; model.places = [] } label: { VStack(alignment: .leading) { Text(item.name ?? "Business").bold(); Text(item.placemark.title ?? "").font(.caption) }.frame(maxWidth: .infinity, alignment: .leading) }.nativePreloginField()
            }
            if let place = model.place { Text("\(place.name ?? "")\n\(place.placemark.title ?? "")").nativePreloginField() }
            PhotosPicker(selection: $photoItem, matching: .images) {
                HStack {
                    if let image = model.photo { Image(uiImage: image).resizable().scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 12)) }
                    Text(model.photo == nil ? "Upload logo (optional)" : "Change logo").font(.system(size: 14, weight: .bold)).foregroundStyle(cream)
                }
            }
            TextField("Category", text: $model.businessCategory).nativePreloginField()
            clayButton("Continue", id: "businessNext") { if model.place == nil || model.businessCategory.isEmpty { model.error = "Select your business and enter its category." } else { model.go(.verification) } }
        case .verification:
            heading("Verify business")
            subtitle("Provide your business contact and ownership details for review.")
            TextField("Business phone (optional)", text: $model.contactPhone).keyboardType(.phonePad).nativePreloginField()
            TextField("Your role and proof of ownership", text: $model.proof, axis: .vertical).lineLimit(3...5).nativePreloginField()
            subtitle("Verification is pending until your submission is reviewed.")
            clayButton("Continue", id: "verificationNext") { if model.proof.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { model.error = "Add your ownership details to continue." } else { model.go(.review) } }
        case .review:
            heading("Review & submit"); subtitle("Confirm before submitting for review.")
            Text(model.place?.name ?? "").nativePreloginField()
            Text(model.businessCategory).nativePreloginField()
            Text(model.place?.placemark.title ?? "").nativePreloginField()
            Text(model.email).nativePreloginField()
            clayButton("Submit for review", id: "submitBusiness") { Task { await model.submit(auth: auth) } }
        }
    }
    private var emailField: some View { TextField("E-Mail", text: $model.email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().nativePreloginField().accessibilityIdentifier("preloginEmail") }
    private func heading(_ value: String) -> some View { Text(value).font(.custom("AvenirNext-Heavy", size: 30)).foregroundStyle(cream).multilineTextAlignment(.center).shadow(color: .black.opacity(0.35), radius: 1, y: 2).fixedSize(horizontal: false, vertical: true) }
    private func subtitle(_ value: String) -> some View { Text(value).font(.custom("AvenirNext-DemiBold", size: 15)).foregroundStyle(cream).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }
    private func link(_ label: String, action: @escaping () -> Void) -> some View { Button(label, action: action).font(.system(size: 14, weight: .bold)).foregroundStyle(cream).padding(4) }
    private func clayButton(_ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(label).font(.custom("AvenirNext-Heavy", size: 22)).foregroundStyle(LinearGradient(colors: [.black, Color(red: 0.36, green: 0.07, blue: 0.22), .pink, Color(red: 0.3, green: 0, blue: 0.17), .black], startPoint: .top, endPoint: .bottom)).frame(width: 250, height: 58).background(LinearGradient(colors: [.white, .white, Color(red: 1, green: 0.93, blue: 0.97), Color(red: 0.89, green: 0.88, blue: 0.91)], startPoint: .top, endPoint: .bottom), in: Capsule()).overlay(Capsule().stroke(.pink, lineWidth: 2.5)).shadow(color: .black.opacity(0.24), radius: 5, y: 6) }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
    private func thumbnail(_ asset: String, size: CGFloat) -> some View {
        Group { if let image = NativePreloginThumbnails.image(asset) { Image(uiImage: image).resizable().scaledToFit() } else { Image(systemName: asset == "zoom_buildings" ? "building.2.fill" : "person.fill").resizable().scaledToFit().padding(10).foregroundStyle(.pink) } }.frame(width: size, height: size).background(cream, in: RoundedRectangle(cornerRadius: 13)).accessibilityHidden(true)
    }
    private func choice(_ title: String, detail: String, asset: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { HStack(spacing: 12) { thumbnail(asset, size: 48); VStack(alignment: .leading, spacing: 4) { Text(title).font(.custom("AvenirNext-Heavy", size: 20)); Text(detail).font(.system(size: 12, weight: .semibold)) }; Spacer(); if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.pink) } }.padding(12).frame(maxWidth: .infinity).foregroundStyle(Color(red: 0.31, green: 0.05, blue: 0.18)).background(cream, in: RoundedRectangle(cornerRadius: 20)).overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? .white : .pink.opacity(0.5), lineWidth: 3)).shadow(color: .black.opacity(0.18), radius: 3, y: 4) }.buttonStyle(.plain).accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private var introLines: [String] {
        model.accountType == .business ? ["Your radius is anchored to your address, not your phone — it stays where your door is.", "Your doorstep stays covered even on a quiet week, so people outside can always find you.", "Reach locals actually within range, and post offers and bookings straight from your spot.", "You see who you reached as numbers, never as individuals."] : ["Your radius follows you. Everything you post radiates out from wherever you were standing.", "Radius decays. Keep posting and it grows; go quiet and it shrinks back.", "Take over ground on the map, one pop at a time — the goal is a radius the size of the world.", "You are discovered by interception: people inside your circle see you, and you see theirs."]
    }
    private func biometricSignIn() async {
        guard !model.busy else { return }
        guard let email = PoplurKeychain.savedEmail else { model.error = "Sign in with email and enable biometrics on this device first."; return }
        let context = LAContext()
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Sign in to Poplur") else { return }
            guard let password = PoplurKeychain.retrievePassword(for: email) else { model.error = "Saved sign-in is unavailable. Sign in with email and enable biometrics again."; return }
            model.email = email; model.password = password; await model.signIn(auth: auth)
        } catch { model.error = error.localizedDescription }
    }
}

private extension View {
    func nativePreloginField() -> some View {
        self.font(.system(size: 16, weight: .semibold)).foregroundStyle(Color(red: 0.25, green: 0.04, blue: 0.16)).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 1, green: 0.957, blue: 0.97), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.85), lineWidth: 2)).shadow(color: .black.opacity(0.12), radius: 2, y: 3)
    }
}
