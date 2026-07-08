import SwiftUI
import CoreLocation

// MARK: - Design palette (sampled from the Create mockup)

private enum CreateC {
    static let pageBG      = Color(red: 254/255, green: 240/255, blue: 245/255) // #FEF0F5
    static let card        = Color(red: 253/255, green: 246/255, blue: 249/255)
    static let creditsCard = Color(red: 254/255, green: 248/255, blue: 252/255)
    static let tabTrack    = Color(red: 249/255, green: 227/255, blue: 235/255) // #F9E3EB
    static let accent      = Color(red: 247/255, green: 44/255,  blue: 134/255) // #F72C86
    static let title       = Color(red: 16/255,  green: 20/255,  blue: 38/255)
    static let subtitle    = Color(red: 128/255, green: 128/255, blue: 142/255)
    static let tabInactive = Color(red: 92/255,  green: 92/255,  blue: 106/255)
}

/// The eight tools shown in the Create mockup, in mockup order.
private let createTools: [PoplurAIContentType] = [
    .image, .video, .threeDModel, .voice, .music, .game, .vfx, .coupon
]

private func createIconAsset(for type: PoplurAIContentType) -> String {
    switch type {
    case .image:        return "create_ic_image"
    case .video:        return "create_ic_video"
    case .threeDModel:  return "create_ic_3d"
    case .voice:        return "create_ic_voice"
    case .music:        return "create_ic_music"
    case .game:         return "create_ic_game"
    case .vfx, .vfxVideo: return "create_ic_vfx"
    case .coupon, .campaign, .edit: return "create_ic_coupon"
    }
}

struct PoplurAICreateView: View {
    @State private var selectedType: PoplurAIContentType = .image
    @State private var prompt: String = ""
    @State private var credits: Int = 0
    @State private var plan: PoplurPlan = .free
    @State private var status: PoplurAIGenerationStatus = .queued
    @State private var resultText: String?
    @State private var locationName: String = ""
    @State private var radiusMeters: Double = 1_000
    @State private var destination: String = "Profile"
    @State private var wantsBoost: Bool = false
    @State private var showToolSheet = false

    private let config = PoplurAIStackConfig.productionDefaults

    var body: some View {
        ZStack {
            CreateC.pageBG.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    planTabs
                    toolGrid
                    comingSoonCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.never)
        }
        .sheet(isPresented: $showToolSheet) {
            toolSheet
        }
    }

    private var selectedCost: Int { config.estimatedCost(for: selectedType) }

    private var canGenerate: Bool {
        plan.canGenerateAI(with: credits) && credits >= selectedCost
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    // Same icon shown in the hold-menu wheel that opens this screen.
                    HoldMenuIconBadge(icon: HoldMenuIcons.create, size: 44)
                    Text("Create")
                        .font(.system(size: 44, weight: .black, design: .rounded))
                        .foregroundStyle(CreateC.title)
                }
                Text("Use Creator Credits to generate premium AI content, then publish it to a real Poplur map location.")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(CreateC.subtitle)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            creditsCard
        }
    }

    private var creditsCard: some View {
        HStack(spacing: 10) {
            Image("create_ic_credits")
                .resizable()
                .scaledToFit()
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 0) {
                Text("\(credits)")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(CreateC.accent)
                Text("Creator Credits")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(CreateC.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background(CreateC.creditsCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 4)
        .frame(width: 190)
    }

    // MARK: - Plan tabs

    private var planTabs: some View {
        HStack(spacing: 0) {
            ForEach(PoplurPlan.allCases, id: \.self) { item in
                let isOn = item == plan
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { plan = item }
                } label: {
                    Text(item.rawValue.capitalized)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(isOn ? .white : CreateC.tabInactive)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(
                            Capsule().fill(isOn ? CreateC.accent : .clear)
                                .shadow(color: isOn ? CreateC.accent.opacity(0.35) : .clear, radius: 8, x: 0, y: 4)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(CreateC.tabTrack, in: Capsule())
    }

    // MARK: - Tool grid

    private var toolGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
            spacing: 14
        ) {
            ForEach(createTools) { type in
                toolCard(type)
            }
        }
    }

    private func toolCard(_ type: PoplurAIContentType) -> some View {
        let isSelected = type == selectedType
        return Button {
            selectedType = type
            status = .queued
            resultText = nil
            showToolSheet = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Image(createIconAsset(for: type))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 62, height: 62)

                Text(type.displayName)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(CreateC.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(type.providerLabel)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(CreateC.subtitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .padding(16)
            .background(CreateC.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isSelected ? CreateC.accent : Color.clear, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.03), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Coming soon

    private var comingSoonCard: some View {
        HStack(spacing: 12) {
            VStack(spacing: 10) {
                Image(systemName: "sparkle")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.24))
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(Color(red: 0.24, green: 0.76, blue: 0.98))
                Image(systemName: "sparkle")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(CreateC.accent)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("More tools coming soon!")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(CreateC.title)
                Text("We're adding new ways for you to create and share on Poplur.")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(CreateC.subtitle)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Image("create_ic_p")
                .resizable()
                .scaledToFit()
                .frame(width: 62, height: 62)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CreateC.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Tool sheet (generate + publish flow)

    private var toolSheet: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    Image(createIconAsset(for: selectedType))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedType.displayName)
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(CreateC.title)
                        Text(selectedType.providerLabel)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(CreateC.subtitle)
                    }
                    Spacer()
                    Button {
                        showToolSheet = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(CreateC.subtitle.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }

                promptPanel
                PremiumAIAssistPanel(
                    mediaType: selectedType,
                    locationName: locationName,
                    basePrompt: prompt,
                    onUseGeneratedText: { generated in
                        prompt = generated
                        resultText = generated
                        status = .completed
                    },
                    onUpgrade: {
                        resultText = "Poplur AI is included with Premium. Open Premium from settings or the store to upgrade."
                    }
                )
                publishPanel
                resultPanel
            }
            .padding(20)
        }
        .background(CreateC.pageBG.ignoresSafeArea())
    }

    private var promptPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Prompt")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(CreateC.title)
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(selectedCost)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(CreateC.title)
                    Text("credits")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(CreateC.subtitle)
                }
            }

            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("Describe what Poplur AI should create.")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(CreateC.subtitle)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                }
                TextEditor(text: $prompt)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(CreateC.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .tint(CreateC.accent)
                    .frame(minHeight: 120)
                    .padding(10)
            }
            .background(CreateC.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if !canGenerate {
                Text("Use Creator Credits to generate AI content.")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.orange)
            }

            Button {
                startPlaceholderJob()
            } label: {
                Label("Generate", systemImage: "sparkles")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Capsule().fill(canGenerate ? CreateC.accent : CreateC.subtitle.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .disabled(!canGenerate || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(18)
        .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var publishPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Publish to Map")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(CreateC.title)

            TextField("Location name", text: $locationName)
                .textFieldStyle(.plain)
                .foregroundStyle(CreateC.title)
                .tint(CreateC.accent)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .padding(14)
                .background(CreateC.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Picker("Destination", selection: $destination) {
                Text("Profile").tag("Profile")
                Text("Business").tag("Business")
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading) {
                Text("\(Int(radiusMeters)) m radius")
                    .foregroundStyle(CreateC.subtitle)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                Slider(value: $radiusMeters, in: 250...10_000, step: 250)
                    .tint(CreateC.accent)
            }

            Toggle("Boost radius with credits", isOn: $wantsBoost)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(CreateC.title)
                .tint(CreateC.accent)

            Button {
                resultText = "Ready to publish \(selectedType.rawValue) to \(locationName.ifEmpty("selected map location"))."
            } label: {
                Label("Publish to Map", systemImage: "mappin.and.ellipse")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(CreateC.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Job Status")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(CreateC.title)
            Text(status.rawValue.capitalized)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.22, green: 0.70, blue: 0.32))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(CreateC.card)
                .frame(height: 170)
                .overlay {
                    Text(resultText ?? "Generated content preview will appear here.")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(CreateC.subtitle)
                        .multilineTextAlignment(.center)
                        .padding()
                }
        }
        .padding(18)
        .background(.white.opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func startPlaceholderJob() {
        guard canGenerate else { return }
        credits -= selectedCost
        status = .processing
        resultText = "Queued through Poplur AI backend. Provider credentials stay server-side."
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}

#Preview {
    PoplurAICreateView()
}
