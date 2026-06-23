import SwiftUI
import SpriteKit

public struct MockBrowser<Content: View>: View {
    public let urlString: String
    public let content: Content

    @StateObject private var sceneStore = BrowserSceneStore()

    public init(urlString: String, @ViewBuilder content: () -> Content) {
        self.urlString = urlString
        self.content = content()
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.white
                    .ignoresSafeArea()

                BrowserSpriteSceneView(scene: sceneStore.scene, urlString: urlString)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: BrowserChromeMetrics.height)

                    ScrollView(showsIndicators: false) {
                        content
                            .frame(maxWidth: .infinity)
                    }
                    .background(Color.white)
                }
            }
            .coordinateSpace(name: BrowserChromeMetrics.coordinateSpace)
            .onAppear {
                sceneStore.scene.updateLayout(size: proxy.size, urlString: urlString)
            }
            .onChange(of: proxy.size) { _, newSize in
                sceneStore.scene.updateLayout(size: newSize, urlString: urlString)
            }
            .onChange(of: urlString) { _, newURL in
                sceneStore.scene.updateLayout(size: proxy.size, urlString: newURL)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(BrowserChromeMetrics.coordinateSpace))
                    .onChanged { value in
                        sceneStore.scene.moveCursor(to: value.location, pressed: true)
                    }
                    .onEnded { value in
                        sceneStore.scene.click(at: value.location)
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    sceneStore.scene.moveCursor(to: location, pressed: false)
                case .ended:
                    sceneStore.scene.hideCursor()
                }
            }
        }
        .background(Color.white)
    }
}

private enum BrowserChromeMetrics {
    static let height: CGFloat = 108
    static let titleHeight: CGFloat = 38
    static let toolbarHeight: CGFloat = height - titleHeight
    static let coordinateSpace = "PoplurBrowserCanvas"
}

private final class BrowserSceneStore: ObservableObject {
    let scene = PoplurBrowserChromeScene()
}

private struct BrowserSpriteSceneView: UIViewRepresentable {
    let scene: PoplurBrowserChromeScene
    let urlString: String

    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: .zero)
        view.allowsTransparency = true
        view.backgroundColor = .clear
        view.isOpaque = false
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.isUserInteractionEnabled = false
        scene.scaleMode = .resizeFill
        view.presentScene(scene)
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {
        if uiView.scene !== scene {
            uiView.presentScene(scene)
        }
        let size = uiView.bounds.size
        guard size.width > 1, size.height > 1 else { return }
        scene.updateLayout(size: size, urlString: urlString)
    }
}

private final class PoplurBrowserChromeScene: SKScene {
    private var chromeLayer = SKNode()
    private var cursorLayer = SKNode()
    private var cursorNode: SKShapeNode?
    private var currentURL = ""
    private var currentLayoutSize: CGSize = .zero

    private static let chromeShader = SKShader(source: """
    void main() {
        vec4 base = v_color_mix;
        float line = sin((v_path_distance + u_time * 18.0) * 0.045) * 0.5 + 0.5;
        float sheen = smoothstep(0.72, 1.0, line) * 0.045;
        gl_FragColor = vec4(base.rgb + vec3(sheen), base.a);
    }
    """)

    override init() {
        super.init(size: UIScreen.main.bounds.size)
        scaleMode = .resizeFill
        backgroundColor = .clear
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        view.allowsTransparency = true
        view.backgroundColor = .clear
        buildCursorIfNeeded()
        updateLayout(size: size, urlString: currentURL)
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // Avoid re-entrant layout loops and redundant updates
        guard size != oldSize else { return }
        if currentLayoutSize != size {
            updateLayout(size: size, urlString: currentURL)
        }
    }

    func updateLayout(size newSize: CGSize, urlString: String) {
        guard newSize.width > 1, newSize.height > 1 else { return }
        // Ensure the scene is attached to a view before mutating node graph
        guard view != nil else { return }

        let shouldRebuild = currentLayoutSize != newSize || currentURL != urlString || chromeLayer.parent == nil

        currentLayoutSize = newSize
        currentURL = urlString
        if self.size != newSize {
            self.size = newSize
        }

        guard shouldRebuild else { return }
        // Defer rebuild to the next run loop to avoid SpriteKit render-pass mutations
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // Double-check attachment and current layout before rebuilding
            guard self.view != nil, self.currentLayoutSize == newSize, self.currentURL == urlString else { return }
            self.rebuildChrome()
            self.buildCursorIfNeeded()
        }
    }

    func moveCursor(to point: CGPoint, pressed: Bool) {
        buildCursorIfNeeded()
        guard let cursorNode else { return }
        cursorNode.isHidden = false
        cursorNode.position = scenePoint(fromViewPoint: point)
        cursorNode.run(.scale(to: pressed ? 0.86 : 1.0, duration: 0.08))
    }

    func click(at point: CGPoint) {
        moveCursor(to: point, pressed: false)

        let scenePoint = scenePoint(fromViewPoint: point)
        let ring = SKShapeNode(circleOfRadius: 7)
        ring.position = scenePoint
        ring.strokeColor = UIColor.black.withAlphaComponent(0.30)
        ring.fillColor = .clear
        ring.lineWidth = 1.5
        ring.zPosition = 900
        cursorLayer.addChild(ring)

        ring.run(.sequence([
            .group([
                .scale(to: 4.4, duration: 0.32),
                .fadeOut(withDuration: 0.32)
            ]),
            .removeFromParent()
        ]))
    }

    func hideCursor() {
        cursorNode?.isHidden = true
    }

    private func rebuildChrome() {
        chromeLayer.removeFromParent()
        chromeLayer = SKNode()
        chromeLayer.zPosition = 10
        addChild(chromeLayer)

        let backgroundRect = CGRect(origin: .zero, size: currentLayoutSize)
        let background = rectNode(
            rect: backgroundRect,
            radius: 0,
            fill: UIColor(red: 0.965, green: 0.965, blue: 0.975, alpha: 1.0),
            stroke: .clear,
            lineWidth: 0
        )
        background.zPosition = 0
        chromeLayer.addChild(background)

        let titleRect = CGRect(
            x: 0,
            y: currentLayoutSize.height - BrowserChromeMetrics.titleHeight,
            width: currentLayoutSize.width,
            height: BrowserChromeMetrics.titleHeight
        )
        let titleBar = rectNode(
            rect: titleRect,
            radius: 0,
            fill: UIColor(red: 0.91, green: 0.915, blue: 0.93, alpha: 1.0),
            stroke: UIColor.black.withAlphaComponent(0.08),
            lineWidth: 0.5
        )
        titleBar.fillShader = Self.chromeShader
        titleBar.zPosition = 2
        chromeLayer.addChild(titleBar)

        let toolbarRect = CGRect(
            x: 0,
            y: currentLayoutSize.height - BrowserChromeMetrics.height,
            width: currentLayoutSize.width,
            height: BrowserChromeMetrics.toolbarHeight
        )
        let toolbar = rectNode(
            rect: toolbarRect,
            radius: 0,
            fill: UIColor(red: 0.955, green: 0.958, blue: 0.968, alpha: 1.0),
            stroke: UIColor.black.withAlphaComponent(0.08),
            lineWidth: 0.5
        )
        toolbar.fillShader = Self.chromeShader
        toolbar.zPosition = 2
        chromeLayer.addChild(toolbar)

        addTrafficLights(in: titleRect)
        addBrowserControls(in: toolbarRect)
        addAddressBar(in: toolbarRect)
        addPageDivider(at: toolbarRect.minY)

        cursorLayer.removeFromParent()
        cursorLayer.zPosition = 800
        addChild(cursorLayer)
    }

    private func addTrafficLights(in rect: CGRect) {
        let colors = [
            UIColor(red: 1.0, green: 0.36, blue: 0.31, alpha: 1.0),
            UIColor(red: 1.0, green: 0.78, blue: 0.24, alpha: 1.0),
            UIColor(red: 0.20, green: 0.80, blue: 0.35, alpha: 1.0)
        ]

        for (index, color) in colors.enumerated() {
            let node = SKShapeNode(circleOfRadius: 6)
            node.fillColor = color
            node.strokeColor = UIColor.black.withAlphaComponent(0.10)
            node.lineWidth = 0.5
            node.position = CGPoint(x: 18 + CGFloat(index) * 20, y: rect.midY)
            node.zPosition = 4
            chromeLayer.addChild(node)
        }
    }

    private func addBrowserControls(in rect: CGRect) {
        let leftInset: CGFloat = currentLayoutSize.width < 520 ? 12 : 18
        let labels = ["<", ">", "reload"]

        for (index, value) in labels.enumerated() {
            let button = rectNode(
                rect: CGRect(x: leftInset + CGFloat(index) * 39, y: rect.midY - 16, width: 30, height: 30),
                radius: 15,
                fill: UIColor.white.withAlphaComponent(0.75),
                stroke: UIColor.black.withAlphaComponent(0.08),
                lineWidth: 0.5
            )
            button.zPosition = 4
            chromeLayer.addChild(button)

            let label = SKLabelNode(text: value)
            label.fontName = "SFProText-Semibold"
            label.fontSize = value == "reload" ? 8.5 : 16
            label.fontColor = UIColor.black.withAlphaComponent(0.46)
            label.verticalAlignmentMode = .center
            label.horizontalAlignmentMode = .center
            label.position = CGPoint(x: button.frame.midX, y: button.frame.midY - (value == "reload" ? 0.5 : 0))
            label.zPosition = 5
            chromeLayer.addChild(label)
        }
    }

    private func addAddressBar(in rect: CGRect) {
        let compact = currentLayoutSize.width < 520
        let x: CGFloat = compact ? 132 : 154
        let rightInset: CGFloat = compact ? 12 : 20
        let barRect = CGRect(
            x: x,
            y: rect.midY - 18,
            width: max(120, currentLayoutSize.width - x - rightInset),
            height: 36
        )

        let address = rectNode(
            rect: barRect,
            radius: 18,
            fill: UIColor.white.withAlphaComponent(0.88),
            stroke: UIColor.black.withAlphaComponent(0.08),
            lineWidth: 0.8
        )
        address.fillShader = Self.chromeShader
        address.zPosition = 4
        chromeLayer.addChild(address)

        let lock = SKLabelNode(text: "lock")
        lock.fontName = "SFProText-Semibold"
        lock.fontSize = 8.5
        lock.fontColor = UIColor(red: 0.08, green: 0.47, blue: 0.22, alpha: 1.0)
        lock.verticalAlignmentMode = .center
        lock.horizontalAlignmentMode = .left
        lock.position = CGPoint(x: barRect.minX + 14, y: barRect.midY)
        lock.zPosition = 5
        chromeLayer.addChild(lock)

        let urlLabel = SKLabelNode(text: currentURL)
        urlLabel.fontName = "SFProText-Medium"
        urlLabel.fontSize = compact ? 13 : 14
        urlLabel.fontColor = UIColor.black.withAlphaComponent(0.72)
        urlLabel.verticalAlignmentMode = .center
        urlLabel.horizontalAlignmentMode = .left
        urlLabel.position = CGPoint(x: barRect.minX + (compact ? 47 : 52), y: barRect.midY)
        urlLabel.zPosition = 5
        chromeLayer.addChild(urlLabel)
    }

    private func addPageDivider(at y: CGFloat) {
        let divider = SKShapeNode(rect: CGRect(x: 0, y: y, width: currentLayoutSize.width, height: 1))
        divider.fillColor = UIColor.black.withAlphaComponent(0.08)
        divider.strokeColor = .clear
        divider.zPosition = 6
        chromeLayer.addChild(divider)
    }

    private func buildCursorIfNeeded() {
        guard cursorNode == nil else { return }

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -27))
        path.addLine(to: CGPoint(x: 8, y: -20))
        path.addLine(to: CGPoint(x: 13, y: -31))
        path.addLine(to: CGPoint(x: 18, y: -29))
        path.addLine(to: CGPoint(x: 13, y: -18))
        path.addLine(to: CGPoint(x: 24, y: -18))
        path.closeSubpath()

        let cursor = SKShapeNode(path: path)
        cursor.fillColor = UIColor.white.withAlphaComponent(0.98)
        cursor.strokeColor = UIColor.black.withAlphaComponent(0.72)
        cursor.lineWidth = 1.2
        cursor.glowWidth = 1.5
        cursor.zPosition = 901
        cursor.isHidden = true
        cursorLayer.addChild(cursor)
        cursorNode = cursor
    }

    private func scenePoint(fromViewPoint point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: currentLayoutSize.height - point.y)
    }

    private func rectNode(rect: CGRect, radius: CGFloat, fill: UIColor, stroke: UIColor, lineWidth: CGFloat) -> SKShapeNode {
        let path: CGPath
        if radius > 0 {
            path = UIBezierPath(roundedRect: rect, cornerRadius: radius).cgPath
        } else {
            path = UIBezierPath(rect: rect).cgPath
        }

        let node = SKShapeNode(path: path)
        node.fillColor = fill
        node.strokeColor = stroke
        node.lineWidth = lineWidth
        return node
    }
}

struct MockBrowser_Previews: PreviewProvider {
    static var previews: some View {
        MockBrowser(urlString: "www.poplurstore.ca") {
            VStack(spacing: 24) {
                Text("Poplur Store")
                    .font(.largeTitle.bold())

                Text("Preview content")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 800)
            .background(Color.white)
        }
    }
}
