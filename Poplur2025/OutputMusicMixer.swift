import AVFoundation
import UIKit

// Mixes an audio track into a video, or bakes a still image + audio into a video file.
// Used after AI generation to add music to the output before upload.
enum OutputMusicMixer {

    /// Mix audio from `audioURL` into `videoURL`.
    /// If `audioURL` points to a video file, its audio track is extracted automatically.
    /// Trims to `trimSeconds` when provided.
    static func mixAudio(_ audioURL: URL, intoVideo videoURL: URL, trimSeconds: Double? = nil) async -> URL? {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        guard let videoTrack  = try? await videoAsset.loadTracks(withMediaType: .video).first,
              let audioTrack  = try? await audioAsset.loadTracks(withMediaType: .audio).first,
              let videoDur    = try? await videoAsset.load(.duration)
        else { return nil }

        let finalDuration: CMTime = {
            if let t = trimSeconds, t > 0 {
                return CMTime(seconds: min(t, CMTimeGetSeconds(videoDur)), preferredTimescale: 600)
            }
            return videoDur
        }()

        let composition = AVMutableComposition()
        guard
            let compVideo = composition.addMutableTrack(withMediaType: .video,  preferredTrackID: kCMPersistentTrackID_Invalid),
            let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }

        let videoRange = CMTimeRange(start: .zero, duration: finalDuration)
        guard (try? compVideo.insertTimeRange(videoRange, of: videoTrack, at: .zero)) != nil else { return nil }

        let audioDur  = (try? await audioAsset.load(.duration)) ?? finalDuration
        let audioRange = CMTimeRange(start: .zero, duration: min(audioDur, finalDuration))
        try? compAudio.insertTimeRange(audioRange, of: audioTrack, at: .zero)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("poplur-mixed-\(UUID().uuidString).mp4")

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else { return nil }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        return await withCheckedContinuation { cont in
            session.exportAsynchronously {
                if session.status == .completed {
                    cont.resume(returning: outputURL)
                } else {
                    try? FileManager.default.removeItem(at: outputURL)
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Bake a still image into a short video and add an audio track.
    /// Used when the AI output is an image and the user adds music (result posted as video).
    static func imageWithAudio(
        _ image: UIImage,
        audioURL: URL,
        duration: Double = 10.0,
        filter: PostCaptureFilter = .original
    ) async -> URL? {
        let size = largestSize(image.size)

        // Apply filter once up front
        let filteredImage = filter != .original ? image.applyingFilter(filter) : image
        guard let cgImage = filteredImage.cgImage else { return nil }

        let silentURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("poplur-silent-\(UUID().uuidString).mp4")

        guard let writer = try? AVAssetWriter(outputURL: silentURL, fileType: .mp4) else { return nil }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: nil)

        guard writer.canAdd(videoInput) else { return nil }
        writer.add(videoInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let fps: Int32 = 30
        let frameCount = Int(duration * Double(fps))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        for i in 0..<frameCount {
            while !videoInput.isReadyForMoreMediaData {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            var pb: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height),
                                kCVPixelFormatType_32ARGB, nil, &pb)
            if let pb {
                CVPixelBufferLockBaseAddress(pb, [])
                if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb),
                                       width: Int(size.width), height: Int(size.height),
                                       bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                       space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) {
                    ctx.draw(cgImage, in: CGRect(origin: .zero, size: size))
                }
                CVPixelBufferUnlockBaseAddress(pb, [])
                adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
            }
        }
        videoInput.markAsFinished()

        return await withCheckedContinuation { cont in
            writer.finishWriting {
                guard writer.status == .completed else {
                    try? FileManager.default.removeItem(at: silentURL)
                    cont.resume(returning: nil)
                    return
                }
                Task {
                    let mixed = await OutputMusicMixer.mixAudio(audioURL, intoVideo: silentURL, trimSeconds: nil)
                    try? FileManager.default.removeItem(at: silentURL)
                    cont.resume(returning: mixed)
                }
            }
        }
    }

    // Cap output at 1080p to avoid huge files.
    private static func largestSize(_ size: CGSize) -> CGSize {
        let maxDim: CGFloat = 1080
        let scale = min(maxDim / max(size.width, size.height), 1)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}

private extension UIImage {
    func applyingFilter(_ filter: PostCaptureFilter) -> UIImage {
        guard let cg = cgImage else { return self }
        let ci = filter.apply(to: CIImage(cgImage: cg))
        let ctx = CIContext()
        guard let out = ctx.createCGImage(ci, from: ci.extent) else { return self }
        return UIImage(cgImage: out, scale: scale, orientation: imageOrientation)
    }
}
