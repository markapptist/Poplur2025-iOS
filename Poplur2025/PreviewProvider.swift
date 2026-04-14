//
//  PreviewProvider.swift
//  Poplur2025
//
//  INSTRUCTIONS:
//  1. After creating this file, REMOVE it from the Poplur2025 target
//  2. It should have NO target membership
//  3. It will only be used by Xcode Previews
//

#if DEBUG

import SwiftUI

// This file acts as a preview-only entry point
// It references AppSimulationPreview.swift but is NOT compiled into your app

@available(iOS 17.0, *)
struct PreviewProvider_Wrapper {
    // This wrapper allows previews to work without linking the main app
}

#Preview("App Simulation - Fast Preview") {
    // By keeping this in a separate file with no target membership,
    // Xcode can compile it independently from your main app
    if let previewType = NSClassFromString("LightweightPreviewHarness") {
        // Dynamically load the preview if available
        AnyView(Text("Preview loading..."))
    } else {
        // Fallback simple preview
        NavigationStack {
            ZStack {
                Color.blue.opacity(0.1).ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                    
                    Text("Fast Preview Mode")
                        .font(.title).bold()
                    
                    Text("Lightweight simulation without heavy dependencies")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    HStack(spacing: 15) {
                        ForEach(["map", "camera", "list.bullet", "person"], id: \.self) { icon in
                            VStack {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .frame(width: 60, height: 60)
                                    .background(Color.blue.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
                .padding()
            }
        }
    }
}

#endif
