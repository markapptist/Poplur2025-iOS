//
//  PolePositionModel.swift
//  Shared Pole Position Model
//

import SwiftUI

// MARK: - Environment key for LocationProvider

struct LocationProviderKey: EnvironmentKey {
    static let defaultValue: LocationProvider? = nil
}

extension EnvironmentValues {
    var locationProvider: LocationProvider? {
        get { self[LocationProviderKey.self] }
        set { self[LocationProviderKey.self] = newValue }
    }
}

// MARK: - Shared pole position model and overlay

// Normalized pole position within the view's content area (0...1 in both axes)
public struct PolePosition {
    public var x: CGFloat
    public var y: CGFloat
    
    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }
}

// Observable model so multiple views (Map, Feed, Camera) can render the pole identically
public final class PolePositionModel: ObservableObject {
    @Published public var position: PolePosition = .init(x: 0.5, y: 0.5)
    
    public init() {}
}

// A lightweight overlay that renders a pole at the normalized position
public struct PoleOverlay: View {
    @EnvironmentObject var poleModel: PolePositionModel

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // Clamp normalized values to [0,1] to avoid accidental overflow
            let nx = min(max(poleModel.position.x, 0), 1)
            let ny = min(max(poleModel.position.y, 0), 1)
            let x = nx * size.width
            let y = ny * size.height

            // Match Map view: blue accuracy halo + white ring center (no filled dot)
            // Since we don't have a map projection in Feed, we use a visual heuristic to size the halo.
            // The halo scales with the shorter screen dimension to suggest radius without geographic accuracy.
            let haloSize = min(size.width, size.height) * 0.25 // tweak as desired for feel

            ZStack {
                // Accuracy halo (visual approximation of MapCircle)
                Circle()
                    .fill(Color.blue.opacity(0.20))
                    .frame(width: haloSize, height: haloSize)
                    .overlay(
                        Circle().stroke(Color.blue.opacity(0.5), lineWidth: 2)
                    )

                // Center marker: white ring only (no center fill)
                Circle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: 20, height: 20)
            }
            .position(x: x, y: y)
            .accessibilityLabel("Pole indicator")
        }
        .allowsHitTesting(false)
    }
}
