//
//  RadiusNumberDisplay.swift
//  Poplur2025
//

import SwiftUI

struct RadiusNumberDisplay: View {
    @Binding var radiusMeters: Double
    
    private var earthRadius: Double { 3958.8 }
    private var postRadius: Double { radiusMeters / 1609.34 }
    
    private var numeratorText: String {
        if postRadius < 0.1 { return "0" }
        else if postRadius < 10.0 { return String(format: "%.1f", postRadius) }
        else if postRadius < 100.0 { return String(format: "%.0f", postRadius) }
        else { return String(format: "%.0f", postRadius) }
    }
    
    private var denominatorText: String { String(format: "%.0f", earthRadius) }
    
    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            Text("RADIUS")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .kerning(1.2)
            
            VStack(spacing: 0) {
                Text(numeratorText)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 60, height: 2)
                    .padding(.vertical, 2)
                
                Text(denominatorText)
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            
            Text("mi")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
                .kerning(1.0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
}

struct RadiusNumberBadge: View {
    @Binding var radiusMeters: Double
    private var earthRadius: Double { 3958.8 }
    private var postRadius: Double { radiusMeters / 1609.34 }
    
    private var numeratorText: String {
        if postRadius < 0.1 { return "0" }
        else if postRadius < 10.0 { return String(format: "%.1f", postRadius) }
        else { return String(format: "%.0f", postRadius) }
    }
    
    private var denominatorText: String { String(format: "%.0f", earthRadius) }
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "scope")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            
            HStack(spacing: 2) {
                Text(numeratorText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                
                Text("/")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                
                Text(denominatorText)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                
                Text("mi")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
    }
}

struct RadiusCornerBadge: View {
    @Binding var radiusMeters: Double
    private var earthRadius: Double { 3958.8 }
    private var postRadius: Double { radiusMeters / 1609.34 }
    
    private var numeratorText: String {
        if postRadius < 0.1 { return "0" }
        else if postRadius < 10.0 { return String(format: "%.1f", postRadius) }
        else { return String(format: "%.0f", postRadius) }
    }
    
    private var denominatorText: String { String(format: "%.0f", earthRadius) }
    
    var body: some View {
        HStack(spacing: 3) {
            Text(numeratorText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
            
            Text("/")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            
            Text(denominatorText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .monospacedDigit()
            
            Text("mi")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 1))
    }
}

struct RadiusDisplayWithIcon: View {
    @Binding var radiusMeters: Double
    private var earthRadius: Double { 3958.8 }
    private var postRadius: Double { radiusMeters / 1609.34 }
    
    private var numeratorText: String {
        if postRadius < 0.1 { return "0" }
        else if postRadius < 10.0 { return String(format: "%.1f", postRadius) }
        else if postRadius < 100.0 { return String(format: "%.0f", postRadius) }
        else { return String(format: "%.0f", postRadius) }
    }
    
    private var denominatorText: String { String(format: "%.0f", earthRadius) }
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.dotted")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 2) {
                Text(numeratorText)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 70, height: 2)
                
                HStack(spacing: 4) {
                    Text(denominatorText)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    
                    Text("mi")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
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
