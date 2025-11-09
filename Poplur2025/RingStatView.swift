import SwiftUI

struct RingStatView: View {
    let value: Double
    let maxValue: Double
    let unit: String
    let accentColor: Color
    let trackColor: Color
    let lineWidthFactor: Double // fraction of the shortest side

    private var clampedProgress: Double {
        guard maxValue > 0 else { return 0 }
        return max(0, min(1, value / maxValue))
    }

    private func formattedNumber(_ v: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 0
        return nf.string(from: NSNumber(value: v)) ?? String(Int(v))
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let lineWidth = max(2, side * lineWidthFactor)
            let inset = lineWidth / 2
            let startAngle: Angle = .degrees(-90)
            let endAngle: Angle = .degrees(-90 + 360 * clampedProgress)

            ZStack {
                // Track
                Circle()
                    .inset(by: inset)
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .foregroundStyle(trackColor)

                // Progress arc
                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .inset(by: inset)
                    .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .foregroundStyle(accentColor)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.4), value: clampedProgress)

                VStack(spacing: 4) {
                    Text(formattedNumber(value))
                        .font(.system(size: side * 0.22, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)

                    Text(unit.uppercased())
                        .font(.system(size: side * 0.10, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .padding(.horizontal, 6)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

struct RingStatView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.pink.ignoresSafeArea()
            RingStatView(
                value: 3500,
                maxValue: 10000,
                unit: "KM",
                accentColor: .black,
                trackColor: .white.opacity(0.25),
                lineWidthFactor: 0.12
            )
            .frame(width: 260, height: 260)
        }
        .preferredColorScheme(.dark)
    }
}
