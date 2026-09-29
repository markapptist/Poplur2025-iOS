import SwiftUI
import UIKit

// The account-deletion dialogs in the house style: the native twin of
// PoplurDialog (poplur-clay-map/src/PoplurDialog.module.css). A pink clay
// frame around a dark panel, the P tab on the top edge, a rounded title and
// one pink pill of a button. They replace three stock alerts whose password
// field rendered as a squashed capsule on iOS 26 (owner, 29 Sep 2026). The
// password is typed and used here, in the native shell, never in the page.

@MainActor
final class PoplurDeletionDialogModel: ObservableObject {
    enum Phase: Equatable {
        case confirm
        case working
        case result(title: String, message: String)
    }

    @Published var phase: Phase
    @Published var password = ""
    @Published var inlineError: String?
    var onConfirm: (String) -> Void = { _ in }
    var onCancel: () -> Void = {}
    var onAcknowledge: () -> Void = {}

    init(phase: Phase) { self.phase = phase }
}

final class PoplurDeletionDialogController: UIHostingController<PoplurDeletionDialogView> {
    let model: PoplurDeletionDialogModel

    init(model: PoplurDeletionDialogModel) {
        self.model = model
        super.init(rootView: PoplurDeletionDialogView(model: model))
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        // A dark keyboard and dark system chrome under a dark panel.
        overrideUserInterfaceStyle = .dark
        isModalInPresentation = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }
}

struct PoplurDeletionDialogView: View {
    @ObservedObject var model: PoplurDeletionDialogModel
    @FocusState private var passwordFocused: Bool
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.58)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            card
                .frame(maxWidth: 344)
                .padding(.horizontal, 18)
                .scaleEffect(shown ? 1 : 0.86)
                .offset(y: shown ? 0 : 18)
                .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.68)) { shown = true }
        }
        .task {
            guard model.phase == .confirm else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            passwordFocused = true
        }
        .onChange(of: model.phase) { _, phase in
            passwordFocused = phase == .confirm
        }
    }

    // MARK: Frame

    private var card: some View {
        VStack(spacing: 12) {
            switch model.phase {
            case .confirm:
                confirmContent
            case .working:
                workingContent
            case let .result(title, message):
                resultContent(title: title, message: message)
            }
        }
        .padding(EdgeInsets(top: 40, leading: 16, bottom: 16, trailing: 16))
        .frame(maxWidth: .infinity)
        .background(
            Self.panelShape
                .fill(Self.panelFill)
                .overlay(Self.panelShape.strokeBorder(Color.black.opacity(0.6), lineWidth: 1))
        )
        .padding(12)
        .background(
            Self.frameShape
                .fill(Self.frameFill)
                .overlay(Self.frameShape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
        )
        .overlay(alignment: .top) { tab.offset(y: -26) }
        .overlay(alignment: .topTrailing) {
            if model.phase == .confirm { closeButton }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.62), radius: 27, x: 0, y: 22)
        .shadow(color: Self.pink.opacity(0.35), radius: 15)
        .padding(.top, 26)
        .animation(.easeInOut(duration: 0.22), value: model.phase)
        .animation(.easeInOut(duration: 0.18), value: model.inlineError)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    /// The P tab: a dark clay square with a pink rim, straddling the top edge.
    private var tab: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(colors: [Self.rgb(0x2a1f27), Self.rgb(0x120d12)], startPoint: .top, endPoint: .bottom)
                        .shadow(.inner(color: .white.opacity(0.14), radius: 0, x: 0, y: 2))
                        .shadow(.inner(color: .black.opacity(0.55), radius: 0, x: 0, y: -3))
                )
            if let logo = Self.logo {
                Image(uiImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.6), radius: 1.5, x: 0, y: 2)
            }
        }
        .frame(width: 62, height: 62)
        .background(
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(Self.pink)
                .padding(-5)
        )
        .shadow(color: .black.opacity(0.5), radius: 11, x: 0, y: 10)
        .accessibilityHidden(true)
    }

    private var closeButton: some View {
        Button { model.onCancel() } label: {
            Text("×")
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.white)
                .shadow(color: Self.maroon.opacity(0.6), radius: 0, x: 0, y: 2)
                .padding(.bottom, 2)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .padding(.top, 8)
        .padding(.trailing, 10)
    }

    // MARK: Phases

    @ViewBuilder private var confirmContent: some View {
        heading("Delete account?")
        bodyText("This permanently deletes your Poplur account, profile, posts, uploaded media and the messages you sent. It can't be undone. Enter your password to confirm.")
        passwordField
        if let error = model.inlineError {
            Text(error)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Self.pinkLight)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        }
        Button("Delete account", action: confirm)
            .buttonStyle(PoplurClayPrimaryButtonStyle())
            .disabled(model.password.isEmpty)
            .opacity(model.password.isEmpty ? 0.5 : 1)
        Button { model.onCancel() } label: {
            Text("Cancel")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .tracking(0.5)
                .foregroundStyle(Color.white.opacity(0.82))
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var workingContent: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.large)
            .tint(Self.pinkLight)
            .padding(.bottom, 2)
        heading("Deleting account…")
        bodyText("Removing your account and personal data. Please keep Poplur open.")
    }

    @ViewBuilder private func resultContent(title: String, message: String) -> some View {
        heading(title)
        bodyText(message)
        Button("OK") { model.onAcknowledge() }
            .buttonStyle(PoplurClayPrimaryButtonStyle())
    }

    // MARK: Parts

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28, weight: .black, design: .rounded))
            .tracking(-0.8)
            .foregroundStyle(Color.white)
            .multilineTextAlignment(.center)
            .shadow(color: .black.opacity(0.5), radius: 0, x: 0, y: 2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundStyle(Self.muted)
            .multilineTextAlignment(.center)
            .lineSpacing(2.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, -4)
    }

    private var passwordField: some View {
        SecureField("", text: $model.password, prompt: Text("Password").foregroundStyle(Self.muted.opacity(0.55)))
            .font(.system(size: 16, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white)
            .tint(Self.pinkLight)
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($passwordFocused)
            .onSubmit(confirm)
            .padding(.horizontal, 18)
            .frame(minHeight: 48)
            .background(
                Capsule().fill(
                    Self.rgb(0x0d0b0f)
                        .shadow(.inner(color: .black.opacity(0.85), radius: 2.5, x: 0, y: 2))
                        .shadow(.inner(color: .white.opacity(0.06), radius: 0, x: 0, y: -1))
                )
            )
            .overlay(
                Capsule().strokeBorder(Self.pinkLight.opacity(passwordFocused ? 0.75 : 0.22), lineWidth: passwordFocused ? 1.5 : 1)
            )
            .accessibilityLabel("Password")
    }

    private func confirm() {
        let password = model.password
        guard !password.isEmpty else { return }
        model.password = ""
        model.inlineError = nil
        passwordFocused = false
        model.onConfirm(password)
    }

    // MARK: Style (values from PoplurDialog.module.css)

    fileprivate static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    fileprivate static let pink = rgb(0xff2f91)
    fileprivate static let pinkLight = rgb(0xff79b9)
    fileprivate static let muted = rgb(0xf0dbe7)
    fileprivate static let maroon = rgb(0x7a003e)
    private static let frameShape = RoundedRectangle(cornerRadius: 34, style: .continuous)
    private static let panelShape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    private static var frameFill: some ShapeStyle {
        LinearGradient(stops: [
            .init(color: rgb(0xff7ebb), location: 0),
            .init(color: pink, location: 0.34),
            .init(color: rgb(0xd12677), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .shadow(.inner(color: .white.opacity(0.55), radius: 0, x: 0, y: 3))
        .shadow(.inner(color: maroon.opacity(0.55), radius: 0, x: 0, y: -4))
    }

    private static var panelFill: some ShapeStyle {
        LinearGradient(colors: [rgb(0x1f181d), rgb(0x121014)], startPoint: .top, endPoint: .bottom)
            .shadow(.inner(color: .white.opacity(0.06), radius: 0, x: 0, y: 2))
            .shadow(.inner(color: .black.opacity(0.35), radius: 12, x: 0, y: 12))
    }

    /// The web dialog's P tab uses the bundle's own logo mark; draw it once at
    /// the tab's size instead of scaling the 843 px source every frame.
    private static let logo: UIImage? = {
        guard let url = Bundle.main.url(forResource: "logo_icon", withExtension: "png", subdirectory: "ClayMapWeb"),
              let source = UIImage(contentsOfFile: url.path), source.size.width > 0, source.size.height > 0 else {
            return UIImage(named: "logo")
        }
        let side: CGFloat = 44
        let scale = min(side / source.size.width, side / source.size.height)
        let drawn = CGSize(width: source.size.width * scale, height: source.size.height * scale)
        let origin = CGPoint(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2)
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            source.draw(in: CGRect(origin: origin, size: drawn))
        }
    }()
}

/// PoplurDialog's `.primary`: one pink pill of a button.
struct PoplurClayPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(size: 17, weight: .black, design: .rounded))
            .tracking(-0.17)
            .foregroundStyle(Color.white)
            .shadow(color: PoplurDeletionDialogView.maroon.opacity(0.5), radius: 0, x: 0, y: 1)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(
                Capsule().fill(
                    LinearGradient(stops: [
                        .init(color: PoplurDeletionDialogView.rgb(0xff5fae), location: 0),
                        .init(color: PoplurDeletionDialogView.pink, location: 0.48),
                        .init(color: PoplurDeletionDialogView.rgb(0xe0126f), location: 1),
                    ], startPoint: .top, endPoint: .bottom)
                    .shadow(.inner(color: .white.opacity(pressed ? 0.35 : 0.5), radius: 0, x: 0, y: 3))
                    .shadow(.inner(color: PoplurDeletionDialogView.maroon.opacity(0.55), radius: 0, x: 0, y: pressed ? -2 : -4))
                )
            )
            .shadow(color: PoplurDeletionDialogView.rgb(0xf63b9a).opacity(pressed ? 0.15 : 0.35), radius: 9, x: 0, y: pressed ? 4 : 8)
            .offset(y: pressed ? 2 : 0)
            .padding(.top, 2)
            .contentShape(Capsule())
    }
}
