import SwiftUI
import AVKit
import AVFoundation
import Foundation
#if canImport(UIKit)
import UIKit
#endif

public struct CapturePreviewOverlay: View {
    public init(image: UIImage?, videoURL: URL?) { self.image = image; self.videoURL = videoURL }
    public let image: UIImage?
    public let videoURL: URL?
    public var body: some View { InlineCapturePreview(image: image, videoURL: videoURL) }
}

private struct InlineCapturePreview: View {
    let image: UIImage?
    let videoURL: URL?

    @State private var player: AVPlayer?
    @State private var playerItem: AVPlayerItem?
    @State private var stabilizedURL: URL?
    @State private var playerReady: Bool = false
    @State private var autoDismissWorkItem: DispatchWorkItem?
    @State private var userInteracted: Bool = false
    @State private var appearedAt: Date = .distantPast

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.95)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    let since = Date().timeIntervalSince(appearedAt)
                    if since < 0.25 {
                        print("[InlinePreview] Ignoring tap dismiss during grace (\(since)s)")
                        return
                    }
                    userInteracted = true
                    autoDismissWorkItem?.cancel()
                    NotificationCenter.default.post(name: Notification.Name("InlinePreviewDismissRequested"), object: nil)
                }
                .onAppear { print("[InlinePreview] appeared. image? \(image != nil), video? \(videoURL != nil)") }
                .onAppear {
                    appearedAt = Date()
                    let work = DispatchWorkItem {
                        if !userInteracted {
                            print("[InlinePreview] Auto-dismissing after timeout")
                            NotificationCenter.default.post(name: Notification.Name("InlinePreviewDismissRequested"), object: nil)
                        }
                    }
                    autoDismissWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
                }
                .onDisappear {
                    autoDismissWorkItem?.cancel()
                }

            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else if let incomingURL = stabilizedURL ?? videoURL {
                // Defer player creation until file exists and has non-zero size. Show a lightweight preparing label meanwhile.
                if let player {
                    VideoPlayer(player: player)
                        .onAppear {
                            print("[InlinePreview] VideoPlayer onAppear (ready=\(playerReady))")
                            if playerReady {
                                player.seek(to: .zero)
                                player.play()
                            }
                        }
                        .onDisappear {
                            player.pause()
                            player.replaceCurrentItem(with: nil)
                            self.player = nil
                            self.playerItem = nil
                            self.playerReady = false
                        }
                        .padding()
                } else {
                    VStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Preparing preview…")
                            .foregroundColor(.white.opacity(0.9))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .onAppear {
                        if self.stabilizedURL == nil { self.stabilizedURL = incomingURL }
                        Task { @MainActor in
                            // Wait a short moment to let file system settle, then verify existence/size with retries.
                            let maxRetries = 5
                            var attempt = 0
                            var finalURL: URL? = self.stabilizedURL
                            while attempt < maxRetries {
                                guard let url = finalURL else { break }
                                let path = url.path
                                let exists = FileManager.default.fileExists(atPath: path)
                                let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.intValue ?? 0
                                print("[InlinePreview] File check attempt #\(attempt + 1): exists=\(exists) size=\(size) path=\(path)")
                                if exists && size > 0 { break }
                                attempt += 1
                                try? await Task.sleep(nanoseconds: 150_000_000)
                            }
                            guard let readyURL = finalURL else {
                                print("[InlinePreview] Missing stabilized URL; cannot init player")
                                return
                            }
                            // Create an AVPlayerItem and observe readiness to avoid black frames
                            let item = AVPlayerItem(url: readyURL)
                            self.playerItem = item
                            let p = AVPlayer(playerItem: item)
                            self.player = p
                            // Observe status changes via periodic time observer fallback
                            // Prefer KVO-like polling here in SwiftUI-friendly way
                            var checks = 0
                            let maxChecks = 20
                            while checks < maxChecks && item.status != .readyToPlay {
                                try? await Task.sleep(nanoseconds: 50_000_000)
                                checks += 1
                            }
                            self.playerReady = (item.status == .readyToPlay)
                            print("[InlinePreview] Player item ready? \(self.playerReady)")
                            if self.playerReady {
                                await p.seek(to: .zero)
                                p.play()
                            }
                        }
                    }
                    .padding()
                }
            } else {
                Text("No media")
                    .foregroundColor(.white)
            }

            VStack {
                Spacer()
                HStack(spacing: 16) {
                    Button {
                        let since = Date().timeIntervalSince(appearedAt)
                        if since < 0.25 {
                            print("[InlinePreview] Ignoring Retake tap during grace (\(since)s)")
                            return
                        }
                        userInteracted = true
                        autoDismissWorkItem?.cancel()
                        NotificationCenter.default.post(name: Notification.Name("InlinePreviewDismissRequested"), object: nil)
                    } label: {
                        Text("Retake")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.black.opacity(0.45), in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        let since = Date().timeIntervalSince(appearedAt)
                        if since < 0.25 {
                            print("[InlinePreview] Ignoring Use tap during grace (\(since)s)")
                            return
                        }
                        userInteracted = true
                        autoDismissWorkItem?.cancel()
                        NotificationCenter.default.post(name: Notification.Name("InlinePreviewUseRequested"), object: nil)
                    } label: {
                        Text("Use")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundColor(.black)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.white, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 72)
            }

            VStack {
                Spacer()
                Text("Tap anywhere to close")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.35), in: Capsule())
                    .padding(.bottom, 24)
            }

            // Dismiss button
            VStack {
                HStack {
                    Button {
                        let since = Date().timeIntervalSince(appearedAt)
                        if since < 0.25 {
                            print("[InlinePreview] Ignoring close tap during grace (\(since)s)")
                            return
                        }
                        // Use Notification to ask parent to hide preview
                        NotificationCenter.default.post(name: Notification.Name("InlinePreviewDismissRequested"), object: nil)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .shadow(radius: 2)
                    }
                    .buttonStyle(.plain)
                    .padding([.top, .leading], 16)
                    Spacer()
                }
                Spacer()
            }
        }
    }
}

