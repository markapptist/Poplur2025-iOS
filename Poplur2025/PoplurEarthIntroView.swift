import SwiftUI
import WebKit
import SceneKit

// MARK: - Poplur Earth Intro
//
// Shows a Mapbox GL JS globe styled with the Poplur clay palette (clay-green land,
// toy-blue water, near-black space, pink atmospheric rim) spinning slowly.
// Falls back to the SCNSphere + earth_day texture when no Mapbox token is set.

struct PoplurEarthIntroView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let token = AppSecrets.mapboxToken
        if token.isEmpty {
            return makeFallbackView()
        }
        return makeWebGlobeView(token: token)
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    // MARK: - Mapbox WebView globe

    private func makeWebGlobeView(token: String) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = UIColor(red: 5/255, green: 4/255, blue: 7/255, alpha: 1)
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isUserInteractionEnabled = false
        // Base URL is api.mapbox.com so the inline HTML can load Mapbox CDN scripts.
        webView.loadHTMLString(Self.globeHTML(token: token),
                               baseURL: URL(string: "https://api.mapbox.com"))
        return webView
    }

    // MARK: - Globe HTML

    private static func globeHTML(token: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <link href="https://api.mapbox.com/mapbox-gl-js/v3.7.0/mapbox-gl.css" rel="stylesheet">
        <script src="https://api.mapbox.com/mapbox-gl-js/v3.7.0/mapbox-gl.js"></script>
        <style>
          *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
          html, body { width: 100%; height: 100%; overflow: hidden; background: #050407; }
          #map { width: 100%; height: 100%; }
          /* Hide all Mapbox controls and attribution */
          .mapboxgl-ctrl, .mapboxgl-ctrl-attrib-inner,
          .mapboxgl-ctrl-logo { display: none !important; }
        </style>
        </head>
        <body>
        <div id="map"></div>
        <script>
        mapboxgl.accessToken = '\(token)';

        const map = new mapboxgl.Map({
          container: 'map',
          // dark-v11 has predictable layer IDs for clay overrides
          style: 'mapbox://styles/mapbox/dark-v11',
          center: [20, 15],
          zoom: 1.6,
          pitch: 0,
          bearing: 0,
          projection: 'globe',
          interactive: false,
          attributionControl: false,
          logoPosition: 'top-left',
        });

        map.on('load', () => {
          // --- Clay color palette ---
          const LAND     = '#3a7a2a';  // rich clay green
          const LAND_HL  = '#62B548';  // bright clay green highlight
          const WATER    = '#145D73';  // toy blue
          const SPACE    = '#050407';  // near-black space
          const PINK     = '#F63B9A';
          const ROAD_DK  = '#09080A';

          // Background (space)
          try { map.setPaintProperty('background', 'background-color', SPACE); } catch(e) {}

          // Land — dark-v11 uses 'land' as a fill layer
          const landLayers = ['land', 'landcover', 'landcover-crop', 'landcover-grass',
                              'landcover-scrub', 'landcover-snow', 'landcover-wood'];
          landLayers.forEach(id => {
            try { map.setPaintProperty(id, 'fill-color', LAND); } catch(e) {}
          });

          // Country/admin fills where applicable
          const countryFills = ['country-label-sm', 'country-boundaries'];
          countryFills.forEach(id => {
            try { map.setPaintProperty(id, 'fill-color', LAND); } catch(e) {}
          });

          // Parks & national parks → brighter green
          ['national-park', 'landuse', 'landuse-residential', 'park', 'park-label'].forEach(id => {
            try { map.setPaintProperty(id, 'fill-color', LAND_HL); } catch(e) {}
          });

          // Water → toy blue
          try { map.setPaintProperty('water', 'fill-color', WATER); } catch(e) {}
          try { map.setPaintProperty('waterway', 'line-color', WATER); } catch(e) {}
          try { map.setPaintProperty('waterway-shadow', 'line-color', WATER); } catch(e) {}

          // Roads → dark; pink stitches on main roads
          ['road-motorway-trunk', 'road-primary', 'road-secondary-tertiary',
           'road-street', 'road-minor', 'road-path'].forEach(id => {
            try { map.setPaintProperty(id, 'line-color', ROAD_DK); } catch(e) {}
          });
          ['road-motorway-trunk-case', 'road-primary-case'].forEach(id => {
            try { map.setPaintProperty(id, 'line-color', PINK); } catch(e) {}
          });

          // Buildings → very dark
          ['building', 'building-outline'].forEach(id => {
            try {
              map.setPaintProperty(id, 'fill-color', '#111014');
              map.setPaintProperty(id, 'fill-outline-color', '#2A252B');
            } catch(e) {}
          });

          // Admin boundaries → subtle pink
          ['admin-0-boundary', 'admin-1-boundary', 'admin-0-boundary-disputed'].forEach(id => {
            try {
              map.setPaintProperty(id, 'line-color', 'rgba(246,59,154,0.25)');
              map.setPaintProperty(id, 'line-width', 0.6);
            } catch(e) {}
          });

          // --- Globe atmosphere ---
          // Space behind the globe is near-black; pink rim on the atmosphere edge.
          map.setFog({
            'range': [0.5, 10],
            'color': 'rgba(20, 93, 115, 0.08)',    // faint blue haze at horizon
            'high-color': '#050407',
            'horizon-blend': 0.035,
            'space-color': '#050407',
            'star-intensity': 0.25,
          });

          // Directional light to create a clay terminator (lit side vs dark side)
          // Mapbox GL JS v3 light API:
          try {
            map.setLight({
              anchor: 'viewport',
              color: '#FFF2F8',
              intensity: 0.28,
              position: [1.5, 210, 30],
            });
          } catch(e) {}

          // --- Auto-rotation ---
          let bearing = 0;
          function spinGlobe() {
            bearing = (bearing + 0.055) % 360;
            map.setBearing(-bearing);
            requestAnimationFrame(spinGlobe);
          }
          spinGlobe();
        });

        // If the style fails to load (bad token, offline), show a dark fallback
        map.on('error', e => {
          document.getElementById('map').style.background = '#050407';
        });
        </script>
        </body>
        </html>
        """
    }

    // MARK: - SCNSphere fallback (no token)

    private func makeFallbackView() -> SCNView {
        let view = PoplurManagedSCNView(
            performanceName: "EarthIntro3D",
            classification: .heavy
        )
        view.backgroundColor = UIColor(red: 5/255, green: 4/255, blue: 7/255, alpha: 1)
        view.antialiasingMode = .multisampling2X
        view.isUserInteractionEnabled = false
        view.rendersContinuously = PoplurPerformanceManager.shared.decorativeRenderingAllowed
        view.preferredFramesPerSecond = PoplurPerformanceManager.shared.targetFPS

        let scene = SCNScene()
        scene.background.contents = Self.starfieldImage()
        view.scene = scene

        let camera = SCNCamera()
        camera.fieldOfView = 38
        camera.zNear = 0.01
        camera.zFar = 100
        let camNode = SCNNode()
        camNode.camera = camera
        camNode.position = SCNVector3(0, 0, 4.0)
        scene.rootNode.addChildNode(camNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 260
        ambient.light?.color = UIColor(red: 0.55, green: 0.60, blue: 0.85, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.light?.color = UIColor(red: 1.0, green: 0.96, blue: 0.9, alpha: 1)
        key.position = SCNVector3(-3, 2.5, 4)
        key.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(key)

        let pivot = SCNNode()
        pivot.eulerAngles = SCNVector3(0.15, 0, 0.41)
        scene.rootNode.addChildNode(pivot)
        pivot.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 26)))

        let sphere = SCNSphere(radius: 1.15)
        sphere.segmentCount = 96
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = PoplurTextureLoader.image(named: "earth_day")
            ?? UIColor(red: 0.2, green: 0.45, blue: 0.85, alpha: 1)
        m.selfIllumination.contents = PoplurTextureLoader.image(named: "earth_night") ?? UIColor.clear
        m.selfIllumination.intensity = 0.6
        m.roughness.contents = 0.65
        m.metalness.contents = 0.0
        sphere.materials = [m]
        let globeNode = SCNNode(geometry: sphere)
        globeNode.opacity = 0
        pivot.addChildNode(globeNode)
        globeNode.runAction(.fadeIn(duration: 0.6))

        return view
    }

    // MARK: - Procedural starfield (used by fallback)

    static func starfieldImage() -> UIImage {
        let maximum = PoplurPerformanceManager.shared.maximumPreferredTextureResolution
        let width = max(512, maximum)
        let height = max(256, width / 2)
        let key = "EarthIntro:starfield:\(width)x\(height)"
        if let cached: UIImage = PoplurAssetCache.shared.asset(
            forKey: key,
            category: .texture
        ) {
            return cached
        }
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let cg = ctx.cgContext
            let colors = [
                UIColor(red: 0.01, green: 0.01, blue: 0.05, alpha: 1).cgColor,
                UIColor(red: 0.04, green: 0.02, blue: 0.10, alpha: 1).cgColor,
                UIColor(red: 0.01, green: 0.01, blue: 0.04, alpha: 1).cgColor,
            ]
            if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors as CFArray, locations: [0, 0.5, 1]) {
                cg.drawLinearGradient(grad, start: .zero,
                                      end: CGPoint(x: 0, y: size.height), options: [])
            }
            var gen = SystemRandomNumberGenerator()
            for _ in 0..<1400 {
                let x = CGFloat.random(in: 0..<size.width, using: &gen)
                let y = CGFloat.random(in: 0..<size.height, using: &gen)
                let r = CGFloat.random(in: 0.3..<0.9, using: &gen)
                let a = CGFloat.random(in: 0.15..<0.5, using: &gen)
                cg.setFillColor(UIColor(white: 1, alpha: a).cgColor)
                cg.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
            for _ in 0..<260 {
                let x = CGFloat.random(in: 0..<size.width, using: &gen)
                let y = CGFloat.random(in: 0..<size.height, using: &gen)
                let r = CGFloat.random(in: 1.0..<2.6, using: &gen)
                let a = CGFloat.random(in: 0.6..<1.0, using: &gen)
                let tint = [UIColor(white: 1, alpha: a),
                            UIColor(red: 0.7, green: 0.8, blue: 1, alpha: a),
                            UIColor(red: 1, green: 0.85, blue: 0.7, alpha: a)
                ].randomElement(using: &gen)!
                cg.setFillColor(tint.cgColor)
                cg.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
        }
        _ = PoplurAssetCache.shared.insert(
            image,
            forKey: key,
            category: .texture,
            estimatedByteCost: width * height * 4
        )
        return image
    }
}
