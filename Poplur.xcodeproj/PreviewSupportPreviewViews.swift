//
//  PreviewViews.swift
//  PreviewSupport
//
//  Reusable preview view components
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Feed View

public struct PreviewFeedView: View {
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.orange.opacity(0.3)
            Text("FeedView")
                .font(.title)
                .bold()
        }
    }
}

// MARK: - Map View

public struct PreviewMapView: View {
    public var coordinate: (latitude: Double, longitude: Double)?
    
    public init(coordinate: (latitude: Double, longitude: Double)? = nil) {
        self.coordinate = coordinate
    }
    
    public var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.green.opacity(0.2)
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.green, lineWidth: 3)
                    .padding(20)
                
                if let coordinate = coordinate {
                    VStack {
                        Text("MapView")
                            .font(.title)
                            .bold()
                            .padding(.bottom, 5)
                        Text("Lat: \(coordinate.latitude, specifier: "%.4f")")
                        Text("Lon: \(coordinate.longitude, specifier: "%.4f")")
                    }
                    .foregroundColor(.green)
                    .background(Color.white.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
                } else {
                    Text("No Coordinate")
                        .foregroundColor(.gray)
                }
            }
        }
    }
}

// MARK: - Profile View

public struct PreviewProfileView: View {
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.purple.opacity(0.3)
            Text("ProfileView")
                .font(.title)
                .bold()
        }
    }
}

// MARK: - Visual Effect Blur

public struct VisualEffectBlur: UIViewRepresentable {
    public var blurStyle: UIBlurEffect.Style
    
    public init(blurStyle: UIBlurEffect.Style) {
        self.blurStyle = blurStyle
    }
    
    public func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
    }
    
    public func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}

// MARK: - UIViewController Wrapper

public struct UIViewControllerRepresentableWrapper: UIViewControllerRepresentable {
    public let vc: UIViewController
    
    public init(vc: UIViewController) {
        self.vc = vc
    }
    
    public func makeUIViewController(context: Context) -> UIViewController {
        vc
    }
    
    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No-op
    }
}
