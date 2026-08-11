import Foundation
import Vision
import CoreVideo

/// Real bounding boxes from Vision's built-in detectors.
///
/// The web already has a green-box overlay (`DetectionOverlay.tsx`) fed by
/// `src/mlDetect.ts` — but that file says of itself: "ML detection, simulated…
/// nothing here claims to recognise what is actually in front of the lens." It
/// clusters a frame-difference map and labels the blobs from a plausible list.
/// Fine as a browser stand-in; not something to paint over a live lens on the
/// phone, where it reads as a claim about what the camera can see.
///
/// So the boxes come from Vision instead. These requests genuinely locate what
/// they name:
///   • VNDetectHumanRectanglesRequest — people
///   • VNRecognizeAnimalsRequest      — cats and dogs, with the species label
///   • VNDetectRectanglesRequest      — screens, signs, cards, posters
///   • VNDetectBarcodesRequest        — codes, with their payload
/// Faces stay with UserRecognitionManager, which resolves them to Poplur users.
///
/// The trade is honest and worth stating: Vision has no GENERAL object
/// detector, so a coffee cup gets no box. The whole-image classifier
/// (`VNClassifyImageRequest`, already running) still names the scene above.
/// Boxes for arbitrary objects need a CoreML detection model in the bundle;
/// there is none in this project.
final class VisionBoxDetector {

    /// One box, in Vision's normalised space converted to the web's convention.
    struct Box {
        let id: String
        let x: CGFloat      // 0..1, origin TOP-left (Vision reports bottom-left)
        let y: CGFloat
        let w: CGFloat
        let h: CGFloat
        let label: String
        let confidence: Float
    }

    /// CameraKitController now chooses this detector's round-robin frame at
    /// roughly 1 Hz. Keep this local gate at one so the controller cadence is
    /// not multiplied by another twelve; `isProcessing` remains the hard
    /// backpressure guard if a Vision request outlives its allotted window.
    var frameSkipInterval = 1

    private var frameCount = 0
    private var isProcessing = false
    private let queue = DispatchQueue(label: "com.apptist.poplur.visionboxes", qos: .userInitiated)

    /// Called on the main actor with the current boxes (possibly empty).
    var onBoxes: (([Box]) -> Void)?

    /// Returns false when this frame was not accepted. An accepted request
    /// always delivers `onBoxes` exactly once, including Vision failures, so a
    /// caller can safely use that callback as completion ownership.
    @discardableResult
    func process(pixelBuffer: CVPixelBuffer) -> Bool {
        frameCount += 1
        guard frameCount % frameSkipInterval == 0 else { return false }
        guard !isProcessing else { return false }
        isProcessing = true

        queue.async { [weak self] in
            guard let self else { return }
            defer { self.isProcessing = false }

            // CameraKitController rotates the AVCaptureVideoDataOutput
            // connection into portrait before this buffer is emitted.
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            let humans = VNDetectHumanRectanglesRequest()
            let animals = VNRecognizeAnimalsRequest()
            let rectangles = VNDetectRectanglesRequest()
            rectangles.minimumConfidence = 0.6
            rectangles.maximumObservations = 4
            let barcodes = VNDetectBarcodesRequest()

            do {
                try handler.perform([humans, animals, rectangles, barcodes])
            } catch {
                DispatchQueue.main.async { self.onBoxes?([]) }
                return
            }

            var boxes: [Box] = []
            var index = 0
            func add(_ bb: CGRect, _ label: String, _ confidence: Float) {
                // Vision's origin is BOTTOM-left; the overlay positions with CSS
                // top/left. Flipping y here keeps that conversion in one place.
                boxes.append(Box(
                    id: "\(label)-\(index)",
                    x: bb.origin.x,
                    y: 1 - bb.origin.y - bb.height,
                    w: bb.width,
                    h: bb.height,
                    label: label,
                    confidence: confidence
                ))
                index += 1
            }

            for o in (humans.results ?? []) { add(o.boundingBox, "person", o.confidence) }
            for o in (animals.results ?? []) {
                let name = o.labels.first?.identifier ?? "animal"
                add(o.boundingBox, name, o.labels.first?.confidence ?? o.confidence)
            }
            for o in (barcodes.results ?? []) {
                add(o.boundingBox, o.symbology.rawValue.replacingOccurrences(of: "VNBarcodeSymbology", with: ""), o.confidence)
            }
            // Rectangles are the noisiest and least meaningful of the four, so
            // they only fill space the others left — a screen behind a person
            // should not compete with the person.
            if boxes.count < 3 {
                for o in (rectangles.results ?? []).prefix(3 - boxes.count) {
                    add(o.boundingBox, "screen", o.confidence)
                }
            }

            let result = boxes
            DispatchQueue.main.async { self.onBoxes?(result) }
        }
        return true
    }
}
