import SwiftUI
import PhotosUI
import AVKit
import AVFoundation
import FirebaseAuth
import UniformTypeIdentifiers

// MARK: - Brand token

private let pinkAI = Color(red: 1, green: 0.176, blue: 0.588) // #FF2D96

// MARK: - Theme

enum PoplurAIChatTheme: String, CaseIterable {
    case dark, warmDark, cardHeader, prelogin

    var displayName: String {
        switch self {
        case .dark:       return "Dark"
        case .warmDark:   return "Warm Dark"
        case .cardHeader: return "Card Header"
        case .prelogin:   return "Pre-login"
        }
    }

    var icon: String {
        switch self {
        case .dark:       return "moon.fill"
        case .warmDark:   return "sparkle"
        case .cardHeader: return "rectangle.topthird.inset.filled"
        case .prelogin:   return "sun.max.fill"
        }
    }

    var isLight: Bool    { self == .prelogin }
    var isCard: Bool     { self == .cardHeader || self == .prelogin }
    var isFullCard: Bool { self == .prelogin }

    var screenBg: Color {
        switch self {
        case .dark:       return .black
        case .warmDark:   return Color(red: 0.051, green: 0, blue: 0.031)
        case .cardHeader: return Color(red: 0.051, green: 0, blue: 0.031)
        case .prelogin:   return Color(red: 0.973, green: 0.929, blue: 0.961)
        }
    }

    var brandNameColor: Color { isCard ? Color(.label) : .white }
    var brandSubColor: Color  { pinkAI.opacity(isLight ? 0.65 : 0.8) }

    var assistantBubbleBg: Color {
        switch self {
        case .dark:       return Color.white.opacity(0.08)
        case .warmDark:   return pinkAI.opacity(0.1)
        case .cardHeader: return Color.white.opacity(0.08)
        case .prelogin:   return Color(red: 1, green: 0.941, blue: 0.965)
        }
    }
    var assistantBubbleText: Color { isLight ? Color(.label) : Color.white.opacity(0.92) }

    var chipBg: Color {
        switch self {
        case .dark:       return Color.white.opacity(0.07)
        case .warmDark:   return pinkAI.opacity(0.1)
        case .cardHeader: return Color.white.opacity(0.07)
        case .prelogin:   return Color(red: 1, green: 0.941, blue: 0.965)
        }
    }
    var chipText: Color   { isLight ? Color(.label) : Color.white.opacity(0.82) }
    var chipBorder: Color {
        switch self {
        case .warmDark:   return pinkAI.opacity(0.38)
        case .prelogin:   return pinkAI.opacity(0.28)
        default:          return pinkAI.opacity(0.22)
        }
    }
    var emptyStateText: Color { isLight ? Color(.secondaryLabel) : Color.white.opacity(0.55) }

    var inputBarBg: Color       { isFullCard ? .white : Color.black.opacity(0.92) }
    var inputFieldBg: Color     { isFullCard ? Color(UIColor.systemGray6) : Color.white.opacity(0.07) }
    var inputTextColor: Color   { isLight ? Color(.label) : .white }
    var placeholderColor: Color { isLight ? Color(.placeholderText) : Color.white.opacity(0.28) }

    var modePillInactiveBg: Color   { isLight ? Color(UIColor.systemGray5) : Color.white.opacity(0.1) }
    var modePillInactiveText: Color { isLight ? Color(.secondaryLabel) : Color.white.opacity(0.75) }
    var plusButtonStroke: Color     { isLight ? Color(.separator) : pinkAI.opacity(0.35) }
    var plusButtonIcon: Color       { isLight ? Color(.secondaryLabel) : Color.white.opacity(0.75) }
    var micIcon: Color              { isLight ? Color(.secondaryLabel) : Color.white.opacity(0.6) }
    var typingBg: Color             { isLight ? Color(UIColor.systemGray5) : Color.white.opacity(0.07) }
    var genBubbleBg: Color          { isLight ? Color(UIColor.systemGray5) : Color.white.opacity(0.06) }
    var genStepActive: Color        { isLight ? Color(.label) : .white }
    var genStepInactive: Color      { isLight ? Color(.tertiaryLabel) : Color.white.opacity(0.28) }
}

private struct PAIThemeKey: EnvironmentKey {
    static let defaultValue = PoplurAIChatTheme.prelogin
}

extension EnvironmentValues {
    var paiTheme: PoplurAIChatTheme {
        get { self[PAIThemeKey.self] }
        set { self[PAIThemeKey.self] = newValue }
    }
}

private extension View {
    @ViewBuilder
    func paiCard(radius: CGFloat, enabled: Bool) -> some View {
        if enabled {
            self.background(.white, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .padding(.horizontal, 10)
        } else {
            self
        }
    }

    @ViewBuilder
    func `if`<C: View>(_ condition: Bool, transform: (Self) -> C) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - Data models

enum PoplurAIChatRole { case user, assistant, generation }

struct PoplurAIChatAttachment: Identifiable {
    let id = UUID()
    var image: UIImage?
    var videoURL: URL?
    var fileName: String
    var fileType: PAIFileType

    enum PAIFileType { case photo, video, audio, pdf, gif, model, other }

    var thumbnail: UIImage? {
        if let image { return image }
        if let url = videoURL { return videoFirstFrame(url: url) }
        return nil
    }
    var typeIcon: String {
        switch fileType {
        case .photo: return "photo.fill"
        case .video: return "video.fill"
        case .audio: return "waveform"
        case .pdf:   return "doc.fill"
        case .gif:   return "sparkles.rectangle.stack.fill"
        case .model: return "cube.transparent.fill"
        case .other: return "paperclip"
        }
    }
}

private func videoFirstFrame(url: URL) -> UIImage? {
    let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    gen.appliesPreferredTrackTransform = true
    gen.maximumSize = CGSize(width: 200, height: 200)
    guard let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) else { return nil }
    return UIImage(cgImage: cg)
}

struct PoplurAIGenStep: Identifiable {
    let id = UUID()
    let emoji: String
    let label: String
    var isComplete = false
    var isCurrent = false
}

struct PoplurAIChatMessage: Identifiable {
    var id: UUID = UUID()
    var role: PoplurAIChatRole
    var text: String
    var attachments: [PoplurAIChatAttachment] = []
    var steps: [PoplurAIGenStep] = []
    var resultImage: UIImage? = nil
    var resultVideoURL: URL? = nil
    var isStreaming = false
    var showStoreButton = false
    var timestamp = Date()
}

struct PoplurAISuggestion: Identifiable {
    let id = UUID()
    let emoji: String
    let label: String
}

private let kSuggestions: [PoplurAISuggestion] = [
    .init(emoji: "✨", label: "Make this cinematic"),
    .init(emoji: "🎬", label: "Create commercial"),
    .init(emoji: "😂", label: "Make funny"),
    .init(emoji: "🎨", label: "Cartoon style"),
    .init(emoji: "📺", label: "90s TV"),
    .init(emoji: "🎵", label: "Add music"),
    .init(emoji: "🗣", label: "Translate"),
    .init(emoji: "📈", label: "Make viral"),
    .init(emoji: "🧠", label: "Brainstorm"),
]

// MARK: - ViewModel

@MainActor
final class PoplurAIChatViewModel: ObservableObject {
    @Published var messages: [PoplurAIChatMessage] = []
    @Published var inputText = ""
    @Published var attachments: [PoplurAIChatAttachment] = []
    @Published var isGenerating = false
    @Published var showSuggestions = true
    @Published var searchMode = false
    @Published var smartMode = false

    var onPost: ((UIImage?, URL?) -> Void)?

    func loadInitialMedia(image: UIImage?, videoURL: URL?) {
        var a: PoplurAIChatAttachment?
        if let img = image {
            a = PoplurAIChatAttachment(image: img, fileName: "capture.jpg", fileType: .photo)
        } else if let url = videoURL {
            a = PoplurAIChatAttachment(videoURL: url, fileName: "capture.mp4", fileType: .video)
        }
        if let a { attachments = [a] }
    }

    func removeAttachment(_ id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachments.isEmpty else { return }
        let msg = PoplurAIChatMessage(role: .user, text: text, attachments: attachments)
        messages.append(msg)
        inputText = ""
        attachments = []
        showSuggestions = false
        Task { await respond(to: msg) }
    }

    func sendSuggestion(_ s: PoplurAISuggestion) {
        inputText = s.label
        send()
    }

    // MARK: Response logic

    private func respond(to msg: PoplurAIChatMessage) async {
        // Typing indicator
        var typingMsg = PoplurAIChatMessage(role: .assistant, text: "", isStreaming: true)
        let typingId = typingMsg.id
        messages.append(typingMsg)
        try? await Task.sleep(nanoseconds: 200_000_000)
        messages.removeAll { $0.id == typingId }

        let lower = msg.text.lowercased()
        if needsClarification(lower) {
            await offerStyleMenu()
        } else if isStylePick(lower) {
            await generate(prompt: msg.text)
        } else if isEditCommand(lower) {
            await generate(prompt: msg.text)
        } else {
            appendAssistant(fallbackReply())
        }
    }

    private func needsClarification(_ text: String) -> Bool {
        let triggers = ["cinematic", "make it", "stylize", "style it"]
        return triggers.contains { text.hasPrefix($0) || text.contains(" \($0)") }
    }

    private func isStylePick(_ text: String) -> Bool {
        ["hollywood","horror","anime","pixar","80s","vhs","clay","lego","minecraft","gta","cartoon"].contains { text.contains($0) }
    }

    private func isEditCommand(_ text: String) -> Bool {
        let cmds = ["remove","replace","change","add","blur","fix","upscale","translate","dub",
                    "slow motion","speed ramp","create","generate","turn","make","age","face swap",
                    "beauty","color","caption","subtitle","commercial","viral","sticker","meme","gif",
                    "reel","tiktok","youtube","intro","outro","trailer","avatar","clothing"]
        return cmds.contains { text.contains($0) }
    }

    private func appendAssistant(_ text: String) {
        messages.append(PoplurAIChatMessage(role: .assistant, text: text))
    }

    private func offerStyleMenu() async {
        appendAssistant("I can do that! Which style would you like?")
        try? await Task.sleep(nanoseconds: 300_000_000)
        appendAssistant("• Hollywood\n• Horror\n• Anime\n• Pixar\n• 80s VHS\n• Clay\n• Cartoon")
    }

    private func fallbackReply() -> String {
        [
            "Ready to edit your content! Try asking me to make it cinematic, add effects, remove the background, or anything else.",
            "I understand. What AI edit would you like to apply? I can stylize, enhance, or completely transform your media.",
            "Got it! What would you like me to create or change? I support hundreds of editing commands."
        ].randomElement()!
    }

    // MARK: Generation

    private func generate(prompt: String) async {
        isGenerating = true
        let steps: [PoplurAIGenStep] = [
            .init(emoji: "✨", label: "Understanding..."),
            .init(emoji: "🎨", label: "Applying effects..."),
            .init(emoji: "⚡️", label: "Rendering..."),
        ]
        var genMsg = PoplurAIChatMessage(role: .generation, text: "", steps: steps)
        messages.append(genMsg)
        let genId = genMsg.id

        // Start API call immediately — runs concurrently with the animation
        async let apiWork = performGeneration(prompt: prompt)

        for i in 0..<steps.count {
            try? await Task.sleep(nanoseconds: 380_000_000)
            updateStep(genId: genId, index: i)
        }

        let (resultImage, resultVideo, errText) = await apiWork

        // Mark all done
        if let idx = messages.firstIndex(where: { $0.id == genId }) {
            for i in 0..<messages[idx].steps.count {
                messages[idx].steps[i].isComplete = true
                messages[idx].steps[i].isCurrent = false
            }
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        messages.removeAll { $0.id == genId }
        isGenerating = false

        if let err = errText {
            let needsStore = err == AIStackError.insufficientCredits.errorDescription
                          || err == AIStackError.aiLockedForPlan.errorDescription
            var msg = PoplurAIChatMessage(
                role: .assistant,
                text: needsStore ? "You need Creator Credits to generate AI content." : "Something went wrong: \(err)\n\nCheck your connection and try again.",
                showStoreButton: needsStore
            )
            messages.append(msg)
        } else {
            var result = PoplurAIChatMessage(role: .assistant, text: "Done! Here's your result:")
            result.resultImage = resultImage
            result.resultVideoURL = resultVideo
            messages.append(result)
        }
    }

    private func performGeneration(prompt: String) async -> (UIImage?, URL?, String?) {
        let sourceImage = allAttachments().compactMap(\.image).first
        let sourceVideo = allAttachments().compactMap(\.videoURL).first
        do {
            if sourceVideo != nil {
                let url = try await callVideoGeneration(prompt: prompt)
                return (nil, url, nil)
            } else {
                let img = try await callImageGeneration(prompt: prompt, source: sourceImage)
                return (img, nil, nil)
            }
        } catch {
            return (nil, nil, error.localizedDescription)
        }
    }

    private func updateStep(genId: UUID, index: Int) {
        guard let idx = messages.firstIndex(where: { $0.id == genId }) else { return }
        messages[idx].steps[index].isCurrent = true
        if index > 0 {
            messages[idx].steps[index - 1].isCurrent = false
            messages[idx].steps[index - 1].isComplete = true
        }
    }

    private func allAttachments() -> [PoplurAIChatAttachment] {
        messages.flatMap(\.attachments) + attachments
    }

    private func callImageGeneration(prompt: String, source: UIImage?) async throws -> UIImage {
        guard let uid = Auth.auth().currentUser?.uid else { throw PAIChatError.notAuthenticated }
        let req = AIGenerationRequest(
            userId: uid, plan: .creator, contentType: .edit,
            prompt: prompt, inputAssetIds: [], publishMetadata: nil,
            campaignAssetTypes: [], metadata: ["client": "ios", "surface": "ai_chat"]
        )
        let resp = try await PoplurAIBackendClient().generate(req)
        guard let url = resp.outputUrl else { throw PAIChatError.generationFailed }
        let (data, http) = try await URLSession.shared.data(from: url)
        guard (http as? HTTPURLResponse)?.statusCode == 200, let img = UIImage(data: data) else {
            throw PAIChatError.downloadFailed
        }
        return img
    }

    private func callVideoGeneration(prompt: String) async throws -> URL {
        guard let uid = Auth.auth().currentUser?.uid else { throw PAIChatError.notAuthenticated }
        let req = AIGenerationRequest(
            userId: uid, plan: .creator, contentType: .video,
            prompt: prompt, inputAssetIds: [], publishMetadata: nil,
            campaignAssetTypes: [], metadata: ["client": "ios", "surface": "ai_chat"]
        )
        let resp = try await PoplurAIBackendClient().generate(req)
        guard let url = resp.outputUrl else { throw PAIChatError.generationFailed }
        return url
    }
}

enum PAIChatError: LocalizedError {
    case notAuthenticated, generationFailed, downloadFailed
    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You need to be signed in to use Poplur AI."
        case .generationFailed: return "AI generation failed."
        case .downloadFailed:   return "Could not download the result."
        }
    }
}

// MARK: - Root view

struct PoplurAIChatView: View {
    let initialImage: UIImage?
    let initialVideoURL: URL?
    var onDismiss: () -> Void
    var onPost: ((UIImage?, URL?) -> Void)?

    @StateObject private var vm = PoplurAIChatViewModel()
    @State private var showSettings = false
    @State private var showStore = false
    @FocusState private var inputFocused: Bool
    @State private var glitterPhase: CGFloat = 0
    @AppStorage("poplur_ai_chat_theme") private var theme: PoplurAIChatTheme = .prelogin

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background
            theme.screenBg.ignoresSafeArea()
            PoplurAIConfettiLayer()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Glitter border overlay
            RoundedRectangle(cornerRadius: 0, style: .continuous)
                .stroke(
                    AngularGradient(
                        colors: [pinkAI, pinkAI.opacity(0.15), pinkAI.opacity(0.6),
                                 pinkAI.opacity(0.05), pinkAI, pinkAI.opacity(0.3)],
                        center: .center, startAngle: .degrees(glitterPhase), endAngle: .degrees(glitterPhase + 360)
                    ),
                    lineWidth: 1.8
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .onAppear {
                    withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                        glitterPhase = 360
                    }
                }

            // Main layout
            VStack(spacing: theme.isFullCard ? 8 : 0) {
                // Header — white card for card themes, dark bar for dark themes
                Group {
                    if theme.isCard {
                        PAIChatHeader(onDismiss: onDismiss, onSettings: { showSettings = true })
                            .background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .padding(.horizontal, 10)
                            .padding(.top, 4)
                    } else {
                        PAIChatHeader(onDismiss: onDismiss, onSettings: { showSettings = true })
                            .background(Color.black.opacity(0.88))
                    }
                }

                if !theme.isCard {
                    Divider().overlay(pinkAI.opacity(0.28))
                }

                // Conversation — white card for prelogin
                PAIConversationScroll(vm: vm, onPost: { img, url in onPost?(img, url); onDismiss() })
                    .paiCard(radius: 18, enabled: theme.isFullCard)

                if !theme.isCard {
                    Divider().overlay(pinkAI.opacity(0.14))
                }

                // Input bar — rounded card for prelogin
                PAIInputBar(vm: vm, inputFocused: $inputFocused)
                    .if(theme.isFullCard) {
                        $0.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                          .padding(.horizontal, 10)
                          .padding(.bottom, 8)
                    }
            }
        }
        .environment(\.paiTheme, theme)
        .preferredColorScheme(theme.isLight ? .light : .dark)
        .onAppear { vm.loadInitialMedia(image: initialImage, videoURL: initialVideoURL) }
        .sheet(isPresented: $showSettings) { PAISettingsSheet() }
        .sheet(isPresented: $showStore) { PoplurStoreView() }
        .onReceive(NotificationCenter.default.publisher(for: .OpenPoplurStoreRequested)) { _ in
            showStore = true
        }
    }
}

// MARK: - Header

private struct PAIChatHeader: View {
    var onDismiss: () -> Void
    var onSettings: () -> Void
    @Environment(\.paiTheme) private var theme

    var body: some View {
        HStack(spacing: 14) {
            // P logo
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(colors: [pinkAI.opacity(0.9), pinkAI.opacity(0.5)],
                                       center: .center, startRadius: 0, endRadius: 22)
                    )
                    .frame(width: 44, height: 44)
                Text("P")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: pinkAI, radius: 8)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("poplur")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(theme.brandNameColor)
                        .poplurTextShader(intensity: theme.isLight ? 0.0 : 0.9)
                    Text("AI")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(pinkAI)
                        .poplurTextShader(intensity: 1.0)
                }
                HStack(spacing: 4) {
                    Image(systemName: "sparkle")
                        .poplurIconShader()
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.brandSubColor)
                    Text("stay connected.")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.brandSubColor)
                        .poplurTextShader(intensity: theme.isLight ? 0.0 : 0.72)
                    Image(systemName: "sparkle")
                        .poplurIconShader()
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.brandSubColor)
                }
            }

            Spacer()

            Button(action: onSettings) {
                ZStack {
                    Circle()
                        .stroke(pinkAI.opacity(0.4), lineWidth: 1.2)
                        .frame(width: 36, height: 36)
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(pinkAI).frame(width: 4, height: 4)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        // Background applied by parent based on theme (dark bar or white card)
    }
}

// MARK: - Conversation scroll

private struct PAIConversationScroll: View {
    @ObservedObject var vm: PoplurAIChatViewModel
    var onPost: (UIImage?, URL?) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if vm.showSuggestions && vm.messages.isEmpty {
                        PAISuggestionGrid(vm: vm)
                            .padding(.top, 28)
                    }

                    ForEach(vm.messages) { msg in
                        PAIMessageRow(message: msg, vm: vm, onPost: onPost)
                            .id(msg.id)
                    }

                    Color.clear.frame(height: 1).id("pai_bottom")
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .onChange(of: vm.messages.count) { _, _ in
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    proxy.scrollTo("pai_bottom", anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Message row dispatcher

private struct PAIMessageRow: View {
    let message: PoplurAIChatMessage
    @ObservedObject var vm: PoplurAIChatViewModel
    var onPost: (UIImage?, URL?) -> Void

    var body: some View {
        switch message.role {
        case .user:
            PAIUserBubble(message: message)
        case .assistant:
            PAIAssistantBubble(message: message, onPost: onPost)
        case .generation:
            PAIGenerationBubble(message: message)
        }
    }
}

// MARK: - User bubble

private struct PAIUserBubble: View {
    let message: PoplurAIChatMessage
    @State private var appeared = false

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            VStack(alignment: .trailing, spacing: 8) {
                if !message.attachments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(message.attachments) { att in
                                PAIInlineAttachment(attachment: att)
                            }
                        }
                    }
                }
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(pinkAI.opacity(0.88), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(pinkAI.opacity(0.35), lineWidth: 0.8)
                        )
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 18)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { appeared = true }
        }
    }
}

private struct PAIInlineAttachment: View {
    let attachment: PoplurAIChatAttachment

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let img = attachment.thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: attachment.typeIcon)
                            .poplurIconShader()
                            .font(.system(size: 22))
                            .foregroundStyle(pinkAI)
                    )
            }
            if attachment.fileType == .video {
                Image(systemName: "play.circle.fill")
                    .poplurIconShader()
                    .font(.system(size: 18))
                    .foregroundStyle(.white)
                    .padding(6)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(pinkAI.opacity(0.28), lineWidth: 0.8)
        )
    }
}

// MARK: - Assistant bubble

private struct PAIAssistantBubble: View {
    let message: PoplurAIChatMessage
    var onPost: (UIImage?, URL?) -> Void
    @State private var appeared = false
    @Environment(\.paiTheme) private var theme

    private let hasResult: Bool
    init(message: PoplurAIChatMessage, onPost: @escaping (UIImage?, URL?) -> Void) {
        self.message = message
        self.onPost = onPost
        self.hasResult = message.resultImage != nil || message.resultVideoURL != nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // AI avatar dot
            Circle()
                .fill(pinkAI.opacity(0.85))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "sparkles")
                        .poplurIconShader()
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 10) {
                if message.isStreaming {
                    PAITypingIndicator()
                } else if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.assistantBubbleText)
                        .fixedSize(horizontal: false, vertical: true)
                        .if(theme.isLight) {
                            $0.padding(.horizontal, 14).padding(.vertical, 11)
                              .background(theme.assistantBubbleBg,
                                          in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                }

                if message.showStoreButton {
                    Button {
                        NotificationCenter.default.post(name: .OpenPoplurStoreRequested, object: nil)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "creditcard.fill")
                                .poplurIconShader()
                                .font(.system(size: 12, weight: .bold))
                            Text("Get Credits →")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(pinkAI, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(.top, 2)
                }

                if hasResult {
                    PAIMediaPreviewCard(
                        image: message.resultImage,
                        videoURL: message.resultVideoURL,
                        onPost: onPost
                    )
                }
            }

            Spacer(minLength: 28)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { appeared = true }
        }
    }
}

// MARK: - Typing indicator

private struct PAITypingIndicator: View {
    @State private var phase = 0
    @Environment(\.paiTheme) private var theme
    private let timer = Timer.publish(every: 0.45, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(pinkAI.opacity(phase == i ? 1.0 : 0.3))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == i ? 1.3 : 1.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: phase)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(theme.typingBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onReceive(timer) { _ in
            phase = (phase + 1) % 3
        }
    }
}

// MARK: - Generation bubble

private struct PAIGenerationBubble: View {
    let message: PoplurAIChatMessage
    @State private var appeared = false
    @Environment(\.paiTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(pinkAI.opacity(0.85))
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "sparkles")
                        .poplurIconShader()
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 8) {
                ForEach(message.steps) { step in
                    HStack(spacing: 10) {
                        Text(step.emoji)
                            .font(.system(size: 15))
                        Text(step.label)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(
                                step.isCurrent ? theme.genStepActive :
                                step.isComplete ? pinkAI.opacity(0.6) : theme.genStepInactive
                            )
                            .poplurTextShader(intensity: step.isCurrent ? 0.78 : 0.42)
                        Spacer()
                        if step.isComplete {
                            Image(systemName: "checkmark.circle.fill")
                                .poplurIconShader()
                                .font(.system(size: 13))
                                .foregroundStyle(pinkAI)
                        } else if step.isCurrent {
                            PAISpinnerDot()
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(theme.genBubbleBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(pinkAI.opacity(0.25), lineWidth: 0.8)
            )

            Spacer(minLength: 28)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { appeared = true }
        }
    }
}

private struct PAISpinnerDot: View {
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(pinkAI, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 13, height: 13)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .onAppear {
                withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                    spinning = true
                }
            }
    }
}

// MARK: - Media preview card

private struct PAIMediaPreviewCard: View {
    let image: UIImage?
    let videoURL: URL?
    var onPost: (UIImage?, URL?) -> Void

    @State private var isPlaying = false
    @State private var player: AVPlayer? = nil
    @State private var bounced = false

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail / video player
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipped()
                } else if let url = videoURL {
                    PAIVideoPlayer(url: url)
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .clipped()
                }
                // Neon border flash
                RoundedRectangle(cornerRadius: 0, style: .continuous)
                    .stroke(pinkAI.opacity(0.5), lineWidth: 1)
            }
            .frame(height: 200)
            .clipped()

            // Metadata row
            HStack(spacing: 0) {
                metaBadge(icon: "clock", label: "0:15")
                Divider().frame(height: 28).overlay(Color.white.opacity(0.12))
                metaBadge(icon: "square.3.layers.3d", label: "1080p")
                Divider().frame(height: 28).overlay(Color.white.opacity(0.12))
                metaBadge(icon: "doc.fill", label: "8.2 MB")
            }
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06))

            // Action buttons
            HStack(spacing: 8) {
                cardButton("play.fill", "Play", style: .secondary) { isPlaying.toggle() }
                cardButton("arrow.left.arrow.right", "Compare", style: .secondary) {}
                cardButton("arrow.down.circle.fill", "Save", style: .secondary) { saveToLibrary() }
                cardButton("dot.radiowaves.right", "Post", style: .primary) { onPost(image, videoURL) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.05))

            // Edit again
            Button {
                // Would scroll to input and prefill
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                        .poplurIconShader()
                        .font(.system(size: 13))
                    Text("Edit Again")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .poplurTextShader(intensity: 0.68)
                }
                .foregroundStyle(pinkAI)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(pinkAI.opacity(0.08))
            }
            .buttonStyle(.plain)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(pinkAI.opacity(0.45), lineWidth: 1.2)
        )
        .shadow(color: pinkAI.opacity(0.22), radius: 18, y: 6)
        .scaleEffect(bounced ? 1 : 0.88)
        .onAppear {
            withAnimation(.spring(response: 0.48, dampingFraction: 0.62)) { bounced = true }
        }
    }

    private func metaBadge(icon: String, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .poplurIconShader()
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(pinkAI.opacity(0.7))
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
    }

    private func cardButton(_ icon: String, _ label: String, style: ButtonStyle, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .poplurIconShader()
                    .font(.system(size: style == .primary ? 16 : 14, weight: .bold))
                    .foregroundStyle(style == .primary ? .black : .white.opacity(0.8))
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(style == .primary ? .black : .white.opacity(0.7))
                    .poplurTextShader(intensity: style == .primary ? 0.0 : 0.52)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                style == .primary
                    ? AnyShapeStyle(pinkAI)
                    : AnyShapeStyle(Color.white.opacity(0.09)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
        }
        .buttonStyle(PAIPressStyle())
    }

    enum ButtonStyle { case primary, secondary }

    private func saveToLibrary() {
        if let img = image {
            UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        }
    }
}

private struct PAIVideoPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .none
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        context.coordinator.player = player
        context.coordinator.layer = layer
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem, queue: .main
        ) { _ in player.seek(to: .zero); player.play() }
        player.play()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.layer?.frame = uiView.bounds
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.player?.pause()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var player: AVPlayer?; var layer: AVPlayerLayer? }
}

// MARK: - Suggestion chips

private struct PAISuggestionGrid: View {
    @ObservedObject var vm: PoplurAIChatViewModel
    @Environment(\.paiTheme) private var theme

    var body: some View {
        VStack(spacing: 16) {
            // Empty state graphic
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(pinkAI.opacity(0.12))
                        .frame(width: 72, height: 72)
                    Image(systemName: "sparkles")
                        .poplurIconShader()
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(pinkAI)
                }
                Text("What would you like to create?")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.emptyStateText)
                    .poplurTextShader(intensity: theme.isLight ? 0.0 : 0.52)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 8)

            // Chips grid — two columns
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(kSuggestions) { s in
                    Button { vm.sendSuggestion(s) } label: {
                        HStack(spacing: 8) {
                            Text(s.emoji).font(.system(size: 16))
                            Text(s.label)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.chipText)
                                .poplurTextShader(intensity: theme.isLight ? 0.0 : 0.62)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(theme.chipBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(theme.chipBorder, lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(PAIPressStyle())
                }
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Input bar

private struct PAIInputBar: View {
    @ObservedObject var vm: PoplurAIChatViewModel
    var inputFocused: FocusState<Bool>.Binding
    @Environment(\.paiTheme) private var theme

    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem? = nil
    @State private var glitterPulse = false

    var body: some View {
        VStack(spacing: 0) {
            // Attachment chips
            if !vm.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.attachments) { att in
                            PAIAttachmentChip(attachment: att) {
                                vm.removeAttachment(att.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                }
                .frame(height: 58)
            }

            HStack(alignment: .bottom, spacing: 0) {
                // Left: + attach
                Button { showPhotoPicker = true } label: {
                    ZStack {
                        Circle()
                            .stroke(theme.plusButtonStroke, lineWidth: 1.2)
                            .frame(width: 34, height: 34)
                        Image(systemName: "plus")
                            .poplurIconShader()
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(theme.plusButtonIcon)
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .padding(.bottom, 6)

                // Text field + mode pills
                VStack(alignment: .leading, spacing: 4) {
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(theme.inputFieldBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(pinkAI.opacity(inputFocused.wrappedValue ? 0.45 : 0.16), lineWidth: 1)
                            )

                        if vm.inputText.isEmpty {
                            Text("Ask Poplur AI anything...")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(theme.placeholderColor)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $vm.inputText)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.inputTextColor)
                            .tint(pinkAI)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .focused(inputFocused)
                            .frame(minHeight: 36, maxHeight: 100)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }

                    // Mode pills: Search + Smart
                    HStack(spacing: 8) {
                        PAIModePill(
                            icon: "globe",
                            label: "Search",
                            isActive: vm.searchMode
                        ) { vm.searchMode.toggle() }

                        PAIModePill(
                            icon: "sparkles",
                            label: "Smart",
                            isActive: vm.smartMode
                        ) { vm.smartMode.toggle() }

                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 6)
                    .padding(.bottom, 4)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)

                // Right: mic + generate
                HStack(spacing: 8) {
                    Button {} label: {
                        Image(systemName: "mic.fill")
                            .poplurIconShader()
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(theme.micIcon)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    // Glitter generate button
                    Button { vm.send() } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [pinkAI.opacity(0.95), Color(red: 0.8, green: 0.0, blue: 0.5)],
                                        center: .center, startRadius: 0, endRadius: 18
                                    )
                                )
                                .scaleEffect(glitterPulse ? 1.06 : 1.0)
                                .shadow(color: pinkAI.opacity(0.6), radius: 10)

                            Image(systemName: "arrow.up")
                                .poplurIconShader()
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 38, height: 38)
                    }
                    .buttonStyle(PAIPressStyle())
                    .disabled(vm.isGenerating)
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                            glitterPulse = true
                        }
                    }
                }
                .padding(.trailing, 10)
                .padding(.bottom, 6)
            }
        }
        .background(theme.inputBarBg)
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .any(of: [.images, .videos]))
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run {
                        vm.attachments.append(
                            PoplurAIChatAttachment(image: img, fileName: "photo.jpg", fileType: .photo)
                        )
                    }
                }
                selectedPhoto = nil
            }
        }
    }

}

// MARK: - Mode pill (Search / Smart toggle)

private struct PAIModePill: View {
    let icon: String
    let label: String
    let isActive: Bool
    let action: () -> Void
    @Environment(\.paiTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .poplurIconShader()
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isActive ? .black : theme.modePillInactiveText)
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(isActive ? .black : theme.modePillInactiveText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                isActive ? AnyShapeStyle(pinkAI) : AnyShapeStyle(theme.modePillInactiveBg),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(pinkAI.opacity(isActive ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PAIPressStyle())
    }
}

// MARK: - Attachment chip (above input)

private struct PAIAttachmentChip: View {
    let attachment: PoplurAIChatAttachment
    var onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack(alignment: .bottomLeading) {
                if let img = attachment.thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: attachment.typeIcon)
                                .poplurIconShader()
                                .font(.system(size: 16))
                                .foregroundStyle(pinkAI)
                        )
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(pinkAI.opacity(0.3), lineWidth: 0.8)
            )

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .poplurIconShader()
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .background(Circle().fill(Color.black.opacity(0.7)))
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
        }
    }
}

// MARK: - Settings sheet

private struct PAISettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("poplur_ai_chat_theme") private var theme: PoplurAIChatTheme = .prelogin

    var body: some View {
        NavigationStack {
            List {
                Section("Chat Theme") {
                    ForEach(PoplurAIChatTheme.allCases, id: \.self) { t in
                        Button {
                            theme = t
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: t.icon)
                                    .foregroundStyle(pinkAI)
                                    .frame(width: 22)
                                Text(t.displayName)
                                    .font(.system(size: 16, weight: .medium, design: .rounded))
                                    .foregroundStyle(.primary)
                                Spacer()
                                if theme == t {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(pinkAI)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Poplur AI") {
                    Label("Model: Gemini Pro Vision", systemImage: "cpu")
                    Label("Mode: Media Editing", systemImage: "wand.and.stars")
                    Label("Quality: Ultra", systemImage: "sparkles")
                }
                Section("Responses") {
                    Label("Streaming: On", systemImage: "dot.radiowaves.right")
                    Label("Auto-generate: On", systemImage: "sparkles.rectangle.stack.fill")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(pinkAI)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Floating confetti layer

private struct PoplurAIConfettiLayer: View {
    @State private var particles: [PAIConfettiParticle] = []
    private let timer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { p in
                    Diamond()
                        .fill(p.color)
                        .frame(width: p.size, height: p.size)
                        .rotationEffect(.degrees(p.rotation))
                        .position(x: p.x, y: p.y)
                        .opacity(p.opacity)
                }
            }
            .onReceive(timer) { _ in
                spawnParticle(in: geo.size)
                fadeOldParticles()
            }
            .onAppear { spawnInitialBatch(in: geo.size) }
        }
    }

    private func spawnInitialBatch(in size: CGSize) {
        guard particles.isEmpty else { return }
        for _ in 0..<14 {
            particles.append(PAIConfettiParticle(bounds: size))
        }
    }

    private func spawnParticle(in size: CGSize) {
        guard particles.count < 8 else { return }
        particles.append(PAIConfettiParticle(bounds: size))
    }

    private func fadeOldParticles() {
        let cutoff = Date().addingTimeInterval(-8)
        particles.removeAll { $0.born < cutoff }
    }
}

private struct PAIConfettiParticle: Identifiable {
    let id = UUID()
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let rotation: Double
    let color: Color
    let opacity: Double
    let born = Date()

    init(bounds: CGSize) {
        x = CGFloat.random(in: 0...bounds.width)
        y = CGFloat.random(in: 0...bounds.height)
        size = CGFloat.random(in: 5...10)
        rotation = Double.random(in: 0...45)
        opacity = Double.random(in: 0.15...0.45)
        let colors: [Color] = [
            Color(red: 1, green: 0.176, blue: 0.588), // pink
            .purple, .green, .orange, .cyan
        ]
        color = colors.randomElement()!
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Press animation style

private struct PAIPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
