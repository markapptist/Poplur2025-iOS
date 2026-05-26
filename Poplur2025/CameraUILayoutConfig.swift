//
//  CameraUILayoutConfig.swift
//  Poplur2025
//
//  Centralized configuration for ALL camera UI positioning
//  Change values here to adjust layout for AR filters, camera roll button, radius display, countdown, etc.
//

import SwiftUI
import CoreGraphics

/// 🎯 **CENTRALIZED CAMERA UI LAYOUT CONFIGURATION**
/// 
/// All camera UI positioning in one place for easy adjustments.
/// Modify values here to reposition AR filters, camera roll button, radius bar, countdown view, etc.
///
/// **Usage:**
/// ```swift
/// let config = CameraUILayoutConfig.shared
/// .offset(y: config.arFilterOffsetY)
/// ```
final class CameraUILayoutConfig: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = CameraUILayoutConfig()
    
    private init() {
        print("📐 [CameraUILayoutConfig] Initialized with default values")
    }
    
    // MARK: - 🎨 AR FILTER SELECTOR POSITIONING
    
    /// Vertical offset from top of screen for AR filter selector (Snapchat-style horizontal scroll)
    /// **Default:** 120 points from top (just below status bar)
    /// **Increase** = move down, **Decrease** = move up
    @Published var arFilterOffsetY: CGFloat = 120
    
    /// Horizontal padding for AR filter selector scroll view
    /// **Default:** 24 points on each side
    @Published var arFilterHorizontalPadding: CGFloat = 24
    
    /// Height of AR filter selector bar
    /// **Default:** 100 points
    @Published var arFilterHeight: CGFloat = 100
    
    /// Whether AR filters should appear above or below the cube
    /// **Default:** true (filters appear above cube)
    @Published var arFilterAboveCube: Bool = true
    
    /// Custom offset from cube when AR filters are positioned relative to cube
    /// Only used if `arFilterAboveCube` is true
    /// **Default:** -150 points (150 points above cube)
    @Published var arFilterCubeRelativeOffset: CGFloat = -150
    
    // MARK: - 📸 CAMERA ROLL BUTTON POSITIONING
    
    /// Horizontal offset from right edge for camera roll button
    /// **Default:** -24 points from trailing edge
    /// **More negative** = closer to edge, **Less negative** = more centered
    @Published var cameraRollTrailingOffset: CGFloat = -24
    
    /// Vertical offset from bottom for camera roll button
    /// **Default:** 140 points from bottom (just above radius bar)
    /// **Increase** = move up, **Decrease** = move down
    @Published var cameraRollBottomOffset: CGFloat = 140
    
    /// Size of camera roll button thumbnail
    /// **Default:** 60x60 points
    @Published var cameraRollSize: CGFloat = 60
    
    /// Corner radius for camera roll button
    /// **Default:** 12 points
    @Published var cameraRollCornerRadius: CGFloat = 12
    
    // MARK: - 📊 RADIUS DISPLAY POSITIONING (Bottom Bar)
    
    /// Vertical offset from bottom for radius display/slider
    /// **Default:** 60 points from bottom (above home indicator)
    /// **Increase** = move up, **Decrease** = move down
    @Published var radiusDisplayBottomOffset: CGFloat = 60
    
    /// Horizontal padding for radius bar from screen edges
    /// **Default:** 20 points on each side
    @Published var radiusDisplayHorizontalPadding: CGFloat = 20
    
    /// Height of radius display bar
    /// **Default:** 60 points
    @Published var radiusDisplayHeight: CGFloat = 60
    
    /// Width of radius value label
    /// **Default:** 100 points
    @Published var radiusLabelWidth: CGFloat = 100
    
    // MARK: - ⏱️ COUNTDOWN VIEW POSITIONING (Recording Timer / Post Count)
    
    /// Horizontal offset from left edge for countdown/post count view
    /// **Default:** 20 points from leading edge
    @Published var countdownLeadingOffset: CGFloat = 20
    
    /// Vertical offset from bottom for countdown view
    /// Should align with radius display for visual consistency
    /// **Default:** 60 points from bottom (same as radius bar)
    @Published var countdownBottomOffset: CGFloat = 60
    
    /// Alignment adjustment to perfectly align countdown with radius bar baseline
    /// **Default:** 0 (no adjustment)
    /// **Positive** = move down, **Negative** = move up
    @Published var countdownBaselineAdjustment: CGFloat = 0
    
    // MARK: - 🎪 CUBE TAB VIEW POSITIONING
    
    /// Vertical offset from bottom for cube tab view
    /// **Default:** 220 points from bottom (above radius bar and countdown)
    /// **Increase** = move up, **Decrease** = move down closer to radius bar
    @Published var cubeBottomOffset: CGFloat = 220
    
    /// Size of cube tab view
    /// **Default:** 200x200 points
    @Published var cubeSize: CGFloat = 200
    
    // MARK: - 🔔 NOTIFICATION BANNER POSITIONING
    
    /// Vertical offset from top for notification banners (permissions, errors, etc.)
    /// **Default:** 60 points from top (below status bar)
    @Published var notificationBannerTopOffset: CGFloat = 60
    
    /// Horizontal padding for notification banners
    /// **Default:** 16 points on each side
    @Published var notificationBannerHorizontalPadding: CGFloat = 16
    
    // MARK: - 🎬 CAMERA CONTROLS POSITIONING
    
    /// Vertical spacing between camera roll button and radius bar
    /// **Default:** 20 points gap
    @Published var cameraRollToRadiusSpacing: CGFloat = 20
    
    /// Vertical spacing between radius bar and cube
    /// **Default:** 40 points gap
    @Published var radiusToCubeSpacing: CGFloat = 40
    
    // MARK: - 📱 SAFE AREA ADJUSTMENTS
    
    /// Additional bottom padding for devices with home indicator
    /// **Default:** 20 points (for iPhone X and later)
    @Published var safeAreaBottomPadding: CGFloat = 20
    
    /// Additional top padding for notch/Dynamic Island devices
    /// **Default:** 0 points (handled automatically by safe area)
    @Published var safeAreaTopPadding: CGFloat = 0
    
    // MARK: - 🎯 COMPUTED POSITIONS
    
    /// Total offset from bottom for camera roll button (includes safe area)
    var cameraRollTotalBottomOffset: CGFloat {
        cameraRollBottomOffset + safeAreaBottomPadding
    }
    
    /// Total offset from bottom for radius display (includes safe area)
    var radiusDisplayTotalBottomOffset: CGFloat {
        radiusDisplayBottomOffset + safeAreaBottomPadding
    }
    
    /// Total offset from bottom for countdown view (includes safe area)
    var countdownTotalBottomOffset: CGFloat {
        countdownBottomOffset + safeAreaBottomPadding + countdownBaselineAdjustment
    }
    
    /// Total offset from bottom for cube (includes safe area)
    var cubeTotalBottomOffset: CGFloat {
        cubeBottomOffset + safeAreaBottomPadding
    }
    
    // MARK: - 🛠️ PRESET LAYOUTS
    
    /// Reset to default layout values
    func resetToDefaults() {
        arFilterOffsetY = 120
        arFilterHorizontalPadding = 24
        arFilterHeight = 100
        arFilterAboveCube = true
        arFilterCubeRelativeOffset = -150
        
        cameraRollTrailingOffset = -24
        cameraRollBottomOffset = 140
        cameraRollSize = 60
        cameraRollCornerRadius = 12
        
        radiusDisplayBottomOffset = 60
        radiusDisplayHorizontalPadding = 20
        radiusDisplayHeight = 60
        radiusLabelWidth = 100
        
        countdownLeadingOffset = 20
        countdownBottomOffset = 60
        countdownBaselineAdjustment = 0
        
        cubeBottomOffset = 220
        cubeSize = 200
        
        notificationBannerTopOffset = 60
        notificationBannerHorizontalPadding = 16
        
        cameraRollToRadiusSpacing = 20
        radiusToCubeSpacing = 40
        
        safeAreaBottomPadding = 20
        safeAreaTopPadding = 0
        
        print("📐 [CameraUILayoutConfig] Reset to default values")
    }
    
    /// Compact layout - everything closer together for smaller screens
    func applyCompactLayout() {
        arFilterOffsetY = 100
        arFilterHeight = 80
        
        cameraRollBottomOffset = 120
        cameraRollSize = 50
        
        radiusDisplayBottomOffset = 50
        radiusDisplayHeight = 50
        
        countdownBottomOffset = 50
        
        cubeBottomOffset = 180
        cubeSize = 180
        
        cameraRollToRadiusSpacing = 15
        radiusToCubeSpacing = 30
        
        print("📐 [CameraUILayoutConfig] Applied compact layout")
    }
    
    /// Spacious layout - more breathing room between elements
    func applySpacedLayout() {
        arFilterOffsetY = 140
        arFilterHeight = 120
        
        cameraRollBottomOffset = 160
        cameraRollSize = 70
        
        radiusDisplayBottomOffset = 70
        radiusDisplayHeight = 70
        
        countdownBottomOffset = 70
        
        cubeBottomOffset = 260
        cubeSize = 220
        
        cameraRollToRadiusSpacing = 30
        radiusToCubeSpacing = 60
        
        print("📐 [CameraUILayoutConfig] Applied spaced layout")
    }
    
    /// AR-focused layout - AR filters more prominent, other UI elements minimized
    func applyARFocusedLayout() {
        arFilterOffsetY = 80
        arFilterHeight = 140
        arFilterHorizontalPadding = 32
        
        cameraRollBottomOffset = 100
        cameraRollSize = 50
        
        radiusDisplayBottomOffset = 40
        radiusDisplayHeight = 50
        
        countdownBottomOffset = 40
        
        cubeBottomOffset = 160
        cubeSize = 160
        
        print("📐 [CameraUILayoutConfig] Applied AR-focused layout")
    }
    
    // MARK: - 📊 DEBUG OVERLAY HELPERS
    
    /// Whether to show debug outlines for all UI elements
    @Published var showDebugOutlines: Bool = false
    
    /// Debug overlay color
    var debugOutlineColor: Color {
        Color.red.opacity(0.3)
    }
    
    /// Print current layout configuration to console
    func printConfiguration() {
        print("""
        
        📐 CAMERA UI LAYOUT CONFIGURATION:
        
        🎨 AR FILTERS:
           • Offset Y: \(arFilterOffsetY)
           • Height: \(arFilterHeight)
           • Horizontal Padding: \(arFilterHorizontalPadding)
           • Above Cube: \(arFilterAboveCube)
           • Cube Relative Offset: \(arFilterCubeRelativeOffset)
        
        📸 CAMERA ROLL:
           • Trailing Offset: \(cameraRollTrailingOffset)
           • Bottom Offset: \(cameraRollBottomOffset)
           • Total Bottom: \(cameraRollTotalBottomOffset)
           • Size: \(cameraRollSize)x\(cameraRollSize)
           • Corner Radius: \(cameraRollCornerRadius)
        
        📊 RADIUS DISPLAY:
           • Bottom Offset: \(radiusDisplayBottomOffset)
           • Total Bottom: \(radiusDisplayTotalBottomOffset)
           • Horizontal Padding: \(radiusDisplayHorizontalPadding)
           • Height: \(radiusDisplayHeight)
           • Label Width: \(radiusLabelWidth)
        
        ⏱️ COUNTDOWN VIEW:
           • Leading Offset: \(countdownLeadingOffset)
           • Bottom Offset: \(countdownBottomOffset)
           • Total Bottom: \(countdownTotalBottomOffset)
           • Baseline Adjustment: \(countdownBaselineAdjustment)
        
        🎪 CUBE TAB VIEW:
           • Bottom Offset: \(cubeBottomOffset)
           • Total Bottom: \(cubeTotalBottomOffset)
           • Size: \(cubeSize)x\(cubeSize)
        
        🔔 NOTIFICATIONS:
           • Top Offset: \(notificationBannerTopOffset)
           • Horizontal Padding: \(notificationBannerHorizontalPadding)
        
        📱 SPACING:
           • Camera Roll to Radius: \(cameraRollToRadiusSpacing)
           • Radius to Cube: \(radiusToCubeSpacing)
           • Safe Area Bottom: \(safeAreaBottomPadding)
           • Safe Area Top: \(safeAreaTopPadding)
        
        """)
    }
}

// MARK: - Environment Key for SwiftUI

struct CameraUILayoutConfigKey: EnvironmentKey {
    static let defaultValue: CameraUILayoutConfig = .shared
}

extension EnvironmentValues {
    var cameraUILayout: CameraUILayoutConfig {
        get { self[CameraUILayoutConfigKey.self] }
        set { self[CameraUILayoutConfigKey.self] = newValue }
    }
}

// MARK: - SwiftUI View Extension for Easy Access

extension View {
    /// Apply camera UI layout configuration to environment
    func cameraUILayoutConfig(_ config: CameraUILayoutConfig = .shared) -> some View {
        self.environment(\.cameraUILayout, config)
    }
}

// MARK: - Preview Helpers

#if DEBUG
struct CameraUILayoutConfig_Previews: PreviewProvider {
    static var previews: some View {
        CameraUILayoutDebugView()
    }
}

/// Debug view showing all camera UI positions with adjustable sliders
struct CameraUILayoutDebugView: View {
    @StateObject private var config = CameraUILayoutConfig.shared
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Camera UI Layout Configuration")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding()
                
                // AR Filters Section
                GroupBox(label: Label("🎨 AR Filters", systemImage: "camera.filters")) {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledSlider(label: "Offset Y", value: $config.arFilterOffsetY, range: 60...300)
                        LabeledSlider(label: "Height", value: $config.arFilterHeight, range: 60...200)
                        LabeledSlider(label: "H. Padding", value: $config.arFilterHorizontalPadding, range: 0...60)
                        Toggle("Above Cube", isOn: $config.arFilterAboveCube)
                        LabeledSlider(label: "Cube Offset", value: $config.arFilterCubeRelativeOffset, range: -300...0)
                    }
                }
                .padding(.horizontal)
                
                // Camera Roll Section
                GroupBox(label: Label("📸 Camera Roll", systemImage: "photo.on.rectangle.angled")) {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledSlider(label: "Trailing Offset", value: $config.cameraRollTrailingOffset, range: -100...0)
                        LabeledSlider(label: "Bottom Offset", value: $config.cameraRollBottomOffset, range: 60...300)
                        LabeledSlider(label: "Size", value: $config.cameraRollSize, range: 40...100)
                        LabeledSlider(label: "Corner Radius", value: $config.cameraRollCornerRadius, range: 0...30)
                    }
                }
                .padding(.horizontal)
                
                // Radius Display Section
                GroupBox(label: Label("📊 Radius Display", systemImage: "chart.bar.fill")) {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledSlider(label: "Bottom Offset", value: $config.radiusDisplayBottomOffset, range: 20...150)
                        LabeledSlider(label: "H. Padding", value: $config.radiusDisplayHorizontalPadding, range: 0...60)
                        LabeledSlider(label: "Height", value: $config.radiusDisplayHeight, range: 40...100)
                        LabeledSlider(label: "Label Width", value: $config.radiusLabelWidth, range: 60...200)
                    }
                }
                .padding(.horizontal)
                
                // Countdown Section
                GroupBox(label: Label("⏱️ Countdown", systemImage: "timer")) {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledSlider(label: "Leading Offset", value: $config.countdownLeadingOffset, range: 0...100)
                        LabeledSlider(label: "Bottom Offset", value: $config.countdownBottomOffset, range: 20...150)
                        LabeledSlider(label: "Baseline Adj.", value: $config.countdownBaselineAdjustment, range: -50...50)
                    }
                }
                .padding(.horizontal)
                
                // Cube Section
                GroupBox(label: Label("🎪 Cube", systemImage: "cube.fill")) {
                    VStack(alignment: .leading, spacing: 12) {
                        LabeledSlider(label: "Bottom Offset", value: $config.cubeBottomOffset, range: 120...400)
                        LabeledSlider(label: "Size", value: $config.cubeSize, range: 120...300)
                    }
                }
                .padding(.horizontal)
                
                // Preset Buttons
                GroupBox(label: Label("🎯 Presets", systemImage: "slider.horizontal.3")) {
                    HStack(spacing: 12) {
                        Button("Default") { config.resetToDefaults() }
                        Button("Compact") { config.applyCompactLayout() }
                        Button("Spaced") { config.applySpacedLayout() }
                        Button("AR Focus") { config.applyARFocusedLayout() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                
                // Debug Toggle
                Toggle("Show Debug Outlines", isOn: $config.showDebugOutlines)
                    .padding(.horizontal)
                
                // Print Button
                Button("Print Configuration") {
                    config.printConfiguration()
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
                
                Spacer(minLength: 40)
            }
        }
    }
}

struct LabeledSlider: View {
    let label: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f", value))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
    }
}
#endif
