import UIKit
import ARKit
import RealityKit
import ModelIO
import MetalKit
import simd

final class HeadScannerViewController: UIViewController, ARSessionDelegate {
    var onComplete: ((Result<HeadScanOutput, HeadScanError>) -> Void)?

    private let arView = ARView(frame: .zero)
    private var capturedGeometries: [ARFaceGeometry] = []
    private var lastCameraImage: UIImage?
    private var isFinishing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupAR()
        setupUI()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        arView.frame = view.bounds
    }

    private func setupAR() {
        guard ARFaceTrackingConfiguration.isSupported else {
            onComplete?(.failure(.unavailable))
            return
        }
        view.addSubview(arView)
        arView.session.delegate = self

        let config = ARFaceTrackingConfiguration()
        config.isWorldTrackingEnabled = true
        config.providesAudioData = false
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    private func setupUI() {
        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.tintColor = .white
        close.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false

        let done = UIButton(type: .system)
        done.setTitle("Finish", for: .normal)
        done.titleLabel?.font = .boldSystemFont(ofSize: 17)
        done.tintColor = .white
        done.addTarget(self, action: #selector(finishTapped), for: .touchUpInside)
        done.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(close)
        view.addSubview(done)

        NSLayoutConstraint.activate([
            close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            close.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            done.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            done.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
        ])

        let hint = UILabel()
        hint.text = "Slowly turn your head left and right to capture your whole head"
        hint.textColor = .white
        hint.numberOfLines = 0
        hint.textAlignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hint.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            hint.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])
    }

    @objc private func cancelTapped() {
        guard !isFinishing else { return }
        isFinishing = true
        arView.session.pause()
        onComplete?(.failure(.cancelled))
        navigationController?.popViewController(animated: true)
    }

    @objc private func finishTapped() {
        guard !isFinishing else { return }
        isFinishing = true
        arView.session.pause()
        let output = exportUSDZFromCapturedGeometry()
        onComplete?(.success(HeadScanOutput(usdzURL: output, previewImage: lastCameraImage)))
        navigationController?.popViewController(animated: true)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Capture latest camera image for preview
        lastCameraImage = UIImage(pixelBuffer: frame.capturedImage)
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        for anchor in anchors {
            if let faceAnchor = anchor as? ARFaceAnchor {
                capturedGeometries.append(faceAnchor.geometry)
            }
        }
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        for anchor in anchors {
            if let faceAnchor = anchor as? ARFaceAnchor {
                capturedGeometries.append(faceAnchor.geometry)
            }
        }
    }

    private func exportUSDZFromCapturedGeometry() -> URL? {
        guard !capturedGeometries.isEmpty else { return nil }

        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(bufferAllocator: allocator)

        for g in capturedGeometries.prefix(60) { // limit to reduce size
            let mdlMesh = MDLMesh(faceGeometry: g, allocator: allocator)
            asset.add(mdlMesh)
        }

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = docs.appendingPathComponent("HeadScan.usdz")
        do {
            try asset.export(to: url)
            return url
        } catch {
            return nil
        }
    }
}

private extension MDLMesh {
    convenience init(faceGeometry: ARFaceGeometry, allocator: MDLMeshBufferAllocator) {
        let vertexCount = faceGeometry.vertices.count
        let vertexBuffer = allocator.newBuffer(MemoryLayout<SIMD3<Float>>.stride * vertexCount, type: .vertex)
        faceGeometry.vertices.withUnsafeBytes { src in
            let dst = vertexBuffer.map().bytes
            dst.copyMemory(from: src.baseAddress!, byteCount: MemoryLayout<SIMD3<Float>>.stride * vertexCount)
        }
        let indexCount = faceGeometry.triangleCount * 3
        let indexBuffer = allocator.newBuffer(MemoryLayout<UInt16>.stride * indexCount, type: .index)
        faceGeometry.triangleIndices.withUnsafeBytes { src in
            let dst = indexBuffer.map().bytes
            dst.copyMemory(from: src.baseAddress!, byteCount: MemoryLayout<UInt16>.stride * indexCount)
        }
        let submesh = MDLSubmesh(indexBuffer: indexBuffer, indexCount: indexCount, indexType: .uInt16, geometryType: .triangles, material: nil)
        self.init(vertexBuffer: vertexBuffer, vertexCount: vertexCount, descriptor: MDLVertexDescriptor.defaultLayout, submeshes: [submesh])
    }
}

private extension MDLVertexDescriptor {
    static var defaultLayout: MDLVertexDescriptor {
        let d = MDLVertexDescriptor()
        d.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        d.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<SIMD3<Float>>.stride)
        return d
    }
}

private extension UIImage {
    convenience init?(pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        self.init(cgImage: cgImage, scale: UIScreen.main.scale, orientation: .right)
    }
}

// Supporting types for result handling

struct HeadScanOutput {
    let usdzURL: URL?
    let previewImage: UIImage?
}

enum HeadScanError: Error {
    case unavailable
    case cancelled
}
