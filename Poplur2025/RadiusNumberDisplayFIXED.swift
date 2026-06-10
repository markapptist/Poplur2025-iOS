//
//  RadiusNumberDisplay.swift
//  Poplur2025
//

import SwiftUI

enum CounterSeparatorAlignment: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat {
        context[VerticalAlignment.center]
    }
}

extension VerticalAlignment {
    static let counterSeparator = VerticalAlignment(CounterSeparatorAlignment.self)
}

struct RadiusNumberDisplay: View {
    @Binding var radiusMeters: Double
    
    @State private var useKilometers: Bool = false
    @State private var animationTimer: Timer? = nil
    
    // Earth's radius constants
    private var earthRadiusMiles: Double { 3959 }
    private var earthRadiusKilometers: Double { 6371 }
    
    // Post radius in current unit
    private var postRadiusMiles: Double { radiusMeters / 1609.34 }
    private var postRadiusKilometers: Double { radiusMeters / 1000.0 }
    
    // Current values based on unit
    private var currentPostRadius: Double { 
        useKilometers ? postRadiusKilometers : postRadiusMiles 
    }
    private var currentEarthRadius: Double { 
        useKilometers ? earthRadiusKilometers : earthRadiusMiles 
    }
    private var currentUnit: String { 
        useKilometers ? "km" : "mi" 
    }
    
    // Rank calculation based on percentage of Earth's radius
    private var rankPercentage: Double {
        guard currentEarthRadius > 0 else { return 0 }
        return currentPostRadius / currentEarthRadius
    }
    
    private var rank: RadiusRank {
        if rankPercentage >= 1.0 {
            return .platinum
        } else if rankPercentage >= 0.67 {
            return .gold
        } else if rankPercentage >= 0.33 {
            return .silver
        } else {
            return .bronze
        }
    }
    
    // Format numerator based on magnitude
    private var formattedNumerator: String {
        if currentPostRadius < 0.1 { 
            return "0" 
        } else if currentPostRadius < 10.0 { 
            return String(format: "%.1f", currentPostRadius) 
        } else { 
            return String(format: "%.0f", currentPostRadius) 
        }
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Label with rank badge
            HStack(spacing: 6) {
                Text("RADIUS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .kerning(1.2)
                
                // Rank badge
                Image(systemName: rank.iconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(rank.color)
                    .shadow(color: rank.color.opacity(0.5), radius: 4, x: 0, y: 0)
            }
            
            // Fraction display: Numerator / Denominator unit
            VStack(alignment: .trailing, spacing: 2) {
                // Numerator (post radius) - colored by rank
                Text(formattedNumerator)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(rank.color)
                    .shadow(color: rank.color.opacity(0.3), radius: 6, x: 0, y: 2)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: currentPostRadius))
                
                // Fraction bar - matches width of denominator
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(rank.color)
                        .frame(width: 90, height: 2)
                        .shadow(color: rank.color.opacity(0.5), radius: 2, x: 0, y: 0)
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                        .alignmentGuide(.counterSeparator) { dimensions in
                            dimensions[VerticalAlignment.center]
                        }
                }
                
                // Denominator (Earth's radius - constant)
                Text(String(format: "%.0f", currentEarthRadius))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: currentEarthRadius))
            }
            
            // Unit - animated
            Text(currentUnit)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(rank.color.opacity(0.9))
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                .transition(.scale.combined(with: .opacity))
                .id(currentUnit) // Force recreation on unit change
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: radiusMeters)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: useKilometers)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: rank)
        .onAppear {
            startUnitAnimation()
        }
        .onDisappear {
            stopUnitAnimation()
        }
    }
    
    private func startUnitAnimation() {
        // Toggle between km and mi every 5 seconds
        animationTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                useKilometers.toggle()
            }
        }
    }
    
    private func stopUnitAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
}

// MARK: - Radius Rank Enum

enum RadiusRank {
    case bronze
    case silver
    case gold
    case platinum
    
    var color: Color {
        switch self {
        case .bronze:
            return Color(red: 0.8, green: 0.5, blue: 0.2) // Bronze
        case .silver:
            return Color(red: 0.75, green: 0.75, blue: 0.75) // Silver
        case .gold:
            return Color(red: 1.0, green: 0.84, blue: 0.0) // Gold
        case .platinum:
            return Color(red: 0.9, green: 1.0, blue: 1.0) // Platinum/Cyan
        }
    }
    
    var iconName: String {
        switch self {
        case .bronze:
            return "shield.fill"
        case .silver:
            return "shield.lefthalf.filled"
        case .gold:
            return "crown.fill"
        case .platinum:
            return "star.fill"
        }
    }
    
    var name: String {
        switch self {
        case .bronze: return "Bronze"
        case .silver: return "Silver"
        case .gold: return "Gold"
        case .platinum: return "Platinum"
        }
    }
}
