import SwiftUI
import WatchKit
@preconcurrency import WatchConnectivity

// MARK: - Types

enum RadiusTrend { case up, down, stable }

// MARK: - Layout constants (fractions of rendered image)

private let LCD_LEFT:   CGFloat = 0.087
private let LCD_RIGHT:  CGFloat = 0.913
private let LCD_TOP:    CGFloat = 0.096
private let LCD_BOTTOM: CGFloat = 0.906
private let IMG_ASPECT: CGFloat = 1136.0 / 1385.0

// MARK: - Watch face artwork

private enum WatchFaceArtwork: String, CaseIterable {
    case closeup, silver, gold, rose, sapphire, ruby, frost

    var imageName: String {
        switch self {
        case .closeup:  return "poplur_watch_face_closeup"
        case .silver:   return "poplur_watch_face_silver"
        case .gold:     return "poplur_watch_face_gold"
        case .rose:     return "poplur_watch_face_rose"
        case .sapphire: return "poplur_watch_face_sapphire"
        case .ruby:     return "poplur_watch_face_ruby"
        case .frost:    return "poplur_watch_face_frost"
        }
    }

    var accent: Color {
        switch self {
        case .closeup, .silver: return Color(white: 0.92)
        case .gold:     return Color(red: 1.0, green: 0.76, blue: 0.11)
        case .rose:     return Color(red: 1.0, green: 0.56, blue: 0.47)
        case .sapphire: return Color(red: 0.20, green: 0.68, blue: 1.0)
        case .ruby:     return Color(red: 1.0, green: 0.19, blue: 0.19)
        case .frost:    return Color(red: 0.85, green: 0.96, blue: 1.0)
        }
    }
}

// MARK: - Browse arrow

private struct BrowseArrow: View {
    let isLeft: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Canvas { ctx, size in
                var path = Path()
                if isLeft {
                    path.move(to: CGPoint(x: size.width * 0.72, y: size.height * 0.12))
                    path.addLine(to: CGPoint(x: size.width * 0.24, y: size.height * 0.50))
                    path.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.88))
                } else {
                    path.move(to: CGPoint(x: size.width * 0.28, y: size.height * 0.12))
                    path.addLine(to: CGPoint(x: size.width * 0.76, y: size.height * 0.50))
                    path.addLine(to: CGPoint(x: size.width * 0.28, y: size.height * 0.88))
                }
                ctx.stroke(path, with: .color(color.opacity(0.86)), lineWidth: 4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Spinning globe + trend indicator

private struct GlobeTrendView: View {
    let globePhase: Double   // 0–1, longitude rotation
    let trend: RadiusTrend
    let arrowPhase: Double   // 0–1 sinusoidal bounce cycle

    private let green  = Color(red: 0.20, green: 1.00, blue: 0.15)
    private let red    = Color(red: 1.00, green: 0.18, blue: 0.12)
    private let yellow = Color(red: 1.00, green: 0.86, blue: 0.10)

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let cx = w * 0.50
            let globeBottom = h * 0.68
            let r = min(w * 0.42, globeBottom * 0.48)
            let cy = globeBottom - r

            // ── Globe shell ──────────────────────────────────────────────
            let globeColor = GraphicsContext.Shading.color(green.opacity(0.85))
            let dimColor   = GraphicsContext.Shading.color(green.opacity(0.45))
            ctx.stroke(Path(ellipseIn: CGRect(x: cx-r, y: cy-r, width: r*2, height: r*2)),
                       with: globeColor, lineWidth: 1.5)

            // Latitude lines
            for frac in [CGFloat(0.28), 0.50, 0.72] {
                let ly  = (cy - r) + r * 2 * frac
                let sinV = sqrt(max(0, 1 - pow(frac * 2 - 1, 2)))
                let hw  = r * sinV
                let lh  = r * 0.13
                if hw > 1 {
                    ctx.stroke(Path(ellipseIn: CGRect(x: cx-hw, y: ly-lh/2,
                                                      width: hw*2, height: lh)),
                               with: dimColor, lineWidth: 0.8)
                }
            }

            // Rotating longitude ellipse
            let lonAngle = globePhase * .pi * 2
            let lonHW = r * abs(cos(lonAngle))
            if lonHW > 0.5 {
                ctx.stroke(Path(ellipseIn: CGRect(x: cx-lonHW, y: cy-r,
                                                  width: lonHW*2, height: r*2)),
                           with: dimColor, lineWidth: 0.8)
            }

            // ── Continent dot pattern (rotates with longitude) ────────────
            let cosA = cos(lonAngle), sinA = sin(lonAngle)
            let continentDots: [(CGFloat, CGFloat)] = [
                // North America-ish
                (-0.45, -0.40), (-0.55, -0.25), (-0.35, -0.55), (-0.60, -0.10),
                (-0.20, -0.60), (-0.50, -0.50), (-0.30, -0.30),
                // Europe / Africa
                (0.15, -0.55),  (0.25, -0.40),  (0.20, -0.20),  (0.10, -0.05),
                (0.30, -0.60),  (0.12,  0.10),  (0.05,  0.25),
                // Asia
                (0.40, -0.50),  (0.55, -0.35),  (0.50, -0.15),  (0.45,  0.05),
            ]
            for (dx, dz) in continentDots {
                let rotX = dx * cosA               // longitude rotation
                let depthZ = dx * sinA + dz * 0   // depth for culling
                if depthZ > 0.15 { continue }      // back hemisphere → skip
                let sx = cx + rotX * r
                let sy = cy + dz  * r
                let sz = CGFloat(max(0.3, min(1.0, 1.0 - depthZ * 0.5)))
                let ds = 2.0 * sz
                ctx.fill(Path(ellipseIn: CGRect(x: sx-ds/2, y: sy-ds/2, width: ds, height: ds)),
                         with: globeColor)
            }

            // ── Trend arrow / indicator ──────────────────────────────────
            let bounce = CGFloat(sin(arrowPhase * .pi * 2)) * 2.5
            let arrowCY = globeBottom + (h - globeBottom) * 0.35 + bounce
            let arrowW  = w * 0.28
            let arrowH  = (h - globeBottom) * 0.30
            let al = cx - arrowW / 2
            let ar = cx + arrowW / 2

            switch trend {
            case .up:
                let arrowShading = GraphicsContext.Shading.color(green)
                var p = Path()
                p.move(to:    CGPoint(x: cx, y: arrowCY - arrowH))
                p.addLine(to: CGPoint(x: ar, y: arrowCY + arrowH * 0.2))
                p.addLine(to: CGPoint(x: cx + arrowW * 0.18, y: arrowCY + arrowH * 0.2))
                p.addLine(to: CGPoint(x: cx + arrowW * 0.18, y: arrowCY + arrowH))
                p.addLine(to: CGPoint(x: cx - arrowW * 0.18, y: arrowCY + arrowH))
                p.addLine(to: CGPoint(x: cx - arrowW * 0.18, y: arrowCY + arrowH * 0.2))
                p.addLine(to: CGPoint(x: al, y: arrowCY + arrowH * 0.2))
                p.closeSubpath()
                ctx.fill(p, with: arrowShading)

            case .down:
                let arrowShading = GraphicsContext.Shading.color(red)
                var p = Path()
                p.move(to:    CGPoint(x: cx, y: arrowCY + arrowH))
                p.addLine(to: CGPoint(x: ar, y: arrowCY - arrowH * 0.2))
                p.addLine(to: CGPoint(x: cx + arrowW * 0.18, y: arrowCY - arrowH * 0.2))
                p.addLine(to: CGPoint(x: cx + arrowW * 0.18, y: arrowCY - arrowH))
                p.addLine(to: CGPoint(x: cx - arrowW * 0.18, y: arrowCY - arrowH))
                p.addLine(to: CGPoint(x: cx - arrowW * 0.18, y: arrowCY - arrowH * 0.2))
                p.addLine(to: CGPoint(x: al, y: arrowCY - arrowH * 0.2))
                p.closeSubpath()
                ctx.fill(p, with: arrowShading)

            case .stable:
                // Three pulsing dots
                let pulse = CGFloat(0.55 + 0.45 * sin(arrowPhase * .pi * 2))
                let dotShading = GraphicsContext.Shading.color(yellow.opacity(pulse))
                let dotR: CGFloat = 3.5
                for i in [-1, 0, 1] {
                    let dx = cx + CGFloat(i) * dotR * 2.8
                    ctx.fill(Path(ellipseIn: CGRect(x: dx-dotR, y: arrowCY-dotR,
                                                    width: dotR*2, height: dotR*2)),
                             with: dotShading)
                }
            }
        }
    }
}

// MARK: - LCD overlay

private struct LCDOverlay: View {
    @ObservedObject var store: WatchRadiusStore
    let globePhase: Double
    let arrowPhase: Double

    @State private var showKm = true

    private let lcdGreen  = Color(red: 0.22, green: 1.00, blue: 0.15)
    private let lcdOrange = Color(red: 1.00, green: 0.58, blue: 0.04)
    private let lcdBlue   = Color(red: 0.24, green: 0.78, blue: 1.00)
    private let divider   = Color(red: 0.10, green: 0.45, blue: 0.10)

    private let switchTimer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack(alignment: .topLeading) {
                Color.black

                VStack(spacing: 0) {
                    // ── Header ──────────────────────────────────────────
                    header(w: w, h: h * 0.115)

                    // ── Main: globe (left) + data (right) ───────────────
                    HStack(alignment: .top, spacing: 0) {
                        GlobeTrendView(globePhase: globePhase,
                                       trend: store.trend,
                                       arrowPhase: arrowPhase)
                            .frame(width: w * 0.54, height: h * 0.635)

                        dataColumn(w: w * 0.46, h: h * 0.635)
                    }

                    Spacer(minLength: 0)

                    // ── Tab bar ──────────────────────────────────────────
                    Rectangle().fill(divider).frame(height: 0.5)
                    tabBar(w: w, h: h * 0.115)

                    // ── Stats ────────────────────────────────────────────
                    Rectangle().fill(divider).frame(height: 0.5)
                    statsBar(w: w, h: h * 0.105)
                }
            }
        }
        .onReceive(switchTimer) { _ in
            withAnimation(.easeInOut(duration: 0.35)) { showKm.toggle() }
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
        .frame(width: w, height: h)
    }

    // MARK: Data column (world time + radius)

    @ViewBuilder private func dataColumn(w: CGFloat, h: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            // World time
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
            .padding(.trailing, 2)

            Rectangle().fill(divider).frame(height: 0.5)

            // Radius label
            Text("RADIUS")
                .font(.system(size: w * 0.115, weight: .medium, design: .monospaced))
                .foregroundColor(lcdBlue)
                .frame(width: w, alignment: .trailing)
                .padding(.trailing, 2)
                .padding(.top, 2)

            // Main radius number
            Text(showKm ? store.displayValue(metric: true)
                        : store.displayValue(metric: false))
                .font(.system(size: w * 0.360, weight: .bold, design: .monospaced))
                .foregroundColor(lcdGreen)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: w, alignment: .trailing)
                .padding(.trailing, 2)
                .transition(.opacity)

            // Post count
            Text("\(store.postCount)")
                .font(.system(size: w * 0.230, weight: .bold, design: .monospaced))
                .foregroundColor(lcdGreen.opacity(0.75))
                .frame(width: w, alignment: .trailing)
                .padding(.trailing, 2)

            // Earth radius denominator + unit
            Text(showKm ? "/6371" : "/3959")
                .font(.system(size: w * 0.155, weight: .medium, design: .monospaced))
                .foregroundColor(lcdGreen.opacity(0.85))
                .frame(width: w, alignment: .trailing)
                .padding(.trailing, 2)
                .transition(.opacity)

            Text(showKm ? "km" : "mi")
                .font(.system(size: w * 0.120, weight: .regular, design: .monospaced))
                .foregroundColor(lcdGreen.opacity(0.70))
                .frame(width: w, alignment: .trailing)
                .padding(.trailing, 2)
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
            .lineLimit(1).minimumScaleFactor(0.5)
            .frame(width: w)
    }

    // MARK: Stats bar

    @ViewBuilder private func statsBar(w: CGFloat, h: CGFloat) -> some View {
        let battery = store.batteryPercent
        let posts   = store.postCount
        HStack(spacing: 0) {
            statChip("↑\(posts)",    w: w * 0.28)
            statChip("◾84°F",       w: w * 0.27)
            statChip("🔋\(battery)%", w: w * 0.25)
            statChip("♥75",          w: w * 0.20)
        }
        .frame(height: h)
    }

    @ViewBuilder private func statChip(_ label: String, w: CGFloat) -> some View {
        Text(label)
            .font(.system(size: w * 0.220, weight: .regular, design: .monospaced))
            .foregroundColor(lcdGreen.opacity(0.80))
            .lineLimit(1).minimumScaleFactor(0.5)
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
    @AppStorage("watchFaceArtwork") private var faceRaw = WatchFaceArtwork.closeup.rawValue

    private var face: WatchFaceArtwork {
        WatchFaceArtwork(rawValue: faceRaw) ?? .closeup
    }

    var body: some View {
        TimelineView(.animation) { tl in
            let t          = tl.date.timeIntervalSinceReferenceDate
            let globePhase = (t / 8.0).truncatingRemainder(dividingBy: 1.0)
            let arrowPhase = (t / 1.4).truncatingRemainder(dividingBy: 1.0)
            let shinePhase = (t / 4.8).truncatingRemainder(dividingBy: 1.0)

            GeometryReader { proxy in
                let pw = proxy.size.width, ph = proxy.size.height
                let fw = min(pw, ph * IMG_ASPECT)
                let fh = fw / IMG_ASPECT
                let cx = pw / 2, cy = ph / 2

                // LCD rect in screen-space
                let imgLeft = cx - fw / 2
                let imgTop  = cy - fh / 2
                let lcdX = imgLeft + fw * LCD_LEFT
                let lcdY = imgTop  + fh * LCD_TOP
                let lcdW = fw * (LCD_RIGHT  - LCD_LEFT)
                let lcdH = fh * (LCD_BOTTOM - LCD_TOP)

                ZStack {
                    Color.black.ignoresSafeArea()

                    // Bezel image
                    Image(face.imageName)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: fw, height: fh)
                        .position(x: cx, y: cy)

                    // Live LCD overlay
                    LCDOverlay(store: store,
                               globePhase: globePhase,
                               arrowPhase: arrowPhase)
                        .frame(width: lcdW, height: lcdH)
                        .position(x: lcdX + lcdW / 2, y: lcdY + lcdH / 2)
                        .clipped()

                    // Shine sweep
                    Canvas { ctx, size in
                        var sc = ctx
                        sc.blendMode = .plusLighter
                        let sweep = shinePhase * 2.25 - 0.55
                        let sx = size.width * sweep
                        var canvas = Path()
                        canvas.addRect(CGRect(origin: .zero, size: size))
                        sc.fill(canvas, with: .linearGradient(
                            Gradient(stops: [
                                .init(color: .clear,                     location: 0),
                                .init(color: .white.opacity(0),          location: 0.42),
                                .init(color: .white.opacity(0.38),       location: 0.50),
                                .init(color: face.accent.opacity(0.16),  location: 0.58),
                                .init(color: .clear,                     location: 1)
                            ]),
                            startPoint: CGPoint(x: sx - size.width * 0.34, y: size.height * 1.08),
                            endPoint:   CGPoint(x: sx + size.width * 0.34, y: -size.height * 0.08)
                        ))
                    }
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                    // Browse arrows
                    BrowseArrow(isLeft: true, color: face.accent) { browse(-1) }
                        .frame(width: 27, height: 54)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    BrowseArrow(isLeft: false, color: face.accent) { browse(1) }
                        .frame(width: 27, height: 54)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .accessibilityLabel("Poplur watch face")
    }

    private func browse(_ direction: Int) {
        let all = WatchFaceArtwork.allCases
        let current = all.firstIndex(of: face) ?? 0
        faceRaw = all[(current + direction + all.count) % all.count].rawValue
        WKInterfaceDevice.current().play(.click)
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
        if let v = p[key] as? Double    { return v }
        if let v = p[key] as? Int       { return Double(v) }
        if let v = p[key] as? NSNumber  { return v.doubleValue }
        if let v = p[key] as? String    { return Double(v) }
        return nil
    }

    private static func int(_ key: String, _ p: [String: Any]) -> Int? {
        if let v = p[key] as? Int       { return v }
        if let v = p[key] as? Double    { return Int(v) }
        if let v = p[key] as? NSNumber  { return v.intValue }
        if let v = p[key] as? String    { return Int(v) }
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
