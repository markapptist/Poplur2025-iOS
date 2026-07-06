import SwiftUI

struct PremiumAIAssistPanel: View {
    var mediaType: PoplurAIContentType
    var locationName: String
    var basePrompt: String
    var onUseGeneratedText: (String) -> Void
    var onUpgrade: () -> Void

    @StateObject private var viewModel = PremiumAIViewModel()
    @State private var selectedAction: PremiumAIAction = .generateCaption
    @State private var captionDirection = ""
    @State private var ideaCategory = ""
    @State private var ideaVibe = ""
    @State private var businessName = ""
    @State private var businessType = ""
    @State private var offerDetails = ""
    @State private var translateText = ""
    @State private var targetLanguage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            panelHeader

            if viewModel.entitlement == nil {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, minHeight: 96)
            } else if viewModel.entitlement?.isPremium != true {
                upsellView
            } else {
                premiumControls
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.07)))
        .task {
            await viewModel.loadEntitlement()
        }
    }

    private var panelHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Label("Premium AI", systemImage: "sparkles")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text(usageText)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }
            Spacer()
            if viewModel.isLoading {
                ProgressView()
                    .tint(.green)
            }
        }
    }

    private var usageText: String {
        guard let entitlement = viewModel.entitlement else {
            return "Checking Premium access..."
        }

        guard entitlement.isPremium else {
            return "Included with Premium."
        }

        return "\(entitlement.remaining) AI generations left this month"
    }

    private var upsellView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Poplur AI is included with Premium.")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Button(action: onUpgrade) {
                Text("Upgrade to Premium")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white))
            }
        }
    }

    private var premiumControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PremiumAIAction.allCases) { action in
                        Button {
                            selectedAction = action
                            viewModel.errorMessage = nil
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(action == selectedAction ? .black : .white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(action == selectedAction ? Color.white : Color.white.opacity(0.11))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            actionFields

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    await viewModel.run(action: selectedAction, input: requestInput)
                }
            } label: {
                Label(viewModel.isLoading ? "Generating..." : "Run AI Assist", systemImage: "sparkles")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(RoundedRectangle(cornerRadius: 8).fill(canRun ? Color.white : Color.white.opacity(0.38)))
            }
            .disabled(!canRun || viewModel.isLoading)

            if !viewModel.generatedText.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Editable Result")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                    TextEditor(text: $viewModel.generatedText)
                        .scrollContentBackground(.hidden)
                        .foregroundStyle(.white)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .frame(minHeight: 150)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
                    Button {
                        onUseGeneratedText(viewModel.generatedText)
                    } label: {
                        Label("Use In Create Prompt", systemImage: "arrow.down.doc.fill")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.32), lineWidth: 1))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionFields: some View {
        switch selectedAction {
        case .generateCaption:
            field("Caption direction", text: $captionDirection, placeholder: basePrompt.ifEmpty("Tell AI the style or angle you want."))
        case .suggestPostIdea:
            field("Location", text: .constant(locationName.ifEmpty("Selected location")), placeholder: "Location")
            field("Category", text: $ideaCategory, placeholder: "Food, news, nightlife, shopping...")
            field("Vibe", text: $ideaVibe, placeholder: "Funny, luxury, urgent, cozy...")
        case .businessPromo:
            field("Business name", text: $businessName, placeholder: "Business name")
            field("Business type", text: $businessType, placeholder: "Cafe, barber, boutique...")
            field("Offer details", text: $offerDetails, placeholder: "What should the promo include?")
            field("Location", text: .constant(locationName.ifEmpty("Selected location")), placeholder: "Location")
        case .translateCaption:
            field("Caption", text: $translateText, placeholder: basePrompt.ifEmpty("Paste caption to translate."))
            field("Target language", text: $targetLanguage, placeholder: "Spanish, French, Arabic...")
        }
    }

    private func field(_ title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.08)))
        }
    }

    private var requestInput: [String: Any] {
        switch selectedAction {
        case .generateCaption:
            return compact([
                "mediaType": mediaWireValue,
                "locationName": locationName,
                "userPrompt": captionDirection.ifEmpty(basePrompt)
            ])
        case .suggestPostIdea:
            return compact([
                "locationName": locationName.ifEmpty("Selected location"),
                "category": ideaCategory,
                "vibe": ideaVibe
            ])
        case .businessPromo:
            return compact([
                "businessName": businessName,
                "businessType": businessType,
                "offerDetails": offerDetails,
                "locationName": locationName.ifEmpty("Selected location")
            ])
        case .translateCaption:
            return compact([
                "text": translateText.ifEmpty(basePrompt),
                "targetLanguage": targetLanguage
            ])
        }
    }

    private var canRun: Bool {
        switch selectedAction {
        case .generateCaption:
            return !captionDirection.ifEmpty(basePrompt).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .suggestPostIdea:
            return !ideaCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !ideaVibe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .businessPromo:
            return !businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !businessType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !offerDetails.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .translateCaption:
            return !translateText.ifEmpty(basePrompt).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !targetLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var mediaWireValue: String {
        mediaType == .video || mediaType == .vfxVideo ? "video" : "image"
    }

    private func compact(_ values: [String: String]) -> [String: Any] {
        values.reduce(into: [String: Any]()) { result, pair in
            let trimmed = pair.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                result[pair.key] = trimmed
            }
        }
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
