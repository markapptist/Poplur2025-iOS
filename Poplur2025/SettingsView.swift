import SwiftUI

struct SettingsView: View {
    // Brand color (sRGB) #FF2D96
    private let brandPink = Color(red: 1.0, green: 45.0/255.0, blue: 150.0/255.0)

    var body: some View {
        GeometryReader { geo in
            VStack {
                Spacer(minLength: 0)
                ZStack {
                    TicketBackground()
                        .fill(brandPink)
                        .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 10)

                    VStack(spacing: 16) {
                        Text("Settings Ticket Loaded")
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                        Text("If you can read this, the tab is using the correct SettingsView.swift")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.95))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
                .frame(width: min(geo.size.width - 24, 700), height: geo.size.height * 0.78)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.clear)
    }
}

// Same ticket shape used before
private struct TicketBackground: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner: CGFloat = 24
        let rounded = UIBezierPath(roundedRect: rect, cornerRadius: corner).cgPath
        path.addPath(Path(rounded))

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

