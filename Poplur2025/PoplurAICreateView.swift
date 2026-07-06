import SwiftUI
import CoreLocation

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

    private let config = PoplurAIStackConfig.productionDefaults

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    createMenu
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
                .padding(.bottom, 32)
            }
        }
    }

    private var selectedCost: Int {
        config.estimatedCost(for: selectedType)
    }

    private var canGenerate: Bool {
        plan.canGenerateAI(with: credits) && credits >= selectedCost
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create")
                .font(DS.Font.title(36))
                .foregroundStyle(DS.Color.textPrimary)
            Text("Use Creator Credits to generate premium AI content, then publish it to a real Poplur map location.")
                .font(DS.Font.caption(15))
                .foregroundStyle(DS.Color.textSecondary)
            HStack {
                Label("\(credits) Creator Credits", systemImage: "bolt.circle.fill")
                    .foregroundStyle(DS.Color.accent)
                Spacer()
                Picker("Plan", selection: $plan) {
                    ForEach(PoplurPlan.allCases, id: \.self) { plan in
                        Text(plan.rawValue.capitalized).tag(plan)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .font(.system(size: 13, weight: .black, design: .rounded))
        }
    }

    private var createMenu: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 142), spacing: 10)], spacing: 10) {
            ForEach([PoplurAIContentType.image, .video, .threeDModel, .voice, .music, .game, .vfx, .coupon, .campaign]) { type in
                Button {
                    selectedType = type
                    status = .queued
                    resultText = nil
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: type.systemImage)
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(type == selectedType ? DS.Color.accent : DS.Color.textPrimary)
                        Text(type.displayName)
                            .font(.system(size: 15, weight: .black, design: .rounded))
                            .foregroundStyle(DS.Color.textPrimary)
                        Text(type.providerLabel)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(DS.Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
                    .padding(14)
                    .background(
                        type == selectedType ? DS.Color.pinkCard : DS.Color.card,
                        in: RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                            .stroke(type == selectedType ? DS.Color.accent.opacity(0.5) : DS.Color.border, lineWidth: 1.5)
                    )
                    .shadow(color: .black.opacity(0.04), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var promptPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedType.displayName)
                        .font(DS.Font.heading(22))
                        .foregroundStyle(DS.Color.textPrimary)
                    Text(selectedType.providerLabel)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.22, green: 0.70, blue: 0.32))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(selectedCost)")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(DS.Color.textPrimary)
                    Text("credits")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(DS.Color.textSecondary)
                }
            }

            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("Describe what Poplur AI should create.")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Color.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
                TextEditor(text: $prompt)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(DS.Color.textPrimary)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .tint(DS.Color.accent)
                    .frame(minHeight: 130)
                    .padding(10)
            }
            .background(DS.Color.fill, in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                    .stroke(DS.Color.border, lineWidth: 1)
            )

            if !canGenerate {
                Text("Use Creator Credits to generate AI content.")
                    .font(.system(size: 14, weight: .black, design: .rounded))
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
                    .background(
                        Capsule().fill(canGenerate ? DS.Color.accent : DS.Color.textSecondary.opacity(0.4))
                    )
            }
            .disabled(!canGenerate || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(18)
        .poplurCard()
    }

    private var publishPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Publish to Map")
                .font(DS.Font.heading(20))
                .foregroundStyle(DS.Color.textPrimary)
            TextField("Location name", text: $locationName)
                .textFieldStyle(.plain)
                .foregroundStyle(DS.Color.textPrimary)
                .tint(DS.Color.accent)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .padding(14)
                .background(DS.Color.fill, in: RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.input, style: .continuous)
                        .stroke(DS.Color.border, lineWidth: 1)
                )
            Picker("Destination", selection: $destination) {
                Text("Profile").tag("Profile")
                Text("Business").tag("Business")
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading) {
                Text("\(Int(radiusMeters)) m radius")
                    .foregroundStyle(DS.Color.textSecondary)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                Slider(value: $radiusMeters, in: 250...10_000, step: 250)
                    .tint(DS.Color.accent)
            }
            Toggle("Boost radius with credits", isOn: $wantsBoost)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(DS.Color.textPrimary)
                .tint(DS.Color.accent)
            Button {
                resultText = "Ready to publish \(selectedType.rawValue) to \(locationName.ifEmpty("selected map location"))."
            } label: {
                Label("Publish to Map", systemImage: "mappin.and.ellipse")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(DS.Color.accent))
            }
        }
        .padding(18)
        .poplurCard()
    }

    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Job Status")
                .font(DS.Font.heading(17))
                .foregroundStyle(DS.Color.textPrimary)
            Text(status.rawValue.capitalized)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 0.22, green: 0.70, blue: 0.32))
            RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                .fill(DS.Color.fill)
                .frame(height: 180)
                .overlay {
                    Text(resultText ?? "Generated content preview will appear here.")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding()
                }
        }
        .padding(18)
        .poplurCard()
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
