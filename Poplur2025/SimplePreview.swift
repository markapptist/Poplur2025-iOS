//
//  SimplePreview.swift
//  Poplur2025
//
//  Minimal preview file that should load instantly
//  NO app dependencies - pure SwiftUI only
//

#if DEBUG

import SwiftUI

// MARK: - Ultra-Lightweight Previews

#Preview("Feed") {
    SimpleFeedView()
}

#Preview("Map") {
    SimpleMapView()
}

#Preview("Profile") {
    SimpleProfileView()
}

#Preview("Camera") {
    SimpleCameraView()
}

// MARK: - Simple Views

struct SimpleFeedView: View {
    var body: some View {
        ZStack {
            Color.orange.opacity(0.3)
            VStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle.angled")
                    .poplurIconShader()
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                Text("Feed View")
                    .font(.title)
                    .bold()
                Text("Your content feed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .ignoresSafeArea()
    }
}

struct SimpleMapView: View {
    var body: some View {
        ZStack {
            Color.green.opacity(0.2)
            VStack(spacing: 12) {
                Image(systemName: "map")
                    .poplurIconShader()
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                Text("Map View")
                    .font(.title)
                    .bold()
                Text("37.7749° N, 122.4194° W")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .ignoresSafeArea()
    }
}

struct SimpleProfileView: View {
    var body: some View {
        ZStack {
            Color.purple.opacity(0.3)
            VStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .poplurIconShader()
                    .font(.system(size: 60))
                    .foregroundStyle(.purple)
                Text("Profile View")
                    .font(.title)
                    .bold()
                Text("User profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .ignoresSafeArea()
    }
}

struct SimpleCameraView: View {
    var body: some View {
        ZStack {
            Color.indigo.opacity(0.2)
            VStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .poplurIconShader()
                    .font(.system(size: 60))
                    .foregroundStyle(.indigo)
                Text("Camera View")
                    .font(.title)
                    .bold()
                Text("Tap to capture")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .ignoresSafeArea()
    }
}

#endif // DEBUG
