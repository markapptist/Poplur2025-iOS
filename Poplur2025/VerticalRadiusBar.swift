import SwiftUI

struct VerticalRadiusBar: View {
    let radius: Int
    let maxRadius: Int
    let width: CGFloat
    let maxHeight: CGFloat
    let color: Color
    let showsLabel: Bool
    let labelFormat: (Int) -> String

    init(
        radius: Int,
        maxRadius: Int = 10_000,
        width: CGFloat = 8,
        maxHeight: CGFloat = 100,
        color: Color = .blue,
        showsLabel: Bool = false,
        labelFormat: @escaping (Int) -> String = { r in
            if r >= 1000 {
                return "\(r / 1000) km"
            } else {
                return "\(r) m"
            }
        }
    ) {
        self.radius = max(0, radius)
        self.maxRadius = max(1, maxRadius)
        self.width = width
        self.maxHeight = maxHeight
        self.color = color
        self.showsLabel = showsLabel
        self.labelFormat = labelFormat
    }

    var body: some View {
        let clamped = min(radius, maxRadius)
        let height = CGFloat(clamped) / CGFloat(maxRadius) * maxHeight

        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: width / 2)
                .fill(color)
                .frame(width: width, height: max(height, 2)) // ensure visible even for tiny values
                .overlay(
                    RoundedRectangle(cornerRadius: width / 2)
                        .stroke(color.opacity(0.2), lineWidth: 1)
                )

            if showsLabel {
                Text(labelFormat(radius))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .accessibilityLabel("Radius")
        .accessibilityValue(labelFormat(radius))
    }
}

#Preview {
    VStack(spacing: 16) {
        VerticalRadiusBar(radius: 500, maxRadius: 10_000, showsLabel: true)
        VerticalRadiusBar(radius: 5_000, maxRadius: 10_000, color: .green, showsLabel: true)
        VerticalRadiusBar(radius: 10_000, maxRadius: 10_000, color: .red, showsLabel: true)
    }
    .padding()
}
