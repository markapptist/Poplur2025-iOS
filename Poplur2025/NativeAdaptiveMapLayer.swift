import Foundation
import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// Reversible switch for the native-map experiment.
///
/// This is intentionally separate from `PoplurClayWebMap.isEnabled`: the web
/// home remains the shell/HUD while only its Mapbox iframe is replaced. A
/// launch argument always wins so QA can compare both renderers without
/// rebuilding the app.
enum PoplurNativeAdaptiveMap {
    static let defaultsKey = "poplur_native_adaptive_map"

    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-DisableNativeAdaptiveMap") { return false }
        if arguments.contains("-EnableNativeAdaptiveMap") { return true }
        // The shared WebView map is the production path for iPhone and Android.
        // Keep this native MapKit experiment opt-in for QA only; an explicit
        // launch argument above can still enable it for comparison testing.
        return UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? false
    }
}

/// Small command surface used by the web-home bridge. The web HUD remains the
/// visual owner; it asks this object to move the native renderer underneath it.
@MainActor
final class NativeAdaptiveMapController: ObservableObject {
    static let shared = NativeAdaptiveMapController()

    enum DimensionMode: String {
        case adaptive
        case flat2D
        case threeD
    }

    struct CameraCommand: Identifiable {
        enum Action {
            case locateUser
            /// Values above 1 zoom in; values below 1 zoom out.
            case zoom(factor: Double)
            /// Absolute 0...1 HUD position, globe/far to buildings/near.
            case setZoom(progress: Double)
            case focus(
                coordinate: CLLocationCoordinate2D,
                distanceMeters: CLLocationDistance
            )
            case showRadius(
                center: CLLocationCoordinate2D?,
                radiusMeters: CLLocationDistance
            )
            case clearRadius
        }

        let id = UUID()
        let action: Action
    }

    fileprivate struct CameraSnapshot {
        let center: CLLocationCoordinate2D
        let distance: CLLocationDistance
        let heading: CLLocationDirection
        let pitch: CGFloat
    }

    fileprivate struct RadiusState {
        let center: CLLocationCoordinate2D?
        let meters: CLLocationDistance
    }

    @Published private(set) var dimensionMode: DimensionMode = .adaptive
    @Published private(set) var isShowingThreeD = false
    /// A human-readable, ephemeral discovery state for the native map's
    /// lightweight art-direction layer. This deliberately carries no map
    /// tiles, models, particles, or timer-driven animation.
    @Published private(set) var selectedPlaceName: String?
    @Published fileprivate var cameraCommand: CameraCommand?
    fileprivate var cameraSnapshot: CameraSnapshot?
    fileprivate var radiusState: RadiusState?

    func setDimensionMode(_ mode: DimensionMode) {
        dimensionMode = mode
    }

    func locateUser() {
        cameraCommand = CameraCommand(action: .locateUser)
    }

    func zoom(by factor: Double) {
        guard factor.isFinite, factor > 0 else { return }
        cameraCommand = CameraCommand(action: .zoom(factor: factor))
    }

    func setZoom(progress: Double) {
        guard progress.isFinite else { return }
        cameraCommand = CameraCommand(
            action: .setZoom(progress: max(0, min(1, progress)))
        )
    }

    func focus(
        on coordinate: CLLocationCoordinate2D,
        distanceMeters: CLLocationDistance = 4_000
    ) {
        guard CLLocationCoordinate2DIsValid(coordinate),
              distanceMeters.isFinite else { return }
        cameraCommand = CameraCommand(
            action: .focus(
                coordinate: coordinate,
                distanceMeters: max(80, distanceMeters)
            )
        )
    }

    func showRadius(
        meters: CLLocationDistance,
        centeredAt coordinate: CLLocationCoordinate2D? = nil
    ) {
        guard meters.isFinite, meters > 0 else { return }
        if let coordinate, !CLLocationCoordinate2DIsValid(coordinate) { return }
        radiusState = RadiusState(center: coordinate, meters: meters)
        cameraCommand = CameraCommand(
            action: .showRadius(center: coordinate, radiusMeters: meters)
        )
    }

    func clearRadius() {
        radiusState = nil
        cameraCommand = CameraCommand(action: .clearRadius)
    }

    fileprivate func selectPlace(named name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        selectedPlaceName = trimmed.isEmpty ? "New place" : trimmed
    }

    fileprivate func reportThreeDimensional(_ value: Bool) {
        guard isShowingThreeD != value else { return }
        isShowingThreeD = value
    }

    fileprivate func rememberCamera(_ camera: MKMapCamera) {
        cameraSnapshot = CameraSnapshot(
            center: camera.centerCoordinate,
            distance: camera.centerCoordinateDistance,
            heading: camera.heading,
            pitch: camera.pitch
        )
    }

    fileprivate func rememberRadius(
        center: CLLocationCoordinate2D,
        meters: CLLocationDistance
    ) {
        radiusState = RadiusState(center: center, meters: meters)
    }

    fileprivate func consumeCommand(_ id: UUID) {
        guard cameraCommand?.id == id else { return }
        cameraCommand = nil
    }
}

/// The low-power map that sits behind the existing web Home HUD.
///
/// MapKit renders natively and is event-driven while idle. The camera starts
/// as a north-up, flat city map. Buildings are only pitched into view after a
/// close zoom, with hysteresis so small pinch changes do not flap between 2D
/// and 3D. Terrain stays flat in both modes; the close-range pitch supplies the
/// useful building depth without paying for a globe or realistic terrain.
struct NativeAdaptiveMapLayer: View {
    @ObservedObject private var locationProvider = LocationProvider.shared
    @ObservedObject private var mapController = NativeAdaptiveMapController.shared

    var body: some View {
        ZStack {
            NativeAdaptiveMapView(
                userCoordinate: locationProvider.coordinate,
                dimensionMode: mapController.dimensionMode,
                cameraCommand: mapController.cameraCommand,
                mapController: mapController
            )

            // This is intentionally a static SwiftUI overlay. It gives the
            // MapKit base a little of Poplur’s editorial feel without bringing
            // back a WebGL map, animated atmosphere, or a render loop.
            NativeMapArtDirectionOverlay(
                selectedPlaceName: mapController.selectedPlaceName
            )
            .allowsHitTesting(false)
        }
            .ignoresSafeArea()
            .onAppear {
                // Preserve the clay permission-primer ordering. Merely opening
                // the map never raises Apple's location sheet.
                locationProvider.requestIfAlreadyAuthorized()
            }
            .onDisappear {
                // The provider normally stops itself after one adequate fix;
                // leaving Map is also a hard radio-off boundary.
                locationProvider.stop()
            }
    }
}

/// Event-driven visual polish for the native renderer. It is computed when
/// this view is drawn; there is no clock, display link, particle system, or
/// per-frame map update.
private struct NativeMapArtDirectionOverlay: View {
    let selectedPlaceName: String?

    private enum TimePalette {
        case dawn, day, goldenHour, night

        static var current: TimePalette {
            switch Calendar.autoupdatingCurrent.component(.hour, from: .now) {
            case 5..<9: return .dawn
            case 9..<17: return .day
            case 17..<21: return .goldenHour
            default: return .night
            }
        }

        var colors: [Color] {
            switch self {
            case .dawn:
                return [.pink.opacity(0.14), .clear, .indigo.opacity(0.06)]
            case .day:
                return [.cyan.opacity(0.045), .clear, .orange.opacity(0.035)]
            case .goldenHour:
                return [.orange.opacity(0.12), .clear, .pink.opacity(0.065)]
            case .night:
                return [.indigo.opacity(0.18), .clear, .black.opacity(0.09)]
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: TimePalette.current.colors,
                startPoint: .top,
                endPoint: .bottom
            )
            .blendMode(.softLight)

            if let selectedPlaceName {
                Label(selectedPlaceName.uppercased(), systemImage: "seal.fill")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .kerning(0.7)
                    .foregroundStyle(Color(red: 0.56, green: 0.05, blue: 0.30))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.thinMaterial, in: Capsule())
                    .overlay {
                        Capsule().stroke(
                            Color(red: 0.96, green: 0.16, blue: 0.58).opacity(0.42),
                            lineWidth: 1
                        )
                    }
                    .padding(.top, 148)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    .accessibilityLabel("Discovered \(selectedPlaceName)")
            }
        }
    }
}

private struct NativeAdaptiveMapView: UIViewRepresentable {
    let userCoordinate: CLLocationCoordinate2D?
    let dimensionMode: NativeAdaptiveMapController.DimensionMode
    let cameraCommand: NativeAdaptiveMapController.CameraCommand?
    let mapController: NativeAdaptiveMapController

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        context.coordinator.configure(mapView, controller: mapController)
        context.coordinator.updateUserCoordinate(userCoordinate, on: mapView)
        context.coordinator.update(
            dimensionMode: dimensionMode,
            command: cameraCommand,
            on: mapView
        )
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.updateUserCoordinate(userCoordinate, on: mapView)
        context.coordinator.update(
            dimensionMode: dimensionMode,
            command: cameraCommand,
            on: mapView
        )
    }

    static func dismantleUIView(_ mapView: MKMapView, coordinator: Coordinator) {
        coordinator.teardown()
        mapView.delegate = nil
        mapView.removeAnnotations(mapView.annotations)
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        /// Close enough for individual buildings to be useful.
        private let enterThreeDDistance: CLLocationDistance = 2_200
        /// Hysteresis prevents repeated 2D/3D transitions around one distance.
        private let exitThreeDDistance: CLLocationDistance = 3_200
        private let initialDistance: CLLocationDistance = 16_000
        private let minimumDistance: CLLocationDistance = 80
        private let maximumDistance: CLLocationDistance = 2_000_000
        private let closePitch: CGFloat = 52

        /// Used only until an already-authorized location fix arrives.
        private let fallbackCoordinate = CLLocationCoordinate2D(
            latitude: 43.6532,
            longitude: -79.3832
        )

        private var isThreeDimensional = false
        private var isApplyingAdaptiveCamera = false
        private var hasCenteredOnUser = false
        private var latestUserCoordinate: CLLocationCoordinate2D?
        private var userAnnotation: NativeAdaptiveUserAnnotation?
        private var radiusOverlay: MKCircle?
        private var selectionOverlay: MKCircle?
        private var lastCommandID: UUID?
        private var dimensionMode: NativeAdaptiveMapController.DimensionMode = .adaptive
        private weak var mapController: NativeAdaptiveMapController?
        private let geocoder = CLGeocoder()
        private var geocodeTask: Task<Void, Never>?
        private var lastPlaceName = "Toronto"

        func configure(
            _ mapView: MKMapView,
            controller: NativeAdaptiveMapController
        ) {
            mapController = controller
            dimensionMode = controller.dimensionMode
            mapView.delegate = self
            // Light muted cartography provides the cream/grey Poplur base. Pink
            // stays restrained to the user pin, active radius and native tint;
            // the approved web HUD remains the only chrome layer.
            mapView.overrideUserInterfaceStyle = .light
            mapView.backgroundColor = UIColor(
                red: 0.975,
                green: 0.95,
                blue: 0.92,
                alpha: 1
            )
            mapView.tintColor = UIColor(red: 0.96, green: 0.16, blue: 0.58, alpha: 1)

            // Standard vector cartography is substantially cheaper than the
            // linked photorealistic Google Maps 3D SDK and requires no token.
            // Keep elevation flat; close-range camera pitch supplies buildings.
            let configuration = MKStandardMapConfiguration(
                elevationStyle: .flat,
                emphasisStyle: .muted
            )
            configuration.showsTraffic = false
            mapView.preferredConfiguration = configuration
            mapView.showsBuildings = true

            mapView.isPitchEnabled = true
            mapView.isRotateEnabled = true
            mapView.showsCompass = false
            mapView.showsScale = false
            mapView.showsUserLocation = false
            mapView.selectableMapFeatures = []
            mapView.cameraZoomRange = MKMapView.CameraZoomRange(
                minCenterCoordinateDistance: minimumDistance,
                maxCenterCoordinateDistance: maximumDistance
            )

            let tap = UITapGestureRecognizer(
                target: self,
                action: #selector(nativeMapTapped(_:))
            )
            tap.cancelsTouchesInView = false
            mapView.addGestureRecognizer(tap)

            let camera = MKMapCamera()
            if let snapshot = controller.cameraSnapshot {
                camera.centerCoordinate = snapshot.center
                camera.centerCoordinateDistance = snapshot.distance
                camera.heading = snapshot.heading
                camera.pitch = snapshot.pitch
                hasCenteredOnUser = true
                isThreeDimensional = snapshot.pitch > 1
                controller.reportThreeDimensional(isThreeDimensional)
            } else {
                camera.centerCoordinate = fallbackCoordinate
                camera.centerCoordinateDistance = initialDistance
                camera.heading = 0
                camera.pitch = 0
            }
            mapView.setCamera(camera, animated: false)
            applyDimensionMode(to: mapView, animated: false)
            if let radius = controller.radiusState, let center = radius.center {
                installRadius(center: center, meters: radius.meters, on: mapView)
            }
            publishCameraState(from: mapView, geocode: true)
        }

        func teardown() {
            geocodeTask?.cancel()
            geocodeTask = nil
            geocoder.cancelGeocode()
        }

        func update(
            dimensionMode newMode: NativeAdaptiveMapController.DimensionMode,
            command: NativeAdaptiveMapController.CameraCommand?,
            on mapView: MKMapView
        ) {
            if dimensionMode != newMode {
                dimensionMode = newMode
                mapView.isPitchEnabled = newMode != .flat2D
                applyDimensionMode(to: mapView, animated: true)
            }

            guard let command, command.id != lastCommandID else { return }
            lastCommandID = command.id
            apply(command.action, to: mapView)
            // A camera request is an event, not durable view state. Camera and
            // radius snapshots above restore the settled result on remount.
            Task { @MainActor [weak mapController] in
                mapController?.consumeCommand(command.id)
            }
        }

        func updateUserCoordinate(
            _ coordinate: CLLocationCoordinate2D?,
            on mapView: MKMapView
        ) {
            guard let coordinate, CLLocationCoordinate2DIsValid(coordinate) else { return }
            latestUserCoordinate = coordinate

            if let userAnnotation {
                userAnnotation.coordinate = coordinate
            } else {
                let annotation = NativeAdaptiveUserAnnotation(coordinate: coordinate)
                userAnnotation = annotation
                mapView.addAnnotation(annotation)
            }

            // Do not snap back after the user starts browsing. The first fix
            // replaces the harmless Toronto fallback once, then navigation is
            // entirely user-driven.
            guard !hasCenteredOnUser else { return }
            hasCenteredOnUser = true
            let camera = MKMapCamera()
            camera.centerCoordinate = coordinate
            camera.centerCoordinateDistance = initialDistance
            camera.heading = 0
            camera.pitch = 0
            mapView.setCamera(camera, animated: false)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if isApplyingAdaptiveCamera {
                isApplyingAdaptiveCamera = false
                publishCameraState(from: mapView, geocode: true)
                return
            }
            applyDimensionMode(to: mapView, animated: true)
            publishCameraState(from: mapView, geocode: true)
        }

        func mapView(
            _ mapView: MKMapView,
            viewFor annotation: any MKAnnotation
        ) -> MKAnnotationView? {
            guard annotation is NativeAdaptiveUserAnnotation else { return nil }
            let identifier = "PoplurNativeUser"
            let marker = (mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
                as? MKMarkerAnnotationView) ?? MKMarkerAnnotationView(
                    annotation: annotation,
                    reuseIdentifier: identifier
                )
            marker.annotation = annotation
            marker.canShowCallout = false
            marker.markerTintColor = UIColor(red: 0.96, green: 0.16, blue: 0.58, alpha: 1)
            marker.glyphTintColor = .white
            marker.glyphImage = UIImage(systemName: "person.fill")
            marker.displayPriority = .required
            return marker
        }

        func mapView(
            _ mapView: MKMapView,
            rendererFor overlay: any MKOverlay
        ) -> MKOverlayRenderer {
            if overlay === selectionOverlay {
                let renderer = MKCircleRenderer(overlay: overlay)
                renderer.fillColor = UIColor(
                    red: 1,
                    green: 0.27,
                    blue: 0.64,
                    alpha: 0.14
                )
                renderer.strokeColor = UIColor(
                    red: 0.96,
                    green: 0.16,
                    blue: 0.58,
                    alpha: 0.88
                )
                renderer.lineWidth = 2
                return renderer
            }

            guard overlay === radiusOverlay else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKCircleRenderer(overlay: overlay)
            renderer.fillColor = UIColor(
                red: 1,
                green: 0.78,
                blue: 0.88,
                alpha: 0.18
            )
            renderer.strokeColor = UIColor(
                red: 0.96,
                green: 0.16,
                blue: 0.58,
                alpha: 0.82
            )
            renderer.lineWidth = 2
            return renderer
        }

        private func apply(
            _ action: NativeAdaptiveMapController.CameraCommand.Action,
            to mapView: MKMapView
        ) {
            switch action {
            case .locateUser:
                guard let latestUserCoordinate else { return }
                moveCamera(
                    on: mapView,
                    center: latestUserCoordinate,
                    distance: min(mapView.camera.centerCoordinateDistance, initialDistance)
                )

            case .zoom(let factor):
                moveCamera(
                    on: mapView,
                    center: mapView.camera.centerCoordinate,
                    distance: mapView.camera.centerCoordinateDistance / factor
                )

            case .setZoom(let progress):
                moveCamera(
                    on: mapView,
                    center: mapView.camera.centerCoordinate,
                    distance: distance(for: progress),
                    // A range input emits a stream of values. Animating each
                    // one queues camera flights, makes the HUD thumb lag and
                    // unnecessarily keeps the renderer busy. The rail itself
                    // is still immediate; MapKit simply takes each latest
                    // camera position without replaying the earlier ones.
                    animated: false
                )

            case .focus(let coordinate, let distanceMeters):
                moveCamera(on: mapView, center: coordinate, distance: distanceMeters)

            case .showRadius(let center, let radiusMeters):
                let resolvedCenter = center ?? mapView.camera.centerCoordinate
                installRadius(center: resolvedCenter, meters: radiusMeters, on: mapView)
                mapController?.rememberRadius(center: resolvedCenter, meters: radiusMeters)
                moveCamera(
                    on: mapView,
                    center: resolvedCenter,
                    distance: max(240, min(2_000_000, radiusMeters * 3.4))
                )

            case .clearRadius:
                if let radiusOverlay { mapView.removeOverlay(radiusOverlay) }
                radiusOverlay = nil
            }
        }

        private func installRadius(
            center: CLLocationCoordinate2D,
            meters: CLLocationDistance,
            on mapView: MKMapView
        ) {
            if let radiusOverlay { mapView.removeOverlay(radiusOverlay) }
            let circle = MKCircle(center: center, radius: meters)
            radiusOverlay = circle
            mapView.addOverlay(circle, level: .aboveRoads)
        }

        private func installSelection(
            at coordinate: CLLocationCoordinate2D,
            on mapView: MKMapView
        ) {
            if let selectionOverlay { mapView.removeOverlay(selectionOverlay) }
            let circle = MKCircle(center: coordinate, radius: 52)
            selectionOverlay = circle
            mapView.addOverlay(circle, level: .aboveRoads)
        }

        private func moveCamera(
            on mapView: MKMapView,
            center: CLLocationCoordinate2D,
            distance: CLLocationDistance,
            animated: Bool = !UIAccessibility.isReduceMotionEnabled
        ) {
            let camera = mapView.camera.copy() as? MKMapCamera ?? mapView.camera
            camera.centerCoordinate = center
            camera.centerCoordinateDistance = max(minimumDistance, min(maximumDistance, distance))
            mapView.setCamera(camera, animated: animated)
        }

        private func distance(for progress: Double) -> CLLocationDistance {
            let clamped = max(0, min(1, progress))
            // Perceptually even zoom: camera distance spans five orders of
            // magnitude, so the HUD must be logarithmic rather than linear.
            return maximumDistance * pow(minimumDistance / maximumDistance, clamped)
        }

        private func progress(for distance: CLLocationDistance) -> Double {
            let clamped = max(minimumDistance, min(maximumDistance, distance))
            return max(0, min(1,
                log(maximumDistance / clamped) / log(maximumDistance / minimumDistance)
            ))
        }

        private func applyDimensionMode(to mapView: MKMapView, animated: Bool) {
            switch dimensionMode {
            case .flat2D:
                applyThreeDimensional(false, to: mapView, animated: animated)
            case .threeD:
                applyThreeDimensional(true, to: mapView, animated: animated)
            case .adaptive:
                let distance = mapView.camera.centerCoordinateDistance
                if !isThreeDimensional, distance <= enterThreeDDistance {
                    applyThreeDimensional(true, to: mapView, animated: animated)
                } else if isThreeDimensional, distance >= exitThreeDDistance {
                    applyThreeDimensional(false, to: mapView, animated: animated)
                }
            }
        }

        private func applyThreeDimensional(
            _ enabled: Bool,
            to mapView: MKMapView,
            animated: Bool
        ) {
            guard enabled != isThreeDimensional else { return }
            isThreeDimensional = enabled
            mapController?.reportThreeDimensional(enabled)
            isApplyingAdaptiveCamera = true

            let camera = mapView.camera.copy() as? MKMapCamera ?? mapView.camera
            camera.pitch = enabled ? closePitch : 0
            // A north-up reset on the flat transition keeps the cheap overview
            // visually stable; close 3D retains whatever heading the user chose.
            if !enabled { camera.heading = 0 }
            mapView.setCamera(
                camera,
                animated: animated && !UIAccessibility.isReduceMotionEnabled
            )
        }

        @objc private func nativeMapTapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            guard let mapView = recognizer.view as? MKMapView else { return }
            let coordinate = mapView.convert(
                recognizer.location(in: mapView),
                toCoordinateFrom: mapView
            )
            installSelection(at: coordinate, on: mapView)
            mapController?.selectPlace(named: lastPlaceName)
            resolveSelectedPlace(at: coordinate, on: mapView)
            PostLoginHomeWebView.liveWebView?.evaluateJavaScript(
                "window.dispatchEvent(new CustomEvent('poplur-native-map-tap'));"
                + "window.postMessage({type:'poplur-map-touched'},'*');true;",
                completionHandler: nil
            )
        }

        private func resolveSelectedPlace(
            at coordinate: CLLocationCoordinate2D,
            on mapView: MKMapView
        ) {
            geocodeTask?.cancel()
            geocoder.cancelGeocode()
            geocodeTask = Task { @MainActor [weak self, weak mapView] in
                guard let self, let mapView else { return }
                let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                guard let placemarks = try? await self.geocoder.reverseGeocodeLocation(location),
                      !Task.isCancelled,
                      let placemark = placemarks.first else { return }
                let place = placemark.areasOfInterest?.first
                    ?? placemark.subLocality
                    ?? placemark.locality
                    ?? placemark.name
                guard let place, !place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self.lastPlaceName = place
                self.mapController?.selectPlace(named: place)
                self.publishCameraState(from: mapView, geocode: false)
            }
        }

        private func publishCameraState(from mapView: MKMapView, geocode: Bool) {
            let center = mapView.camera.centerCoordinate
            mapController?.rememberCamera(mapView.camera)
            publishWebState(
                mode: isThreeDimensional ? "3d" : "2d",
                zoom: progress(for: mapView.camera.centerCoordinateDistance),
                place: lastPlaceName
            )
            guard geocode else { return }
            geocodeTask?.cancel()
            geocoder.cancelGeocode()
            geocodeTask = Task { @MainActor [weak self, weak mapView] in
                try? await Task.sleep(nanoseconds: 650_000_000)
                guard !Task.isCancelled, let self, let mapView else { return }
                let location = CLLocation(latitude: center.latitude, longitude: center.longitude)
                guard let placemarks = try? await self.geocoder.reverseGeocodeLocation(location),
                      !Task.isCancelled,
                      let placemark = placemarks.first else { return }
                let place = placemark.areasOfInterest?.first
                    ?? placemark.subLocality
                    ?? placemark.locality
                    ?? placemark.name
                guard let place, !place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self.lastPlaceName = place
                self.publishWebState(
                    mode: self.isThreeDimensional ? "3d" : "2d",
                    zoom: self.progress(for: mapView.camera.centerCoordinateDistance),
                    place: place
                )
            }
        }

        private func publishWebState(mode: String, zoom: Double, place: String) {
            let payload: [String: Any] = ["mode": mode, "zoom": zoom, "place": place]
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let json = String(data: data, encoding: .utf8) else { return }
            PostLoginHomeWebView.liveWebView?.evaluateJavaScript(
                "window.dispatchEvent(new CustomEvent('poplur-native-map-state',{detail:\(json)}));true;",
                completionHandler: nil
            )
        }
    }
}

private final class NativeAdaptiveUserAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}
