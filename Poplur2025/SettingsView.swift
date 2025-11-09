import SwiftUI

struct SettingsView: View {
    // Brand color (sRGB) #FF2D96
    private let brandPink = Color(red: 1.0, green: 45.0/255.0, blue: 150.0/255.0)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Full-bleed ticket background
                TicketBackground()
                    .fill(brandPink)
                    .ignoresSafeArea() // extend under status/home areas
                    .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)

                // Replace with your real settings content
                ScrollView {
                    VStack(spacing: 24) {
                        Text("Settings")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.top, 24)

                        Text("Account Options")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(.white.opacity(0.95))
                            .padding(.top, 8)

                        // Demo rows (swap for real toggles/links)
                        settingsRowLeft("Private Account") {
                            Toggle("", isOn: .constant(true))
                                .labelsHidden()
                                .tint(.indigo)
                        }
                        settingsRowLeft("Notifications") {
                            Toggle("", isOn: .constant(true))
                                .labelsHidden()
                                .tint(.indigo)
                        }
                        settingsRowRight("Email Address")
                        settingsRowRight("Password")

                        Button {
                            // sign out
                        } label: {
                            Text("Sign Out")
                                .font(.system(size: 20, weight: .heavy, design: .rounded))
                                .foregroundColor(.black)
                                .padding(.vertical, 16)
                                .frame(maxWidth: .infinity)
                                .background(Color.white, in: Capsule())
                                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                        }
                        .padding(.top, 24)

                        Spacer(minLength: 80) // leave room above scallops
                    }
                    .padding(.horizontal, 24) // internal padding only
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea() // scroll content goes edge-to-edge
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.clear)
    }

    // MARK: - Row helpers

    private func settingsRowLeft<Accessory: View>(_ title: String,
                                                  @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            accessory()
        }
    }

    private func settingsRowRight(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.indigo.opacity(0.95))
        }
    }
}

// Same ticket shape used before, now drawn full-bleed
private struct TicketBackground: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner: CGFloat = 24
        let rounded = UIBezierPath(roundedRect: rect, cornerRadius: corner).cgPath
        path.addPath(Path(rounded))

        // Scallops along the bottom edge
        let diameter: CGFloat = 18
        let spacing: CGFloat = 8
        let total = Int((rect.width + spacing) / (diameter + spacing))
        let y = rect.maxY - diameter / 2 - 4

        for i in 0..<total {
            let x = rect.minX + (CGFloat(i) * (diameter + spacing)) + diameter / 2
            let circle = CGRect(x: x - diameter/2, y: y - diameter/2, width: diameter, height: diameter)
            path.addEllipse(in: circle)
        }
        return path.eoFilled()
    }
}

private extension Path {
    func eoFilled() -> Path {
        var p = self
        p = p.strokedPath(.init(lineWidth: 0))
        return p
    }
}
