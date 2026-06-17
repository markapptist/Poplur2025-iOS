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
    
    @State private var pulseAnimation: Bool = false
    @State private var arrowAnimation: Bool = false
    
    // Animation state for toggling between TRENDING/arrow and LIKES/number
    @State private var showLikesMode: Bool = false
    
    private var shouldShowRecording: Bool {
        isRecording && selectedTab == .record
    }
    
    private var shouldShowPostCount: Bool {
        !isRecording && [AppTab.map, .feed, .profile].contains(selectedTab)
    }
    
    var body: some View {
        Group {
            if shouldShowRecording {
                // Recording countdown mode - video timer (10s → 0s)
                recordingCountdownBadge
                    .allowsHitTesting(false)
            } else if shouldShowPostCount {
                // Post count mode - align baseline with radius display
                postCountBadge
                    .allowsHitTesting(false)
            }
        }
        .opacity((shouldShowRecording || shouldShowPostCount) ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.3), value: shouldShowRecording)
        .animation(.easeInOut(duration: 0.3), value: shouldShowPostCount)
        .onAppear {
            pulseAnimation = true
            arrowAnimation = true
            // Start animation timer for likes/trending toggle
            startLikesAnimation()
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("RECORDING")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
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

            VStack(alignment: .center, spacing: 2) {
                Text(secondsRemaining > 0 ? "\(secondsRemaining)" : "0")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.red)
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .poplurMetalNumberShader(intensity: 1.18)
                    .shadow(color: .red.opacity(0.3), radius: 6, x: 0, y: 2)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .contentTransition(.numericText(value: Double(max(secondsRemaining, 0))))

                Rectangle()
                    .fill(.white)
                    .frame(width: 90, height: 2)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    .alignmentGuide(.counterSeparator) { dimensions in
                        dimensions[VerticalAlignment.center]
                    }

                Text("seconds")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .poplurMetalNumberShader(intensity: 0.60)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
            }
            .frame(width: 90, alignment: .center)

            Text("unit")
                .font(.system(size: 14, weight: .medium))
                .hidden()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Post Count Badge
    
    @ViewBuilder
    private var postCountBadge: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(showLikesMode ? "LIKES" : "TRENDING")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                .kerning(1.2)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            
            VStack(alignment: .center, spacing: 2) {
                Group {
                    if showLikesMode {
                        Text("\(likesCount)")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.red)
                            .monospacedDigit()
                            .minimumScaleFactor(0.4)
                            .lineLimit(1)
                            .poplurMetalNumberShader(intensity: 1.12)
                            .shadow(color: .red.opacity(0.3), radius: 6, x: 0, y: 2)
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    } else if radiusTrend != .neutral {
                        Image(systemName: radiusTrend == .up ? "arrow.up" : "arrow.down")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(radiusTrend == .up ? Color.green : Color.red)
                            .scaleEffect(arrowAnimation ? 1.0 : 0.85)
                            .opacity(arrowAnimation ? 1.0 : 0.7)
                            .animation(
                                .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true),
                                value: arrowAnimation
                            )
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                            .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    } else {
                        Text("")
                            .font(.system(size: 40, weight: .bold))
                    }
                }

                Rectangle()
                    .fill(.white)
                    .frame(width: 90, height: 2)
                    .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                    .alignmentGuide(.counterSeparator) { dimensions in
                        dimensions[VerticalAlignment.center]
                    }

                Text("\(postCount)")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .poplurMetalNumberShader(intensity: 0.78)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
            }
            .frame(width: 90, alignment: .center)
            
            Text(postCount == 1 ? "post" : "posts")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .poplurMetalNumberShader(intensity: 0.45)
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: showLikesMode)
    }

    // MARK: - Likes Animation
    
    private func startLikesAnimation() {
        // Toggle without withAnimation wrapper — the postCountBadge VStack owns the spring
        // so it never leaks into secondsRemaining updates and causes countdown jitter.
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
            showLikesMode.toggle()
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
                    radiusTrend: .constant(.neutral)
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
                    radiusTrend: .constant(.neutral)
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
                    radiusTrend: .constant(.neutral)
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
                    radiusTrend: .constant(.up)
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
                    radiusTrend: .constant(.down)
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
                    radiusTrend: .constant(.neutral)
                )
            }
            .previewDisplayName("Post Count - Neutral")
        }
    }
}
#endif
