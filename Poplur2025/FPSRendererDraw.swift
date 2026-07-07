import Foundation
import CoreGraphics
import UIKit

// MARK: - FPSRenderer low-level CG drawing primitives (used by HUD / menu)
//
// These draw directly on the renderer's flipped bitmap context (top-left / y-down),
// so they compose with any active pushZoom transform.

extension FPSRenderer {
    func roundRect(_ x: CGFloat, _ y: CGFloat, _ ww: CGFloat, _ hh: CGFloat, _ radius: CGFloat, fill: UIColor) {
        let path = UIBezierPath(roundedRect: CGRect(x: x, y: y, width: ww, height: hh), cornerRadius: radius)
        ctx.setFillColor(fill.cgColor)
        ctx.addPath(path.cgPath)
        ctx.fillPath()
    }

    func strokeRound(_ x: CGFloat, _ y: CGFloat, _ ww: CGFloat, _ hh: CGFloat, _ radius: CGFloat,
                     color: UIColor, lineWidth: CGFloat) {
        let path = UIBezierPath(roundedRect: CGRect(x: x, y: y, width: ww, height: hh), cornerRadius: radius)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.addPath(path.cgPath)
        ctx.strokePath()
    }

    func fillCircle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: UIColor) {
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    func radialVignette() {
        let W = CGFloat(w), H = CGFloat(h)
        let cs = CGColorSpaceCreateDeviceRGB()
        let colors = [UIColor(white: 0, alpha: 0).cgColor, UIColor(white: 0, alpha: 0.55).cgColor] as CFArray
        guard let grad = CGGradient(colorsSpace: cs, colors: colors, locations: [0.5, 1.0]) else { return }
        ctx.drawRadialGradient(grad,
                               startCenter: CGPoint(x: W / 2, y: H / 2), startRadius: 0,
                               endCenter: CGPoint(x: W / 2, y: H / 2), endRadius: W * 0.7,
                               options: [])
    }

    /// Applies the menu zoom transform (0 = full cabinet, 1 = into the CRT) then
    /// runs `body`. Mirrors Menu.ts's setTransform-based zoom.
    func pushZoom(into L: (cabL: CGFloat, cabTop: CGFloat, cw: CGFloat, ch: CGFloat,
                           marqY: CGFloat, marqH: CGFloat,
                           screenX: CGFloat, screenY: CGFloat, screenW: CGFloat, screenH: CGFloat),
                  t: Double, _ body: () -> Void) {
        let W = CGFloat(w), H = CGFloat(h)
        let scaleTarget = W / L.screenW
        let txTarget = W / 2 - (L.screenX + L.screenW / 2) * scaleTarget
        let tyTarget = H / 2 - (L.screenY + L.screenH / 2) * scaleTarget
        let tt = CGFloat(max(0, min(1, t)))
        let ease = tt < 1 ? tt * tt * (3 - 2 * tt) : 1
        let sc = 1 + (scaleTarget - 1) * ease
        let tx = txTarget * ease
        let ty = tyTarget * ease
        ctx.saveGState()
        ctx.translateBy(x: tx, y: ty)
        ctx.scaleBy(x: sc, y: sc)
        body()
        ctx.restoreGState()
    }
}
