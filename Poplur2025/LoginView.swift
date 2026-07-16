import SwiftUI
import SpriteKit
import UIKit
import FirebaseAuth
import LocalAuthentication

// MARK: - SpriteKit Scene for Login visuals (pink ticket, scallop, logo)

private final class LoginScene: SKScene {

    // Nodes
    private let ticketNode = SKShapeNode()
    private let scallopNode = SKShapeNode()

    // Layout constants (SpriteKit points)
    private let cornerRadius: CGFloat = 24
    private let ticketShadow: CGFloat = 8
    private let scallopHeight: CGFloat = 18
    private let scallopDiameter: CGFloat = 18
    private let scallopSpacing: CGFloat = 8

    // Brand color (sRGB) #FF2D96
    private let brandPink = UIColor(red: 1.0, green: 45.0/255.0, blue: 150.0/255.0, alpha: 1.0)

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true

        buildTicketBackground()
        buildScallop()
        layoutAll()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        layoutAll()
    }

    // MARK: Build visuals

    private func buildTicketBackground() {
        ticketNode.removeFromParent()

        // Rounded rectangle path for the pink ticket card
        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius).cgPath

        let shape = SKShapeNode(path: path)
        shape.fillColor = brandPink
        shape.strokeColor = .clear

        // Flat look matching mock: gradient overlay uses same color for both stops
        let gradient = gradientTexture(
            size: size,
            colors: [brandPink, brandPink],
            startPoint: CGPoint(x: 0, y: 1),
            endPoint: CGPoint(x: 1, y: 0)
        )
        let gradientNode = SKSpriteNode(texture: gradient)
        gradientNode.size = size
        gradientNode.anchorPoint = CGPoint(x: 0, y: 0)
        gradientNode.position = .zero
        gradientNode.alpha = 0.999

        // Create a container so we can add shadow-like effect easily
        let container = SKNode()
        container.addChild(shape)
        container.addChild(gradientNode)

        // A soft shadow via duplicate blurred sprite (cheap approximation)
        let shadow = SKSpriteNode(color: .black, size: CGSize(width: size.width, height: size.height))
        shadow.alpha = 0.08
        shadow.position = CGPoint(x: 0, y: -ticketShadow)
        shadow.anchorPoint = CGPoint(x: 0, y: 0)
        shadow.zPosition = -1
        container.addChild(shadow)

        container.zPosition = 0

        ticketNode.addChild(container)
        addChild(ticketNode)
    }

    private func buildScallop() {
        scallopNode.removeFromParent()
        scallopNode.zPosition = 3

        // Even-odd path: full rect with circles appended (holes)
        let width = size.width
        let height = scallopHeight
        let y = height / 2
        let total = Int((width + scallopSpacing) / (scallopDiameter + scallopSpacing))

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let path = UIBezierPath(rect: rect)
        for i in 0..<total {
            let x = (CGFloat(i) * (scallopDiameter + scallopSpacing)) + scallopDiameter / 2
            let circle = UIBezierPath(ovalIn: CGRect(x: x - scallopDiameter/2, y: y - scallopDiameter/2, width: scallopDiameter, height: scallopDiameter))
            path.append(circle)
        }

        let shape = SKShapeNode(path: path.cgPath)
        shape.fillColor = .white
        shape.strokeColor = .clear
        shape.lineWidth = 0

        scallopNode.addChild(shape)
        addChild(scallopNode)
    }

    private func layoutAll() {
        ticketNode.position = .zero
        scallopNode.position = .zero
    }

    private func gradientTexture(size: CGSize, colors: [UIColor], startPoint: CGPoint, endPoint: CGPoint) -> SKTexture {
        let layer = CAGradientLayer()
        layer.frame = CGRect(origin: .zero, size: size)
        layer.colors = colors.map { $0.cgColor }
        layer.startPoint = startPoint
        layer.endPoint = endPoint

        UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else {
            return SKTexture()
        }
        layer.render(in: ctx)
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        return SKTexture(image: image)
    }
}

// MARK: - SwiftUI LoginView: SpriteKit visuals + native TextFields

struct LoginView: View {
    // Carousel mode: parent (WelcomeView) manages the background, confetti, and AI guide.
    var isCarousel: Bool = false
    var onBack: (() -> Void)? = nil
    var onGoToSignUp: (() -> Void)? = nil

    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var stripeCoordinator: StripeTransitionCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var loginErrorMessage: String? = nil
    @State private var isLoading = false
    @State private var isBiometricLoading = false
    @State private var navigateToSignup = false
    @State private var biometricAvailable = false
    @State private var biometricType: LABiometryType = .none
    @State private var hasSavedCredentials = false
    @State private var showEnableFaceIDSheet = false
    @FocusState private var focusedField: Field?

    enum Field { case email, password }

    private var biometricIcon: String {
        biometricType == .touchID ? "touchid" : "faceid"
    }
    private var biometricLabel: String {
        biometricType == .touchID ? "Touch ID" : "Face ID"
    }
    private var showFaceIDHero: Bool { biometricAvailable && hasSavedCredentials }

    var body: some View {
        ZStack {
            // In carousel mode the parent WelcomeView provides the white bg and confetti.
            if !isCarousel {
                Color.white.ignoresSafeArea()
                AuthConfettiBackground()
            }

            VStack {
                Spacer(minLength: 24)

                ZStack(alignment: .top) {
                    SpriteView(scene: makeLoginScene())
                        .background(Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)

                    VStack(spacing: 0) {
                        // Logo
                        Image("logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 110, height: 110)
                            .padding(.top, 20)

                        Spacer().frame(height: 10)

                        // Cube — tap to go back (carousel uses closure, standalone uses dismiss)
                        LoginCubeView(onTap: { if let onBack { onBack() } else { stripeCoordinator.trigger { dismiss() } } })
                            .frame(width: 200, height: 200)

                        Spacer().frame(height: 14)

                        VStack(alignment: .leading, spacing: 20) {

                            // ── Face ID hero ──────────────────────────────────
                            if showFaceIDHero {
                                faceIDHeroButton
                                orDivider
                            }

                            // ── Email field ───────────────────────────────────
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 12) {
                                    Image(systemName: "at.circle")
                                        .poplurIconShader()
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.95))
                                    TextField("E-Mail", text: $email)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled(true)
                                        .keyboardType(.emailAddress)
                                        .textContentType(.username)
                                        .foregroundColor(.white)
                                        .tint(.white)
                                        .focused($focusedField, equals: .email)
                                }
                                Rectangle().fill(Color.white.opacity(0.9)).frame(height: 1)
                            }

                            // ── Password field ────────────────────────────────
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Image(systemName: "lock")
                                        .poplurIconShader()
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.95))
                                    SecureField("Password", text: $password)
                                        .textContentType(.oneTimeCode)
                                        .foregroundColor(.white)
                                        .tint(.white)
                                        .focused($focusedField, equals: .password)
                                    Spacer()
                                    Button(action: forgotPassword) {
                                        Text("FORGOT")
                                            .font(.system(size: 12, weight: .bold, design: .rounded))
                                            .kerning(0.5)
                                            .foregroundColor(.white.opacity(0.95))
                                    }
                                    .buttonStyle(.plain)
                                }
                                Rectangle().fill(Color.white.opacity(0.9)).frame(height: 1)
                            }

                            if let msg = loginErrorMessage {
                                Text(msg)
                                    .font(.footnote)
                                    .foregroundColor(.white)
                            }

                            // ── Sign In button ────────────────────────────────
                            Button(action: { hideKeyboard(); loginUser() }) {
                                ZStack {
                                    Capsule()
                                        .fill(Color.white)
                                        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
                                    HStack(spacing: 8) {
                                        if isLoading {
                                            ProgressView().progressViewStyle(.circular).tint(.black)
                                        }
                                        Text("Sign In")
                                            .font(.system(.headline, design: .rounded).weight(.bold))
                                            .foregroundColor(.black)
                                    }
                                    .padding(.vertical, 16)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .disabled(isLoading || isBiometricLoading || email.isEmpty || password.isEmpty)

                            Button {
                                hideKeyboard()
                                if let onGoToSignUp { onGoToSignUp() }
                                else { navigateToSignup = true }
                            } label: {
                                Text("New here? Create an account")
                                    .font(.system(size: 14, weight: .black, design: .rounded))
                                    .foregroundColor(.white.opacity(0.94))
                            }
                            .buttonStyle(.plain)
                            .navigationDestination(isPresented: $navigateToSignup) {
                                SignUpView()
                                    .toolbar(.hidden, for: .navigationBar)
                                    .navigationBarBackButtonHidden(true)
                            }
                        }
                        .padding(.horizontal, 24)

                        Spacer()
                    }
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: 600)
                .frame(height: showFaceIDHero ? 700 : 640)
                .padding(.horizontal, 24)

                Spacer(minLength: 24)
            }
        }
        .overlay(alignment: .bottom) {
            // In carousel mode the parent WelcomeView's unified guide handles the greeting.
            if !isCarousel {
                AuthAIGuide(screen: .login)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showEnableFaceIDSheet) {
            EnableFaceIDSheet(email: email, onEnable: {
                PoplurKeychain.saveCredentials(email: email, password: password)
                hasSavedCredentials = PoplurKeychain.hasCredentials
            })
            .presentationDetents([.height(300)])
        }
        .onAppear {
            checkBiometrics()
            // Auto-trigger Face ID if credentials are saved
            if PoplurKeychain.hasCredentials {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    attemptBiometricSignIn()
                }
            }
        }
        .onTapGesture { hideKeyboard() }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: auth.isAuthenticated) { _, authed in
            if authed && !isCarousel { dismiss() }
        }
    }

    // MARK: - Face ID hero

    @ViewBuilder
    private var faceIDHeroButton: some View {
        Button(action: attemptBiometricSignIn) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.20))
                        .frame(width: 52, height: 52)
                    if isBiometricLoading {
                        ProgressView().progressViewStyle(.circular).tint(.white)
                    } else {
                        Image(systemName: biometricIcon)
                            .font(.system(size: 26, weight: .light))
                            .foregroundColor(.white)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sign in with \(biometricLabel)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    if let saved = PoplurKeychain.savedEmail {
                        Text(saved)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.45))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isBiometricLoading)

        // Remove saved credentials link
        Button {
            PoplurKeychain.clearSavedCredentials()
            hasSavedCredentials = false
        } label: {
            Text("Use a different account")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var orDivider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.white.opacity(0.28)).frame(height: 0.5)
            Text("or sign in with email")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.55))
                .fixedSize()
            Rectangle().fill(Color.white.opacity(0.28)).frame(height: 0.5)
        }
    }

    // MARK: - Biometrics

    private func checkBiometrics() {
        let ctx = LAContext()
        var error: NSError?
        let canEval = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        biometricType = ctx.biometryType
        biometricAvailable = canEval
        hasSavedCredentials = PoplurKeychain.hasCredentials
        if let saved = PoplurKeychain.savedEmail {
            email = saved
        }
    }

    func attemptBiometricSignIn() {
        guard let savedEmail = PoplurKeychain.savedEmail,
              let savedPassword = PoplurKeychain.retrievePassword(for: savedEmail) else { return }
        let ctx = LAContext()
        isBiometricLoading = true
        ctx.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Sign in to Poplur"
        ) { success, _ in
            DispatchQueue.main.async {
                if success {
                    self.email = savedEmail
                    self.password = savedPassword
                    self.loginUser()
                } else {
                    self.isBiometricLoading = false
                }
            }
        }
    }

    // MARK: - Actions

    func loginUser() {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        isBiometricLoading = false
        loginErrorMessage = nil

        Auth.auth().signIn(withEmail: email, password: password) { _, error in
            isLoading = false
            if let error = error {
                print("Login failed: \(error.localizedDescription)")
                self.loginErrorMessage = error.localizedDescription
            } else {
                // Offer Face ID save if biometrics available and nothing saved yet
                if self.biometricAvailable && !self.hasSavedCredentials {
                    self.showEnableFaceIDSheet = true
                }
            }
        }
    }

    func forgotPassword() {
        guard !email.isEmpty else { focusedField = .email; return }
        Auth.auth().sendPasswordReset(withEmail: email) { _ in }
    }

    private func hideKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func makeLoginScene() -> SKScene {
        let scene = LoginScene(size: CGSize(width: 600, height: 640))
        scene.scaleMode = .resizeFill
        return scene
    }
}

// MARK: - Enable Face ID prompt sheet

private struct EnableFaceIDSheet: View {
    let email: String
    let onEnable: () -> Void
    @Environment(\.dismiss) private var dismiss

    private let brand = Color(red: 1, green: 0.18, blue: 0.59)

    private var biometricIcon: String {
        let ctx = LAContext()
        var err: NSError?
        ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        return ctx.biometryType == .touchID ? "touchid" : "faceid"
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()

            ZStack {
                Circle().fill(brand.opacity(0.12)).frame(width: 72, height: 72)
                Image(systemName: biometricIcon)
                    .font(.system(size: 34, weight: .light))
                    .foregroundColor(brand)
            }

            VStack(spacing: 6) {
                Text("Enable Face ID?")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundColor(.black)
                Text("Sign in faster next time as \(email)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.black.opacity(0.55))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                Button {
                    onEnable()
                    dismiss()
                } label: {
                    Text("Enable")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(brand))
                }
                .buttonStyle(.plain)

                Button { dismiss() } label: {
                    Text("Not Now")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.black.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .background(Color.white)
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack { LoginView() }
            .preferredColorScheme(.light)
    }
}
