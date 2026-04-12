//
//  PreviewHarness.swift
//  PreviewSupport
//
//  Main preview harness for app simulation
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Camera Controller Shim

fileprivate final class HomeViewCameraControllerShim: NSObject {
    let preview: PreviewCameraKitController

    init(preview: PreviewCameraKitController) {
        self.preview = preview
    }

    var isReady: Bool {
        get { preview.isReady }
        set { preview.isReady = newValue }
    }

    var previewViewController: UIViewController? {
        get { preview.previewViewController }
        set { preview.previewViewController = newValue }
    }
    
    var recordPreviewViewController: UIViewController? {
        get { preview.recordPreviewViewController }
        set { preview.recordPreviewViewController = newValue }
    }

    @MainActor func startPreview() async { 
        await preview.startPreview() 
    }
    
    @MainActor func start() async { 
        await preview.start() 
    }
    
    @MainActor func stop() async { 
        await preview.stop() 
    }
}

// MARK: - Home View Stub

fileprivate struct PreviewHomeViewStub: View {
    @Binding var selectedTab: PreviewAppTab
    let cameraController: HomeViewCameraControllerShim
    
    @State private var triedRealCamera: Bool = false
    @State private var usePlaceholderCamera: Bool = false

    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
            Group {
                switch selectedTab {
                case .feed:
                    PreviewFeedView()
                case .map:
                    PreviewMapView(coordinate: (latitude: 37.7749, longitude: -122.4194))
                case .profile:
                    PreviewProfileView()
                case .record:
                    Group {
                        if usePlaceholderCamera {
                            if let vc = cameraController.preview.previewViewController {
                                UIViewControllerRepresentableWrapper(vc: vc)
                                    .ignoresSafeArea()
                            } else {
                                Text("Camera Preview Unavailable")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ZStack {
                                Color.black.opacity(0.05)
                                ProgressView("Starting Camera…")
                            }
                            .task(id: selectedTab) {
                                await attemptRealCameraWithFallback()
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func attemptRealCameraWithFallback() async {
        guard !triedRealCamera else { return }
        triedRealCamera = true

        await cameraController.preview.startPreview()

        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            if cameraController.preview.isReady {
                return
            }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        usePlaceholderCamera = true
    }
}

// MARK: - Lightweight Preview Harness

public struct LightweightPreviewHarness: View {
    @StateObject private var authViewModel = PreviewAuthViewModel()
    @StateObject private var cameraController = PreviewCameraKitController()
    
    @State private var selectedTab: PreviewAppTab = .feed
    @State private var lastAction: String = ""
    @State private var showBanner: Bool = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                PreviewHomeViewStub(
                    selectedTab: $selectedTab,
                    cameraController: HomeViewCameraControllerShim(preview: cameraController)
                )
                .ignoresSafeArea()
                
                controlPanel
                    .padding()
                    .background(
                        VisualEffectBlur(blurStyle: .systemMaterial)
                            .cornerRadius(16)
                            .shadow(radius: 4)
                    )
                    .padding(.horizontal)
                    .padding(.top, 10)
                
                VStack {
                    if showBanner {
                        Text(lastAction)
                            .font(.subheadline).bold()
                            .padding(8)
                            .background(.ultraThickMaterial)
                            .clipShape(Capsule())
                            .shadow(radius: 3)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            .padding(.top, 60)
                    }
                    Spacer()
                }
                .animation(.easeInOut(duration: 0.25), value: showBanner)
            }
            .onAppear {
                Task { await cameraController.startPreview() }
            }
            .onChange(of: selectedTab) { newValue in
                switch newValue {
                case .map:
                    NotificationCenter.default.post(name: .preview_LoadMapNow, object: nil)
                case .feed:
                    NotificationCenter.default.post(name: .preview_LoadFeedNow, object: nil)
                case .profile:
                    NotificationCenter.default.post(name: .preview_LoadProfileNow, object: nil)
                case .record:
                    break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .preview_FeedReady)) { _ in show("Feed Ready") }
            .onReceive(NotificationCenter.default.publisher(for: .preview_cameraCubeHoldBegan)) { _ in show("Hold Began") }
            .onReceive(NotificationCenter.default.publisher(for: .preview_cameraCubeHoldEnded)) { _ in show("Hold Ended") }
        }
    }
    
    private var controlPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(authViewModel.isAuthenticated ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text("Auth: \(authViewModel.isAuthenticated ? "Signed In" : "Signed Out")  ·  Tab: \(selectedTab.displayName)")
                    .font(.caption).foregroundStyle(.secondary)
                Text("· Framework Preview")
                    .font(.caption).foregroundStyle(.tertiary)
                Spacer()
            }
            
            HStack {
                Toggle(isOn: $authViewModel.isAuthenticated.animation()) {
                    Text("Authenticated")
                        .bold()
                        .font(.caption)
                }
                .onChange(of: authViewModel.isAuthenticated) { auth in
                    show(auth ? "Signed In" : "Signed Out")
                }
                Spacer()
                Button("Feed Ready") {
                    NotificationCenter.default.post(name: .preview_FeedReady, object: nil)
                    show("Feed Ready")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            Picker("Selected Tab", selection: $selectedTab) {
                ForEach(PreviewAppTab.allCases) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedTab) { _ in show("Tab: \(selectedTab.displayName)") }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }
    
    private func show(_ message: String) {
        lastAction = message
        withAnimation { showBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showBanner = false }
        }
    }
}
