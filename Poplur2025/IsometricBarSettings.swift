import SwiftUI

/// Shared settings for the isometric radius bar positioning and appearance
final class IsometricBarSettings: ObservableObject {
    @Published var horizontalOffset: CGFloat = 40
    @Published var bottomOffset: CGFloat = -80
    @Published var barWidth: CGFloat = 98
    @Published var barHeight: CGFloat = 390
    @Published var barTiltDegrees: Double = -8
    
    init() {}
}
