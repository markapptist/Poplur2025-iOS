import SwiftUI

// MARK: – Duration constant shared with FeedView
let kCommercialTransitionDuration: TimeInterval = 1.0

// MARK: – Public entry point

struct PoplurTransitionFlash: View {
    let channelNumber: Int
    let channelCategory: String

    init(channelNumber: Int, channelCategory: String = "Poplur TV") {
        self.channelNumber = channelNumber
        self.channelCategory = channelCategory
    }

    var body: some View {
        PoplurStripeTransition()
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

// MARK: – Stripe transition

private let kStripeColors: [Color] = [
    Color(red: 0.84, green: 0.02, blue: 0.47),   // deep magenta
    Color(red: 0.54, green: 0.10, blue: 0.76),   // purple
    .white,
    Color(red: 1.00, green: 0.18, blue: 0.60),   // hot pink
    Color(red: 0.58, green: 0.08, blue: 0.82),   // violet
    Color(red: 0.97, green: 0.78, blue: 0.89),   // light pink
    Color(red: 0.94, green: 0.10, blue: 0.52),   // deep pink
    .white,
]

private struct ConfettiDot: Identifiable {
    let id = UUID()
    let x, y: CGFloat
    let w, h: CGFloat
    let angle: Double
    let color: Color
}

private func makeConfetti(count: Int = 28) -> [ConfettiDot] {
    let palette: [Color] = [
        Color(red: 1, green: 0.84, blue: 0),
        Color(red: 1, green: 0.20, blue: 0.60),
        .white,
        Color(red: 0.94, green: 0.10, blue: 0.52),
        Color(red: 0.82, green: 0.62, blue: 1.00),
        Color(red: 1, green: 0.78, blue: 0.12),
    ]
    return (0..<count).map { _ in
        ConfettiDot(
            x: CGFloat.random(in: 0.05...0.95),
            y: CGFloat.random(in: 0.10...0.90),
            w: CGFloat.random(in: 5...11),
            h: CGFloat.random(in: 3...7),
            angle: Double.random(in: 0...360),
            color: palette.randomElement()!
        )
    }
}

private struct PoplurStripeTransition: View {
    private let stripeCount = 8

    @State private var offsets: [CGFloat] = []
    @State private var logoAlpha: Double = 0
    @State private var logoScale: CGFloat = 0.45
    @State private var confetti: [ConfettiDot] = []

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width
            let H = geo.size.height
            let sw = W / CGFloat(stripeCount)

            ZStack {
                Canvas { ctx, size in
                    guard offsets.count == stripeCount else { return }
                    for i in 0..<stripeCount {
                        let le = offsets[i]
                        var path = Path()
                        path.move(to: CGPoint(x: le, y: 0))
                        path.addLine(to: CGPoint(x: le + sw, y: 0))
                        path.addLine(to: CGPoint(x: le + sw + H, y: H))
                        path.addLine(to: CGPoint(x: le + H, y: H))
                        path.closeSubpath()
                        ctx.fill(path, with: .color(kStripeColors[i]))
                        ctx.fill(path, with: .linearGradient(
                            Gradient(stops: [
                                .init(color: .white.opacity(0.44), location: 0),
                                .init(color: .white.opacity(0.00), location: 0.55),
                            ]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: 0, y: H)
                        ))
                    }
                    for dot in confetti {
                        let cx = dot.x * size.width
                        let cy = dot.y * size.height
                        let rect = CGRect(x: cx - dot.w / 2, y: cy - dot.h / 2,
                                         width: dot.w, height: dot.h)
                        ctx.fill(Path(ellipseIn: rect), with: .color(dot.color))
                    }
                }

                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.22), radius: 12, x: 0, y: 6)
                        Image("logo")
                            .resizable()
                            .scaledToFit()
                            .padding(12)
                    }
                    .frame(width: 90, height: 90)
                    Text("poplur")
                        .font(.system(size: 22, weight: .black))
                        .foregroundColor(Color(red: 0.18, green: 0.06, blue: 0.24))
                }
                .scaleEffect(logoScale)
                .opacity(logoAlpha)
            }
            .onAppear {
                offsets = Array(repeating: W, count: stripeCount)
                run(W: W, H: H, sw: sw)
            }
        }
    }

    private func run(W: CGFloat, H: CGFloat, sw: CGFloat) {
        Task { @MainActor in
            // Entry: rightmost stripe first, 28 ms stagger
            for i in stride(from: stripeCount - 1, through: 0, by: -1) {
                withAnimation(.interpolatingSpring(stiffness: 500, damping: 28)) {
                    offsets[i] = CGFloat(i) * sw
                }
                try? await Task.sleep(nanoseconds: 28_000_000)
            }
            try? await Task.sleep(nanoseconds: 160_000_000)  // spring settle

            // Logo + confetti
            confetti = makeConfetti()
            withAnimation(.spring(response: 0.22, dampingFraction: 0.52)) { logoScale = 1.0 }
            withAnimation(.easeIn(duration: 0.14)) { logoAlpha = 1.0 }

            // Hold
            try? await Task.sleep(nanoseconds: 220_000_000)

            // Logo out
            withAnimation(.easeOut(duration: 0.12)) { logoAlpha = 0.0 }

            // Exit: leftmost stripe first, 26 ms stagger
            let exitX: CGFloat = -(H + sw)
            for i in 0..<stripeCount {
                withAnimation(.interpolatingSpring(stiffness: 500, damping: 28)) {
                    offsets[i] = exitX
                }
                try? await Task.sleep(nanoseconds: 26_000_000)
            }
            try? await Task.sleep(nanoseconds: 140_000_000)  // spring settle
            confetti = []
        }
    }
}
