import SwiftUI
import StoreKit

struct SettingsView: View {
    // Brand color (sRGB) #FF2D96
    private let brandPink = Color(red: 255.0/255.0, green: 255.0/255.0, blue: 255.0/255.0)
    
    @EnvironmentObject var quota: DailyQuotaViewModel
    @EnvironmentObject var skinManager: PoplurCubeSkinManager
    @StateObject private var purchaseVM = PurchaseViewModel()
    @State private var selectedSkin: PoplurCubeSkinStyle = .neon

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // White background replacing ticket background
                Color.white
                    .ignoresSafeArea() // extend under status/home areas

                // Replace with your real settings content
                ScrollView {
                    VStack(spacing: 24) {
                        Text("Settings")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.top, 24)

                        Text("Account Options")
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundColor(.black.opacity(0.9))
                            .padding(.top, 8)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Daily Posts")
                                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                                    .foregroundColor(.black)
                                Spacer()
                                Text("Remaining: \(quota.remainingPosts)/\(quota.dailyPostLimit)")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }

                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .poplurIconShader()
                                    .foregroundColor(.indigo)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Boost your daily limit")
                                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                                    Text("Upgrade to 15 posts/day for $9.99")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button {
                                    Task { await purchaseVM.buyUpgrade(quota: quota) }
                                } label: {
                                    Text(quota.hasDailyUpgrade ? "Purchased" : "$9.99")
                                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                                        .foregroundColor(.white)
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 16)
                                        .background(quota.hasDailyUpgrade ? Color.gray : Color.indigo, in: Capsule())
                                }
                                .disabled(quota.hasDailyUpgrade)
                            }
                            
                            Text("Upgrades are permanent and your daily count resets at midnight.")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.secondary)

                            HStack {
                                Spacer()
                                Button {
                                    Task { await purchaseVM.restoreIfNeeded(quota: quota) }
                                } label: {
                                    Text("Restore Purchases")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.indigo)
                                }
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.gray.opacity(0.08))
                        )
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Cube Skin")
                                .font(.system(size: 18, weight: .heavy, design: .rounded))
                                .foregroundColor(.black.opacity(0.9))

                            Picker("Skin", selection: $selectedSkin) {
                                ForEach(PoplurCubeSkinStyle.allCases, id: \.self) { style in
                                    Text(style.rawValue.capitalized).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)

                            // Apply immediately on change
                            .onChange(of: selectedSkin) { _, newStyle in
                                skinManager.setStyle(newStyle)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.gray.opacity(0.08))
                        )

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
                                .foregroundColor(.white)
                                .padding(.vertical, 16)
                                .frame(maxWidth: .infinity)
                                .background(brandPink, in: Capsule())
                                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                        }
                        .padding(.top, 24)

                        Spacer(minLength: 80) // leave room above scallops
                    }
                    .padding(.horizontal, 24) // internal padding only
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .onAppear { selectedSkin = skinManager.current.style }
                }
                .scrollIndicators(.hidden)
                .scrollContentBackground(.hidden)
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea() // scroll content goes edge-to-edge
                .task {
                    try? await purchaseVM.loadProducts()
                    await purchaseVM.restoreIfNeeded(quota: quota)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        .background(Color.white)
    }

    // MARK: - Row helpers

    private func settingsRowLeft<Accessory: View>(_ title: String,
                                                  @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.black)
            Spacer()
            accessory()
        }
    }

    private func settingsRowRight(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundColor(.black)
            Spacer()
            Image(systemName: "arrow.right")
                .poplurIconShader()
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.gray)
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
