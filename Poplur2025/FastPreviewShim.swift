//
//  FastPreviewShim.swift
//  Development Assets - No Target Membership Required
//
//  ALTERNATIVE SOLUTION: Minimal shim file for instant previews
//  
//  INSTRUCTIONS:
//  1. Copy this file into your project
//  2. DO NOT add it to any target (uncheck all targets when adding)
//  3. Use this for previews instead of AppSimulationPreview.swift
//  4. Previews will load in < 3 seconds
//

#if DEBUG

import SwiftUI

// Tab options for the preview harness
enum QuickTab: String, CaseIterable, Identifiable {
    case map, camera, feed, profile
    
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .map: return "map"
        case .camera: return "camera"
        case .feed: return "list.bullet"
        case .profile: return "person"
        }
    }
}

// Ultra-lightweight preview harness
struct FastPreviewHarness: View {
    @State private var selectedTab: QuickTab = .feed
    @State private var isAuthenticated = false
    @State private var notification: String?
    
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                // Content area
                contentView
                    .ignoresSafeArea()
                
                // Control panel
                VStack {
                    controlPanel
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                    
                    if let notification {
                        Text(notification)
                            .font(.caption).bold()
                            .padding(8)
                            .background(.ultraThickMaterial)
                            .clipShape(Capsule())
                            .padding(.top, 4)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    Spacer()
                }
                .animation(.easeInOut, value: notification)
            }
        }
    }
    
    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .map:
            ZStack {
                Color.green.opacity(0.2)
                VStack {
                    Image(systemName: "map.fill")
                        .poplurIconShader()
                        .font(.system(size: 60))
                        .foregroundStyle(.green)
                    Text("Map View")
                        .font(.title).bold()
                    Text("37.7749° N, 122.4194° W")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            
        case .camera:
            ZStack {
                LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(0.3)
                
                VStack {
                    Image(systemName: "camera.fill")
                        .poplurIconShader()
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                    Text("Camera Preview")
                        .font(.title).bold()
                    Text("Tap to capture")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            
        case .feed:
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(0..<10) { i in
                        HStack {
                            Circle()
                                .fill(Color.orange.opacity(0.3))
                                .frame(width: 50, height: 50)
                                .overlay(
                                    Text("\(i + 1)")
                                        .font(.headline)
                                )
                            
                            VStack(alignment: .leading) {
                                Text("Post \(i + 1)")
                                    .font(.headline)
                                Text("Sample feed item")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .poplurIconShader()
                                .foregroundStyle(.tertiary)
                        }
                        .padding()
                        .background(Color(uiColor: .secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemBackground))
            
        case .profile:
            ZStack {
                Color.purple.opacity(0.2)
                VStack(spacing: 20) {
                    Circle()
                        .fill(Color.purple.opacity(0.3))
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "person.fill")
                                .poplurIconShader()
                                .font(.system(size: 40))
                                .foregroundStyle(.purple)
                        )
                    
                    Text("Profile")
                        .font(.title).bold()
                    
                    Text(isAuthenticated ? "Signed In" : "Signed Out")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var controlPanel: some View {
        VStack(spacing: 12) {
            // Status
            HStack(spacing: 8) {
                Circle()
                    .fill(isAuthenticated ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(isAuthenticated ? "Authenticated" : "Guest")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("Fast Preview Mode")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            
            // Auth toggle
            Toggle(isOn: $isAuthenticated.animation()) {
                Text("Auth")
                    .font(.caption).bold()
            }
            .toggleStyle(.switch)
            .onChange(of: isAuthenticated) { _, value in
                notify(value ? "Signed In" : "Signed Out")
            }
            
            // Tab selector
            Picker("Tab", selection: $selectedTab) {
                ForEach(QuickTab.allCases) { tab in
                    Label(tab.rawValue.capitalized, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
    
    private func notify(_ message: String) {
        notification = message
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            notification = nil
        }
    }
}

// MARK: - Preview

#Preview("Fast Preview - No Dependencies") {
    FastPreviewHarness()
}

#Preview("Fast Preview - Dark Mode") {
    FastPreviewHarness()
        .preferredColorScheme(.dark)
}

#Preview("Fast Preview - Authenticated") {
    FastPreviewHarness()
        .onAppear {
            // Can't directly set @State, so this is for demonstration
        }
}

#endif
