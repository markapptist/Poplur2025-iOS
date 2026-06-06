//
//  UIPositioningCatalog.swift
//
//  Created for centralized UI element positioning across tabs.
//

// MARK: - EDITABLE POSITIONS (Change these values)
// This is the single place to edit default UI positioning for each tab.
// Update these dictionaries to reposition labels and buttons per tab.
// Keys are ControlID convenience values like .title, .subtitle, .primaryAction, .secondaryAction
// Example: adjust alignment, offset, padding, zIndex, and scale.

public enum UIPositionsConfig {
    public static let map: [ControlID: UIPosition] = [
        .title: UIPosition(
            alignment: .topLeading,
            offset: CGSize(width: 10, height: 20),
            padding: EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 0),
            zIndex: 1,
            scale: 1
        ),
        .primaryAction: UIPosition(
            alignment: .bottomTrailing,
            offset: CGSize(width: -16, height: -16),
            padding: EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 20),
            zIndex: 2,
            scale: 1
        ),
        .secondaryAction: UIPosition(
            alignment: .topTrailing,
            offset: CGSize(width: -12, height: 24),
            padding: EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 12),
            zIndex: 1,
            scale: 1
        )
    ]
    
    public static let record: [ControlID: UIPosition] = [
        .title: UIPosition(
            alignment: .top,
            offset: CGSize(width: 0, height: 10),
            padding: EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0),
            zIndex: 1,
            scale: 1
        ),
        .primaryAction: UIPosition(
            alignment: .bottom,
            offset: CGSize(width: 0, height: -24),
            padding: EdgeInsets(top: 0, leading: 0, bottom: 24, trailing: 0),
            zIndex: 2,
            scale: 1
        )
    ]
    
    public static let feed: [ControlID: UIPosition] = [
        .title: UIPosition(
            alignment: .topLeading,
            offset: CGSize(width: 14, height: 16),
            padding: EdgeInsets(top: 8, leading: 14, bottom: 0, trailing: 0),
            zIndex: 1,
            scale: 1
        ),
        .secondaryAction: UIPosition(
            alignment: .topTrailing,
            offset: CGSize(width: -16, height: 14),
            padding: EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 16),
            zIndex: 1,
            scale: 1
        )
    ]
    
    public static let profile: [ControlID: UIPosition] = [
        .title: UIPosition(
            alignment: .top,
            offset: CGSize(width: 0, height: 8),
            padding: EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0),
            zIndex: 1,
            scale: 1
        ),
        .primaryAction: UIPosition(
            alignment: .topTrailing,
            offset: CGSize(width: -20, height: 10),
            padding: EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 20),
            zIndex: 2,
            scale: 1
        )
    ]
}

import SwiftUI

// MARK: - Tab Identifiers
public enum TabID: String, CaseIterable {
    case map
    case record
    case feed
    case profile
}

// MARK: - Control Identifiers
public enum ControlID: Hashable {
    case label(String)
    case button(String)
    
    // Convenience static identifiers for common controls
    public static var title: ControlID { .label("title") }
    public static var subtitle: ControlID { .label("subtitle") }
    public static var primaryAction: ControlID { .button("primaryAction") }
    public static var secondaryAction: ControlID { .button("secondaryAction") }
    public static func auxiliary(_ name: String) -> ControlID { .label("aux_\(name)") }
}

// MARK: - UIPosition Struct for Positioning Data
public struct UIPosition: Sendable {
    public var alignment: Alignment
    public var offset: CGSize
    public var padding: EdgeInsets
    public var zIndex: Double
    public var scale: CGFloat
    
    public init(
        alignment: Alignment = .center,
        offset: CGSize = .zero,
        padding: EdgeInsets = EdgeInsets(),
        zIndex: Double = 0,
        scale: CGFloat = 1
    ) {
        self.alignment = alignment
        self.offset = offset
        self.padding = padding
        self.zIndex = zIndex
        self.scale = scale
    }
    
    /// Returns a new UIPosition applying a scale factor,
    /// multiplying offset and scale accordingly.
    public func applying(scaleFactor: CGFloat) -> UIPosition {
        UIPosition(
            alignment: alignment,
            offset: CGSize(width: offset.width * scaleFactor, height: offset.height * scaleFactor),
            padding: padding,
            zIndex: zIndex,
            scale: scale * scaleFactor
        )
    }
}

// MARK: - Device Classification for Overrides
public enum DeviceClass {
    case compactPhone
    case regularPhone
    case plusPhone
    case smallPad
    case largePad
    
    /// Determines the current device class based on screen size and idiom.
    public static func current() -> DeviceClass {
        let size = UIScreen.main.bounds.size
        let width = min(size.width, size.height)
        let height = max(size.width, size.height)
        let idiom = UIDevice.current.userInterfaceIdiom
        
        switch idiom {
        case .phone:
            if width <= 320 {
                return .compactPhone
            }
            if width <= 375 {
                return .regularPhone
            }
            // Consider larger phones as plusPhone or similar
            return .plusPhone
        case .pad:
            // Approximate small vs large iPads by height
            if height <= 1024 {
                return .smallPad
            } else {
                return .largePad
            }
        default:
            // Fallback to regularPhone for unknown idioms
            return .regularPhone
        }
    }
}

// MARK: - Centralized UIPositioningCatalog
/// Use this singleton catalog to register and retrieve UI positioning
/// information for controls in different tabs, optionally overridden per device class.
///
/// From any TabView or similar, use:
/// ```swift
/// let position = UIPositioningCatalog.shared.position(for: .title, in: .map)
/// ```
/// or apply modifier directly:
/// ```swift
/// Text("Map Title")
///   .positioned(tab: .map, control: .title)
/// ```
public final class UIPositioningCatalog: @unchecked Sendable {
    public static let shared = UIPositioningCatalog()
    private init() {}
    
    /// Base map keyed by (TabID, ControlID)
    private var base: [TabID: [ControlID: UIPosition]] = [:]
    
    /// Optional overrides per device class
    private var overrides: [DeviceClass: [TabID: [ControlID: UIPosition]]] = [:]
    
    /// Global scale factor (e.g., accessibility or design tuning)
    public var globalScale: CGFloat = 1.0
    
    // MARK: Registration APIs
    
    /// Register positioning for a control in a tab (base, device independent).
    public func register(_ position: UIPosition, for control: ControlID, in tab: TabID) {
        var tabMap = base[tab] ?? [:]
        tabMap[control] = position
        base[tab] = tabMap
    }
    
    /// Register positioning override for a control in a tab for a specific device class.
    public func registerOverride(_ position: UIPosition, for control: ControlID, in tab: TabID, deviceClass: DeviceClass) {
        var deviceMap = overrides[deviceClass] ?? [:]
        var tabMap = deviceMap[tab] ?? [:]
        tabMap[control] = position
        deviceMap[tab] = tabMap
        overrides[deviceClass] = deviceMap
    }
    
    // MARK: Lookup API
    
    /// Returns the UIPosition for a control in a tab,
    /// preferring device class overrides and applying global scale.
    public func position(for control: ControlID, in tab: TabID) -> UIPosition? {
        let device = DeviceClass.current()
        // Prefer device override
        if let pos = overrides[device]?[tab]?[control] {
            return pos.applying(scaleFactor: globalScale)
        }
        // Fallback to base
        if let pos = base[tab]?[control] {
            return pos.applying(scaleFactor: globalScale)
        }
        return nil
    }
    
    // MARK: Seed Default Positions
    
    /// Register sensible default positions for each tab and common controls,
    /// plus sample device class overrides.
    public func seedDefaults() {
        // Clear first
        base.removeAll()
        overrides.removeAll()
        
        // Load from editable config dictionaries
        for (control, position) in UIPositionsConfig.map { register(position, for: control, in: .map) }
        for (control, position) in UIPositionsConfig.record { register(position, for: control, in: .record) }
        for (control, position) in UIPositionsConfig.feed { register(position, for: control, in: .feed) }
        for (control, position) in UIPositionsConfig.profile { register(position, for: control, in: .profile) }
        
        // Sample Device Overrides
        
        // PlusPhone: shift primaryAction +10 on x in all tabs that have it
        for tab in TabID.allCases {
            if let basePos = base[tab]?[.primaryAction] {
                let overridePos = UIPosition(
                    alignment: basePos.alignment,
                    offset: CGSize(width: basePos.offset.width + 10, height: basePos.offset.height),
                    padding: basePos.padding,
                    zIndex: basePos.zIndex,
                    scale: basePos.scale
                )
                registerOverride(overridePos, for: .primaryAction, in: tab, deviceClass: .plusPhone)
            }
        }
        
        // smallPad: apply 1.1 scale to all controls in all tabs
        for tab in TabID.allCases {
            if let controls = base[tab] {
                for (control, pos) in controls {
                    let overridePos = UIPosition(
                        alignment: pos.alignment,
                        offset: pos.offset,
                        padding: pos.padding,
                        zIndex: pos.zIndex,
                        scale: pos.scale * 1.1
                    )
                    registerOverride(overridePos, for: control, in: tab, deviceClass: .smallPad)
                }
            }
        }
    }
}

// Auto-seed defaults once upon first load.
private let _uiPositioningCatalogSeed: Int = { UIPositioningCatalog.shared.seedDefaults(); return 0 }()

// MARK: - SwiftUI ViewModifier for Applying Positions from Catalog

/// Applies positioning from the UIPositioningCatalog for a given tab and control.
/// Use `.positioned(tab:control:)` on any View to automatically apply alignment,
/// padding, offset, scale, and zIndex defined in the catalog.
public struct PositionedByCatalog: ViewModifier {
    let tab: TabID
    let control: ControlID
    
    public func body(content: Content) -> some View {
        if let pos = UIPositioningCatalog.shared.position(for: control, in: tab) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: pos.alignment)
                .padding(pos.padding)
                .offset(pos.offset)
                .scaleEffect(pos.scale)
                .zIndex(pos.zIndex)
        } else {
            content
        }
    }
}

public extension View {
    /// Applies the position of a control in a tab from the UIPositioningCatalog.
    /// - Parameters:
    ///   - tab: The tab identifier.
    ///   - control: The control identifier.
    /// - Returns: A View modified with the positioning information.
    func positioned(tab: TabID, control: ControlID) -> some View {
        self.modifier(PositionedByCatalog(tab: tab, control: control))
    }
}

#if DEBUG
import Combine

private struct MockTabCanvas: View {
    @State private var selectedTab: TabID = .map
    @State private var showGrid: Bool = true
    @State private var scale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 12) {
            // Controls
            HStack(spacing: 12) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(TabID.allCases, id: \.self) { tab in
                        Text(tab.rawValue.capitalized).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Grid", isOn: $showGrid)
                    .toggleStyle(.switch)

                HStack(spacing: 6) {
                    Text("Scale").font(.caption)
                    Slider(value: $scale, in: 0.8...1.4, step: 0.05)
                        .frame(width: 140)
                        .onChange(of: scale) { _, newValue in
                            UIPositioningCatalog.shared.globalScale = newValue
                        }
                }
            }
            .padding(.horizontal)

            ZStack {
                // Background canvas mimicking app content
                Rectangle()
                    .fill(Color(UIColor.systemBackground))
                    .cornerRadius(20)
                    .shadow(radius: 4)

                if showGrid {
                    Canvas { context, size in
                        let step: CGFloat = 20
                        var path = Path()
                        for x in stride(from: 0, through: size.width, by: step) { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)) }
                        for y in stride(from: 0, through: size.height, by: step) { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)) }
                        context.stroke(path, with: .color(Color.gray.opacity(0.15)), lineWidth: 0.5)
                    }
                    .allowsHitTesting(false)
                }

                // Sample controls using the catalog positions
                // Title
                Text("Title")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .positioned(tab: selectedTab, control: .title)

                // Subtitle (if provided in config for the tab)
                Text("Subtitle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(.thinMaterial, in: Capsule())
                    .opacity(hasPosition(.subtitle, in: selectedTab) ? 1 : 0)
                    .positioned(tab: selectedTab, control: .subtitle)

                // Primary Action
                Button("Primary Action") {}
                    .buttonStyle(.borderedProminent)
                    .positioned(tab: selectedTab, control: .primaryAction)

                // Secondary Action
                Button("Secondary") {}
                    .buttonStyle(.bordered)
                    .positioned(tab: selectedTab, control: .secondaryAction)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            UIPositioningCatalog.shared.globalScale = scale
        }
        .animation(.default, value: selectedTab)
        .animation(.default, value: scale)
    }

    private func hasPosition(_ control: ControlID, in tab: TabID) -> Bool {
        UIPositioningCatalog.shared.position(for: control, in: tab) != nil
    }
}

#Preview("UI Positions Catalog Preview") {
    MockTabCanvas()
        .frame(width: 390, height: 780) // iPhone 15 Pro logical size
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
}
#endif
