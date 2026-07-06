//
//  LookAroundContainerView.swift
//  Poplur2025
//
//  Full-screen Apple Look Around presentation with an explicit close button.
//

import SwiftUI
import MapKit

@available(iOS 16.0, *)
struct LookAroundContainerView: View {
    let scene: MKLookAroundScene
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            LookAroundViewControllerRepresentable(scene: scene)
                .ignoresSafeArea()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 16)
            .padding(.leading, 16)
            .accessibilityLabel("Close Street View")
        }
    }
}

@available(iOS 16.0, *)
private struct LookAroundViewControllerRepresentable: UIViewControllerRepresentable {
    let scene: MKLookAroundScene

    func makeUIViewController(context: Context) -> MKLookAroundViewController {
        let controller = MKLookAroundViewController(scene: scene)
        controller.isNavigationEnabled = true
        controller.showsRoadLabels = true
        return controller
    }

    func updateUIViewController(_ uiViewController: MKLookAroundViewController, context: Context) {
        if uiViewController.scene !== scene {
            uiViewController.scene = scene
        }
    }
}
