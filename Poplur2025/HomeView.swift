//
//  ContentView.swift
//  Poplur2025
//
//  Created by Apptist Inc. on 2025-08-03.
//

import SwiftUI
import SpriteKit
import CoreLocation

struct HomeView: View {
    var body: some View {
        TabView {
            // Map View Tab
            MapView()
                .tabItem {
                    Image(systemName: "map")
                    Text("Map")
                }
            
            // Middle Record/Upload Tab
            RecorderTab()
                .tabItem {
                    Image(systemName: "plus.circle.fill")
                    Text("Record")
                }
            
            // Feed View Tab
            FeedView()
                .tabItem {
                    Image(systemName: "list.dash")
                    Text("Feed")
                }
            
            // Profile View Tab
            ProfileView()
                .tabItem {
                    Image(systemName: "person.circle")
                    Text("Profile")
                }
        }
    }
}

private final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    private let manager = CLLocationManager()
    
    override init() {
        super.init()
        manager.delegate = self
    }
    
    func request() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate = locations.last?.coordinate
        // We can stop after first fix to save battery; restart when needed.
        manager.stopUpdatingLocation()
    }
}

struct RecorderTab: View {
    @StateObject private var locationProvider = LocationProvider()
    @State private var showPicker = false
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("Record or Pick Media")
                .font(.headline)
            Text("Tap the button below to capture a photo/video or pick from library. We’ll tag it with your current location so it appears on your map and feed.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                showPicker = true
            } label: {
                Label("Open Camera / Library", systemImage: "plus.circle.fill")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            locationProvider.request()
        }
        .sheet(isPresented: $showPicker) {
            // Fallback to a default coordinate if not yet available
            let coord = locationProvider.coordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
            MediaPickerView(location: coord)
        }
    }
}

#Preview {
    HomeView()
}
