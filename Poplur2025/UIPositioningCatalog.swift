import SwiftUI

public enum TabID: String, CaseIterable {
    case map
    case record
    case feed
    case profile
}

public enum ControlID: Hashable {
    case label(String)
    case button(String)

    public static var title: ControlID { .label("title") }
    public static var subtitle: ControlID { .label("subtitle") }
    public static var primaryAction: ControlID { .button("primaryAction") }
    public static var secondaryAction: ControlID { .button("secondaryAction") }
    public static func auxiliary(_ name: String) -> ControlID { .label("aux_\(name)") }
}

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

public enum DeviceClass {
    case compactPhone
    case regularPhone
    case plusPhone
    case smallPad
    case largePad

    public static func current() -> DeviceClass {
        let size = UIScreen.main.bounds.size
        let width = min(size.width, size.height)
        let height = max(size.width, size.height)

        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            if width <= 320 { return .compactPhone }
            if width <= 390 { return .regularPhone }
            return .plusPhone
        case .pad:
            return height <= 1024 ? .smallPad : .largePad
        default:
            return .regularPhone
        }
    }
}

public enum UIPositionsConfig {
    public static let map: [ControlID: UIPosition] = [
        .title: UIPosition(
            alignment: .topLeading,
            offset: CGSize(width: 10, height: 20),
            padding: EdgeInsets(top: 8, leading: 16, bottom: 0, trailing: 0),
            zIndex: 1
        ),
        .primaryAction: UIPosition(
            alignment: .bottomTrailing,
            offset: CGSize(width: -16, height: -16),
            padding: EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 20),
            zIndex: 2
        ),
        .secondaryAction: UIPosition(
            alignment: .topTrailing,
            offset: CGSize(width: -12, height: 24),
            padding: EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 12),
            zIndex: 1
        )
    ]

    public static let record: [ControlID: UIPosition] = [
        .title: UIPosition(
            alignment: .top,
            offset: CGSize(width: 0, height: 10),
            padding: EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0),
            zIndex: 1
        ),
        .primaryAction: UIPosition(
            alignment: .bottom,
            offset: CGSize(width: 0, height: -24),
            padding: EdgeInsets(top: 0, leading: 0, bottom: 24, trailing: 0),
            zIndex: 2
        )
    ]

    public static let feed: [ControlID: UIPosition] = [
        .title: UIPosition(
            alignment: .topLeading,
            offset: CGSize(width: 14, height: 16),
            padding: EdgeInsets(top: 8, leading: 14, bottom: 0, trailing: 0),
            zIndex: 1
        ),
        .secondaryAction: UIPosition(
            alignment: .topTrailing,
            offset: CGSize(width: -16, height: 14),
            padding: EdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 16),
            zIndex: 1
        )
    ]

    public static let profile: [ControlID: UIPosition] = [
        .title: UIPosition(
            alignment: .top,
            offset: CGSize(width: 0, height: 8),
            padding: EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0),
            zIndex: 1
        ),
        .primaryAction: UIPosition(
            alignment: .topTrailing,
            offset: CGSize(width: -20, height: 10),
            padding: EdgeInsets(top: 10, leading: 0, bottom: 0, trailing: 20),
            zIndex: 2
        )
    ]
}

public final class UIPositioningCatalog: @unchecked Sendable {
    public static let shared = UIPositioningCatalog()

    private var base: [TabID: [ControlID: UIPosition]] = [:]
    private var overrides: [DeviceClass: [TabID: [ControlID: UIPosition]]] = [:]

    public var globalScale: CGFloat = 1.0

    private init() {
        seedDefaults()
    }

    public func register(_ position: UIPosition, for control: ControlID, in tab: TabID) {
        var tabMap = base[tab] ?? [:]
        tabMap[control] = position
        base[tab] = tabMap
    }

    public func registerOverride(_ position: UIPosition, for control: ControlID, in tab: TabID, deviceClass: DeviceClass) {
        var deviceMap = overrides[deviceClass] ?? [:]
        var tabMap = deviceMap[tab] ?? [:]
        tabMap[control] = position
        deviceMap[tab] = tabMap
        overrides[deviceClass] = deviceMap
    }

    public func position(for control: ControlID, in tab: TabID) -> UIPosition? {
        let device = DeviceClass.current()
        if let position = overrides[device]?[tab]?[control] {
            return position.applying(scaleFactor: globalScale)
        }
        return base[tab]?[control]?.applying(scaleFactor: globalScale)
    }

    public func seedDefaults() {
        base.removeAll()
        overrides.removeAll()

        for (control, position) in UIPositionsConfig.map {
            register(position, for: control, in: .map)
        }
        for (control, position) in UIPositionsConfig.record {
            register(position, for: control, in: .record)
        }
        for (control, position) in UIPositionsConfig.feed {
            register(position, for: control, in: .feed)
        }
        for (control, position) in UIPositionsConfig.profile {
            register(position, for: control, in: .profile)
        }

        for tab in TabID.allCases {
            if let basePosition = base[tab]?[.primaryAction] {
                registerOverride(
                    UIPosition(
                        alignment: basePosition.alignment,
                        offset: CGSize(width: basePosition.offset.width + 10, height: basePosition.offset.height),
                        padding: basePosition.padding,
                        zIndex: basePosition.zIndex,
                        scale: basePosition.scale
                    ),
                    for: .primaryAction,
                    in: tab,
                    deviceClass: .plusPhone
                )
            }
        }
    }
}

public struct PositionedByCatalog: ViewModifier {
    let tab: TabID
    let control: ControlID

    public func body(content: Content) -> some View {
        if let position = UIPositioningCatalog.shared.position(for: control, in: tab) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: position.alignment)
                .padding(position.padding)
                .offset(position.offset)
                .scaleEffect(position.scale)
                .zIndex(position.zIndex)
        } else {
            content
        }
    }
}

public extension View {
    func positioned(tab: TabID, control: ControlID) -> some View {
        modifier(PositionedByCatalog(tab: tab, control: control))
    }
}

#if DEBUG
private struct UIPositioningCatalogPreviewCanvas: View {
    @State private var selectedTab: TabID = .map
    @State private var showGrid = true
    @State private var scale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(TabID.allCases, id: \.self) { tab in
                        Text(tab.rawValue.capitalized).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Grid", isOn: $showGrid)
            }
            .padding(.horizontal)

            HStack {
                Text("Scale")
                Slider(value: $scale, in: 0.8...1.4, step: 0.05)
                    .onChange(of: scale) { _, value in
                        UIPositioningCatalog.shared.globalScale = value
                    }
            }
            .padding(.horizontal)

            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(uiColor: .systemBackground))
                    .shadow(radius: 4)

                if showGrid {
                    Canvas { context, size in
                        var path = Path()
                        for x in stride(from: 0, through: size.width, by: CGFloat(20)) {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                        }
                        for y in stride(from: 0, through: size.height, by: CGFloat(20)) {
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        }
                        context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)
                    }
                    .allowsHitTesting(false)
                }

                Text("Title")
                    .font(.title3.weight(.semibold))
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .positioned(tab: selectedTab, control: .title)

                Text("Subtitle")
                    .font(.footnote)
                    .padding(6)
                    .background(.thinMaterial, in: Capsule())
                    .opacity(UIPositioningCatalog.shared.position(for: .subtitle, in: selectedTab) == nil ? 0 : 1)
                    .positioned(tab: selectedTab, control: .subtitle)

                Button("Primary Action") {}
                    .buttonStyle(.borderedProminent)
                    .positioned(tab: selectedTab, control: .primaryAction)

                Button("Secondary") {}
                    .buttonStyle(.bordered)
                    .positioned(tab: selectedTab, control: .secondaryAction)
            }
            .padding()
        }
        .onAppear {
            UIPositioningCatalog.shared.globalScale = scale
        }
    }
}

#Preview("UI Positions Catalog Preview") {
    UIPositioningCatalogPreviewCanvas()
        .frame(width: 390, height: 780)
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
}
#endif
