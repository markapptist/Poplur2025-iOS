import SwiftUI
import WatchKit
import SceneKit
import AVFoundation
@preconcurrency import WatchConnectivity

// MARK: - Types

enum RadiusTrend { case up, down, stable }

// MARK: - Static audio helpers (free functions — no actor isolation needed)

private func makeStaticWAV(duration: TimeInterval) -> Data {
    let sampleRate  = 22_050
    let sampleCount = max(1, Int(Double(sampleRate) * duration))
    var samples: [Int16] = []
    samples.reserveCapacity(sampleCount)
    for i in 0..<sampleCount {
        let fadeIn  = min(1.0, Double(i) / 440.0)
        let fadeOut = min(1.0, Double(sampleCount - i) / 880.0)
        let env     = fadeIn * fadeOut
        let noise   = Double.random(in: -1.0...1.0) * 0.62 * env
        let raw     = Int(noise * Double(Int16.max))
        samples.append(Int16(min(Int(Int16.max), max(Int(Int16.min), raw))))
    }
    return makeWAVBytes(samples, sampleRate: sampleRate)
}

private func makeWAVBytes(_ samples: [Int16], sampleRate: Int) -> Data {
    var d = Data()
    func u16(_ v: UInt16) { var b = v.littleEndian; withUnsafeBytes(of: &b) { d.append(contentsOf: $0) } }
    func u32(_ v: UInt32) { var b = v.littleEndian; withUnsafeBytes(of: &b) { d.append(contentsOf: $0) } }
    let ch: UInt16 = 1, bps: UInt16 = 16
    let ds = UInt32(samples.count * 2)
    d.append(contentsOf: "RIFF".utf8); u32(36 + ds)
    d.append(contentsOf: "WAVE".utf8)
    d.append(contentsOf: "fmt ".utf8); u32(16); u16(1); u16(ch)
    u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * UInt32(ch * bps / 8)); u16(ch * bps / 8); u16(bps)
    d.append(contentsOf: "data".utf8); u32(ds)
    for s in samples { var b = s.littleEndian; withUnsafeBytes(of: &b) { d.append(contentsOf: $0) } }
    return d
}

// MARK: - 3D SceneKit globe

private func makeEarthTexture() -> UIImage {
    let width = 512
    let height = 256
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return UIImage() }
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return UIImage() }

    let w = CGFloat(width)
    let h = CGFloat(height)

    // Background ocean
    ctx.setFillColor(UIColor(red: 0.06, green: 0.28, blue: 0.68, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

    // Landmasses
    ctx.setFillColor(UIColor(red: 0.20, green: 0.52, blue: 0.18, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: w*0.04, y: h*0.08, width: w*0.17, height: h*0.30))
    ctx.fillEllipse(in: CGRect(x: w*0.10, y: h*0.36, width: w*0.05, height: h*0.08))
    ctx.fillEllipse(in: CGRect(x: w*0.12, y: h*0.48, width: w*0.11, height: h*0.34))
    ctx.fillEllipse(in: CGRect(x: w*0.22, y: h*0.02, width: w*0.06, height: h*0.10))
    ctx.fillEllipse(in: CGRect(x: w*0.46, y: h*0.07, width: w*0.07, height: h*0.16))
    ctx.fillEllipse(in: CGRect(x: w*0.46, y: h*0.28, width: w*0.10, height: h*0.40))
    ctx.fillEllipse(in: CGRect(x: w*0.53, y: h*0.28, width: w*0.06, height: h*0.14))
    ctx.fillEllipse(in: CGRect(x: w*0.54, y: h*0.04, width: w*0.30, height: h*0.38))
    ctx.fillEllipse(in: CGRect(x: w*0.60, y: h*0.35, width: w*0.07, height: h*0.18))
    ctx.fillEllipse(in: CGRect(x: w*0.72, y: h*0.36, width: w*0.07, height: h*0.14))
    ctx.fillEllipse(in: CGRect(x: w*0.76, y: h*0.56, width: w*0.10, height: h*0.14))

    // Polar caps / clouds
    ctx.setFillColor(UIColor(red: 0.88, green: 0.93, blue: 1.0, alpha: 1).cgColor)
    ctx.fill(CGRect(x: 0, y: h*0.88, width: w, height: h*0.12))
    ctx.fill(CGRect(x: 0, y: 0,      width: w, height: h*0.03))

    guard let cgImage = ctx.makeImage() else { return UIImage() }
    return UIImage(cgImage: cgImage)
}

private struct Globe3DSceneView: WKInterfaceObjectRepresentable {
    typealias WKInterfaceObjectType = WKInterfaceSCNScene

    func makeWKInterfaceObject(context: Context) -> WKInterfaceSCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.black

        let sphere = SCNSphere(radius: 1.0)
        sphere.segmentCount = 48

        let mat = SCNMaterial()
        mat.diffuse.contents  = makeEarthTexture()
        mat.specular.contents = UIColor.white.withAlphaComponent(0.25)
        mat.shininess = 0.4
        mat.isDoubleSided = false
        sphere.materials = [mat]

        let globeNode = SCNNode(geometry: sphere)
        globeNode.eulerAngles = SCNVector3(0, 0, Float(-23.5 * .pi / 180))
        scene.rootNode.addChildNode(globeNode)

        let spin = SCNAction.repeatForever(
            SCNAction.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 12)
        )
        globeNode.runAction(spin)

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.position = SCNVector3(0, 0.2, 3.0)
        cameraNode.eulerAngles = SCNVector3(-0.06, 0, 0)
        scene.rootNode.addChildNode(cameraNode)

        let sunNode = SCNNode()
        let sun = SCNLight()
        sun.type = .directional
        sun.intensity = 900
        sun.color = UIColor(red: 1.0, green: 0.97, blue: 0.90, alpha: 1)
        sunNode.light = sun
        sunNode.eulerAngles = SCNVector3(-0.4, -0.6, 0)
        scene.rootNode.addChildNode(sunNode)

        let ambientNode = SCNNode()
        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 200
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let scnScene = WKInterfaceSCNScene()
        scnScene.scene = scene
        scnScene.preferredFramesPerSecond = 30
        return scnScene
    }

    func updateWKInterfaceObject(_ wkInterfaceObject: WKInterfaceSCNScene, context: Context) {}
}

// MARK: - Globe + trend indicator

private struct GlobeTrendView: View {
    let trend: RadiusTrend
    let arrowPhase: Double

    private let green  = Color(red: 0.20, green: 1.00, blue: 0.15)
    private let red    = Color(red: 1.00, green: 0.18, blue: 0.12)

    var body: some View {
        GeometryReader { geo in
            let globeH = geo.size.height * 0.76
            let arrowH = geo.size.height - globeH

            VStack(spacing: 0) {
                Globe3DSceneView()
                    .frame(width: geo.size.width, height: globeH)

                Canvas { ctx, size in
                    let w = size.width, h = size.height
                    let cx    = w * 0.50
                    let arrowW  = w * 0.28
                    let arrowH2 = h * 0.38
                    let al = cx - arrowW / 2
                    let ar = cx + arrowW / 2

                    switch trend {
                    case .up:
                        let bounce  = CGFloat(sin(arrowPhase * .pi * 2)) * 2.5
                        let arrowCY = h * 0.42 + bounce
                        var p = Path()
                        p.move(to:    CGPoint(x: cx, y: arrowCY - arrowH2))
                        p.addLine(to: CGPoint(x: ar, y: arrowCY + arrowH2 * 0.2))
                        p.addLine(to: CGPoint(x: cx + arrowW * 0.18, y: arrowCY + arrowH2 * 0.2))
                        p.addLine(to: CGPoint(x: cx + arrowW * 0.18, y: arrowCY + arrowH2))
                        p.addLine(to: CGPoint(x: cx - arrowW * 0.18, y: arrowCY + arrowH2))
                        p.addLine(to: CGPoint(x: cx - arrowW * 0.18, y: arrowCY + arrowH2 * 0.2))
                        p.addLine(to: CGPoint(x: al, y: arrowCY + arrowH2 * 0.2))
                        p.closeSubpath()
                        ctx.fill(p, with: .color(green))
                    case .down:
                        let bounce  = CGFloat(sin(arrowPhase * .pi * 2)) * 2.5
                        let arrowCY = h * 0.42 + bounce
                        var p = Path()
                        p.move(to:    CGPoint(x: cx, y: arrowCY + arrowH2))
                        p.addLine(to: CGPoint(x: ar, y: arrowCY - arrowH2 * 0.2))
                        p.addLine(to: CGPoint(x: cx + arrowW * 0.18, y: arrowCY - arrowH2 * 0.2))
                        p.addLine(to: CGPoint(x: cx + arrowW * 0.18, y: arrowCY - arrowH2))
                        p.addLine(to: CGPoint(x: cx - arrowW * 0.18, y: arrowCY - arrowH2))
                        p.addLine(to: CGPoint(x: cx - arrowW * 0.18, y: arrowCY - arrowH2 * 0.2))
                        p.addLine(to: CGPoint(x: al, y: arrowCY - arrowH2 * 0.2))
                        p.closeSubpath()
                        ctx.fill(p, with: .color(red))
                    case .stable:
                        // No bounce — static dash
                        let cy    = h * 0.42
                        let dashW = arrowW * 0.70
                        var p = Path()
                        p.move(to:    CGPoint(x: cx - dashW / 2, y: cy))
                        p.addLine(to: CGPoint(x: cx + dashW / 2, y: cy))
                        ctx.stroke(p, with: .color(green.opacity(0.75)), lineWidth: 2.5)
                    }
                }
                .frame(width: geo.size.width, height: arrowH)
            }
        }
    }
}

// MARK: - Poplur logo mark (actual app icon, circle-clipped, no border)

// MARK: - TV static overlay

private struct StaticOverlay: View {
    let seed: Int
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Animated noise background
            Canvas { ctx, size in
                let block: CGFloat = 4
                let cols = Int(size.width  / block) + 1
                let rows = Int(size.height / block) + 1
                var s = UInt64(bitPattern: Int64(seed &+ 1)) ^ 6_364_136_223_846_793_005
                for row in 0..<rows {
                    for col in 0..<cols {
                        s = s &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                        let v = Double(s >> 33) / Double(UInt32.max)
                        ctx.fill(
                            Path(CGRect(x: CGFloat(col) * block,
                                        y: CGFloat(row)  * block,
                                        width: block, height: block)),
                            with: .color(Color(white: v, opacity: 0.90))
                        )
                    }
                }
            }
            .ignoresSafeArea()

            // Poplur logo centred, gently pulsing — clipped to circle, no border
            Image("poplur_logo")
                .resizable()
                .scaledToFit()
                .frame(width: 68, height: 68)
                .clipShape(Circle())
                .scaleEffect(pulse ? 1.06 : 0.94)
                .animation(
                    .easeInOut(duration: 0.55).repeatForever(autoreverses: true),
                    value: pulse
                )
                .onAppear { pulse = true }
        }
    }
}

// MARK: - LCD overlay

private struct LCDOverlay: View {
    @ObservedObject var store: WatchRadiusStore
    let arrowPhase: Double
    let showKm: Bool

    private let lcdGreen  = Color(red: 0.22, green: 1.00, blue: 0.15)
    private let lcdOrange = Color(red: 1.00, green: 0.58, blue: 0.04)
    private let lcdBlue   = Color(red: 0.24, green: 0.78, blue: 1.00)
    private let divider   = Color(red: 0.10, green: 0.45, blue: 0.10)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .topLeading) {
                Color.black

                VStack(spacing: 0) {
                    header(w: w, h: h * 0.115)

                    HStack(alignment: .top, spacing: 0) {
                        GlobeTrendView(trend: store.trend,
                                       arrowPhase: arrowPhase)
                            .frame(width: w * 0.54, height: h * 0.635)

                        dataColumn(w: w * 0.46, h: h * 0.635)
                    }

                    Spacer(minLength: 0)

                    Rectangle().fill(divider).frame(height: 0.5)
                    tabBar(w: w, h: h * 0.115)

                    Rectangle().fill(divider).frame(height: 0.5)
                    statsBar(w: w, h: h * 0.105)
                }
            }
        }
    }

    // MARK: Header

    @ViewBuilder private func header(w: CGFloat, h: CGFloat) -> some View {
        VStack(spacing: 1) {
            Text("DATA BANK 50")
                .font(.system(size: w * 0.095, weight: .semibold, design: .monospaced))
                .foregroundColor(lcdOrange)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text("WATER RESIST")
                .font(.system(size: w * 0.070, weight: .regular, design: .monospaced))
                .foregroundColor(lcdBlue)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 8)
        .frame(width: w, height: h)
    }

    // MARK: Data column (world time + radius)

    @ViewBuilder private func dataColumn(w: CGFloat, h: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            VStack(alignment: .trailing, spacing: 0) {
                Text("WORLD TIME")
                    .font(.system(size: w * 0.115, weight: .medium, design: .monospaced))
                    .foregroundColor(lcdBlue)
                    .lineLimit(1).minimumScaleFactor(0.5)

                Text(currentTime())
                    .font(.system(size: w * 0.280, weight: .bold, design: .monospaced))
                    .foregroundColor(lcdGreen)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            .frame(width: w, height: h * 0.28, alignment: .trailing)
            .padding(.trailing, 8)

            Rectangle().fill(divider).frame(height: 0.5)

            Text("RADIUS")
                .font(.system(size: w * 0.115, weight: .medium, design: .monospaced))
                .foregroundColor(lcdBlue)
                .frame(width: w, alignment: .trailing)
                .padding(.trailing, 8)
                .padding(.top, 2)

            Text(showKm ? store.displayValue(metric: true)
                        : store.displayValue(metric: false))
                .id("radius_\(showKm)")
                .font(.system(size: w * 0.360, weight: .bold, design: .monospaced))
                .foregroundColor(lcdGreen)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: w, alignment: .trailing)
                .padding(.trailing, 8)
                .transition(.opacity)

            Text("\(store.postCount)")
                .font(.system(size: w * 0.230, weight: .bold, design: .monospaced))
                .foregroundColor(lcdGreen.opacity(0.75))
                .frame(width: w, alignment: .trailing)
                .padding(.trailing, 8)

            Text(showKm ? "/6371" : "/3959")
                .id("denom_\(showKm)")
                .font(.system(size: w * 0.155, weight: .medium, design: .monospaced))
                .foregroundColor(lcdGreen.opacity(0.85))
                .frame(width: w, alignment: .trailing)
                .padding(.trailing, 8)
                .transition(.opacity)

            Text(showKm ? "km" : "mi")
                .id("unit_\(showKm)")
                .font(.system(size: w * 0.120, weight: .regular, design: .monospaced))
                .foregroundColor(lcdGreen.opacity(0.70))
                .frame(width: w, alignment: .trailing)
                .padding(.trailing, 8)
                .transition(.opacity)

            Spacer(minLength: 0)
        }
        .frame(width: w, height: h)
        .animation(.easeInOut(duration: 0.35), value: showKm)
    }

    // MARK: Tab bar

    @ViewBuilder private func tabBar(w: CGFloat, h: CGFloat) -> some View {
        HStack(spacing: 0) {
            tabItem("SCH",        w: w / 3)
            Rectangle().fill(divider).frame(width: 0.5, height: h * 0.7)
            tabItem("WORLD TIME", w: w / 3)
            Rectangle().fill(divider).frame(width: 0.5, height: h * 0.7)
            tabItem("TEL",        w: w / 3)
        }
        .frame(height: h)
    }

    @ViewBuilder private func tabItem(_ label: String, w: CGFloat) -> some View {
        Text(label)
            .font(.system(size: w * 0.165, weight: .medium, design: .monospaced))
            .foregroundColor(lcdGreen)
            .lineLimit(1).minimumScaleFactor(0.4)
            .frame(width: w)
    }

    // MARK: Stats bar

    @ViewBuilder private func statsBar(w: CGFloat, h: CGFloat) -> some View {
        let battery = store.batteryPercent
        let posts   = store.postCount
        HStack(spacing: 0) {
            statChip("↑\(posts)",      w: w * 0.28)
            statChip("◾84°F",         w: w * 0.27)
            statChip("🔋\(battery)%",  w: w * 0.25)
            statChip("♥75",            w: w * 0.20)
        }
        .frame(height: h)
    }

    @ViewBuilder private func statChip(_ label: String, w: CGFloat) -> some View {
        Text(label)
            .font(.system(size: w * 0.220, weight: .regular, design: .monospaced))
            .foregroundColor(lcdGreen.opacity(0.80))
            .lineLimit(1).minimumScaleFactor(0.4)
            .frame(width: w)
    }

    // MARK: Helpers

    private func currentTime() -> String {
        let f = DateFormatter()
        f.dateFormat = "H:mm"
        return f.string(from: Date())
    }
}

// MARK: - Main watch view

struct RadiusWatchView: View {
    @EnvironmentObject private var store: WatchRadiusStore

    @State private var showKm         = true
    @State private var isShowingStatic = false
    @State private var staticPlayer:  AVAudioPlayer?

    private let switchTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        TimelineView(.animation) { tl in
            let t          = tl.date.timeIntervalSinceReferenceDate
            let arrowPhase = (t / 1.4).truncatingRemainder(dividingBy: 1.0)

            ZStack {
                LCDOverlay(store: store,
                           arrowPhase: arrowPhase,
                           showKm: showKm)

                if isShowingStatic {
                    StaticOverlay(seed: Int(t * 22) & 0x7FFF_FFFF)
                }
            }
        }
        .ignoresSafeArea()
        // Touch: show static + audio while held; toggle km/mi on release
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isShowingStatic {
                        isShowingStatic = true
                        playStatic()
                    }
                }
                .onEnded { _ in
                    isShowingStatic = false
                    staticPlayer?.stop()
                    staticPlayer = nil
                    withAnimation(.easeInOut(duration: 0.35)) { showKm.toggle() }
                }
        )
        // Auto-switch km/mi every 4 s (separate from tap)
        .onReceive(switchTimer) { _ in
            withAnimation(.easeInOut(duration: 0.35)) { showKm.toggle() }
        }
        .persistentSystemOverlays(.hidden)
        .accessibilityLabel("Poplur watch face — tap to toggle km/mi")
    }

    private func playStatic() {
        let wavData = makeStaticWAV(duration: 0.65)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(data: wavData)
            player.volume = 0.65
            player.play()
            staticPlayer = player
        } catch {
            // Silently continue — visual static still shows
        }
    }
}

// MARK: - WatchRadiusStore

@MainActor
final class WatchRadiusStore: NSObject, ObservableObject {
    @Published private(set) var radiusMeters: Double
    @Published private(set) var postCount: Int
    @Published private(set) var updatedAt: Date?
    @Published private(set) var trend: RadiusTrend = .stable

    private let radiusKey  = "poplur.watch.overallRadiusMeters"
    private let prevKey    = "poplur.watch.previousRadiusMeters"
    private let postKey    = "poplur.watch.postCount"
    private let updatedKey = "poplur.watch.updatedAt"

    override init() {
        let d = UserDefaults.standard
        radiusMeters = d.double(forKey: "poplur.watch.overallRadiusMeters")
        postCount    = d.integer(forKey: "poplur.watch.postCount")
        let ts = d.double(forKey: "poplur.watch.updatedAt")
        updatedAt = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        super.init()
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        recomputeTrend()
        configureSession()
    }

    var batteryPercent: Int {
        let level = WKInterfaceDevice.current().batteryLevel
        return level < 0 ? 0 : Int(level * 100)
    }

    func displayValue(metric: Bool) -> String {
        guard radiusMeters > 0 else { return "0" }
        if metric {
            let km = radiusMeters / 1_000
            return km >= 10 ? String(format: "%.0f", km) : String(format: "%.1f", km)
        } else {
            let mi = radiusMeters / 1_609.344
            return mi >= 10 ? String(format: "%.0f", mi) : String(format: "%.1f", mi)
        }
    }

    var needsPhoneSync: Bool { updatedAt == nil || radiusMeters <= 0 }

    private func recomputeTrend() {
        let prev = UserDefaults.standard.double(forKey: prevKey)
        guard prev > 0, radiusMeters > 0 else { trend = .stable; return }
        let delta     = radiusMeters - prev
        let threshold = max(radiusMeters * 0.03, 1_000.0)
        trend = delta > threshold ? .up : delta < -threshold ? .down : .stable
    }

    private func apply(_ payload: [String: Any]) {
        let radius = Self.dbl("overallRadiusMeters", payload)
            ?? Self.dbl("radiusMeters", payload)
            ?? Self.dbl("radius", payload) ?? 0
        let posts = Self.int("postCount", payload) ?? 0
        let ts    = Self.dbl("updatedAt", payload) ?? Date().timeIntervalSince1970

        let d = UserDefaults.standard
        d.set(radiusMeters, forKey: prevKey)
        radiusMeters = max(0, radius)
        postCount    = max(0, posts)
        updatedAt    = Date(timeIntervalSince1970: ts)
        d.set(radiusMeters, forKey: radiusKey)
        d.set(postCount,    forKey: postKey)
        d.set(ts,           forKey: updatedKey)
        recomputeTrend()
    }

    private func configureSession() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private static func dbl(_ key: String, _ p: [String: Any]) -> Double? {
        if let v = p[key] as? Double   { return v }
        if let v = p[key] as? Int      { return Double(v) }
        if let v = p[key] as? NSNumber { return v.doubleValue }
        if let v = p[key] as? String   { return Double(v) }
        return nil
    }

    private static func int(_ key: String, _ p: [String: Any]) -> Int? {
        if let v = p[key] as? Int      { return v }
        if let v = p[key] as? Double   { return Int(v) }
        if let v = p[key] as? NSNumber { return v.intValue }
        if let v = p[key] as? String   { return Int(v) }
        return nil
    }
}

extension WatchRadiusStore: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor in self.apply(context) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.apply(message) }
    }
}

#Preview {
    RadiusWatchView()
        .environmentObject(WatchRadiusStore())
}
