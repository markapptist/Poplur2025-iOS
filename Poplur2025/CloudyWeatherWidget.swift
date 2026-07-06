import SwiftUI

/// Test widget for the cloudy weather state.
/// Shows the cloud icon and animates the temperature label between °F and °C
/// on a 3-second loop.
struct CloudyWeatherWidget: View {

    // Seed temperature — update to test different values
    var fahrenheit: Int = 76

    private var celsius: Int { Int((Double(fahrenheit) - 32) * 5 / 9) }

    @State private var showCelsius = false
    @State private var cloudScale: CGFloat = 1.0
    @State private var cloudOpacity: Double = 1.0
    @State private var glowPulse: Bool = false

    var body: some View {
        ZStack {
            // Frosted-glass card background
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .cyan.opacity(0.30), radius: glowPulse ? 18 : 10, x: 0, y: 0)
                .shadow(color: .black.opacity(0.35), radius: 8, x: 0, y: 4)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: glowPulse)

            VStack(spacing: 6) {
                // Animated cloud icon
                Image(systemName: "cloud.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white, Color.cyan.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .scaleEffect(cloudScale)
                    .opacity(cloudOpacity)
                    .shadow(color: .cyan.opacity(0.60), radius: 8, x: 0, y: 0)
                    .animation(
                        .easeInOut(duration: 2.2).repeatForever(autoreverses: true),
                        value: cloudScale
                    )

                Text("Cloudy")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))

                // Temperature — flips between °F and °C
                ZStack {
                    Text("\(fahrenheit)°F")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .opacity(showCelsius ? 0 : 1)
                        .scaleEffect(showCelsius ? 0.75 : 1)
                        .offset(y: showCelsius ? -10 : 0)

                    Text("\(celsius)°C")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(.cyan)
                        .opacity(showCelsius ? 1 : 0)
                        .scaleEffect(showCelsius ? 1 : 0.75)
                        .offset(y: showCelsius ? 0 : 10)
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.72), value: showCelsius)
                .frame(height: 36)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .fixedSize()
        .onAppear {
            cloudScale = 1.06
            glowPulse = true
            scheduleUnitToggle()
        }
    }

    private func scheduleUnitToggle() {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    withAnimation { showCelsius.toggle() }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        CloudyWeatherWidget(fahrenheit: 76)
    }
}
