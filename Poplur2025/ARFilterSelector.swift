//
//  ARFilterSelector.swift
//  AR Filter Selection UI
//

import SwiftUI

/// Snapchat-style horizontal filter selector that appears above the cube
struct ARFilterSelectorHorizontal: View {
    @ObservedObject var filterManager: ARFilterManager
    @ObservedObject var cameraController: CameraKitController
    @Binding var isPresented: Bool
    
    @State private var selectedFilter: ARFilterManager.ARFilter = .none
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter scroll view with live preview
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 20) {
                    ForEach(filterManager.availableFilters) { filter in
                        FilterButtonSnapchat(
                            filter: filter,
                            isSelected: selectedFilter == filter
                        ) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedFilter = filter
                                filterManager.activeFilter = filter
                                
                                // Apply filter to camera preview in real-time
                                applyFilterToCamera(filter)
                                
                                // Haptic feedback
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                
                                print("🎨 Applied filter: \(filter.rawValue)")
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .frame(height: 100)
            .background(
                Color.black.opacity(0.2)
                    .blur(radius: 20)
            )
            
            // Close hint (subtle X button in top-right)
            HStack {
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isPresented = false
                        // Reset filter when closing
                        filterManager.activeFilter = .none
                        applyFilterToCamera(.none)
                        // Clear the AR filters flag so camera can capture again
                        UserDefaults.standard.set(false, forKey: "ARFiltersShown")
                        // Notify CameraPreviewVC to re-enable gestures
                        NotificationCenter.default.post(
                            name: Notification.Name("ARFiltersStateChanged"),
                            object: nil,
                            userInfo: ["isShown": false]
                        )
                    }
                } label: {
                    Image(systemName: "xmark")
                        .poplurIconShader()
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 28, height: 28)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Circle())
                }
                .padding(.trailing, 20)
                .padding(.top, -8)
            }
        }
        .onAppear {
            selectedFilter = filterManager.activeFilter
        }
        .onDisappear {
            // Reset filter when selector disappears
            filterManager.activeFilter = .none
            applyFilterToCamera(.none)
            // Clear the AR filters flag so camera can capture again
            UserDefaults.standard.set(false, forKey: "ARFiltersShown")
            // Notify CameraPreviewVC to re-enable gestures
            NotificationCenter.default.post(
                name: Notification.Name("ARFiltersStateChanged"),
                object: nil,
                userInfo: ["isShown": false]
            )
        }
    }
    
    private func applyFilterToCamera(_ filter: ARFilterManager.ARFilter) {
        // Notify camera controller to apply the selected filter
        NotificationCenter.default.post(
            name: Notification.Name("ARFilterChanged"),
            object: nil,
            userInfo: ["filter": filter.rawValue]
        )
    }
}

// MARK: - Snapchat-Style Filter Button

private struct FilterButtonSnapchat: View {
    let filter: ARFilterManager.ARFilter
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                // Circle with icon (Snapchat style)
                ZStack {
                    // Outer ring when selected
                    if isSelected {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 2.5)
                            .frame(width: 66, height: 66)
                    }
                    
                    Image(filter.thumbnailAsset)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: isSelected ? .white.opacity(0.5) : .clear, radius: 8)
                }
                
                // Filter name — displayName, not rawValue: the raw value is the
                // wire id and still says "Sharpen" for the visor.
                Text(filter.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Legacy Filter Selector (bottom sheet style - kept for compatibility)

/// Filter selector that appears on long press
struct ARFilterSelector: View {
    @ObservedObject var filterManager: ARFilterManager
    @Binding var isPresented: Bool
    
    @State private var selectedFilter: ARFilterManager.ARFilter = .none
    
    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("AR Filters")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button {
                    withAnimation {
                        isPresented = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .poplurIconShader()
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
            .padding()
            .background(Color.black.opacity(0.3))
            
            // Filter scroll view
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(filterManager.availableFilters) { filter in
                        FilterButton(
                            filter: filter,
                            isSelected: selectedFilter == filter
                        ) {
                            withAnimation {
                                selectedFilter = filter
                                filterManager.activeFilter = filter
                                
                                // Haptic feedback
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 0)
            )
            
            // Description
            if selectedFilter != .none {
                Text(selectedFilter.description)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.4))
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            selectedFilter = filterManager.activeFilter
        }
    }
}

// MARK: - Filter Button

private struct FilterButton: View {
    let filter: ARFilterManager.ARFilter
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Image(filter.thumbnailAsset)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.25), lineWidth: 2)
                        )
                }
                
                Text(filter.displayName)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Preview

#if DEBUG
struct ARFilterSelector_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                Spacer()
                
                ARFilterSelectorHorizontal(
                    filterManager: ARFilterManager(),
                    cameraController: CameraKitController(),
                    isPresented: .constant(true)
                )
                .padding(.bottom, 280)
            }
        }
    }
}
#endif
