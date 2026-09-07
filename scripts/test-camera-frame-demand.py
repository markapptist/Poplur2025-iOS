#!/usr/bin/env python3
"""Exercise the controller's real delivery methods with capture-output doubles.

No camera permission or simulator hardware is needed. This isolates the native
connection/delegate lifecycle; device preview and thermal tests remain separate.
"""
from pathlib import Path
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "Poplur2025/CameraKitController.swift"
text = source.read_text()

def method(name):
    start = text.index("    func " + name) if "    func " + name in text else text.index("    private func " + name)
    brace = text.index("{", start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end].replace("private func", "func", 1)

swift = r'''
import Foundation
enum MediaType { case video }
final class Connection { var isEnabled = false; var isActive = true }
final class Output {
    let port = Connection()
    var delegateAttached = false
    func connection(with: MediaType) -> Connection? { port }
    func setSampleBufferDelegate(_ delegate: AnyObject?, queue: DispatchQueue?) { delegateAttached = delegate != nil }
}
final class Queue { func async(execute work: () -> Void) { work() } }
final class Session { var isRunning = true; var outputs = [1] }
enum PoplurDiagLog { static func append(_ message: String) {} }
final class Controller {
    var videoDataOutput: Output? = Output()
    var wantsVideoFrameDelivery = false
    var isVideoFrameDelegateAttached = false
    var nextAnalysisSampleWorkItem: DispatchWorkItem?
    let analysisFrameGateLock = NSLock()
    var analysisFrameGateOpen = false
    let frameProcessingLock = NSLock()
    var frameProcessingAllowed = true
    var captureDesired = true
    var filterWanted = false
    let sessionQueue = Queue()
    let videoOutputQueue = DispatchQueue(label: "camera-demand-test")
    let captureSession = Session()
    func isARFilterProcessingWanted() -> Bool { filterWanted }
    func isCaptureDesired() -> Bool { captureDesired }
    func attachVideoDataOutputOnQueue() { videoDataOutput = Output() }
'''
swift += "\n".join(method(name) for name in ["startVideoFrameDelivery", "stopVideoFrameDelivery", "setVideoFrameDeliveryActiveOnQueue"])
swift += r'''
}
var failures = [String]()
func check(_ condition: Bool, _ message: String) { if !condition { failures.append(message) } }
func delivering(_ c: Controller) -> Bool {
    c.videoDataOutput!.port.isEnabled && c.videoDataOutput!.delegateAttached && c.analysisFrameGateOpen
}
let c = Controller()
c.setVideoFrameDeliveryActiveOnQueue(true)
check(!delivering(c), "plain preview opened a processing output")
c.startVideoFrameDelivery()
check(delivering(c), "Scan did not receive frames")
c.stopVideoFrameDelivery()
check(!delivering(c), "Scan off did not close frame delivery")
for _ in 0..<20 { c.setVideoFrameDeliveryActiveOnQueue(true) }
check(!delivering(c), "policy refresh reactivated a stopped Scan")
c.filterWanted = true
c.setVideoFrameDeliveryActiveOnQueue(true)
check(delivering(c), "Lens did not receive frames")
c.startVideoFrameDelivery()
c.stopVideoFrameDelivery()
check(delivering(c), "turning Scan off starved the active Lens")
c.filterWanted = false
c.setVideoFrameDeliveryActiveOnQueue(true)
check(!delivering(c), "dismissed Lens kept processing plain preview")
c.startVideoFrameDelivery()
c.captureDesired = false
c.setVideoFrameDeliveryActiveOnQueue(true)
check(!delivering(c), "stale activation reopened a hidden camera output")
c.captureDesired = true
c.setVideoFrameDeliveryActiveOnQueue(true)
check(delivering(c), "explicit Scan did not resume after capture returned")
c.setVideoFrameDeliveryActiveOnQueue(false)
check(!delivering(c), "revoked processing lease left frames enabled")
if !failures.isEmpty {
    for failure in failures { print("FAIL: \(failure)") }
    exit(1)
}
print("PASS: Camera Scan/Lens/preview demand and stale-policy lifecycle")
'''
with tempfile.TemporaryDirectory(prefix="poplur-camera-demand-") as directory:
    harness = Path(directory) / "main.swift"
    harness.write_text(swift)
    sys.exit(subprocess.run(["swift", str(harness)]).returncode)
