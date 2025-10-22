import SwiftUI

// MARK: - Reusable components shared by WelcomeView, LoginView, etc.

struct PillButtonLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(.headline, design: .rounded).weight(.bold))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
            )
    }
}

struct FlowerBadge: View {
    var body: some View {
        ZStack {
            FlowerShape(petals: 4, radius: 84, innerRadius: 58)
                .fill(Color.white.opacity(0.18))
                .blur(radius: 0.5)

            FlowerShape(petals: 4, radius: 80, innerRadius: 54)
                .stroke(Color.white, lineWidth: 10)
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 6)

            FlowerShape(petals: 4, radius: 72, innerRadius: 48)
                .fill(Color.white.opacity(0.12))

            Text("P")
                .font(.system(size: 64, weight: .black, design: .rounded))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.35), radius: 10, x: 4, y: 6)
        }
        .frame(width: 200, height: 200)
    }
}

struct FlowerShape: Shape {
    var petals: Int = 4
    var radius: CGFloat = 80
    var innerRadius: CGFloat = 54

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let offsets: [CGPoint] = [
            CGPoint(x: 0, y: -radius),
            CGPoint(x: radius, y: 0),
            CGPoint(x: 0, y: radius),
            CGPoint(x: -radius, y: 0)
        ]
        var path = Path()
        let corner: CGFloat = 48

        for i in 0..<4 {
            let startAngle = Angle.degrees(Double(i) * 90 - 45)
            let endAngle = Angle.degrees(Double(i + 1) * 90 - 45)
            let start = CGPoint(x: center.x + cos(CGFloat(startAngle.radians)) * innerRadius,
                                y: center.y + sin(CGFloat(startAngle.radians)) * innerRadius)
            let end = CGPoint(x: center.x + cos(CGFloat(endAngle.radians)) * innerRadius,
                              y: center.y + sin(CGFloat(endAngle.radians)) * innerRadius)
            if i == 0 { path.move(to: start) } else { path.addLine(to: start) }

            let lobeCenter = CGPoint(x: center.x + offsets[i].x,
                                     y: center.y + offsets[i].y)
            path.addRoundedRect(in: CGRect(x: lobeCenter.x - corner,
                                           y: lobeCenter.y - corner,
                                           width: corner * 2,
                                           height: corner * 2),
                                cornerSize: CGSize(width: corner, height: corner))
            path.addLine(to: end)
        }
        path.closeSubpath()
        return path
    }
}

struct ScallopedEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        let diameter: CGFloat = 18
        let spacing: CGFloat = 8
        let total = Int((rect.width + spacing) / (diameter + spacing))
        let y = rect.midY
        for i in 0..<total {
            let x = (CGFloat(i) * (diameter + spacing)) + diameter / 2
            path.addEllipse(in: CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter))
        }
        return path
    }
}

struct DottedMapOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let dotSize: CGFloat = 6
            let spacing: CGFloat = 10
            let cols = Int(geo.size.width / (dotSize + spacing))
            let rows = Int(geo.size.height / (dotSize + spacing * 1.2))
            ZStack {
                ForEach(0..<rows, id: \.self) { r in
                    ForEach(0..<cols, id: \.self) { c in
                        Circle()
                            .fill(Color.white.opacity((r + c) % 7 == 0 ? 0.9 : 0.35))
                            .frame(width: dotSize, height: dotSize)
                            .offset(x: CGFloat(c) * (dotSize + spacing) - geo.size.width/2 + dotSize,
                                    y: CGFloat(r) * (dotSize + spacing * 1.2) - geo.size.height/2 + dotSize)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}
