import SwiftUI

struct AppSettingsView: View {
    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var radio = RadioPlaybackController.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                radioSection
                accountSection
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 260)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 1, green: 0.92, blue: 0.97), Color(red: 0.78, green: 0.65, blue: 0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.system(size: 42, weight: .black, design: .rounded))
            Text("Radio and playback controls")
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(Color(red: 0.15, green: 0.07, blue: 0.12))
    }

    private var radioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Radio playback")
                .font(.system(size: 22, weight: .black, design: .rounded))

            ForEach(RadioPlaybackMode.allCases) { mode in
                Button {
                    settings.radioPlaybackMode = mode
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: settings.radioPlaybackMode == mode ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color(red: 0.92, green: 0.12, blue: 0.48))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(mode.title)
                                .font(.system(size: 18, weight: .black, design: .rounded))
                            Text(mode.subtitle)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                    .foregroundStyle(Color(red: 0.15, green: 0.07, blue: 0.12))
                    .padding(16)
                    .background(.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack {
                VStack(alignment: .leading) {
                    Text(radio.isPlaying ? "Radio is playing" : "Radio is stopped")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                    Text(radio.currentTitle)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(radio.isPlaying ? "Pause" : "Play") {
                    radio.isPlaying ? radio.pause() : radio.play()
                }
                .font(.system(size: 15, weight: .black, design: .rounded))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color(red: 0.92, green: 0.12, blue: 0.48), in: Capsule())
                .foregroundStyle(.white)
            }
            .padding(16)
            .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account")
                .font(.system(size: 22, weight: .black, design: .rounded))

            Toggle("Notifications", isOn: Binding(
                get: { settings.notificationsEnabled },
                set: { settings.notificationsEnabled = $0 }
            ))
            .font(.system(size: 18, weight: .black, design: .rounded))
            .padding(16)
            .background(.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 22, style: .continuous))

            Toggle("Private account", isOn: Binding(
                get: { settings.isPrivateAccount },
                set: { settings.isPrivateAccount = $0 }
            ))
            .font(.system(size: 18, weight: .black, design: .rounded))
            .padding(16)
            .background(.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}
