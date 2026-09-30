import SwiftUI
import UIKit

// The account-deletion dialogs as a Poplur "clear window": the canonical paint
// for true transient cards (poplur-clay-map/src/TransientPopupSurface.module.css)
// in the News pop card's layout (MapNewsCard.module.css). A dark glass card
// with a thin pink rim and a pink glow in its top corner, a header bar with a
// status pill and a round ×, a left-aligned heavy title, and rounded-rectangle
// buttons. They replace three stock alerts whose password field rendered as a
// squashed capsule on iOS 26 (owner, 29 Sep 2026). The password is typed and
// used here, in the native shell, never in the page.

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
        // A dark keyboard and dark system chrome under a dark card.
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
            // TransientPopupSurface .scrim: blur(7px) under rgba(9, 5, 11, .52). A
            // system material at partial strength stands in for the light blur.
            Rectangle().fill(.ultraThinMaterial).opacity(0.55).ignoresSafeArea()
            Self.rgb(0x09050b).opacity(0.52).ignoresSafeArea()
            card
                .frame(maxWidth: 340)
                .padding(.horizontal, 20)
                .scaleEffect(shown ? 1 : 0.94)
                .offset(y: shown ? 0 : 14)
                .opacity(shown ? 1 : 0)
        }
        .accessibilityAddTraits(.isModal)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { shown = true }
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

    // MARK: Surface

    private var card: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 0) {
                switch model.phase {
                case .confirm:
                    confirmContent
                case .working:
                    workingContent
                case let .result(title, message):
                    resultContent(title: title, message: message)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: 17, leading: 19, bottom: 19, trailing: 19))
        }
        .background(surfaceFill)
        .clipShape(Self.cardShape)
        .overlay(Self.cardShape.strokeBorder(Self.rgb(0xff88c3).opacity(0.72), lineWidth: 1))
        .shadow(color: .black.opacity(0.7), radius: 27, x: 0, y: 20)
        .shadow(color: Self.rgb(0xf63b9a).opacity(0.24), radius: 14)
        .animation(.easeInOut(duration: 0.22), value: model.phase)
        .animation(.easeInOut(duration: 0.18), value: model.inlineError)
    }

    /// linear-gradient(150deg, rgba(29,8,24,.97), rgba(8,7,13,.97)) under a
    /// pink radial glow at 88% 2% that fades out by 38% of the card.
    private var surfaceFill: some View {
        GeometryReader { geo in
            let reach = hypot(geo.size.width * 0.88, geo.size.height * 0.98)
            ZStack {
                Self.cardShape.fill(
                    LinearGradient(
                        colors: [Self.rgb(0x1d0818).opacity(0.97), Self.rgb(0x08070d).opacity(0.97)],
                        startPoint: UnitPoint(x: 0.25, y: 0.07),
                        endPoint: UnitPoint(x: 0.75, y: 0.93)
                    )
                    .shadow(.inner(color: .white.opacity(0.19), radius: 0, x: 0, y: 1))
                )
                RadialGradient(
                    colors: [Self.rgb(0xf93c9a).opacity(0.25), .clear],
                    center: UnitPoint(x: 0.88, y: 0.02),
                    startRadius: 0,
                    endRadius: reach * 0.38
                )
            }
        }
    }

    /// The News pop card's header: a status pill and a round ×.
    private var header: some View {
        HStack(spacing: 10) {
            Text(statusText)
                .font(.system(size: 10, weight: .black))
                .tracking(1.4)
                .foregroundStyle(Color.white)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Capsule().fill(statusColor))
            Spacer(minLength: 0)
            if model.phase == .confirm {
                Button { model.onCancel() } label: {
                    Text("×")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(Color.white)
                        .padding(.bottom, 3)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.white.opacity(0.09)))
                        .overlay(Circle().strokeBorder(Self.rgb(0xffcde5).opacity(0.42), lineWidth: 1))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 16, bottom: 8, trailing: 12))
        .frame(minHeight: 48)
        .background(Self.rgb(0x10070f).opacity(0.9))
    }

    private var statusText: String {
        switch model.phase {
        case .confirm: return "ACCOUNT"
        case .working: return "DELETING"
        case let .result(title, _): return title == "Account deleted" ? "DELETED" : "ACCOUNT"
        }
    }

    private var statusColor: Color {
        if case .result = model.phase { return Self.rgb(0xf00078) }
        return Self.rgb(0xe11859)
    }

    // MARK: Phases

    @ViewBuilder private var confirmContent: some View {
        heading("Delete your account?")
        summary("This permanently deletes your Poplur account, profile, posts, uploaded media and the messages you sent. It can't be undone.")
        Text("ENTER YOUR PASSWORD TO CONFIRM")
            .font(.system(size: 11, weight: .black))
            .tracking(1.1)
            .foregroundStyle(Self.rgb(0x71dfff))
            .padding(.top, 4)
            .padding(.bottom, 8)
        passwordField
        if let error = model.inlineError {
            Text(error)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Self.rgb(0xff79b9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .transition(.opacity)
        }
        VStack(spacing: 8) {
            Button("DELETE ACCOUNT", action: confirm)
                .buttonStyle(PoplurSurfaceButtonStyle(kind: .primary))
                .disabled(model.password.isEmpty)
                .opacity(model.password.isEmpty ? 0.45 : 1)
            Button("CANCEL") { model.onCancel() }
                .buttonStyle(PoplurSurfaceButtonStyle(kind: .secondary))
        }
        .padding(.top, 16)
    }

    @ViewBuilder private var workingContent: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Self.rgb(0x71dfff))
            heading("Deleting your account…")
        }
        summary("Removing your account and personal data. Please keep Poplur open.")
    }

    @ViewBuilder private func resultContent(title: String, message: String) -> some View {
        heading(title)
        summary(message)
        Button("OK") { model.onAcknowledge() }
            .buttonStyle(PoplurSurfaceButtonStyle(kind: .primary))
            .padding(.top, 6)
    }

    // MARK: Parts

    /// MapNewsCard `.copy h2`: white, heavy, tight.
    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 23, weight: .black))
            .tracking(-1.0)
            .foregroundStyle(Color.white)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    /// MapNewsCard `.summary`.
    private func summary(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Self.rgb(0xfff4fa).opacity(0.9))
            .lineSpacing(2.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 13)
            .padding(.bottom, 10)
    }

    /// The composer's text field: a dark inset well with a faint pink rim that
    /// turns cyan while focused.
    private var passwordField: some View {
        SecureField("", text: $model.password, prompt: Text("Password").foregroundStyle(Color.white.opacity(0.45)))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Self.rgb(0xfff9fc))
            .tint(Self.rgb(0x8de9ff))
            .textContentType(.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($passwordFocused)
            .onSubmit(confirm)
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(
                    Self.rgb(0x09080b).opacity(0.82)
                        .shadow(.inner(color: .black.opacity(0.62), radius: 6, x: 0, y: 5))
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(passwordFocused ? Self.rgb(0x8de9ff) : Self.rgb(0xffd1e9).opacity(0.22), lineWidth: 1)
            )
            .shadow(color: Self.rgb(0x45cdef).opacity(passwordFocused ? 0.3 : 0), radius: 6)
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

    // MARK: Style (values from TransientPopupSurface.module.css and MapNewsCard.module.css)

    fileprivate static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    /// 21 px on phones, 26 px wider (the surface's own media query).
    private static let cardShape = RoundedRectangle(cornerRadius: 21, style: .continuous)
}

/// TransientPopupSurface `.primary` (pink) and MapNewsCard `.secondary` (cyan
/// outline): rounded rectangles, spaced capitals.
struct PoplurSurfaceButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return configuration.label
            .font(.system(size: kind == .primary ? 11 : 10, weight: .black))
            .tracking(kind == .primary ? 1.32 : 1.0)
            .foregroundStyle(kind == .primary ? Color.white : PoplurDeletionDialogView.rgb(0xbdeeff))
            .frame(maxWidth: .infinity, minHeight: kind == .primary ? 44 : 42)
            .background(
                Group {
                    if kind == .primary {
                        shape.fill(
                            LinearGradient(
                                colors: [PoplurDeletionDialogView.rgb(0xf63b9a), PoplurDeletionDialogView.rgb(0xbd0f66)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            .shadow(.inner(color: .white.opacity(0.28), radius: 0, x: 0, y: 1))
                        )
                    } else {
                        shape.fill(PoplurDeletionDialogView.rgb(0x71dfff).opacity(0.08))
                    }
                }
            )
            .overlay(
                shape.strokeBorder(
                    kind == .primary
                        ? PoplurDeletionDialogView.rgb(0xffbcde).opacity(0.6)
                        : PoplurDeletionDialogView.rgb(0x71dfff).opacity(0.46),
                    lineWidth: 1
                )
            )
            .shadow(color: PoplurDeletionDialogView.rgb(0x6a0035).opacity(kind == .primary ? 0.38 : 0), radius: 8, x: 0, y: 6)
            .scaleEffect(pressed ? 0.97 : 1)
            .offset(y: pressed ? 1 : 0)
            .contentShape(shape)
    }
}
