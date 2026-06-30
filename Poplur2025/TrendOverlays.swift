import SwiftUI
import CoreGraphics

internal enum TrendCategory: Int, CaseIterable {
    case pop, dance, rap, rnb, rock, crush, jazz, chill, oldies, classics

    internal var symbolName: String {
        switch self {
        case .pop: return "music.mic"
        case .dance: return "figure.dance"
        case .rap: return "music.note"
        case .rnb: return "music.quarternote.3"
        case .rock: return "guitars"
        case .crush: return "heart.fill"
        case .jazz: return "saxophone"
        case .chill: return "snowflake"
        case .oldies: return "radio"
        case .classics: return "pianokeys"
        }
    }

    internal var tint: Color {
        switch self {
        case .pop: return Color(red: 0.95, green: 0.40, blue: 0.55)
        case .dance: return Color(red: 0.95, green: 0.60, blue: 0.35)
        case .rap: return Color(red: 0.25, green: 0.20, blue: 0.85)
        case .rnb: return Color(red: 0.90, green: 0.30, blue: 0.70)
        case .rock: return Color(red: 0.15, green: 0.55, blue: 0.40)
        case .crush: return Color(red: 0.95, green: 0.40, blue: 0.40)
        case .jazz: return Color(red: 0.70, green: 0.70, blue: 0.30)
        case .chill: return Color(red: 0.30, green: 0.70, blue: 0.70)
        case .oldies: return Color(red: 0.60, green: 0.50, blue: 0.30)
        case .classics: return Color(red: 0.20, green: 0.20, blue: 0.60)
        }
    }

    internal var lightTint: Color {
        tint.opacity(0.7)
    }

    internal var darkTint: Color {
        tint.opacity(0.9)
    }
}

internal struct TrendPopObject {
    internal var category: TrendCategory
    internal var strength: CGFloat
    internal var popCount: Int
}

internal struct MusicWaveMarker: View {
    internal var amplitude: CGFloat
    internal var frequency: CGFloat
    internal var phase: CGFloat
    internal var color: Color
    internal var lineWidth: CGFloat

    internal var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let midHeight = height / 2

            Path { path in
                path.move(to: CGPoint(x: 0, y: midHeight))

                for x in stride(from: 0, through: width, by: 1) {
                    let relativeX = x / width
                    let sine = sin(relativeX * frequency * 2 * .pi + phase)
                    let y = midHeight + amplitude * sine * midHeight
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            .stroke(color, lineWidth: lineWidth)
        }
    }
}

internal struct ArcShape: Shape {
    internal var startAngle: Angle
    internal var endAngle: Angle
    internal var clockwise: Bool = false

    internal func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)

        var path = Path()
        path.addArc(center: center,
                    radius: radius,
                    startAngle: startAngle,
                    endAngle: endAngle,
                    clockwise: clockwise)
        return path
    }
}

internal struct TrendPopMarker: View {
    internal var popObject: TrendPopObject
    internal var size: CGFloat

    internal var body: some View {
        ZStack {
            drawTrendShape(category: popObject.category, strength: popObject.strength)
                .frame(width: size, height: size)

            Text("\(popObject.popCount)")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(.white)
                .shadow(radius: 1)
        }
    }
}

internal struct TrendObjectConfetti: View {
    internal var category: TrendCategory
    internal var confettiCount: Int
    internal var size: CGFloat

    internal var body: some View {
        ZStack {
            ForEach(0..<confettiCount, id: \.self) { i in
                Circle()
                    .fill(category.tint.opacity(0.7))
                    .frame(width: size * 0.1, height: size * 0.1)
                    .position(x: CGFloat.random(in: 0...size), y: CGFloat.random(in: 0...size))
                    .opacity(Double.random(in: 0.3...1.0))
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }
}

internal struct TrendObjectGlyph: View {
    internal var category: TrendCategory
    internal var size: CGFloat

    internal var body: some View {
        Image(systemName: category.symbolName)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundColor(category.tint)
            .poplurIconShader()
            .shadow(color: category.darkTint.opacity(0.6), radius: 2, x: 1, y: 1)
    }
}

// MARK: - Helper Drawing Functions

internal func trendPath(in rect: CGRect, strength: CGFloat) -> Path {
    var path = Path()
    let width = rect.width
    let height = rect.height
    let center = CGPoint(x: rect.midX, y: rect.midY)

    let radius = min(width, height) / 2 * strength
    path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))

    return path
}

internal func drawTrendShape(category: TrendCategory, strength: CGFloat) -> some View {
    GeometryReader { geo in
        let rect = geo.frame(in: .local)
        trendPath(in: rect, strength: strength)
            .fill(category.lightTint)
    }
}

internal func drawTrendStroke(category: TrendCategory, strength: CGFloat, lineWidth: CGFloat = 2) -> some View {
    GeometryReader { geo in
        let rect = geo.frame(in: .local)
        trendPath(in: rect, strength: strength)
            .stroke(category.darkTint, lineWidth: lineWidth)
    }
}
