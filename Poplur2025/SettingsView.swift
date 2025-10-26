import SwiftUI

struct SettingsView: View {
    @State private var notificationsEnabled = true
    @State private var useCellularData = true
    @State private var saveToLibrary = true

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("General")) {
                    Toggle("Notifications", isOn: $notificationsEnabled)
                    Toggle("Use Cellular Data", isOn: $useCellularData)
                    Toggle("Save Captures to Photos", isOn: $saveToLibrary)
                }

                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
}
