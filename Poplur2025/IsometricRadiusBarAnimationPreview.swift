import SwiftUI

final class PreviewIsometricBarSettings: ObservableObject {
    @Published var horizontalOffset: CGFloat = 80
    @Published var bottomOffset: CGFloat = 1
    @Published var barWidth: CGFloat = 98
    @Published var barHeight: CGFloat = 390
    @Published var barTiltDegrees: Double = -8
}

struct IsometricRadiusBarAnimationHarness: View {
    private var isPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"].map { $0 == "1" } ?? false
    }

    @State private var targetRadius: Double = 0
    @State private var animatedRadius: Double = 0
    @State private var animationTask: Task<Void, Never>? = nil
    @State private var autoPlayTask: Task<Void, Never>? = nil
    @State private var isAutoPlaying: Bool = false
    
    // Config
    private let earthMeters: Double = (Locale.current.measurementSystem == .metric ? 6_371_000.0 : 3_958.8 * 1609.34)
    private let maxRuntime: Double = 3_323_000.0
    private let riseDuration: Double = 2.0
    private let fallDuration: Double = 1.6
    
    @EnvironmentObject private var settings: PreviewIsometricBarSettings
    
    var body: some View {
        VStack(spacing: 16) {
            Text("IsometricRadiusBar Animation Harness").font(.headline)
            IsometricRadiusBar(
                radius: $animatedRadius,
                baseColor: Color(white: 0.2),
                tintColor: .indigo,
                growthSpeed: 1.5,
                maxSceneHeight: 1.8,
                uiScale: 1.5,
                maxRuntimeRadius: maxRuntime
            )
            .frame(width: settings.barWidth, height: settings.barHeight)
            .rotation3DEffect(.degrees(settings.barTiltDegrees), axis: (x: 1, y: 0, z: 0), perspective: 0.65)
            
            VStack(spacing: 12) {
                // Auto-play toggle
                HStack {
                    Toggle(isAutoPlaying ? "⏸ Auto-Play Running" : "▶️ Start Auto-Play", isOn: $isAutoPlaying)
                        .toggleStyle(.button)
                        .buttonStyle(.borderedProminent)
                        .tint(isAutoPlaying ? .orange : .green)
                }
                
                Text("Radius: \(Int(animatedRadius)) m  (\(Int((animatedRadius / maxRuntime) * 100))%)").monospacedDigit()
                let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(stride(from: 10, through: 100, by: 10)), id: \.self) { pct in
                        Button("\(pct)%") {
                            stopAutoPlay()
                            let target = (Double(pct) / 100.0) * maxRuntime
                            animateTo(target)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isAutoPlaying)
                    }
                }
                Button("Reset") {
                    stopAutoPlay()
                    animateTo(0)
                }
                .buttonStyle(.bordered)
                .disabled(isAutoPlaying)
            }
        }
        .padding()
        .onAppear {
            animatedRadius = targetRadius
        }
        .onChange(of: isAutoPlaying) { _, newValue in
            if newValue {
                startAutoPlay()
            } else {
                stopAutoPlay()
            }
        }
    }
    
    private func animateTo(_ target: Double) {
        // Cancel any existing animation
        animationTask?.cancel()
        
        let startValue = animatedRadius
        let endValue = target
        let duration: Double = 0.8
        
        // Manual frame-by-frame animation for smooth SceneKit updates
        let fps: Double = 60.0
        let frameDuration: Double = 1.0 / fps
        let startTime = CACurrentMediaTime()
        
        targetRadius = target
        
        animationTask = Task { @MainActor in
            while !Task.isCancelled {
                let elapsed = CACurrentMediaTime() - startTime
                let t = min(1.0, elapsed / duration)
                
                // Ease in-out interpolation
                let eased = easeInOutCubic(t)
                let interpolated = startValue + (endValue - startValue) * eased
                
                animatedRadius = interpolated
                
                if t >= 1.0 {
                    animatedRadius = endValue
                    break
                }
                
                try? await Task.sleep(nanoseconds: UInt64(frameDuration * 1_000_000_000))
            }
        }
    }
    
    private func startAutoPlay() {
        stopAutoPlay()
        
        autoPlayTask = Task { @MainActor in
            // Simulate scrolling through a feed with varying radius posts
            let feedRadiusRanges: [(min: Double, max: Double)] = [
                (0.05 * maxRuntime, 0.15 * maxRuntime),  // Small local posts (5-15%)
                (0.15 * maxRuntime, 0.35 * maxRuntime),  // Medium posts (15-35%)
                (0.35 * maxRuntime, 0.60 * maxRuntime),  // Large posts (35-60%)
                (0.60 * maxRuntime, 0.90 * maxRuntime),  // Very large posts (60-90%)
            ]
            
            while !Task.isCancelled && isAutoPlaying {
                // Pick a random range and random value within it
                let range = feedRadiusRanges.randomElement()!
                let randomRadius = Double.random(in: range.min...range.max)
                
                // Animate to the new random radius
                animateTo(randomRadius)
                
                // Wait for animation to complete + a bit of pause to "view" the post
                let viewDuration = Double.random(in: 1.2...2.5)
                try? await Task.sleep(nanoseconds: UInt64(viewDuration * 1_000_000_000))
            }
        }
    }
    
    private func stopAutoPlay() {
        autoPlayTask?.cancel()
        autoPlayTask = nil
    }
    
    private func easeInOutCubic(_ t: Double) -> Double {
        if t < 0.5 {
            return 4 * t * t * t
        } else {
            let f = (2 * t) - 2
            return 0.5 * f * f * f + 1
        }
    }
}

#if DEBUG
private var previewSettings: PreviewIsometricBarSettings {
    let s = PreviewIsometricBarSettings()
    s.horizontalOffset = 80
    s.bottomOffset = 1
    s.barWidth = 98
    s.barHeight = 390
    s.barTiltDegrees = -8
    return s
}
#endif

#Preview("Isometric Bar Animation Loop") {
    // Create a local settings instance so previews always compile
    let settings = {
        let s = PreviewIsometricBarSettings()
        s.horizontalOffset = 80
        s.bottomOffset = 1
        s.barWidth = 98
        s.barHeight = 390
        s.barTiltDegrees = -8
        return s
    }()

    return Group {
        IsometricRadiusBarAnimationHarness()
            .environmentObject(settings)
            .preferredColorScheme(.dark)
    }
}
