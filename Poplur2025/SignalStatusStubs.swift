import Foundation
import CoreGraphics
import SwiftUI

// MARK: - Temporary stubs to satisfy missing references
// These are project-wide placeholders so the build can proceed.
// Replace with real implementations when integrating the Signal Status UI.

public enum SignalGrid {
    public static var columns: Int { 4 }
    public static var rows: Int { 3 }
}

// Expose simple aliases matching the missing symbol names seen in errors
public var signalColumns: Int { SignalGrid.columns }
public var signalRows: Int { SignalGrid.rows }

// Fractions for a patch inside a status frame (defaults centered small tile)
public var signalPatchLeftFraction: CGFloat { 0.1 }
public var signalPatchTopFraction: CGFloat { 0.1 }
public var signalPatchWidthFraction: CGFloat { 0.8 }
public var signalPatchHeightFraction: CGFloat { 0.8 }

// Simple in-memory frame cache used by status rendering code
public final class SignalStatusFrameCache {
    public static let shared = SignalStatusFrameCache()
    private var cache: [String: CGRect] = [:]
    private let lock = NSLock()

    private init() {}

    public subscript(key: String) -> CGRect? {
        get { lock.lock(); defer { lock.unlock() }; return cache[key] }
        set { lock.lock(); cache[key] = newValue; lock.unlock() }
    }

    public func clear() {
        lock.lock(); cache.removeAll(); lock.unlock()
    }
}

// Alias to match missing identifier name
public var signalStatusFrameCache: SignalStatusFrameCache { .shared }

// MARK: - Utility: nearest rounding helper
public extension BinaryFloatingPoint {
    /// Returns the nearest multiple of `step` to this value. If step <= 0, returns self.
    func nearest(_ step: Self) -> Self {
        guard step > 0 else { return self }
        return (self / step).rounded() * step
    }
}

// MARK: - Notes
// These defaults are intentionally conservative and should be replaced with
// your real layout/math for signal status rendering. They exist to unblock
// compilation when the real module is not present.
