//
//  RadiusNumberDisplay.swift
//  Poplur2025
//
//  Created on 2025-05-09.
//

import SwiftUI

/// A simple numeric display showing the exact radius in miles
/// Replaces the isometric 3D radius bar with clean typography
struct RadiusNumberDisplay: View {
    @Binding var radiusMeters: Double
    
    var radiusMiles: Double {
        radiusMeters / 1609.34 // Convert meters to miles
    }
    
    var formattedRadius: String {
        if radiusMiles < 0.1 {
            return String(format: "%.0f ft", radiusMeters * 3.28084) // Show feet for very small distances
        } else if radiusMiles < 1.0 {
            return String(format: "%.1f mi", radiusMiles)
        } else if radiusMiles < 10.0 {
            return String(format: "%.1f mi", radiusMiles)
        } else if radiusMiles < 100.0 {
            return String(format: "%.0f mi", radiusMiles)
        } else if radiusMiles < 1000.0 {
            return String(format: "%.0f mi", radiusMiles)
        } else {
            // Show in thousands for very large distances
            let thousands = radiusMiles / 1000.0
            return String(format: "%.1fk mi", thousands)
        }
    }
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("RADIUS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .kerning(1.2)
            
            Text(formattedRadius)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText(value: radiusMiles))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

/// Alternative: Minimal badge style
struct RadiusNumberBadge: View {
    @Binding var radiusMeters: Double
    
    var radiusMiles: Double {
        radiusMeters / 1609.34
    }
    
    var formattedRadius: String {
        if radiusMiles < 0.1 {
            return String(format: "%.0f ft", radiusMeters * 3.28084)
        } else if radiusMiles < 10.0 {
            return String(format: "%.1f mi", radiusMiles)
        } else {
            return String(format: "%.0f mi", radiusMiles)
        }
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "scope")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            
            Text(formattedRadius)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText(value: radiusMiles))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
    }
}

/// Alternative: Compact corner badge
struct RadiusCornerBadge: View {
    @Binding var radiusMeters: Double
    
    var radiusMiles: Double {
        radiusMeters / 1609.34
    }
    
    var formattedRadius: String {
        if radiusMiles < 0.1 {
            let feet = Int(radiusMeters * 3.28084)
            return "\(feet) ft"
        } else if radiusMiles < 10.0 {
            return String(format: "%.1f mi", radiusMiles)
        } else {
            return String(format: "%.0f mi", radiusMiles)
        }
    }
    
    var body: some View {
        Text(formattedRadius)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
            .contentTransition(.numericText(value: radiusMiles))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
            )
    }
}

/// Alternative: Elegant centered display with icon
struct RadiusDisplayWithIcon: View {
    @Binding var radiusMeters: Double
    
    var radiusMiles: Double {
        radiusMeters / 1609.34
    }
    
    var formattedRadius: String {
        if radiusMiles < 0.1 {
            return String(format: "%.0f", radiusMeters * 3.28084)
        } else if radiusMiles < 10.0 {
            return String(format: "%.1f", radiusMiles)
        } else if radiusMiles < 1000.0 {
            return String(format: "%.0f", radiusMiles)
        } else {
            let thousands = radiusMiles / 1000.0
            return String(format: "%.1fk", thousands)
        }
    }
    
    var unit: String {
        radiusMiles < 0.1 ? "ft" : "mi"
    }
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary)
            
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(formattedRadius)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: radiusMiles))
                
                Text(unit)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            
            Text("RADIUS")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
                .kerning(1.5)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Preview

#if DEBUG
struct RadiusNumberDisplay_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            // Test different radius values
            RadiusNumberDisplay(radiusMeters: .constant(100))
            RadiusNumberDisplay(radiusMeters: .constant(804.67)) // 0.5 miles
            RadiusNumberDisplay(radiusMeters: .constant(1609.34)) // 1 mile
            RadiusNumberDisplay(radiusMeters: .constant(8046.7)) // 5 miles
            RadiusNumberDisplay(radiusMeters: .constant(160934)) // 100 miles
            RadiusNumberDisplay(radiusMeters: .constant(1609340)) // 1000 miles
            
            Divider()
            
            RadiusNumberBadge(radiusMeters: .constant(1609.34))
            RadiusCornerBadge(radiusMeters: .constant(8046.7))
            RadiusDisplayWithIcon(radiusMeters: .constant(1609.34))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
#endif
