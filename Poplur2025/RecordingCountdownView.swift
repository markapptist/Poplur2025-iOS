//
//  RecordingCountdownView.swift
//  Poplur2025
//
//  10-second countdown timer for camera recording
//

import SwiftUI

/// Countdown timer shown during video recording (bottom-left corner)
struct RecordingCountdownView: View {
    @Binding var isRecording: Bool
    @Binding var secondsRemaining: Int
    @State private var pulseAnimation: Bool = false
    
    var body: some View {
        if isRecording {
            VStack {
                Spacer()
                HStack {
                    // Countdown badge (bottom-left)
                    HStack(spacing: 8) {
                        // Recording indicator (pulsing red dot)
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
                        
                        // Countdown number
                        Text("\(secondsRemaining)")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .monospacedDigit()
                            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                        
                        Text("s")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.black.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                    )
                    
                    Spacer()
                }
                .padding(.leading, 20)
                .padding(.bottom, 120) // Position above home indicator
            }
            .transition(.opacity.combined(with: .move(edge: .leading)))
            .onAppear {
                pulseAnimation = true
            }
        }
    }
}

// MARK: - Preview
#if DEBUG
struct RecordingCountdownView_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                Spacer()
                RecordingCountdownView(
                    isRecording: .constant(true),
                    secondsRemaining: .constant(7)
                )
            }
        }
    }
}
#endif
