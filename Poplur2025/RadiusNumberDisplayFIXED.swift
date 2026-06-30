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

enum CounterSeparatorMetrics {
    static let labelHeight: CGFloat = 16
    static let labelToNumeratorSpacing: CGFloat = 4
    static let numeratorHeight: CGFloat = 48
    static let numeratorToSeparatorSpacing: CGFloat = 2
    static let separatorWidth: CGFloat = 90
    static let separatorHeight: CGFloat = 2
    static let separatorToDenominatorSpacing: CGFloat = 2
    static let denominatorHeight: CGFloat = 34
    static let footerHeight: CGFloat = 18
    static let horizontalPadding: CGFloat = 20
    static let verticalPadding: CGFloat = 16

    static let separatorCenterFromTop: CGFloat =
        verticalPadding
        + labelHeight
        + labelToNumeratorSpacing
        + numeratorHeight
        + numeratorToSeparatorSpacing
        + separatorHeight / 2

    static let counterHeight: CGFloat =
        verticalPadding * 2
        + labelHeight
        + labelToNumeratorSpacing
        + numeratorHeight
        + numeratorToSeparatorSpacing
        + separatorHeight
        + separatorToDenominatorSpacing
        + denominatorHeight
        + footerHeight
}

struct RadiusNumberDisplay: View {
    @Binding var radiusMeters: Double

    private var earthRadiusKilometers: Double { 6371 }

    private var currentRadiusMeters: Double {
        max(0, radiusMeters)
    }

    // Rank calculation based on percentage of Earth's radius
    private var rankPercentage: Double {
        guard earthRadiusKilometers > 0 else { return 0 }
        return currentRadiusMeters / (earthRadiusKilometers * 1000)
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
    
    private var formattedCurrentRadius: String {
        if currentRadiusMeters >= 10_000 {
            return String(format: "%.0f", currentRadiusMeters / 1000)
        } else if currentRadiusMeters >= 1000 {
            return String(format: "%.1f", currentRadiusMeters / 1000)
        } else {
            return String(format: "%.0f", currentRadiusMeters)
        }
    }

    private var currentUnit: String {
        currentRadiusMeters >= 1000 ? "km" : "m"
    }

    private var formattedDenominatorRadius: String {
        NumberFormatter.localizedString(from: NSNumber(value: Int(earthRadiusKilometers)), number: .decimal)
    }

    private var denominatorUnit: String {
        "km"
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            // Label with rank badge
            HStack(spacing: 6) {
                Text("RADIUS")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .poplurTextShader(intensity: 0.72)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .kerning(1.2)
                
                // Rank badge
                Image(systemName: rank.iconName)
                    .poplurIconShader()
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(rank.color)
                    .shadow(color: rank.color.opacity(0.5), radius: 4, x: 0, y: 0)
            }
            .frame(height: CounterSeparatorMetrics.labelHeight, alignment: .center)

            Color.clear
                .frame(height: CounterSeparatorMetrics.labelToNumeratorSpacing)

            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(formattedCurrentRadius)
                    .font(.system(size: 46, weight: .bold))
                    .foregroundStyle(rank.color)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .shadow(color: rank.color.opacity(0.3), radius: 6, x: 0, y: 2)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .monospacedDigit()
                    .poplurMetalNumberShader(intensity: 1.05)
                    .contentTransition(.numericText(value: currentRadiusMeters))

                Text(currentUnit)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.9))
                    .poplurTextShader(intensity: 0.85)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .transition(.scale.combined(with: .opacity))
                    .id(currentUnit)
            }
            .frame(maxWidth: .infinity, minHeight: CounterSeparatorMetrics.numeratorHeight, maxHeight: CounterSeparatorMetrics.numeratorHeight, alignment: .bottomTrailing)

            Color.clear
                .frame(height: CounterSeparatorMetrics.numeratorToSeparatorSpacing)

            Rectangle()
                .fill(rank.color)
                .frame(width: CounterSeparatorMetrics.separatorWidth, height: CounterSeparatorMetrics.separatorHeight)
                .shadow(color: rank.color.opacity(0.5), radius: 2, x: 0, y: 0)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                .alignmentGuide(.counterSeparator) { dimensions in
                    dimensions[VerticalAlignment.center]
                }

            Color.clear
                .frame(height: CounterSeparatorMetrics.separatorToDenominatorSpacing)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(formattedDenominatorRadius)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .poplurMetalNumberShader(intensity: 0.72)

                Text(denominatorUnit)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.78))
                    .poplurTextShader(intensity: 0.68)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
            }
            .frame(maxWidth: .infinity, minHeight: CounterSeparatorMetrics.denominatorHeight, maxHeight: CounterSeparatorMetrics.denominatorHeight, alignment: .topTrailing)

            Color.clear
                .frame(height: CounterSeparatorMetrics.footerHeight)
        }
        .padding(.horizontal, CounterSeparatorMetrics.horizontalPadding)
        .padding(.vertical, CounterSeparatorMetrics.verticalPadding)
        .frame(height: CounterSeparatorMetrics.counterHeight, alignment: .top)
        .alignmentGuide(.counterSeparator) { _ in
            CounterSeparatorMetrics.separatorCenterFromTop
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: radiusMeters)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: rank)
        .accessibilityLabel("Current radius \(formattedCurrentRadius) \(currentUnit)")
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
