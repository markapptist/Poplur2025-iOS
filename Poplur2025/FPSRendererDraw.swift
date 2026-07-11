import Foundation
import CoreGraphics
import UIKit

// MARK: - FPSRenderer low-level CG drawing primitives (used by HUD / menu)
//
// These draw directly on the renderer's flipped bitmap context (top-left / y-down).

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

}
