//
//  StreetViewButton.swift
//  Poplur2025
//
//  Floating "Street View" control for the map. Backed by Apple MapKit Look Around —
//  never Mapbox or Mapillary, which are Android-only.
//

import SwiftUI
import MapKit

struct StreetViewButton: View {
    @ObservedObject var viewModel: MapStreetViewViewModel
    var selectedCoordinate: CLLocationCoordinate2D?
    var mapCenterCoordinate: CLLocationCoordinate2D?

    @State private var isPresentingViewer = false
    @State private var presentedScene: MKLookAroundScene?
    @State private var alertMessage: String?

    var body: some View {
        Button {
            viewModel.checkStreetView(selectedCoordinate: selectedCoordinate, mapCenter: mapCenterCoordinate)
        } label: {
            HStack(spacing: 8) {
                if viewModel.state.isChecking {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "binoculars.fill")
                }
                Text(viewModel.state.buttonLabel)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .foregroundStyle(.white)
        }
        .disabled(viewModel.state.isChecking)
        .accessibilityLabel("Street View")
        .onChange(of: viewModel.state) { _, newState in
            switch newState {
            case .available(let scene):
                presentedScene = scene
                isPresentingViewer = true
            case .unavailable:
                alertMessage = "Street View is not available near this location."
            case .noCoordinateSelected:
                alertMessage = "Select a location on the map to check Street View."
            case .unsupported:
                alertMessage = "Street View requires iOS 16 or later."
            case .error(let message):
                alertMessage = message
            case .idle, .checking:
                break
            }
        }
        .fullScreenCover(isPresented: $isPresentingViewer, onDismiss: { viewModel.reset() }) {
            if let presentedScene {
                LookAroundContainerView(scene: presentedScene) {
                    isPresentingViewer = false
                }
            }
        }
        // Poplur's own alert, never the system one — see PoplurAlert.swift.
        // The `presenting:` overload consumes the optional directly, which
        // retires the hand-rolled Binding shim this site used to need and the
        // `?? ""` fallback that came with it. The card is raised in a
        // window-level cover, so it clears the map underneath it.
        //
        // The alert clears `alertMessage` itself as part of the tap, so the
        // button only has to put the view model back to idle.
        .poplurAlert(
            "Street View",
            presenting: $alertMessage,
            icon: .symbol("binoculars.fill"),
            message: { $0 },
            buttons: { _ in [.cancel("OK") { viewModel.reset() }] }
        )
    }
}
