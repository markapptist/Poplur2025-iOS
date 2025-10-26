//
//  AppSettingsView.swift
//  Poplur2025
//
//  Created by Maxine Moodie on 2025-10-26.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct AppSettingsView: View {
    // Pager: 0 = Statistics, 1 = Settings
    @State private var pageIndex: Int = 0

    // Toggles
    @State private var isPrivateAccount = false
    @State private var notificationsEnabled = true

    // Stats
    @State private var posts: [Post] = []
    @State private var isLoadingStats = true

    // Computed stats
    private var totalRadius: Int {
        posts.reduce(0) { $0 + $1.radius }
    }
    private var averageRadius: Double {
        guard !posts.isEmpty else { return 0 }
        return Double(totalRadius) / Double(posts.count)
    }
    private var ringMax: Double {
        let km = max(1.0, Double(totalRadius) / 1000.0)
        let rounded = ceil(km / 1000.0) * 1000.0
        return max(50_000, rounded) * 1000.0
    }

    // Screen-based sizing
    private var screenSize: CGSize { UIScreen.main.bounds.size }
    private var ticketWidth: CGFloat { min(screenSize.width - 24, 700) }
    private var ticketHeight: CGFloat { screenSize.height * 0.78 }

    // Brand color (sRGB) #FF2D96
    private let brandPink = Color(red: 1.0, green: 45.0/255.0, blue: 150.0/255.0)

    var body: some View {
        ZStack {
            // Light canvas behind the ticket
            Color(white: 0.96).ignoresSafeArea()

            VStack {
                Spacer(minLength: 0)

                TicketCard(
                    pageIndex: $pageIndex,
                    isPrivateAccount: $isPrivateAccount,
                    notificationsEnabled: $notificationsEnabled,
                    isLoadingStats: $isLoadingStats,
                    statsHeaderTitle: "Statistics",
                    settingsHeaderTitle: "Settings",
                    statsPage: { statsPage },
                    settingsPage: { settingsPage },
                    brandPink: brandPink
                )
                .frame(width: ticketWidth, height: ticketHeight)

                Spacer(minLength: 0)
            }
        }
        .onAppear { loadStats() }
    }

    // MARK: - Pages

    private var statsPage: some View {
        VStack(spacing: 28) {
            Spacer().frame(height: 8)

            Text("Average Radius")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)

            if isLoadingStats {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            } else {
                RingStatView(
                    value: averageRadius,
                    maxValue: ringMax,
                    unit: "KM",
                    accentColor: .black,
                    trackColor: .white.opacity(0.25),
                    lineWidthFactor: 0.12
                )
                .frame(height: 280)
                .padding(.top, 4)
            }

            VStack(spacing: 10) {
                Text("Accumulated Radius")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)

                if isLoadingStats {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                } else {
                    Text("You’ve reached")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))

                    Text(formattedKM(totalRadius))
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    Text("in total")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
    }

    private var settingsPage: some View {
        VStack(spacing: 30) {
            Spacer().frame(height: 8)

            Text("Account Options")
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white)

            VStack(spacing: 28) {
                toggleRow(title: "Private Account", isOn: $isPrivateAccount)
                toggleRow(title: "Notifications", isOn: $notificationsEnabled)
                navRow(title: "Email Address") { /* push email editor */ }
                navRow(title: "Password") { /* push password editor */ }
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)

            Button(action: signOut) {
                Text("Sign Out")
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white, in: Capsule())
                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
            }
            .padding(.horizontal, 48)
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Rows + helpers

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: Color(.systemIndigo)))
        }
    }

    private func navRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Color(.systemIndigo))
            }
        }
        .buttonStyle(.plain)
    }

    private func loadStats() {
        guard let userId = Auth.auth().currentUser?.uid else {
            self.posts = []
            self.isLoadingStats = false
            return
        }
        isLoadingStats = true
        let db = FirebaseFirestore.Firestore.firestore()
        db.collection("posts").whereField("userID", isEqualTo: userId).getDocuments { snapshot, error in
            if let error = error {
                print("Stats fetch error: \(error.localizedDescription)")
                self.posts = []
                self.isLoadingStats = false
                return
            }
            self.posts = snapshot?.documents.compactMap { doc in
                let data = doc.data()
                return Post(
                    id: doc.documentID,
                    latitude: data["latitude"] as? Double ?? 0,
                    longitude: data["longitude"] as? Double ?? 0,
                    mediaURL: data["mediaURL"] as? String ?? "",
                    radius: data["radius"] as? Int ?? 0,
                    viewCount: data["viewCount"] as? Int ?? 0
                )
            } ?? []
            self.isLoadingStats = false
        }
    }

    private func signOut() {
        do { try Auth.auth().signOut() } catch {
            print("Sign out failed: \(error.localizedDescription)")
        }
    }

    private func formattedKM(_ meters: Int) -> String {
        let km = Double(meters) / 1000.0
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 0
        return (nf.string(from: NSNumber(value: km)) ?? "\(Int(km))") + " KM"
    }
}

// MARK: - Ticket Card container (pink panel + paging + dots; no close button)

private struct TicketCard<Stats: View, Settings: View>: View {
    @Binding var pageIndex: Int
    @Binding var isPrivateAccount: Bool
    @Binding var notificationsEnabled: Bool
    @Binding var isLoadingStats: Bool

    let statsHeaderTitle: String
    let settingsHeaderTitle: String

    @ViewBuilder var statsPage: () -> Stats
    @ViewBuilder var settingsPage: () -> Settings

    let brandPink: Color

    var body: some View {
        ZStack {
            TicketBackground()
                .fill(brandPink) // brand pink #FF2D96
                .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)

            VStack(spacing: 18) {
                // Header
                HStack {
                    Image(systemName: pageIndex == 0 ? "waveform.path.ecg" : "gearshape.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    Text(pageIndex == 0 ? statsHeaderTitle : settingsHeaderTitle)
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Color.clear.frame(width: 18)
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)

                // Pager
                TabView(selection: $pageIndex) {
                    statsPage().tag(0)
                    settingsPage().tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Dots
                HStack(spacing: 10) {
                    Circle()
                        .fill(pageIndex == 0 ? Color.white : Color.white.opacity(0.6))
                        .frame(width: 10, height: 10)
                    Circle()
                        .fill(pageIndex == 1 ? Color.white : Color.white.opacity(0.6))
                        .frame(width: 10, height: 10)
                }
                .padding(.bottom, 24)
            }
        }
        // Removed the bottom close button overlay
    }
}

// MARK: - Ticket background with scalloped bottom (holes)

private struct TicketBackground: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Rounded rect
        let corner: CGFloat = 24
        let rounded = UIBezierPath(roundedRect: rect, cornerRadius: corner).cgPath
        path.addPath(Path(rounded))

        // Scallops (holes) near the bottom edge
        let diameter: CGFloat = 18
        let spacing: CGFloat = 8
        let total = Int((rect.width + spacing) / (diameter + spacing))
        let y = rect.maxY - diameter / 2 - 4

        for i in 0..<total {
            let x = rect.minX + (CGFloat(i) * (diameter + spacing)) + diameter / 2
            let circle = CGRect(x: x - diameter/2, y: y - diameter/2, width: diameter, height: diameter)
            path.addEllipse(in: circle)
        }

        // Even-odd rule to cut the circles out of the card
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

// MARK: - Big ring view (center labels like mock)

private struct RingStatView: View {
    let value: Double        // meters
    let maxValue: Double     // meters
    let unit: String         // "KM"
    let accentColor: Color
    let trackColor: Color
    let lineWidthFactor: CGFloat

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let lineWidth = size * lineWidthFactor
            let progress = max(0, min(value / maxValue, 1))

            ZStack {
                Circle()
                    .stroke(trackColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 6) {
                    Text(DateFormatter.shortMonthDay.string(from: Date()).uppercased())
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(String(format: "%.1f %@", value / 1000.0, unit))
                        .font(.system(size: 42, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text("on average")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                }
            }
            .frame(width: size, height: size)
        }
    }
}

private extension DateFormatter {
    static let shortMonthDay: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("MMM d")
        return df
    }()
}
