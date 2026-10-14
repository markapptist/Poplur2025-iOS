//
//  ARFilterManager.swift
//  AR Face Filters and Effects
//

import Foundation
import CoreImage
@preconcurrency import Vision
#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

/// Manages AR face filters and effects
@MainActor
class ARFilterManager: NSObject, ObservableObject {

    /// A compact, frame-normalized landmark payload for the transparent web
    /// accessory layer. Vision owns the full mesh; the bridge needs only the
    /// feature centres that materially improve Poplur's filter anchors.
    struct FaceLandmarkTrack {
        let leftEye: CGPoint?
        let rightEye: CGPoint?
        let nose: CGPoint?
    }
    
    // MARK: - Published Properties
    
    /// Currently active filter
    @Published var activeFilter: ARFilter = .none {
        didSet {
            // The render path runs per-frame on the camera's output queue and
            // must never hop to the main actor just to learn which filter is
            // live — that hop per frame is what made the old pipeline
            // serialize on main. Mirror the value under a lock instead.
            filterStateLock.lock()
            filterSnapshot = activeFilter
            filterStateLock.unlock()
        }
    }
    
    /// Whether AR session is running
    @Published var isARActive: Bool = false
    
    /// Available filters
    /// The nine with bundled artwork. NOT `allCases` any more: the fifteen web
    /// ids have no `ar_filter_*` thumbnail, so listing them here would put
    /// blank tiles in ARFilterSelector and the video-call rail.
    @Published var availableFilters: [ARFilter] = ARFilter.nativePickerFilters
    
    // MARK: - Private Properties
    
    /// CIContext is documented thread-safe; the whole render path runs off the
    /// main actor, so the context lives outside it too.
    private nonisolated(unsafe) let ciContext = CIContext()
    /// Reuses the Vision pass already required by the native filter pipeline to
    /// anchor the transparent WebGL accessory layer. No second face detector.
    var onFaceTrack: ((CGRect?, Float, CGFloat, CGFloat, FaceLandmarkTrack?) -> Void)?
    private var lastFaceTrackPublishTime: TimeInterval = 0

    // ── Cross-queue state for the per-frame render path ─────────────────────
    // Everything below is written on the main actor (or the render queue) and
    // read per-frame on the camera's output queue, guarded by one lock. The
    // old pipeline instead bounced every frame through DispatchQueue.main and
    // a MainActor Task, which both janked the UI and capped the filtered
    // viewfinder at the analysis lane's 2fps.
    private nonisolated(unsafe) let filterStateLock = NSLock()
    private nonisolated(unsafe) var filterSnapshot: ARFilter = .none
    /// The last face Vision gave us, reused between detection passes. A face
    /// moves slowly relative to 30fps video, so compositing against a reading
    /// up to a few hundred ms old is invisible — while running landmarks on
    /// EVERY frame was the single largest cost of the old pipeline.
    private nonisolated(unsafe) var cachedFaceObservation: VNFaceObservation?
    private nonisolated(unsafe) var cachedFaceAt: TimeInterval = 0
    /// One Vision pass at a time; frames that arrive while one runs reuse the
    /// cache instead of stacking requests on the Neural Engine.
    private nonisolated(unsafe) var faceDetectInFlight = false
    /// Output buffers come from a pool sized to the current frame, not from
    /// CVPixelBufferCreate per frame — allocation churn at display rate is a
    /// real cost on 4K-capable sensors.
    private nonisolated(unsafe) var outputBufferPool: CVPixelBufferPool?
    private nonisolated(unsafe) var outputBufferPoolSize: CGSize = .zero

    /// How stale the cached face may get before the next frame pays for a
    /// fresh landmarks pass. 0.35s ≈ 3Hz, and that IS the delivered rate: the
    /// only call site of publishFaceTrack is inside refreshFaceCacheIfStale,
    /// so its own 12Hz guard can never bind against arrivals this far apart.
    /// Reading "12Hz max" off this comment is what hid a visibly stepping
    /// accessory. The overlay eases between these poses on its side
    /// (easePose, in the web faceARLandmarks module); without that easing,
    /// 3Hz reads to a user as the filter being slow.
    private nonisolated static let faceRefreshInterval: TimeInterval = 0.35

    // Filter intensity (0.0 - 1.0). Written rarely from the main actor, read
    // per-frame on the render queue; an aligned Float load/store is atomic on
    // arm64, and a momentarily stale intensity is harmless.
    private nonisolated(unsafe) var filterIntensity: Float = 0.7
    
    // MARK: - AR Filters
    
    /// A whole-frame colour recipe: the Core Image twin of one CSS `filter`
    /// chain. Defaults are the identity, so a recipe names only what it changes.
    struct Grade: Decodable {
        /// CSS `brightness()` — a multiplier, carried here and converted to an
        /// exposure stop at apply time.
        var brightness: Double = 1
        var contrast: Double = 1
        /// CSS `saturate()`. 0 is `grayscale(1)`.
        var saturation: Double = 1
        var hueDegrees: Double = 0
        var sepia: Double = 0
        /// CSS `blur()`, in points at the web's reference size.
        var blur: Double = 0
        /// Stands in for the web's `drop-shadow` glows, which on an opaque
        /// video frame read as bloom rather than as a cast shadow.
        var bloom: Double = 0
        /// Red/cyan channel separation, in points at the web's reference size.
        /// The one effect CSS genuinely cannot do to an opaque video — a
        /// `drop-shadow` falls entirely BEHIND a frame that has no alpha — so
        /// the web chain expresses it as two shadows that never actually draw.
        /// Core Image can offset the channels for real, so here it is real.
        var anaglyph: Double = 0
    }

    /// A grade supplied by the web for the CURRENT pick.
    ///
    /// The filter library is streamed (see the clay map's arFilterCatalog),
    /// so the set can grow between app releases. When the web sends a recipe
    /// with the pick, that recipe wins; the compiled-in table below is the
    /// fallback for a pick that arrives without one. This is what lets a
    /// filter published today work on a binary shipped last month.
    private nonisolated(unsafe) var streamedGrade: Grade?

    /// Called from the bridge before `activeFilter` is set.
    nonisolated func setStreamedGrade(_ grade: Grade?) {
        filterStateLock.lock()
        streamedGrade = grade
        filterStateLock.unlock()
    }

    /// The recipe for this pick: the streamed one when the web sent it, else
    /// the compiled-in table. Read on the render queue, so it takes the same
    /// lock as every other piece of cross-queue filter state here.
    private nonisolated func currentGrade(for filter: ARFilter) -> Grade? {
        filterStateLock.lock()
        let streamed = streamedGrade
        filterStateLock.unlock()
        return streamed ?? filter.grade
    }

    enum ARFilter: String, CaseIterable, Identifiable {
        case none = "None"
        case faceSmoothing = "Smooth"
        case beautyFilter = "Beauty"
        case brightening = "Brighten"
        case glowingSkin = "Glow"
        case sharpen = "Sharpen"
        case warmth = "Warm"
        case cool = "Cool"
        case vintage = "Vintage"

        // ── The web rail's fifteen ────────────────────────────────────────
        // The rail in ARFilters.tsx was rebuilt from the filter sheet and its
        // ids replaced the nine above wholesale. Nothing here learned them, and
        // WebHomeCameraLayer resolves the web's id against `rawValue` — so
        // `none`/`None` was the ONLY pair that ever matched and every real
        // selection resolved to `.none`. Picking a filter told the native
        // pipeline "no filter", which also posted isShown:false and kept the
        // filtered display layer from ever cross-fading in. That is the whole
        // reason the rail did nothing on a device.
        //
        // These carry the COLOUR GRADE only — the same recipe the web applies
        // as a CSS `filter`, translated to Core Image in `grade` below. The
        // seven head-worn ones have no costume here on purpose: their artwork
        // does not exist, and inventing it is not this fix's job. The three
        // that DO have costumes (puppy-love, butterfly-dream, inferno-eyes)
        // draw them in the web overlay, which on iOS is a transparent WebView
        // sitting on top of this preview — so they land without native work.
        //
        // Deliberately ADDED rather than replacing the nine: ARFilterSelector
        // and InAppVideoCallView show the legacy set with real bundled
        // `ar_filter_*` thumbnails, and these have none. `availableFilters`
        // stays the native nine so those pickers are unchanged.
        case webSmoothGlow = "smooth-glow"
        case webPop3D = "pop-3d"
        case webPuppyLove = "puppy-love"
        case webRetroVHS = "retro-vhs"
        case webChromeShine = "chrome-shine"
        case webButterflyDream = "butterfly-dream"
        case webComicPop = "comic-pop"
        case webInfernoEyes = "inferno-eyes"
        case webHeartCrown = "heart-crown"
        case webFisheyeFun = "fisheye-fun"
        case webOilSlick = "oil-slick"
        case webStarryNight = "starry-night"
        case webDinoHood = "dino-hood"
        case webAngel = "angel"
        case webFlowerCrown = "flower-crown"

        /// A filter that exists only in the STREAMED catalog — published after
        /// this binary was built, so there is no case for it here.
        ///
        /// Without this, streaming was a half-measure that looked complete: an
        /// unknown id resolved to `.none`, and both render entry points return
        /// the frame untouched on `.none` BEFORE any grade is consulted, so the
        /// recipe arrived and was never used. The whole point of the catalog is
        /// that a filter published today works on a phone built last month; a
        /// pick with a grade but no matching case lands here instead, and every
        /// `!= .none` test downstream — including the one that decides whether
        /// frames are delivered at all — treats it as the real filter it is.
        /// Its recipe comes from `setStreamedGrade`; `grade` is nil by design.
        case streamed = "__streamed"

        /// "smooth-glow" -> "Smooth Glow". The rail owns the real captions;
        /// this is only for logs and accessibility on the native side.
        static func labelFromID(_ id: String) -> String {
            id.split(separator: "-").map(\.capitalized).joined(separator: " ")
        }

        /// The nine with bundled artwork and a native picker entry. The web
        /// cases above are reachable only by id, over the bridge.
        static var nativePickerFilters: [ARFilter] {
            [.none, .faceSmoothing, .beautyFilter, .brightening,
             .glowingSkin, .sharpen, .warmth, .cool, .vintage]
        }

        /// A whole-frame colour recipe, mirroring the web's CSS `filter` chain
        /// for the same id. `nil` means "one of the legacy nine", which grades
        /// only the face oval through compositeFaceEffect instead.
        ///
        /// CSS multiplies brightness; CIColorControls ADDS it, so brightness
        /// travels as an exposure stop (log2) where it belongs. Everything else
        /// maps across directly.
        var grade: Grade? {
            switch self {
            case .webSmoothGlow:      return Grade(brightness: 1.07, contrast: 1.05, saturation: 1.06, blur: 1.1, bloom: 0.45)
            // Anaglyph IS the filter. Left as a saturation lift plus a whisper
            // of bloom it measured 1.93/255 mean change against the unfiltered
            // frame — below the threshold anyone notices on a moving
            // viewfinder, i.e. picking Pop 3D looked like picking nothing.
            // `anaglyph` offsets the channels for real.
            case .webPop3D:           return Grade(saturation: 1.1, bloom: 0.2, anaglyph: 3)
            case .webPuppyLove:       return Grade(brightness: 1.08, contrast: 1.02, saturation: 1.14, sepia: 0.1)
            case .webRetroVHS:        return Grade(brightness: 0.96, contrast: 1.18, saturation: 1.45, hueDegrees: -6)
            case .webChromeShine:     return Grade(brightness: 1.12, contrast: 1.55, saturation: 0, bloom: 0.5)
            case .webButterflyDream:  return Grade(brightness: 1.1, contrast: 0.98, saturation: 1.22, hueDegrees: 6)
            case .webComicPop:        return Grade(brightness: 1.04, contrast: 1.85, saturation: 1.7)
            case .webInfernoEyes:     return Grade(brightness: 0.82, contrast: 1.3, saturation: 1.35, hueDegrees: -18, sepia: 0.25)
            case .webHeartCrown:      return Grade(brightness: 1.1, contrast: 1.02, saturation: 1.25, hueDegrees: -8)
            // STAND-IN on both platforms: a real fisheye is a per-pixel barrel
            // warp and needs a geometry pass, not a colour recipe.
            case .webFisheyeFun:      return Grade(brightness: 1.04, contrast: 1.12, saturation: 1.15)
            case .webOilSlick:        return Grade(brightness: 1.05, contrast: 1.25, saturation: 2.2, hueDegrees: 150)
            case .webStarryNight:     return Grade(brightness: 0.72, contrast: 1.2, saturation: 1.3, hueDegrees: 205)
            case .webDinoHood:        return Grade(brightness: 1.04, contrast: 1.05, saturation: 1.2, hueDegrees: -14)
            case .webAngel:           return Grade(brightness: 1.24, contrast: 0.94, saturation: 1.05, blur: 0.6, bloom: 0.6)
            case .webFlowerCrown:     return Grade(brightness: 1.09, contrast: 1.02, saturation: 1.28, sepia: 0.12)
            default:                  return nil
            }
        }

        var id: String { rawValue }

        /// What the rail calls it.
        ///
        /// SEPARATE FROM `rawValue` on purpose. Every one of these draws a
        /// costume on the face further down this file — `.sharpen` is the cyan
        /// visor at `case .sharpen` in the effect pass — so naming them after
        /// the colour grade told you nothing about what you were picking. But
        /// `rawValue` is also the wire value: it goes out in the
        /// `["filter": ...]` notification payload, so renaming the cases would
        /// change a contract to fix a caption. The label moves; the id does not.
        var displayName: String {
            switch self {
            case .none: return "None"
            case .faceSmoothing: return "Smooth"   // genuinely just a grade
            case .beautyFilter: return "Blush"
            case .brightening: return "Ring Light"
            case .glowingSkin: return "Halo"
            case .sharpen: return "Visor"
            case .warmth: return "Freckles"
            case .cool: return "Ice Crown"
            case .vintage: return "Round Specs"
            // The web cases carry their label in the id itself.
            default: return Self.labelFromID(rawValue)
            }
        }

        var icon: String {
            switch self {
            case .none: return "xmark.circle"
            case .faceSmoothing: return "sparkles"
            case .beautyFilter: return "face.smiling"
            case .brightening: return "circle.dashed"
            case .glowingSkin: return "sun.max"
            case .sharpen: return "eyeglasses"
            case .warmth: return "circle.grid.3x3.fill"
            case .cool: return "snowflake"
            case .vintage: return "camera.aperture"
            default: return "camera.filters"
            }
        }

        var thumbnailAsset: String {
            switch self {
            case .none: return "ar_filter_none"
            case .faceSmoothing: return "ar_filter_smooth"
            case .beautyFilter: return "ar_filter_beauty"
            case .brightening: return "ar_filter_brighten"
            case .glowingSkin: return "ar_filter_glow"
            case .sharpen: return "ar_filter_sharpen"
            case .warmth: return "ar_filter_warm"
            case .cool: return "ar_filter_cool"
            case .vintage: return "ar_filter_vintage"
            // Unreachable from a picker — the web cases are excluded from
            // availableFilters precisely because this asset does not exist.
            default: return "ar_filter_none"
            }
        }
        
        var description: String {
            switch self {
            // Lead with the costume, then the grade that comes with it.
            case .none: return "No Filter"
            case .faceSmoothing: return "Smooth skin, reduce wrinkles"
            case .beautyFilter: return "Rosy cheeks and sparkles"
            case .brightening: return "A ring of light around your face"
            case .glowingSkin: return "A golden halo overhead"
            case .sharpen: return "A cyan visor across your eyes"
            case .warmth: return "Freckles and a warm tone"
            case .cool: return "A crown of ice, on a cool tone"
            case .vintage: return "Round specs, on a vintage wash"
            default: return "\(Self.labelFromID(rawValue)) colour grade"
            }
        }
    }
    
    // MARK: - Public Methods
    
    /// Stop the filter session. The filters are Vision face landmarks plus
    /// Core Image on the camera feed; no ARKit/TrueDepth session is ever run
    /// (App Review 2.5.1), so this only clears the state.
    func stopARSession() {
        isARActive = false
    }
    
    /// Apply filter to image. Nonisolated and parameterized by the filter so
    /// the per-frame render can run entirely on the camera's output queue.
    nonisolated func applyFilter(_ filter: ARFilter, to image: CIImage, faceObservation: VNFaceObservation?) -> CIImage? {
        let activeFilter = filter
        guard activeFilter != .none else { return image }

        // A GRADE is a whole-frame colour recipe: Retro VHS, Comic Pop and
        // Starry Night grade the picture, not a face oval, and they must land
        // whether or not anybody is in shot. This used to return early on a
        // missing face — the code below even logs "Frame will remain
        // unchanged" — so the rail did nothing at all unless a face happened to
        // be detected, which is the wrong contract for fourteen of these.
        if let grade = currentGrade(for: activeFilter) {
            return applyGrade(grade, to: image).cropped(to: image.extent)
        }

        // The legacy nine are BEAUTY filters: they grade the face oval only, so
        // they genuinely have nothing to do without an observation.
        guard let faceObservation else { return image }

        var outputImage = image
        
        switch activeFilter {
        case .none:
            return image
            
        case .faceSmoothing:
            outputImage = applySmoothingFilter(to: outputImage)
            
        case .beautyFilter:
            // Combine multiple filters for beauty effect
            outputImage = applySmoothingFilter(to: outputImage)
            outputImage = applyBrighteningFilter(to: outputImage)
            outputImage = applyGlowFilter(to: outputImage)
            
        case .brightening:
            outputImage = applyBrighteningFilter(to: outputImage)
            
        case .glowingSkin:
            outputImage = applyGlowFilter(to: outputImage)
            
        case .sharpen:
            outputImage = applySharpenFilter(to: outputImage)
            
        case .warmth:
            outputImage = applyWarmthFilter(to: outputImage)
            
        case .cool:
            outputImage = applyCoolFilter(to: outputImage)
            
        case .vintage:
            outputImage = applyVintageFilter(to: outputImage)

        default:
            // Every web case returned above through `grade`.
            return image
        }
        
        let faceComposite = compositeFaceEffect(
            original: image,
            filtered: outputImage.cropped(to: image.extent),
            faceObservation: faceObservation
        )
        switch activeFilter {
        case .beautyFilter, .warmth:
            return applyTrackedFaceArtwork(
                filter: activeFilter,
                to: faceComposite,
                faceObservation: faceObservation
            )
        default:
            // Ring light, halo, visor, crown and glasses are real 3D meshes in
            // the transparent shared layer. Drawing these outlines too would
            // leave the old flat sticker underneath the model.
            return faceComposite
        }
    }
    
    /// Set filter intensity
    func setIntensity(_ value: Float) {
        filterIntensity = max(0.0, min(1.0, value))
    }
    
    /// The filter the render path should apply right now, readable from any
    /// queue. `.none` costs one lock round-trip per frame and nothing else.
    nonisolated func currentFilterSnapshot() -> ARFilter {
        filterStateLock.lock()
        defer { filterStateLock.unlock() }
        return filterSnapshot
    }

    /// Bakes the active whole-frame grade into an AVCapture still. Accessory
    /// meshes remain owned by the web capture surface, which composites them
    /// after the native image arrives using the retained Vision landmarks.
    nonisolated func applyActiveGrade(to image: CIImage) -> CIImage? {
        let filter = currentFilterSnapshot()
        guard filter != .none, let grade = currentGrade(for: filter) else {
            return nil
        }
        return applyGrade(grade, to: image).cropped(to: image.extent)
    }

    /// Apply the active filter to a captured video frame. Runs ENTIRELY on the
    /// caller's queue (the camera's video output queue) and completes
    /// synchronously - no main-actor hop, no per-frame Vision.
    ///
    /// The old shape hopped to main to read `activeFilter`, ran a
    /// VNDetectFaceLandmarksRequest on EVERY frame at full sensor resolution,
    /// then rendered Core Image inside a MainActor Task. That is why an active
    /// filter dropped the viewfinder to the 2fps analysis cadence, cooked the
    /// phone, and tripped the 4s analysis watchdog (which silently reset the
    /// filter to .none - "the filters don't do anything"). All fifteen web
    /// filters are whole-frame grades that need no face at all; only the
    /// legacy face-oval nine and the accessory overlay's anchor need Vision,
    /// and a cached observation refreshed at ~3Hz serves both.
    nonisolated func applyFilterToVideoFrame(_ sampleBuffer: CMSampleBuffer, completion: @escaping (CMSampleBuffer?) -> Void) {
        let filter = currentFilterSnapshot()
        guard filter != .none else {
            completion(sampleBuffer)
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            completion(sampleBuffer)
            return
        }

        refreshFaceCacheIfStale(from: pixelBuffer)

        filterStateLock.lock()
        let face = cachedFaceObservation
        filterStateLock.unlock()

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let filteredImage = applyFilter(filter, to: ciImage, faceObservation: face) else {
            completion(sampleBuffer)
            return
        }

        guard let outputPixelBuffer = createPixelBuffer(from: filteredImage) else {
            completion(sampleBuffer)
            return
        }

        var timingInfo = CMSampleTimingInfo()
        CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timingInfo)

        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: outputPixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDesc = formatDescription else {
            completion(sampleBuffer)
            return
        }

        var newSampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: outputPixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timingInfo,
            sampleBufferOut: &newSampleBuffer
        )
        completion(newSampleBuffer)
    }

    /// Refresh the cached face observation when it has gone stale, at most one
    /// Vision pass in flight. Synchronous on the calling (render) queue when it
    /// runs - landmarks at ~3Hz on a background queue is cheap; landmarks at
    /// 30Hz was the burner. Frames between refreshes reuse the cache.
    ///
    /// Landmarks (not bounding-box-only) on purpose: box-only effects looked
    /// like screen stickers and drifted whenever the user turned their head.
    private nonisolated func refreshFaceCacheIfStale(from pixelBuffer: CVPixelBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        filterStateLock.lock()
        let stale = now - cachedFaceAt >= Self.faceRefreshInterval
        let busy = faceDetectInFlight
        if stale && !busy { faceDetectInFlight = true }
        filterStateLock.unlock()
        guard stale, !busy else { return }

        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("[ARFilter] Face detection failed: \(error)")
        }
        let observation = request.results?.first

        filterStateLock.lock()
        cachedFaceObservation = observation
        cachedFaceAt = now
        faceDetectInFlight = false
        filterStateLock.unlock()

        // The accessory overlay's anchor rides the same pass, published from
        // the main actor as before (its own 12Hz throttle still applies).
        Task { @MainActor in
            self.publishFaceTrack(observation)
        }
    }


    private func publishFaceTrack(_ observation: VNFaceObservation?) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFaceTrackPublishTime >= 1.0 / 12.0 else { return }
        lastFaceTrackPublishTime = now
        onFaceTrack?(
            observation?.boundingBox,
            observation?.confidence ?? 0,
            CGFloat(observation?.roll?.doubleValue ?? 0),
            CGFloat(observation?.yaw?.doubleValue ?? 0),
            observation.map(faceLandmarks)
        )
    }

    /// Vision regions are normalized inside the face rectangle. Convert their
    /// centres into full camera-frame coordinates once, while Vision's
    /// coordinate system is still authoritative.
    private func faceLandmarks(_ observation: VNFaceObservation) -> FaceLandmarkTrack {
        func centre(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let region, !region.normalizedPoints.isEmpty else { return nil }
            let total = region.normalizedPoints.reduce(CGPoint.zero) { partial, point in
                CGPoint(x: partial.x + point.x, y: partial.y + point.y)
            }
            let count = CGFloat(region.normalizedPoints.count)
            let bounds = observation.boundingBox
            return CGPoint(
                x: bounds.minX + total.x / count * bounds.width,
                y: bounds.minY + total.y / count * bounds.height
            )
        }

        return FaceLandmarkTrack(
            leftEye: centre(observation.landmarks?.leftEye),
            rightEye: centre(observation.landmarks?.rightEye),
            nose: centre(observation.landmarks?.nose)
        )
    }
    
    /// Create a pixel buffer from CIImage. Buffers come from a pool sized to
    /// the current frame — per-frame CVPixelBufferCreate at display rate was
    /// allocation churn the old 2fps cadence merely hid.
    private nonisolated func createPixelBuffer(from ciImage: CIImage) -> CVPixelBuffer? {
        let extent = ciImage.extent.integral
        guard extent.width > 0, extent.height > 0 else {
            return nil
        }

        let width = Int(extent.width)
        let height = Int(extent.height)

        filterStateLock.lock()
        if outputBufferPool == nil
            || outputBufferPoolSize != CGSize(width: width, height: height) {
            let attributes = [
                kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
                kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!,
                kCVPixelBufferIOSurfacePropertiesKey: [:],
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA
            ] as [CFString: Any]
            var pool: CVPixelBufferPool?
            CVPixelBufferPoolCreate(
                kCFAllocatorDefault,
                // A shallow pool: the display layer holds a frame or two; three
                // covers render-ahead without hoarding 4-channel full-res frames.
                [kCVPixelBufferPoolMinimumBufferCountKey: 3] as CFDictionary,
                attributes as CFDictionary,
                &pool
            )
            outputBufferPool = pool
            outputBufferPoolSize = CGSize(width: width, height: height)
        }
        let currentPool = outputBufferPool
        filterStateLock.unlock()

        guard let currentPool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, currentPool, &pixelBuffer)
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        let normalizedImage = ciImage.transformed(
            by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
        )
        let renderBounds = CGRect(origin: .zero, size: CGSize(width: width, height: height))
        ciContext.render(
            normalizedImage,
            to: buffer,
            bounds: renderBounds,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return buffer
    }
    
    // MARK: - Filter Implementations
    
    /// Smoothing filter to reduce wrinkles and imperfections
    /// Run one `Grade` over the whole frame, in the order a browser applies a
    /// CSS `filter` chain: blur, then colour, then hue, then sepia, then bloom.
    ///
    /// Each step is skipped when it is the identity, so a recipe that only
    /// shifts saturation costs one CIFilter rather than six.
    private nonisolated func applyGrade(_ grade: Grade, to image: CIImage) -> CIImage {
        var output = image
        let extent = image.extent

        // RADII ARE IN CSS PIXELS, PIXELS ARE NOT.
        //
        // Every radius in a Grade was read off the web chain, which styles a
        // video element about 390pt wide on a phone. Core Image runs on the
        // full-resolution sensor buffer — 1080px and up — so feeding the same
        // number straight to CIGaussianBlur made the native soften land about
        // a quarter as strong as the web's: measured mean change against the
        // unfiltered frame, blur(1.1) is 2.08/255 at 390px wide and 0.47/255 at
        // 1080px. Scale the radius with the buffer and the two agree.
        let cssReferenceWidth = 390.0
        let pixelScale = max(1, Double(extent.width) / cssReferenceWidth)

        if grade.blur > 0.01, let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(output, forKey: kCIInputImageKey)
            blur.setValue(grade.blur * pixelScale, forKey: kCIInputRadiusKey)
            // A blur bleeds past the frame; clamp back or the edges go
            // transparent and the preview shows a dark border.
            if let blurred = blur.outputImage { output = blurred.cropped(to: extent) }
        }

        // Red channel left, cyan channels right: the red/cyan-glasses fringe
        // the rail's own Pop 3D tile depicts, and the one thing in this whole
        // set that a colour recipe genuinely cannot express.
        if grade.anaglyph > 0.01 {
            let dx = grade.anaglyph * pixelScale
            let zero = CIVector(x: 0, y: 0, z: 0, w: 0)
            // Clamp before the offset. Sliding a channel copy sideways leaves a
            // strip at each edge where only one channel exists, which renders
            // as a dark band down both sides of the viewfinder.
            let source = output.clampedToExtent()
            let red = source
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputGVector": zero,
                    "inputBVector": zero
                ])
                .transformed(by: CGAffineTransform(translationX: -dx, y: 0))
            let cyan = source
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": zero,
                    "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0)
                ])
                .transformed(by: CGAffineTransform(translationX: dx, y: 0))
            let split = cyan.applyingFilter("CIAdditionCompositing", parameters: [
                kCIInputBackgroundImageKey: red
            ])
            // The offset IS the strength — do not blend the split back over the
            // original. The two halves recombine to the original everywhere
            // they overlap, so a 55/45 mix with the unsplit frame cancels the
            // effect down to nothing outside a hairline at each edge; it
            // measured a mean change of 31/255 that a person could not see.
            //
            // Alpha is written from the BIAS rather than carried through:
            // addition compositing summed two opaque images, so the incoming
            // alpha is 2 in Core Image's unclamped float working space and
            // anything downstream would read as over-bright.
            output = split
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
                ])
                .cropped(to: extent)
        }

        // CSS brightness() is a MULTIPLIER. CIColorControls' brightness is an
        // additive offset, which crushes blacks when used as one — so the
        // multiplier travels as an exposure stop, where it belongs.
        if abs(grade.brightness - 1) > 0.001, let exposure = CIFilter(name: "CIExposureAdjust") {
            exposure.setValue(output, forKey: kCIInputImageKey)
            exposure.setValue(log2(max(0.01, grade.brightness)), forKey: kCIInputEVKey)
            if let adjusted = exposure.outputImage { output = adjusted }
        }

        if abs(grade.contrast - 1) > 0.001 || abs(grade.saturation - 1) > 0.001,
           let controls = CIFilter(name: "CIColorControls") {
            controls.setValue(output, forKey: kCIInputImageKey)
            controls.setValue(grade.contrast, forKey: kCIInputContrastKey)
            controls.setValue(grade.saturation, forKey: kCIInputSaturationKey)
            if let adjusted = controls.outputImage { output = adjusted }
        }

        if abs(grade.hueDegrees) > 0.001, let hue = CIFilter(name: "CIHueAdjust") {
            hue.setValue(output, forKey: kCIInputImageKey)
            hue.setValue(grade.hueDegrees * .pi / 180, forKey: kCIInputAngleKey)
            if let adjusted = hue.outputImage { output = adjusted }
        }

        if grade.sepia > 0.001, let sepia = CIFilter(name: "CISepiaTone") {
            sepia.setValue(output, forKey: kCIInputImageKey)
            sepia.setValue(grade.sepia, forKey: kCIInputIntensityKey)
            if let adjusted = sepia.outputImage { output = adjusted }
        }

        if grade.bloom > 0.001, let bloom = CIFilter(name: "CIBloom") {
            bloom.setValue(output, forKey: kCIInputImageKey)
            bloom.setValue(grade.bloom, forKey: kCIInputIntensityKey)
            // Same CSS-pixel problem as the blur above: a fixed radius of 8 is
            // the web's glow on a 390pt video and a hairline on a 1080px frame.
            bloom.setValue(8.0 * pixelScale, forKey: kCIInputRadiusKey)
            if let bloomed = bloom.outputImage { output = bloomed.cropped(to: extent) }
        }

        return output
    }

    private nonisolated func applySmoothingFilter(to image: CIImage) -> CIImage {
        // Use bilateral filter for edge-preserving smoothing
        guard let smoothingFilter = CIFilter(name: "CIMedianFilter") else {
            return image
        }
        
        smoothingFilter.setValue(image, forKey: kCIInputImageKey)
        
        guard let smoothed = smoothingFilter.outputImage else {
            return image
        }
        
        return smoothed
    }
    
    /// Brightening filter for face
    private nonisolated func applyBrighteningFilter(to image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else {
            return image
        }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(NSNumber(value: 1.0 + (0.2 * filterIntensity)), forKey: kCIInputBrightnessKey)
        filter.setValue(NSNumber(value: 1.0 + (0.1 * filterIntensity)), forKey: kCIInputContrastKey)
        
        return filter.outputImage ?? image
    }
    
    /// Glow filter for radiant skin
    private nonisolated func applyGlowFilter(to image: CIImage) -> CIImage {
        guard let bloomFilter = CIFilter(name: "CIBloom") else {
            return image
        }
        
        bloomFilter.setValue(image, forKey: kCIInputImageKey)
        bloomFilter.setValue(NSNumber(value: 0.3 * filterIntensity), forKey: kCIInputIntensityKey)
        bloomFilter.setValue(NSNumber(value: 10.0), forKey: kCIInputRadiusKey)
        
        guard let bloom = bloomFilter.outputImage else {
            return image
        }
        
        // Blend with original
        guard let blendFilter = CIFilter(name: "CISourceOverCompositing") else {
            return bloom
        }
        
        blendFilter.setValue(bloom, forKey: kCIInputImageKey)
        blendFilter.setValue(image, forKey: kCIInputBackgroundImageKey)
        
        return blendFilter.outputImage ?? image
    }
    
    /// Sharpen filter
    private nonisolated func applySharpenFilter(to image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CISharpenLuminance") else {
            return image
        }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(NSNumber(value: 0.8 * filterIntensity), forKey: kCIInputSharpnessKey)
        
        return filter.outputImage ?? image
    }
    
    /// Warmth filter (orange/golden tones)
    private nonisolated func applyWarmthFilter(to image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CITemperatureAndTint") else {
            return image
        }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: 6500 + (1000 * CGFloat(filterIntensity)), y: 0), forKey: "inputNeutral")
        filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
        
        return filter.outputImage ?? image
    }
    
    /// Cool filter (blue tones)
    private nonisolated func applyCoolFilter(to image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CITemperatureAndTint") else {
            return image
        }
        
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: 6500 - (1000 * CGFloat(filterIntensity)), y: 0), forKey: "inputNeutral")
        filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputTargetNeutral")
        
        return filter.outputImage ?? image
    }
    
    /// Vintage filter
    private nonisolated func applyVintageFilter(to image: CIImage) -> CIImage {
        guard let sepiaFilter = CIFilter(name: "CISepiaTone") else {
            return image
        }
        
        sepiaFilter.setValue(image, forKey: kCIInputImageKey)
        sepiaFilter.setValue(NSNumber(value: 0.7 * filterIntensity), forKey: kCIInputIntensityKey)
        
        guard let sepia = sepiaFilter.outputImage else {
            return image
        }
        
        // Add vignette
        guard let vignetteFilter = CIFilter(name: "CIVignette") else {
            return sepia
        }
        
        vignetteFilter.setValue(sepia, forKey: kCIInputImageKey)
        vignetteFilter.setValue(NSNumber(value: 1.5 * filterIntensity), forKey: kCIInputIntensityKey)
        vignetteFilter.setValue(NSNumber(value: 2.0), forKey: kCIInputRadiusKey)
        
        return vignetteFilter.outputImage ?? sepia
    }
    
    // MARK: - Helper Methods
    
    private nonisolated func compositeFaceEffect(
        original: CIImage,
        filtered: CIImage,
        faceObservation: VNFaceObservation
    ) -> CIImage {
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else { return original }

        blendFilter.setValue(filtered, forKey: kCIInputImageKey)
        blendFilter.setValue(original, forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(
            createFaceMask(from: faceObservation, imageExtent: original.extent),
            forKey: kCIInputMaskImageKey
        )

        return (blendFilter.outputImage ?? original).cropped(to: original.extent)
    }

    /// Create a soft mask around the detected face region.
    private nonisolated func createFaceMask(from observation: VNFaceObservation, imageExtent: CGRect) -> CIImage {
        let bounds = observation.boundingBox
        
        // Vision and Core Image both use lower-left image coordinates.
        let x = imageExtent.minX + bounds.origin.x * imageExtent.width
        let y = imageExtent.minY + bounds.origin.y * imageExtent.height
        let width = bounds.width * imageExtent.width
        let height = bounds.height * imageExtent.height
        
        let faceRect = CGRect(x: x, y: y, width: width, height: height)
            .insetBy(dx: -width * 0.18, dy: -height * 0.22)
        
        // Create a radial gradient mask centered on face
        let centerX = faceRect.midX
        let centerY = faceRect.midY
        let radius = max(faceRect.width, faceRect.height) * 0.58
        
        guard let gradientFilter = CIFilter(name: "CIRadialGradient") else {
            return CIImage(color: CIColor.clear).cropped(to: imageExtent)
        }
        
        gradientFilter.setValue(CIVector(x: centerX, y: centerY), forKey: "inputCenter")
        gradientFilter.setValue(NSNumber(value: radius * 0.5), forKey: "inputRadius0")
        gradientFilter.setValue(NSNumber(value: radius * 1.2), forKey: "inputRadius1")
        gradientFilter.setValue(CIColor.white, forKey: "inputColor0")
        gradientFilter.setValue(CIColor.black, forKey: "inputColor1")
        
        let mask = gradientFilter.outputImage?.cropped(to: imageExtent)
        return mask ?? CIImage(color: CIColor.clear).cropped(to: imageExtent)
    }

    // MARK: - Face-anchored AR artwork

    private nonisolated func applyTrackedFaceArtwork(
        filter: ARFilter,
        to image: CIImage,
        faceObservation: VNFaceObservation
    ) -> CIImage {
        guard filter != .none && filter != .faceSmoothing else { return image }

        let face = faceRect(for: faceObservation, imageExtent: image.extent)
        guard face.width > 1, face.height > 1 else { return image }
        let eyeLine = trackedEyeLine(for: faceObservation, faceRect: face)
        var output = image

        switch filter {
        case .none, .faceSmoothing:
            break

        case .beautyFilter:
            let cheekSize = face.width * 0.16
            output = sourceOver(
                softDot(center: CGPoint(x: face.minX + face.width * 0.25, y: face.minY + face.height * 0.42), radius: cheekSize, color: CIColor(red: 1, green: 0.18, blue: 0.48, alpha: 0.30), extent: image.extent),
                output
            )
            output = sourceOver(
                softDot(center: CGPoint(x: face.maxX - face.width * 0.25, y: face.minY + face.height * 0.42), radius: cheekSize, color: CIColor(red: 1, green: 0.18, blue: 0.48, alpha: 0.30), extent: image.extent),
                output
            )
        case .brightening:
            output = addRoundedOutline(
                rect: face.insetBy(dx: -face.width * 0.08, dy: -face.height * 0.08),
                width: max(3, face.width * 0.018),
                color: CIColor(red: 1, green: 0.93, blue: 0.55, alpha: 0.86),
                to: output
            )

        case .glowingSkin:
            let halo = CGRect(
                x: face.minX + face.width * 0.12,
                y: face.maxY + face.height * 0.08,
                width: face.width * 0.76,
                height: face.height * 0.13
            )
            output = addRoundedOutline(
                rect: halo,
                width: max(4, face.width * 0.025),
                color: CIColor(red: 1, green: 0.77, blue: 0.18, alpha: 0.95),
                to: output
            )
            output = addSparkles(to: output, around: face)

        case .sharpen:
            let visor = CGRect(
                x: face.minX - face.width * 0.03,
                y: eyeLine.y - face.height * 0.11,
                width: face.width * 1.06,
                height: face.height * 0.24
            )
            output = sourceOver(
                roundedRect(visor, radius: visor.height * 0.34, color: CIColor(red: 0.05, green: 0.85, blue: 1, alpha: 0.30), extent: image.extent),
                output
            )
            output = addRoundedOutline(
                rect: visor,
                width: max(3, face.width * 0.018),
                color: CIColor(red: 0.23, green: 0.95, blue: 1, alpha: 0.95),
                to: output
            )
            let bridge = CGRect(x: eyeLine.x - face.width * 0.012, y: visor.minY, width: face.width * 0.024, height: visor.height)
            output = sourceOver(roundedRect(bridge, radius: bridge.width * 0.5, color: CIColor(red: 0.8, green: 1, blue: 1, alpha: 0.8), extent: image.extent), output)

        case .warmth:
            let y = face.minY + face.height * 0.48
            for index in 0..<7 {
                let offset = CGFloat(index - 3) * face.width * 0.055
                let stagger = CGFloat(abs(index - 3)) * face.height * 0.012
                let center = CGPoint(x: face.midX + offset, y: y - stagger)
                output = sourceOver(
                    softDot(center: center, radius: face.width * 0.013, color: CIColor(red: 0.42, green: 0.16, blue: 0.06, alpha: 0.84), extent: image.extent),
                    output
                )
            }

        case .cool:
            let baseY = face.maxY + face.height * 0.01
            let heights: [CGFloat] = [0.16, 0.23, 0.31, 0.23, 0.16]
            for (index, heightScale) in heights.enumerated() {
                let crystalWidth = face.width * 0.12
                let crystalHeight = face.height * heightScale
                let crystal = CGRect(
                    x: face.minX + face.width * (0.16 + CGFloat(index) * 0.13),
                    y: baseY,
                    width: crystalWidth,
                    height: crystalHeight
                )
                output = sourceOver(
                    roundedRect(crystal, radius: crystalWidth * 0.28, color: CIColor(red: 0.35, green: 0.82, blue: 1, alpha: 0.86), extent: image.extent),
                    output
                )
            }

        case .vintage:
            let lensSize = CGSize(width: face.width * 0.42, height: face.height * 0.25)
            let left = CGRect(x: eyeLine.left.x - lensSize.width * 0.5, y: eyeLine.left.y - lensSize.height * 0.5, width: lensSize.width, height: lensSize.height)
            let right = CGRect(x: eyeLine.right.x - lensSize.width * 0.5, y: eyeLine.right.y - lensSize.height * 0.5, width: lensSize.width, height: lensSize.height)
            let frameColor = CIColor(red: 0.08, green: 0.035, blue: 0.02, alpha: 0.96)
            output = addRoundedOutline(rect: left, width: max(5, face.width * 0.035), color: frameColor, to: output)
            output = addRoundedOutline(rect: right, width: max(5, face.width * 0.035), color: frameColor, to: output)
            let bridge = CGRect(x: left.maxX, y: eyeLine.y - face.height * 0.015, width: max(1, right.minX - left.maxX), height: max(5, face.height * 0.03))
            output = sourceOver(roundedRect(bridge, radius: bridge.height * 0.5, color: frameColor, extent: image.extent), output)

        default:
            // The web cases have no native costume — that artwork does not
            // exist and is not invented here. Their three that DO have one
            // (puppy-love, butterfly-dream, inferno-eyes) draw it in the web
            // overlay, which on iOS is a transparent WebView over this preview,
            // so it lands on top without a native pass. They also never reach
            // this function: applyFilter returns them at the grade.
            break
        }

        return output.cropped(to: image.extent)
    }

    private nonisolated func faceRect(for observation: VNFaceObservation, imageExtent: CGRect) -> CGRect {
        CGRect(
            x: imageExtent.minX + observation.boundingBox.minX * imageExtent.width,
            y: imageExtent.minY + observation.boundingBox.minY * imageExtent.height,
            width: observation.boundingBox.width * imageExtent.width,
            height: observation.boundingBox.height * imageExtent.height
        )
    }

    private nonisolated func trackedEyeLine(for observation: VNFaceObservation, faceRect: CGRect) -> (left: CGPoint, right: CGPoint, x: CGFloat, y: CGFloat) {
        func center(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
            guard let region, !region.normalizedPoints.isEmpty else { return nil }
            let average = region.normalizedPoints.reduce(CGPoint.zero) { partial, point in
                CGPoint(x: partial.x + point.x, y: partial.y + point.y)
            }
            let count = CGFloat(region.normalizedPoints.count)
            return CGPoint(
                x: faceRect.minX + average.x / count * faceRect.width,
                y: faceRect.minY + average.y / count * faceRect.height
            )
        }

        let left = center(observation.landmarks?.leftEye)
            ?? CGPoint(x: faceRect.minX + faceRect.width * 0.32, y: faceRect.minY + faceRect.height * 0.62)
        let right = center(observation.landmarks?.rightEye)
            ?? CGPoint(x: faceRect.minX + faceRect.width * 0.68, y: faceRect.minY + faceRect.height * 0.62)
        return (left, right, (left.x + right.x) * 0.5, (left.y + right.y) * 0.5)
    }

    private nonisolated func sourceOver(_ overlay: CIImage, _ background: CIImage) -> CIImage {
        overlay.composited(over: background)
    }

    private nonisolated func roundedRect(_ rect: CGRect, radius: CGFloat, color: CIColor, extent: CGRect) -> CIImage {
        guard let generator = CIFilter(name: "CIRoundedRectangleGenerator") else {
            return CIImage(color: color).cropped(to: rect)
        }
        generator.setValue(CIVector(cgRect: rect), forKey: "inputExtent")
        generator.setValue(radius, forKey: "inputRadius")
        generator.setValue(color, forKey: "inputColor")
        return (generator.outputImage ?? CIImage(color: color).cropped(to: rect)).cropped(to: extent)
    }

    private nonisolated func addRoundedOutline(rect: CGRect, width: CGFloat, color: CIColor, to image: CIImage) -> CIImage {
        let outer = roundedRect(rect, radius: min(rect.width, rect.height) * 0.48, color: color, extent: image.extent)
        let withOuter = sourceOver(outer, image)
        let innerRect = rect.insetBy(dx: width, dy: width)
        guard innerRect.width > 0, innerRect.height > 0 else { return withOuter }
        return sourceOver(image.cropped(to: innerRect), withOuter)
    }

    private nonisolated func softDot(center: CGPoint, radius: CGFloat, color: CIColor, extent: CGRect) -> CIImage {
        guard let gradient = CIFilter(name: "CIRadialGradient") else {
            return CIImage(color: color).cropped(to: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        }
        gradient.setValue(CIVector(cgPoint: center), forKey: "inputCenter")
        gradient.setValue(radius * 0.35, forKey: "inputRadius0")
        gradient.setValue(radius, forKey: "inputRadius1")
        gradient.setValue(color, forKey: "inputColor0")
        gradient.setValue(CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0), forKey: "inputColor1")
        return (gradient.outputImage ?? CIImage.empty()).cropped(to: extent)
    }

    private nonisolated func addSparkles(to image: CIImage, around face: CGRect) -> CIImage {
        let points = [
            CGPoint(x: face.minX - face.width * 0.03, y: face.maxY - face.height * 0.18),
            CGPoint(x: face.maxX + face.width * 0.03, y: face.minY + face.height * 0.58),
            CGPoint(x: face.minX + face.width * 0.12, y: face.minY + face.height * 0.12)
        ]
        return points.reduce(image) { output, point in
            let size = face.width * 0.045
            let vertical = CGRect(x: point.x - size * 0.18, y: point.y - size, width: size * 0.36, height: size * 2)
            let horizontal = CGRect(x: point.x - size, y: point.y - size * 0.18, width: size * 2, height: size * 0.36)
            let color = CIColor(red: 1, green: 0.95, blue: 1, alpha: 0.94)
            let first = sourceOver(roundedRect(vertical, radius: size * 0.18, color: color, extent: image.extent), output)
            return sourceOver(roundedRect(horizontal, radius: size * 0.18, color: color, extent: image.extent), first)
        }
    }
    
    // MARK: - Additional Public Methods
    
    /// Set a simple live tint filter color for demo
    public func setLiveTint(color: CIColor?) {
        // When a color is provided, switch to vintage as base and adjust warmth/cool accordingly
        if let color = color {
            // Simple mapping: warm if red > blue, cool otherwise
            if color.red > color.blue {
                self.activeFilter = .warmth
            } else {
                self.activeFilter = .cool
            }
        } else {
            self.activeFilter = .none
        }
    }
}
