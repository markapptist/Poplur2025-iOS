import SwiftUI
import SpriteKit
import UIKit
import FirebaseAuth

// MARK: - SpriteKit Scene for Login visuals (pink ticket, dots, scallop, logo)

private final class LoginScene: SKScene {

    // Nodes
    private let ticketNode = SKShapeNode()
    private let dotsNode = SKNode()
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
        buildDots()
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

    private func buildDots() {
        dotsNode.removeAllChildren()
        dotsNode.zPosition = 2
        addChild(dotsNode)

        // Dots similar to DottedMapOverlay, but in SpriteKit
        let dotSize: CGFloat = 6
        let spacingX: CGFloat = 10
        let spacingY: CGFloat = 12
        let insetTop: CGFloat = 24

        let usable = CGRect(x: 0, y: insetTop, width: size.width, height: max(0, size.height - insetTop - scallopHeight))
        let cols = max(0, Int(usable.width / (dotSize + spacingX)))
        let rows = max(0, Int(usable.height / (dotSize + spacingY)))

        for r in 0..<rows {
            for c in 0..<cols {
                let circle = SKShapeNode(circleOfRadius: dotSize / 2)
                let opacity: CGFloat = ((r + c) % 7 == 0) ? 0.9 : 0.35
                circle.fillColor = UIColor(white: 1.0, alpha: opacity)
                circle.strokeColor = .clear
                let x = usable.minX + CGFloat(c) * (dotSize + spacingX) + dotSize
                let y = usable.minY + CGFloat(r) * (dotSize + spacingY) + dotSize
                circle.position = CGPoint(x: x, y: y)
                dotsNode.addChild(circle)
            }
        }
        dotsNode.alpha = 0.25
        dotsNode.isUserInteractionEnabled = false
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
        dotsNode.position = .zero
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
    @EnvironmentObject private var auth: AuthViewModel
    @EnvironmentObject private var stripeCoordinator: StripeTransitionCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var isLoginFailed = false
    @State private var isLoading = false
    @State private var navigateToSignup = false
    @State private var logoFloatOffset: CGFloat = 0
    @FocusState private var focusedField: Field?

    enum Field {
        case email, password
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            AuthConfettiBackground()

            VStack {
                Spacer(minLength: 24)

                // Ticket area backed by SpriteKit visuals
                ZStack(alignment: .top) {
                    // SpriteKit scene: pink ticket card, dots, scallop (no logo — shown in SwiftUI below)
                    SpriteView(scene: makeLoginScene())
                        .background(Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 8)

                    // Unified content overlay: floating logo → cube (back) → form fields
                    VStack(spacing: 0) {
                        // Floating Poplur logo
                        Image("logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 110, height: 110)
                            .padding(.top, 20)
                            .offset(y: logoFloatOffset)
                            .onAppear {
                                withAnimation(
                                    .easeInOut(duration: 1.3)
                                    .repeatForever(autoreverses: true)
                                ) { logoFloatOffset = -10 }
                            }

                        Spacer().frame(height: 10)

                        // Login cube — tap to go back to Welcome
                        LoginCubeView(onTap: { stripeCoordinator.trigger { dismiss() } })
                            .frame(width: 200, height: 200)

                        Spacer().frame(height: 14)

                        // Form fields
                        VStack(alignment: .leading, spacing: 20) {
                            // Email field row with icon + underline
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
                                Rectangle()
                                    .fill(Color.white.opacity(0.9))
                                    .frame(height: 1)
                            }

                            // Password field row with icon + "FORGOT" + underline
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Image(systemName: "lock")
                                        .poplurIconShader()
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.95))

                                    SecureField("Password", text: $password)
                                        .textContentType(.oneTimeCode) // suppress strong password banner
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
                                Rectangle()
                                    .fill(Color.white.opacity(0.9))
                                    .frame(height: 1)
                            }

                            if isLoginFailed {
                                Text("Invalid email or password. Please try again.")
                                    .font(.footnote)
                                    .foregroundColor(.white)
                            }

                            // Sign In Button
                            Button(action: {
                                hideKeyboard()
                                loginUser()
                            }) {
                                ZStack {
                                    Capsule()
                                        .fill(Color.white)
                                        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
                                    HStack(spacing: 8) {
                                        if isLoading {
                                            ProgressView()
                                                .progressViewStyle(.circular)
                                                .tint(.black)
                                        }
                                        Text("Sign In")
                                            .font(.system(.headline, design: .rounded).weight(.bold))
                                            .foregroundColor(.black)
                                    }
                                    .padding(.vertical, 16)
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .disabled(isLoading || email.isEmpty || password.isEmpty)

                            Button {
                                hideKeyboard()
                                stripeCoordinator.trigger { navigateToSignup = true }
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
                .frame(height: 640)
                .padding(.horizontal, 24)

                Spacer(minLength: 24)
            }
        }
        .onTapGesture {
            hideKeyboard()
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: auth.isAuthenticated) { _, authed in
            if authed {
                dismiss()
            }
        }
    }

    // Build a scene sized exactly to the ticket card frame (600x640 max, but we use container size)
    private func makeLoginScene() -> SKScene {
        let sceneSize = CGSize(width: 600, height: 640)
        let scene = LoginScene(size: sceneSize)
        scene.scaleMode = .resizeFill
        return scene
    }

    // MARK: - Actions

    func loginUser() {
        guard !email.isEmpty, !password.isEmpty else { return }
        isLoading = true
        isLoginFailed = false

        Auth.auth().signIn(withEmail: email, password: password) { _, error in
            isLoading = false
            if let error = error {
                print("Login failed with error: \(error.localizedDescription)")
                self.isLoginFailed = true
            } else {
                // Root NavigationStack (in App) will switch to HomeView automatically via AuthViewModel
                self.isLoginFailed = false
            }
        }
    }

    func forgotPassword() {
        guard !email.isEmpty else {
            // Optionally prompt user to enter email first
            focusedField = .email
            return
        }
        Auth.auth().sendPasswordReset(withEmail: email) { error in
            if let error = error {
                print("Password reset failed: \(error.localizedDescription)")
            } else {
                print("Password reset email sent.")
            }
        }
    }

    private func hideKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LoginView()
        }
        .preferredColorScheme(.light)
    }
}
