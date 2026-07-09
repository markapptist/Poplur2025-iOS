import SwiftUI

struct ThemedSkinPlate: View {
    let skin: CubeSkin
    var tab: AppTab = .feed
    var cornerRadius: CGFloat = 18
    var isPressed: Bool = false
    var borderWidth: CGFloat = 2
    var glowRadius: CGFloat = 12

    private var theme: CubeSkinAppTheme { skin.appTheme }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            Image(uiImage: skin.makeTexture(tab: tab))
                .resizable()
                .scaledToFill()
                .saturation(skin == .toy ? 0.9 : 1.15)
                .contrast(skin == .ice ? 1.26 : 1.08)

            LinearGradient(
                colors: overlayColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if skin == .sparklePink || skin == .rainbow {
                SkinSparkleField(color: theme.accent2)
                    .blendMode(.screen)
            }

            if skin == .standard || skin == .rubber {
                RubberDotField(color: Color.white.opacity(0.12))
            }

            if skin == .toy {
                ToyCornerAccents()
            }
        }
        .clipShape(shape)
        .overlay {
            shape
                .stroke(
                    LinearGradient(
                        colors: borderColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: borderWidth
                )
        }
        .overlay {
            shape
                .stroke(Color.white.opacity(skin == .ice ? 0.36 : 0.16), lineWidth: 1)
                .padding(5)
        }
        .overlay(alignment: .topLeading) {
            if skin == .camo || skin == .chocolate || skin == .gold {
                PlateBolts(color: theme.primaryText.opacity(skin == .camo ? 0.55 : 0.42))
                    .padding(7)
            }
        }
        .shadow(color: theme.shadow, radius: glowRadius, x: 0, y: 5)
        .shadow(color: skin == .ice ? Color.white.opacity(0.30) : theme.accent.opacity(0.22), radius: skin == .ice ? 8 : 5)
        .scaleEffect(isPressed ? 0.93 : 1)
    }

    private var overlayColors: [Color] {
        switch skin {
        case .ice:
            return [
                Color.white.opacity(0.34),
                theme.accent.opacity(0.12),
                theme.backgroundDeep.opacity(0.18)
            ]
        case .sparklePink, .clay:
            return [
                Color.white.opacity(0.18),
                theme.accent.opacity(0.16),
                Color.black.opacity(0.38)
            ]
        case .rainbow:
            return [
                Color.red.opacity(0.18),
                Color.green.opacity(0.10),
                Color.blue.opacity(0.18),
                Color.pink.opacity(0.20)
            ]
        case .toy:
            return [
                Color.white.opacity(0.38),
                Color.white.opacity(0.08),
                Color.black.opacity(0.08)
            ]
        case .camo:
            return [
                Color.black.opacity(0.28),
                theme.accent.opacity(0.08),
                Color.black.opacity(0.36)
            ]
        case .chocolate:
            return [
                Color.white.opacity(0.18),
                Color.clear,
                Color.black.opacity(0.36)
            ]
        case .gold:
            return [
                Color.white.opacity(0.24),
                theme.accent.opacity(0.16),
                Color.black.opacity(0.30)
            ]
        case .standard, .rubber:
            return [
                Color.white.opacity(0.10),
                Color.black.opacity(0.20),
                Color.black.opacity(0.45)
            ]
        }
    }

    private var borderColors: [Color] {
        switch skin {
        case .ice:
            return [Color.white.opacity(0.92), theme.accent, Color.white.opacity(0.72)]
        case .sparklePink, .clay:
            return [Color.white.opacity(0.72), theme.accent, theme.accent2]
        case .rainbow:
            return [.yellow, .green, .cyan, .pink]
        case .toy:
            return [Color.red.opacity(0.86), Color.yellow.opacity(0.88), Color.blue.opacity(0.86)]
        default:
            return [theme.border, theme.accent.opacity(0.86), theme.accent2.opacity(0.58)]
        }
    }
}

private struct PlateBolts: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)
            let bolt = max(4, size * 0.085)
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.28), color, Color.black.opacity(0.36)],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: bolt
                        )
                    )
                    .frame(width: bolt, height: bolt)
                    .position(position(for: index, in: proxy.size, inset: bolt))
            }
        }
        .allowsHitTesting(false)
    }

    private func position(for index: Int, in size: CGSize, inset: CGFloat) -> CGPoint {
        switch index {
        case 0: return CGPoint(x: inset, y: inset)
        case 1: return CGPoint(x: size.width - inset, y: inset)
        case 2: return CGPoint(x: inset, y: size.height - inset)
        default: return CGPoint(x: size.width - inset, y: size.height - inset)
        }
    }
}

private struct SkinSparkleField: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            for index in 0..<24 {
                let x = CGFloat((index * 37) % 100) / 100 * size.width
                let y = CGFloat((index * 61) % 100) / 100 * size.height
                let radius = CGFloat(1 + (index % 3))
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(color.opacity(index % 4 == 0 ? 0.72 : 0.34)))
                if index % 5 == 0 {
                    var path = Path()
                    path.move(to: CGPoint(x: x - radius * 2.5, y: y))
                    path.addLine(to: CGPoint(x: x + radius * 2.5, y: y))
                    path.move(to: CGPoint(x: x, y: y - radius * 2.5))
                    path.addLine(to: CGPoint(x: x, y: y + radius * 2.5))
                    context.stroke(path, with: .color(.white.opacity(0.62)), lineWidth: 0.8)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct RubberDotField: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 15
            var y: CGFloat = 9
            var row = 0
            while y < size.height {
                var x: CGFloat = row.isMultiple(of: 2) ? 8 : 15
                while x < size.width {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 4, height: 4)),
                        with: .color(color)
                    )
                    x += step
                }
                row += 1
                y += step
            }
        }
        .allowsHitTesting(false)
    }
}

private struct ToyCornerAccents: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                corner(color: .red, rotation: 0)
                    .position(x: 12, y: 12)
                corner(color: .blue, rotation: 90)
                    .position(x: w - 12, y: 12)
                corner(color: .blue, rotation: -90)
                    .position(x: 12, y: h - 12)
                corner(color: .yellow, rotation: 180)
                    .position(x: w - 12, y: h - 12)
            }
        }
        .allowsHitTesting(false)
    }

    private func corner(color: Color, rotation: Double) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .trim(from: 0, to: 0.55)
            .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            .frame(width: 24, height: 24)
            .rotationEffect(.degrees(rotation))
    }
}
