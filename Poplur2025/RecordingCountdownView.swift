//
//  RecordingCountdownView.swift
//  Poplur2025
//
//  Multi-purpose counter view for recording countdown and post count display
//

import SwiftUI

/// Multi-purpose counter shown in bottom-left corner (level with radius bar)
/// - On Record tab (recording): Shows video recording countdown timer (10s → 0s)
/// - On other tabs: Shows user's current post count with radius trend indicator
/// This view is visible across ALL tabs
struct RecordingCountdownView: View {
    @Binding var isRecording: Bool
    @Binding var secondsRemaining: Int
    @Binding var postCount: Int
    @Binding var likesCount: Int
    @Binding var selectedTab: AppTab
    @Binding var radiusTrend: HomeView.RadiusTrend
    @Binding var radiusMeters: Double
    /// When set on camera tab, shows detected user's post count instead of countdown
    var detectedUserPostCount: Int? = nil

    @State private var pulseAnimation: Bool = false
    @State private var arrowAnimation: Bool = false

    private var shouldShowRecording: Bool {
        isRecording && selectedTab == .record
    }

    private var shouldShowPostCount: Bool {
        !isRecording && [AppTab.map, .feed, .profile].contains(selectedTab)
    }

    private var shouldShowDetectedUser: Bool {
        selectedTab == .record && !isRecording && detectedUserPostCount != nil
    }

    private var formattedRadius: String {
        if radiusMeters >= 1000 {
            return String(format: "%.1f km", radiusMeters / 1000)
        } else {
            return "\(Int(radiusMeters)) m"
        }
    }

    private var postCountAccentColor: Color {
        switch radiusTrend {
        case .up: return .green
        case .down: return .red
        case .neutral: return .white.opacity(0.9)
        }
    }
    
    var body: some View {
        Group {
            if shouldShowRecording {
                recordingCountdownBadge
                    .allowsHitTesting(false)
            } else if shouldShowDetectedUser, let count = detectedUserPostCount {
                detectedUserBadge(postCount: count)
                    .allowsHitTesting(false)
            } else if shouldShowPostCount {
                postCountBadge
                    .allowsHitTesting(false)
            }
        }
        .opacity((shouldShowRecording || shouldShowPostCount || shouldShowDetectedUser) ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.3), value: shouldShowRecording)
        .animation(.easeInOut(duration: 0.3), value: shouldShowPostCount)
        .onAppear {
            pulseAnimation = true
            arrowAnimation = true
        }
        .onChange(of: radiusTrend) { _, newTrend in
            // Restart animation when trend changes
            print("🎯 [RecordingCountdownView] Radius trend changed to: \(newTrend)")
            arrowAnimation = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                arrowAnimation = true
            }
        }
    }
    
    // MARK: - Recording Countdown Badge
    
    @ViewBuilder
    private var recordingCountdownBadge: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("RECORDING")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .poplurTextShader(intensity: 0.72)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .kerning(1.2)

                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .scaleEffect(pulseAnimation ? 1.2 : 1.0)
                    .opacity(pulseAnimation ? 0.6 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true),
                        value: pulseAnimation
                    )
            }
            .frame(height: CounterSeparatorMetrics.labelHeight, alignment: .center)

            Color.clear
                .frame(height: CounterSeparatorMetrics.labelToNumeratorSpacing)

            VStack(alignment: .center, spacing: 0) {
                Text(secondsRemaining > 0 ? "\(secondsRemaining)" : "0")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.red)
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .poplurMetalNumberShader(intensity: 1.05)
                    .shadow(color: .red.opacity(0.3), radius: 6, x: 0, y: 2)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .contentTransition(.numericText(value: Double(max(secondsRemaining, 0))))
                    .frame(width: CounterSeparatorMetrics.separatorWidth, height: CounterSeparatorMetrics.numeratorHeight, alignment: .bottom)

                Color.clear
                    .frame(height: CounterSeparatorMetrics.numeratorToSeparatorSpacing)

                Rectangle()
                    .fill(.red)
                    .frame(width: CounterSeparatorMetrics.separatorWidth, height: CounterSeparatorMetrics.separatorHeight)
                    .shadow(color: .red.opacity(0.5), radius: 2, x: 0, y: 0)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    .alignmentGuide(.counterSeparator) { dimensions in
                        dimensions[VerticalAlignment.center]
                    }

                Color.clear
                    .frame(height: CounterSeparatorMetrics.separatorToDenominatorSpacing)

                Text("seconds")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .poplurMetalNumberShader(intensity: 0.72)
                    .frame(width: CounterSeparatorMetrics.separatorWidth, height: CounterSeparatorMetrics.denominatorHeight, alignment: .top)
            }
            .frame(width: CounterSeparatorMetrics.separatorWidth, alignment: .center)

            Text(formattedRadius)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .poplurTextShader(intensity: 0.65)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                .frame(height: CounterSeparatorMetrics.footerHeight, alignment: .top)
        }
        .padding(.horizontal, CounterSeparatorMetrics.horizontalPadding)
        .padding(.vertical, CounterSeparatorMetrics.verticalPadding)
        .frame(height: CounterSeparatorMetrics.counterHeight, alignment: .top)
        .alignmentGuide(.counterSeparator) { _ in
            CounterSeparatorMetrics.separatorCenterFromTop
        }
    }
    
    // MARK: - Detected User Badge (camera tab, face recognized)

    @ViewBuilder
    private func detectedUserBadge(postCount count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DETECTED")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.green.opacity(0.8))
                .poplurTextShader(intensity: 0.8)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                .kerning(1.2)
                .frame(height: CounterSeparatorMetrics.labelHeight, alignment: .center)

            Color.clear
                .frame(height: CounterSeparatorMetrics.labelToNumeratorSpacing)

            VStack(alignment: .center, spacing: 0) {
                Image(systemName: "person.fill.checkmark")
                    .poplurIconShader()
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color.green)
                    .scaleEffect(pulseAnimation ? 1.05 : 0.95)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulseAnimation)
                    .shadow(color: Color.green.opacity(0.4), radius: 6, x: 0, y: 2)
                    .frame(width: CounterSeparatorMetrics.separatorWidth, height: CounterSeparatorMetrics.numeratorHeight, alignment: .bottom)

                Color.clear
                    .frame(height: CounterSeparatorMetrics.numeratorToSeparatorSpacing)

                Rectangle()
                    .fill(Color.green)
                    .frame(width: CounterSeparatorMetrics.separatorWidth, height: CounterSeparatorMetrics.separatorHeight)
                    .shadow(color: Color.green.opacity(0.5), radius: 2, x: 0, y: 0)
                    .alignmentGuide(.counterSeparator) { dimensions in
                        dimensions[VerticalAlignment.center]
                    }

                Color.clear
                    .frame(height: CounterSeparatorMetrics.separatorToDenominatorSpacing)

                Text("\(count)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .poplurMetalNumberShader(intensity: 0.72)
                    .frame(width: CounterSeparatorMetrics.separatorWidth, height: CounterSeparatorMetrics.denominatorHeight, alignment: .top)
            }
            .frame(width: CounterSeparatorMetrics.separatorWidth, alignment: .center)

            Text(count == 1 ? "post" : "posts")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .poplurTextShader(intensity: 0.65)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                .frame(height: CounterSeparatorMetrics.footerHeight, alignment: .top)
        }
        .padding(.horizontal, CounterSeparatorMetrics.horizontalPadding)
        .padding(.vertical, CounterSeparatorMetrics.verticalPadding)
        .frame(height: CounterSeparatorMetrics.counterHeight, alignment: .top)
        .alignmentGuide(.counterSeparator) { _ in
            CounterSeparatorMetrics.separatorCenterFromTop
        }
    }

    // MARK: - Post Count Badge

    @ViewBuilder
    private var postCountBadge: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TRENDING")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .poplurTextShader(intensity: 0.72)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                .kerning(1.2)
                .frame(height: CounterSeparatorMetrics.labelHeight, alignment: .center)

            Color.clear
                .frame(height: CounterSeparatorMetrics.labelToNumeratorSpacing)
            
            VStack(alignment: .center, spacing: 0) {
                Group {
                    if radiusTrend != .neutral {
                        Image(systemName: radiusTrend == .up ? "arrow.up" : "arrow.down")
                            .poplurIconShader()
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(radiusTrend == .up ? Color.green : Color.red)
                            .scaleEffect(arrowAnimation ? 1.0 : 0.85)
                            .opacity(arrowAnimation ? 1.0 : 0.7)
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true),
                                value: arrowAnimation
                            )
                            .poplurMetalNumberShader(intensity: 1.05)
                            .shadow(color: (radiusTrend == .up ? Color.green : Color.red).opacity(0.3), radius: 6, x: 0, y: 2)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    } else {
                        Text("")
                            .font(.system(size: 40, weight: .bold))
                            .poplurTextShader(intensity: 0.45)
                    }
                }
                .frame(width: CounterSeparatorMetrics.separatorWidth, height: CounterSeparatorMetrics.numeratorHeight, alignment: .bottom)

                Color.clear
                    .frame(height: CounterSeparatorMetrics.numeratorToSeparatorSpacing)

                Rectangle()
                    .fill(postCountAccentColor)
                    .frame(width: CounterSeparatorMetrics.separatorWidth, height: CounterSeparatorMetrics.separatorHeight)
                    .shadow(color: postCountAccentColor.opacity(0.5), radius: 2, x: 0, y: 0)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    .alignmentGuide(.counterSeparator) { dimensions in
                        dimensions[VerticalAlignment.center]
                    }

                Color.clear
                    .frame(height: CounterSeparatorMetrics.separatorToDenominatorSpacing)

                Text("\(postCount)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .poplurMetalNumberShader(intensity: 0.72)
                    .frame(width: CounterSeparatorMetrics.separatorWidth, height: CounterSeparatorMetrics.denominatorHeight, alignment: .top)
            }
            .frame(width: CounterSeparatorMetrics.separatorWidth, alignment: .center)
            
            Text("\(postCount == 1 ? "post" : "posts") · \(formattedRadius)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .poplurTextShader(intensity: 0.65)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                .frame(height: CounterSeparatorMetrics.footerHeight, alignment: .top)
        }
        .padding(.horizontal, CounterSeparatorMetrics.horizontalPadding)
        .padding(.vertical, CounterSeparatorMetrics.verticalPadding)
        .frame(height: CounterSeparatorMetrics.counterHeight, alignment: .top)
        .alignmentGuide(.counterSeparator) { _ in
            CounterSeparatorMetrics.separatorCenterFromTop
        }
    }
}

// MARK: - Preview
#if DEBUG
struct RecordingCountdownView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Recording countdown preview - starts at 10 seconds
            ZStack {
                Color.black.ignoresSafeArea()
                RecordingCountdownView(
                    isRecording: .constant(true),
                    secondsRemaining: .constant(10),
                    postCount: .constant(42),
                    likesCount: .constant(126),
                    selectedTab: .constant(.record),
                    radiusTrend: .constant(.neutral),
                    radiusMeters: .constant(2500)
                )
            }
            .previewDisplayName("Recording Start (10s)")
            
            // Recording mid-countdown
            ZStack {
                Color.black.ignoresSafeArea()
                RecordingCountdownView(
                    isRecording: .constant(true),
                    secondsRemaining: .constant(5),
                    postCount: .constant(42),
                    likesCount: .constant(126),
                    selectedTab: .constant(.record),
                    radiusTrend: .constant(.neutral),
                    radiusMeters: .constant(2500)
                )
            }
            .previewDisplayName("Recording Mid (5s)")

            // Recording complete preview
            ZStack {
                Color.black.ignoresSafeArea()
                RecordingCountdownView(
                    isRecording: .constant(true),
                    secondsRemaining: .constant(0),
                    postCount: .constant(42),
                    likesCount: .constant(126),
                    selectedTab: .constant(.record),
                    radiusTrend: .constant(.neutral),
                    radiusMeters: .constant(2500)
                )
            }
            .previewDisplayName("Recording Complete")

            // Post count preview with upward trend (Map tab)
            ZStack {
                Color.black.ignoresSafeArea()
                RecordingCountdownView(
                    isRecording: .constant(false),
                    secondsRemaining: .constant(10),
                    postCount: .constant(42),
                    likesCount: .constant(420),
                    selectedTab: .constant(.map),
                    radiusTrend: .constant(.up),
                    radiusMeters: .constant(2500)
                )
            }
            .previewDisplayName("Post Count - Radius Up ⬆️")

            // Post count preview with downward trend (Feed tab)
            ZStack {
                Color.black.ignoresSafeArea()
                RecordingCountdownView(
                    isRecording: .constant(false),
                    secondsRemaining: .constant(10),
                    postCount: .constant(128),
                    likesCount: .constant(904),
                    selectedTab: .constant(.feed),
                    radiusTrend: .constant(.down),
                    radiusMeters: .constant(800)
                )
            }
            .previewDisplayName("Post Count - Radius Down ⬇️")

            // Single post preview (neutral)
            ZStack {
                Color.black.ignoresSafeArea()
                RecordingCountdownView(
                    isRecording: .constant(false),
                    secondsRemaining: .constant(10),
                    postCount: .constant(1),
                    likesCount: .constant(12),
                    selectedTab: .constant(.profile),
                    radiusTrend: .constant(.neutral),
                    radiusMeters: .constant(1200)
                )
            }
            .previewDisplayName("Post Count - Neutral")
        }
    }
}
#endif
