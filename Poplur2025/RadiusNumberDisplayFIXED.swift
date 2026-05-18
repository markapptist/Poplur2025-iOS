//
//  RadiusNumberDisplay.swift
//  Poplur2025
//

import SwiftUI

struct RadiusNumberDisplay: View {
    @Binding var radiusMeters: Double
    
    // Earth's radius in miles (constant denominator)
    private var earthRadiusMiles: Double { 3959 }
    
    // Post radius in miles (numerator)
    private var postRadiusMiles: Double { radiusMeters / 1609.34 }
    
    // Format numerator based on magnitude
    private var formattedNumerator: String {
        if postRadiusMiles < 0.1 { 
            return "0" 
        } else if postRadiusMiles < 10.0 { 
            return String(format: "%.1f", postRadiusMiles) 
        } else { 
            return String(format: "%.0f", postRadiusMiles) 
        }
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Label
            Text("RADIUS")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                .kerning(1.2)
            
            // Fraction display: Numerator / Denominator mi
            VStack(alignment: .trailing, spacing: 2) {
                // Numerator (post radius)
                Text(formattedNumerator)
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: postRadiusMiles))
                
                // Fraction bar - matches width of denominator
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(.white)
                        .frame(width: 90, height: 2)  // Width matches "3959" text
                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                }
                
                // Denominator (Earth's radius - constant)
                Text("3959")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
                    .monospacedDigit()
            }
            
            // Unit
            Text("mi")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: radiusMeters)
    }
}

