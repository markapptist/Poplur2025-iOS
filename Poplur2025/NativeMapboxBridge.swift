import UIKit
import WebKit
import SwiftUI
import MapboxMaps

enum PoplurNativeMapbox {
    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return !args.contains("-UseWebGLMap") && !(args.contains("-EnableNativeAdaptiveMap") && !args.contains("-DisableNativeAdaptiveMap"))
    }
}

/// Native map pixels behind the existing map document. This owns no Poplur
/// controls: the production slider, labels, pins and gesture pad stay in HTML.
@MainActor final class NativeMapboxBridge: ObservableObject {
    static let shared = NativeMapboxBridge()
    let container = UIView()
    private var map: MapboxMaps.MapView?
    private weak var webView: WKWebView?
    private var session = ""
    private var cancelables = Set<AnyCancelable>()
    private var tiles: NativeMapTileServer?
    private var commands: [(String, [String: Any])] = []
    private var processing = false
    private var viewport = CGSize(width: 393, height: 852)
    private var lastCameraSend: CFTimeInterval = 0
    private var gestureActive = false
    private var models: [String: [String: Any]] = [:]
    private var pendingModels = Set<String>()
    private var lastCameraSignature = ""

    func detach(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        commands.removeAll(); destroy(); self.webView = nil
    }

    func present(_ active: Bool) { container.isHidden = !active }

    func receive(_ body: [String: Any], webView: WKWebView) {
        guard let session = body["session"] as? String, let incoming = body["commands"] as? [[String: Any]] else { return }
        self.webView = webView
        commands.append(contentsOf: incoming.map { (session, $0) })
        guard !processing else { return }
        processing = true
        Task { @MainActor in
            defer { processing = false }
            while !commands.isEmpty {
                let (owner, command) = commands.removeFirst()
                do { try await apply(command, owner: owner) }
                catch { emit("error", ["message": "\(command["op"] ?? "map"): \(error.localizedDescription)"]) }
            }
        }
    }

    private func create(_ options: [String: Any], owner: String) throws {
        destroy()
        session = owner
        if let token = options["accessToken"] as? String { MapboxOptions.accessToken = token }
        viewport = CGSize(width: number(options["width"], 393), height: number(options["height"], 852))
        let camera = cameraOptions(options["camera"] as? [String: Any] ?? [:])
        let view = MapboxMaps.MapView(frame: container.bounds, mapInitOptions: MapInitOptions(cameraOptions: camera, styleURI: .dark))
        view.mapboxMap.setTileCacheBudget(size:.megabytes(48))
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
        view.ornaments.options.compass.visibility = .hidden
        view.ornaments.options.scaleBar.visibility = .hidden
        // Attribution and the Mapbox wordmark remain the SDK's own ornaments.
        container.addSubview(view); map = view
        tiles = try NativeMapTileServer()
        try view.mapboxMap.setCameraBounds(with: CameraBoundsOptions(maxZoom: number(options["maxZoom"],22), minZoom: number(options["minZoom"],0), maxPitch: 85, minPitch: 0))
        view.mapboxMap.onStyleLoaded.observeNext { [weak self] _ in
            guard let self, self.session == owner else { return }
            try? view.mapboxMap.setProjection(StyleProjection(name: .mercator))
            try? view.mapboxMap.setLights(ambient: AmbientLight(id: "poplur-ambient").intensity(0.55),
                                         directional: DirectionalLight(id: "poplur-sun").intensity(0.75).direction(azimuthal: 210, polar: 45).castShadows(false))
            let style = (try? JSONSerialization.jsonObject(with: Data(view.mapboxMap.styleJSON.utf8))) ?? [:]
            self.emit("load", ["style": style])
            self.emit("styledata")
        }.store(in: &cancelables)
        view.mapboxMap.onCameraChanged.observe { [weak self] _ in self?.publishCamera() }.store(in: &cancelables)
        view.mapboxMap.onMapIdle.observe { [weak self] _ in
            self?.publishCamera(force: true)
            if let self {
                for id in self.pendingModels { self.emit("modelReady", ["id":id]) }
                self.pendingModels.removeAll()
                self.emit("render")
                self.emit("idle")
            }
        }.store(in: &cancelables)
        view.mapboxMap.onMapLoadingError.observe { [weak self] error in
            if let source = error.sourceId { self?.pendingModels.remove(source.replacingOccurrences(of:"native-model-source-",with:"")) }
            self?.emit("error",["message":error.message])
        }.store(in: &cancelables)
        view.mapboxMap.onRenderFrameFinished.observe { [weak self] _ in self?.emit("render") }.store(in: &cancelables)
        view.gestures.onMapTap.observe { [weak self] context in self?.tap(at: context.point, coordinate: context.coordinate) }.store(in: &cancelables)
        let touch = UILongPressGestureRecognizer(target: self, action: #selector(touchChanged(_:)))
        touch.minimumPressDuration = 0; touch.cancelsTouchesInView = false; touch.delegate = NativeMapGestureDelegate.shared
        view.addGestureRecognizer(touch)
    }

    @objc private func touchChanged(_ recognizer: UIGestureRecognizer) {
        gestureActive = recognizer.state == .began || recognizer.state == .changed
        if let map {
            let point = recognizer.location(in:map), coordinate = map.mapboxMap.coordinate(for:point)
            let event = recognizer.state == .began ? "touchstart" : recognizer.state == .changed ? "touchmove" : "touchend"
            emit(event,["gesture":true,"point":[point.x*viewport.width/max(1,map.bounds.width),point.y*viewport.height/max(1,map.bounds.height)],"coordinate":[coordinate.longitude,coordinate.latitude]])
        }
        if recognizer.state == .began {
            webView?.evaluateJavaScript("window.dispatchEvent(new CustomEvent('poplur-native-map-tap'));true;")
        }
    }
    private func publishCamera(force: Bool = false) {
        guard let map else { return }
        let now = CACurrentMediaTime()
        guard force || now-lastCameraSend >= 1/30 else { return }
        lastCameraSend = now
        let camera = map.mapboxMap.cameraState, center = camera.center
        let signature = "\(center.longitude),\(center.latitude),\(camera.zoom),\(camera.pitch),\(camera.bearing),\(map.bounds.size),\(viewport)"
        guard signature != lastCameraSignature else { return }
        lastCameraSignature = signature
        let x = (center.longitude+180)/360
        let y = (1-log(tan(.pi/4+center.latitude * .pi/360)) / .pi)/2
        let span = pow(2, -camera.zoom)*0.2
        let sx = viewport.width / max(1,map.bounds.width), sy = viewport.height / max(1,map.bounds.height)
        let samples: [[String: Any]] = [(-1.0,-1.0),(1,-1),(1,1),(-1,1)].map { dx,dy in
            let wx = x+dx*span, wy = y+dy*span
            let coordinate = CLLocationCoordinate2D(latitude: atan(sinh(.pi*(1-2*wy)))*180 / .pi, longitude: wx*360-180)
            let point = map.mapboxMap.point(for: coordinate)
            return ["world": [wx,wy], "screen": [point.x*sx,point.y*sy]]
        }
        emit("camera", ["camera": ["center": [center.longitude,center.latitude], "zoom": camera.zoom,
                                   "pitch": camera.pitch, "bearing": camera.bearing], "projection": samples, "gesture": gestureActive])
    }
    private func emit(_ event: String, _ fields: [String: Any] = [:]) {
        guard !session.isEmpty, let webView else { return }
        var payload = fields
        payload["type"] = "poplur-native-map-event"; payload["session"] = session; payload["event"] = event
        guard JSONSerialization.isValidJSONObject(payload), let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
        // The renderer lives in the existing map iframe. Route by session, so
        // late native callbacks cannot update a newly opened map document.
        webView.evaluateJavaScript("(()=>{const p=\(json);function send(w){try{w.dispatchEvent(new CustomEvent('poplur-native-map-event',{detail:p}));for(const f of w.document.querySelectorAll('iframe'))send(f.contentWindow)}catch{}}send(window)})();true;")
    }

    private func apply(_ command: [String: Any], owner: String) async throws {
        let op = command["op"] as? String ?? "", args = command["args"] as? [Any] ?? []
        func arg(_ i: Int) -> Any { args.indices.contains(i) ? args[i] : NSNull() }
        func text(_ i: Int) -> String { arg(i) as? String ?? "" }
        func object(_ i: Int) -> [String: Any] { arg(i) as? [String: Any] ?? [:] }
        if op == "create" { try create(object(0), owner: owner); return }
        guard owner == session, let view = map else { return }
        guard let style = view.mapboxMap else { return }
        switch op {
        case "destroy": destroy()
        case "resize": viewport = CGSize(width: number(object(0)["width"],393),height:number(object(0)["height"],852)); publishCamera(force: true)
        case "stop": view.camera.cancelAnimations()
        case "camera":
            let options = object(1), camera = cameraOptions(options)
            if text(0) == "jump" || number(options["duration"],300) == 0 { view.camera.cancelAnimations(); style.setCamera(to: camera) }
            else if text(0) == "fly" { view.camera.fly(to: camera, duration: number(options["duration"],1200)/1000) }
            else { view.camera.ease(to: camera, duration: number(options["duration"],300)/1000, curve: .easeInOut) }
        case "fitBounds":
            let points = (arg(0) as? [[Double]] ?? []).compactMap(coordinate)
            let options = object(1)
            let camera = try style.camera(for: points, camera: cameraOptions(options), coordinatesPadding: padding(options["padding"]), maxZoom: (options["maxZoom"] as? NSNumber)?.doubleValue, offset: nil)
            view.camera.ease(to: camera, duration: number(options["duration"],600)/1000)
        case "bounds":
            let value = object(0)
            try style.setCameraBounds(with: CameraBoundsOptions(maxZoom: cg(value["maxZoom"]), minZoom: cg(value["minZoom"]), maxPitch: cg(value["maxPitch"]), minPitch: cg(value["minPitch"])))
        case "gesture":
            let enabled = arg(1) as? Bool ?? false
            switch text(0) {
            case "dragPan": view.gestures.options.panEnabled = enabled
            case "rotation", "dragRotate": view.gestures.options.rotateEnabled = enabled
            case "touchPitch": view.gestures.options.pitchEnabled = enabled
            case "touchZoomRotate": view.gestures.options.pinchEnabled = enabled
            case "doubleClickZoom": view.gestures.options.doubleTapToZoomInEnabled = enabled
            default: break // mouse/keyboard-only gestures have no native touch equivalent
            }
        case "addSource":
            var properties = object(1)
            if let raw = properties["url"] as? String, let url = URL(string: raw), url.pathExtension == "pmtiles", let tiles {
                properties.removeValue(forKey: "url"); properties["tiles"] = [try await tiles.tiles(for: url)]
                properties["maxzoom"] = 14
            }
            guard owner == session else { return }
            try style.addSource(withId: text(0), properties: properties)
        case "sourceData": try style.setSourceProperty(for: text(0), property: "data", value: arg(1))
        case "removeSource": if style.sourceExists(withId: text(0)) { try style.removeSource(withId: text(0)) }
        case "addLayer":
            var properties = object(0)
            // Classic native styles do not use Standard's slot graph.
            properties.removeValue(forKey: "slot")
            if var paint = properties["paint"] as? [String: Any] { paint.removeValue(forKey: "background-pitch-alignment"); properties["paint"] = paint }
            try style.addLayer(with: properties, layerPosition: text(1).isEmpty ? nil : .below(text(1)))
        case "removeLayer": if style.layerExists(withId: text(0)) { try style.removeLayer(withId: text(0)) }
        case "moveLayer": try style.moveLayer(withId: text(0), to: text(1).isEmpty ? .above(style.allLayerIdentifiers.last?.id ?? "") : .below(text(1)))
        case "paint", "layout":
            if text(1) != "background-pitch-alignment" { try style.setLayerProperty(for: text(0), property: text(1), value: arg(2)) }
        case "filter": try style.setLayerProperty(for: text(0), property: "filter", value: arg(1))
        case "image":
            if let encoded = text(1).split(separator: ",").last, let data = Data(base64Encoded: String(encoded)), let image = UIImage(data: data) { try style.addImage(image,id:text(0),sdf:object(2)["sdf"] as? Bool ?? false) }
        case "featureState":
            let target = object(0)
            style.setFeatureState(sourceId: target["source"] as? String ?? "",sourceLayerId: target["sourceLayer"] as? String,featureId: "\(target["id"] ?? "")",state:object(1)) { _ in }
        case "removeFeatureState":
            let target = object(0)
            style.removeFeatureState(sourceId: target["source"] as? String ?? "",sourceLayerId: target["sourceLayer"] as? String,featureId: "\(target["id"] ?? "")",stateKey:arg(1) as? String) { _ in }
        case "fog":
            // A null web fog removes atmosphere. Converting it to an empty
            // object enables Mapbox's default white haze over the clay paints.
            if arg(0) is NSNull { try style.removeAtmosphere() }
            else { try style.setAtmosphere(properties: object(0)) }
        case "config": if style.styleImports.contains(where: { $0.id == text(0) }) { try style.setStyleImportConfigProperty(for:text(0),config:text(1),value:arg(2)) }
        case "repaint": style.triggerRepaint()
        case "fov": break // Ground pins use the SDK's exact projection samples.
        case "query": query(key:text(0),kind:text(1),geometry:arg(2),options:object(3))
        case "model": try addModel(object(0))
        case "modelPose":
            if var model = models[text(0)], let coordinates = arg(1) as? [Double], let asset = model["asset"] as? String,
               let url = Bundle.main.resourceURL?.appendingPathComponent("ClayMapWeb").appendingPathComponent(asset) {
                model["coords"] = coordinates; models[text(0)] = model
                try style.setSourceProperty(for:"native-model-source-\(text(0))",property:"models",value:[text(0):["uri":url.absoluteString,"position":coordinates]])
                try style.setLayerProperty(for:"native-model-\(text(0))",property:"model-rotation",value:[0,0,number(arg(2))])
            }
        case "modelVisibility": try style.setLayerProperty(for: "native-model-\(text(0))", property: "visibility", value: (arg(1) as? Bool ?? false) ? "visible" : "none")
        case "removeModel":
            if style.layerExists(withId:"native-model-\(text(0))") { try style.removeLayer(withId:"native-model-\(text(0))") }
            if style.sourceExists(withId:"native-model-source-\(text(0))") { try style.removeSource(withId:"native-model-source-\(text(0))") }
            models.removeValue(forKey:text(0)); pendingModels.remove(text(0))
        default: throw NSError(domain:"Poplur.NativeMap",code:1,userInfo:[NSLocalizedDescriptionKey:"Unsupported map command \(op)"])
        }
    }

    private func addModel(_ values: [String: Any]) throws {
        guard let map, let id = values["id"] as? String, let position = values["coords"] as? [Double], let asset = values["asset"] as? String,
              !asset.contains(".."), let url = Bundle.main.resourceURL?.appendingPathComponent("ClayMapWeb").appendingPathComponent(asset), FileManager.default.fileExists(atPath: url.path) else { throw URLError(.fileDoesNotExist) }
        let sourceID = "native-model-source-\(id)", layerID = "native-model-\(id)", height = number(values["heightM"],1)
        var source = ModelSource(id:sourceID)
        source.models = [Model(id:id,uri:url,position:position)]
        try map.mapboxMap.addSource(source)
        var layer = ModelLayer(id:layerID,source:sourceID)
        layer.modelScale = .constant([height,height,height])
        layer.modelRotation = .constant([0,0,number(values["yaw"],0)])
        layer.visibility = .constant((values["visible"] as? Bool ?? false) ? .visible : .none)
        try map.mapboxMap.addLayer(layer)
        models[id] = values
        pendingModels.insert(id)
    }
    private func expression(_ value: Any?) -> Exp? {
        guard let value, let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else { return nil }
        return try? JSONDecoder().decode(Exp.self, from: data)
    }
    private func query(key: String, kind: String, geometry: Any, options: [String: Any]) {
        guard let map else { return }
        let owner = session
        if kind == "source", let source = geometry as? String {
            map.mapboxMap.querySourceFeatures(for:source,options:SourceQueryOptions(sourceLayerIds:(options["sourceLayer"] as? String).map { [$0] },filter:options["filter"] ?? true)) { [weak self] result in
                guard let self, self.session == owner else { return }
                let features = (try? result.get())?.compactMap { self.feature($0.queriedFeature) } ?? []
                self.emit("query",["query":key,"features":features])
            }
        } else {
            let rect = queryRect(geometry)
            map.mapboxMap.queryRenderedFeatures(with:rect,options:RenderedQueryOptions(layerIds:options["layers"] as? [String],filter:expression(options["filter"]))) { [weak self] result in
                guard let self, self.session == owner else { return }
                let features = (try? result.get())?.compactMap { item -> [String: Any]? in
                    guard var value = self.feature(item.queriedFeature) else { return nil }
                    value["layer"] = ["id":item.layers.first ?? ""]; return value
                } ?? []
                self.emit("query",["query":key,"features":features])
            }
        }
    }
    private func tap(at point: CGPoint, coordinate: CLLocationCoordinate2D) {
        guard let map else { return }
        let owner = session
        map.mapboxMap.queryRenderedFeatures(with:point,options:nil) { [weak self] result in
            guard let self, self.session == owner else { return }
            let features = (try? result.get())?.compactMap { item -> [String: Any]? in
                guard var value = self.feature(item.queriedFeature) else { return nil }
                value["layer"] = ["id":item.layers.first ?? ""]; return value
            } ?? []
            self.emit("click",["point":[point.x*self.viewport.width/max(1,map.bounds.width),point.y*self.viewport.height/max(1,map.bounds.height)],
                               "coordinate":[coordinate.longitude,coordinate.latitude],"features":features,"gesture":true])
        }
    }
    private func feature(_ item: QueriedFeature) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(item.feature), var result = try? JSONSerialization.jsonObject(with:data) as? [String: Any] else { return nil }
        result["source"] = item.source; result["sourceLayer"] = item.sourceLayer
        return result
    }
    private func queryRect(_ geometry: Any) -> CGRect {
        guard let map else { return .zero }
        let sx = map.bounds.width/max(1,viewport.width), sy = map.bounds.height/max(1,viewport.height)
        if let points = geometry as? [[Double]], points.count == 2 { return CGRect(x:points[0][0]*sx,y:points[0][1]*sy,width:(points[1][0]-points[0][0])*sx,height:(points[1][1]-points[0][1])*sy) }
        let point: [Double]?
        if let value = geometry as? [Double] { point = value }
        else if let value = geometry as? [String: Double], let x = value["x"], let y = value["y"] { point = [x,y] }
        else { point = nil }
        if let point, point.count == 2 { return CGRect(x:point[0]*sx,y:point[1]*sy,width:1,height:1) }
        return map.bounds
    }
    private func coordinate(_ values: [Double]) -> CLLocationCoordinate2D? { values.count == 2 ? CLLocationCoordinate2D(latitude:values[1],longitude:values[0]) : nil }
    private func number(_ value: Any?, _ fallback: Double = 0) -> Double { (value as? NSNumber)?.doubleValue ?? fallback }
    private func cg(_ value: Any?) -> CGFloat? { (value as? NSNumber).map { CGFloat($0.doubleValue) } }
    private func padding(_ value: Any?) -> UIEdgeInsets? {
        if let scalar = value as? Double { return UIEdgeInsets(top:scalar,left:scalar,bottom:scalar,right:scalar) }
        guard let edges = value as? [String: Any] else { return nil }
        return UIEdgeInsets(top:number(edges["top"]),left:number(edges["left"]),bottom:number(edges["bottom"]),right:number(edges["right"]))
    }
    private func cameraOptions(_ value: [String: Any]) -> CameraOptions {
        var camera = CameraOptions(center:(value["center"] as? [Double]).flatMap(coordinate),padding:padding(value["padding"]),zoom:cg(value["zoom"]),bearing:value["bearing"] as? Double,pitch:cg(value["pitch"]))
        // The shared HUD sends CSS pixels. On a scaled tablet surface those
        // differ from native points, just as they do for projection samples.
        if let edges = camera.padding, let map {
            let sx = map.bounds.width / max(1, viewport.width)
            let sy = map.bounds.height / max(1, viewport.height)
            camera.padding = UIEdgeInsets(top: edges.top * sy, left: edges.left * sx,
                                          bottom: edges.bottom * sy, right: edges.right * sx)
        }
        if let offset = value["offset"] as? [Double], offset.count == 2, let map {
            camera.anchor = CGPoint(x:map.bounds.midX+offset[0]*map.bounds.width/max(1,viewport.width),y:map.bounds.midY+offset[1]*map.bounds.height/max(1,viewport.height))
        }
        return camera
    }
    func destroy() {
        cancelables.removeAll(); map?.camera.cancelAnimations(); map?.removeFromSuperview(); map = nil
        tiles?.close(); tiles = nil; models.removeAll(); pendingModels.removeAll(); lastCameraSignature = ""; session = ""; gestureActive = false
    }
}

private final class NativeMapGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = NativeMapGestureDelegate()
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
}
struct NativeMapboxSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { NativeMapboxBridge.shared.container }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
